// PERFORMANCE — 4.15.2 : réponse du serveur à la demande 64, données FICTIVES, VRAI HTTP :
//  - borne, caisse fermée : UNE requête (POST paiements-mobile), aucune interrogation du statut ensuite, refus reçu en
//    moins de 2 s ; serveur déployé : même nombre de requêtes qu'en 4.15.1 pour créer le paiement ;
//  - comptoir, panier verrouillé : UNE requête par modification refusée (aucune relecture du panier ni du net), en
//    moins de 2 s ; 200 refus de suite sans fuite ni ralentissement (moins de 15 ms en moyenne) ;
//  - verrou levé : modification + relecture du panier et du net, comme en 4.15.1.
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/paiements/paiements_mobile.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../outils/clients_vente_fictifs.dart';
import '../outils/demande62_fictive.dart';
import '../outils/demande64_fictive.dart';
import '../outils/faux_serveur_prestige.dart';

void main() {
  late FauxServeurPrestige srv;
  late Demande64Fictive d64;
  late ApiService api;

  setUp(() => avecVraiHttp(() async {
        SharedPreferences.setMockInitialValues({});
        srv = FauxServeurPrestige();
        ClientsVenteFictifs(srv);
        d64 = Demande64Fictive(srv);
        srv.droitsComptes = {DonneesFictives.login: ['P_SM_VENTE', droitBorne]};
        await srv.demarrer();
        await DioClient.cookieJar.deleteAll();
        api = ApiService(baseUrl: srv.base);
        expect(await api.login(DonneesFictives.login, DonneesFictives.motDePasse), isNotNull);
      }));
  tearDown(() => avecVraiHttp(() async {
        await srv.arreter();
        await DioClient.cookieJar.deleteAll();
      }));

  List<String> depuis(int n) => srv.recues.sublist(n).map((r) => '${r.methode} ${r.chemin.replaceAll(RegExp(r'^.*/api/v1'), '')}').toList();

  for (final d64Actif in [true, false]) {
    test('borne : ${d64Actif ? 'caisse fermée → 1 requête, aucun suivi, < 2 s' : 'serveur déployé → paiement créé en 1 requête (4.15.1)'}', () => avecVraiHttp(() async {
          d64.d64 = d64Actif;
          final id = d64.d62.preventeDeLaBorne(payee: false);
          final a = AttentePaiement(DioPaiementsMobileApi(() => api.dio), intervalle: const Duration(hours: 1));
          final n = srv.recues.length;
          final sw = Stopwatch()..start();
          await a.demarrer(venteId: id, operateur: 'wave', cloturer: true);
          sw.stop();
          expect(depuis(n), ['POST /paiements-mobile']);
          expect(a.refusAvantPaiement, d64Actif);
          expect(sw.elapsedMilliseconds, lessThan(2000));
          if (d64Actif) {
            await a.interroger();
            expect(depuis(n), ['POST /paiements-mobile'], reason: 'aucune interrogation du statut');
          }
          a.dispose();
        }));
  }

  test('comptoir : 1 requête par modification refusée, aucune relecture ; < 2 s', () => avecVraiHttp(() async {
        final id = d64.d62.preventeDeLaBorne();
        final c = VenteController(gateway: DioVenteGateway(api));
        await c.loadVente(id);
        final ligne = c.items.single;
        final n = srv.recues.length;
        final sw = Stopwatch()..start();
        expect((await c.updateLine(ligne, 2, 4125)).isOk, isFalse);
        expect((await c.removeLine(ligne)).isOk, isFalse);
        sw.stop();
        expect(depuis(n), ['POST /vente/update/item/vno', 'POST /vente/remove/vno/item/${ligne.lgPREENREGISTREMENTDETAILID}']);
        expect(sw.elapsedMilliseconds, lessThan(2000));
      }));

  test('comptoir : 200 refus de suite, moins de 15 ms en moyenne, panier inchangé', () => avecVraiHttp(() async {
        final id = d64.d62.preventeDeLaBorne();
        final gw = DioVenteGateway(api);
        final l = (await gw.saleDetails(id)).valueOrNull!.single;
        final sw = Stopwatch()..start();
        for (var i = 0; i < 200; i++) {
          final r = await gw.updateItem(itemId: l.lgPREENREGISTREMENTDETAILID, produitId: 'F1', qte: 2, itemPu: 4125);
          expect((r as VenteRefused).panierVerrouille, isTrue);
        }
        sw.stop();
        expect(sw.elapsedMilliseconds / 200, lessThan(15));
        expect(srv.ventes[id]!.single['intQUANTITY'], 1);
      }));

  test('verrou levé : modification puis panier et net relus (mêmes requêtes qu\'en 4.15.1)', () => avecVraiHttp(() async {
        final id = d64.d62.preventeDeLaBorne(payee: false);
        final c = VenteController(gateway: DioVenteGateway(api));
        await c.loadVente(id);
        final n = srv.recues.length;
        expect((await c.updateLine(c.items.single, 2, 4125)).isOk, isTrue);
        final r = depuis(n);
        expect(r.first, 'POST /vente/update/item/vno');
        expect(r.where((x) => x == 'GET /vente/deatails'), hasLength(1));
        expect(r.where((x) => x == 'POST /vente/net/vno'), hasLength(1));
      }));
}
