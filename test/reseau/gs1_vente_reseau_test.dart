// RÉSEAU — 4.9.0 : étiquettes GS1 à la vente, en vrai HTTP vers le faux serveur Prestige (données FICTIVES) :
//  - réglage KEY_VENTE_LECTURE_GS1 lu avec la session (GET v1/app-params/value) : « 1 » actif ; « 0 », 404, panne,
//    serveur coupé → inactif ;
//  - verdict GET v1/vente/gs1 (paramètre « code », cookie de session) : mode B lot en stock → `lotScanne` dans le
//    corps de POST v1/vente/add/vno, une seule fois ; périmée → refus ;
//  - 404 / 405 / 500 / délai dépassé / coupure : produit trouvé exactement comme avant (mêmes codes essayés), au plus
//    tard après le délai du scan.
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/api/utilisateur_session.dart';
import 'package:prestige_vente_app/ventes/core/gs1_recherche.dart';
import 'package:prestige_vente_app/ventes/core/gs1_vente.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';

import '../outils/faux_serveur_prestige.dart';
import '../outils/parcours_vente.dart';

final _doli = {...produitFictif(83), 'lgFAMILLEID': 'F83', 'strNAME': 'DOLI FICTIF 1000 CPR B/8', 'intCIP': '3400935955838'};
const _dm = '01034009359558381728103110LOTA1';

Map<String, dynamic> _verdict({String mode = 'B', bool lotEnStock = true, bool perime = false}) => {
      'success': true,
      'actif': true,
      'gs1': true,
      'lot': 'LOTA1',
      'peremption': perime ? '31/01/2020' : '31/10/2028',
      'perime': perime,
      'cip': '3400935955838',
      'gtin': '03400935955838',
      'lotPrevu': 'LOTB2',
      'peremptionPrevue': '30/06/2028',
      'controle': 'DIFFERENT',
      'modeControle': mode,
      'lotEnStock': lotEnStock,
      'data': {'lgFAMILLEID': 'F83', 'intCIP': '3400935955838'},
    };

void main() {
  late FauxServeurPrestige srv;
  late ApiService api;
  late DioVenteGateway gw;
  String lecture = '1';
  int? statutLecture;
  int statutGs1 = 200;
  Duration delaiGs1 = Duration.zero;
  Map<String, dynamic> verdict = _verdict();

  Future<VenteResult<ProductPage>> recherche(String q, int s, int l) => gw.searchProductsPage(q, s, l);

  setUp(() => avecVraiHttp(() async {
        lecture = '1';
        statutLecture = null;
        statutGs1 = 200;
        delaiGs1 = Duration.zero;
        verdict = _verdict();
        srv = FauxServeurPrestige();
        CatalogueFictif(srv, nombre: 10).produits.add(_doli);
        srv.routes['GET /app-params/value/KEY_VENTE_LECTURE_GS1'] = (_) => statutLecture != null
            ? ReponseLocale('<html>$statutLecture</html>', statut: statutLecture!)
            : FauxServeurPrestige.ok({'success': true, 'data': lecture, 'total': 1});
        srv.routes['GET /vente/gs1'] = (_) =>
            statutGs1 != 200 ? ReponseLocale('<html>$statutGs1</html>', statut: statutGs1) : FauxServeurPrestige.ok(verdict, delai: delaiGs1);
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

  test('réglage lu avec la session : « 1 » actif ; « 0 », 404, 500, serveur coupé → inactif', () => avecVraiHttp(() async {
        final g = Gs1Vente.instance;
        await g.relireReglage(api.dio);
        expect(g.actif, isTrue);
        expect(srv.recuesSur('/app-params/value/KEY_VENTE_LECTURE_GS1').single.jsessionid, isNotNull);
        lecture = '0';
        await g.relireReglage(api.dio);
        expect(g.actif, isFalse);
        for (final s in [404, 405, 500]) {
          lecture = '1';
          await g.relireReglage(api.dio);
          statutLecture = s;
          await g.relireReglage(api.dio);
          expect(g.actif, isFalse, reason: 'HTTP $s');
          statutLecture = null;
        }
        await g.relireReglage(api.dio);
        await srv.couper();
        await g.relireReglage(api.dio);
        expect(g.actif, isFalse, reason: 'serveur coupé');
      }));

  test('mode B, lot en stock : code envoyé en paramètre, « lotScanne » dans l\'ajout de la ligne, une seule fois', () => avecVraiHttp(() async {
        await Gs1Vente.instance.relireReglage(api.dio);
        final r = (await rechercherEtiquetteGs1(_dm, recherche))!;
        expect(r.exact, isTrue);
        expect(r.produits.single.lgFAMILLEID, 'F83');
        expect(r.avertissement, contains('Lot différent'));
        final appel = srv.recuesSur('/vente/gs1').single;
        expect(appel.query['code'], _dm);
        expect(appel.jsessionid, isNotNull, reason: 'avec la session');
        final v = await gw.addItemVno(produitId: 'F83', qte: 1, itemPu: 1000, prevente: true);
        expect(v, isA<VenteOk<String>>());
        expect(srv.recuesSur('/vente/add/vno').single.json['lotScanne'], 'LOTA1');
        await gw.addItemVno(produitId: 'F83', qte: 1, itemPu: 1000, venteId: (v as VenteOk<String>).value, prevente: true);
        expect(srv.recuesSur('/vente/add/item').single.json.containsKey('lotScanne'), isFalse, reason: 'pris une seule fois');
      }));

  test('boîte périmée : refusée, aucune recherche de produit', () => avecVraiHttp(() async {
        verdict = _verdict(perime: true);
        await Gs1Vente.instance.relireReglage(api.dio);
        final r = (await rechercherEtiquetteGs1(_dm, recherche))!;
        expect(r.refus?.message, 'Boîte périmée (31/01/2020) : non ajoutée');
        expect(srv.recuesSur('/vente/search'), isEmpty);
      }));

  for (final (cas, preparer) in <(String, void Function())>[
    ('404 (serveur ancien)', () => statutGs1 = 404),
    ('405', () => statutGs1 = 405),
    ('500', () => statutGs1 = 500),
    ('délai dépassé (6 s)', () => delaiGs1 = const Duration(seconds: 6)),
  ]) {
    test('vente/gs1 $cas : produit trouvé comme avant, mêmes codes essayés, au plus tard après le délai', () => avecVraiHttp(() async {
          verdict = _verdict(perime: true); // jamais appliqué si la lecture n'aboutit pas
          await Gs1Vente.instance.relireReglage(api.dio);
          preparer();
          final sw = Stopwatch()..start();
          final r = (await rechercherEtiquetteGs1(_dm, recherche))!;
          sw.stop();
          expect(r.refus, isNull);
          expect(r.produits.single.lgFAMILLEID, 'F83');
          expect(sw.elapsed, lessThan(Gs1Vente.delai + const Duration(milliseconds: 1500)));
          final ref = (await ProductLookup.byCode(_dm, recherche)).valueOrNull!;
          expect(r.essayes, ref.tried, reason: 'mêmes codes que le chemin d\'avant');
          expect(LotScanneEnAttente.champ('F83'), isEmpty);
        }));
  }

  test('lecture inactive : jamais vente/gs1, produit trouvé comme avant', () => avecVraiHttp(() async {
        lecture = '0';
        await Gs1Vente.instance.relireReglage(api.dio);
        final r = (await rechercherEtiquetteGs1(_dm, recherche))!;
        expect(r.produits.single.lgFAMILLEID, 'F83');
        expect(srv.recuesSur('/vente/gs1'), isEmpty);
      }));
}
