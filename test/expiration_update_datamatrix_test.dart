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

  testWidgets('bouton Scanner DataMatrix (caméra) : même résultat que la douchette', (tester) async {
    await pumpScreen(tester, cameraCode: '01${gtin}17261002${gs}107445');
    expect(find.byIcon(Icons.photo_camera), findsNothing); // plus d'icône dans la recherche
    await tester.tap(find.text('Scanner DataMatrix'));
    await tester.pumpAndSettle();
    expect(find.text('DOLIPRANE 1000MG CP'), findsOneWidget);
    expect(text(tester, 'N° de Lot'), '7445');
    expect(text(tester, 'Date de Péremption (JJMMYY)'), '02/10/2026');
  });

  testWidgets('Photo étiquette : confirmation obligatoire puis remplissage', (tester) async {
    await pumpScreen(tester, labelLines: ['DOLIPRANE 1000 mg', 'LOT: A1234B', 'EXP: 10/2027', '3 400935 955838']);
    await tester.tap(find.text('Photo étiquette'));
    await tester.pumpAndSettle();

    expect(find.text('Vérifiez avec la boîte'), findsOneWidget);
    expect(field('N° de Lot'), findsNothing); // rien rempli avant validation
    // correction par l'opérateur dans la fenêtre
    await tester.enterText(find.widgetWithText(TextField, 'N° de Lot').last, 'a1234c');
    await tester.ensureVisible(find.text('Valider'));
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();

    expect(find.text('DOLIPRANE 1000MG CP'), findsOneWidget); // produit retrouvé par l'EAN imprimé
    expect(text(tester, 'N° de Lot'), 'A1234C');
    expect(text(tester, 'Date de Péremption (JJMMYY)'), '31/10/2027');
    expect(find.text('Étiquette lue (valeurs confirmées)'), findsOneWidget);
    expect(api.addLotCalls, isEmpty);
  });

  testWidgets('Photo étiquette annulée : rien ne change', (tester) async {
    await pumpScreen(tester, labelLines: ['LOT: A1', 'EXP: 10/2027']);
    await tester.tap(find.text('Photo étiquette'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(find.text('DataMatrix lu'), findsNothing);
    expect(find.textContaining('Étiquette lue'), findsNothing);
    expect(api.searches, isEmpty);
  });
}
