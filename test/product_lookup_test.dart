// Recherche produit : code exact (variantes EAN/CIP/GTIN) et liste texte par pages.
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';

ProductSearchResult _p(String id, String name, String cip) =>
    ProductSearchResult(lgFAMILLEID: id, strNAME: name, intCIP: cip, intPRICE: 1000, intNUMBERAVAILABLE: 5, strLIBELLEE: '', intPAF: 800);

void main() {
  // 120 produits « DOLI… », recherche serveur « commence par » sur nom ou CIP.
  final catalog = [for (var i = 0; i < 120; i++) _p('P$i', 'DOLI PRODUIT ${i.toString().padLeft(3, '0')}', '35955${i.toString().padLeft(2, '0')}')];
  final calls = <String>[];
  Future<VenteResult<ProductPage>> server(String q, int start, int limit) async {
    calls.add('$q@$start');
    final all = catalog.where((p) => p.strNAME.startsWith(q) || p.intCIP.startsWith(q)).toList();
    return VenteOk(ProductPage(all.skip(start).take(limit).toList(), all.length));
  }

  setUp(calls.clear);

  test('code : variantes EAN-13 34009 → CIP7, GTIN-14 → EAN-13, DataMatrix', () {
    expect(ProductLookup.codeCandidates('3400935955838'), ['3400935955838', '3595583']);
    expect(ProductLookup.codeCandidates('03400935955838'), ['03400935955838', '3400935955838', '3595583']);
    expect(ProductLookup.codeCandidates('0103400935955838\u001d17281002\u001d10LOT1').contains('3595583'), isTrue);
    expect(ProductLookup.looksLikeCode('3595583'), isTrue);
    expect(ProductLookup.looksLikeCode('DOLIPRANE'), isFalse);
    expect(ProductLookup.looksLikeCode('1000'), isFalse);
  });

  test('scan du 48ᵉ produit : trouvé exactement, même si 120 produits commencent pareil', () async {
    final r = await ProductLookup.byCode('3595548', server);
    expect(r.valueOrNull!.exact!.lgFAMILLEID, 'P48');
  });

  test('scan d\'un EAN-13 dont seul le CIP7 est connu', () async {
    final r = await ProductLookup.byCode('3400935955838', server);
    expect(r.valueOrNull!.exact!.intCIP, '3595583');
    expect(calls, ['3400935955838@0', '3595583@0']);
  });

  test('code inconnu : aucun produit, codes essayés listés', () async {
    final r = await ProductLookup.byCode('9999999', server);
    expect(r.valueOrNull!.exact, isNull);
    expect(r.valueOrNull!.tried, ['9999999']);
  });

  test('panne : échec, jamais « introuvable »', () async {
    final r = await ProductLookup.byCode('3595548', (q, s, l) async => const VenteFailed('Serveur injoignable'));
    expect(r, isA<VenteFailed<CodeLookup>>());
  });

  test('texte : pages de 50, total connu, le 120ᵉ est atteignable', () async {
    final pager = ProductPager(server, 'DOLI');
    await pager.loadMore();
    expect(pager.items.length, 50);
    expect(pager.total, 120);
    expect(pager.hasMore, isTrue);
    await pager.loadMore();
    await pager.loadMore();
    expect(pager.items.length, 120);
    expect(pager.hasMore, isFalse);
    expect(pager.items.last.lgFAMILLEID, 'P119');
    await pager.loadMore(); // rien de plus
    expect(calls, ['DOLI@0', 'DOLI@50', 'DOLI@100']);
  });
}
