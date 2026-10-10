import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/reception/reception_gateway.dart';
import 'package:prestige_vente_app/reception/reception_logic.dart';
import 'package:prestige_vente_app/reception/reception_models.dart';
import 'package:prestige_vente_app/screens/reception_bl/reception_bl_screen.dart';
import 'package:prestige_vente_app/screens/reception_bl/reception_home_screen.dart';

const gs = '\u001d';
const dolipraneGtin = '03400935955838'; // EAN 3400935955838, CIP7 3595583
const otherGtin = '03400930000007'; // EAN 3400930000007, CIP7 3000000
String dm(String gtin, String yymmdd, String lot) => '01$gtin' '17$yymmdd' '10$lot';

/// Serveur Prestige simulé, avec ses règles : somme des lots <= quantité commandée ; entrée en stock refusée
/// si une ligne commencée est incomplète.
class FakePrestige implements ReceptionGateway {
  final Map<String, ({ReceptionLine line, String ean})> rows = {};
  final List<Map<String, Object?>> addLotCalls = [];
  final List<String> created = [];
  int validateCalls = 0;
  bool authorized = true;
  List<ReceptionBl> blList = [const ReceptionBl(id: 'bl1', ref: 'BL-778', grossiste: 'LABOREX')];
  List<ReceptionOrder> orderList = [const ReceptionOrder(id: 'o1', ref: 'CMD-12', grossiste: 'COPHARMED', products: 3, amount: 45000, statut: 'passed')];

  void add(String id, String name, String cip, String ean, int ordered, {int entered = 0, List<String> lots = const []}) {
    rows[id] = (
      line: ReceptionLine(detailId: id, produitId: 'p$id', name: name, code: cip, ordered: ordered, entered: entered, lots: lots, blRef: 'BL-778'),
      ean: ean,
    );
  }

  @override
  Future<List<ReceptionBl>> bls({String query = ''}) async => blList;
  @override
  Future<List<ReceptionOrder>> orders() async => orderList;

  @override
  Future<ReceptionResult> createBl({required String orderId, required String ref, required DateTime date, required int amountHt, required int tva}) async {
    if (ref == 'BL-778') return const ReceptionResult(false, 'Cette référence a déjà été utilisé pour ce grossiste');
    created.add('$orderId|$ref|${date.toIso8601String().substring(0, 10)}|$amountHt|$tva');
    blList = [...blList, ReceptionBl(id: 'bl2', ref: ref, grossiste: 'COPHARMED')];
    return const ReceptionResult(true, 'ok', {'success': true, 'data': []});
  }

  @override
  Future<List<ReceptionLine>> lines(String blId, {String query = ''}) async {
    final q = query.toLowerCase();
    return [
      for (final r in rows.values)
        if (q.isEmpty || r.ean == query || r.line.code == query || r.line.name.toLowerCase().startsWith(q)) r.line,
    ];
  }

  @override
  Future<ReceptionResult> addLot({required String detailId, required int quantity, required int freeQty, required String numLot, DateTime? expiry}) async {
    final r = rows[detailId]!;
    if (r.line.entered + quantity > r.line.ordered) {
      return const ReceptionResult(false, 'La quantité réçue est supérieure à la quantité commantée.');
    }
    addLotCalls.add({'detail': detailId, 'qty': quantity, 'ug': freeQty, 'lot': numLot, 'exp': expiry});
    final l = r.line;
    rows[detailId] = (
      line: ReceptionLine(
        detailId: l.detailId,
        produitId: l.produitId,
        name: l.name,
        code: l.code,
        ordered: l.ordered,
        entered: l.entered + quantity + freeQty,
        freeQty: l.freeQty + freeQty,
        lots: [...l.lots, numLot],
        expiries: [...l.expiries, if (expiry != null) expiry],
        blRef: l.blRef,
      ),
      ean: r.ean,
    );
    return const ReceptionResult(true);
  }

  @override
  Future<ReceptionResult> clearLots(ReceptionLine line) async {
    final r = rows[line.detailId]!;
    add(line.detailId, line.name, line.code, r.ean, line.ordered);
    return const ReceptionResult(true, 'Lots de la ligne effacés');
  }

  @override
  Future<void> markChecked(String detailId, int quantity) async {}
  @override
  Future<bool> canValidate() async => authorized;

  @override
  Future<ReceptionResult> validate(String blId) async {
    validateCalls++;
    if (rows.values.any((r) => r.line.isPartial)) {
      return const ReceptionResult(false, 'La reception de certains produits n\'a pas ete faite.');
    }
    return const ReceptionResult(true, 'Opération effectuée avec success');
  }
}

void main() {
  final now = DateTime(2026, 10, 10, 9);

  group('Règles', () {
    test('dates saisies à la main', () {
      expect(parseExpiryInput('31/10/2027'), DateTime(2027, 10, 31));
      expect(parseExpiryInput('311027'), DateTime(2027, 10, 31));
      expect(parseExpiryInput('08/2028'), DateTime(2028, 8, 31)); // jour absent -> fin du mois
      expect(parseExpiryInput('02/28'), DateTime(2028, 2, 29));
      expect(parseExpiryInput('31/02/2027'), isNull);
      expect(parseExpiryInput('13/2027'), isNull);
    });

    test('codes cherchés pour un scan', () {
      final dmScan = scanQueries(dm(dolipraneGtin, '271031', 'A1'));
      expect(dmScan.queries, ['3400935955838', '3595583']);
      expect(dmScan.dataMatrix!.lot, 'A1');
      expect(scanQueries(' 3595583\n').queries, ['3595583']);
    });

    const line = ReceptionLine(detailId: 'd', produitId: 'p', name: 'X', ordered: 24, entered: 10, lots: ['A1']);
    List<LotIssue> check({String lot = 'B2', DateTime? exp, int qty = 14, bool required = true}) => checkLotEntry(
          line: line,
          lot: lot,
          expiry: exp,
          quantity: qty,
          freeQty: 0,
          now: now,
          shortExpiryMonths: 6,
          peremptionRequired: required,
        );

    test('bloquants : quantité, lot, date absente / dépassée / incohérente', () {
      expect(check(exp: DateTime(2028, 1, 31)), isEmpty);
      expect(check(exp: DateTime(2028, 1, 31), qty: 15).single.kind, LotIssueKind.quantityTooHigh);
      expect(check(exp: DateTime(2028, 1, 31), qty: 0).single.kind, LotIssueKind.quantityInvalid);
      expect(check(exp: DateTime(2028, 1, 31), lot: ' ').single.kind, LotIssueKind.lotMissing);
      expect(check().single.kind, LotIssueKind.expiryMissing);
      expect(check(required: false).single.blocking, isFalse);
      expect(check(exp: DateTime(2026, 10, 10)).single.kind, LotIssueKind.expired);
      expect(check(exp: DateTime(2045, 1, 1)).single.kind, LotIssueKind.expiryIncoherent);
    });

    test('à confirmer : péremption courte (jours restants), lot déjà saisi', () {
      final short = check(exp: DateTime(2026, 12, 31)).single;
      expect(short.kind, LotIssueKind.shortExpiry);
      expect(short.blocking, isFalse);
      expect(short.message, contains('82 jours'));
      final dup = check(lot: 'a1', exp: DateTime(2028, 1, 31)).single;
      expect(dup.kind, LotIssueKind.lotAlreadyEntered);
    });

    test('bilan : non saisies, incomplètes, complètes, péremptions courtes', () {
      final s = ReceptionSummary.of([
        const ReceptionLine(detailId: '1', produitId: 'a', name: 'A', ordered: 5),
        ReceptionLine(detailId: '2', produitId: 'b', name: 'B', ordered: 5, entered: 2, lots: const ['L'], expiries: [DateTime(2028)]),
        ReceptionLine(detailId: '3', produitId: 'c', name: 'C', ordered: 5, entered: 7, freeQty: 2, lots: const ['M'], expiries: [DateTime(2027, 1, 15)]),
        const ReceptionLine(detailId: '4', produitId: 'd', name: 'D', ordered: 1, entered: 1, lots: ['N']),
      ], now: now, shortExpiryMonths: 6);
      expect(s.notEntered.map((l) => l.name), ['A']);
      expect(s.partial.map((l) => l.name), ['B']);
      expect(s.complete.map((l) => l.name), ['C', 'D']);
      expect(s.shortExpiries.single.line.name, 'C');
      expect(s.missingExpiry.single.name, 'D');
      expect(s.serverWillRefuse, isTrue);
    });

    test('lecture des lignes renvoyées par Prestige', () {
      final l = ReceptionLine.fromJson({
        'lg_BON_LIVRAISON_DETAIL': 'd1',
        'lg_FAMILLE_ID': 'f1',
        'lg_FAMILLE_NAME': 'DOLIPRANE 1000MG CP',
        'lg_FAMILLE_CIP': '3595583',
        'int_QTE_CMDE': 24,
        'quantiteSaisie': 12,
        'freeQty': 0,
        'lots': 'A1 | B2',
        'datePeremption': '31/10/2027 | 30/06/2028',
        'str_REF_LIVRAISON': 'BL-778',
      });
      expect(l.lots, ['A1', 'B2']);
      expect(l.expiries, [DateTime(2027, 10, 31), DateTime(2028, 6, 30)]);
      expect(l.remaining, 12);
      expect(l.isPartial, isTrue);
      final bl = ReceptionBl.fromJson({'lg_BON_LIVRAISON_ID': 'x', 'str_REF_LIVRAISON': 'BL1', 'DISPLAYFILTER': false});
      expect(bl.peremptionOptional, isFalse);
    });
  });

  group('Écran de saisie', () {
    late FakePrestige server;
    setUp(() {
      server = FakePrestige()
        ..add('d1', 'DOLIPRANE 1000MG CP', '3595583', '3400935955838', 24)
        ..add('d2', 'AUTRE PRODUIT', '3000000', '3400930000007', 10, entered: 4, lots: ['Z9']);
    });

    Future<void> pump(WidgetTester tester, {
      ReceptionSettings settings = const ReceptionSettings(),
      List<String>? labelLines,
      String? cameraValue,
      bool peremptionOptional = true,
    }) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: ReceptionBlScreen(
          bl: ReceptionBl(id: 'bl1', ref: 'BL-778', grossiste: 'LABOREX', peremptionOptional: peremptionOptional),
          gateway: server,
          settings: settings,
          clock: () => now,
          labelCamera: (_) async => labelLines,
          codeCamera: (BuildContext _, {bool dataMatrixOnly = false}) async => cameraValue,
        ),
      ));
      await tester.pumpAndSettle();
    }

    final scanField = find.byType(TextField).first;
    Future<void> scan(WidgetTester tester, String code) async {
      await tester.enterText(scanField, code);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
    }

    String field(WidgetTester tester, String label) =>
        tester.widget<TextField>(find.widgetWithText(TextField, label)).controller!.text;

    testWidgets('DataMatrix : produit, lot et date remplis, quantité = reste, une touche pour confirmer', (tester) async {
      await pump(tester);
      expect(find.text('0/2 lignes · 4/34 boîtes'), findsOneWidget);
      await scan(tester, dm(dolipraneGtin, '271031', 'A123$gs'));
      expect(find.text('DOLIPRANE 1000MG CP'), findsOneWidget);
      expect(field(tester, 'N° de lot'), 'A123');
      expect(field(tester, 'Péremption (JJ/MM/AAAA ou MM/AAAA)'), '31/10/2027');
      expect(field(tester, 'Quantité (boîtes)'), '24');
      await tester.tap(find.text('Confirmer 24'));
      await tester.pumpAndSettle();
      expect(server.addLotCalls.single, {'detail': 'd1', 'qty': 24, 'ug': 0, 'lot': 'A123', 'exp': DateTime(2027, 10, 31)});
      expect(find.text('1/2 lignes · 28/34 boîtes'), findsOneWidget);
      expect(find.text('Scannez un produit du BL'), findsOneWidget); // retour au scan
    });

    testWidgets('produit absent du BL : bloqué', (tester) async {
      await pump(tester);
      await scan(tester, '9999999');
      expect(find.text('Produit absent de ce BL'), findsOneWidget);
      expect(server.addLotCalls, isEmpty);
    });

    testWidgets('CIP puis DataMatrix d\'un autre produit : bloqué, on reste sur la ligne', (tester) async {
      await pump(tester);
      await scan(tester, '3595583');
      expect(find.text('DOLIPRANE 1000MG CP'), findsOneWidget);
      await scan(tester, dm(otherGtin, '280131', 'Q1'));
      expect(find.text('Autre produit'), findsOneWidget);
      await tester.tap(find.textContaining('Rester sur'));
      await tester.pumpAndSettle();
      expect(field(tester, 'N° de lot'), '');
      expect(find.text('DOLIPRANE 1000MG CP'), findsOneWidget);
    });

    testWidgets('péremption courte : confirmation ; Refuser n\'enregistre rien, Accepter enregistre', (tester) async {
      await pump(tester);
      await scan(tester, dm(dolipraneGtin, '261231', 'S1'));
      await tester.tap(find.text('Confirmer 24'));
      await tester.pumpAndSettle();
      expect(find.textContaining('PÉREMPTION COURTE'), findsOneWidget);
      await tester.tap(find.text('Refuser / corriger'));
      await tester.pumpAndSettle();
      expect(server.addLotCalls, isEmpty);
      await tester.tap(find.text('Confirmer 24'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Accepter'));
      await tester.pumpAndSettle();
      expect(server.addLotCalls.single['lot'], 'S1');
    });

    testWidgets('lot périmé et quantité trop élevée : refusés', (tester) async {
      await pump(tester);
      await scan(tester, dm(dolipraneGtin, '260901', 'P1'));
      await tester.tap(find.text('Confirmer 24'));
      await tester.pumpAndSettle();
      expect(find.textContaining('LOT PÉRIMÉ'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Péremption (JJ/MM/AAAA ou MM/AAAA)'), '05/2028');
      await tester.enterText(find.widgetWithText(TextField, 'Quantité (boîtes)'), '30');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmer 30'));
      await tester.pumpAndSettle();
      expect(find.textContaining('supérieure au reste'), findsOneWidget);
      expect(server.addLotCalls, isEmpty);
    });

    testWidgets('autre lot du même produit : ligne incomplète reste ouverte ; même lot : « déjà saisi »', (tester) async {
      await pump(tester);
      await scan(tester, '3000000'); // AUTRE PRODUIT : 4/10, lot Z9
      expect(find.textContaining('Déjà saisi : lot Z9'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'N° de lot'), 'z9');
      await tester.enterText(find.widgetWithText(TextField, 'Péremption (JJ/MM/AAAA ou MM/AAAA)'), '31/01/2028');
      await tester.enterText(find.widgetWithText(TextField, 'Quantité (boîtes)'), '3');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmer 3'));
      await tester.pumpAndSettle();
      expect(find.textContaining('DÉJÀ SAISI'), findsOneWidget);
      await tester.tap(find.text('Confirmer'));
      await tester.pumpAndSettle();
      expect(server.addLotCalls.single['qty'], 3);
      // 7/10 : la ligne reste ouverte pour le reste.
      expect(field(tester, 'Quantité (boîtes)'), '3');
      expect(find.text('AUTRE PRODUIT'), findsOneWidget);
    });

    testWidgets('photo LOT/EXP : valeurs proposées, à vérifier', (tester) async {
      await pump(tester, labelLines: ['LOT: K77B', 'EXP: 03/2028']);
      await scan(tester, '3595583');
      await tester.tap(find.text('Photo LOT/EXP'));
      await tester.pumpAndSettle();
      expect(field(tester, 'N° de lot'), 'K77B');
      expect(field(tester, 'Péremption (JJ/MM/AAAA ou MM/AAAA)'), '31/03/2028');
      expect(find.textContaining('vérifiez avec la boîte'), findsOneWidget);
    });

    testWidgets('bilan : ligne incomplète -> entrée en stock impossible ; complète -> validation', (tester) async {
      await pump(tester, settings: const ReceptionSettings(terminalValidation: true));
      await tester.tap(find.text('Terminer et vérifier'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Prestige refusera'), findsOneWidget);
      final validateButton = find.ancestor(of: find.text('Valider l\'entrée en stock'), matching: find.byWidgetPredicate((w) => w is ElevatedButton));
      expect(tester.widget<ElevatedButton>(validateButton).onPressed, isNull);
      await tester.tap(find.text('Continuer la saisie'));
      await tester.pumpAndSettle();

      // On complète la ligne incomplète (6 restantes) et la première.
      await scan(tester, dm(otherGtin, '280131', 'Q1'));
      await tester.tap(find.text('Confirmer 6'));
      await tester.pumpAndSettle();
      await scan(tester, dm(dolipraneGtin, '280131', 'A1'));
      await tester.tap(find.text('Confirmer 24'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Terminer et vérifier'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Valider l\'entrée en stock'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Valider'));
      await tester.pumpAndSettle();
      expect(server.validateCalls, 1);
      expect(find.text('Entrée en stock effectuée'), findsOneWidget);
    });

    testWidgets('sans le paramètre du terminal : seulement « Laisser pour validation sur Prestige »', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Terminer et vérifier'));
      await tester.pumpAndSettle();
      expect(find.text('Valider l\'entrée en stock'), findsNothing);
      expect(find.text('Laisser pour validation sur Prestige'), findsOneWidget);
    });
  });

  testWidgets('commande -> « Créer BL » (doublon refusé, puis créé et ouvert)', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final server = FakePrestige()..add('d1', 'DOLIPRANE 1000MG CP', '3595583', '3400935955838', 24);
    await tester.pumpWidget(MaterialApp(
      home: ReceptionHomeScreen(gateway: server, settings: const ReceptionSettings(), clock: () => now),
    ));
    await tester.pumpAndSettle();
    expect(find.text('BL BL-778 — LABOREX'), findsOneWidget);
    await tester.tap(find.text('Commandes (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Créer BL'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'N° du BL *'), 'BL-778');
    await tester.tap(find.text('Créer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('déjà été utilisé'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Créer BL'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'N° du BL *'), 'BL-901');
    await tester.tap(find.text('Créer'));
    await tester.pumpAndSettle();
    expect(server.created.single, 'o1|BL-901|2026-10-10|45000|0');
    expect(find.text('BL BL-901'), findsOneWidget); // écran de saisie ouvert
  });
}
