// État de Stock : présentations A, B, C sur 360 px, erreurs de chargement distinguées
// d'une liste vide, contrôles de saisie des filtres et absence de double requête.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/rayon.dart';
import 'package:prestige_vente_app/api/models/stock_report_models.dart';
import 'package:prestige_vente_app/providers/stock_report_provider.dart';
import 'package:prestige_vente_app/screens/stock_report/stock_report_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

StockReportItem _item(String id, String libelle, {int stock = 10, int seuil = 0, String rayon = 'RAYON A3'}) => StockReportItem.fromJson({
      'id': id,
      'code': '359${id.padLeft(4, '0')}',
      'codeEan': '',
      'libelle': libelle,
      'prixVente': 1500,
      'prixAchat': 1100,
      'stock': stock,
      'rayonLibelle': rayon,
      'grossisteId': 'g1',
      'seuiRappro': seuil,
      'qteReappro': 5,
      'tva': '0',
    });

class _FakeApi extends ApiService {
  _FakeApi() : super(baseUrl: 'http://localhost');

  List<StockReportItem> items = [
    _item('1', 'DOLIPRANE 1000MG CP B/8 BOITE FAMILIALE TRÈS LONGUE DÉSIGNATION', stock: 0),
    _item('2', 'DOLIPRANE 500MG CP B/16', stock: 3, seuil: 5),
    _item('3', 'EFFERALGAN 1G', stock: 40),
  ];
  int total = 3;
  Object? reportError;
  Object? rayonsError;
  List<Rayon> rayons = [
    Rayon(id: 'r1', libelle: 'RAYON A3'),
    Rayon(id: 'r1', libelle: 'RAYON A3 (doublon)'),
    Rayon(id: '', libelle: 'SANS CODE'),
    Rayon(id: 'r2', libelle: 'RÉSERVE'),
  ];
  final calls = <Map<String, String>>[];

  @override
  Future<List<Rayon>> getRayonsForFilters() async {
    if (rayonsError != null) throw rayonsError!;
    return rayons;
  }

  @override
  Future<List<Grossiste>> getGrossistes() async => [Grossiste(id: 'g1', libelle: 'LABOREX')];

  @override
  Future<Map<String, dynamic>> getStockReport({
    String query = '',
    String codeRayon = '',
    String codeGrossiste = '',
    String filtreStock = '',
    String stockValue = '',
    int page = 1,
    int limit = 20,
  }) async {
    calls.add({'query': query, 'codeRayon': codeRayon, 'filtreStock': filtreStock, 'stock': stockValue});
    if (reportError != null) throw reportError!;
    return {'data': items, 'total': total};
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(720, 1400); // 360 x 700
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  Future<void> open(WidgetTester tester, _FakeApi api, ListPresentation style) async {
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => StockReportProvider(api),
      child: MaterialApp(home: StockReportScreen(presentation: style)),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('stock_search')), text);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(f, 150,
        scrollable: find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first);
    await tester.pumpAndSettle();
  }

  for (final style in ListPresentation.values) {
    testWidgets('État de Stock — ${style.label} : liste, statuts, détail', (tester) async {
      phone(tester);
      final api = _FakeApi()..total = 57;
      await open(tester, api, style);

      expect(find.text('État de Stock'), findsOneWidget);
      expect(find.text('Saisissez des critères pour rechercher'), findsOneWidget);
      expect(api.calls, isEmpty);

      await search(tester, 'doli');
      expect(api.calls.single['query'], 'doli');
      if (style == ListPresentation.dashboard) {
        expect(find.text('rupture(s)'), findsOneWidget);
        expect(find.text('valeur achat F'), findsOneWidget);
      }
      if (style == ListPresentation.compact) expect(find.text('sous seuil'), findsOneWidget);
      if (style == ListPresentation.guided) expect(find.text('Critères'), findsOneWidget);
      expect(find.textContaining('3 premiers articles sur 57'), findsOneWidget);
      // Les filtres défilent avec la liste.
      await reveal(tester, find.text('DOLIPRANE 500MG CP B/16'));
      expect(find.text('Rupture'), findsOneWidget);
      expect(find.text('Sous seuil'), findsOneWidget);
      await reveal(tester, find.text('EFFERALGAN 1G'));
      expect(tester.takeException(), isNull);

      // Détail (le libellé du grossiste vient de la liste du serveur).
      await tester.tap(find.text('EFFERALGAN 1G'));
      await tester.pumpAndSettle();
      expect(find.text('LABOREX'), findsOneWidget);
      expect(find.text('Fermer'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('État de Stock — ${style.label} : erreur réseau ≠ liste vide', (tester) async {
      phone(tester);
      final api = _FakeApi()..reportError = const ApiLoadException('Serveur injoignable (articles non chargés).');
      await open(tester, api, style);
      await search(tester, 'doli');

      expect(find.text('Chargement impossible'), findsOneWidget);
      expect(find.text('Serveur injoignable (articles non chargés).'), findsOneWidget);
      expect(find.text('Aucun article trouvé.'), findsNothing);

      api.reportError = null;
      api.items = [];
      await tester.ensureVisible(find.text('Réessayer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(api.calls.length, 2);
      expect(find.text('Chargement impossible'), findsNothing);
      expect(find.text('Aucun article trouvé.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('Emplacements non chargés : bandeau visible, liste déroulante sans doublon', (tester) async {
    phone(tester);
    final api = _FakeApi()..rayonsError = const ApiLoadException('Erreur du serveur (code 500).');
    await open(tester, api, ListPresentation.dashboard);
    expect(find.textContaining('Emplacements non chargés'), findsOneWidget);

    api.rayonsError = null;
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Emplacements non chargés'), findsNothing);

    // Doublons et identifiants vides écartés : pas d'assertion de la liste déroulante.
    await tester.tap(find.byKey(const Key('stock_rayon')));
    await tester.pumpAndSettle();
    expect(find.text('RAYON A3 (doublon)'), findsNothing);
    expect(find.text('SANS CODE'), findsNothing);
    await tester.tap(find.text('RÉSERVE').last);
    await tester.pumpAndSettle();
    expect(api.calls.last['codeRayon'], 'r2');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Valeur de stock : chiffres seulement, 5 au plus ; filtre appliqué seulement avec une valeur', (tester) async {
    phone(tester);
    final api = _FakeApi();
    await open(tester, api, ListPresentation.dashboard);

    await tester.tap(find.byKey(const Key('stock_filter_type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supérieur à (>)').last);
    await tester.pumpAndSettle();
    expect(find.text('Saisissez une valeur de stock pour appliquer le filtre.'), findsOneWidget);
    // Pas de valeur : rien n'est envoyé.
    expect(api.calls, isEmpty);

    // Saisie fantaisiste : lettres refusées.
    await tester.enterText(find.byKey(const Key('stock_value')), 'abc');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(find.byKey(const Key('stock_value'))).controller!.text, '');
    expect(api.calls.where((c) => c['filtreStock']!.isNotEmpty), isEmpty);

    // Valeur trop longue : limitée à 5 chiffres (≤ 99999).
    await tester.enterText(find.byKey(const Key('stock_value')), '12a345678');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(find.byKey(const Key('stock_value'))).controller!.text, '12345');
    expect(api.calls.last, {'query': '', 'codeRayon': '', 'filtreStock': 'GREATER', 'stock': '12345'});
    expect(find.text('Saisissez une valeur de stock pour appliquer le filtre.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Recherche : texte nettoyé, pas de double requête pour la même saisie', (tester) async {
    phone(tester);
    final api = _FakeApi();
    await open(tester, api, ListPresentation.compact);

    await search(tester, '  doli  ');
    expect(api.calls.single['query'], 'doli');
    await search(tester, 'doli ');
    expect(api.calls.length, 1);

    // Caractères de contrôle et longueur bornés.
    expect(find.text('DOLIPRANE 500MG CP B/16'), findsOneWidget);
    await search(tester, 'dol\u0007i${'x' * 100}');
    expect(api.calls.last['query']!.length, lessThanOrEqualTo(60));
    expect(api.calls.last['query']!.contains('\u0007'), isFalse);

    // Vider les filtres : liste vidée, état initial.
    await tester.tap(find.byTooltip('Vider les filtres'));
    await tester.pumpAndSettle();
    expect(find.text('Saisissez des critères pour rechercher'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('Lecture défensive des articles du serveur', () {
    final i = StockReportItem.fromJson({'id': 7, 'stock': '12', 'prixVente': 1500.0, 'libelle': null, 'seuiRappro': 'x'});
    expect(i.id, '7');
    expect(i.stock, 12);
    expect(i.prixVente, 1500);
    expect(i.libelle, '');
    expect(i.seuiRappro, 0);
  });
}
