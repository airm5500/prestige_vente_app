// 4.5.1 — Droits de vente (demande du serveur du 19/10/2026, docs/serveur/DEMANDE_SERVEUR_DROITS_VENTE_2026-10-19.md) :
// règles de droits, repli sans la route, lecture de GET v1/user/droits (mémoire seulement), 403 `interdit` (message,
// vente gardée, jamais une déconnexion), 409 `sessionChangee`, en-tête X-Prestige-Utilisateur, vente à reprendre
// liée à son compte, ventes hors ligne envoyées sous la session de leur compte, blocage à la source hors ligne.
// Données fictives uniquement.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/api/utilisateur_session.dart';
import 'package:prestige_vente_app/droits/droits_vente.dart';
import 'package:prestige_vente_app/horsligne/vente_hors_ligne.dart';
import 'package:prestige_vente_app/horsligne/ventes_sync.dart';
import 'package:prestige_vente_app/paiements/paiements_mobile.dart';
import 'package:prestige_vente_app/ventes/core/pending_sale_store.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'outils/serveur_json_local.dart';

ReponseLocale _interdit([String m = 'Droit manquant : terminer une vente.']) =>
    ReponseLocale({'success': false, 'interdit': true, 'msg': m}, statut: 403);
const _change = ReponseLocale({'success': false, 'sessionChangee': true, 'msg': 'Un autre compte (admin) s\'est connecté.'}, statut: 409);

void main() {
  setUp(() {
    DroitsVente.instance.oublier();
    UtilisateurSession.id = null;
    SessionChangee.instance = SessionChangee();
  });
  tearDown(() {
    DroitsVente.instance.oublier();
    UtilisateurSession.id = null;
  });

  group('Règles des droits', () {
    test('repli (droits inconnus, serveur sans la route) : tout est permis comme avant', () {
      final d = DroitsVente();
      expect(d.connus, isFalse);
      expect(d.terminerVente, isTrue);
      expect(d.cloturerPaiementMobile, isTrue);
      expect(d.venteDepot, isTrue);
      expect(d.annulerVente, isTrue);
      expect(d.preventeSeule, isFalse);
      d.fixer(null);
      expect(d.routeAbsente, isTrue);
      expect(d.terminerVente, isTrue);
    });

    test('profil « Pre-vente » : ne peut ni terminer, ni clôturer par mobile money, ni dépôt, ni annuler', () {
      final d = DroitsVente()..fixer({'P_SM_VENTE', 'P_PREVENTE'});
      expect(d.preventeSeule, isTrue);
      expect(d.terminerVente, isFalse);
      expect(d.cloturerPaiementMobile, isFalse);
      expect(d.venteDepot, isFalse);
      expect(d.annulerVente, isFalse);
    });

    test('l\'un des trois droits suffit pour terminer une vente (et le paiement mobile avec clôture)', () {
      for (final droit in DroitsVente.terminerVenteDroits) {
        final d = DroitsVente()..fixer({droit});
        expect(d.terminerVente, isTrue, reason: droit);
        expect(d.cloturerPaiementMobile, isTrue, reason: droit);
      }
      expect(DroitsVente.terminerVenteDroits, {'P_SM_CLOTURER_CAISSE', 'P_SM_DEPOT_EXTENSION', 'P_BT_MODIFICATION_DE_VENTE'});
    });

    test('vente en dépôt : P_SM_VENTEDEPOT, P_SM_DEPOT_EXTENSION ou P_SM_CLOTURER_CAISSE ; annulation : P_BT_ANNULER_VENTE', () {
      expect(DroitsVente.venteDepotDroits, {'P_SM_VENTEDEPOT', 'P_SM_DEPOT_EXTENSION', 'P_SM_CLOTURER_CAISSE'});
      expect((DroitsVente()..fixer({'P_SM_VENTEDEPOT'})).venteDepot, isTrue);
      expect((DroitsVente()..fixer({'P_SM_VENTEDEPOT'})).terminerVente, isFalse);
      expect((DroitsVente()..fixer({'P_BT_MODIFICATION_DE_VENTE'})).venteDepot, isFalse);
      expect((DroitsVente()..fixer({'P_BT_ANNULER_VENTE'})).annulerVente, isTrue);
    });
  });

  group('Lecture de GET v1/user/droits (mémoire seulement)', () {
    test('liste lue ; route absente (404) → repli ; échec réseau → dernière lecture gardée ; autre compte → oubliés', () async {
      await avecVraiHttp(() async {
        final s = ServeurJsonLocal();
        await s.demarrer();
        addTearDown(s.arreter);
        final dio = Dio(BaseOptions(baseUrl: s.base));
        s.routes['GET /user/droits'] = (_) => const ReponseLocale({'success': true, 'profil': 'mainmenumanager', 'droits': ['P_SM_VENTE']});
        final d = DroitsVente();
        await d.actualiser(dio, utilisateur: 'U-awa');
        expect(d.connus, isTrue);
        expect(d.preventeSeule, isTrue);
        expect(d.droits, {'P_SM_VENTE'});
        // Panne : dernière lecture gardée (hors ligne).
        s.routes['GET /user/droits'] = (_) => const ReponseLocale('<html>500</html>', statut: 500);
        await d.actualiser(dio, utilisateur: 'U-awa');
        expect(d.preventeSeule, isTrue);
        // Autre compte : droits du précédent oubliés avant la lecture.
        s.routes['GET /user/droits'] = (_) => const ReponseLocale({'success': false}, statut: 404);
        await d.actualiser(dio, utilisateur: 'U-admin');
        expect(d.connus, isFalse);
        expect(d.routeAbsente, isTrue);
        expect(d.terminerVente, isTrue, reason: 'serveur ancien : comportement d\'avant');
        expect(d.lectures, 3);
      });
    });

    test('aucune écriture sur l\'appareil : les droits ne sont jamais dans les préférences', () async {
      SharedPreferences.setMockInitialValues({});
      final d = DroitsVente()..fixer({'P_SM_CLOTURER_CAISSE'});
      expect(d.terminerVente, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => '${prefs.get(k)}'.contains('P_SM_')), isEmpty);
    });
  });

  group('Réponses de sécurité du serveur', () {
    test('403 interdit → message ; autre 403 (filtre de connexion) → null ; 409 sessionChangee → message', () {
      expect(refusDeDroit(403, {'success': false, 'interdit': true, 'msg': 'Droit manquant'}), 'Droit manquant');
      expect(refusDeDroit(403, '{"interdit":true,"msg":"Refusé"}'), 'Refusé');
      expect(refusDeDroit(403, 'Veuillez vous connecter'), isNull);
      expect(refusDeDroit(401, {'interdit': true}), isNull);
      expect(refusDeDroit(403, {'interdit': true}), contains('administrateur'));
      expect(sessionChangeeDe(409, {'sessionChangee': true, 'msg': 'Autre compte'}), 'Autre compte');
      expect(sessionChangeeDe(409, {'success': false}), isNull);
      expect(sessionChangeeDe(200, {'sessionChangee': true}), isNull);
    });

    test('passerelle des ventes : 403 interdit = refus « interdit » (vente gardée, aucune relance), 409 = échec sans effet', () async {
      await avecVraiHttp(() async {
        final s = ServeurJsonLocal();
        await s.demarrer();
        addTearDown(s.arreter);
        s.routes['POST /vente/cloturer/vno'] = (_) => _interdit();
        final gw = DioVenteGateway(ApiService(baseUrl: s.base));
        final summary = SaleSummary(montant: 1000, montantNet: 1000, reference: 'R', venteId: 'V1');
        final r = await gw.cloturerVno(venteId: 'V1', summary: summary, typeReglementId: '1', clientId: 'especes', userVendeurId: 'U-awa');
        expect(r, isA<VenteRefused<Map<String, dynamic>>>());
        expect((r as VenteRefused).interdit, isTrue);
        expect(r.message, 'Droit manquant : terminer une vente.');
        expect(r.uncertain, isFalse, reason: 'rien n\'a été enregistré : pas de vérification ni de relance');
        expect(s.recuesSur('/vente/cloturer/vno'), hasLength(1));
        s.routes['POST /vente/cloturer/vno'] = (_) => _change;
        final r2 = await gw.cloturerVno(venteId: 'V1', summary: summary, typeReglementId: '1', clientId: 'especes', userVendeurId: 'U-awa');
        expect(r2, isA<VenteFailed<Map<String, dynamic>>>());
        expect(r2.uncertain, isFalse, reason: 'non exécuté');
        expect(r2.message, contains('Un autre compte'));
      });
    });

    test('ancienne interface : 403 interdit → {success:false, interdit:true, msg} ; dépôt : message du refus', () async {
      await avecVraiHttp(() async {
        final s = ServeurJsonLocal();
        await s.demarrer();
        addTearDown(s.arreter);
        s.routes['POST /vente/cloturer/vno'] = (_) => _interdit('Refus vente');
        s.routes['POST /vente/clotureVenteDepot'] = (_) => _interdit('Refus dépôt');
        final api = ApiService(baseUrl: s.base);
        final r = await api.cloturerVente(
            venteId: 'V1', summary: SaleSummary(montant: 1, montantNet: 1, reference: '', venteId: 'V1'), typeReglementId: '1', clientId: 'x', userVendeurId: 'u');
        expect(r, {'success': false, 'msg': 'Refus vente', 'interdit': true});
        expect(await api.closeDepotSale(venteId: 'V1', clientId: 'D1'), isFalse);
        expect(api.dernierRefusSecurite, 'Refus dépôt');
      });
    });

    test('paiement mobile money avec clôture : 403 interdit → refus « interdit », attente marquée (pas de nouvel essai)', () async {
      await avecVraiHttp(() async {
        final s = ServeurJsonLocal();
        await s.demarrer();
        addTearDown(s.arreter);
        s.routes['POST /paiements-mobile'] = (_) => _interdit('Clôture refusée');
        final api = DioPaiementsMobileApi(() => Dio(BaseOptions(baseUrl: s.base)));
        final r = await api.creer(venteId: 'V1', operateur: 'wave', cloturer: true, cle: 'k');
        expect((r as VenteRefused).interdit, isTrue);
        final a = AttentePaiement(api);
        await a.demarrer(venteId: 'V1', operateur: 'wave', cloturer: true);
        expect(a.interdit, isTrue);
        expect(a.paiement, isNull);
        expect(a.erreur, 'Clôture refusée');
        a.dispose();
        expect(s.recuesSur('/paiements-mobile'), hasLength(2));
      });
    });
  });

  group('En-tête X-Prestige-Utilisateur et 409', () {
    test('envoyé sur chaque requête avec le str_USER_ID de la connexion ; jamais sur /user/auth ; absent sans compte', () async {
      await avecVraiHttp(() async {
        final vus = <String, String>{};
        final s = ServeurJsonLocal();
        await s.demarrer();
        addTearDown(s.arreter);
        for (final k in ['GET /officine', 'POST /user/auth', 'GET /vente/search']) {
          s.routes[k] = (r) {
            vus[k] = r.utilisateur;
            return const ReponseLocale({'success': true});
          };
        }
        final dio = IntercepteurUtilisateur.brancher(Dio(BaseOptions(baseUrl: s.base)));
        expect(dio.interceptors.whereType<IntercepteurUtilisateur>(), hasLength(1));
        IntercepteurUtilisateur.brancher(dio);
        expect(dio.interceptors.whereType<IntercepteurUtilisateur>(), hasLength(1), reason: 'jamais en double');
        await dio.get('/officine');
        expect(vus['GET /officine'], '', reason: 'personne de connecté');
        UtilisateurSession.id = 'U-awa';
        await dio.post('/user/auth', data: {});
        await dio.get('/vente/search');
        expect(vus['POST /user/auth'], '');
        expect(vus['GET /vente/search'], 'U-awa');
      });
    });

    test('409 sessionChangee : l\'application est prévenue UNE fois par rafale', () async {
      await avecVraiHttp(() async {
        final s = ServeurJsonLocal();
        await s.demarrer();
        addTearDown(s.arreter);
        s.routes['GET /vente/search'] = (_) => _change;
        final messages = <String>[];
        SessionChangee.instance.traiter = (m) async {
          messages.add(m);
          await Future<void>.delayed(const Duration(milliseconds: 50));
        };
        final dio = IntercepteurUtilisateur.brancher(Dio(BaseOptions(baseUrl: s.base, validateStatus: (_) => true)));
        UtilisateurSession.id = 'U-awa';
        await Future.wait([dio.get('/vente/search'), dio.get('/vente/search'), dio.get('/vente/search')]);
        await SessionChangee.instance.attendre();
        expect(SessionChangee.instance.recus, 3);
        expect(messages, ['Un autre compte (admin) s\'est connecté.']);
      });
    });

    test('client partagé, client commun (Réserve, Posos…) : intercepteur branché', () {
      final api = ApiService(baseUrl: 'http://x');
      expect(api.dio.interceptors.whereType<IntercepteurUtilisateur>(), hasLength(1));
    });
  });

  group('Un compte, un panier', () {
    test('vente à reprendre : jamais proposée à un AUTRE compte (effacée), proposée à son compte', () async {
      SharedPreferences.setMockInitialValues({});
      UtilisateurSession.id = 'U-awa';
      await PendingSaleStore.save(VenteMenu.prevente, PendingSale(venteId: 'V9', savedAt: DateTime(2026, 10, 19)));
      expect((await PendingSaleStore.load(VenteMenu.prevente))?.venteId, 'V9');
      UtilisateurSession.id = 'U-admin';
      expect(await PendingSaleStore.load(VenteMenu.prevente), isNull);
      UtilisateurSession.id = 'U-awa';
      expect(await PendingSaleStore.load(VenteMenu.prevente), isNull, reason: 'effacée dès qu\'un autre compte l\'a vue');
      await PendingSaleStore.save(VenteMenu.assurance, PendingSale(venteId: 'A1', savedAt: DateTime(2026, 10, 19)));
      await PendingSaleStore.toutEffacer();
      expect(await PendingSaleStore.load(VenteMenu.assurance), isNull);
    });

    test('ventes hors ligne : envoyées seulement sous la session de leur compte ; ancienne vente sans compte : comme avant', () {
      final f = FileVentesHL(store: MemoryVentesHLStore());
      VenteHorsLigne v(String user) => VenteHorsLigne(
          id: user, numero: 1, type: TypeVenteHL.comptant, lignes: const [], fin: FinVenteHL.especes, totalEstime: 0, netEstime: 0, createdAt: DateTime(2026, 10, 19), updatedAt: DateTime(2026, 10, 19), userId: user);
      f.compteCourant = () => 'U-awa';
      expect(f.duCompteCourant(v('U-awa')), isTrue);
      expect(f.duCompteCourant(v('U-admin')), isFalse);
      expect(f.duCompteCourant(v('')), isTrue);
      f.compteCourant = () => null;
      expect(f.duCompteCourant(v('U-admin')), isTrue, reason: 'compte inconnu (tests, avant connexion)');
    });
  });
}
