import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/reception/reception_models.dart';
import 'package:prestige_vente_app/retour/retour_gateway.dart';
import 'package:prestige_vente_app/retour/retour_models.dart';
import 'package:prestige_vente_app/screens/retour_frs/retour_bl_screen.dart';
import 'package:prestige_vente_app/screens/retour_frs/retour_home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Prestige simulé : retour lié au n° du BL, un produit par ligne (quantités cumulées, premier motif gardé),
/// quantité totale <= quantité reçue.
class FakeRetourServer implements RetourGateway {
  final lines = <ReceptionLine>[
    const ReceptionLine(detailId: 'd1', produitId: 'p1', name: 'DOLIPRANE 1000MG CP', code: '3595583', ordered: 24, entered: 24, received: 24, stock: 30, lots: ['A1']),
    const ReceptionLine(detailId: 'd2', produitId: 'p2', name: 'AMOXICILLINE 500', code: '3000000', ordered: 10, entered: 10, received: 10, stock: 3),
  ];
  final motifList = const [
    MotifRetour(id: '01', label: 'Périmé'),
    MotifRetour(id: '02', label: 'Avarié / cassé'),
    MotifRetour(id: '03', label: 'Erreur de livraison'),
  ];
  final created = <Map<String, Object?>>[];
  final added = <Map<String, Object?>>[];
  final items0 = <RetourLine>[];
  List<ReceptionBl> blList = const [
    ReceptionBl(id: 'bl1', ref: 'BL-778', grossiste: 'LABOREX', lines: 2),
    ReceptionBl(id: 'bl2', ref: 'BL-990', grossiste: 'COPHARMED', lines: 5),
  ];

  final periods = <String>[];
  @override
  Future<List<ReceptionBl>> bls({String query = '', required DateTime from, required DateTime to}) async {
    periods.add('${from.toIso8601String().substring(0, 10)}..${to.toIso8601String().substring(0, 10)}');
    return blList.where((b) => b.ref.startsWith(query)).toList();
  }
  @override
  Future<List<ReceptionLine>> blLines(String blId, {String query = ''}) async =>
      lines.where((l) => query.isEmpty || l.code == query || l.name.toLowerCase().startsWith(query.toLowerCase())).toList();
  @override
  Future<List<MotifRetour>> motifs() async => motifList;

  ({bool success, String message}) _put(String produitId, String motifId, int qty) {
    final line = lines.firstWhere((l) => l.produitId == produitId);
    final i = items0.indexWhere((x) => x.produitId == produitId);
    final current = i < 0 ? 0 : items0[i].quantity;
    if (current + qty > line.received) return (success: false, message: 'L\'opération a échoué . Veuillez vérifier la quantité à retourner');
    final motif = i < 0 ? motifList.firstWhere((m) => m.id == motifId).label : items0[i].motif;
    final updated = RetourLine(id: 'r$produitId', produitId: produitId, name: line.name, cip: line.code, motif: motif, quantity: current + qty);
    if (i < 0) {
      items0.add(updated);
    } else {
      items0[i] = updated;
    }
    return (success: true, message: 'ok');
  }

  @override
  Future<({bool success, String message, RetourCreated? retour})> create({
    required String blRef,
    required String produitId,
    required String motifId,
    required int quantity,
    String comment = '',
  }) async {
    created.add({'bl': blRef, 'produit': produitId, 'motif': motifId, 'qty': quantity, 'comment': comment});
    final r = _put(produitId, motifId, quantity);
    return (success: r.success, message: r.message, retour: r.success ? const RetourCreated('ret1', 'K7Q2M9XA') : null);
  }

  @override
  Future<({bool success, String message})> addItem({required String retourId, required String produitId, required String motifId, required int quantity}) async {
    added.add({'retour': retourId, 'produit': produitId, 'motif': motifId, 'qty': quantity});
    return _put(produitId, motifId, quantity);
  }

  @override
  Future<({bool success, String message})> updateItem(String lineId, int quantity) async {
    final i = items0.indexWhere((x) => x.id == lineId);
    final x = items0[i];
    items0[i] = RetourLine(id: x.id, produitId: x.produitId, name: x.name, cip: x.cip, motif: x.motif, quantity: quantity);
    return (success: true, message: 'ok');
  }

  @override
  Future<bool> removeItem(String lineId) async {
    items0.removeWhere((x) => x.id == lineId);
    return true;
  }

  @override
  Future<List<RetourLine>> items(String retourId) async => List.of(items0);
}

void main() {
  group('Quantité à retourner', () {
    const line = ReceptionLine(detailId: 'd', produitId: 'p', name: 'X', ordered: 10, received: 10, stock: 6);
    test('reçu, stock et quantité déjà dans le retour', () {
      expect(checkReturnQuantity(line: line, alreadyInReturn: 0, quantity: 6), isNull);
      expect(checkReturnQuantity(line: line, alreadyInReturn: 0, quantity: 0), contains('nulle'));
      expect(checkReturnQuantity(line: line, alreadyInReturn: 0, quantity: 7), contains('Stock insuffisant : 6 en stock'));
      expect(checkReturnQuantity(line: line, alreadyInReturn: 4, quantity: 3), contains('4 déjà dans ce retour'));
      const big = ReceptionLine(detailId: 'd', produitId: 'p', name: 'X', ordered: 10, received: 10, stock: 50);
      expect(checkReturnQuantity(line: big, alreadyInReturn: 8, quantity: 3), contains('quantité reçue sur ce BL (10, dont 8'));
    });

    test('lecture des motifs et des lignes renvoyés par Prestige', () {
      expect(MotifRetour.fromJson({'lgMOTIFRETOUR': '02', 'strCODE': 'AV', 'strLIBELLE': 'Avarié'}).label, 'Avarié');
      final l = RetourLine.fromJson({'lgRETOURFRSDETAIL': 'x', 'produitId': 'p', 'strNAME': 'N', 'intCIP': '123', 'motif': 'Périmé', 'intNUMBERRETURN': 4});
      expect(l.quantity, 4);
      final bl = ReceptionLine.fromJson({'int_QTE_CMDE': 10, 'int_QTE_RECUE_BIS': 8, 'freeQty': 2, 'lg_FAMILLE_QTE_STOCK': 5});
      expect(bl.received, 10);
      expect(ReceptionLine.fromJson({'int_QTE_CMDE': 7, 'int_QTE_RECUE_BIS': -1}).received, 7);
    });
  });

  group('Écran de retour', () {
    late FakeRetourServer server;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      server = FakeRetourServer();
    });

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(
                  builder: (_) => RetourBlScreen(bl: server.blList.first, gateway: server),
                )),
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
    }

    final scanField = find.byType(TextField).first;
    Future<void> scan(WidgetTester tester, String code) async {
      await tester.enterText(scanField, code);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
    }

    testWidgets('scan -> quantité -> motif -> ajout ; 2e produit ; terminer en préparation', (tester) async {
      await pump(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Commentaire du retour (facultatif)'), 'Cartons abîmés');
      await scan(tester, '3595583');
      expect(find.text('DOLIPRANE 1000MG CP'), findsOneWidget);
      expect(find.text('Reçu (BL)'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Quantité à retourner'), '2');
      await tester.tap(find.text('Avarié / cassé'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajouter au retour'));
      await tester.pumpAndSettle();
      expect(server.created.single, {'bl': 'BL-778', 'produit': 'p1', 'motif': '02', 'qty': 2, 'comment': 'Cartons abîmés'});
      expect(find.text('Retour K7Q2M9XA — BL BL-778'), findsOneWidget);

      // Produit suivant : le motif précédent est déjà choisi.
      await scan(tester, 'amoxi');
      await tester.tap(find.text('Ajouter au retour'));
      await tester.pumpAndSettle();
      expect(server.added.single, {'retour': 'ret1', 'produit': 'p2', 'motif': '02', 'qty': 1});
      expect(find.text('AMOXICILLINE 500'), findsOneWidget);

      await tester.tap(find.text('Terminer : retour en préparation (3)'));
      await tester.pumpAndSettle();
      expect(find.text('Retour en préparation'), findsOneWidget);
      expect(find.textContaining('2 produit(s), 3 boîte(s)'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('ouvrir'), findsOneWidget);
    });

    testWidgets('produit absent du BL, stock insuffisant, motif manquant : refusés', (tester) async {
      await pump(tester);
      await scan(tester, '9999999');
      expect(find.text('Produit absent de ce BL'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await scan(tester, '3000000'); // 3 en stock
      await tester.enterText(find.widgetWithText(TextField, 'Quantité à retourner'), '4');
      await tester.tap(find.text('Ajouter au retour'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Stock insuffisant : 3 en stock'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Quantité à retourner'), '2');
      await tester.tap(find.text('Ajouter au retour'));
      await tester.pumpAndSettle();
      expect(find.text('Motif obligatoire'), findsOneWidget);
      expect(server.created, isEmpty);
    });

    testWidgets('même produit avec un autre motif : prévenu ; modification et retrait d\'une ligne', (tester) async {
      await pump(tester);
      await scan(tester, '3595583');
      await tester.tap(find.text('Périmé'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajouter au retour'));
      await tester.pumpAndSettle();

      await scan(tester, '3595583');
      expect(find.text('Dans ce retour'), findsOneWidget);
      await tester.tap(find.text('Erreur de livraison'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajouter au retour'));
      await tester.pumpAndSettle();
      expect(find.text('Produit déjà dans le retour'), findsOneWidget);
      await tester.tap(find.text('Ajouter'));
      await tester.pumpAndSettle();
      expect(server.items0.single.quantity, 2);
      expect(server.items0.single.motif, 'Périmé');

      await tester.tap(find.text('DOLIPRANE 1000MG CP'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Quantité à retourner').last, '5');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(server.items0.single.quantity, 5);

      await tester.tap(find.text('DOLIPRANE 1000MG CP'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retirer du retour'));
      await tester.pumpAndSettle();
      expect(server.items0, isEmpty);
    });
  });

  testWidgets('choix du BL : aujourd\'hui par défaut, période, filtre par grossiste', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final server = FakeRetourServer();
    await tester.pumpWidget(MaterialApp(home: RetourHomeScreen(gateway: server, clock: () => DateTime(2026, 10, 10, 9))));
    await tester.pumpAndSettle();
    expect(server.periods.single, '2026-10-10..2026-10-10');
    expect(find.text('Entrés en stock le 10/10/2026 · 2 BL'), findsOneWidget);
    await tester.tap(find.text('7 jours'));
    await tester.pumpAndSettle();
    expect(server.periods.last, '2026-10-04..2026-10-10');
    expect(find.text('BL BL-778 — LABOREX'), findsOneWidget);
    expect(find.text('BL BL-990 — COPHARMED'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'LABOREX'));
    await tester.pumpAndSettle();
    expect(find.text('BL BL-990 — COPHARMED'), findsNothing);
    await tester.tap(find.text('BL BL-778 — LABOREX'));
    await tester.pumpAndSettle();
    expect(find.text('Retour — BL BL-778'), findsOneWidget);
  });
}
