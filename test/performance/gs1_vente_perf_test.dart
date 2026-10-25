// PERFORMANCE — 4.9.0 : la lecture GS1 à la vente ne ralentit pas le scan :
//  - reconnaissance (sans réseau) de 20 000 codes (EAN-13, CIP7, noms, DataMatrix, lien numérique) en moins de
//    500 ms ; jamais de requête pour un code-barres classique ;
//  - verdict du serveur rapide : produit trouvé avec UNE requête de plus, rien d'autre ;
//  - serveur lent : le scan n'attend jamais plus que Gs1Vente.delai (puis comportement d'avant).
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/ventes/core/gs1_recherche.dart';
import 'package:prestige_vente_app/ventes/core/gs1_vente.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';

const _dm = '01034009359558381728103110LOTA1';

class _Srv extends Interceptor {
  int appels = 0;
  Duration delai = Duration.zero;
  @override
  void onRequest(RequestOptions o, RequestInterceptorHandler h) async {
    appels++;
    await Future<void>.delayed(delai);
    h.resolve(Response(
        requestOptions: o,
        statusCode: 200,
        data: jsonEncode({
          'success': true,
          'actif': true,
          'lot': 'LOTA1',
          'peremption': '31/10/2028',
          'perime': false,
          'cip': '3400935955838',
          'controle': 'CONFORME',
          'modeControle': 'A',
          'lotEnStock': false,
          'data': {'lgFAMILLEID': 'F83'},
        })));
  }
}

void main() {
  late _Srv srv;
  var recherches = 0;
  Future<VenteResult<ProductPage>> recherche(String q, int s, int l) async {
    recherches++;
    final p = ProductSearchResult(lgFAMILLEID: 'F83', strNAME: 'DOLI FICTIF', intCIP: '3400935955838', intPRICE: 1000, intNUMBERAVAILABLE: 5, strLIBELLEE: '', intPAF: 800);
    return VenteOk(ProductPage(q == '3400935955838' ? [p] : const [], q == '3400935955838' ? 1 : 0));
  }

  setUp(() {
    recherches = 0;
    srv = _Srv();
    final d = Dio()..interceptors.add(srv);
    final g = Gs1Vente.instance;
    g.dio = () => d;
    g.horsLigne = () => false;
    g.actifPourTests = true;
  });

  test('reconnaissance de 20 000 codes en moins de 500 ms, aucune requête pour un code-barres classique', () async {
    final codes = ['3400935955838', '3595583', 'DOLIPRANE 1000', _dm, 'https://id.gs1.org/01/03400935955838/10/LOTA1?17=281031', '0123456789012'];
    var gs1 = 0;
    final sw = Stopwatch()..start();
    for (var k = 0; k < 20000; k++) {
      if (Gs1Vente.ressembleGs1(codes[k % codes.length])) gs1++;
    }
    sw.stop();
    expect(gs1, 20000 ~/ 6 * 2 + (20000 % 6 > 3 ? 1 : 0) + (20000 % 6 > 4 ? 1 : 0));
    expect(sw.elapsedMilliseconds, lessThan(500), reason: '${sw.elapsedMilliseconds} ms');
    for (final c in ['3400935955838', '3595583', 'DOLIPRANE 1000']) {
      expect(await rechercherEtiquetteGs1(c, recherche), isNull);
    }
    expect(srv.appels, 0, reason: 'jamais vente/gs1 hors étiquette GS1');
  });

  test('verdict rapide : une requête de plus, une recherche, en moins de 300 ms', () async {
    final sw = Stopwatch()..start();
    final r = (await rechercherEtiquetteGs1(_dm, recherche))!;
    sw.stop();
    expect(r.exact, isTrue);
    expect((srv.appels, recherches), (1, 1));
    expect(sw.elapsedMilliseconds, lessThan(300), reason: '${sw.elapsedMilliseconds} ms');
  });

  test('serveur lent (10 s) : le scan n\'attend pas plus que le délai, puis comme avant', () async {
    srv.delai = const Duration(seconds: 10);
    final sw = Stopwatch()..start();
    final r = (await rechercherEtiquetteGs1(_dm, recherche))!;
    sw.stop();
    expect(r.exact, isTrue, reason: 'produit trouvé par le décodage de l\'appareil');
    expect(sw.elapsed, lessThan(Gs1Vente.delai + const Duration(milliseconds: 500)));
    expect(Gs1Vente.delai, lessThanOrEqualTo(const Duration(seconds: 3)));
  });
}
