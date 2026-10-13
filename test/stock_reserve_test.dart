// Stock réserve (serveur 2e4615e) : GET /info renvoie `stockReserve`, `seuilReserve`, `seuilMiniRayon`
// (null si le produit n'est pas géré en réserve, absents d'un serveur ancien).
// Lecture tolérante (ProductInfo, ArticleAnalysis) ; affichage « Stock rayon / Stock réserve / seuils /
// Total rayon + réserve », « — » sans réserve, pastille « À réapprovisionner » ; menus Analyse article
// (A, B, C + fenêtre de détails), fiche produit de l'accueil et Recherche Article ; 360 px et tablette.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestige_vente_app/accueil/fiche_produit_screen.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/article_analysis_model.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/product_info.dart';
import 'package:prestige_vente_app/api/models/product_search_result.dart';
import 'package:prestige_vente_app/api/models/product_stats.dart';
import 'package:prestige_vente_app/api/models/stock_reserve.dart';
import 'package:prestige_vente_app/providers/article_analysis_provider.dart';
import 'package:prestige_vente_app/providers/product_search_provider.dart';
import 'package:prestige_vente_app/screens/analysis/article_analysis_screen.dart';
import 'package:prestige_vente_app/screens/analysis/article_analysis_widgets.dart';
import 'package:prestige_vente_app/screens/product_search/product_search_screen.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart' show ProductPage;
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Réponse GET /info : un produit géré en réserve (rayon 3 ≤ seuil mini 5 → alerte), un non géré.
final _lignesInfo = <Map<String, dynamic>>[
  {
    'produitId': 'f1', 'codeCip': '3595583', 'libelle': 'DOLIPRANE 1000MG CP B/8', 'emplacement': 'RAYON A3',
    'grossiste': 'LABOREX', 'moyenne': 4.5, 'prixAchat': 1100, 'prixVente': 1500, 'quantiteVendue': 30,
    'stock': 3, 'quantiteMois': '1:40,2:45', 'stockReserve': 20, 'seuilReserve': 10, 'seuilMiniRayon': 5,
  },
  {
    'produitId': 'f2', 'codeCip': '3000000', 'libelle': 'EFFERALGAN 500MG CP B/16', 'emplacement': '',
    'grossiste': 'DPCI', 'moyenne': 1, 'prixAchat': 600, 'prixVente': 900, 'quantiteVendue': 3,
    'stock': 14, 'quantiteMois': '', 'stockReserve': null, 'seuilReserve': null, 'seuilMiniRayon': null,
  },
];

ProductSearchResult _produit(String id, String nom, String cip, int stock) => ProductSearchResult(
    lgFAMILLEID: id, strNAME: nom, intCIP: cip, intPRICE: 1500, intNUMBERAVAILABLE: stock, strLIBELLEE: '', intPAF: 1100);

class _FakeApi extends ApiService {
  _FakeApi() : super(baseUrl: 'http://localhost');

  @override
  Future<List<ArticleAnalysis>> fetchArticleAnalysis(String query) async => [for (final j in _lignesInfo) ArticleAnalysis.fromJson(j)];

  @override
  Future<List<ProductSearchResult>> searchProducts(String query) async => [
        _produit('f1', 'DOLIPRANE 1000MG CP B/8', '3595583', 3),
        _produit('f2', 'EFFERALGAN 500MG CP B/16', '3000000', 14),
      ];

  @override
  Future<ProductPage> searchProductsPageOrFail(String query, int start, int limit) async {
    final all = await searchProducts(query);
    return ProductPage(all.skip(start).take(limit).toList(), all.length);
  }

  @override
  Future<ProductInfo?> getProductInfo(String codeCip) async =>
      ProductInfo.fromJson(_lignesInfo.firstWhere((j) => j['codeCip'] == codeCip));

  @override
  Future<ProductDetails?> getProductDetailsForSearch(String codeCip) async => null;

  @override
  Future<List<ProductOrderHistory>> getProductOrderHistory(String productId, String dtStart, String dtEnd) async => [];

  @override
  Future<List<ProductAnnualSale>> getAnnualSales(String query, int year) async => [];
}

void _taille(WidgetTester tester, Size logique) {
  tester.view.physicalSize = logique * 2;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

const _telephone = Size(360, 740);
const _tablette = Size(1024, 1366);

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Lecture tolérante', () {
    test('entierTolerant : nombre, décimal, texte, vide, absent, autre', () {
      expect(entierTolerant(7), 7);
      expect(entierTolerant(7.9), 7);
      expect(entierTolerant('12'), 12);
      expect(entierTolerant(' 12.0 '), 12);
      expect(entierTolerant('3,5'), 3);
      expect(entierTolerant(''), isNull);
      expect(entierTolerant('abc'), isNull);
      expect(entierTolerant(null), isNull);
      expect(entierTolerant(true), isNull);
      expect(entierTolerant(double.infinity), isNull);
    });

    test('ArticleAnalysis (/info) : présents, null, absents (serveur ancien), texte, décimal', () {
      final a = ArticleAnalysis.fromJson(_lignesInfo[0]);
      expect([a.stockReserve, a.seuilReserve, a.seuilMiniRayon], [20, 10, 5]);
      expect(a.reserve.total(a.stock), 23);
      final nuls = ArticleAnalysis.fromJson(_lignesInfo[1]);
      expect(nuls.reserve.geree, isFalse);
      final ancien = ArticleAnalysis.fromJson({'libelle': 'X', 'stock': 4, 'prixVente': 900});
      expect([ancien.stockReserve, ancien.seuilReserve, ancien.seuilMiniRayon], [null, null, null]);
      expect([ancien.stock, ancien.prixVente], [4, 900], reason: 'le reste de la lecture est inchangé');
      final texte = ArticleAnalysis.fromJson({'stockReserve': '15', 'seuilReserve': '4.0', 'seuilMiniRayon': 2.6});
      expect([texte.stockReserve, texte.seuilReserve, texte.seuilMiniRayon], [15, 4, 2]);
      expect(ArticleAnalysis.fromJson({'stockReserve': 0}).reserve.geree, isTrue, reason: 'géré en réserve, rien en réserve');
    });

    test('ProductInfo (/info) : présents, null, absents, texte, décimal', () {
      final p = ProductInfo.fromJson({'stock': 8, 'stockReserve': '4', 'seuilReserve': 5.0, 'seuilMiniRayon': '2'});
      expect([p.stockReserve, p.seuilReserve, p.seuilMiniRayon], [4, 5, 2]);
      final ancien = ProductInfo.fromJson({'stock': 8, 'libelle': 'X'});
      expect(ancien.reserve.geree, isFalse);
      expect([ancien.stock, ancien.libelle], [8, 'X']);
      final nuls = ProductInfo.fromJson({'stock': 8, 'stockReserve': null, 'seuilReserve': null, 'seuilMiniRayon': null});
      expect(nuls.reserve.geree, isFalse);
    });
  });

  group('Règles d\'affichage', () {
    test('lignes : réserve, seuils, total ; sans réserve « — » et pas de total ; seuils à 0 non renseignés', () {
      const r = StockReserve(stockReserve: 20, seuilReserve: 10, seuilMiniRayon: 5);
      expect(stockReserveInfos(3, r), [
        ('Stock rayon', '3'),
        ('Stock réserve', '20'),
        ('Seuil réserve', '10'),
        ('Seuil mini rayon', '5'),
        ('Total rayon + réserve', '23'),
      ]);
      expect(stockReserveInfos(12, StockReserve.aucun), [('Stock rayon', '12'), ('Stock réserve', '—')]);
      expect(stockReserveInfos(12, StockReserve.aucun, avecRayon: false), [('Stock réserve', '—')]);
      expect(stockReserveInfos(0, const StockReserve(stockReserve: 0, seuilReserve: 0, seuilMiniRayon: 0)),
          [('Stock rayon', '0'), ('Stock réserve', '0'), ('Total rayon + réserve', '0')]);
    });

    test('alerte : rayon ≤ seuil mini rayon ou réserve ≤ seuil réserve', () {
      const r = StockReserve(stockReserve: 20, seuilReserve: 10, seuilMiniRayon: 5);
      expect(r.aReapprovisionner(5), isTrue);
      expect(r.aReapprovisionner(6), isFalse);
      expect(const StockReserve(stockReserve: 10, seuilReserve: 10).aReapprovisionner(50), isTrue);
      expect(StockReserve.aucun.aReapprovisionner(0), isFalse, reason: 'non géré en réserve : pas d\'alerte');
      expect(const StockReserve(stockReserve: 0, seuilReserve: 0, seuilMiniRayon: 0).aReapprovisionner(0), isFalse);
    });

    testWidgets('pastille et résumé lisibles en thème sombre', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: const Scaffold(body: StockReserveResume(reserve: StockReserve(stockReserve: 2, seuilReserve: 5), rayon: 1)),
      ));
      expect(find.text('Réserve : 2 · Total : 3'), findsOneWidget);
      expect(find.text('À réapprovisionner'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Analyse article', () {
    for (final taille in [_telephone, _tablette]) {
      for (final style in ListPresentation.values) {
        testWidgets('${style.label} (${taille.width.toInt()} px) : liste, détails, « — », alerte', (tester) async {
          _taille(tester, taille);
          await tester.pumpWidget(ChangeNotifierProvider(
            create: (_) => ArticleAnalysisProvider(_FakeApi()),
            child: MaterialApp(home: ArticleAnalysisScreen(presentation: style)),
          ));
          await tester.enterText(find.byType(TextField).first, 'doli');
          await tester.pump(const Duration(milliseconds: 600));
          await tester.pumpAndSettle();
          // Liste : résumé seulement pour le produit géré en réserve.
          expect(find.text('Réserve : 20 · Total : 23'), findsOneWidget);
          expect(find.textContaining('Réserve :'), findsOneWidget);
          expect(find.text('À réapprovisionner'), findsOneWidget, reason: 'rayon 3 ≤ seuil mini 5');
          expect(tester.takeException(), isNull);

          await tester.tap(find.text('DOLIPRANE 1000MG CP B/8').first);
          await tester.pumpAndSettle();
          var bloc = find.byKey(const ValueKey('analyse-stock-reserve'));
          for (final t in ['Stock rayon', 'Stock réserve', '20', 'Seuil réserve', '10', 'Seuil mini rayon', '5', 'Total rayon + réserve', '23']) {
            expect(find.descendant(of: bloc, matching: find.text(t)), findsOneWidget, reason: t);
          }
          expect(find.descendant(of: bloc, matching: find.byKey(const ValueKey('pastille-reappro'))), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.byIcon(Icons.close));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('analyse-stock-reserve')), findsNothing);

          // C : seule la première carte s'ouvre d'un toucher ; les suivantes par leur bouton « Analyser ».
          final ouvrir = style == ListPresentation.guided
              ? find.byTooltip('Analyser EFFERALGAN 500MG CP B/16')
              : find.text('EFFERALGAN 500MG CP B/16');
          await tester.ensureVisible(ouvrir);
          await tester.pumpAndSettle();
          await tester.tap(ouvrir);
          await tester.pumpAndSettle();
          bloc = find.byKey(const ValueKey('analyse-stock-reserve'));
          expect(find.descendant(of: bloc, matching: find.text('Stock rayon')), findsOneWidget);
          expect(find.descendant(of: bloc, matching: find.text('14')), findsOneWidget);
          expect(find.descendant(of: bloc, matching: find.text('—')), findsOneWidget);
          expect(find.descendant(of: bloc, matching: find.text('Total rayon + réserve')), findsNothing);
          expect(find.descendant(of: bloc, matching: find.text('Seuil réserve')), findsNothing);
          expect(find.descendant(of: bloc, matching: find.byKey(const ValueKey('pastille-reappro'))), findsNothing);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('Fiche produit (accueil)', () {
    for (final style in ListPresentation.values) {
      testWidgets('${style.label} (360 px) : réserve, seuils, total, alerte', (tester) async {
        _taille(tester, _telephone);
        await tester.pumpWidget(MaterialApp(
          home: FicheProduitScreen(
            produit: _produit('f1', 'DOLIPRANE 1000MG CP B/8', '3595583', 3),
            loadAnalyse: (_) async => [for (final j in _lignesInfo) ArticleAnalysis.fromJson(j)],
            presentation: style,
          ),
        ));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('fiche-reserve-Stock rayon')), findsOneWidget);
        expect(find.descendant(of: find.byKey(const ValueKey('fiche-reserve-Stock réserve')), matching: find.text('20')), findsOneWidget);
        expect(find.descendant(of: find.byKey(const ValueKey('fiche-reserve-Total rayon + réserve')), matching: find.text('23')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('fiche-reserve-Seuil réserve')), findsOneWidget);
        expect(find.byKey(const ValueKey('fiche-reserve-Seuil mini rayon')), findsOneWidget);
        expect(find.byKey(const ValueKey('pastille-reappro')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('sans réserve : « — », ni total ni alerte', (tester) async {
      _taille(tester, _telephone);
      await tester.pumpWidget(MaterialApp(
        home: FicheProduitScreen(
          produit: _produit('f2', 'EFFERALGAN 500MG CP B/16', '3000000', 14),
          loadAnalyse: (_) async => [for (final j in _lignesInfo) ArticleAnalysis.fromJson(j)],
          presentation: ListPresentation.dashboard,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byKey(const ValueKey('fiche-reserve-Stock réserve')), matching: find.text('—')), findsOneWidget);
      expect(find.byKey(const ValueKey('fiche-reserve-Total rayon + réserve')), findsNothing);
      expect(find.byKey(const ValueKey('pastille-reappro')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Recherche Article', () {
    for (final style in ListPresentation.values) {
      testWidgets('${style.label} (360 px) : réserve, total, alerte ; « — » sans réserve', (tester) async {
        _taille(tester, _telephone);
        final api = _FakeApi();
        Future<void> ouvrir(String nom) async {
          await tester.enterText(find.byType(TextField).first, 'doli');
          await tester.pump(const Duration(milliseconds: 600));
          await tester.pumpAndSettle();
          await tester.tap(find.text(nom));
          await tester.pumpAndSettle();
        }

        // Liste paresseuse (B) : les lignes sous l'écran ne sont construites qu'au défilement.
        Future<void> voir(Key cle) async {
          await tester.scrollUntilVisible(find.byKey(cle), 120, scrollable: find.byType(Scrollable).last);
          await tester.pumpAndSettle();
        }

        await tester.pumpWidget(MultiProvider(
          providers: [
            Provider<ApiService>.value(value: api),
            ChangeNotifierProvider(create: (_) => ProductSearchProvider(api)),
          ],
          child: MaterialApp(home: ProductSearchScreen(presentation: style)),
        ));
        await tester.pumpAndSettle();
        await ouvrir('DOLIPRANE 1000MG CP B/8');
        await voir(const ValueKey('recherche-reserve-Stock réserve'));
        expect(find.descendant(of: find.byKey(const ValueKey('recherche-reserve-Stock réserve')), matching: find.text('20')),
            findsOneWidget);
        await voir(const ValueKey('recherche-reserve-Total rayon + réserve'));
        expect(find.descendant(of: find.byKey(const ValueKey('recherche-reserve-Total rayon + réserve')), matching: find.text('23')),
            findsOneWidget);
        await voir(const ValueKey('pastille-reappro'));
        expect(find.byKey(const ValueKey('pastille-reappro')), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Nouvelle recherche'));
        await tester.pumpAndSettle();
        await ouvrir('EFFERALGAN 500MG CP B/16');
        await voir(const ValueKey('recherche-reserve-Stock réserve'));
        expect(find.descendant(of: find.byKey(const ValueKey('recherche-reserve-Stock réserve')), matching: find.text('—')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('recherche-reserve-Total rayon + réserve')), findsNothing);
        expect(find.byKey(const ValueKey('pastille-reappro')), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
