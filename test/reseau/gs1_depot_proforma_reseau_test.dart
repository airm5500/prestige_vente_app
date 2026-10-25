// RÉSEAU — 4.9.1 : lecture GS1 des ventes Dépôt et Proforma, en vrai HTTP vers le faux serveur Prestige (données
// FICTIVES) : verdict GET v1/vente/gs1 avec la session ; mode B lot en stock → ligne ajoutée SANS `lotScanne`
// (POST v1/vente/add/depot, POST v1/vente/devis) ; refus → aucune ligne ; 404 / 500 / délai / coupure de vente/gs1 →
// produit trouvé comme avant, au plus tard après le délai du scan.
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/api/models/depot_model.dart';
import 'package:prestige_vente_app/api/models/proforma_models.dart';
import 'package:prestige_vente_app/api/utilisateur_session.dart';
import 'package:prestige_vente_app/providers/depot_sale_provider.dart';
import 'package:prestige_vente_app/providers/proforma_provider.dart';
import 'package:prestige_vente_app/ventes/core/gs1_vente.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../outils/faux_serveur_prestige.dart';
import '../outils/parcours_vente.dart';

final _doli = {...produitFictif(83), 'lgFAMILLEID': 'F83', 'strNAME': 'DOLI FICTIF 1000 CPR B/8', 'intCIP': '3400935955838'};
const _dm = '01034009359558381728103110LOTA1';

Map<String, dynamic> _verdict({String mode = 'B', bool perime = false}) => {
      'success': true,
      'actif': true,
      'lot': 'LOTA1',
      'peremption': perime ? '31/01/2020' : '31/10/2028',
      'perime': perime,
      'cip': '3400935955838',
      'lotPrevu': 'LOTB2',
      'peremptionPrevue': '30/06/2028',
      'controle': 'DIFFERENT',
      'modeControle': mode,
      'lotEnStock': true,
      'data': {'lgFAMILLEID': 'F83'},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FauxServeurPrestige srv;
  late ApiService api;
  int statutGs1 = 200;
  Duration delaiGs1 = Duration.zero;
  Map<String, dynamic> verdict = _verdict();

  setUp(() => avecVraiHttp(() async {
        SharedPreferences.setMockInitialValues({});
        statutGs1 = 200;
        delaiGs1 = Duration.zero;
        verdict = _verdict();
        srv = FauxServeurPrestige();
        CatalogueFictif(srv, nombre: 10).produits.add(_doli);
        srv.routes['GET /app-params/value/KEY_VENTE_LECTURE_GS1'] = (_) => FauxServeurPrestige.ok({'success': true, 'data': '1', 'total': 1});
        srv.routes['GET /vente/gs1'] = (_) =>
            statutGs1 != 200 ? ReponseLocale('<html>$statutGs1</html>', statut: statutGs1) : FauxServeurPrestige.ok(verdict, delai: delaiGs1);
        srv.routes['POST /vente/add/depot'] =
            (_) => FauxServeurPrestige.ok({'success': true, 'data': {'lgPREENREGISTREMENTID': 'D-1', 'strREF': 'DEP-1'}});
        srv.routes['POST /vente/devis'] =
            (_) => FauxServeurPrestige.ok({'success': true, 'data': {'lgPREENREGISTREMENTID': 'P-1', 'strREF': 'DEV-1'}});
        await srv.demarrer();
        await DioClient.cookieJar.deleteAll();
        api = ApiService(baseUrl: srv.base);
        expect(await api.login(DonneesFictives.login, DonneesFictives.motDePasse), isNotNull);
        UtilisateurSession.id = 'U-${DonneesFictives.login}';
        Gs1Vente.instance.dio = () => api.dio;
        Gs1Vente.instance.horsLigne = () => false;
        await Gs1Vente.instance.relireReglage(api.dio);
        expect(Gs1Vente.instance.actif, isTrue);
      }));
  tearDown(() => avecVraiHttp(() async {
        await srv.arreter();
        await DioClient.cookieJar.deleteAll();
        UtilisateurSession.id = null;
      }));

  DepotSaleProvider depot() => DepotSaleProvider(api)
    ..selectDepot(DepotModel.fromJson(const {'lgCLIENTID': 'D1', 'strNAME': 'DEPOT FICTIF', 'lgEMPLACEMENTID': 'E2', 'lgTYPEDEPOTID': 'T1'}));
  ProformaProvider proforma() => ProformaProvider(api)
    ..setTypeDevis(TypeDevis(lgTYPEVENTEID: '1', strNAME: 'VENTE AU COMPTANT', strDESCRIPTION: ''))
    ..setClient(ClientModel(lgCLIENTID: 'C1', strFIRSTNAME: 'CLIENT', strLASTNAME: 'FICTIF'));

  test('dépôt, mode B lot en stock : verdict avec la session, ligne SANS lotScanne', () => avecVraiHttp(() async {
        final p = depot();
        await p.searchProducts(_dm);
        expect(p.searchResults.single.lgFAMILLEID, 'F83');
        expect(p.productSearch.avertissementGs1, contains('Lot différent'));
        final appel = srv.recuesSur('/vente/gs1').single;
        expect(appel.query['code'], _dm);
        expect(appel.jsessionid, isNotNull);
        expect(await p.addToCart(p.searchResults.single), isTrue);
        final a = srv.recuesSur('/vente/add/depot').single;
        expect(a.json['produitId'], 'F83');
        expect(a.json.containsKey('lotScanne'), isFalse);
      }));

  test('proforma, mode B lot en stock : ligne SANS lotScanne', () => avecVraiHttp(() async {
        final p = proforma();
        await p.searchProducts(_dm);
        expect(p.searchResults.single.lgFAMILLEID, 'F83');
        expect(await p.addProduct(p.searchResults.single, 1), isTrue);
        final a = srv.recuesSur('/vente/devis').single;
        expect(a.json['produitId'], 'F83');
        expect(a.json.containsKey('lotScanne'), isFalse);
      }));

  test('périmée : refus, aucune recherche de produit (dépôt et proforma)', () => avecVraiHttp(() async {
        verdict = _verdict(perime: true);
        final d = depot();
        await d.searchProducts(_dm);
        expect(d.productSearch.refusGs1, 'Boîte périmée (31/01/2020) : non ajoutée');
        final f = proforma();
        await f.searchProducts(_dm);
        expect(f.productSearch.refusGs1, 'Boîte périmée (31/01/2020) : non ajoutée');
        expect(srv.recuesSur('/vente/search'), isEmpty);
      }));

  for (final (cas, preparer) in <(String, void Function())>[
    ('404', () => statutGs1 = 404),
    ('500', () => statutGs1 = 500),
    ('délai dépassé (6 s)', () => delaiGs1 = const Duration(seconds: 6)),
  ]) {
    test('vente/gs1 $cas : produit trouvé comme avant, au plus tard après le délai', () => avecVraiHttp(() async {
          verdict = _verdict(perime: true);
          preparer();
          final sw = Stopwatch()..start();
          final d = depot();
          await d.searchProducts(_dm);
          sw.stop();
          expect(d.productSearch.refusGs1, isNull);
          expect(d.searchResults.single.lgFAMILLEID, 'F83');
          expect(sw.elapsed, lessThan(Gs1Vente.delai + const Duration(milliseconds: 1500)));
        }));
  }

  test('serveur coupé pendant la lecture : comme avant (panne de la recherche, jamais un refus)', () => avecVraiHttp(() async {
        final d = depot();
        await srv.couper();
        await d.searchProducts(_dm);
        expect(d.productSearch.refusGs1, isNull);
        expect(d.searchError, isNotNull, reason: 'recherche impossible, comme avant');
        expect(d.searchNotFound, isNull);
      }));
}
