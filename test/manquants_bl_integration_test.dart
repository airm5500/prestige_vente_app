// INTÉGRATION — Prestige Mobile 4.12.0 (demande 59) : passerelle de l'application (OfflineReceptionGateway autour du
// client HTTP DioReceptionGateway) contre le faux serveur Prestige, données FICTIVES.
//  - en ligne : capacités, écarts, clôture au reçu et retour des manquants passent au serveur, X-Client-Ref compris ;
//  - hors ligne : rien n'est envoyé ni mis dans la file d'envoi (clôture et retour en ligne seulement), capacités
//    absentes (aucun bouton), message « en ligne uniquement ».
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/horsligne/catalogue_sync.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart';
import 'package:prestige_vente_app/horsligne/server_monitor.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_gateways.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_horsligne.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_store.dart';
import 'package:prestige_vente_app/horsligne/vente_hors_ligne.dart';
import 'package:prestige_vente_app/horsligne/ventes_sync.dart';
import 'package:prestige_vente_app/reception/reception_gateway.dart';

import 'outils/faux_serveur_prestige.dart';

void main() {
  late FauxServeurPrestige srv;
  late HorsLigne hl;
  late StockHorsLigne stock;

  setUp(() => avecVraiHttp(() async {
        srv = FauxServeurPrestige();
        await srv.demarrer();
        await DioClient.cookieJar.deleteAll();
        expect(await ApiService(baseUrl: srv.base).login(DonneesFictives.login, DonneesFictives.motDePasse), isNotNull);
        final local = MemoryLocalStore();
        hl = HorsLigne(
            monitor: ServerMonitor(), store: local, sync: CatalogueSync(store: local), ventes: FileVentesHL(store: MemoryVentesHLStore()));
        stock = StockHorsLigne(store: MemoryStockStore());
        stock.attach(hl);
        final avant = HorsLigne.instance;
        HorsLigne.instance = hl;
        addTearDown(() => HorsLigne.instance = avant);
        srv.routes['GET /reception/parametres'] = (_) => FauxServeurPrestige.ok({'success': true, 'clotureRecu': true, 'retourManquants': true});
        srv.routes['GET /reception/BL1/ecarts'] = (_) => FauxServeurPrestige.ok({
              'success': true,
              'mode': 'RECU',
              'ecarts': [
                {'detailId': 'D1', 'cip': '3595583', 'nom': 'PRODUIT FICTIF', 'commande': 4, 'recu': 1, 'ug': 0, 'manquant': 3}
              ],
              'totalManquant': 3,
              'retourManquants': null
            });
        srv.routes['PUT /commande/validerbl/BL1'] = (_) => FauxServeurPrestige.ok({'success': true, 'mode': 'RECU', 'msg': 'ok', 'ecarts': [], 'totalManquant': 0});
        srv.routes['POST /reception/BL1/retour-manquants'] =
            (_) => FauxServeurPrestige.ok({'success': true, 'deja': false, 'retourId': 'R1', 'ref': 'RF-0001', 'statut': 'is_Waiting', 'lignes': 1, 'totalManquant': 3});
      }));
  tearDown(() => avecVraiHttp(() async {
        await srv.arreter();
        await DioClient.cookieJar.deleteAll();
      }));

  OfflineReceptionGateway gw() => OfflineReceptionGateway(DioReceptionGateway(DioClient.getClient(srv.base)), stock: stock);

  test('en ligne : tout passe au serveur, X-Client-Ref compris', () => avecVraiHttp(() async {
        final g = gw();
        expect(await g.clotureRecuDisponible(), isTrue);
        expect(await g.retourManquantsDisponible(), isTrue);
        expect((await g.ecartsBl('BL1')).totalManquant, 3);
        expect((await g.validateRecu('BL1', clientRef: 'BLR-int-1')).success, isTrue);
        expect(srv.recuesSur('/commande/validerbl/BL1').single.clientRef, 'BLR-int-1');
        expect((await g.creerRetourManquants('BL1', clientRef: 'BLM-int-1')).ref, 'RF-0001');
        expect(srv.recuesSur('/reception/BL1/retour-manquants').single.clientRef, 'BLM-int-1');
        expect(stock.queue.ops, isEmpty, reason: 'rien dans la file d\'envoi');
      }));

  test('hors ligne : capacités absentes, rien envoyé, rien dans la file', () => avecVraiHttp(() async {
        hl.monitor.goOffline();
        final g = gw();
        final avant = srv.recues.length;
        expect(await g.clotureRecuDisponible(), isFalse);
        expect(await g.retourManquantsDisponible(), isFalse);
        final e = await g.ecartsBl('BL1');
        expect(e.success, isFalse);
        expect(e.message, contains('en ligne uniquement'));
        final r = await g.creerRetourManquants('BL1', clientRef: 'BLM-int-2');
        expect(r.success, isFalse);
        expect(r.texte, contains('en ligne uniquement'));
        expect((await g.validateRecu('BL1', clientRef: 'BLR-int-2')).success, isFalse);
        expect(srv.recues.length, avant, reason: 'aucune requête hors ligne');
        expect(stock.queue.ops, isEmpty);
      }));
}
