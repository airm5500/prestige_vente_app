// PERFORMANCE — 4.9.1 : la lecture GS1 des ventes Dépôt et Proforma ne ralentit pas la recherche :
//  - 2 000 recherches de codes-barres, CIP et noms : aucune requête vente/gs1, temps comparable à la recherche d'avant ;
//  - étiquette GS1 avec un verdict rapide : une seule requête de plus ;
//  - serveur lent : la recherche n'attend jamais plus que Gs1Vente.delai, puis comme avant ;
//  - 4.9.3 : étiquettes étendues au Dépôt sans requête vente/gs1.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/services/product_finder.dart';
import 'package:prestige_vente_app/ventes/core/gs1_vente.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';

const _dm = '01034009359558381728103110LOTA1';

class _Api extends ApiService {
  _Api() : super(baseUrl: 'http://localhost');
  int recherches = 0;
  @override
  Future<ProductPage> searchProductsPageOrFail(String query, int start, int limit) async {
    recherches++;
    final p = ProductSearchResult(lgFAMILLEID: 'F83', strNAME: 'DOLI FICTIF', intCIP: '3400935955838', intPRICE: 1000, intNUMBERAVAILABLE: 5, strLIBELLEE: '', intPAF: 800);
    final ok = query == '3400935955838' || query.startsWith('DOLI');
    return ProductPage(ok ? [p] : const [], ok ? 1 : 0);
  }
}

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
          'perime': false,
          'cip': '3400935955838',
          'controle': 'CONFORME',
          'modeControle': 'B',
          'lotEnStock': true,
          'data': {'lgFAMILLEID': 'F83'},
        })));
  }
}

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
    g.actifPourTests = true;
  });

  test('2 000 recherches hors étiquette GS1 : aucune requête vente/gs1, temps comparable à avant', () async {
    final codes = ['3400935955838', '3595583', 'DOLI FICTIF', '0123456789012'];
    Future<Duration> mesurer(bool gs1) async {
      final s = PagedProductSearch(() => api, gs1Vente: gs1);
      final sw = Stopwatch()..start();
      for (var k = 0; k < 2000; k++) {
        await s.run(codes[k % codes.length]);
      }
      return sw.elapsed;
    }

    await mesurer(false); // chauffe
    final avant = await mesurer(false);
    final apres = await mesurer(true);
    expect(srv.appels, 0);
    expect(apres.inMicroseconds, lessThan(avant.inMicroseconds * 2 + 200000), reason: 'avant $avant, après $apres');
  });

  test('4.9.3 — Dépôt : 2 000 étiquettes étendues, lecture active, aucune requête vente/gs1, temps comme avant', () async {
    final codes = ['01034009359558381728103110LOTA1|91EPLUS1|92DOLI', 'EP1|CIP:3400935955838|NOM:DOLI'];
    Future<Duration> mesurer(bool gs1) async {
      final s = PagedProductSearch(() => api, gs1Vente: gs1);
      final sw = Stopwatch()..start();
      for (var k = 0; k < 2000; k++) {
        await s.run(codes[k % 2]);
      }
      return sw.elapsed;
    }

    await mesurer(false);
    final avant = await mesurer(false);
    final apres = await mesurer(true);
    expect(srv.appels, 0);
    expect(apres.inMicroseconds, lessThan(avant.inMicroseconds * 2 + 200000), reason: 'avant $avant, après $apres');
  });

  test('étiquette GS1, verdict rapide : une requête de plus, moins de 300 ms', () async {
    final s = PagedProductSearch(() => api, gs1Vente: true);
    final sw = Stopwatch()..start();
    await s.run(_dm);
    sw.stop();
    expect(s.items.single.lgFAMILLEID, 'F83');
    expect(srv.appels, 1);
    expect(sw.elapsedMilliseconds, lessThan(300));
    expect(LotScanneEnAttente.champ('F83'), isEmpty, reason: 'aucun lot pour le dépôt ou la proforma');
  });

  test('serveur lent (10 s) : pas plus que le délai, puis comme avant', () async {
    srv.delai = const Duration(seconds: 10);
    final s = PagedProductSearch(() => api, gs1Vente: true);
    final sw = Stopwatch()..start();
    await s.run(_dm);
    sw.stop();
    expect(s.items.single.lgFAMILLEID, 'F83');
    expect(sw.elapsed, lessThan(Gs1Vente.delai + const Duration(milliseconds: 500)));
    expect(ProductLookup.pageSize, 50);
  });
}
