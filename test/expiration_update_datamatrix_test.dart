import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/providers/expiration_update_provider.dart';
import 'package:prestige_vente_app/screens/expiration_update/expiration_update_screen.dart';
import 'package:provider/provider.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(baseUrl: 'http://localhost');

  final Map<String, List<ProductSearchResult>> catalog = {};
  final List<String> searches = [];
  final List<Map<String, dynamic>> addLotCalls = [];

  @override
  Future<List<ProductSearchResult>> searchProducts(String query) async {
    searches.add(query);
    return catalog[query] ?? [];
  }

  @override
  Future<bool> addLot({
    required String produitId,
    required String datePeremption,
    required String numLot,
    required int quantity,
  }) async {
    addLotCalls.add({
      'produitId': produitId,
      'datePeremption': datePeremption,
      'numLot': numLot,
      'quantity': quantity,
    });
    return true;
  }
}

ProductSearchResult _product(String id, String name, String cip) => ProductSearchResult(
      lgFAMILLEID: id,
      strNAME: name,
      intCIP: cip,
      intPRICE: 1000,
      intNUMBERAVAILABLE: 5,
      strLIBELLEE: '',
      intPAF: 800,
    );

void main() {
  const gs = '\u001d';
  const gtin = '03400935955838';
  final doliprane = _product('15712354735457071135', 'DOLIPRANE 1000MG CP', '3595583');
  final efferalgan = _product('999', 'EFFERALGAN 500', '1234567');

  late _FakeApi api;

  Future<void> pumpScreen(WidgetTester tester, {String? cameraCode, List<String>? labelLines}) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ExpirationUpdateProvider(api),
        child: MaterialApp(
          home: ExpirationUpdateScreen(
            codeScanner: (_) async => cameraCode,
            labelReader: (_) async => labelLines,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);
  String text(WidgetTester tester, String label) =>
      tester.widget<TextFormField>(field(label)).controller!.text;
  final search = find.byType(TextField).first;

  setUp(() {
    api = _FakeApi()
      ..catalog['3400935955838'] = [doliprane]
      ..catalog['doliprane'] = [doliprane]
      ..catalog['efferalgan'] = [efferalgan];
  });

  testWidgets('scan DataMatrix : produit trouvé, lot et date pré-remplis, envoi add-lot', (tester) async {
    await pumpScreen(tester);
    await tester.enterText(search, '01${gtin}17261002${gs}107445');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(find.text('DOLIPRANE 1000MG CP'), findsOneWidget);
    expect(text(tester, 'Date de Péremption (JJMMYY)'), '02/10/2026');
    expect(text(tester, 'N° de Lot'), '7445');
    expect(text(tester, 'Quantité'), '1');
    // Le focus est sur la quantité : l'opérateur saisit la quantité du lot et valide.
    final qtyField = tester.widget<EditableText>(find.descendant(of: field('Quantité'), matching: find.byType(EditableText)));
    expect(qtyField.focusNode.hasFocus, isTrue);

    await tester.enterText(field('Quantité'), '3');
    await tester.ensureVisible(find.text('Valider'));
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();

    expect(api.addLotCalls, [
      {'produitId': '15712354735457071135', 'datePeremption': '2026-10-02', 'numLot': '7445', 'quantity': 3},
    ]);
    // Retour à la recherche, prêt pour la boîte suivante
    expect(find.text('DataMatrix lu'), findsNothing);
    expect(field('N° de Lot'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('recherche classique sans DataMatrix inchangée', (tester) async {
    await pumpScreen(tester);
    await tester.enterText(search, 'doliprane');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(api.searches, ['doliprane']);
    expect(find.text('DataMatrix lu'), findsNothing);
    expect(text(tester, 'Date de Péremption (JJMMYY)'), '');
    expect(text(tester, 'N° de Lot'), '');

    await tester.enterText(field('Date de Péremption (JJMMYY)'), '021026');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    final lotEditable = tester.widget<EditableText>(find.descendant(of: field('N° de Lot'), matching: find.byType(EditableText)));
    expect(lotEditable.focusNode.hasFocus, isTrue);
    expect(find.text('Le N° de lot est requis'), findsNothing);
    await tester.enterText(field('N° de Lot'), 'A1');
    await tester.enterText(field('Quantité'), '2');
    await tester.ensureVisible(find.text('Valider'));
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(api.addLotCalls.single,
        {'produitId': '15712354735457071135', 'datePeremption': '2026-10-02', 'numLot': 'A1', 'quantity': 2});
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('produit introuvable par GTIN : recherche par nom puis report du lot', (tester) async {
    api.catalog.remove('3400935955838');
    await pumpScreen(tester);
    await tester.enterText(search, '01${gtin}17271031${gs}10LOTX');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(api.searches, ['3400935955838', '3595583']);
    expect(find.textContaining('Produit introuvable'), findsOneWidget);

    await tester.enterText(search, 'doliprane');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(text(tester, 'N° de Lot'), 'LOTX');
    expect(text(tester, 'Date de Péremption (JJMMYY)'), '31/10/2027');
  });

  testWidgets('lot ambigu : proposé en choix, jamais imposé', (tester) async {
    await pumpScreen(tester);
    await tester.enterText(search, '01${gtin}17271031107445213456789');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(text(tester, 'N° de Lot'), '');
    expect(find.widgetWithText(ActionChip, '7445'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(ActionChip, '7445'));
    await tester.tap(find.widgetWithText(ActionChip, '7445'));
    await tester.pumpAndSettle();
    expect(text(tester, 'N° de Lot'), '7445');
    expect(find.byType(ActionChip), findsNothing);
  });

  testWidgets('DataMatrix lu dans un champ du formulaire : jamais envoyé tel quel', (tester) async {
    await pumpScreen(tester);
    await tester.enterText(search, 'doliprane');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    await tester.enterText(field('Date de Péremption (JJMMYY)'), '01${gtin}17261002${gs}107445');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();

    expect(find.text('DOLIPRANE 1000MG CP'), findsOneWidget);
    expect(text(tester, 'Date de Péremption (JJMMYY)'), '02/10/2026');
    expect(text(tester, 'N° de Lot'), '7445');
    expect(api.addLotCalls, isEmpty);
  });

  testWidgets('changement manuel de produit après un scan : le scan est abandonné', (tester) async {
    await pumpScreen(tester);
    await tester.enterText(search, '01${gtin}17261002${gs}107445');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(text(tester, 'N° de Lot'), '7445');

    await tester.enterText(search, 'efferalgan');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('EFFERALGAN 500'), findsOneWidget);
    expect(text(tester, 'N° de Lot'), '');
    expect(find.text('DataMatrix lu'), findsNothing);
  });

  Future<void> selectDoliprane(WidgetTester tester) async {
    await tester.enterText(search, 'doliprane');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('DOLIPRANE 1000MG CP'), findsOneWidget);
  }

  bool hasFocus(WidgetTester tester, String label) => tester
      .widget<EditableText>(find.descendant(of: field(label), matching: find.byType(EditableText)))
      .focusNode
      .hasFocus;

  const unknownGtin = '03400930000007'; // GTIN valide absent du stock

  testWidgets('icône caméra de la recherche = douchette Sunmi (DataMatrix)', (tester) async {
    await pumpScreen(tester, cameraCode: '01${gtin}17261002${gs}107445');
    await tester.tap(find.byIcon(Icons.photo_camera));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('DOLIPRANE 1000MG CP'), findsOneWidget);
    expect(text(tester, 'N° de Lot'), '7445');
    expect(text(tester, 'Date de Péremption (JJMMYY)'), '02/10/2026');
  });

  testWidgets('icône caméra de la recherche : code-barres EAN simple affiche le produit', (tester) async {
    await pumpScreen(tester, cameraCode: '3400935955838');
    await tester.tap(find.byIcon(Icons.photo_camera));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('DOLIPRANE 1000MG CP'), findsOneWidget);
    expect(text(tester, 'N° de Lot'), '');
    expect(find.text('DataMatrix lu'), findsNothing);
  });

  testWidgets('produit affiché + scan Sunmi (code inconnu) : lot et date seulement, focus quantité', (tester) async {
    await pumpScreen(tester);
    await selectDoliprane(tester);
    await tester.enterText(search, '01${unknownGtin}17271031${gs}10GT22254');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(find.text('DOLIPRANE 1000MG CP'), findsOneWidget); // même produit
    expect(text(tester, 'N° de Lot'), 'GT22254');
    expect(text(tester, 'Date de Péremption (JJMMYY)'), '31/10/2027');
    expect(find.textContaining('introuvable'), findsNothing);
    expect(find.textContaining('Attention'), findsNothing);
    expect(hasFocus(tester, 'Quantité'), isTrue);
  });

  testWidgets('bouton Scanner lot / date du formulaire', (tester) async {
    await pumpScreen(tester, cameraCode: '01${unknownGtin}17271031${gs}10GT22254');
    await selectDoliprane(tester);
    await tester.tap(find.text('Scanner lot / date'));
    await tester.pumpAndSettle();
    expect(find.text('DOLIPRANE 1000MG CP'), findsOneWidget);
    expect(text(tester, 'N° de Lot'), 'GT22254');
    expect(text(tester, 'Date de Péremption (JJMMYY)'), '31/10/2027');
    expect(hasFocus(tester, 'Quantité'), isTrue);

    await tester.enterText(field('Quantité'), '4');
    await tester.ensureVisible(find.text('Valider'));
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(api.addLotCalls.single,
        {'produitId': '15712354735457071135', 'datePeremption': '2027-10-31', 'numLot': 'GT22254', 'quantity': 4});
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('bouton Scanner lot / date avec un code-barres simple : message, rien ne change', (tester) async {
    await pumpScreen(tester, cameraCode: '3400935955838');
    await selectDoliprane(tester);
    await tester.tap(find.text('Scanner lot / date'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Code-barres simple'), findsOneWidget);
    expect(text(tester, 'N° de Lot'), '');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('garde-fou : le code correspond à un autre produit du stock', (tester) async {
    await pumpScreen(tester, cameraCode: '01${gtin}17271031${gs}10GT22254');
    await tester.enterText(search, 'efferalgan');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scanner lot / date'));
    await tester.pumpAndSettle();

    expect(find.text('EFFERALGAN 500'), findsOneWidget);
    expect(text(tester, 'N° de Lot'), 'GT22254');
    expect(find.textContaining('ce code correspond à « DOLIPRANE 1000MG CP »'), findsOneWidget);

    await tester.tap(find.text('Utiliser DOLIPRANE 1000MG CP'));
    await tester.pumpAndSettle();
    expect(find.text('DOLIPRANE 1000MG CP'), findsOneWidget);
    expect(text(tester, 'N° de Lot'), 'GT22254');
    expect(find.textContaining('Attention'), findsNothing);
  });

  testWidgets('Photo étiquette (formulaire) : confirmation obligatoire puis remplissage', (tester) async {
    await pumpScreen(tester, labelLines: ['DOLIPRANE 1000 mg', 'LOT: A1234B', 'EXP: 10/2027', '3 400935 955838']);
    await selectDoliprane(tester);
    await tester.tap(find.text('Photo étiquette'));
    await tester.pumpAndSettle();

    expect(find.text('Vérifiez avec la boîte'), findsOneWidget);
    expect(text(tester, 'N° de Lot'), ''); // rien rempli avant validation
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(TextField, 'N° de Lot')), 'a1234c');
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Valider')));
    await tester.pumpAndSettle();

    expect(find.text('DOLIPRANE 1000MG CP'), findsOneWidget);
    expect(text(tester, 'N° de Lot'), 'A1234C');
    expect(text(tester, 'Date de Péremption (JJMMYY)'), '31/10/2027');
    expect(find.text('Étiquette lue (valeurs confirmées)'), findsOneWidget);
    expect(find.textContaining('Attention'), findsNothing);
    expect(hasFocus(tester, 'Quantité'), isTrue);
    expect(api.addLotCalls, isEmpty);
  });

  testWidgets('Photo étiquette annulée : rien ne change', (tester) async {
    await pumpScreen(tester, labelLines: ['LOT: A1', 'EXP: 10/2027']);
    await selectDoliprane(tester);
    await tester.tap(find.text('Photo étiquette'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Étiquette lue'), findsNothing);
    expect(text(tester, 'N° de Lot'), '');
  });
}
