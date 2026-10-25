// 4.9.1 — lecture GS1 dans la recherche des ventes Dépôt et Proforma (PagedProductSearch(gs1Vente: true)) :
//  - verdicts : refus (C, périmée, étendue, sans produit), avertissement A / B neutre, JAMAIS de lot en attente
//    (`lotScanne` : routes d'ajout qui ne s'en servent pas) ;
//  - NON-RÉGRESSION : lecture inactive, 404, 405, 500, réseau coupé, délai, réponse illisible → produits, « introuvable »
//    et panne identiques à la recherche d'avant (gs1Vente: false) ; code-barres, CIP, nom : jamais vente/gs1 ;
//  - hors ligne (lecture active) : boîte périmée refusée par sa date ; autres menus inchangés.
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/services/product_finder.dart';
import 'package:prestige_vente_app/ventes/core/gs1_vente.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';

ProductSearchResult _p(String id, String name, String cip) =>
    ProductSearchResult(lgFAMILLEID: id, strNAME: name, intCIP: cip, intPRICE: 1000, intNUMBERAVAILABLE: 5, strLIBELLEE: '', intPAF: 800);

class _Api extends ApiService {
  _Api() : super(baseUrl: 'http://localhost');
  final catalog = [for (var i = 0; i < 120; i++) _p('P$i', 'DOLI PRODUIT ${i.toString().padLeft(3, '0')}', '35955${i.toString().padLeft(2, '0')}')];
  final appels = <String>[];
  bool panne = false;
  @override
  Future<ProductPage> searchProductsPageOrFail(String query, int start, int limit) async {
    appels.add(query);
    if (panne) throw const ApiLoadException('Serveur injoignable (recherche).');
    final all = catalog.where((p) => p.strNAME.startsWith(query) || p.intCIP.startsWith(query)).toList();
    return ProductPage(all.skip(start).take(limit).toList(), all.length);
  }
}

class _Srv extends Interceptor {
  final List<String> chemins = [];
  FutureOr<(int, Object?)> Function(RequestOptions o)? reponse;
  @override
  void onRequest(RequestOptions o, RequestInterceptorHandler h) async {
    chemins.add(o.path);
    final f = reponse;
    if (f == null) return h.reject(DioException(requestOptions: o, type: DioExceptionType.connectionError));
    final (s, b) = await f(o);
    h.resolve(Response(requestOptions: o, statusCode: s, data: b is String ? b : jsonEncode(b)));
  }
}

const _dm = '0103400935955838\u001d17281031\u001d10LOTA1';
const _dmPerime = '0103400935955838\u001d17200131\u001d10LOTX';

Map<String, dynamic> _ok({String controle = 'DIFFERENT', String mode = 'A', bool lotEnStock = false, bool perime = false}) => {
      'success': true,
      'actif': true,
      'lot': 'LOTA1',
      'peremption': perime ? '31/01/2020' : '31/10/2028',
      'perime': perime,
      'cip': '3595583',
      'lotPrevu': 'LOTB2',
      'peremptionPrevue': '30/06/2028',
      'controle': controle,
      'modeControle': mode,
      'lotEnStock': lotEnStock,
      'data': {'lgFAMILLEID': 'P83'},
    };

void main() {
  late _Api api;
  late _Srv srv;
  setUp(() {
    api = _Api();
    srv = _Srv();
    final d = Dio()..interceptors.add(srv);
    final g = Gs1Vente.instance;
    g.dio = () => d;
    g.horsLigne = () => false;
    g.maintenant = () => DateTime(2026, 10, 25);
    g.actifPourTests = true;
  });

  PagedProductSearch depot() => PagedProductSearch(() => api, gs1Vente: true);

  /// Résultat observable d'une recherche (produits, introuvable, panne).
  Future<(List<String>, String?, String?, List<String>)> resultat(PagedProductSearch s, String q) async {
    api.appels.clear();
    await s.run(q);
    return (s.items.map((p) => p.lgFAMILLEID).toList(), s.notFound, s.error, [...api.appels]);
  }

  group('verdicts (dépôt, proforma)', () {
    for (final (cas, corps, message) in <(String, Map<String, dynamic>, String)>[
      ('mode C', _ok(mode: 'C'), 'Prenez une boîte du lot LOTB2'),
      ('périmée', _ok(controle: 'CONFORME', perime: true), 'Boîte périmée (31/01/2020) : non ajoutée'),
      ('étendue', {'success': false, 'actif': true, 'etendu': true, 'msg': 'Étiquette étendue.'}, 'Étiquette étendue.'),
      ('sans produit', {'success': false, 'actif': true, 'sansProduit': true, 'msg': 'Étiquette sans produit.'}, 'Étiquette sans produit.'),
    ]) {
      test('$cas : refus, aucun produit, aucune recherche', () async {
        srv.reponse = (_) => (200, corps);
        final s = depot();
        await s.run(_dm);
        expect(s.refusGs1, startsWith(message));
        expect(s.items, isEmpty);
        expect((s.notFound, s.error), (null, null));
        expect(api.appels, isEmpty);
      });
    }

    for (final mode in ['A', 'B']) {
      test('mode $mode lot différent : produit trouvé, avertissement neutre, aucun lot en attente', () async {
        srv.reponse = (_) => (200, _ok(mode: mode, lotEnStock: true));
        LotScanneEnAttente.vider();
        final s = depot();
        await s.run(_dm);
        expect(s.items.single.lgFAMILLEID, 'P83');
        expect(s.avertissementGs1, 'Lot différent : boîte scannée lot LOTA1 - pér. 31/10/2028 (prévu : lot LOTB2, péremption 30/06/2028).');
        expect(LotScanneEnAttente.champ('P83'), isEmpty, reason: 'jamais de lotScanne pour ces ventes');
        expect(srv.chemins, ['/vente/gs1']);
      });
    }

    test('une nouvelle recherche efface refus et avertissement', () async {
      srv.reponse = (_) => (200, _ok(mode: 'C'));
      final s = depot();
      await s.run(_dm);
      expect(s.refusGs1, isNotNull);
      await s.run('DOLI');
      expect((s.refusGs1, s.avertissementGs1), (null, null));
      s.clear();
      expect(s.refusGs1, isNull);
    });
  });

  group('non-régression : comportement d\'avant', () {
    final replis = <(String, void Function(_Srv))>[
      ('lecture inactive', (s) => Gs1Vente.instance.actifPourTests = false),
      ('404 (serveur ancien)', (s) => s.reponse = (_) => (404, '<html>404</html>')),
      ('405', (s) => s.reponse = (_) => (405, '<html>405</html>')),
      ('500', (s) => s.reponse = (_) => (500, '<html>500</html>')),
      ('réseau coupé', (s) => s.reponse = null),
      ('réponse illisible', (s) => s.reponse = (_) => (200, 'pas du json')),
      ('pas une étiquette GS1', (s) => s.reponse = (_) => (200, {'success': false, 'actif': true, 'gs1': false})),
      ('délai dépassé', (s) => s.reponse = (_) async {
            await Future<void>.delayed(const Duration(seconds: 4));
            return (200, _ok(perime: true));
          }),
    ];
    for (final (cas, preparer) in replis) {
      test('$cas : produits, introuvable et codes essayés identiques à la recherche d\'avant', () async {
        preparer(srv);
        for (final q in [_dm, _dmPerime, '3400935955838', '3595583', 'DOLI', '0109999999999999\u001d17281031\u001d10L']) {
          final avant = await resultat(PagedProductSearch(() => api), q);
          final apres = await resultat(depot(), q);
          final r = '$cas / ${q.length} caractères';
          expect(apres.$1, avant.$1, reason: r);
          expect((apres.$2, apres.$3), (avant.$2, avant.$3), reason: r);
          expect(apres.$4, avant.$4, reason: r);
        }
        final s = depot();
        await s.run(_dm);
        expect((s.refusGs1, s.avertissementGs1), (null, null));
      }, timeout: const Timeout(Duration(seconds: 60)));
    }

    test('panne de la recherche : même panne qu\'avant, jamais « introuvable »', () async {
      srv.reponse = (_) => (200, _ok(mode: 'A'));
      api.panne = true;
      final avant = await resultat(PagedProductSearch(() => api), _dm);
      final s = depot();
      await s.run(_dm);
      expect(s.error, avant.$3);
      expect(s.notFound, isNull);
    });

    test('code-barres, CIP7, nom : jamais vente/gs1', () async {
      srv.reponse = (_) => (200, _ok(perime: true));
      for (final q in ['3400935955838', '3595583', 'DOLI PRODUIT', '03400935955838']) {
        await depot().run(q);
      }
      expect(srv.chemins, isEmpty);
    });

    test('autres menus (gs1Vente: false) : jamais vente/gs1, même lecture active', () async {
      srv.reponse = (_) => (200, _ok(perime: true));
      final s = PagedProductSearch(() => api);
      await s.run(_dm);
      expect(srv.chemins, isEmpty);
      expect(s.items.single.lgFAMILLEID, 'P83');
      expect(s.refusGs1, isNull);
    });
  });

  group('hors ligne', () {
    test('lecture active : boîte périmée refusée par sa date ; valide trouvée ; aucune requête vente/gs1', () async {
      Gs1Vente.instance.horsLigne = () => true;
      srv.reponse = (_) => (200, _ok());
      final s = depot();
      await s.run(_dmPerime);
      expect(s.refusGs1, 'Boîte périmée (31/01/2020) : non ajoutée');
      await s.run(_dm);
      expect(s.items.single.lgFAMILLEID, 'P83');
      expect(srv.chemins, isEmpty);
    });

    test('lecture inactive : rien ne change', () async {
      Gs1Vente.instance.horsLigne = () => true;
      Gs1Vente.instance.actifPourTests = false;
      final s = depot();
      await s.run(_dmPerime);
      expect(s.refusGs1, isNull);
      expect(s.items.single.lgFAMILLEID, 'P83');
    });
  });

  test('vente au comptant inchangée : mode B lot en stock garde son lot en attente', () async {
    srv.reponse = (_) => (200, _ok(mode: 'B', lotEnStock: true));
    final v = await Gs1Vente.instance.verdict(_dm);
    expect((v as Gs1Accepte).lotScanne, 'LOTA1');
    expect(v.avertissement, contains('la vente sortira ce lot'));
    expect(LotScanneEnAttente.champ('P83'), {'lotScanne': 'LOTA1'});
    LotScanneEnAttente.vider();
  });

  test('ProductLookup.pageSize inchangé', () => expect(ProductLookup.pageSize, 50));
}
