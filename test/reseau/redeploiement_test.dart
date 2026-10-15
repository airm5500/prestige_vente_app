// RÉSEAU — 4.3.2 : Prestige en cours de REDÉPLOIEMENT. Payara répond alors 404 (page HTML « Error report ») sur
// toutes les routes de l'application, ou 502 / 503 (proxy, démarrage), ou refuse la connexion. Avant : la connexion
// affichait « erreur 404 » (borne : « Connexion refusée … (Le serveur a répondu HTTP 404) ») ou, dans l'interface
// d'origine, « Login ou mot de passe incorrect ». Après : « Serveur indisponible, veuillez réessayer » dans les deux
// interfaces, jamais confondu avec un mot de passe faux (qui reste « incorrect »).
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/accueil/accueil_screen.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/api/models/licence_lookup.dart';
import 'package:prestige_vente_app/api/session_expiree.dart';
import 'package:prestige_vente_app/borne/borne_launcher.dart';
import 'package:prestige_vente_app/connexion/connexion_screen.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/screens/auth/login_screen.dart';
import 'package:prestige_vente_app/services/identifiants_securises.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../outils/app_e2e.dart';

/// Page d'erreur de Payara pendant un redéploiement (application absente) : 404 en HTML.
const _payara404 = ReponseLocale(
    '<!DOCTYPE html><html><head><title>Payara Server  5.2022.5 #badassfish - Error report</title></head>'
    '<body><h1>HTTP Status 404 - Not Found</h1></body></html>',
    statut: 404);

const _indisponible = 'Serveur indisponible, veuillez réessayer';

void main() {
  group('ApiService.login : serveur indisponible ≠ identifiants refusés', () {
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

    for (final (nom, rep) in [
      ('404 de Payara (redéploiement)', _payara404),
      ('502', FauxServeurPrestige.erreurServeur(502)),
      ('503', FauxServeurPrestige.erreurServeur(503)),
      ('504', FauxServeurPrestige.erreurServeur(504)),
    ]) {
      test('$nom → « $_indisponible », jamais « incorrect » ni « 404 »', () => avecVraiHttp(() async {
            srv.routes['POST /user/auth'] = (_) => rep;
            expect(await api.login(DonneesFictives.login, DonneesFictives.motDePasse), isNull);
            final e = api.dernierEchecConnexion!;
            expect(e.type, EchecConnexion.indisponible);
            expect(e.estRefus, isFalse);
            expect(e.message, '$_indisponible.');
            expect(e.message, isNot(contains('404')));
            // Interface d'origine (AuthProvider.errorMessage) et borne (motif) : même message.
            final auth = AuthProvider(api);
            expect(await auth.login(DonneesFictives.login, DonneesFictives.motDePasse), isFalse);
            expect(auth.errorMessage, '$_indisponible.');
            expect(auth.dernierEchecServeur, isTrue);
            expect(motifConnexionBorne(login: 'borne', motDePasse: true, echec: e), '$_indisponible.');
          }));
    }

    test('connexion refusée (serveur arrêté pendant le redéploiement) → indisponible', () => avecVraiHttp(() async {
          await srv.couper();
          expect(await api.login(DonneesFictives.login, DonneesFictives.motDePasse), isNull);
          expect(api.dernierEchecConnexion!.type, EchecConnexion.indisponible);
          await srv.retablir();
        }));

    test('mot de passe faux (le serveur répond) → toujours « incorrect »', () => avecVraiHttp(() async {
          final auth = AuthProvider(api);
          expect(await auth.login(DonneesFictives.login, 'mauvais'), isFalse);
          expect(api.dernierEchecConnexion!.estRefus, isTrue);
          expect(auth.errorMessage, 'Login ou mot de passe incorrect.');
          expect(auth.dernierEchecServeur, isFalse);
          // 401 sur la connexion : un refus, pas une panne.
          srv.routes['POST /user/auth'] = (_) => FauxServeurPrestige.nonConnecte401;
          expect(await auth.login(DonneesFictives.login, DonneesFictives.motDePasse), isFalse);
          expect(auth.errorMessage, 'Login ou mot de passe incorrect.');
        }));

    test('licence pendant le redéploiement (404 partout, 503) : serveur indisponible, jamais « aucune licence »',
        () => avecVraiHttp(() async {
              srv.licence = _payara404;
              srv.routes['POST /user/auth'] = (_) => _payara404;
              expect((await api.lookupLicence()).issue, LicenceIssue.appNotFound);
              srv.licence = FauxServeurPrestige.erreurServeur(503);
              expect((await api.lookupLicence()).issue, LicenceIssue.unreachable);
            }));
  });

  group('Écrans de connexion (application entière)', () {
    testWidgets('nouvelle interface : redéploiement → « $_indisponible », puis connexion normale une fois Prestige revenu',
        (t) async {
      TailleEcran.sunmiV2s.appliquer(t);
      final app = AppE2E();
      await app.preparer();
      await app.lancer(t);
      expect(await app.attendreQue(t, find.byType(ConnexionScreen)), isTrue);
      // Redéploiement : Payara répond 404 (HTML) sur la connexion et sur le test du serveur.
      app.serveur.routes['POST /user/auth'] = (_) => _payara404;
      app.serveur.routes['GET /officine'] = (_) => _payara404;
      await t.enterText(find.byKey(const Key('connexion_login')), DonneesFictives.login);
      await t.enterText(find.byKey(const Key('connexion_mdp')), DonneesFictives.motDePasse);
      await t.ensureVisible(find.byKey(const Key('se_connecter')));
      await t.tap(find.byKey(const Key('se_connecter')));
      await app.attendre(t, const Duration(seconds: 2));
      expect(find.textContaining(_indisponible), findsWidgets);
      expect(find.textContaining('incorrect'), findsNothing, reason: 'jamais confondu avec un mot de passe faux');
      expect(find.textContaining('404'), findsNothing);
      // Prestige est revenu : la connexion aboutit.
      app.serveur.routes.remove('POST /user/auth');
      app.serveur.routes.remove('GET /officine');
      await t.ensureVisible(find.byKey(const Key('se_connecter')));
      await t.tap(find.byKey(const Key('se_connecter')));
      expect(await app.attendreQue(t, find.byType(AccueilScreen)), isTrue);
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });

    testWidgets('interface d\'origine : redéploiement → « $_indisponible » (avant : « Login ou mot de passe incorrect »)',
        (t) async {
      TailleEcran.telephone.appliquer(t);
      final app = AppE2E();
      await app.preparer(interfaceNouvelle: false);
      await app.lancer(t);
      expect(await app.attendreQue(t, find.byType(AncienLoginScreen)), isTrue);
      app.serveur.routes['POST /user/auth'] = (_) => FauxServeurPrestige.erreurServeur(503);
      final champs = find.byType(TextFormField);
      await t.enterText(champs.at(0), DonneesFictives.login);
      await t.enterText(champs.at(1), DonneesFictives.motDePasse);
      await t.tap(find.text('Se connecter'));
      await app.attendre(t, const Duration(seconds: 2));
      expect(find.textContaining(_indisponible), findsOneWidget);
      expect(find.textContaining('incorrect'), findsNothing);
      // Mot de passe faux, serveur revenu : « incorrect » (inchangé).
      app.serveur.routes.remove('POST /user/auth');
      await t.enterText(champs.at(1), 'mauvais');
      await t.tap(find.text('Se connecter'));
      await app.attendre(t, const Duration(seconds: 2));
      expect(find.text('Login ou mot de passe incorrect.'), findsOneWidget);
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });
  });
}
