// Gestion des Périmés : les trois présentations (A, B, C) sur un petit téléphone (360 px),
// et les contrôles de saisie (date impossible, quantité absurde, lot vide, confirmations,
// pas de double envoi).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/perime_models.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/providers/perime_provider.dart';
import 'package:prestige_vente_app/screens/perimes/perime_main_screen.dart';
import 'package:prestige_vente_app/screens/perimes/perime_widgets.dart';
import 'package:prestige_vente_app/screens/perimes/tabs/saisie_perimes_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart' show ProductPage;

class _FakeApi extends ApiService {
  // Recherche par pages : mêmes produits que la recherche simulée ci-dessous.
  @override
  Future<ProductPage> searchProductsPageOrFail(String query, int start, int limit) async {
    final all = await searchProducts(query);
    return ProductPage(all.skip(start).take(limit).toList(), all.length);
  }

  _FakeApi() : super(baseUrl: 'http://localhost');

  final adds = <Map<String, dynamic>>[];
  final deletes = <String>[];
  final closes = <String>[];
  Completer<void>? addGate;

  List<SaisieEnCoursItem> enCours = [
    SaisieEnCoursItem(
      id: 'it1',
      lot: 'AMX24',
      produitCip: '3400000',
      quantity: 4,
      produitId: 'p9',
      stockInitial: 10,
      dateEntree: '2026-10-01',
      datePeremption: '2026-09-30',
      stockFinal: 6,
      produitLibelle: 'AMOXICILLINE 500MG GELULES B/12',
    ),
  ];

  @override
  Future<Map<String, dynamic>> getProduitsPerimes(int nbreMois) async => {
        'data': <ProduitPerime>[
          ProduitPerime(
            libelleRayon: 'RAYON A3',
            numLot: 'LT2201',
            datePerement: '30/09/2026',
            libelleGrossiste: 'LABOREX',
            libelle: 'DOLIPRANE 1000MG CP B/8',
            statut: 'Périmé il y a 10 jours',
            libelleFamille: 'ANTALGIQUES',
            quantiteLot: 12,
            codeCip: '3595583',
            valeurVente: 18000,
            valeurAchat: 13200,
          ),
          ProduitPerime(
            libelleRayon: '',
            numLot: '',
            datePerement: '15/12/2026',
            libelleGrossiste: 'DPCI',
            libelle: 'SPASFON LYOC 80MG COMPRIMES ORODISPERSIBLES BOITE DE 10 TRES LONG LIBELLE',
            statut: 'Périme dans 2 mois',
            libelleFamille: '',
            quantiteLot: 3,
            codeCip: '3000001',
            valeurVente: 4500,
            valeurAchat: 3300,
          ),
        ],
        'metaData': PerimeMetaData(totalQuantiteLot: 15, totalValeurAchat: 16500, totalValeurVente: 1234567890),
      };

  @override
  Future<List<SaisieEnCoursItem>> getSaisiePerimesEnCours() async => List.of(enCours);

  @override
  Future<List<SaisiePerimeItem>> getSaisiePerimesHistory({String? dtStart, String? dtEnd}) async => [
        SaisiePerimeItem(
          intCIP: '3011111',
          strNAME: 'IBUPROFENE 400MG CP B/30',
          prixAchat: 900,
          intPRICE: 1250,
          stockInitial: 8,
          intQUANTITY: 2,
          stockFinal: 6,
          ticketNum: 'IB77',
          dtCREATED: '2026-08-31',
          dateOperation: '10/10/2026 09:12',
          libelleRayon: 'B1',
        ),
      ];

  @override
  Future<List<ProductSearchResult>> searchProducts(String query) async => [
        ProductSearchResult(
          lgFAMILLEID: 'fam42',
          strNAME: 'DOLIPRANE 500MG CP B/16',
          intCIP: '3400935',
          intPRICE: 900,
          intNUMBERAVAILABLE: 50,
          strLIBELLEE: '',
          intPAF: 600,
        ),
      ];

  @override
  Future<Map<String, dynamic>> addPerimeItem({
    required String produitId,
    required String datePeremption,
    required String lot,
    required int quantite,
  }) async {
    adds.add({'produitId': produitId, 'date': datePeremption, 'lot': lot, 'qte': quantite});
    if (addGate != null) await addGate!.future;
    return {'success': true};
  }

  @override
  Future<bool> deletePerimeItem(String itemId) async {
    deletes.add(itemId);
    enCours = enCours.where((e) => e.id != itemId).toList();
    return true;
  }

  @override
  Future<bool> closeSaisiePerimes(String batchId) async {
    closes.add(batchId);
    enCours = [];
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

  Widget app(_FakeApi api, Widget home) => ChangeNotifierProvider(
        create: (_) => PerimeProvider(api),
        child: MaterialApp(home: home),
      );

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3)); // snackbars, anti-rebond
    await tester.pumpAndSettle();
  }

  Future<void> openSaisieAndSelect(WidgetTester tester) async {
    await tester.tap(find.text('Saisie').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'doli');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DOLIPRANE 500MG CP B/16'));
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  for (final style in ListPresentation.values) {
    testWidgets('Gestion Périmés — ${style.label} : les trois onglets', (tester) async {
      phone(tester);
      final api = _FakeApi();
      await tester.pumpWidget(app(api, PerimeMainScreen(presentation: style)));
      await tester.pumpAndSettle();

      expect(find.text('Gestion des Périmés'), findsOneWidget);
      expect(find.text('Périmés dans :'), findsOneWidget);
      expect(find.text('Imprimer'), findsOneWidget);
      expect(find.text('Val. vente'), findsOneWidget);
      expect(find.text('DOLIPRANE 1000MG CP B/8'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('DOLIPRANE 1000MG CP B/8'));
      await tester.pumpAndSettle();
      expect(find.text('LABOREX'), findsOneWidget);
      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Saisie').first);
      await tester.pumpAndSettle();
      expect(find.text('AMOXICILLINE 500MG GELULES B/12'), findsOneWidget);
      expect(find.text('Valider la Saisie (1)'), findsOneWidget);
      expect(find.text('boîtes à sortir'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Historique').first);
      await tester.pumpAndSettle();
      expect(find.text('IBUPROFENE 400MG CP B/30 (Qté: 2)'), findsOneWidget);
      expect(find.text('Date Début'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Formulaire de saisie à 360 px, sans débordement.
      await openSaisieAndSelect(tester);
      expect(find.text('Ajouter à la liste'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await settle(tester);
    });

    testWidgets('Saisie / Historique (sous-onglets) — ${style.label}', (tester) async {
      phone(tester);
      final api = _FakeApi();
      await tester.pumpWidget(app(api, Scaffold(body: SaisiePerimesScreen(presentation: style))));
      await tester.pumpAndSettle();
      expect(find.text('Saisie en Cours'), findsOneWidget);
      expect(find.text('Historique des Saisies'), findsOneWidget);
      expect(find.text('AMOXICILLINE 500MG GELULES B/12'), findsOneWidget);
      await tester.tap(find.text('Historique des Saisies'));
      await tester.pumpAndSettle();
      expect(find.text('IBUPROFENE 400MG CP B/30 (Qté: 2)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Saisie : date impossible, quantité ou lot absurdes refusés, rien envoyé', (tester) async {
    phone(tester);
    final api = _FakeApi();
    await tester.pumpWidget(app(api, const PerimeMainScreen(presentation: ListPresentation.dashboard)));
    await tester.pumpAndSettle();
    await openSaisieAndSelect(tester);

    // 31 février : refusé.
    await tester.enterText(field('Date Péremption (JJMMAA ou MMAA) *'), '310226');
    await tester.enterText(field('N° Lot *'), 'L1');
    await tester.tap(find.text('Ajouter à la liste'));
    await tester.pumpAndSettle();
    expect(find.text('Date invalide (JJMMAA ou MMAA)'), findsOneWidget);
    expect(api.adds, isEmpty);

    // Mois 13 : refusé.
    await tester.enterText(field('Date Péremption (JJMMAA ou MMAA) *'), '1326');
    await tester.tap(find.text('Ajouter à la liste'));
    await tester.pumpAndSettle();
    expect(find.text('Date invalide (JJMMAA ou MMAA)'), findsOneWidget);

    // Quantité 0 et lot blanc : refusés.
    await tester.enterText(field('Date Péremption (JJMMAA ou MMAA) *'), '1226');
    await tester.enterText(field('N° Lot *'), '   ');
    await tester.enterText(field('Quantité *'), '0');
    await tester.tap(find.text('Ajouter à la liste'));
    await tester.pumpAndSettle();
    expect(find.text('Min. 1'), findsOneWidget);
    expect(find.text('Requis'), findsOneWidget);
    expect(api.adds, isEmpty);

    // Lettres dans la quantité : filtrées à la frappe ; 6 chiffres : coupés à 5.
    await tester.enterText(field('Quantité *'), '12abc');
    expect(find.text('12'), findsOneWidget);
    await tester.enterText(field('Quantité *'), '1234567');
    expect(find.text('12345'), findsOneWidget);

    // Quantité supérieure au stock (50) : confirmation, « Annuler » n'envoie rien.
    await tester.enterText(field('N° Lot *'), 'L1');
    await tester.enterText(field('Quantité *'), '99');
    await tester.tap(find.text('Ajouter à la liste'));
    await tester.pumpAndSettle();
    expect(find.text('Quantité supérieure au stock'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(api.adds, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Saisie : un seul envoi malgré un double appui, valeurs nettoyées', (tester) async {
    phone(tester);
    final api = _FakeApi()..addGate = Completer<void>();
    await tester.pumpWidget(app(api, const PerimeMainScreen(presentation: ListPresentation.guided)));
    await tester.pumpAndSettle();
    await openSaisieAndSelect(tester);

    await tester.enterText(field('Date Péremption (JJMMAA ou MMAA) *'), '15/12/26');
    await tester.enterText(field('N° Lot *'), '  LT-99  ');
    await tester.enterText(field('Quantité *'), '3');
    await tester.tap(find.text('Ajouter à la liste'));
    await tester.tap(find.text('Ajouter à la liste'), warnIfMissed: false);
    await tester.pump();
    expect(api.adds.length, 1);
    expect(api.adds.single, {'produitId': 'fam42', 'date': '2026-12-15', 'lot': 'LT-99', 'qte': 3});

    api.addGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Produit ajouté.'), findsOneWidget);
    expect(api.adds.length, 1);
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Saisie : confirmation avant suppression et avant validation', (tester) async {
    phone(tester);
    final api = _FakeApi();
    await tester.pumpWidget(app(api, const PerimeMainScreen(presentation: ListPresentation.compact)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saisie').first);
    await tester.pumpAndSettle();

    // Suppression : annulée, puis confirmée.
    await tester.tap(find.byTooltip('Retirer'));
    await tester.pumpAndSettle();
    expect(find.text('Retirer ce produit ?'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(api.deletes, isEmpty);

    // Validation : annulée, rien n'est envoyé.
    await tester.tap(find.text('Valider la Saisie (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Valider la Saisie ?'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(api.closes, isEmpty);

    // Validation confirmée : un seul envoi.
    await tester.tap(find.text('Valider la Saisie (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Valider'));
    await tester.pumpAndSettle();
    expect(api.closes, ['it1']);
    expect(find.text('Saisie validée avec succès.'), findsOneWidget);
    await settle(tester);

    // Plus rien en cours : état vide explicite.
    expect(find.text('Aucun produit en cours de saisie.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Saisie : suppression confirmée', (tester) async {
    phone(tester);
    final api = _FakeApi();
    await tester.pumpWidget(app(api, const PerimeMainScreen(presentation: ListPresentation.dashboard)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saisie').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Retirer'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Retirer'));
    await tester.pumpAndSettle();
    expect(api.deletes, ['it1']);
    expect(find.text('AMOXICILLINE 500MG GELULES B/12'), findsNothing);
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  group('parseDatePeremption', () {
    final now = DateTime(2026, 10, 10);
    test('formats acceptés', () {
      expect(parseDatePeremption('1226', now: now), DateTime(2026, 12, 1));
      expect(parseDatePeremption('150327', now: now), DateTime(2027, 3, 15));
      expect(parseDatePeremption('29/02/2028', now: now), DateTime(2028, 2, 29));
      expect(parseDatePeremption('01-01-2025', now: now), DateTime(2025, 1, 1));
    });
    test('dates impossibles ou fantaisistes refusées', () {
      for (final bad in ['', '12', '310226', '290227', '1326', '0026', '000126', '01/01/1999', '01/01/2040', '12ab', '1234567890123']) {
        expect(parseDatePeremption(bad, now: now), isNull, reason: bad);
      }
    });
  });
}
