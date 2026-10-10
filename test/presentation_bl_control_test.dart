// Pointage BL Stock : les trois présentations (A, B, C) de la liste, du pointage et du rapport
// sur un petit téléphone (360 px), et les contrôles de saisie des quantités.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/bon_livraison.dart';
import 'package:prestige_vente_app/api/models/bon_livraison_item.dart';
import 'package:prestige_vente_app/providers/bl_control_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/screens/bl_control/bl_detail_screen.dart';
import 'package:prestige_vente_app/screens/bl_control/bl_list_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(baseUrl: 'http://localhost');

  final posts = <(String, int)>[];
  int itemCalls = 0;

  @override
  Future<List<BonLivraison>> getBonsLivraison({String query = '', String? dtStart, String? dtEnd}) async => [
        BonLivraison(
          id: 'bl1',
          ref: 'BL-2026-0042',
          grossiste: 'LABOREX COTE D\'IVOIRE DISTRIBUTION',
          date: '10/10/2026',
          nbreLignes: 2,
          montantTotal: 1254300,
          statutTraitement: 'EN_COURS',
          strStatut: 'is_Closed',
        ),
        BonLivraison(
          id: 'bl2',
          ref: 'BL-2026-0043',
          grossiste: 'DPCI',
          date: '10/10/2026',
          nbreLignes: 1,
          montantTotal: 5000,
          statutTraitement: 'A_FAIRE',
          strStatut: 'is_Closed',
        ),
        BonLivraison(
          id: 'bl3',
          ref: 'BL-2026-0001',
          grossiste: 'COPHARMED',
          date: '01/10/2026',
          nbreLignes: 4,
          montantTotal: 90000,
          statutTraitement: 'TERMINE',
          strStatut: 'is_Closed',
        ),
      ];

  @override
  Future<List<BonLivraisonItem>> getBonLivraisonItems(String blId) async {
    itemCalls++;
    return [
      BonLivraisonItem(
        id: 'd1',
        produitId: 'p1',
        nomProduit: 'DOLIPRANE 1000MG CP B/8 BOITE FAMILIALE GRAND MODELE',
        cip: '3595583',
        qteCommandee: 5,
        qteRecue: 5,
        stockFinal: 10,
        stockInitialReel: 5,
        freeQty: 0,
        isChecked: false,
        checkedQuantity: 0,
        prixAchat: 1100,
        prixVente: 1500,
        zoneGeoName: 'RAYON A3',
      ),
      BonLivraisonItem(
        id: 'd2',
        produitId: 'p2',
        nomProduit: 'EFFERALGAN 500MG',
        cip: '3400000',
        qteCommandee: 3,
        qteRecue: 3,
        stockFinal: 3,
        stockInitialReel: 0,
        freeQty: 0,
        isChecked: true,
        checkedQuantity: 2,
        prixAchat: 600,
        prixVente: 900,
        zoneGeoName: 'RAYON B1',
      ),
    ];
  }

  @override
  Future<bool> postBonItemCheckedQuantity({required String detailId, required int quantity}) async {
    posts.add((detailId, quantity));
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

  Widget app(_FakeApi api, BlControlProvider bl, Widget home) => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider.value(value: bl),
        ],
        child: MaterialApp(home: home),
      );

  /// Pointage d'un BL déjà sélectionné.
  Future<_FakeApi> openDetail(WidgetTester tester, ListPresentation style) async {
    final api = _FakeApi();
    final provider = BlControlProvider(api);
    await provider.fetchBonsLivraison();
    await provider.selectBonLivraison(provider.bonsLivraison.first);
    await tester.pumpWidget(app(api, provider, BlDetailScreen(presentation: style)));
    await tester.pumpAndSettle();
    return api;
  }

  /// Amène l'élément en haut de la liste (sous l'en-tête) puis le touche.
  Future<void> tapVisible(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Finder qtyField() => find.ancestor(of: find.text('Qté'), matching: find.byType(TextField));

  for (final style in ListPresentation.values) {
    testWidgets('Liste, pointage et rapport — ${style.label}', (tester) async {
      phone(tester);
      final api = _FakeApi();
      final provider = BlControlProvider(api);
      await tester.pumpWidget(app(api, provider, BlListScreen(initialFilter: 'A_TRAITER', presentation: style)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // À traiter par défaut : le BL terminé est masqué.
      expect(find.textContaining('BL-2026-0042'), findsOneWidget);
      final list = find.descendant(of: find.byType(ListView).first, matching: find.byType(Scrollable)).first;
      await tester.scrollUntilVisible(find.textContaining('BL-2026-0043'), 150, scrollable: list);
      expect(find.textContaining('BL-2026-0043'), findsOneWidget);
      expect(find.textContaining('BL-2026-0001'), findsNothing);
      expect(find.text('Rechercher'), findsOneWidget);
      expect(find.text('Date Début'), findsOneWidget);

      // Filtre « Terminés ».
      await tapVisible(tester, find.textContaining('Terminés').first);
      expect(find.textContaining('BL-2026-0001'), findsOneWidget);
      expect(find.textContaining('BL-2026-0042'), findsNothing);
      await tapVisible(tester, find.textContaining('À Traiter').first);

      // Ouverture du BL -> pointage.
      await tapVisible(tester, find.textContaining('BL-2026-0042').first);
      expect(tester.takeException(), isNull);
      expect(api.itemCalls, 1);
      expect(find.text('BL BL-2026-0042'), findsOneWidget);
      expect(find.text('EFFERALGAN 500MG'), findsOneWidget);
      expect(find.text('1/2 lignes'), findsOneWidget);
      final rapport = find.ancestor(of: find.text('Rapport'), matching: find.byWidgetPredicate((w) => w is ElevatedButton));
      expect(rapport, findsOneWidget);

      // Rapport.
      await tester.tap(rapport);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Rapport & Supervision'), findsOneWidget);
      expect(find.text('1 / 2 produits contrôlés dans cette zone'), findsOneWidget);
      expect(find.text('Non compté'), findsOneWidget);
      expect(find.text('Imprimer la liste affichée (2)'), findsOneWidget);
      await tester.tap(find.text('Avec écart (1)'));
      await tester.pumpAndSettle();
      expect(find.text('-1'), findsOneWidget); // 2 comptés pour 3 attendus
      expect(find.text('Imprimer la liste affichée (1)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Quantité trop grande refusée, rien envoyé', (tester) async {
    phone(tester);
    final api = await openDetail(tester, ListPresentation.dashboard);
    final field = qtyField().first; // première ligne (DOLIPRANE)
    await tester.enterText(field, '50000');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(find.textContaining('Quantité refusée'), findsOneWidget);
    expect(api.posts, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Lettres impossibles dans la quantité', (tester) async {
    phone(tester);
    await openDetail(tester, ListPresentation.compact);
    final field = qtyField().first;
    await tester.enterText(field, '1a2-');
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, '12');
  });

  testWidgets('Écart absurde : confirmation, puis rien envoyé si on corrige', (tester) async {
    phone(tester);
    final api = await openDetail(tester, ListPresentation.guided);
    final field = qtyField().first;
    await tester.enterText(field, '500'); // attendu : 10
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(find.text('Quantité inhabituelle'), findsOneWidget);
    await tester.tap(find.text('Corriger'));
    await tester.pumpAndSettle();
    expect(api.posts, isEmpty);
    expect(tester.widget<TextField>(field).controller!.text, '');

    // Valeur normale : envoyée une seule fois.
    await tester.enterText(field, '11');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(api.posts, [('d1', 11)]);
    // Même valeur : pas de nouvel envoi.
    await tester.tap(field);
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(api.posts.length, 1);

    // Écart confirmé : envoyé.
    await tester.enterText(field, '400');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmer 400'));
    await tester.pumpAndSettle();
    expect(api.posts.last, ('d1', 400));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Scan d\'un CIP : saisie rapide bornée', (tester) async {
    phone(tester);
    final api = await openDetail(tester, ListPresentation.dashboard);
    await tester.enterText(find.widgetWithText(TextField, 'Rechercher (Scan, Nom, CIP)'), '3595583');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('Saisir la quantité comptée :'), findsOneWidget);
    final dialogField = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(dialogField, '20000');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(find.text('Mauvaise valeur : de 0 à 10000'), findsOneWidget);
    expect(api.posts, isEmpty);

    await tester.enterText(dialogField, '9');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(api.posts, [('d1', 9)]);
    expect(find.textContaining('Quantité mise à jour : 9'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Période : la date de fin ne peut pas précéder le début', (tester) async {
    phone(tester);
    final api = _FakeApi();
    await tester.pumpWidget(app(api, BlControlProvider(api), const BlListScreen(presentation: ListPresentation.compact)));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.calendar_today).last);
    await tester.pumpAndSettle();
    final picker = tester.widget<CalendarDatePicker>(find.byType(CalendarDatePicker));
    final now = DateTime.now();
    expect(picker.firstDate, DateTime(now.year, now.month, now.day));
    await tester.tap(find.text('Annuler').evaluate().isNotEmpty ? find.text('Annuler') : find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Retour arrière pendant la saisie : quantité enregistrée, pas de plantage', (tester) async {
    phone(tester);
    final api = _FakeApi();
    await tester.pumpWidget(app(api, BlControlProvider(api), const BlListScreen(presentation: ListPresentation.dashboard)));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.textContaining('BL-2026-0042').first);
    await tester.enterText(qtyField().first, '11');
    await tester.pump();
    await tester.tap(find.byTooltip('Retour'));
    await tester.pumpAndSettle();
    expect(find.text('Bons de Livraison'), findsOneWidget);
    expect(api.posts, [('d1', 11)]);
    expect(tester.takeException(), isNull);
  });

  test('Écart inhabituel', () {
    expect(isSuspiciousBlCount(counted: 12, reference: 10), isFalse);
    expect(isSuspiciousBlCount(counted: 30, reference: 10), isFalse);
    expect(isSuspiciousBlCount(counted: 31, reference: 10), isTrue);
    expect(isSuspiciousBlCount(counted: 0, reference: 300), isFalse);
    expect(isSuspiciousBlCount(counted: 700, reference: 300), isTrue);
  });
}
