// RÉSEAU — 4.15.0 : demande 62 en VRAI HTTP (faux serveur Prestige sur un port local), données FICTIVES :
//  - relecture de la prévente lente : bandeau après la réponse ; tronquée ou en panne : aucun bandeau (page
//    d'origine, le serveur reste juge à la clôture) ;
//  - clôture d'une prévente payée : réponse perdue → vente relue (terminée) et jamais de seconde clôture à l'aveugle ;
//    refus paiementMobile reçu lentement : message tel quel ;
//  - paiement de la borne : 403 puis cloturer:false sur un serveur lent ; serveur coupé : aucune nouvelle demande.
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/paiements/paiements_mobile.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../outils/clients_vente_fictifs.dart';
import '../outils/demande62_fictive.dart';
import '../outils/faux_serveur_prestige.dart';
import '../outils/remises_fictives.dart';

const _incomplet = ReponseLocale('{"success":tr', entetes: {'content-type': 'application/json; charset=utf-8'});

void main() {
  late FauxServeurPrestige srv;
  late Demande62Fictive d62;
  late ApiService api;

  setUp(() => avecVraiHttp(() async {
        SharedPreferences.setMockInitialValues({});
        srv = FauxServeurPrestige();
        ClientsVenteFictifs(srv);
        RemisesFictives(srv);
        d62 = Demande62Fictive(srv);
        await srv.demarrer();
        await DioClient.cookieJar.deleteAll();
        api = ApiService(baseUrl: srv.base);
        expect(await api.login(DonneesFictives.login, DonneesFictives.motDePasse), isNotNull);
      }));
  tearDown(() => avecVraiHttp(() async {
        await srv.arreter();
        await DioClient.cookieJar.deleteAll();
      }));

  Future<VenteController> reprise(String id) async {
    final c = VenteController(gateway: DioVenteGateway(api));
    await c.loadVente(id);
    return c;
  }

  test('relecture lente : bandeau après la réponse ; tronquée : aucun bandeau, page d\'origine', () => avecVraiHttp(() async {
        final id = d62.preventeDeLaBorne();
        final route = srv.routes['GET /ventestats/$id']!;
        srv.routes['GET /ventestats/$id'] = (r) async {
          final rep = await route(r);
          return ReponseLocale(rep.corps, delai: const Duration(milliseconds: 1200));
        };
        expect((await reprise(id)).preventePayee?.montant, 4125);
        srv.routes['GET /ventestats/$id'] = (_) => _incomplet;
        final c = await reprise(id);
        expect(c.preventePayee, isNull);
        expect(c.netUpToDate, isTrue, reason: 'le panier reste utilisable');
      }));

  test('clôture d\'une prévente payée, réponse perdue : vente relue (terminée), aucune seconde clôture', () => avecVraiHttp(() async {
        final id = d62.preventeDeLaBorne();
        final c = await reprise(id);
        final route = srv.routes['POST /vente/cloturer/vno']!;
        srv.routes['POST /vente/cloturer/vno'] = (r) async {
          await route(r); // clôture faite côté serveur…
          return _incomplet; // …mais la réponse est perdue
        };
        final r = await c.encaisser(method: PaymentMethod(id: '10', name: 'WAVE'), userId: 'U-FICT', expectedChanges: c.changes);
        expect(r.isOk, isTrue);
        expect(c.finished, isTrue);
        expect(d62.clotures, hasLength(1));
      }));

  test('refus paiementMobile reçu lentement : message tel quel, vente gardée', () => avecVraiHttp(() async {
        final id = d62.preventeDeLaBorne();
        final c = await reprise(id);
        final route = srv.routes['POST /vente/cloturer/vno']!;
        srv.routes['POST /vente/cloturer/vno'] = (r) async {
          final rep = await route(r);
          return ReponseLocale(rep.corps, delai: const Duration(milliseconds: 1500));
        };
        final r = await c.encaisser(method: PaymentMethod(id: '1', name: 'Espèces'), userId: 'U-FICT', expectedChanges: c.changes, montantRecu: 5000, montantRemis: 875);
        expect((r as VenteRefused).paiementMobile, isTrue);
        expect(r.message, contains('déjà payée par Wave'));
        expect(c.finished, isFalse);
        expect(c.preventePayee, isNotNull);
      }));

  test('borne : 403 sur un serveur lent → aucun repli (4.15.2) ; serveur coupé : une seule tentative', () => avecVraiHttp(() async {
        srv.droitsComptes = {DonneesFictives.login: ['P_SM_VENTE']};
        final id = d62.preventeDeLaBorne(payee: false);
        srv.latence = const Duration(milliseconds: 600);
        final pm = DioPaiementsMobileApi(() => api.dio);
        final a = AttentePaiement(pm);
        await a.demarrer(venteId: id, operateur: 'wave', cloturer: true);
        expect((a.interdit, a.paiement), (true, null));
        expect(d62.creations.map((c) => c['cloturer']), [true], reason: 'jamais cloturer:false');
        a.dispose();
        srv.latence = Duration.zero;
        await srv.arreter();
        final b = AttentePaiement(pm);
        await b.demarrer(venteId: id, operateur: 'wave', cloturer: true);
        expect((b.paiement, b.interdit, b.refusAvantPaiement), (null, false, false));
        expect(b.erreur, contains('injoignable'));
        b.dispose();
      }));
}
