// Contrôle Réception : les trois présentations (A, B, C) des écrans liste, comptage et rapport,
// sans débordement à 360 px, et les contrôles de saisie (quantités, écarts, double envoi, période).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/reception_model.dart';
import 'package:prestige_vente_app/providers/reception_provider.dart';
import 'package:prestige_vente_app/screens/reception_control/reception_detail_screen.dart';
import 'package:prestige_vente_app/screens/reception_control/reception_list_screen.dart';
import 'package:prestige_vente_app/screens/reception_control/reception_report_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

ReceptionItem _item(String id, String name, String cip, int expected, int checked, String zone) => ReceptionItem(
      id: id,
      produitId: 'p$id',
      nomProduit: name,
      cip: cip,
      ean: '',
      qteCommandee: expected,
      qteRecue: expected,
      quantiteControle: checked,
      prixAchat: 1000,
      prixVente: 1500,
      emplacement: zone,
    );

class _FakeApi extends ApiService {
  _FakeApi() : super(baseUrl: 'http://localhost');
  final posted = <(String, int)>[];
  final queries = <String>[];

  @override
  Future<List<ReceptionBon>> getReceptionBons({String query = '', String? dtStart, String? dtEnd}) async {
    queries.add('$dtStart|$dtEnd|$query');
    return [
      ReceptionBon(
        id: 'b1',
        ref: 'BL-2026-000123-LABOREX',
        grossiste: 'LABOREX CÔTE D\'IVOIRE DISTRIBUTION',
        dateLivraison: '10/10/2026',
        dateCreation: '10/10/2026',
        statutTraitement: 'EN_COURS',
        nbreLignes: 3,
        montantHt: 1254300,
        details: [
          _item('d1', 'DOLIPRANE 1000MG CP B/8 BOITE FAMILIALE GRAND MODELE', '3595583', 5, 0, 'RAYON A1'),
          _item('d2', 'EFFERALGAN 500MG', '3400000', 10, 10, 'RAYON A1'),
          _item('d3', 'SMECTA SACHETS', '3411111', 3, 0, ''),
        ],
      ),
      ReceptionBon(
        id: 'b2',
        ref: 'BL-0099',
        grossiste: 'COPHARMED',
        dateLivraison: '09/10/2026',
        dateCreation: '09/10/2026',
        statutTraitement: 'TERMINE',
        nbreLignes: 1,
        montantHt: 5000,
        details: [_item('d9', 'SPASFON', '3422222', 2, 2, 'RAYON B')],
      ),
    ];
  }

  @override
  Future<bool> postBonItemCheckedQuantity({required String detailId, required int quantity}) async {
    posted.add((detailId, quantity));
    return true;
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(720, 1400); // 360 x 700
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  Future<ReceptionProvider> selected(_FakeApi api) async {
    final p = ReceptionProvider(api);
    await p.fetchReceptionBons(dtStart: '2026-10-10', dtEnd: '2026-10-10');
    p.selectBon(p.receptionBons.first);
    return p;
  }

  Widget app(ReceptionProvider p, Widget home) => ChangeNotifierProvider<ReceptionProvider>.value(
        value: p,
        child: MaterialApp(home: home),
      );

  for (final style in ListPresentation.values) {
    testWidgets('Liste des bons — ${style.label}', (tester) async {
      phone(tester);
      final api = _FakeApi();
      final p = ReceptionProvider(api);
      await tester.pumpWidget(app(p, ReceptionListScreen(presentation: style, clock: () => DateTime(2026, 10, 10))));
      await tester.pumpAndSettle();
      expect(find.text('Contrôle Réception'), findsOneWidget);
      expect(find.text('BL-2026-000123-LABOREX'), findsOneWidget);
      expect(find.text('Le 10/10/2026'), findsOneWidget);
      expect(api.queries.single, '2026-10-10|2026-10-10|');
      expect(find.byTooltip('Présentation'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Onglet des bons terminés.
      await tester.drag(find.byType(TabBarView), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(find.text('BL-0099'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Ouverture d'un bon : l'écran de comptage reçoit la présentation.
      await tester.drag(find.byType(TabBarView), const Offset(300, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('BL-2026-000123-LABOREX'));
      await tester.pumpAndSettle();
      expect(find.byType(ReceptionDetailScreen), findsOneWidget);
      expect(find.text('EFFERALGAN 500MG'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Comptage et rapport — ${style.label}', (tester) async {
      phone(tester);
      final api = _FakeApi();
      final p = await selected(api);
      await tester.pumpWidget(app(p, ReceptionDetailScreen(presentation: style)));
      await tester.pumpAndSettle();
      expect(find.text('BL-2026-000123-LABOREX'), findsOneWidget);
      expect(find.text('SMECTA SACHETS'), findsOneWidget);
      expect(find.text('Sans Emplacement'.toUpperCase()).evaluate().isNotEmpty || find.text('Sans Emplacement').evaluate().isNotEmpty, isTrue);
      final reportButton = find.ancestor(of: find.text('Rapport'), matching: find.byWidgetPredicate((w) => w is ElevatedButton));
      expect(reportButton, findsOneWidget);
      expect(tester.takeException(), isNull);

      // Saisie normale dans la case « Reçu » : envoyée en quittant la case.
      await tester.enterText(find.byKey(const ValueKey('qte_d1')), '5');
      await tester.showKeyboard(find.byType(TextField).first);
      await tester.pumpAndSettle();
      expect(api.posted, [('d1', 5)]);

      // Filtre « Écarts » : aucun écart.
      await tester.ensureVisible(find.textContaining('Écarts ('));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Écarts ('));
      await tester.pumpAndSettle();
      expect(find.text('Aucun produit trouvé'), findsOneWidget);
      await tester.tap(find.text('Tout afficher'));
      await tester.pumpAndSettle();

      await tester.tap(reportButton);
      await tester.pumpAndSettle();
      expect(find.text('Rapport & Supervision'), findsOneWidget);
      expect(find.text('Imprimer PDF (3)'), findsOneWidget);
      expect(find.text('2 / 3 produits contrôlés (Global)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Quantité trop grande refusée, rien envoyé', (tester) async {
    phone(tester);
    final api = _FakeApi();
    final p = await selected(api);
    await tester.pumpWidget(app(p, const ReceptionDetailScreen(presentation: ListPresentation.dashboard)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('qte_d1')), '99999');
    await tester.showKeyboard(find.byType(TextField).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Quantité refusée'), findsOneWidget);
    expect(api.posted, isEmpty);
    // Caractères non numériques filtrés.
    await tester.enterText(find.byKey(const ValueKey('qte_d3')), '-3a');
    expect(find.descendant(of: find.byKey(const ValueKey('qte_d3')), matching: find.text('3')), findsOneWidget);
  });

  testWidgets('Écart inhabituel : confirmation demandée', (tester) async {
    phone(tester);
    final api = _FakeApi();
    final p = await selected(api);
    await tester.pumpWidget(app(p, const ReceptionDetailScreen(presentation: ListPresentation.guided)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('qte_d1')), '500');
    await tester.showKeyboard(find.byType(TextField).first);
    await tester.pumpAndSettle();
    expect(find.text('Quantité inhabituelle'), findsOneWidget);
    await tester.tap(find.text('Corriger'));
    await tester.pumpAndSettle();
    expect(api.posted, isEmpty);

    await tester.enterText(find.byKey(const ValueKey('qte_d1')), '50');
    await tester.showKeyboard(find.byType(TextField).first);
    await tester.pumpAndSettle();
    expect(find.text('Quantité inhabituelle'), findsOneWidget);
    await tester.tap(find.text('Confirmer'));
    await tester.pumpAndSettle();
    expect(api.posted, [('d1', 50)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Scan rapide : dialogue de quantité borné', (tester) async {
    phone(tester);
    final api = _FakeApi();
    final p = await selected(api);
    await tester.pumpWidget(app(p, const ReceptionDetailScreen(presentation: ListPresentation.compact)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '3411111');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('Saisir la quantité comptée :'), findsOneWidget);
    final dialogField = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(dialogField, '20000');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(find.text('Quantité invalide (0 à 10000)'), findsOneWidget);
    expect(api.posted, isEmpty);

    await tester.enterText(dialogField, '3');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(api.posted, [('d3', 3)]);

    // Code inconnu : message, pas de dialogue.
    await tester.enterText(find.byType(TextField).first, '0000000');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('Produit introuvable dans ce bon.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Rapport : pas de double impression', (tester) async {
    phone(tester);
    final api = _FakeApi();
    final p = await selected(api);
    var calls = 0;
    final done = Completer<void>();
    await tester.pumpWidget(app(
      p,
      ReceptionReportScreen(
        presentation: ListPresentation.dashboard,
        printer: ({required bon, required items, required filterTitle}) {
          calls++;
          return done.future;
        },
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Imprimer PDF (3)'));
    await tester.pump();
    await tester.tap(find.text('Impression…'), warnIfMissed: false);
    await tester.pump();
    expect(calls, 1);
    expect(find.text('Impression…'), findsOneWidget);
    done.complete();
    await tester.pumpAndSettle();
    expect(find.text('Imprimer PDF (3)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('Règles de saisie', () {
    expect(ReceptionQuantity.parse('12'), 12);
    expect(ReceptionQuantity.parse(' 0 '), 0);
    expect(ReceptionQuantity.parse('10001'), isNull);
    expect(ReceptionQuantity.parse('-1'), isNull);
    expect(ReceptionQuantity.parse('abc'), isNull);
    expect(ReceptionQuantity.isUnusual(15, 5), isFalse);
    expect(ReceptionQuantity.isUnusual(16, 5), isTrue);
    expect(ReceptionQuantity.isUnusual(200, 100), isFalse);
    expect(ReceptionQuantity.isUnusual(201, 100), isTrue);
    expect(ReceptionQuantity.isUnusual(0, 100), isFalse);

    final (s, e) = ReceptionPeriod.ordered(DateTime(2026, 10, 12), DateTime(2026, 10, 1));
    expect(s, DateTime(2026, 10, 1));
    expect(e, DateTime(2026, 10, 12));
    expect(ReceptionPeriod.cleanQuery('  BL\n123\t '), 'BL123');
    expect(ReceptionPeriod.cleanQuery('x' * 80).length, ReceptionPeriod.maxSearchLength);
  });
}
