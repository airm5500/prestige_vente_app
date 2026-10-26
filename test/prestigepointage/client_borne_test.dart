// Prestige Pointage — INTÉGRATION : enrôlement et client signé contre le faux serveur Prestige en mémoire, qui applique
// les règles du vrai serveur (test/outils/faux_serveur_borne.dart, d'après le commit 31622a33) :
//  - enrôlement : administrateur → identité (secret décodé, 32 octets) puis session fermée ; compte sans droit → 403 ;
//    serveur sans la demande 57 → « serveur à mettre à jour » ;
//  - appels signés : moi, employés (champs réduits), pointage (idempotent), photo (multipart, octets exacts),
//    empreintes (DESACTIVE) ; tout autre chemin RH → 404 sans requête ;
//  - refus : signature fausse (autre secret) → « non reconnue », horloge décalée → « heure incorrecte », borne retirée →
//    REVOQUEE, hors réseau → RESEAU, 429 → aucune requête avant Retry-After, serveur ancien → « à mettre à jour » ;
//    dans tous ces cas RhHorsLigne (le terminal garde le pointage en file) ;
//  - le secret n'est dans aucune requête (ni en-tête ni corps) ; seule la signature circule.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/prestigepointage/client_borne.dart';
import 'package:prestige_vente_app/prestigepointage/enrolement_borne.dart';
import 'package:prestige_vente_app/prestigepointage/identite_borne.dart';
import 'package:prestige_vente_app/rh/rh_api.dart';
import 'package:prestige_vente_app/serveur/panne_serveur.dart';

import '../outils/faux_serveur_borne.dart';
import '../outils/faux_serveur_prestige.dart';

final _emp = 'ab12cd34' * 8;

void main() {
  late FauxServeurPrestige srv;
  late FauxBornes bornes;

  setUp(() async {
    srv = FauxServeurPrestige()..installerEnMemoire();
    bornes = FauxBornes(srv);
    SondeDeploiement.vider();
    await DioClient.cookieJar.deleteAll();
  });
  tearDown(() async {
    srv.desinstaller();
    await DioClient.cookieJar.deleteAll();
  });

  Future<IdentiteBorne> enroler({String nom = 'Borne entrée'}) async {
    final r = await EnrolementBorne().enroler(
        baseUrl: srv.base, login: DonneesFictives.admin, motDePasse: DonneesFictives.motDePasseAdmin, nom: nom, empreinte: _emp);
    expect(r.reussi, isTrue, reason: r.message);
    return r.identite!;
  }

  group('enrôlement', () {
    test('administrateur : identité (secret de 32 octets), session fermée aussitôt', () async {
      final i = await enroler();
      expect(i.secret, hasLength(32));
      expect(i.empreinte, _emp);
      expect(i.serveur, srv.base);
      expect(bornes.bornes[i.borneId]!.secret, i.secret);
      final post = srv.recuesSur('/rh/bornes').single;
      expect(post.json, {'empreinte': _emp, 'nom': 'Borne entrée'});
      expect(srv.recuesSur('/user/logout'), hasLength(1), reason: 'déconnexion immédiate');
      expect(srv.sessions, isEmpty, reason: 'aucune session gardée par la borne');
      expect(i.toString(), isNot(contains(base64Url.encode(i.secret).substring(0, 10))), reason: 'jamais le secret');
    });

    test('compte sans le droit : refus clair ; serveur sans la demande 57 : « à mettre à jour » ; mot de passe faux', () async {
      final sans = await EnrolementBorne().enroler(
          baseUrl: srv.base, login: DonneesFictives.login, motDePasse: DonneesFictives.motDePasse, nom: 'B', empreinte: _emp);
      expect(sans.message, EnrolementBorne.messageDroit);
      final faux = await EnrolementBorne().enroler(baseUrl: srv.base, login: DonneesFictives.admin, motDePasse: 'faux', nom: 'B', empreinte: _emp);
      expect(faux.reussi, isFalse);
      srv.routesParDefaut.remove('POST /rh/bornes');
      final ancien = await EnrolementBorne().enroler(
          baseUrl: srv.base, login: DonneesFictives.admin, motDePasse: DonneesFictives.motDePasseAdmin, nom: 'B', empreinte: _emp);
      expect(ancien.message, EnrolementBorne.messageServeurAncien);
      expect(srv.sessions, isEmpty);
    });

    test('réenrôler la même empreinte retire l\'ancienne borne (401 REVOQUEE)', () async {
      final a = await enroler();
      final b = await enroler(nom: 'Borne bis');
      final ca = ClientBorne(a);
      await expectLater(ca.get('/rh/droits'), throwsA(isA<RhHorsLigne>()));
      expect(ca.etat, EtatBorne.revoquee);
      expect((await ClientBorne(b).get('/rh/droits')).body, {'success': true, 'gerer': false});
    });
  });

  group('appels signés', () {
    test('moi, employés réduits, pointage puis renvoi idempotent, photo multipart, empreintes DESACTIVE', () async {
      final c = ClientBorne(await enroler());
      expect(c.horsLigne, isFalse);
      expect((await c.get('/rh/droits')).body, {'success': true, 'gerer': false});
      expect(c.etat, EtatBorne.ok);
      final e = await c.get('/rh/employes', const {'query': '', 'inactifs': 'false'});
      expect((e.body!['data'] as List).first.keys.toSet(), {'id', 'matricule', 'nom', 'prenoms', 'badge', 'statut'});
      final n = DateTime.now();
      final corps = {
        'id': '0f8b2c1e-7d4a-4b9e-9c3f-2a1b3c4d5e6f',
        'employeId': 'E1',
        'jour': '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}',
        'heure': '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}',
        'sens': 'ENTREE',
        'motif': 'Badge terminal Borne entrée',
        'controle': {'photo': true},
      };
      expect((await c.post('/rh/pointages', corps)).body?['success'], isTrue);
      expect((await c.post('/rh/pointages', corps)).body?['deja'], isTrue, reason: 'même id : rien de créé');
      expect(bornes.pointages, hasLength(1));
      final jpeg = Uint8List.fromList(List.generate(2048, (i) => (i * 31) & 0xff));
      final ph = await c.envoyerPhoto(corps['id'] as String, jpeg, n);
      expect(ph.body?['success'], isTrue);
      expect(bornes.photos.values.single, containsAllInOrder(jpeg.sublist(0, 64)), reason: 'octets du JPEG intacts');
      final autre = await c.envoyerPhoto('inconnu-1234', jpeg, n);
      expect(autre.body?['msg'], 'Pointage introuvable pour cette borne.');
      final emp = await c.get('/rh/empreintes', const {'format': 'SUNMI_A400_RAW', 'depuis': '2026-10-26T08:00:00'});
      expect(emp.body?['code'], 'DESACTIVE');
      expect(bornes.refusSignature, 0, reason: 'toutes les signatures justes, paramètres encodés compris');
    });

    test('jamais d\'autre route : présence, gestion → 404 sans requête ; le secret ne circule jamais', () async {
      final i = await enroler();
      final c = ClientBorne(i);
      final avant = srv.recues.length;
      expect((await c.get('/rh/presence', const {'jour': '2026-10-26'})).status, 404);
      expect((await c.post('/rh/employes/E1/empreintes', const {})).status, 404);
      expect(srv.recues.length, avant);
      await c.get('/rh/droits');
      final b64 = base64Url.encode(i.secret).replaceAll('=', '');
      for (final r in srv.recues.where((r) => r.chemin.contains('/borne-pointage/'))) {
        expect(r.entetes.values.join('|'), isNot(contains(b64)));
        expect(r.corps, isNot(contains(b64)));
        expect(r.entete('x-borne'), i.borneId);
        expect(r.entete('x-borne-signature'), isNotNull);
        expect(r.cookie, isEmpty, reason: 'ni session ni cookie');
      }
    });
  });

  group('refus et états', () {
    test('mauvais secret → non reconnue ; horloge décalée de 10 min → heure incorrecte (en-tête Date du serveur)', () async {
      final i = await enroler();
      final faux = IdentiteBorne(borneId: i.borneId, secret: List.filled(32, 7), empreinte: i.empreinte, nom: i.nom, serveur: i.serveur);
      final c = ClientBorne(faux);
      await expectLater(c.get('/rh/droits'), throwsA(isA<RhHorsLigne>()));
      expect(c.etat, EtatBorne.nonReconnue);
      expect(c.horsLigne, isTrue);
      final h = ClientBorne(i, maintenant: () => DateTime.now().add(const Duration(minutes: 10)));
      await expectLater(h.get('/rh/droits'), throwsA(isA<RhHorsLigne>()));
      expect(h.etat, EtatBorne.horloge);
      expect(h.message, contains('Heure du terminal incorrecte'));
      expect(h.ecartHorloge!.inMinutes, inInclusiveRange(9, 10));
    });

    test('borne retirée → REVOQUEE ; hors réseau → RESEAU ; serveur ancien (sans la demande 57) → à mettre à jour', () async {
      final i = await enroler();
      final c = ClientBorne(i);
      bornes.retirer(i.borneId);
      await expectLater(c.get('/rh/employes'), throwsA(isA<RhHorsLigne>()));
      expect(c.etat, EtatBorne.revoquee);
      expect(c.message, startsWith('Appareil retiré : faites-le enrôler à nouveau'));
      bornes.horsReseau = true;
      await expectLater(c.get('/rh/employes'), throwsA(isA<RhHorsLigne>()));
      expect(c.etat, EtatBorne.reseau);
      expect(c.message, startsWith('Borne utilisable seulement sur le réseau de l\'officine'));
      srv.filtreAvantSession = null; // serveur sans la demande 57 : routes inconnues, session exigée
      await expectLater(c.get('/rh/employes'), throwsA(isA<RhHorsLigne>()));
      expect(c.etat, EtatBorne.serveurAncien);
      expect(c.message, startsWith('Serveur à mettre à jour'));
    });

    test('429 + Retry-After : plus aucune requête avant la fin de l\'attente ; serveur coupé → hors ligne', () async {
      final i = await enroler();
      var t = DateTime.now();
      bornes.horloge = () => t;
      final c = ClientBorne(i, maintenant: () => t);
      for (var k = 0; k < 120; k++) {
        await c.get('/rh/droits');
      }
      await expectLater(c.get('/rh/droits'), throwsA(isA<RhHorsLigne>()));
      expect(c.etat, EtatBorne.tropDeDemandes);
      final avant = srv.recues.length;
      await expectLater(c.get('/rh/droits'), throwsA(isA<RhHorsLigne>()));
      expect(srv.recues.length, avant, reason: 'Retry-After respecté');
      t = t.add(const Duration(seconds: 61));
      expect((await c.get('/rh/droits')).status, 200);
      expect(c.etat, EtatBorne.ok);
      await srv.couper();
      await expectLater(c.get('/rh/droits'), throwsA(isA<RhHorsLigne>()));
      expect(c.etat, EtatBorne.horsLigne);
      await srv.retablir();
    });
  });

  test('ApiService de l\'application jamais utilisé par la borne (aucun cookie de session après l\'enrôlement)', () async {
    await enroler();
    final cookies = await DioClient.cookieJar.loadForRequest(Uri.parse(srv.base));
    expect(cookies, isEmpty);
    expect(ApiService(baseUrl: srv.base).dio.options.baseUrl, srv.base);
  });
}
