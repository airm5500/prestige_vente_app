// Présentations A, B, C de « Gestion Caisse » (et billetage), « Évaluation Vente » et
// « Recherche Article » sur un petit téléphone (360 px), et contrôles de saisie.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/caisse_models.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/product_info.dart';
import 'package:prestige_vente_app/api/models/product_search_result.dart';
import 'package:prestige_vente_app/api/models/product_stats.dart';
import 'package:prestige_vente_app/providers/caisse_provider.dart';
import 'package:prestige_vente_app/providers/product_search_provider.dart';
import 'package:prestige_vente_app/providers/product_stats_provider.dart';
import 'package:prestige_vente_app/screens/caisse/caisse_screen.dart';
import 'package:prestige_vente_app/screens/product_evaluation/product_evaluation_screen.dart';
import 'package:prestige_vente_app/screens/product_search/product_search_screen.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart' show ProductPage;

class _FakeApi extends ApiService {
  // Recherche par pages : mêmes produits que la recherche simulée ci-dessous.
  @override
  Future<ProductPage> searchProductsPageOrFail(String query, int start, int limit) async {
    final all = await searchProducts(query);
    return ProductPage(all.skip(start).take(limit).toList(), all.length);
  }

  _FakeApi({this.inUse = false}) : super(baseUrl: 'http://localhost');

  bool inUse;
  int ouvrirCalls = 0;
  final List<Map<String, int>> clotures = [];
  final List<String> queries = [];

  @override
  Future<OuvertureData?> getOuvertureData() async =>
      OuvertureData(userFullName: 'Awa Kouassi', userId: 'u1', amount: 0, inUse: inUse, createAt: '10/10/2026 08:02');

  @override
  Future<ClotureData?> getClotureData() async => ClotureData(
        totalAmount: 1254300,
        cashFund: 0,
        solde: 125000,
        userFullName: 'Awa Kouassi',
        userId: 'u1',
        resumeCaisseId: 'r1',
        caisseId: 'c1',
        createAt: '10/10/2026 08:02',
        updateAt: '',
      );

  @override
  Future<bool> ouvrirCaisse() async {
    ouvrirCalls++;
    inUse = true;
    return true;
  }

  @override
  Future<bool> cloturerCaisse({required String resumeCaisseId, required Map<String, int> billetage}) async {
    clotures.add(billetage);
    inUse = false;
    return true;
  }

  @override
  Future<List<ProductSearchResult>> searchProducts(String query) async {
    queries.add(query);
    return [
      ProductSearchResult(
        lgFAMILLEID: 'f1',
        strNAME: 'DOLIPRANE 1000MG CP B/8 BOITE FAMILIALE TRES LONGUE DESIGNATION',
        intCIP: '3595583',
        intPRICE: 1500,
        intNUMBERAVAILABLE: 12,
        strLIBELLEE: 'RAYON A3',
        intPAF: 1100,
      ),
      ProductSearchResult(
        lgFAMILLEID: 'f2',
        strNAME: 'DOLIPRANE 500MG CP B/16',
        intCIP: '3000000',
        intPRICE: 900,
        intNUMBERAVAILABLE: 0,
        strLIBELLEE: '',
        intPAF: 600,
      ),
    ];
  }

  ProductInfo _info(String cip) => ProductInfo(
        codeCip: cip,
        emplacement: 'RAYON A3',
        grossiste: 'LABOREX',
        libelle: 'DOLIPRANE 1000MG CP B/8',
        moyenne: 4,
        prixAchat: 1100,
        prixVente: 1500,
        produitId: 'f1',
        stock: 12,
      );

  @override
  Future<ProductInfo?> getProductInfo(String codeCip) async => _info(codeCip);

  @override
  Future<ProductInfo?> getProductInfoForStats(String codeCip) async => _info(codeCip);

  @override
  Future<ProductDetails?> getProductDetailsForSearch(String codeCip) async => null;

  @override
  Future<List<ProductOrderHistory>> getProductOrderHistory(String productId, String dtStart, String dtEnd) async =>
      [ProductOrderHistory(dtEntree: '02/03/2026 10:00', intNumber: 20)];

  @override
  Future<List<ProductAnnualSale>> getAnnualSales(String query, int year) async => [
        ProductAnnualSale.fromJson({'id': 'f1', 'libelle': 'DOLIPRANE 1000MG CP B/8', 'codeCip': query, 'janvier': 12, 'fevrier': 8, 'aout': 1250}),
      ];
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(720, 1400); // 360 x 700
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  Widget app(_FakeApi api, Widget home) => MultiProvider(
        providers: [
          Provider<ApiService>.value(value: api),
          ChangeNotifierProvider(create: (_) => CaisseProvider(api)),
          ChangeNotifierProvider(create: (_) => ProductStatsProvider(api)),
          ChangeNotifierProvider(create: (_) => ProductSearchProvider(api)),
        ],
        child: MaterialApp(home: home),
      );

  Future<void> typeSearch(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField).first, text);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(f, 150, scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
  }

  Future<void> openBilletage(WidgetTester tester) async {
    await tester.tap(find.text('Clôturer la Caisse'));
    await tester.pumpAndSettle();
    expect(find.text('Billetage de Clôture'), findsOneWidget);
  }

  Future<void> setField(WidgetTester tester, String key, String value) async {
    final f = find.byKey(Key('billet_$key'));
    await tester.ensureVisible(f);
    await tester.enterText(f, value);
    await tester.pump();
  }

  for (final style in ListPresentation.values) {
    testWidgets('Caisse fermée puis ouverture — ${style.label}', (tester) async {
      phone(tester);
      final api = _FakeApi();
      await tester.pumpWidget(app(api, CaisseScreen(presentation: style)));
      await tester.pumpAndSettle();
      expect(find.text('Gestion de Caisse'), findsOneWidget);
      expect(find.text('Ouvrir la Caisse'), findsOneWidget);
      expect(find.text('Clôturer la Caisse'), findsOneWidget);
      expect(find.textContaining('Fond de'), findsWidgets);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Ouvrir la Caisse'));
      await tester.pumpAndSettle();
      expect(find.text('Confirmer l\'ouverture'), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Ouvrir')));
      await tester.pumpAndSettle();
      expect(api.ouvrirCalls, 1);
      expect(find.text('Caisse ouverte avec succès.'), findsOneWidget);
      expect(find.textContaining('Solde'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Caisse ouverte, billetage et clôture — ${style.label}', (tester) async {
      phone(tester);
      final api = _FakeApi(inUse: true);
      await tester.pumpWidget(app(api, CaisseScreen(presentation: style)));
      await tester.pumpAndSettle();
      await openBilletage(tester);
      expect(find.text('10 000 F'), findsOneWidget);
      expect(find.text('Autres (Pièces)'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await setField(tester, 'dixMille', '12');
      await setField(tester, 'cinqCent', '10');
      await setField(tester, 'autre', '250');
      expect(find.text(Constants.formatNumber(125250)), findsWidgets); // total compté
      expect(find.text('+${Constants.formatNumber(250)}'), findsWidgets); // écart

      await tester.tap(find.text('Valider la Clôture'));
      await tester.pumpAndSettle();
      expect(find.text('Confirmer la clôture'), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Clôturer')));
      await tester.pumpAndSettle();
      expect(api.clotures, hasLength(1));
      expect(api.clotures.single, {'dixMille': 12, 'cinqMille': 0, 'deuxMille': 0, 'mille': 0, 'cinqCent': 10, 'autre': 250});
      expect(find.text('Billetage de Clôture'), findsNothing);
      expect(find.text('Caisse clôturée avec succès.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Recherche Article — ${style.label}', (tester) async {
      phone(tester);
      final api = _FakeApi();
      await tester.pumpWidget(app(api, ProductSearchScreen(presentation: style)));
      await tester.pumpAndSettle();
      expect(find.text('Recherche Article'), findsOneWidget);
      expect(find.text('Saisissez le nom, le code CIP ou scannez le produit'), findsOneWidget);
      await typeSearch(tester, 'doli');
      expect(find.text('DOLIPRANE 500MG CP B/16'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('DOLIPRANE 500MG CP B/16'));
      await tester.pumpAndSettle();
      expect(find.text('DOLIPRANE 1000MG CP B/8'), findsOneWidget);
      expect(find.text('LABOREX'), findsOneWidget);
      await reveal(tester, find.text('Comparaison Ventes / Commandes'));
      expect(find.text('Comparaison Ventes / Commandes'), findsOneWidget);
      expect(find.text('Nouvelle recherche'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Nouvelle recherche'));
      await tester.pumpAndSettle();
      expect(find.text('Comparaison Ventes / Commandes'), findsNothing);
    });

    testWidgets('Évaluation Vente — ${style.label}', (tester) async {
      phone(tester);
      final api = _FakeApi();
      await tester.pumpWidget(app(api, ProductEvaluationScreen(presentation: style)));
      await tester.pumpAndSettle();
      expect(find.text('Évaluation Vente'), findsOneWidget);
      await typeSearch(tester, 'doli');
      expect(find.text('DOLIPRANE 500MG CP B/16'), findsOneWidget);
      await tester.tap(find.text('DOLIPRANE 500MG CP B/16'));
      await tester.pumpAndSettle();
      expect(find.text('LABOREX'), findsOneWidget);
      await reveal(tester, find.text('Août'));
      expect(find.text('Consommations (Année en cours)'), findsOneWidget);
      expect(find.text('Août'), findsOneWidget);
      expect(find.text('1250'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final compare = find.text('Comparer sur 3 ans');
      await reveal(tester, compare);
      await tester.tap(compare);
      await tester.pumpAndSettle();
      expect(find.text('Comparaison des Ventes Mensuelles'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  group('Contrôles de saisie du billetage', () {
    testWidgets('champ vide refusé, rien envoyé', (tester) async {
      phone(tester);
      final api = _FakeApi(inUse: true);
      await tester.pumpWidget(app(api, const CaisseScreen(presentation: ListPresentation.dashboard)));
      await tester.pumpAndSettle();
      await openBilletage(tester);
      await setField(tester, 'mille', '');
      await tester.tap(find.text('Valider la Clôture'));
      await tester.pumpAndSettle();
      expect(find.text('Requis'), findsOneWidget);
      expect(find.text('Corrigez les champs en rouge.'), findsOneWidget);
      expect(find.text('Confirmer la clôture'), findsNothing);
      expect(api.clotures, isEmpty);
    });

    testWidgets('lettres filtrées, nombre de billets limité à 5 chiffres', (tester) async {
      phone(tester);
      final api = _FakeApi(inUse: true);
      await tester.pumpWidget(app(api, const CaisseScreen(presentation: ListPresentation.compact)));
      await tester.pumpAndSettle();
      await openBilletage(tester);
      await setField(tester, 'dixMille', '1a2-b');
      expect(tester.widget<EditableText>(find.descendant(of: find.byKey(const Key('billet_dixMille')), matching: find.byType(EditableText))).controller.text, '12');
      await setField(tester, 'cinqMille', '1234567');
      expect(tester.widget<EditableText>(find.descendant(of: find.byKey(const Key('billet_cinqMille')), matching: find.byType(EditableText))).controller.text, '12345');
    });

    testWidgets('total absurde refusé, rien envoyé', (tester) async {
      phone(tester);
      final api = _FakeApi(inUse: true);
      await tester.pumpWidget(app(api, const CaisseScreen(presentation: ListPresentation.guided)));
      await tester.pumpAndSettle();
      await openBilletage(tester);
      await setField(tester, 'dixMille', '99999');
      await setField(tester, 'autre', '999999999');
      await tester.tap(find.text('Valider la Clôture'));
      await tester.pumpAndSettle();
      expect(find.text('Total trop élevé : vérifiez le nombre de billets saisis.'), findsOneWidget);
      expect(find.text('Confirmer la clôture'), findsNothing);
      expect(api.clotures, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('« Corriger » dans la confirmation : rien envoyé', (tester) async {
      phone(tester);
      final api = _FakeApi(inUse: true);
      await tester.pumpWidget(app(api, const CaisseScreen(presentation: ListPresentation.dashboard)));
      await tester.pumpAndSettle();
      await openBilletage(tester);
      await tester.tap(find.text('Valider la Clôture'));
      await tester.pumpAndSettle();
      expect(find.text('Attention : aucun billet ni pièce compté.'), findsOneWidget);
      await tester.tap(find.text('Corriger'));
      await tester.pumpAndSettle();
      expect(api.clotures, isEmpty);
      expect(find.text('Billetage de Clôture'), findsOneWidget);
    });
  });

  group('Contrôles de saisie de la recherche', () {
    testWidgets('Recherche Article : vide, trop court, espaces, double requête', (tester) async {
      phone(tester);
      final api = _FakeApi();
      await tester.pumpWidget(app(api, const ProductSearchScreen(presentation: ListPresentation.dashboard)));
      await tester.pumpAndSettle();

      await typeSearch(tester, '    ');
      expect(api.queries, isEmpty);
      await typeSearch(tester, 'a');
      expect(api.queries, isEmpty);
      expect(find.text('Saisissez au moins 2 caractères'), findsOneWidget);

      await typeSearch(tester, '  do\u0007li  ');
      expect(api.queries, ['doli']);

      // Validation du même texte : pas de seconde requête.
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(api.queries, ['doli']);

      // Texte trop long : tronqué à 60 caractères.
      await typeSearch(tester, 'x' * 200);
      expect(api.queries.last.length, 60);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Évaluation Vente : CIP trop court refusé, pas de double requête', (tester) async {
      phone(tester);
      final api = _FakeApi();
      await tester.pumpWidget(app(api, const ProductEvaluationScreen(presentation: ListPresentation.guided)));
      await tester.pumpAndSettle();

      await typeSearch(tester, '12');
      expect(api.queries, isEmpty);
      expect(find.text('Saisissez au moins 3 chiffres'), findsOneWidget);

      await typeSearch(tester, ' doli ');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(api.queries, ['doli']);
      expect(tester.takeException(), isNull);
    });
  });
}
