// Briques communes des ventes : quantité, modification de ligne, espèces, modes de paiement,
// liste de choix produit, recherche/scan (3 caractères, panne ≠ introuvable), message serveur.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/common/product_list_modal.dart';
import 'package:prestige_vente_app/ventes/common/quantity_dialog.dart';
import 'package:prestige_vente_app/ventes/common/vente_dialogs.dart';
import 'package:prestige_vente_app/ventes/common/vente_messages.dart';
import 'package:prestige_vente_app/ventes/common/vente_product_search.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProductSearchResult _p(String id, String name, {int stock = 5}) =>
    ProductSearchResult(lgFAMILLEID: id, strNAME: name, intCIP: '34009$id', intPRICE: 1000, intNUMBERAVAILABLE: stock, strLIBELLEE: '', intPAF: 0);

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(720, 1400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

/// Ouvre [open] depuis un bouton et mémorise le résultat.
Future<List<Object?>> _host(WidgetTester tester, Future<Object?> Function(BuildContext) open) async {
  final results = <Object?>[];
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (ctx) => Center(child: ElevatedButton(onPressed: () async => results.add(await open(ctx)), child: const Text('go'))),
      ),
    ),
  ));
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  return results;
}

Finder _dialogField([int i = 0]) => find.descendant(of: find.byType(AlertDialog), matching: find.byType(EditableText)).at(i);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('message du serveur sans balises HTML', () {
    expect(venteMessage('<b>Plafond</b> atteint<br/>pour ce client'), 'Plafond atteint pour ce client');
    expect(venteMessage('  '), 'Opération impossible.');
  });

  testWidgets('quantité : 0 refusé, > 50 confirmé', (tester) async {
    _phone(tester);
    final r = await _host(tester, (ctx) => showDialog<int>(context: ctx, builder: (_) => QuantityDialog(product: _p('1', 'DOLIPRANE'))));
    await tester.enterText(_dialogField(), '0');
    await tester.tap(find.text('Ajouter'));
    await tester.pumpAndSettle();
    expect(find.text('Entre 1 et 9999'), findsOneWidget);
    await tester.enterText(_dialogField(), '60');
    await tester.tap(find.text('Ajouter'));
    await tester.pumpAndSettle();
    expect(find.text('Ajouter 60 unités ?'), findsOneWidget);
    await tester.tap(find.text('OUI, CONFIRMER'));
    await tester.pumpAndSettle();
    expect(r, [60]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('modification de ligne : prix borné, 0 F confirmé', (tester) async {
    _phone(tester);
    final r = await _host(tester, (ctx) => showEditLineDialog(ctx, name: 'DOLIPRANE', qty: 2, price: 1500));
    await tester.enterText(_dialogField(1), '0');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(find.text('Prix à 0 F'), findsOneWidget);
    await tester.tap(find.text('Oui, 0 F'));
    await tester.pumpAndSettle();
    expect(r.single, (qty: 2, price: 0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('espèces : montant insuffisant bloqué, aberrant refusé, monnaie calculée', (tester) async {
    _phone(tester);
    final r = await _host(tester, (ctx) => showCashDialog(ctx, montantNet: 4500));
    Finder validate() => find.widgetWithText(ElevatedButton, 'Valider');
    await tester.enterText(_dialogField(), '4000');
    await tester.pump();
    expect(tester.widget<ElevatedButton>(validate()).onPressed, isNull);
    await tester.enterText(_dialogField(), '3400930000001');
    await tester.pump();
    expect(find.textContaining('aberrant'), findsOneWidget);
    await tester.tap(find.text(Constants.formatNumber(5000)));
    await tester.pump();
    expect(find.text('Monnaie à rendre : ${Constants.formatNumber(500)} F'), findsOneWidget);
    await tester.tap(validate());
    await tester.pumpAndSettle();
    expect(r.single, (verse: 5000, monnaie: 500));
    expect(tester.takeException(), isNull);
  });

  testWidgets('modes de paiement : aucun activé → message clair', (tester) async {
    _phone(tester);
    await _host(tester, (ctx) => showPaymentMethodPicker(ctx, const []));
    expect(find.textContaining('Aucun mode de règlement n\'est activé'), findsOneWidget);
    expect(find.text('Fermer'), findsOneWidget);
  });

  testWidgets('liste de choix produit : filtre et sélection', (tester) async {
    _phone(tester);
    final r = await _host(tester, (ctx) => showProductListModal(ctx, [_p('1', 'DOLIPRANE 500'), _p('2', 'EFFERALGAN')]));
    expect(find.text('Résultats (2)'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'effer');
    await tester.pumpAndSettle();
    expect(find.text('Résultats (1)'), findsOneWidget);
    await tester.tap(find.text('EFFERALGAN'));
    await tester.pumpAndSettle();
    expect((r.single as ProductSearchResult).lgFAMILLEID, '2');
    expect(tester.takeException(), isNull);
  });

  group('recherche / scan', () {
    late List<String> queries;
    late List<(String, int)> added;
    late VenteResult<List<ProductSearchResult>> Function(String) answer;

    Future<void> pump(WidgetTester tester) async {
      queries = [];
      added = [];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: VenteProductSearch(
            search: (q) async {
              queries.add(q);
              return answer(q);
            },
            addProduct: (p, qty) async {
              added.add((p.lgFAMILLEID, qty));
              return true;
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('moins de 3 caractères : indiqué, pas de recherche', (tester) async {
      _phone(tester);
      answer = (_) => const VenteOk([]);
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'do');
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Saisissez au moins 3 caractères'), findsOneWidget);
      expect(queries, isEmpty);
      await tester.enterText(find.byType(TextField), 'dol');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(queries, ['dol']);
      expect(find.textContaining('Aucun produit trouvé'), findsOneWidget);
    });

    testWidgets('panne : « Recherche impossible », jamais « introuvable » ; scan rapide mémorisé', (tester) async {
      _phone(tester);
      answer = (_) => const VenteFailed('Serveur injoignable');
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('vente-scan-rapide')));
      await tester.pumpAndSettle();
      expect((await SharedPreferences.getInstance()).getBool(QuickScanPrefs.key), isTrue);
      await tester.enterText(find.byType(TextField), '3400912345678');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.textContaining('Recherche impossible'), findsOneWidget);
      expect(find.textContaining('introuvable'), findsNothing);
      expect(added, isEmpty);
    });

    testWidgets('scan : stock vide → « forcer ? », Non = rien ajouté', (tester) async {
      _phone(tester);
      SharedPreferences.setMockInitialValues({QuickScanPrefs.key: true});
      answer = (_) => VenteOk([_p('9', 'RUPTURE', stock: 0)]);
      await pump(tester);
      await tester.enterText(find.byType(TextField), '340099');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('Stock insuffisant'), findsOneWidget);
      await tester.tap(find.text('Non'));
      await tester.pumpAndSettle();
      expect(added, isEmpty);
      await tester.enterText(find.byType(TextField), '340099');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forcer'));
      await tester.pumpAndSettle();
      expect(added, [('9', 1)]);
      expect(find.text('RUPTURE ajouté (+1)'), findsOneWidget);
    });
  });
}
