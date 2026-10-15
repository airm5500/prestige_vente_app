// Intégration : services principaux de l'application contre le faux serveur Prestige (vrai HTTP local, et transport
// en mémoire pour les délais en temps simulé). Données fictives.
// Couvre ce qui ne l'était pas déjà contre un serveur : ApiService (licence, connexion, officine, préventes, BL,
// analyse article), LicenceProvider, AuthProvider (connexion, connexion automatique, déconnexion) et la passerelle
// de vente DioVenteGateway (création, panier, net, prévente, refus métier, 5xx, coupure).
// Déjà couverts ailleurs : ClientPrestige, Réserve, Posos, Fiche client, droits (test/*_test.dart avec
// test/outils/serveur_json_local.dart), session expirée / renouvelée (session_expiree_test, session_renouvelee_test).
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/api/models/licence_lookup.dart';
import 'package:prestige_vente_app/api/session_expiree.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/bl_control_provider.dart';
import 'package:prestige_vente_app/providers/licence_provider.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/services/identifiants_securises.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'outils/faux_serveur_prestige.dart';

void main() {
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

  Future<void> connecter() async => expect(await api.login(DonneesFictives.login, DonneesFictives.motDePasse), isNotNull);

  group('ApiService : licence', () {
    test('licence trouvée, réponse vide = aucune licence', () => avecVraiHttp(() async {
          final ok = await api.lookupLicence();
          expect(ok.issue, isNull);
          expect(ok.licence!.dateEnd, '2099-12-31');
          srv.licence = const ReponseLocale('');
          final vide = await api.lookupLicence();
          expect((vide.issue, vide.licence), (null, null));
        }));

    test('5xx, 401 et 403 « Veuillez vous connecter » : problème de serveur, jamais « aucune licence »', () => avecVraiHttp(() async {
          for (final r in [FauxServeurPrestige.erreurServeur(500), FauxServeurPrestige.nonConnecte401, FauxServeurPrestige.nonConnecte403]) {
            srv.licence = r;
            final l = await api.lookupLicence();
            expect(l.issue, LicenceIssue.serverError, reason: 'HTTP ${r.statut}');
            expect(l.licence, isNull);
          }
          // 4.3.2 : 502 / 503 / 504 (Prestige en redémarrage) → serveur indisponible, jamais « aucune licence ».
          for (final code in [502, 503, 504]) {
            srv.licence = FauxServeurPrestige.erreurServeur(code);
            final l = await api.lookupLicence();
            expect(l.issue, LicenceIssue.unreachable, reason: 'HTTP $code');
            expect(l.licence, isNull);
          }
        }));

    test('404 : application absente (aucune route) ≠ application présente sans licence', () => avecVraiHttp(() async {
          srv.licence = const ReponseLocale({'message': 'introuvable'}, statut: 404);
          // POST /user/auth répond (200 success:false) : l'application Prestige est là → aucune licence.
          expect((await api.lookupLicence()).issue, isNull);
          srv.routes['POST /user/auth'] = (_) => const ReponseLocale('Not Found', statut: 404);
          expect((await api.lookupLicence()).issue, LicenceIssue.appNotFound);
        }));

    test('serveur coupé : injoignable ; LicenceProvider ne bloque pas une licence déjà connue et valide', () => avecVraiHttp(() async {
          final p = LicenceProvider(api);
          expect(await p.checkLicence(), LicenceStatus.valid);
          await srv.couper();
          expect((await api.lookupLicence()).issue, LicenceIssue.unreachable);
          expect(await p.checkLicence(), LicenceStatus.error);
          expect(p.errorTitle, 'Serveur indisponible, veuillez réessayer');
          expect(await p.mustBlockAccess(), isFalse, reason: 'coupure réseau : le travail continue');
          await srv.retablir();
          expect(await p.checkLicence(), LicenceStatus.valid);
        }));

    test('LicenceProvider : expirée, absente → accès bloqué', () => avecVraiHttp(() async {
          final p = LicenceProvider(api);
          srv.licence = ReponseLocale(DonneesFictives.licence(dateEnd: '2020-01-31'));
          expect(await p.checkLicence(), LicenceStatus.expired);
          expect(await p.mustBlockAccess(), isTrue);
          srv.licence = const ReponseLocale('');
          expect(await p.checkLicence(), LicenceStatus.none);
          expect(await p.mustBlockAccess(), isTrue);
        }));
  });

  group('ApiService et providers : connexion et données', () {
    test('connexion : cookie JSESSIONID posé puis envoyé ; identifiants refusés → null', () => avecVraiHttp(() async {
          expect(await api.login(DonneesFictives.login, 'faux'), isNull);
          expect(srv.connexions, 0);
          final u = await api.login(DonneesFictives.login, DonneesFictives.motDePasse);
          expect(u!.login, DonneesFictives.login);
          final o = await api.fetchOfficineInfo();
          expect(o, isNotNull);
          await api.getPreventes();
          expect(srv.recuesSur('/ventestats/preventes').single.jsessionid, srv.derniereSession);
          expect(srv.refusSession, 0);
        }));

    test('sans session : route protégée refusée (401) et requête non exécutée', () => avecVraiHttp(() async {
          srv.routes['GET /info'] = (_) => fail('la requête ne doit pas être exécutée sans session');
          await expectLater(api.fetchArticleAnalysisOrFail('para'), throwsA(isA<ApiLoadException>()));
          expect(srv.refusSession, 1);
        }));

    test('analyse article (GET /info) : lignes lues ; 5xx → erreur de chargement (≠ liste vide)', () => avecVraiHttp(() async {
          await connecter();
          final l = await api.fetchArticleAnalysisOrFail('9990001');
          expect(l.single.libelle, 'PARACETAMOL TEST 500MG CP B/16');
          srv.routes['GET /info'] = (_) => FauxServeurPrestige.erreurServeur(500);
          await expectLater(api.fetchArticleAnalysisOrFail('9990001'), throwsA(isA<ApiLoadException>()));
        }));

    test('BL du jour : liste vide ≠ panne (message d\'erreur gardé par le provider)', () => avecVraiHttp(() async {
          await connecter();
          final bl = BlControlProvider(api);
          await bl.fetchBonsLivraison(query: '');
          expect(bl.loadError, isNull);
          expect(bl.bonsLivraison, isEmpty);
          srv.routes['GET /commande/list-bons'] = (_) => FauxServeurPrestige.erreurServeur(502);
          await bl.fetchBonsLivraison(query: '');
          expect(bl.loadError, isNotNull);
        }));

    test('préventes en cours lues par le SaleProvider', () => avecVraiHttp(() async {
          await connecter();
          srv.routes['GET /ventestats/preventes'] = (_) => const ReponseLocale({
                'data': [
                  {'lgPREENREGISTREMENTID': 'P1', 'strREF': 'PV-001', 'intPRICE': 2400, 'heure': '09:10:00', 'dtUPDATED': '13/10/2026', 'userFullName': 'Awa Test', 'lgTYPEVENTEID': '1'}
                ]
              });
          final s = SaleProvider(api);
          await s.fetchPreventes();
          expect(s.preventes.single.strREF, 'PV-001');
        }));

    test('AuthProvider : connexion, connexion automatique (« Rester connecté »), déconnexion côté serveur', () => avecVraiHttp(() async {
          final auth = AuthProvider(api);
          expect(await auth.login(DonneesFictives.admin, DonneesFictives.motDePasseAdmin), isTrue);
          expect(auth.isAdmin, isTrue);
          await auth.logout();
          expect(auth.status, AuthStatus.Unauthenticated);
          expect(srv.sessions, isEmpty, reason: 'session fermée sur le serveur');
          expect(await auth.tryAutoLogin(), isFalse, reason: '« Rester connecté » désactivé par la déconnexion');

          SharedPreferences.setMockInitialValues({'stay_connected': true, 'saved_login': DonneesFictives.login});
          await IdentifiantsSecurises.instance.ecrire(DonneesFictives.motDePasse);
          final auto = AuthProvider(api);
          expect(await auto.tryAutoLogin(), isTrue);
          expect(auto.user!.login, DonneesFictives.login);
          expect(srv.connexions, 2);
        }));
  });

  group('Passerelle de vente (DioVenteGateway)', () {
    test('création au 1er article, 2e article, panier relu, net, prévente enregistrée', () => avecVraiHttp(() async {
          await connecter();
          final gw = DioVenteGateway(api);
          final page = await gw.searchProductsPage('para', 0, 30);
          final p = page.valueOrNull!.items.single;
          final id = (await gw.addItemVno(produitId: p.lgFAMILLEID, qte: 2, itemPu: p.intPRICE, prevente: true)).valueOrNull;
          expect(id, 'V-1');
          expect((await gw.addItemVno(produitId: p.lgFAMILLEID, qte: 1, itemPu: p.intPRICE, venteId: id, prevente: true)).valueOrNull, 'V-1');
          final lignes = (await gw.saleDetails('V-1')).valueOrNull!;
          expect(lignes.map((l) => l.intQUANTITY), [2, 1]);
          final net = (await gw.netVno('V-1')).valueOrNull!;
          expect(net.montantNet, 3600);
          expect((await gw.terminerPrevente('V-1')).isOk, isTrue);
          expect((await gw.fullSale('V-1')).valueOrNull!['strSTATUT'], 'is_Process');
        }));

    test('refus métier (200 success:false) ≠ panne (5xx) ≠ coupure', () => avecVraiHttp(() async {
          await connecter();
          final gw = DioVenteGateway(api);
          srv.routes['POST /vente/add/vno'] = (_) => FauxServeurPrestige.refus('Stock insuffisant');
          expect(await gw.addItemVno(produitId: 'PF-1', qte: 99, itemPu: 1200, prevente: true), isA<VenteRefused<String>>());
          srv.routes['POST /vente/add/vno'] = (_) => FauxServeurPrestige.erreurServeur(500);
          expect(await gw.addItemVno(produitId: 'PF-1', qte: 1, itemPu: 1200, prevente: true), isA<VenteFailed<String>>());
          await srv.couper();
          final r = await gw.saleDetails('V-1');
          expect(r, isA<VenteFailed>());
          expect(srv.ventes, isEmpty);
        }));
  });

  group('Transport en mémoire (temps simulé)', () {
    testWidgets('délai dépassé : licence « serveur injoignable » après le délai du client (10 s), sans attente réelle', (t) async {
      final m = FauxServeurPrestige()..licence = ReponseLocale(DonneesFictives.licence(), delai: const Duration(seconds: 30));
      m.installerEnMemoire();
      addTearDown(m.desinstaller);
      final a = ApiService(baseUrl: m.base);
      LicenceLookup? r;
      a.lookupLicence().then((v) => r = v);
      await t.pump(const Duration(seconds: 9));
      expect(r, isNull);
      await t.pump(const Duration(seconds: 2));
      expect(r!.issue, LicenceIssue.unreachable);
      await t.pump(const Duration(seconds: 30));
    });
  });
}
