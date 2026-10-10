// Barre de recherche des ventes : code scanné → produit exact (même au-delà de 30 résultats),
// EAN-13 → CIP7, recherche texte par pages (« 50 sur 120 », la suite se charge).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/ventes/common/vente_product_search.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProductSearchResult _p(int i) => ProductSearchResult(
      lgFAMILLEID: 'P$i',
      strNAME: 'DOLI PRODUIT ${i.toString().padLeft(3, '0')}',
      intCIP: '35955${i.toString().padLeft(2, '0')}',
      intPRICE: 1000,
      intNUMBERAVAILABLE: 50,
      strLIBELLEE: '',
      intPAF: 800,
    );

void main() {
  final catalog = [for (var i = 0; i < 120; i++) _p(i), ProductSearchResult(lgFAMILLEID: 'RV1', strNAME: 'RV DOLI', intCIP: '9990001', intPRICE: 1, intNUMBERAVAILABLE: 1, strLIBELLEE: '', intPAF: 1)];
  late List<(String, int)> added;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    added = [];
  });

  Future<VenteResult<ProductPage>> server(String q, int start, int limit) async {
    final all = catalog.where((p) => p.strNAME.startsWith(q) || p.intCIP.startsWith(q)).toList();
    return VenteOk(ProductPage(all.skip(start).take(limit).toList(), all.length));
  }

  Future<GlobalKey<VenteProductSearchState>> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(720, 1400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final key = GlobalKey<VenteProductSearchState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          VenteProductSearch(
            key: key,
            search: (q) async => const VenteOk([]),
            pageSearch: server,
            visible: (p) => !p.strNAME.startsWith('RV '),
            addProduct: (p, q) async {
              added.add((p.lgFAMILLEID, q));
              return true;
            },
            debounce: const Duration(milliseconds: 10),
          ),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    return key;
  }

  testWidgets('CIP du 48ᵉ produit tapé : fenêtre de quantité de CE produit', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), '3595548');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.textContaining('DOLI PRODUIT 048'), findsWidgets);
    expect(find.textContaining('Résultats'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scan rapide d\'un EAN-13 dont seul le CIP7 est connu : ajouté directement', (tester) async {
    final catalogEan = _p(83); // CIP 3595583
    expect(catalogEan.intCIP, '3595583');
    final key = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('vente-scan-rapide')));
    await tester.pumpAndSettle();
    expect(key.currentState!.quickScan, isTrue);
    await tester.enterText(find.byType(TextField), '3400935955838');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(added, [('P83', 1)]);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('texte : « 50 sur 120 », la suite se charge, le 120ᵉ est atteignable, RV masqués', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'DOLI');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(find.text('Résultats (50 sur 120)'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('DOLI PRODUIT 119'), 600, scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
    expect(find.text('Résultats (120 sur 120)'), findsOneWidget);
    await tester.tap(find.textContaining('DOLI PRODUIT 119'));
    await tester.pumpAndSettle();
    expect(find.textContaining('DOLI PRODUIT 119'), findsWidgets); // fenêtre de quantité
    expect(find.text('RV DOLI'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('code inconnu : message clair avec les codes essayés', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), '3400930000004');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.textContaining('Code 3400930000004 introuvable (essayé aussi 3000000)'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });
}
