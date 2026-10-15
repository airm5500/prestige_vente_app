// RÉSEAU — 4.3.3 : un 404 de Payara a le même corps HTML que Prestige soit NON DÉPLOYÉ (démarrage / redéploiement)
// ou qu'une route manque sur un serveur ANCIEN. L'application ne conclut « route absente / serveur ancien » (replis :
// reserve/droits, posos/droits, rh pointages photo, app-vente…) qu'après avoir vérifié GET /officine — et seulement
// sur un tel 404 (aucune requête de plus en fonctionnement normal). Prestige non déployé : « Serveur indisponible… »,
// à réessayer, rien de mémorisé. Serveur éteint : « Serveur injoignable… ».
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/horsligne/client_ref.dart';
import 'package:prestige_vente_app/horsligne/routes_app_vente.dart';
import 'package:prestige_vente_app/horsligne/server_monitor.dart';
import 'package:prestige_vente_app/rh/pointage_rh.dart';
import 'package:prestige_vente_app/rh/rh_api.dart';
import 'package:prestige_vente_app/serveur/client_prestige.dart';
import 'package:prestige_vente_app/serveur/erreur_vue.dart';
import 'package:prestige_vente_app/serveur/panne_serveur.dart';
import 'package:prestige_vente_app/support/support_centre.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import '../outils/app_e2e.dart';

DioException _err(DioExceptionType type, {int? statut, Object? erreur, Map<String, dynamic> extra = const {}}) {
  final o = RequestOptions(path: 'http://x/prestige/api/v1/a');
  return DioException(
    requestOptions: o,
    type: type,
    error: erreur,
    response: statut == null ? null : Response<dynamic>(requestOptions: o, statusCode: statut, extra: extra),
  );
}

void main() {
  group('Unitaires : classement des pannes', () {
    test('aucune réponse → injoignable ; 502/503/504 ou 404 marqué → indisponible ; 401, 404 simple, 500 → rien', () {
      expect(panneDe(_err(DioExceptionType.connectionError)), PanneServeur.injoignable);
      expect(panneDe(_err(DioExceptionType.connectionTimeout)), PanneServeur.injoignable);
      expect(panneDe(_err(DioExceptionType.receiveTimeout)), PanneServeur.injoignable);
      expect(panneDe(_err(DioExceptionType.unknown, erreur: const SocketException('Connection refused'))), PanneServeur.injoignable);
      expect(panneDe(const SocketException('x')), PanneServeur.injoignable);
      expect(panneDe(TimeoutException('x')), PanneServeur.injoignable);
      for (final c in [502, 503, 504]) {
        expect(panneDe(_err(DioExceptionType.badResponse, statut: c)), PanneServeur.indisponible, reason: 'HTTP $c');
      }
      expect(panneDe(_err(DioExceptionType.badResponse, statut: 503, extra: {cleIndisponible: true})), PanneServeur.indisponible);
      for (final c in [401, 403, 404, 500]) {
        expect(panneDe(_err(DioExceptionType.badResponse, statut: c)), isNull, reason: 'HTTP $c : le serveur Prestige a répondu');
      }
      expect(panneDe(_err(DioExceptionType.cancel)), isNull);
      expect(panneDe(_err(DioExceptionType.badCertificate)), isNull, reason: 'HTTPS : message propre');
    });

    test('corps d\'un 404 à vérifier : HTML ou vide (Payara) ; jamais une réponse JSON de Prestige', () {
      expect(corpsNonPrestige(null), isTrue);
      expect(corpsNonPrestige(''), isTrue);
      expect(corpsNonPrestige(FauxServeurPrestige.payara404.corps), isTrue);
      expect(corpsNonPrestige('Not Found'), isTrue);
      expect(corpsNonPrestige(<int>[]), isTrue);
      expect(corpsNonPrestige({'success': false}), isFalse);
      expect(corpsNonPrestige('{"success":false,"message":"inconnu"}'), isFalse);
      expect(corpsNonPrestige(const []), isFalse);
    });

    test('racine de l\'API d\'une adresse', () {
      expect(SondeDeploiement.racine(Uri.parse('http://10.0.0.5:8080/prestige/api/v1/reserve/droits?x=1')),
          'http://10.0.0.5:8080/prestige/api/v1');
      expect(SondeDeploiement.racine(Uri.parse('https://ph.example.com/prestige/api/v1/mobile/connexion')),
          'https://ph.example.com/prestige/api/v1');
      expect(SondeDeploiement.racine(Uri.parse('http://x/autre')), isNull);
    });
  });

  group('Intégration : vérification par /officine (serveur local, vrai HTTP)', () {
    late FauxServeurPrestige srv;
    late ClientPrestige client;
    setUp(() => avecVraiHttp(() async {
          srv = FauxServeurPrestige()..exigerSession = false;
          await srv.demarrer();
          SondeDeploiement.sondes = 0;
          client = ClientPrestige(() => srv.base);
        }));
    tearDown(() => avecVraiHttp(() async {
          await srv.arreter();
          await DioClient.cookieJar.deleteAll();
        }));

    int officines() => srv.recuesSur('/officine').length;

    test('fonctionnement normal : AUCUNE vérification (aucune requête de plus)', () => avecVraiHttp(() async {
          srv.routes['GET /reserve/droits'] = (_) => FauxServeurPrestige.ok({'success': true, 'traiter': true});
          for (var i = 0; i < 3; i++) {
            expect((await client.get('/reserve/droits'))['traiter'], isTrue);
          }
          expect((SondeDeploiement.sondes, officines()), (0, 0));
        }));

    test('serveur ancien (route absente, 404 HTML, Prestige déployé) → 404 rendu : repli d\'origine ; une vérification '
        'pour plusieurs 404', () => avecVraiHttp(() async {
          srv.routes['GET /posos/droits'] = (_) => FauxServeurPrestige.payara404;
          srv.routes['GET /reserve/droits'] = (_) => FauxServeurPrestige.payara404;
          await expectLater(client.get('/posos/droits'), throwsA(isA<ErreurHttp>().having((e) => e.status, 'status', 404)));
          await expectLater(client.get('/reserve/droits'), throwsA(isA<ErreurHttp>().having((e) => e.status, 'status', 404)));
          expect(SondeDeploiement.sondes, 1, reason: 'résultat gardé 10 s');
          expect(officines(), 1);
        }));

    test('404 JSON de Prestige (ex. clé client inconnue) : jamais vérifié', () => avecVraiHttp(() async {
          srv.routes['GET /client-ref/X'] = (_) => const ReponseLocale({'success': false, 'message': 'inconnue'}, statut: 404);
          await expectLater(client.get('/client-ref/X'), throwsA(isA<ErreurHttp>().having((e) => e.status, 'status', 404)));
          expect(SondeDeploiement.sondes, 0);
        }));

    test('Prestige non déployé (404 partout) → ServeurIndisponible « Serveur indisponible… », jamais « route absente »',
        () => avecVraiHttp(() async {
              srv.prestigeAbsent = true;
              final e = await client.get('/reserve/droits').then<Object?>((_) => null, onError: (Object e) => e);
              expect(e, isA<ServeurIndisponible>());
              expect(e, isNot(isA<ErreurHttp>()));
              expect('$e', MessagesServeur.indisponible);
              expect(titreErreur(e!), 'Serveur indisponible');
              expect(SondeDeploiement.sondes, 1);
              // 503 du serveur d'applications : même message, sans vérification.
              srv.statutAbsent = 503;
              SondeDeploiement.vider();
              await expectLater(client.get('/reserve/droits'), throwsA(isA<ServeurIndisponible>()));
            }));

    test('serveur coupé (connexion refusée) → ServeurInjoignable « Serveur injoignable… »', () => avecVraiHttp(() async {
          await srv.couper();
          final e = await client.get('/reserve/droits').then<Object?>((_) => null, onError: (Object e) => e);
          expect(e, isA<ServeurInjoignable>());
          expect(e, isNot(isA<ServeurIndisponible>()));
          expect('$e', MessagesServeur.injoignable);
          expect(titreErreur(e!), 'Serveur injoignable');
          await srv.retablir();
        }));

    test('app-vente/capacites : Prestige non déployé → 503, aucun préfixe ni « capacité absente » mémorisé ; '
        'serveur ancien → 404, capacité absente', () => avecVraiHttp(() async {
          RoutesAppVente.vider();
          final d = Dio(BaseOptions(baseUrl: srv.base, validateStatus: (_) => true))..interceptors.add(IntercepteurDeploiement());
          Future<({int status, Object? body})> lire(String chemin) async {
            final r = await d.get<dynamic>(chemin);
            return (status: r.statusCode ?? 0, body: r.data);
          }

          srv.prestigeAbsent = true;
          var r = await RoutesAppVente.lireCapacites(srv.base, lire);
          expect(r.status, 503);
          expect(RoutesAppVente.connu(srv.base), isFalse);
          expect(CapaciteClientRef.depuisReponse(r.status, r.body), isNull, reason: 'indéterminé : à relire plus tard');
          // Serveur ancien, Prestige déployé : les deux chemins répondent 404 HTML.
          srv.prestigeAbsent = false;
          SondeDeploiement.vider();
          srv.routes['GET /app-vente/capacites'] = (_) => FauxServeurPrestige.payara404;
          srv.routes['GET /mobile/capacites'] = (_) => FauxServeurPrestige.payara404;
          r = await RoutesAppVente.lireCapacites(srv.base, lire);
          expect(r.status, 404);
          expect(CapaciteClientRef.depuisReponse(r.status, r.body), isFalse);
        }));

    test('pointage RH : Prestige non déployé → RhHorsLigne « indisponible » (file hors ligne), jamais « routes RH absentes »',
        () => avecVraiHttp(() async {
              final rh = DioRhServeur(() => srv.base);
              srv.prestigeAbsent = true;
              final e = await rh.get('/rh/droits').then<Object?>((_) => null, onError: (Object e) => e);
              expect(e, isA<RhHorsLigne>().having((x) => x.panne, 'panne', PanneServeur.indisponible));
              expect('$e', MessagesServeur.indisponible);
              srv.prestigeAbsent = false;
              await srv.couper();
              final e2 = await rh.get('/rh/droits').then<Object?>((_) => null, onError: (Object e) => e);
              expect(e2, isA<RhHorsLigne>().having((x) => x.panne, 'panne', PanneServeur.injoignable));
              await srv.retablir();
              expect(const BilanEnvoiRh(interrompu: true, panne: PanneServeur.indisponible).message, contains('serveur indisponible'));
              expect(const BilanEnvoiRh(interrompu: true).message, contains('serveur injoignable'));
            }));

    test('centre de support : 503 (Prestige non déployé) → gardé et renvoyé, jamais « route absente »', () {
      expect(lireReponseSupport(503, null), SupportReponse.echec);
      expect(lireReponseSupport(404, null), SupportReponse.routeAbsente);
    });
  });

  group('Surveillance du serveur', () {
    test('ServerMonitor : panne « indisponible » constatée, remise à zéro au retour', () async {
      var ok = false;
      final m = ServerMonitor(ping: () async => ok);
      m.signalIndisponible();
      for (var i = 0; i < 3; i++) {
        await m.checkNow();
      }
      expect(m.etat, EtatServeur.injoignable);
      expect(m.panne, PanneServeur.indisponible);
      ok = true;
      await m.checkNow();
      expect(m.etat, EtatServeur.enLigne);
      expect(m.panne, PanneServeur.injoignable);
    });

    testWidgets('accueil : Prestige redéployé → « Serveur indisponible » ; PC éteint → « Serveur injoignable »', (t) async {
      TailleEcran.sunmiV2s.appliquer(t);
      final app = AppE2E();
      await app.preparer(prefs: {'presentation_listes_v1': ListPresentation.dashboard.name});
      await app.lancer(t);
      expect(await app.seConnecter(t), isTrue);
      app.serveur.prestigeAbsent = true;
      await app.attendre(t, const Duration(seconds: 100));
      expect(find.textContaining(MessagesServeur.titreIndisponible), findsWidgets);
      expect(find.textContaining('404'), findsNothing);
      app.serveur.prestigeAbsent = false;
      await app.serveur.couper();
      await app.attendre(t, const Duration(seconds: 35));
      expect(find.textContaining(MessagesServeur.titreInjoignable), findsWidgets);
      expect(find.textContaining(MessagesServeur.titreIndisponible), findsNothing);
      await app.serveur.retablir();
      await app.attendre(t, const Duration(seconds: 35));
      expect(find.textContaining(MessagesServeur.titreInjoignable), findsNothing);
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });
  });
}
