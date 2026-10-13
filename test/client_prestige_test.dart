// Client JSON commun (Réserve, Analyse posologie, Fiche client) : chaque cause d'échec a son type
// (serveur injoignable ≠ session expirée ≠ refus métier ≠ erreur HTTP ≠ réponse illisible), délais bornés,
// cookie de session de l'application envoyé, lecture tolérante des champs.
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/serveur/client_prestige.dart';
import 'package:prestige_vente_app/serveur/json_tolerant.dart';

import 'outils/serveur_json_local.dart';

void main() {
  group('lecture tolérante', () {
    test('entiers, décimaux, booléens, textes et listes de types inattendus', () {
      expect(entier('12'), 12);
      expect(entier(12.0), 12);
      expect(entier('12,0'), 12);
      expect(entier(null), isNull);
      expect(entier('abc'), isNull);
      expect(entier(true), isNull);
      expect(entier0(null), 0);
      expect(decimal('1,25'), 1.25);
      expect(decimal(double.nan), isNull);
      expect(booleen('O'), isTrue);
      expect(booleen(1), isTrue);
      expect(booleen('false'), isFalse);
      expect(booleen(null), isFalse);
      expect(txt(null), '');
      expect(txtOuNull('  '), isNull);
      expect(objets([1, 'x', {'a': 1}]), [
        {'a': 1}
      ]);
      expect(objets('pas une liste'), isEmpty);
      expect(textes(['a', '', null, 3]), ['a', '3']);
    });
  });

  group('erreurs typées contre un serveur local', () {
    late ServeurJsonLocal srv;
    late ClientPrestige client;

    setUp(() async {
      await avecVraiHttp(() async {
        srv = ServeurJsonLocal();
        await srv.demarrer();
      });
      client = ClientPrestige(() => srv.base, delaiConnexion: const Duration(seconds: 2), delaiReponse: const Duration(milliseconds: 400));
    });
    tearDown(() => avecVraiHttp(() => srv.arreter()));

    test('succès : objet JSON rendu, cookie de session de l\'application envoyé', () => avecVraiHttp(() async {
          await DioClient.cookieJar.saveFromResponse(Uri.parse(srv.base), [Cookie('JSESSIONID', 'session-test')]);
          srv.routes['GET /ok'] = (_) => const ReponseLocale({'success': true, 'valeur': 3});
          final j = await client.get('/ok');
          expect(j['valeur'], 3);
          expect(srv.recues.single.cookie, contains('JSESSIONID=session-test'));
          await DioClient.cookieJar.deleteAll();
        }));

    test('HTTP 200 success:false → RefusMetier avec message et code', () => avecVraiHttp(() async {
          srv.routes['PUT /refus'] = (_) => const ReponseLocale({'success': false, 'message': 'Suggestion occupée', 'code': 'SUGGESTION_OCCUPEE'});
          await expectLater(
              client.put('/refus'),
              throwsA(isA<RefusMetier>()
                  .having((e) => e.message, 'message', 'Suggestion occupée')
                  .having((e) => e.code, 'code', 'SUGGESTION_OCCUPEE')));
        }));

    test('HTTP 401 → SessionExpiree et rappel du mécanisme de session ; 200 « Veuillez vous connecter » aussi', () => avecVraiHttp(() async {
          var rappels = 0;
          ClientPrestige.surSessionExpiree = () => rappels++;
          addTearDown(() => ClientPrestige.surSessionExpiree = null);
          srv.routes['GET /a'] = (_) => const ReponseLocale('Veuillez vous connecter', statut: 401);
          srv.routes['GET /b'] = (_) => const ReponseLocale({'success': false, 'msg': 'Veuillez vous connecter'});
          await expectLater(client.get('/a'), throwsA(isA<SessionExpiree>()));
          await expectLater(client.get('/b'), throwsA(isA<SessionExpiree>()));
          expect(rappels, 2);
        }));

    test('HTTP 500 et 404 → ErreurHttp (≠ refus métier)', () => avecVraiHttp(() async {
          srv.routes['GET /panne'] = (_) => const ReponseLocale('boom', statut: 500);
          await expectLater(client.get('/panne'), throwsA(isA<ErreurHttp>().having((e) => e.status, 'status', 500)));
          await expectLater(client.get('/absente'), throwsA(isA<ErreurHttp>().having((e) => e.status, 'status', 404)));
        }));

    test('page HTML ou JSON tronqué → ReponseIllisible', () => avecVraiHttp(() async {
          srv.routes['GET /html'] = (_) => const ReponseLocale('<html>login</html>');
          srv.routes['GET /vide'] = (_) => const ReponseLocale('');
          await expectLater(client.get('/html'), throwsA(isA<ReponseIllisible>()));
          await expectLater(client.get('/vide'), throwsA(isA<ReponseIllisible>()));
        }));

    test('délai dépassé : ServeurInjoignable ; résultat incertain seulement pour un envoi non idempotent', () => avecVraiHttp(() async {
          srv.routes['POST /lent'] = (_) => const ReponseLocale({'success': true}, delai: Duration(seconds: 2));
          await expectLater(client.post('/lent', {}, idempotent: false),
              throwsA(isA<ServeurInjoignable>().having((e) => e.resultatIncertain, 'incertain', isTrue).having((e) => e.delai, 'delai', isTrue)));
          await expectLater(client.post('/lent', {}, idempotent: true), throwsA(isA<ServeurInjoignable>().having((e) => e.resultatIncertain, 'incertain', isFalse)));
        }));

    test('serveur arrêté → ServeurInjoignable (message distinct de la session)', () => avecVraiHttp(() async {
          final port = (await ServerSocket.bind(InternetAddress.loopbackIPv4, 0))..close();
          final c = ClientPrestige(() => 'http://127.0.0.1:${port.port}/prestige/api/v1', delaiConnexion: const Duration(seconds: 2));
          await expectLater(c.get('/x'), throwsA(isA<ServeurInjoignable>()));
          expect(const ServeurInjoignable().message, isNot(const SessionExpiree().message));
        }));

    test('tableau nu (motifs) lu par getListe', () => avecVraiHttp(() async {
          srv.routes['GET /motifs'] = (_) => const ReponseLocale([
                {'id': 1, 'libelle': 'A'}
              ]);
          expect(await client.getListe('/motifs'), hasLength(1));
        }));
  });

  test('le pot à cookies partagé est bien celui de l\'application', () {
    expect(DioClient.cookieJar, isA<CookieJar>());
  });
}
