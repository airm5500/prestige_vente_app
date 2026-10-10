// Vente Dépôt : présentations A, B, C (liste + saisie) sur 360 px, contrôles de saisie,
// erreurs réseau distinguées d'une liste vide, pas de double clôture.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/depot_model.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/providers/depot_sale_provider.dart';
import 'package:prestige_vente_app/screens/depot_sale/depot_sale_list_screen.dart';
import 'package:prestige_vente_app/screens/depot_sale/depot_sale_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(baseUrl: 'http://localhost');

  bool listFails = false;
  bool itemsFail = false;
  bool searchFails = false;
  bool depotsFail = false;
  bool closeOk = true;
  int closeCalls = 0;
  int updateCalls = 0;
  int addCalls = 0;
  Duration closeDelay = Duration.zero;

  @override
  Future<List<DepotSaleListItem>> fetchDepotSales({String query = '', String statut = 'is_Process', int start = 0, int limit = 15}) async {
    if (listFails) throw const ApiLoadException('Serveur injoignable (ventes dépôt non chargés).');
    return [
      DepotSaleListItem(
        lgPREENREGISTREMENTID: 'v1',
        strREF: 'DEP-0042',
        strClientFullName: 'PHARMACIE DU DÉPÔT DE YOPOUGON ANANERAIE NORD',
        dtUPDATED: '10/10/2026',
        heure: '09:41',
        intPRICE: 1254300,
        strSTATUT: 'is_Process',
        userFullName: 'Awa Kouassi',
      ),
      DepotSaleListItem(
        lgPREENREGISTREMENTID: 'v2',
        strREF: 'DEP-0007',
        strClientFullName: 'DEPOT ABOBO',
        dtUPDATED: '01/09/2026',
        heure: '15:02',
        intPRICE: 12000,
        strSTATUT: 'is_Process',
        userFullName: '',
      ),
      DepotSaleListItem(
        lgPREENREGISTREMENTID: 'v3',
        strREF: 'DEP-VIDE',
        strClientFullName: 'VIDE',
        dtUPDATED: '10/10/2026',
        heure: '10:00',
        intPRICE: 0,
        strSTATUT: 'is_Process',
        userFullName: '',
      ),
    ];
  }

  @override
  Future<Map<String, dynamic>?> getDepotSaleDetails(String saleId) async => {
        'strREF': 'DEP-0042',
        'magasin': {
          'lgCLIENTID': 'c1',
          'strFIRSTNAME': 'DEPOT',
          'strLASTNAME': 'YOPOUGON',
          'strNAME': '',
          'lgEMPLACEMENTID': 'e1',
          'lgTYPEDEPOTID': 't1',
          'desciptiontypedepot': 'Dépôt',
        },
      };

  @override
  Future<List<DepotModel>> fetchDepots({String query = ''}) async {
    if (depotsFail) throw const ApiLoadException('Serveur injoignable (dépôts non chargés).');
    return [
        DepotModel(
          lgCLIENTID: 'c1',
          strFIRSTNAME: 'DEPOT',
          strLASTNAME: 'YOPOUGON',
          strNAME: '',
          lgEMPLACEMENTID: 'e1',
          lgTYPEDEPOTID: 't1',
          descriptionTypeDepot: 'Dépôt',
        ),
      ];
  }

  @override
  Future<List<SaleLine>> fetchDepotSaleItems(String venteId) async {
    if (itemsFail) throw const ApiLoadException('Serveur injoignable (lignes de la vente non chargés).');
    return [
      SaleLine(
        lgPREENREGISTREMENTDETAILID: 'd1',
        lgFAMILLEID: 'p1',
        strNAME: 'DOLIPRANE 1000MG COMPRIME SECABLE BOITE DE 8 TRES LONG NOM',
        intPRICE: 15000,
        intPRICEUNITAIR: 1500,
        intQUANTITY: 10,
      ),
      SaleLine(
        lgPREENREGISTREMENTDETAILID: 'd2',
        lgFAMILLEID: 'p2',
        strNAME: 'EFFERALGAN 500',
        intPRICE: 1239300,
        intPRICEUNITAIR: 1239300,
        intQUANTITY: 1,
      ),
    ];
  }

  @override
  Future<List<ProductSearchResult>> searchDepotProducts(String query) async {
    if (searchFails) throw const ApiLoadException('Serveur injoignable (produits non chargés).');
    return [];
  }

  @override
  Future<bool> addNextDepotItem({
    required String venteId,
    required String clientId,
    required String emplacementId,
    required String typeDepotId,
    required String produitId,
    required int itemPu,
    required int qte,
  }) async {
    addCalls++;
    return true;
  }

  @override
  Future<bool> updateDepotItem({required String itemId, required String produitId, required int itemPu, required int qte}) async {
    updateCalls++;
    return true;
  }

  @override
  Future<bool> removeDepotItem(String itemId) async => true;

  @override
  Future<bool> closeDepotSale({required String venteId, required String clientId}) async {
    closeCalls++;
    if (closeDelay > Duration.zero) await Future<void>.delayed(closeDelay);
    return closeOk;
  }

  @override
  Future<bool> deleteSale(String saleId) async => true;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(720, 1400); // 360 x 700
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  Widget app(_FakeApi api, DepotSaleProvider provider, Widget home) => MultiProvider(
        providers: [
          Provider<ApiService>.value(value: api),
          ChangeNotifierProvider.value(value: provider),
        ],
        child: MaterialApp(home: home),
      );

  // Ouvre l'écran de saisie depuis un écran parent (pour tester le retour).
  Widget pushed(Widget screen) => Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => screen)),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      );

  for (final style in ListPresentation.values) {
    testWidgets('Liste ventes dépôt — ${style.label}', (tester) async {
      phone(tester);
      final api = _FakeApi();
      final provider = DepotSaleProvider(api);
      await tester.pumpWidget(app(api, provider, DepotSaleListScreen(presentation: style, clock: () => DateTime(2026, 10, 10))));
      await tester.pumpAndSettle();
      expect(find.text('Ventes Dépôt en cours'), findsOneWidget);
      expect(find.text('DEP-0042'), findsOneWidget);
      expect(find.text('DEP-0007'), findsOneWidget);
      expect(find.text('DEP-VIDE'), findsNothing); // filtre existant : montant > 0
      expect(find.text('Nouvelle Vente'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Recherche locale.
      await tester.enterText(find.byType(TextField).first, 'abobo');
      await tester.pumpAndSettle();
      expect(find.text('DEP-0042'), findsNothing);
      expect(find.text('DEP-0007'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pumpAndSettle();

      // Période « Aujourd'hui » : la vente du 01/09 disparaît.
      await tester.tap(find.text('Aujourd\'hui'));
      await tester.pumpAndSettle();
      expect(find.text('DEP-0042'), findsOneWidget);
      expect(find.text('DEP-0007'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Saisie vente dépôt — ${style.label}', (tester) async {
      phone(tester);
      final api = _FakeApi();
      final provider = DepotSaleProvider(api);
      expect(await provider.loadExistingSale('v1'), isTrue);
      await tester.pumpWidget(app(api, provider, DepotSaleScreen(presentation: style)));
      await tester.pumpAndSettle();
      expect(find.text('Vente Dépôt'), findsOneWidget);
      expect(find.text('Client: DEPOT YOPOUGON'), findsOneWidget);
      expect(find.textContaining('DOLIPRANE 1000MG'), findsOneWidget);
      expect(find.text('EFFERALGAN 500'), findsOneWidget);
      expect(find.text('TOTAL NET'), findsOneWidget);
      expect(find.text('1 254 300 F'.replaceAll(' ', ' ')).evaluate().isNotEmpty || find.textContaining('254').evaluate().isNotEmpty, isTrue);
      expect(find.text('CLÔTURER'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Nouvelle vente dépôt — ${style.label}', (tester) async {
      phone(tester);
      final api = _FakeApi();
      final provider = DepotSaleProvider(api);
      await tester.pumpWidget(app(api, provider, DepotSaleScreen(presentation: style)));
      await tester.pumpAndSettle();
      expect(find.text('Nouvelle Vente Dépôt'), findsOneWidget);
      expect(find.text('Sélectionner le Dépôt / Client'), findsOneWidget);
      expect(find.textContaining("Choisissez d'abord le dépôt"), findsOneWidget);
      final btn = tester.widget<ElevatedButton>(find.ancestor(of: find.text('CLÔTURER'), matching: find.byWidgetPredicate((w) => w is ElevatedButton)));
      expect(btn.onPressed, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Dépôts non chargés : erreur affichée avec « Réessayer »', (tester) async {
    phone(tester);
    final api = _FakeApi()..depotsFail = true;
    final provider = DepotSaleProvider(api);
    await tester.pumpWidget(app(api, provider, const DepotSaleScreen(presentation: ListPresentation.dashboard)));
    await tester.pumpAndSettle();
    expect(find.textContaining('dépôts non chargés'), findsOneWidget);
    api.depotsFail = false;
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('dépôts non chargés'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Liste : une erreur réseau n\'est pas affichée comme « aucune vente »', (tester) async {
    phone(tester);
    final api = _FakeApi()..listFails = true;
    final provider = DepotSaleProvider(api);
    await tester.pumpWidget(app(api, provider, const DepotSaleListScreen(presentation: ListPresentation.dashboard)));
    await tester.pumpAndSettle();
    expect(find.text('Chargement impossible'), findsOneWidget);
    expect(find.textContaining('Serveur injoignable'), findsOneWidget);
    expect(find.text('Aucune vente en cours'), findsNothing);
    api.listFails = false;
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.text('DEP-0042'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Modification de ligne : quantité absurde refusée, rien envoyé', (tester) async {
    phone(tester);
    final api = _FakeApi();
    final provider = DepotSaleProvider(api);
    await provider.loadExistingSale('v1');
    await tester.pumpWidget(app(api, provider, const DepotSaleScreen(presentation: ListPresentation.dashboard)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Modifier').first);
    await tester.pumpAndSettle();
    expect(find.text('MODIFICATION LIGNE'), findsOneWidget);
    final qty = find.widgetWithText(TextFormField, 'Quantité');
    await tester.enterText(qty, '0');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(find.text('Minimum 1'), findsOneWidget);
    await tester.enterText(qty, '');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(find.text('Quantité requise'), findsOneWidget);
    // Les lettres et le signe moins sont filtrés.
    await tester.enterText(qty, '-3a');
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
    expect(api.updateCalls, 0);
    // Valeur correcte : envoyée une fois, dialogue fermé après la réponse.
    await tester.enterText(qty, '12');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(api.updateCalls, 1);
    expect(find.text('MODIFICATION LIGNE'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Quantité à l\'ajout : 0 et > 9999 refusés', (tester) async {
    phone(tester);
    final product = ProductSearchResult(
      lgFAMILLEID: 'p1', strNAME: 'DOLIPRANE', intCIP: '3595583', intPRICE: 1500, intNUMBERAVAILABLE: 4, strLIBELLEE: '', intPAF: 0);
    int? result = -1;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: ElevatedButton(
            onPressed: () async => result = await showDialog<int>(context: ctx, builder: (_) => QuantityDialog(product: product)),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '0');
    await tester.tap(find.text('Ajouter'));
    await tester.pumpAndSettle();
    expect(find.text('Min 1'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '99999');
    await tester.tap(find.text('Ajouter'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Trop grand'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '3');
    await tester.tap(find.text('Ajouter'));
    await tester.pumpAndSettle();
    expect(result, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Clôture : confirmation, une seule clôture, échec affiché et vente conservée', (tester) async {
    phone(tester);
    final api = _FakeApi()
      ..closeOk = false
      ..closeDelay = const Duration(milliseconds: 300);
    final provider = DepotSaleProvider(api);
    await provider.loadExistingSale('v1');
    await tester.pumpWidget(app(api, provider, const DepotSaleScreen(presentation: ListPresentation.guided)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CLÔTURER'));
    await tester.pumpAndSettle();
    expect(find.text('Clôturer Vente Dépôt'), findsOneWidget);
    await tester.tap(find.text('Oui'));
    await tester.pump();
    // Second appui pendant l'envoi : ignoré.
    await tester.tap(find.text('CLÔTURER'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(api.closeCalls, 1);
    expect(find.textContaining('Vente NON clôturée'), findsOneWidget);
    expect(provider.cartItems.length, 2);
    expect(provider.currentSaleId, 'v1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Panier non relu : bandeau d\'erreur, clôture bloquée', (tester) async {
    phone(tester);
    final api = _FakeApi();
    final provider = DepotSaleProvider(api);
    await provider.loadExistingSale('v1');
    api.itemsFail = true;
    await tester.pumpWidget(app(api, provider, const DepotSaleScreen(presentation: ListPresentation.compact)));
    await tester.pumpAndSettle();
    // Un ajout réussi suivi d'un échec de relecture : panier conservé, erreur affichée.
    final ok = await provider.addToCart(ProductSearchResult(
        lgFAMILLEID: 'p3', strNAME: 'X', intCIP: '1', intPRICE: 100, intNUMBERAVAILABLE: 5, strLIBELLEE: '', intPAF: 0));
    await tester.pumpAndSettle();
    expect(ok, isTrue);
    expect(api.addCalls, 1);
    expect(provider.cartItems.length, 2);
    expect(find.textContaining('Panier non actualisé'), findsOneWidget);
    final btn = tester.widget<ElevatedButton>(find.ancestor(of: find.text('CLÔTURER'), matching: find.byWidgetPredicate((w) => w is ElevatedButton)));
    expect(btn.onPressed, isNull);
    api.itemsFail = false;
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Panier non actualisé'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Recherche : une erreur réseau n\'est pas « produit introuvable »', (tester) async {
    phone(tester);
    final api = _FakeApi()..searchFails = true;
    final provider = DepotSaleProvider(api);
    await provider.loadExistingSale('v1');
    await tester.pumpWidget(app(api, provider, const DepotSaleScreen(presentation: ListPresentation.dashboard)));
    await tester.pumpAndSettle();
    final search = find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Saisir nom ou scanner');
    await tester.enterText(search, '3595583');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.textContaining('Recherche impossible'), findsOneWidget);
    expect(find.text('Produit introuvable'), findsNothing);
    expect(api.addCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Quitter avec un panier non vide demande confirmation', (tester) async {
    phone(tester);
    final api = _FakeApi();
    final provider = DepotSaleProvider(api);
    await provider.loadExistingSale('v1');
    await tester.pumpWidget(app(api, provider, pushed(const DepotSaleScreen(presentation: ListPresentation.dashboard))));
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Retour'));
    await tester.pumpAndSettle();
    expect(find.text('Quitter la vente ?'), findsOneWidget);
    await tester.tap(find.text('Rester'));
    await tester.pumpAndSettle();
    expect(find.text('TOTAL NET'), findsOneWidget);
    await tester.tap(find.byTooltip('Retour'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quitter'));
    await tester.pumpAndSettle();
    expect(find.text('ouvrir'), findsOneWidget);
    expect(provider.currentSaleId, 'v1'); // la vente reste en cours
    expect(tester.takeException(), isNull);
  });
}
