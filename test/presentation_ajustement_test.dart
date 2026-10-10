// Ajustement de stock : les trois présentations (A, B, C) sur un petit téléphone (360 px),
// contrôles de saisie (rien n'est envoyé si la saisie est absurde), échecs réseau affichés
// clairement, clôture confirmée avec récapitulatif et impression unique.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/ajustement.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/providers/ajustement_provider.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/screens/ajustement/ajustement_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart' show ProductPage;

const _longName = 'DOLIPRANE 1000MG COMPRIMES PELLICULES SECABLES BOITE DE 8 GRAND FORMAT';

ProductSearchResult _product({int stock = 12}) => ProductSearchResult(
      lgFAMILLEID: 'f1',
      strNAME: _longName,
      intCIP: '3400936',
      intPRICE: 1500,
      intNUMBERAVAILABLE: stock,
      strLIBELLEE: '',
      intPAF: 1100,
    );

class _Api extends ApiService {
  // Recherche par pages : mêmes produits que la recherche simulée ci-dessous.
  @override
  Future<ProductPage> searchProductsPageOrFail(String query, int start, int limit) async {
    final all = await searchProductsOrFail(query);
    return ProductPage(all.skip(start).take(limit).toList(), all.length);
  }

  _Api() : super(baseUrl: 'http://localhost');

  String? typesFailure;
  String? itemsFailure;
  bool postOk = true;
  bool putOk = true;
  int stock = 12;
  final calls = <String>[];
  final lines = <Map<String, dynamic>>[];

  @override
  Future<List<TypeAjustement>> getTypesAjustement() async {
    if (typesFailure != null) throw ApiLoadException(typesFailure!);
    return [TypeAjustement(id: 1, libelle: 'Casse'), TypeAjustement(id: 2, libelle: 'Inventaire')];
  }

  @override
  Future<List<AjustementItem>> getAjustementItems(String ajustementId) async {
    if (itemsFailure != null) throw ApiLoadException(itemsFailure!);
    return [
      for (var i = 0; i < lines.length; i++)
        AjustementItem(
          lgAJUSTEMENTDETAILID: 'd$i',
          lgAJUSTEMENTID: ajustementId,
          lgFAMILLEID: lines[i]['refTwo'] as String,
          strNAME: _longName,
          intCIP: '3400936',
          intPRICE: 1500,
          intPAF: 1100,
          intNUMBER: lines[i]['value'] as int,
          intNUMBERCURRENTSTOCK: lines[i]['valueTwo'] as int,
          intNUMBERAFTERSTOCK: (lines[i]['valueTwo'] as int) + (lines[i]['value'] as int),
          motifAjustement: lines[i]['valueFour'] == 1 ? 'Casse' : 'Inventaire',
          operateur: 'Awa',
          dateOperation: '10/10/2026',
          heure: '09:41',
        ),
    ];
  }

  @override
  Future<List<ProductSearchResult>> searchProducts(String query) async => [_product(stock: stock)];

  @override
  Future<List<ProductSearchResult>> searchProductsOrFail(String query) async => [_product(stock: stock)];

  @override
  Future<dynamic> request({required String method, required String url, Map<String, dynamic>? data, Map<String, dynamic>? queryParameters}) async {
    calls.add('$method $url');
    if (method == 'POST') {
      if (!postOk) return null;
      lines.add(data!);
      return {
        'success': true,
        'data': {'lgAJUSTEMENTID': 'AJ1'}
      };
    }
    if (method == 'PUT') {
      if (!putOk) return null;
      lines.clear();
      return {'success': true};
    }
    return null;
  }

  int get posts => calls.where((c) => c.startsWith('POST')).length;
  int get puts => calls.where((c) => c.startsWith('PUT')).length;
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(720, 1400); // 360 x 700
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

/// Ajoute des lignes directement par le provider (comme le ferait le dialogue).
Future<void> _seed(WidgetTester tester, AjustementProvider provider, List<int> quantities) async {
  for (final q in quantities) {
    final f = provider.addProduct(product: _product(), quantity: q, typeAjustementId: 1);
    await tester.pump(const Duration(milliseconds: 400));
    expect(await f, isTrue);
  }
  await tester.pump();
}

Future<void> _pumpScreen(
  WidgetTester tester,
  _Api api,
  AjustementProvider provider, {
  ListPresentation style = ListPresentation.dashboard,
  Future<void> Function(List<AjustementItem>, String)? printer,
  bool pushed = false,
}) async {
  final screen = AjustementScreen(presentation: style, printTicket: printer ?? (_, __) async {});
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AjustementProvider>.value(value: provider),
      ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider(api)),
    ],
    child: MaterialApp(
      home: pushed
          ? Builder(
              builder: (ctx) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => screen)),
                    child: const Text('Ouvrir'),
                  ),
                ),
              ),
            )
          : screen,
    ),
  ));
  if (pushed) {
    await tester.tap(find.text('Ouvrir'));
  }
  await tester.pumpAndSettle();
}

/// Ouvre le dialogue de quantité : saisie dans la recherche → liste des produits → produit.
Future<void> _openAddDialog(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, 'DOLI');
  await tester.pump(const Duration(milliseconds: 900));
  await tester.pumpAndSettle();
  await tester.tap(find.text('CIP: 3400936 | Stock: 12'));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
  expect(find.text('Stock Actuel : 12'), findsOneWidget);
}

Finder _qtyField() => find.widgetWithText(TextFormField, 'Quantité');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final style in ListPresentation.values) {
    testWidgets('Ajustement — ${style.label} : vide puis avec lignes, sans débordement', (tester) async {
      _phone(tester);
      final api = _Api();
      final provider = AjustementProvider(api);

      await _pumpScreen(tester, api, provider, style: style);
      expect(find.text('Ajustement de Stock'), findsOneWidget);
      expect(find.text('Aucun ajustement en cours'), findsOneWidget);
      expect(find.text('Rechercher un produit'), findsOneWidget);
      expect(find.text('CLÔTURER AJUSTEMENT'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _seed(tester, provider, [5, -3]);
      await tester.pumpAndSettle();
      expect(find.text(_longName), findsNWidgets(2));
      expect(find.text('+5'), findsWidgets);
      expect(find.text('−3'), findsWidgets);
      expect(find.text('17'), findsOneWidget); // 12 → 17
      expect(find.text('9'), findsOneWidget); // 12 → 9
      expect(find.text('CLÔTURER AJUSTEMENT (2)'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('Saisie absurde refusée : rien n\'est envoyé', (tester) async {
    _phone(tester);
    final api = _Api();
    final provider = AjustementProvider(api);
    await _pumpScreen(tester, api, provider);
    await _openAddDialog(tester);

    // Ni sens ni quantité.
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(find.text('Quantité requise'), findsOneWidget);
    expect(find.text('Choisissez Entrée ou Sortie'), findsOneWidget);

    // Zéro refusé.
    await tester.tap(find.text('− Sortie'));
    await tester.enterText(_qtyField(), '0');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(find.text('La quantité doit être au moins 1'), findsOneWidget);

    // Lettres et signes filtrés.
    await tester.enterText(_qtyField(), '-2a');
    await tester.pump();
    expect(find.text('2'), findsWidgets);

    // Code-barres scanné dans la quantité : refusé.
    await tester.enterText(_qtyField(), '3400936123456');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(find.text('Trop grand (max 9999). Erreur de scan ?'), findsOneWidget);

    expect(api.posts, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Écart très grand : confirmation, « Corriger » n\'envoie rien', (tester) async {
    _phone(tester);
    final api = _Api();
    final provider = AjustementProvider(api);
    await _pumpScreen(tester, api, provider);
    await _openAddDialog(tester);

    await tester.tap(find.text('− Sortie'));
    await tester.enterText(_qtyField(), '30'); // stock 12 → −18
    await tester.pump();
    expect(find.text('-18'), findsOneWidget);
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(find.text('Quantité élevée'), findsOneWidget);
    expect(find.textContaining('Le stock deviendrait négatif'), findsOneWidget);
    expect(find.textContaining('Écart très grand'), findsOneWidget);
    await tester.tap(find.text('Corriger'));
    await tester.pumpAndSettle();
    expect(api.posts, 0);
    expect(find.text('Stock Actuel : 12'), findsOneWidget); // dialogue toujours ouvert
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ligne envoyée : attend le serveur ; échec affiché, rien présenté comme enregistré', (tester) async {
    _phone(tester);
    final api = _Api()..postOk = false;
    final provider = AjustementProvider(api);
    await _pumpScreen(tester, api, provider);
    await _openAddDialog(tester);

    await tester.tap(find.text('+ Entrée'));
    await tester.enterText(_qtyField(), '4');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(api.posts, 1);
    expect(find.textContaining('Ligne NON enregistrée'), findsOneWidget);
    expect(find.text('Stock Actuel : 12'), findsOneWidget); // saisie conservée
    expect(provider.items, isEmpty);

    // Réessai réussi : le dialogue se ferme et la ligne apparaît.
    api.postOk = true;
    await tester.tap(find.text('Valider'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(api.posts, 2);
    expect(find.text('Stock Actuel : 12'), findsNothing);
    expect(find.text('+4'), findsWidgets);
    expect(api.lines.single['value'], 4);
    expect(api.lines.single['valueFour'], 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Clôture : récapitulatif, un seul envoi, une seule impression', (tester) async {
    _phone(tester);
    final api = _Api();
    final provider = AjustementProvider(api);
    var prints = 0;
    await _pumpScreen(tester, api, provider, printer: (items, user) async {
      prints++;
      expect(items.length, 3);
    });
    await _seed(tester, provider, [5, -3, -2]);
    await tester.pumpAndSettle();

    await tester.tap(find.text('CLÔTURER AJUSTEMENT (3)'));
    await tester.pumpAndSettle();
    expect(find.text("Confirmer l'ajustement"), findsOneWidget);
    expect(find.text('Clôturer cet ajustement de 3 lignes ?'), findsOneWidget);
    expect(find.text('Entrées (1 ligne)'), findsOneWidget);
    expect(find.text('Sorties (2 lignes)'), findsOneWidget);
    expect(find.text('−5'), findsWidgets);

    await tester.tap(find.text('Oui, clôturer'));
    await tester.pumpAndSettle();
    expect(api.puts, 1);
    expect(find.textContaining('imprimer le bon'), findsOneWidget);
    await tester.tap(find.text('Oui, imprimer'));
    await tester.pumpAndSettle();
    expect(prints, 1);
    expect(find.text('Aucun ajustement en cours'), findsOneWidget);
    expect(find.text('Dernier ajustement validé (3 lignes)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Clôture refusée (réseau) : message clair, lignes conservées', (tester) async {
    _phone(tester);
    final api = _Api()..putOk = false;
    final provider = AjustementProvider(api);
    await _pumpScreen(tester, api, provider);
    await _seed(tester, provider, [1]);
    await tester.pumpAndSettle();

    await tester.tap(find.text('CLÔTURER AJUSTEMENT (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Oui, clôturer'));
    await tester.pumpAndSettle();
    expect(find.text('Ajustement NON validé'), findsOneWidget);
    expect(find.textContaining('Clôture NON confirmée'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(provider.items.length, 1);
    expect(find.text('CLÔTURER AJUSTEMENT (1)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Motifs non chargés : bandeau d\'erreur, ajout bloqué', (tester) async {
    _phone(tester);
    final api = _Api()..typesFailure = 'Serveur injoignable (motifs d\'ajustement non chargés).';
    final provider = AjustementProvider(api);
    await _pumpScreen(tester, api, provider);
    expect(find.textContaining('Serveur injoignable'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);

    await tester.ensureVisible(find.text('Rechercher un produit'));
    await tester.tap(find.text('Rechercher un produit'));
    await tester.pumpAndSettle();
    expect(find.textContaining('impossible d\'ajouter une ligne'), findsWidgets);
    expect(find.text('Recherche produit...'), findsNothing); // pas de modal

    api.typesFailure = null;
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Serveur injoignable'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Lignes non rechargées : bandeau (≠ liste vide)', (tester) async {
    _phone(tester);
    final api = _Api();
    final provider = AjustementProvider(api);
    await _pumpScreen(tester, api, provider);
    await _seed(tester, provider, [2]);
    api.itemsFailure = 'Serveur injoignable (lignes d\'ajustement non chargés).';
    await provider.refreshItems();
    await tester.pumpAndSettle();
    expect(find.textContaining('Lignes non rechargées'), findsOneWidget);
    expect(find.text(_longName), findsOneWidget); // lignes déjà connues conservées
    expect(tester.takeException(), isNull);
  });

  testWidgets('Quitter avec des lignes non clôturées : confirmation', (tester) async {
    _phone(tester);
    final api = _Api();
    final provider = AjustementProvider(api);
    await _pumpScreen(tester, api, provider, pushed: true);
    await _seed(tester, provider, [2]);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Retour'));
    await tester.pumpAndSettle();
    expect(find.text('Ajustement non clôturé'), findsOneWidget);
    await tester.tap(find.text('Rester'));
    await tester.pumpAndSettle();
    expect(find.text('Ajustement de Stock'), findsOneWidget);

    await tester.tap(find.byTooltip('Retour'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quitter quand même'));
    await tester.pumpAndSettle();
    expect(find.text('Ouvrir'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
