// RÉSEAU — 4.3.2 / 4.3.3 : deux pannes du serveur, affichées différemment à la connexion (deux interfaces, borne) :
// 1. INJOIGNABLE (aucune réponse : connexion refusée = PC serveur éteint ou Payara arrêté, délai, réseau absent)
//    → « Serveur injoignable. Vérifiez le Wi-Fi et que le PC serveur est allumé. »
// 2. INDISPONIBLE (le serveur répond, Prestige non déployé : 404 de Payara, 502 / 503 / 504)
//    → « Serveur indisponible : Prestige est en cours de démarrage ou de redéploiement. Veuillez réessayer dans un instant. »
// Jamais « erreur 404 » ni « mot de passe incorrect » ; un vrai mot de passe faux reste « incorrect ».
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/accueil/accueil_screen.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/api/models/licence_lookup.dart';
import 'package:prestige_vente_app/api/session_expiree.dart';
import 'package:prestige_vente_app/borne/borne_config.dart';
import 'package:prestige_vente_app/borne/borne_diagnostic.dart';
import 'package:prestige_vente_app/borne/borne_launcher.dart';
import 'package:prestige_vente_app/connexion/connexion_screen.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/licence_provider.dart';
import 'package:prestige_vente_app/rh/mobile_api.dart';
import 'package:prestige_vente_app/rh/rh_api.dart';
import 'package:prestige_vente_app/screens/auth/login_screen.dart';
import 'package:prestige_vente_app/serveur/panne_serveur.dart';
import 'package:prestige_vente_app/services/identifiants_securises.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../outils/app_e2e.dart';

const _injoignable = 'Serveur injoignable. Vérifiez le Wi-Fi et que le PC serveur est allumé.';
const _indisponible = 'Serveur indisponible : Prestige est en cours de démarrage ou de redéploiement. Veuillez réessayer dans un instant.';

void main() {
  test('les deux messages, mot pour mot', () {
    expect(MessagesServeur.injoignable, _injoignable);
    expect(MessagesServeur.indisponible, _indisponible);
  });

  group('ApiService.login : injoignable ≠ indisponible ≠ identifiants refusés', () {
    late FauxServeurPrestige srv;
    late ApiService api;
    setUp(() => avecVraiHttp(() async {
          SharedPreferences.setMockInitialValues({});
          FlutterSecureStorage.setMockInitialValues({});
          IdentifiantsSecurises.instance = IdentifiantsSecurises();
          SessionExpiree.instance = SessionExpiree();
          await DioClient.cookieJar.deleteAll();
          srv = FauxServeurPrestige();
          await srv.demarrer();
          api = ApiService(baseUrl: srv.base);
        }));
    tearDown(() => avecVraiHttp(() async {
          await srv.arreter();
          await DioClient.cookieJar.deleteAll();
        }));

    for (final statut in [404, 502, 503, 504]) {
      test('Prestige non déployé (HTTP $statut) → « Serveur indisponible… », jamais « incorrect » ni « 404 »', () => avecVraiHttp(() async {
            srv
              ..prestigeAbsent = true
              ..statutAbsent = statut;
            expect(await api.login(DonneesFictives.login, DonneesFictives.motDePasse), isNull);
            final e = api.dernierEchecConnexion!;
            expect((e.type, e.panne, e.estRefus), (EchecConnexion.indisponible, PanneServeur.indisponible, false));
            expect(e.message, _indisponible);
            expect(e.message, isNot(contains('404')));
            // Interface d'origine (AuthProvider.errorMessage) et borne (motif) : même message.
            final auth = AuthProvider(api);
            expect(await auth.login(DonneesFictives.login, DonneesFictives.motDePasse), isFalse);
            expect(auth.errorMessage, _indisponible);
            expect(auth.dernierePanne, PanneServeur.indisponible);
            expect(motifConnexionBorne(login: 'borne', motDePasse: true, echec: e), _indisponible);
          }));
    }

    test('connexion refusée (PC serveur éteint, Payara arrêté) → « Serveur injoignable… »', () => avecVraiHttp(() async {
          await srv.couper();
          expect(await api.login(DonneesFictives.login, DonneesFictives.motDePasse), isNull);
          final e = api.dernierEchecConnexion!;
          expect((e.type, e.panne), (EchecConnexion.reseau, PanneServeur.injoignable));
          expect(e.message, _injoignable);
          final auth = AuthProvider(api);
          await auth.login(DonneesFictives.login, DonneesFictives.motDePasse);
          expect(auth.errorMessage, _injoignable);
          expect(motifConnexionBorne(login: 'borne', motDePasse: true, echec: e), _injoignable);
          await srv.retablir();
        }));

    test('mot de passe faux, 401, 500 : inchangés (refus, jamais une panne)', () => avecVraiHttp(() async {
          final auth = AuthProvider(api);
          expect(await auth.login(DonneesFictives.login, 'mauvais'), isFalse);
          expect(api.dernierEchecConnexion!.estRefus, isTrue);
          expect(auth.errorMessage, 'Login ou mot de passe incorrect.');
          expect(auth.dernierePanne, isNull);
          srv.routes['POST /user/auth'] = (_) => FauxServeurPrestige.nonConnecte401;
          expect(await auth.login(DonneesFictives.login, DonneesFictives.motDePasse), isFalse);
          expect(auth.errorMessage, 'Login ou mot de passe incorrect.');
          srv.routes['POST /user/auth'] = (_) => FauxServeurPrestige.erreurServeur(500);
          expect(await api.login(DonneesFictives.login, DonneesFictives.motDePasse), isNull);
          expect((api.dernierEchecConnexion!.type, api.dernierEchecConnexion!.panne), (EchecConnexion.refusee, null));
        }));

    test('licence : non déployé (404 partout, 503) → indisponible ; serveur coupé → injoignable ; jamais « aucune licence »',
        () => avecVraiHttp(() async {
              srv.prestigeAbsent = true;
              expect((await api.lookupLicence()).issue, LicenceIssue.appNotFound);
              final p = LicenceProvider(api);
              await p.checkLicence();
              expect(p.errorTitle, MessagesServeur.titreIndisponible);
              expect(p.errorMessage, startsWith(_indisponible));
              srv.statutAbsent = 503;
              expect((await api.lookupLicence()).issue, LicenceIssue.appNotFound);
              srv.prestigeAbsent = false;
              await srv.couper();
              expect((await api.lookupLicence()).issue, LicenceIssue.unreachable);
              await p.checkLicence();
              expect(p.errorTitle, MessagesServeur.titreInjoignable);
              expect(p.errorMessage, startsWith(_injoignable));
              await srv.retablir();
            }));
  });

  group('Borne et pointage', () {
    test('« Tester la borne » : Prestige non déployé → indisponible ; serveur coupé → injoignable ; mauvais mot de passe → refusée',
        () => avecVraiHttp(() async {
              final s = FauxServeurPrestige();
              await s.demarrer();
              addTearDown(s.arreter);
              const c = BorneConfig(actif: true, login: DonneesFictives.login);
              s.prestigeAbsent = true;
              var d = await TesteurBorne(baseUrl: s.base, secrets: MemoireBorneSecrets(DonneesFictives.motDePasse)).tester(c);
              expect(d.conclusion, _indisponible);
              s.prestigeAbsent = false;
              d = await TesteurBorne(baseUrl: s.base, secrets: MemoireBorneSecrets('mauvais')).tester(c);
              expect(d.conclusion, contains('Connexion refusée'));
              await s.couper();
              d = await TesteurBorne(baseUrl: s.base, secrets: MemoireBorneSecrets(DonneesFictives.motDePasse)).tester(c);
              expect(d.conclusion, startsWith(_injoignable));
              await s.retablir();
            }));

    test('téléphone de pointage (API mobile) et terminal RH : le message suit la panne', () {
      expect(const MobileHorsLigne().texte, _injoignable);
      expect(const MobileHorsLigne(PanneServeur.indisponible).texte, _indisponible);
      expect('${const RhHorsLigne(PanneServeur.indisponible)}', _indisponible);
      expect(const RhHorsLigne().titre, 'Serveur injoignable');
    });
  });

  group('Écrans de connexion (application entière)', () {
    testWidgets('nouvelle interface : Prestige non déployé → « Serveur indisponible » ; PC serveur éteint → « Serveur injoignable »',
        (t) async {
      TailleEcran.sunmiV2s.appliquer(t);
      final app = AppE2E();
      await app.preparer();
      await app.lancer(t);
      expect(await app.attendreQue(t, find.byType(ConnexionScreen)), isTrue);
      Future<void> seConnecter() async {
        await t.enterText(find.byKey(const Key('connexion_login')), DonneesFictives.login);
        await t.enterText(find.byKey(const Key('connexion_mdp')), DonneesFictives.motDePasse);
        await t.ensureVisible(find.byKey(const Key('se_connecter')));
        await t.tap(find.byKey(const Key('se_connecter')));
        await app.attendre(t, const Duration(seconds: 2));
      }

      // 1. Redéploiement : Payara répond 404 (HTML) sur toutes les routes.
      app.serveur.prestigeAbsent = true;
      await seConnecter();
      expect(find.text(MessagesServeur.titreIndisponible), findsWidgets);
      expect(find.textContaining(MessagesServeur.detailIndisponible), findsWidgets);
      expect(find.textContaining('incorrect'), findsNothing, reason: 'jamais confondu avec un mot de passe faux');
      expect(find.textContaining('404'), findsNothing);
      expect(find.text(MessagesServeur.titreInjoignable), findsNothing);
      // 2. PC serveur éteint : aucune réponse.
      app.serveur.prestigeAbsent = false;
      await app.serveur.couper();
      await seConnecter();
      expect(find.text(MessagesServeur.titreInjoignable), findsWidgets);
      expect(find.textContaining(MessagesServeur.detailInjoignable), findsWidgets);
      expect(find.textContaining(MessagesServeur.detailIndisponible), findsNothing);
      // Prestige revenu : la connexion aboutit.
      await app.serveur.retablir();
      await t.ensureVisible(find.byKey(const Key('se_connecter')));
      await t.tap(find.byKey(const Key('se_connecter')));
      expect(await app.attendreQue(t, find.byType(AccueilScreen)), isTrue);
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });

    testWidgets('lancement : Prestige non déployé → « Serveur indisponible » ; serveur coupé → « Serveur injoignable »', (t) async {
      TailleEcran.sunmiV2s.appliquer(t);
      final app = AppE2E();
      await app.preparer();
      app.serveur.prestigeAbsent = true;
      await app.lancer(t);
      expect(await app.attendreQue(t, find.byKey(const Key('lancement_injoignable'))), isTrue);
      expect(find.text(MessagesServeur.titreIndisponible), findsOneWidget);
      expect(find.textContaining(MessagesServeur.detailIndisponible), findsOneWidget);
      expect(find.textContaining('La licence n\'est pas en cause'), findsOneWidget);
      expect(find.byKey(const Key('lancement_reessayer')).hitTestable(), findsOneWidget);
      // Le serveur s'éteint : réessai → injoignable.
      app.serveur.prestigeAbsent = false;
      await app.serveur.couper();
      await t.tap(find.byKey(const Key('lancement_reessayer')));
      await app.attendre(t, const Duration(seconds: 2));
      expect(find.text(MessagesServeur.titreInjoignable), findsOneWidget);
      expect(find.textContaining(MessagesServeur.detailInjoignable), findsOneWidget);
      await app.serveur.retablir();
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });

    testWidgets('interface d\'origine : 503 → « Serveur indisponible… », coupure → « Serveur injoignable… », mot de passe faux → incorrect',
        (t) async {
      TailleEcran.telephone.appliquer(t);
      final app = AppE2E();
      await app.preparer(interfaceNouvelle: false);
      await app.lancer(t);
      expect(await app.attendreQue(t, find.byType(AncienLoginScreen)), isTrue);
      final champs = find.byType(TextFormField);
      app.serveur
        ..prestigeAbsent = true
        ..statutAbsent = 503;
      await t.enterText(champs.at(0), DonneesFictives.login);
      await t.enterText(champs.at(1), DonneesFictives.motDePasse);
      await t.tap(find.text('Se connecter'));
      await app.attendre(t, const Duration(seconds: 2));
      expect(find.text(_indisponible), findsOneWidget);
      expect(find.textContaining('incorrect'), findsNothing);
      app.serveur.prestigeAbsent = false;
      await app.serveur.couper();
      await t.tap(find.text('Se connecter'));
      await app.attendre(t, const Duration(seconds: 2));
      expect(find.text(_injoignable), findsOneWidget);
      await app.serveur.retablir();
      await t.enterText(champs.at(1), 'mauvais');
      await t.tap(find.text('Se connecter'));
      await app.attendre(t, const Duration(seconds: 2));
      expect(find.text('Login ou mot de passe incorrect.'), findsOneWidget);
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });
  });
}
