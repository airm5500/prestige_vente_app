import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/reception/reception_gateway.dart';
import 'package:prestige_vente_app/reception/reception_logic.dart';
import 'package:prestige_vente_app/reception/reception_models.dart';
import 'package:prestige_vente_app/screens/reception_bl/reception_bl_screen.dart';
import 'package:prestige_vente_app/screens/reception_bl/reception_home_screen.dart';
import 'package:prestige_vente_app/services/saisie_peremption.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const gs = '\u001d';
const dolipraneGtin = '03400935955838'; // EAN 3400935955838, CIP7 3595583
const otherGtin = '03400930000007'; // EAN 3400930000007, CIP7 3000000
String dm(String gtin, String yymmdd, String lot) => '01$gtin' '17$yymmdd' '10$lot';

/// Serveur Prestige simulé, avec ses règles : somme des lots <= quantité commandée ; entrée en stock refusée
/// si une ligne commencée est incomplète.
class FakePrestige implements ReceptionGateway {
  /// D18 : séries déjà enregistrées (« gtin/serie ») et séries reçues avec chaque lot accepté.
  final seriesConsommees = <String>{};
  final seriesRecues = <({String? serie, String? gtin})>[];
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
  Future<ReceptionResult> addLot(
      {required String detailId, required int quantity, required int freeQty, required String numLot, DateTime? expiry, String? serie, String? gtin}) async {
    final r = rows[detailId]!;
    // D18 (4.3.1) : serveur à jour, boîte déjà scannée refusée, rien d'ajouté.
    if (serie != null && !seriesConsommees.add('$gtin/$serie')) {
      return const ReceptionResult(false, 'Boîte déjà scannée', {'success': false, 'code': 'SERIE_DEJA_CONSOMMEE', 'msg': 'Boîte déjà scannée'});
    }
    seriesRecues.add((serie: serie, gtin: gtin));
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

/// 4.11.0 (demande 59) : serveur qui sait entrer seulement ce qui a été reçu.
class FakePrestigeRecu extends FakePrestige implements ClotureRecuGateway {
  bool disponible = true;
  int recuCalls = 0;
  @override
  Future<bool> clotureRecuDisponible() async => disponible;
  @override
  Future<ReceptionResult> validateRecu(String blId) async {
    recuCalls++;
    return ReceptionResult(true, 'BL entré avec écart', {
      'success': true,
      'ecarts': [
        for (final r in rows.values)
          if (r.line.entered < r.line.ordered)
            {'cip': r.line.code, 'nom': r.line.name, 'commande': r.line.ordered, 'recu': r.line.entered, 'manquant': r.line.ordered - r.line.entered},
      ],
    });
  }
}

void main() {
  final now = DateTime(2026, 10, 10, 9);

  group('Règles', () {
    test('dates saisies à la main', () {
      expect(parseExpiryInput('31/10/2027'), DateTime(2027, 10, 31));
      expect(parseExpiryInput('311027'), DateTime(2027, 10, 31));
      // 4.11.0 (plan du 08/11) : règle de « Mise à jour péremption » : jour absent → 1er du mois, barres facultatives.
      expect(parseExpiryInput('08/2028'), DateTime(2028, 8, 1));
      expect(parseExpiryInput('02/28'), DateTime(2028, 2, 1));
      expect(parseExpiryInput('0128'), DateTime(2028, 1, 1));
      expect(parseExpiryInput('010128'), DateTime(2028, 1, 1));
      expect(parseExpiryInput('01012028'), DateTime(2028, 1, 1));
      expect(parseExpiryInput('1/1/28'), DateTime(2028, 1, 1));
      expect(parseExpiryInput('310228'), isNull);
      expect(parseExpiryInput('1328'), isNull);
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
      ListPresentation style = ListPresentation.dashboard,
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
          presentation: style,
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

    for (final style in [ListPresentation.compact, ListPresentation.guided]) {
      testWidgets('présentation ${style.label} : DataMatrix -> confirmer -> bilan', (tester) async {
        await pump(tester, style: style, settings: const ReceptionSettings(terminalValidation: true));
        expect(find.text('0/2 lignes · 4/34 boîtes'), findsOneWidget);
        await scan(tester, dm(dolipraneGtin, '271031', 'A123$gs'));
        expect(field(tester, 'N° de lot'), 'A123');
        await tester.tap(find.text('Confirmer 24'));
        await tester.pumpAndSettle();
        expect(server.addLotCalls.single['qty'], 24);
        expect(find.text('1/2 lignes · 28/34 boîtes'), findsOneWidget);
        await tester.tap(find.text('Terminer et vérifier'));
        await tester.pumpAndSettle();
        expect(find.text('Bilan BL BL-778'), findsOneWidget);
        expect(find.textContaining('Prestige refusera'), findsOneWidget);
      });
    }

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

    // D18 (4.3.1, décision du pharmacien) : une boîte déjà scannée est refusée.
    testWidgets('D18 : série + GTIN envoyés ; même boîte rescannée → « Boîte déjà scannée », rien d\'ajouté, boîte suivante acceptée', (tester) async {
      await pump(tester);
      await scan(tester, '01${dolipraneGtin}21SN0001$gs' '17271031' '10A123$gs');
      expect(field(tester, 'N° de lot'), 'A123');
      await tester.enterText(find.widgetWithText(TextField, 'Quantité (boîtes)'), '1');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmer 1'));
      await tester.pumpAndSettle();
      expect(server.seriesRecues.single, (serie: 'SN0001', gtin: dolipraneGtin));
      expect(server.addLotCalls, hasLength(1));
      // Même boîte rescannée : refus clair, aucune quantité ajoutée.
      await scan(tester, '01${dolipraneGtin}21SN0001$gs' '17271031' '10A123$gs');
      await tester.enterText(find.widgetWithText(TextField, 'Quantité (boîtes)'), '1');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmer 1'));
      await tester.pumpAndSettle();
      // Même lot déjà saisi sur la ligne : confirmation habituelle « déjà saisi ».
      if (find.text('Confirmer').evaluate().isNotEmpty) {
        await tester.tap(find.text('Confirmer'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Boîte déjà scannée'), findsOneWidget);
      expect(find.textContaining('Aucune quantité ajoutée'), findsOneWidget);
      expect(find.textContaining('SN0001'), findsNothing, reason: 'jamais le numéro de série à l\'écran');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(server.addLotCalls, hasLength(1), reason: 'rien d\'ajouté');
      expect(find.text('1/2 lignes · 5/34 boîtes').evaluate().isNotEmpty || find.textContaining('5/34').evaluate().isNotEmpty, isTrue);
      expect(field(tester, 'N° de lot'), '', reason: 'ligne remise à zéro : scan suivant');
      // Boîte suivante (autre série) : acceptée.
      await scan(tester, '01${dolipraneGtin}21SN0002$gs' '17271031' '10A123$gs');
      await tester.enterText(find.widgetWithText(TextField, 'Quantité (boîtes)'), '1');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmer 1'));
      await tester.pumpAndSettle();
      if (find.text('Confirmer').evaluate().isNotEmpty) {
        await tester.tap(find.text('Confirmer'));
        await tester.pumpAndSettle();
      }
      expect(server.addLotCalls, hasLength(2));
      expect(server.seriesRecues.last.serie, 'SN0002');
      expect(tester.takeException(), isNull);
    });

    testWidgets('D18 ergonomie : refus « Boîte déjà scannée » lisible sur 360×640 dp, texte ×1,3, bouton OK ≥ 48 dp', (tester) async {
      server.seriesConsommees.add('$dolipraneGtin/SN0009');
      await pump(tester);
      tester.view.physicalSize = const Size(720, 1280);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      await scan(tester, '01${dolipraneGtin}21SN0009$gs' '17271031' '10A123$gs');
      await tester.enterText(find.widgetWithText(TextField, 'Quantité (boîtes)'), '1');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Confirmer 1'));
      await tester.tap(find.text('Confirmer 1'));
      await tester.pumpAndSettle();
      expect(find.text('Boîte déjà scannée'), findsOneWidget);
      expect(tester.getSize(find.widgetWithText(ElevatedButton, 'OK')).height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull, reason: 'aucun débordement');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(server.addLotCalls, isEmpty);
    });

    testWidgets('D18 : DataMatrix sans numéro de série, ou saisie à la main → aucune série envoyée', (tester) async {
      await pump(tester);
      await scan(tester, dm(dolipraneGtin, '271031', 'A123$gs'));
      await tester.tap(find.text('Confirmer 24'));
      await tester.pumpAndSettle();
      expect(server.seriesRecues.single, (serie: null, gtin: null));
      await scan(tester, '3000000');
      await tester.enterText(find.widgetWithText(TextField, 'N° de lot'), 'B7');
      await tester.enterText(find.widgetWithText(TextField, 'Péremption (JJ/MM/AAAA ou MM/AAAA)'), '31/01/2028');
      await tester.enterText(find.widgetWithText(TextField, 'Quantité (boîtes)'), '1');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmer 1'));
      await tester.pumpAndSettle();
      expect(server.seriesRecues.last, (serie: null, gtin: null));
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
      // 4.11.0 : chemin de « Mise à jour péremption » : confirmation obligatoire des valeurs lues.
      expect(find.text('Vérifiez avec la boîte'), findsOneWidget);
      expect(field(tester, 'N° de lot'), '', reason: 'rien de repris avant la confirmation');
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
      expect(field(tester, 'N° de lot'), 'K77B');
      expect(field(tester, 'Péremption (JJ/MM/AAAA ou MM/AAAA)'), '31/03/2028');
      expect(find.textContaining('vérifiée avec la boîte'), findsOneWidget);
    });

    // 4.11.0 (plan du 08/11) : enchaînement des champs, péremption sans barres, quantité pré-sélectionnée.
    testWidgets('4.11.0 : lot → Entrée → péremption « 0128 » → Entrée → quantité pré-sélectionnée → Entrée enregistre', (tester) async {
      await pump(tester);
      await scan(tester, '3595583');
      expect(find.text('DOLIPRANE 1000MG CP'), findsOneWidget);
      final lotField = find.widgetWithText(TextField, 'N° de lot');
      final dateField = find.widgetWithText(TextField, 'Péremption (JJ/MM/AAAA ou MM/AAAA)');
      final qtyField = find.widgetWithText(TextField, 'Quantité (boîtes)');
      FocusNode focus(Finder f) => tester.widget<TextField>(f).focusNode!;
      expect(find.text(aideSaisiePeremption), findsOneWidget, reason: 'aide sous le champ');
      expect(tester.widget<TextField>(lotField).textInputAction, TextInputAction.next);
      expect(tester.widget<TextField>(dateField).textInputAction, TextInputAction.next);
      await tester.tap(lotField);
      await tester.enterText(lotField, 'L77');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expect(focus(dateField).hasFocus, isTrue, reason: 'lot validé → péremption');
      await tester.enterText(dateField, '0128');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expect(field(tester, 'Péremption (JJ/MM/AAAA ou MM/AAAA)'), '01/01/2028', reason: '0128 = 01/01/2028');
      expect(focus(qtyField).hasFocus, isTrue, reason: 'péremption validée → quantité');
      final q = tester.widget<TextField>(qtyField).controller!;
      expect(q.text, '24');
      expect(q.selection, const TextSelection(baseOffset: 0, extentOffset: 2), reason: 'quantité attendue pré-sélectionnée');
      // La frappe remplace la sélection.
      tester.testTextInput.updateEditingValue(const TextEditingValue(text: '20', selection: TextSelection.collapsed(offset: 2)));
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(server.addLotCalls.single, {'detail': 'd1', 'qty': 20, 'ug': 0, 'lot': 'L77', 'exp': DateTime(2028, 1, 1)});
    });

    testWidgets('4.11.0 : péremption « 010128 » acceptée ; date illisible : message sous le champ, curseur gardé', (tester) async {
      await pump(tester);
      await scan(tester, '3595583');
      final dateField = find.widgetWithText(TextField, 'Péremption (JJ/MM/AAAA ou MM/AAAA)');
      await tester.enterText(find.widgetWithText(TextField, 'N° de lot'), 'L1');
      await tester.tap(dateField);
      await tester.enterText(dateField, '3102');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expect(find.textContaining('Date illisible'), findsOneWidget);
      expect(tester.widget<TextField>(dateField).focusNode!.hasFocus, isTrue);
      await tester.enterText(dateField, '010128');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expect(find.textContaining('Date illisible'), findsNothing);
      expect(field(tester, 'Péremption (JJ/MM/AAAA ou MM/AAAA)'), '01/01/2028');
    });

    testWidgets('4.11.0 : DataMatrix lu sur la PHOTO → lot et date sûrs, sans confirmation ; produit vérifié', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: ReceptionBlScreen(
          bl: const ReceptionBl(id: 'bl1', ref: 'BL-778', grossiste: 'LABOREX'),
          gateway: server,
          settings: const ReceptionSettings(),
          clock: () => now,
          etiquetteCamera: (_) async => (lignes: const ['TEXTE ILLISIBLE'], codes: [dm(dolipraneGtin, '290630', 'PH7$gs')]),
        ),
      ));
      await tester.pumpAndSettle();
      await scan(tester, '3595583');
      await tester.tap(find.text('Photo LOT/EXP'));
      await tester.pumpAndSettle();
      expect(find.text('Vérifiez avec la boîte'), findsNothing, reason: 'DataMatrix : valeurs sûres');
      expect(field(tester, 'N° de lot'), 'PH7');
      expect(field(tester, 'Péremption (JJ/MM/AAAA ou MM/AAAA)'), '30/06/2029');
    });

    testWidgets('4.11.0 : DataMatrix par la caméra : lecture « lot / date » de « Mise à jour péremption » demandée', (tester) async {
      var demandeDm = false;
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: ReceptionBlScreen(
          bl: const ReceptionBl(id: 'bl1', ref: 'BL-778', grossiste: 'LABOREX'),
          gateway: server,
          settings: const ReceptionSettings(),
          clock: () => now,
          codeCamera: (BuildContext _, {bool dataMatrixOnly = false}) async {
            demandeDm = dataMatrixOnly;
            return dm(dolipraneGtin, '281130', 'CAM1$gs');
          },
        ),
      ));
      await tester.pumpAndSettle();
      await scan(tester, '3595583');
      await tester.tap(find.text('DataMatrix'));
      await tester.pumpAndSettle();
      expect(demandeDm, isTrue);
      expect(field(tester, 'N° de lot'), 'CAM1');
      expect(field(tester, 'Quantité (boîtes)'), '24');
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

    // 4.11.0 (plan du 08/11, demande 59) : BL incomplet.
    for (final dispo in [true, false]) {
      testWidgets('4.11.0 : BL incomplet, serveur ${dispo ? 'avec' : 'SANS'} la clôture « au reçu »', (tester) async {
        final recu = FakePrestigeRecu()
          ..disponible = dispo
          ..add('d1', 'DOLIPRANE 1000MG CP', '3595583', '3400935955838', 24)
          ..add('d2', 'AUTRE PRODUIT', '3000000', '3400930000007', 10, entered: 4, lots: ['Z9']);
        server = recu;
        await pump(tester, settings: const ReceptionSettings(terminalValidation: true));
        await tester.tap(find.text('Terminer et vérifier'));
        await tester.pumpAndSettle();
        // Rapport des écarts toujours visible : ce qui a été vu, ce qui manque.
        expect(find.byKey(const Key('bl_ecarts')), findsOneWidget);
        expect(find.text('AUTRE PRODUIT — reçu 4/10, manquant 6'), findsOneWidget);
        expect(find.text('DOLIPRANE 1000MG CP — reçu 0/24, manquant 24'), findsOneWidget);
        if (!dispo) {
          expect(find.byKey(const Key('bl_entrer_recu')), findsNothing, reason: 'serveur actuel : jamais d\'entrée d\'un BL incomplet');
          expect(find.textContaining('n\'entre pas encore un BL incomplet'), findsOneWidget);
          expect(recu.recuCalls, 0);
          return;
        }
        final bouton = find.byKey(const Key('bl_entrer_recu'));
        await tester.ensureVisible(bouton);
        await tester.tap(bouton);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('bl_cloture_recu_confirmation')), findsOneWidget);
        expect(find.textContaining('Seules les boîtes saisies entrent en stock. 2 ligne(s) en écart, 30 boîte(s) manquante(s)'), findsOneWidget);
        await tester.tap(find.text('Entrer le reçu'));
        await tester.pumpAndSettle();
        expect(recu.recuCalls, 1);
        expect(recu.validateCalls, 0, reason: 'jamais la clôture classique (quantité commandée)');
        expect(find.byKey(const Key('bl_cloture_recu_resultat')), findsOneWidget);
        expect(find.text('Écart au rapport :'), findsOneWidget);
        expect(find.text('AUTRE PRODUIT — reçu 4/10, manquant 6'), findsWidgets);
      });
    }

    testWidgets('sans le paramètre du terminal : seulement « Laisser pour validation sur Prestige »', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Terminer et vérifier'));
      await tester.pumpAndSettle();
      expect(find.text('Valider l\'entrée en stock'), findsNothing);
      expect(find.text('Laisser pour validation sur Prestige'), findsOneWidget);
    });
  });

  Future<FakePrestige> pumpHome(WidgetTester tester, ListPresentation style) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final server = FakePrestige()..add('d1', 'DOLIPRANE 1000MG CP', '3595583', '3400935955838', 24);
    await tester.pumpWidget(MaterialApp(
      home: ReceptionHomeScreen(gateway: server, settings: const ReceptionSettings(), clock: () => now, presentation: style),
    ));
    await tester.pumpAndSettle();
    return server;
  }

  testWidgets('A (défaut) : commandes d\'abord, « Créer le BL » sur page dédiée, doublon refusé sur place, puis onglet BL', (tester) async {
    final server = await pumpHome(tester, ListPresentation.dashboard);
    // Chiffres clés et onglet « Commandes » affiché en premier.
    expect(find.text('lignes à saisir'), findsOneWidget);
    expect(find.text('COPHARMED'), findsWidgets);
    expect(find.text('BL BL-778'), findsNothing);

    await tester.tap(find.text('Créer le BL'));
    await tester.pumpAndSettle();
    expect(find.text('Nouveau BL'), findsOneWidget);
    expect(find.text('10/10/2026'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'N° du BL *'), 'BL-778');
    await tester.tap(find.text('Créer le BL'));
    await tester.pumpAndSettle();
    expect(find.textContaining('déjà été utilisé'), findsOneWidget); // message sur la page, saisie gardée
    expect(find.text('Nouveau BL'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'N° du BL *'), 'BL-901');
    await tester.enterText(find.widgetWithText(TextFormField, 'TVA'), '810');
    await tester.tap(find.text('Créer le BL'));
    await tester.pumpAndSettle();
    expect(server.created.single, 'o1|BL-901|2026-10-10|45000|810');
    // Retour à la liste, onglet « BL à entrer », nouveau BL mis en évidence avec son avancement.
    expect(find.text('BL BL-901'), findsOneWidget);
    expect(find.text('Nouveau'), findsOneWidget);
    expect(find.text('0 / 1 lignes saisies'), findsWidgets);
    expect(find.textContaining('touchez-le pour commencer la saisie'), findsOneWidget);
  });

  testWidgets('A : BL commencé -> « Continuer » et « Bilan »', (tester) async {
    final server = await pumpHome(tester, ListPresentation.dashboard);
    await server.addLot(detailId: 'd1', quantity: 10, freeQty: 0, numLot: 'L1', expiry: DateTime(2028));
    await tester.tap(find.byTooltip('Actualiser'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BL à entrer · 1'));
    await tester.pumpAndSettle();
    expect(find.text('En saisie'), findsOneWidget);
    expect(find.text('10 / 24 boîtes'), findsOneWidget);
    await tester.tap(find.text('Bilan'));
    await tester.pumpAndSettle();
    expect(find.text('Bilan BL BL-778'), findsOneWidget);
  });

  testWidgets('4.11.0 : commandes à réceptionner : nombre de LIGNES (int_LINE), pas de produits', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final server = FakePrestige()
      ..orderList = [const ReceptionOrder(id: 'o1', ref: 'CMD-12', grossiste: 'COPHARMED', products: 48, linesCount: 3, amount: 45000, statut: 'passed')];
    for (final style in ListPresentation.values) {
      await tester.pumpWidget(MaterialApp(
        key: ValueKey(style),
        home: ReceptionHomeScreen(gateway: server, settings: const ReceptionSettings(), clock: () => now, presentation: style),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('48'), findsNothing, reason: '${style.label} : la quantité n\'est plus affichée comme des produits');
      expect(find.textContaining('produit'), findsNothing, reason: style.label);
      expect(find.textContaining('3'), findsWidgets);
      expect(find.textContaining('ligne'), findsWidgets);
    }
  });

  testWidgets('B : liste groupée par grossiste, total, « Créer BL »', (tester) async {
    await pumpHome(tester, ListPresentation.compact);
    expect(find.text('COPHARMED'), findsWidgets); // en-tête de groupe et filtre
    expect(find.textContaining('Total'), findsOneWidget);
    await tester.tap(find.text('Créer BL'));
    await tester.pumpAndSettle();
    expect(find.text('Nouveau BL'), findsOneWidget);
  });

  testWidgets('C : parcours en étapes, « Recevoir cette livraison », étape Saisie BL', (tester) async {
    await pumpHome(tester, ListPresentation.guided);
    expect(find.text('ÉTAPE 1'), findsOneWidget);
    expect(find.text('Recevoir cette livraison'), findsOneWidget);
    await tester.tap(find.text('Saisie BL'));
    await tester.pumpAndSettle();
    expect(find.text('BL BL-778'), findsOneWidget);
    expect(find.text('Commencer le scan'), findsOneWidget);
  });

  testWidgets('changement de présentation depuis la barre du haut', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    // Compte administrateur : le bouton « Présentation » lui est réservé.
    await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>(
      create: (_) => _Auth(admin: true),
      child: MaterialApp(
        home: ReceptionHomeScreen(gateway: FakePrestige(), settings: const ReceptionSettings(), clock: () => now),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('lignes à saisir'), findsOneWidget); // A par défaut
    await tester.tap(find.byTooltip('Présentation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('C · Parcours guidé'));
    await tester.pumpAndSettle();
    expect(find.text('ÉTAPE 1'), findsOneWidget);
    expect(await PresentationPrefs.load(), ListPresentation.guided);
  });

  testWidgets('non-admin : bouton « Présentation » absent, présentation choisie par l\'admin respectée', (tester) async {
    SharedPreferences.setMockInitialValues({'presentation_listes_v1': 'guided'});
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>(
      create: (_) => _Auth(admin: false),
      child: MaterialApp(
        home: ReceptionHomeScreen(gateway: FakePrestige(), settings: const ReceptionSettings(), clock: () => now),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Présentation'), findsNothing);
    expect(find.byType(PresentationMenuButton), findsOneWidget, reason: 'point unique : le widget commun se masque');
    expect(find.text('ÉTAPE 1'), findsOneWidget); // C, choisie par l'administrateur
    expect(await PresentationPrefs.load(), ListPresentation.guided);
  });
}

class _Auth extends AuthProvider {
  _Auth({required this.admin}) : super(ApiService(baseUrl: 'http://localhost'));
  final bool admin;
  @override
  bool get isAdmin => admin;
}
