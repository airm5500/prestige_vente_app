// RÉSEAU — 4.9.2 : étiquette étendue (DataMatrix+, QR+) refusée sur l'appareil, en vrai HTTP vers le faux serveur
// Prestige (données FICTIVES) : lecture GS1 inactive, réglage absent (404), active ou serveur coupé → refus SANS
// AUCUNE requête (ni vente/gs1, ni recherche de produit) ; étiquette normale, lecture inactive → recherche d'avant.
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/api/models/depot_model.dart';
import 'package:prestige_vente_app/api/utilisateur_session.dart';
import 'package:prestige_vente_app/providers/depot_sale_provider.dart';
import 'package:prestige_vente_app/ventes/core/gs1_recherche.dart';
import 'package:prestige_vente_app/ventes/core/gs1_vente.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';

import '../outils/faux_serveur_prestige.dart';
import '../outils/parcours_vente.dart';

final _doli = {...produitFictif(83), 'lgFAMILLEID': 'F83', 'strNAME': 'DOLI FICTIF 1000 CPR B/8', 'intCIP': '3400935955838'};
const _dmPlus = '0103400935955838\u001d17281031\u001d10LOTA1\u001d91EPLUS1\u001d92DOLI_FICTIF';
const _qrPlus = 'EP1|CIP:3400935955838|NOM:DOLI FICTIF|LOT:LOTA1';
const _dm = '01034009359558381728103110LOTA1';

void main() {
  late FauxServeurPrestige srv;
  late ApiService api;
  late DioVenteGateway gw;
  String? lecture = '0';
  Future<VenteResult<ProductPage>> recherche(String q, int s, int l) => gw.searchProductsPage(q, s, l);

  setUp(() => avecVraiHttp(() async {
        lecture = '0';
        srv = FauxServeurPrestige();
        CatalogueFictif(srv, nombre: 10).produits.add(_doli);
        srv.routes['GET /app-params/value/KEY_VENTE_LECTURE_GS1'] =
            (_) => lecture == null ? FauxServeurPrestige.payara404 : FauxServeurPrestige.ok({'success': true, 'data': lecture, 'total': 1});
        srv.routes['GET /vente/gs1'] = (_) => FauxServeurPrestige.ok({'success': true, 'actif': true, 'cip': '3400935955838', 'controle': 'CONFORME'});
        await srv.demarrer();
        await DioClient.cookieJar.deleteAll();
        api = ApiService(baseUrl: srv.base);
        expect(await api.login(DonneesFictives.login, DonneesFictives.motDePasse), isNotNull);
        UtilisateurSession.id = 'U-${DonneesFictives.login}';
        gw = DioVenteGateway(api);
        Gs1Vente.instance.dio = () => api.dio;
        Gs1Vente.instance.horsLigne = () => false;
      }));
  tearDown(() => avecVraiHttp(() async {
        await srv.arreter();
        await DioClient.cookieJar.deleteAll();
        UtilisateurSession.id = null;
      }));

  for (final (cas, l) in <(String, String?)>[('lecture inactive', '0'), ('réglage absent (404)', null), ('lecture active', '1')]) {
    test('$cas : DataMatrix+ et QR+ refusés sans aucune requête', () => avecVraiHttp(() async {
          lecture = l;
          await Gs1Vente.instance.relireReglage(api.dio);
          final avant = srv.recues.length;
          for (final e in [_dmPlus, _qrPlus]) {
            final r = (await rechercherEtiquetteGs1(e, recherche))!;
            expect(r.refus?.message, Gs1Refus.messageEtendue);
          }
          expect(srv.recues.length, avant, reason: 'reconnue sur l\'appareil');
        }));
  }

  test('4.9.3 — Dépôt, lecture active : étiquette étendue jamais envoyée à vente/gs1, recherche d\'avant, ligne sans lotScanne',
      () => avecVraiHttp(() async {
            lecture = '1';
            srv.routes['POST /vente/add/depot'] =
                (_) => FauxServeurPrestige.ok({'success': true, 'data': {'lgPREENREGISTREMENTID': 'D-1', 'strREF': 'DEP-1'}});
            await Gs1Vente.instance.relireReglage(api.dio);
            expect(Gs1Vente.instance.actif, isTrue);
            final p = DepotSaleProvider(api)
              ..selectDepot(DepotModel.fromJson(const {'lgCLIENTID': 'D1', 'strNAME': 'DEPOT FICTIF', 'lgEMPLACEMENTID': 'E2', 'lgTYPEDEPOTID': 'T1'}));
            await p.searchProducts(_qrPlus);
            expect(p.productSearch.refusGs1, isNull);
            expect(p.searchResults, isEmpty);
            await p.searchProducts(_dmPlus);
            expect(p.productSearch.refusGs1, isNull);
            expect(p.searchResults.single.lgFAMILLEID, 'F83');
            expect(srv.recuesSur('/vente/gs1'), isEmpty);
            expect(await p.addToCart(p.searchResults.single), isTrue);
            expect(srv.recuesSur('/vente/add/depot').single.json.containsKey('lotScanne'), isFalse);
          }));

  test('serveur coupé : refus quand même (détection locale)', () => avecVraiHttp(() async {
        await Gs1Vente.instance.relireReglage(api.dio);
        await srv.couper();
        final r = (await rechercherEtiquetteGs1(_qrPlus, recherche))!;
        expect(r.refus?.message, Gs1Refus.messageEtendue);
      }));

  test('lecture inactive, étiquette normale : recherche d\'avant, jamais vente/gs1', () => avecVraiHttp(() async {
        await Gs1Vente.instance.relireReglage(api.dio);
        final r = (await rechercherEtiquetteGs1(_dm, recherche))!;
        expect(r.refus, isNull);
        expect(r.produits.single.lgFAMILLEID, 'F83');
        final ref = (await ProductLookup.byCode(_dm, recherche)).valueOrNull!;
        expect(r.essayes, ref.tried);
        expect(srv.recuesSur('/vente/gs1'), isEmpty);
      }));
}
