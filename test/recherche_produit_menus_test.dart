// Recherche produit des menus hors ventes (Proforma, Dépôt, Ajustement, Péremption, Périmés,
// EAN / Emplacement, Évaluation, Recherche article) : plus de limite silencieuse à 30 résultats.
// - un code trouve le produit EXACT (le 48ᵉ de 120 produits qui commencent pareil) ;
// - un EAN-13 34009… trouve le produit dont seul le CIP7 est enregistré ;
// - un nom donne « 50 sur 120 » et la suite se charge en faisant défiler ;
// - une panne n'est jamais annoncée comme « introuvable ».
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/product_search_result.dart';
import 'package:prestige_vente_app/api/models/rayon.dart';
import 'package:prestige_vente_app/providers/ajustement_provider.dart';
import 'package:prestige_vente_app/providers/depot_sale_provider.dart';
import 'package:prestige_vente_app/providers/expiration_update_provider.dart';
import 'package:prestige_vente_app/providers/perime_provider.dart';
import 'package:prestige_vente_app/providers/product_search_provider.dart';
import 'package:prestige_vente_app/providers/product_stats_provider.dart';
import 'package:prestige_vente_app/providers/product_update_provider.dart';
import 'package:prestige_vente_app/providers/proforma_provider.dart';
import 'package:prestige_vente_app/screens/common/product_search_modal.dart';
import 'package:prestige_vente_app/screens/expiration_update/expiration_update_screen.dart';
import 'package:prestige_vente_app/screens/product_search/product_search_screen.dart';
import 'package:prestige_vente_app/screens/product_update/ean_update_screen.dart';
import 'package:prestige_vente_app/screens/product_update/emplacement_update_screen.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart' show ProductPage;
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProductSearchResult _p(String id, String name, String cip) =>
    ProductSearchResult(lgFAMILLEID: id, strNAME: name, intCIP: cip, intPRICE: 1000, intNUMBERAVAILABLE: 5, strLIBELLEE: '', intPAF: 800);

String _n(int i) => i.toString().padLeft(3, '0');

/// 120 produits « DOLI PRODUIT 000…119 » (CIP 3595500…3595619 : le 48ᵉ a le CIP 3595548, le 83ᵉ 3595583),
/// plus 10 produits dont le CIP commence par 3595548 (le serveur cherche « commence par »).
final _catalog = [
  for (var i = 0; i < 120; i++) _p('P$i', 'DOLI PRODUIT ${_n(i)}', '${3595500 + i}'),
  for (var i = 0; i < 10; i++) _p('X$i', 'AUTRE ${_n(i)}', '3595548$i'),
];

class _Api extends ApiService {
  _Api() : super(baseUrl: 'http://localhost');

  final calls = <String>[];
  bool down = false;

  @override
  Future<ProductPage> searchProductsPageOrFail(String query, int start, int limit) async {
    calls.add('$query@$start');
    if (down) throw const ApiLoadException('Serveur injoignable (produits non chargés).');
    final q = query.trim().toUpperCase();
    final all = _catalog.where((p) => p.strNAME.startsWith(q) || p.intCIP.startsWith(q)).toList();
    return ProductPage(all.skip(start).take(limit).toList(), all.length);
  }

  /// L'ancienne recherche (limitée à 30) ne doit plus servir dans ces menus.
  @override
  Future<List<ProductSearchResult>> searchProducts(String query) async => throw StateError('ancienne recherche limitée à 30 utilisée');

  @override
  Future<List<ProductSearchResult>> searchProductsOrFail(String query) async => throw StateError('ancienne recherche limitée à 30 utilisée');

  @override
  Future<List<ProductSearchResult>> searchDepotProducts(String query) async => throw StateError('ancienne recherche limitée à 30 utilisée');

  @override
  Future<ProductDetails?> getProductDetailsForSearch(String codeCip) async =>
      ProductDetails.fromJson({'lg_FAMILLE_ID': 'x', 'int_CIP': codeCip, 'str_NAME': 'DOLI'});

  @override
  Future<List<Rayon>> getRayons() async => [Rayon(id: 'r1', libelle: 'RAYON A1')];
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(720, 1400); // 360 x 700
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField).first, text);
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
  }

  /// Fait défiler la liste jusqu'au 120ᵉ produit : la suite se charge toute seule.
  Future<void> scrollToLast(WidgetTester tester, _Api api) async {
    await tester.scrollUntilVisible(find.text('DOLI PRODUIT 119'), 400, scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
    expect(find.text('DOLI PRODUIT 119'), findsOneWidget);
    expect(api.calls.where((c) => c.startsWith('DOLI@')), ['DOLI@0', 'DOLI@50', 'DOLI@100']);
  }

  group('Proforma / devis', () {
    test('code : 48ᵉ produit exact, EAN-13 → CIP7, code inconnu, panne', () async {
      final api = _Api();
      final provider = ProformaProvider(api);
      await provider.searchProducts('3595548');
      expect(provider.searchResults.map((p) => p.lgFAMILLEID), ['P48']);

      await provider.searchProducts('3400935955838');
      expect(provider.searchResults.single.intCIP, '3595583');
      expect(api.calls.sublist(api.calls.length - 2), ['3400935955838@0', '3595583@0']);

      await provider.searchProducts('9999999');
      expect(provider.searchResults, isEmpty);
      expect(provider.searchNotFound, 'Code 9999999 introuvable');

      api.down = true;
      await provider.searchProducts('3595548');
      expect(provider.searchResults, isEmpty);
      expect(provider.searchError, contains('Serveur injoignable'));
      expect(provider.searchNotFound, isNull);
    });

    test('nom : « 50 sur 120 », la suite se charge jusqu\'au 120ᵉ', () async {
      final api = _Api();
      final provider = ProformaProvider(api);
      await provider.searchProducts('DOLI');
      expect(provider.searchResults, hasLength(50));
      expect(provider.productSearch.countLabel, '50 sur 120');
      expect(provider.productSearch.pager, isNotNull); // liste de choix par pages
      await provider.loadMoreProducts();
      expect(provider.productSearch.countLabel, '100 sur 120');
      await provider.loadMoreProducts();
      expect(provider.searchResults.last.strNAME, 'DOLI PRODUIT 119');
      expect(provider.productSearch.hasMore, isFalse);
    });
  });

  test('Vente dépôt : code exact et liste par pages', () async {
    final api = _Api();
    final provider = DepotSaleProvider(api);
    await provider.searchProducts('3595548');
    expect(provider.searchResults.single.lgFAMILLEID, 'P48');
    await provider.searchProducts('DOLI');
    expect(provider.productSearch.countLabel, '50 sur 120');
    api.down = true;
    await provider.searchProducts('DOLI');
    expect(provider.searchError, contains('Serveur injoignable'));
  });

  test('Gestion périmés / Évaluation / Recherche article : code exact, EAN-13 → CIP7, pages', () async {
    final api = _Api();
    final perime = PerimeProvider(api);
    await perime.searchProduct('3595548');
    expect(perime.productSearchResults.single.lgFAMILLEID, 'P48');
    await perime.searchProduct('3400935955838');
    expect(perime.productSearchResults.single.lgFAMILLEID, 'P83');
    await perime.searchProduct('DOLI');
    expect(perime.productSearch.countLabel, '50 sur 120');

    final stats = ProductStatsProvider(api);
    await stats.searchProducts('3595548');
    expect(stats.searchResults.single.lgFAMILLEID, 'P48');
    await stats.searchProducts('DOLI');
    await stats.loadMoreProducts();
    expect(stats.productSearch.countLabel, '100 sur 120');
  });

  group('Ajustement stock', () {
    test('scan : 48ᵉ exact, EAN-13 → CIP7, « Code X introuvable », panne ≠ introuvable', () async {
      final api = _Api();
      final provider = AjustementProvider(api);
      expect((await provider.searchProductForScan('3595548')).map((p) => p.lgFAMILLEID), ['P48']);
      expect((await provider.searchProductForScan('3400935955838')).single.lgFAMILLEID, 'P83');
      expect(await provider.searchProductForScan('3400999999990'), isEmpty);
      expect(provider.scanNotFound, 'Code 3400999999990 introuvable (essayé aussi 9999999)');
      api.down = true;
      await expectLater(provider.searchProductForScan('3595548'), throwsA(isA<ApiLoadException>()));
    });

    testWidgets('fenêtre de recherche : « 50 sur 120 », la suite se charge en défilant', (tester) async {
      phone(tester);
      final api = _Api();
      ProductSearchResult? chosen;
      await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => AjustementProvider(api),
        child: MaterialApp(
          home: Scaffold(body: ProductSearchModal(initialQuery: 'DOLI', onProductSelected: (p) => chosen = p)),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('50 sur 120'), findsWidgets);
      await scrollToLast(tester, api);
      expect(find.textContaining('120 sur 120'), findsOneWidget);
      await tester.tap(find.text('DOLI PRODUIT 119'));
      await tester.pumpAndSettle();
      expect(chosen?.lgFAMILLEID, 'P119');
    });

    testWidgets('fenêtre de recherche : panne affichée avec « Réessayer »', (tester) async {
      phone(tester);
      final api = _Api()..down = true;
      await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => AjustementProvider(api),
        child: MaterialApp(home: Scaffold(body: ProductSearchModal(initialQuery: 'DOLI', onProductSelected: (_) {}))),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('Recherche impossible'), findsOneWidget);
      expect(find.text('Aucun résultat'), findsNothing);
      api.down = false;
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.text('DOLI PRODUIT 000'), findsOneWidget);
    });
  });

  group('Mise à jour péremption', () {
    Future<_Api> pump(WidgetTester tester) async {
      phone(tester);
      final api = _Api();
      await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => ExpirationUpdateProvider(api),
        child: const MaterialApp(home: ExpirationUpdateScreen()),
      ));
      await tester.pumpAndSettle();
      return api;
    }

    testWidgets('code du 48ᵉ produit : ouvert directement', (tester) async {
      await pump(tester);
      await type(tester, '3595548');
      expect(find.text('DOLI PRODUIT 048'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'N° de Lot'), findsOneWidget);
    });

    testWidgets('EAN-13 34009… : produit trouvé par son CIP7', (tester) async {
      final api = await pump(tester);
      await type(tester, '3400935955838');
      expect(find.text('DOLI PRODUIT 083'), findsOneWidget);
      expect(api.calls, containsAllInOrder(['3400935955838@0', '3595583@0']));
    });

    testWidgets('nom : « 50 sur 120 » puis la suite en défilant', (tester) async {
      final api = await pump(tester);
      await type(tester, 'DOLI');
      expect(find.textContaining('50 sur 120'), findsWidgets);
      await scrollToLast(tester, api);
    });
  });

  group('Mise à jour EAN et Emplacement', () {
    Widget app(_Api api, Widget home) => ChangeNotifierProvider(create: (_) => ProductUpdateProvider(api), child: MaterialApp(home: home));

    for (final (label, screen) in [
      ('EAN', const EanUpdateScreen(presentation: ListPresentation.dashboard)),
      ('Emplacement', const EmplacementUpdateScreen(presentation: ListPresentation.compact)),
    ]) {
      testWidgets('$label : code du 48ᵉ produit ouvert directement', (tester) async {
        phone(tester);
        final api = _Api();
        await tester.pumpWidget(app(api, screen));
        await tester.pumpAndSettle();
        await type(tester, '3595548');
        expect(find.text('DOLI PRODUIT 048'), findsWidgets);
        expect(find.text('DOLI PRODUIT 049'), findsNothing);
      });

      testWidgets('$label : EAN-13 → CIP7, code inconnu, liste « 50 sur 120 »', (tester) async {
        phone(tester);
        final api = _Api();
        await tester.pumpWidget(app(api, screen));
        await tester.pumpAndSettle();
        await type(tester, '3400935955838');
        expect(find.text('DOLI PRODUIT 083'), findsWidgets);

        // Nouvel écran (le produit ouvert est refermé).
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(app(api, screen));
        await tester.pumpAndSettle();
        await type(tester, '3400999999990');
        expect(find.text('Code 3400999999990 introuvable (essayé aussi 9999999)'), findsOneWidget);

        await type(tester, 'DOLI');
        expect(find.textContaining('50 sur 120'), findsWidgets);
        await scrollToLast(tester, api);
      });
    }
  });

  group('Recherche article', () {
    Widget app(_Api api) => MultiProvider(
          providers: [
            Provider<ApiService>.value(value: api),
            ChangeNotifierProvider(create: (_) => ProductSearchProvider(api)),
          ],
          child: const MaterialApp(home: ProductSearchScreen(presentation: ListPresentation.dashboard)),
        );

    testWidgets('code du 48ᵉ produit et EAN-13 → CIP7', (tester) async {
      phone(tester);
      final api = _Api();
      await tester.pumpWidget(app(api));
      await tester.pumpAndSettle();
      await type(tester, '3595548');
      expect(find.text('DOLI PRODUIT 048'), findsOneWidget);
      expect(find.text('AUTRE 000'), findsNothing); // seul le produit exact
      await type(tester, '3400935955838');
      expect(find.text('DOLI PRODUIT 083'), findsOneWidget);
    });

    testWidgets('nom : « 50 sur 120 » puis la suite ; panne ≠ « aucun résultat »', (tester) async {
      phone(tester);
      final api = _Api();
      await tester.pumpWidget(app(api));
      await tester.pumpAndSettle();
      await type(tester, 'DOLI');
      expect(find.textContaining('50 sur 120'), findsWidgets);
      await scrollToLast(tester, api);

      api.down = true;
      await type(tester, 'DOLIP');
      expect(find.textContaining('Recherche impossible'), findsOneWidget);
      expect(find.text('Aucun résultat'), findsNothing);
    });
  });
}
