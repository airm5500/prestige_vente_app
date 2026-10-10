// Pré-vente / Vente (nouvelle version) : parcours complet à 360 px, choix final prévente/vente,
// double scan (1 seule vente), double tap encaissement (1 seule clôture), panne / réponse perdue / refus,
// caisse fermée, net non à jour, panier non relu, quitter / reprendre, liste des préventes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/assurance_sale_summary.dart';
import 'package:prestige_vente_app/api/models/ayant_droit.dart';
import 'package:prestige_vente_app/api/models/client_assurance.dart';
import 'package:prestige_vente_app/api/models/payment_method_qr.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/api/models/tiers_payant_assurance.dart';
import 'package:prestige_vente_app/api/models/user.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/core/pending_sale_store.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_controller.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProductSearchResult _p(String id, String name, String cip, {int price = 1500, int stock = 10}) => ProductSearchResult(
      lgFAMILLEID: id,
      strNAME: name,
      intCIP: cip,
      intPRICE: price,
      intNUMBERAVAILABLE: stock,
      strLIBELLEE: '',
      intPAF: 0,
    );

final _doli = _p('P1', 'DOLIPRANE 1000MG CP B/8', '3400930000001');
final _effer = _p('P2', 'EFFERALGAN 500MG', '3400930000002', price: 1200);

enum _Mode { ok, failed, lost, lostNotApplied, refused, caisse }

class _FakeGateway implements VenteGateway {
  // Paiement en plusieurs modes : non utilisé par ces tests.
  @override
  Future<VenteResult<Map<String, dynamic>>> cloturerVnoReglements({
    required String venteId,
    required SaleSummary summary,
    required List<VenteReglement> reglements,
    required String clientId,
    required String userVendeurId,
    required int montantRecu,
    required int montantRemis,
  }) =>
      throw UnimplementedError();

  @override
  Future<VenteResult<Map<String, dynamic>>> cloturerAssuranceReglements({
    required String venteId,
    required String clientId,
    required String ayantDroitId,
    required String natureVenteId,
    required String typeVenteId,
    required String? userVendeurId,
    required AssuranceSaleSummary summary,
    required List<VenteReglement> reglements,
    required List<VenteTp> tierspayants,
    required int montantRecu,
    required int montantRemis,
  }) =>
      throw UnimplementedError();

  // Recherche par pages : même catalogue que searchProducts (une seule page).
  @override
  Future<VenteResult<ProductPage>> searchProductsPage(String query, int start, int limit) async {
    final r = await searchProducts(query);
    return r.map((items) => ProductPage(start == 0 ? items : const [], items.length));
  }

  Duration delay = const Duration(milliseconds: 50);
  final List<ProductSearchResult> catalog = [_doli, _effer];
  final Map<String, List<SaleItemDetail>> sales = {};
  final Map<String, String> statut = {};
  final List<String?> addVenteIds = [];
  final List<bool> addPrevente = [];
  int creations = 0;
  int terminerCalls = 0;
  int clotureCalls = 0;
  final List<String> clients = [];
  bool searchFails = false;
  bool detailsFail = false;
  bool netFails = false;
  _Mode addMode = _Mode.ok;
  _Mode clotureMode = _Mode.ok;
  _Mode terminerMode = _Mode.ok;
  List<PreventeListItem> preventeList = [];

  Future<void> _wait() => Future.delayed(delay);

  SaleItemDetail _line(String venteId, ProductSearchResult p, int qty, int pu) => SaleItemDetail(
        lgPREENREGISTREMENTDETAILID: '$venteId-L${(sales[venteId]?.length ?? 0) + 1}',
        lgFAMILLEID: p.lgFAMILLEID,
        strNAME: p.strNAME,
        intCIP: p.intCIP,
        intQUANTITY: qty,
        intPRICEUNITAIR: pu,
        intPRICE: qty * pu,
        strREF: 'REF-$venteId',
      );

  @override
  Future<VenteResult<List<ProductSearchResult>>> searchProducts(String query) async {
    await _wait();
    if (searchFails) return const VenteFailed('Serveur injoignable (rechercher le produit).');
    final q = query.toLowerCase();
    return VenteOk(catalog.where((p) => p.strNAME.toLowerCase().contains(q) || p.intCIP == query).toList());
  }

  @override
  Future<VenteResult<String>> addItemVno({required String produitId, required int qte, required int itemPu, String? venteId, required bool prevente}) async {
    addVenteIds.add(venteId);
    addPrevente.add(prevente);
    await _wait();
    final mode = addMode;
    if (mode == _Mode.failed) return const VenteFailed('Serveur injoignable (ajouter le produit).');
    if (mode == _Mode.refused) return const VenteRefused('Plafond de vente atteint pour ce produit');
    if (mode == _Mode.caisse) return const VenteRefused('Désolé votre caisse est fermée');
    if (mode == _Mode.lostNotApplied) return const VenteFailed('Le serveur met trop de temps à répondre.', maybeApplied: true);
    var id = venteId;
    if (id == null) {
      creations++;
      id = 'V$creations';
      sales[id] = [];
      statut[id] = 'pending';
    }
    final p = catalog.firstWhere((p) => p.lgFAMILLEID == produitId);
    sales[id]!.add(_line(id, p, qte, itemPu));
    if (mode == _Mode.lost) return const VenteFailed('Le serveur met trop de temps à répondre.', maybeApplied: true);
    return VenteOk(id);
  }

  @override
  Future<VenteResult<List<SaleItemDetail>>> saleDetails(String venteId) async {
    await _wait();
    if (detailsFail) return const VenteFailed('Serveur injoignable (relire le panier).');
    return VenteOk(List.of(sales[venteId] ?? const []));
  }

  @override
  Future<VenteResult<SaleSummary>> netVno(String venteId) async {
    await _wait();
    if (netFails) return const VenteFailed('Serveur injoignable (calculer le net).');
    final total = (sales[venteId] ?? const []).fold<int>(0, (s, i) => s + i.intPRICE);
    return VenteOk(SaleSummary(montant: total, montantNet: total, venteId: venteId, reference: 'REF-$venteId'));
  }

  @override
  Future<VenteResult<void>> updateItem({required String itemId, required String produitId, required int qte, required int itemPu}) async {
    await _wait();
    for (final e in sales.entries) {
      final i = e.value.indexWhere((l) => l.lgPREENREGISTREMENTDETAILID == itemId);
      if (i >= 0) {
        final l = e.value[i];
        e.value[i] = SaleItemDetail(
          lgPREENREGISTREMENTDETAILID: itemId,
          lgFAMILLEID: l.lgFAMILLEID,
          strNAME: l.strNAME,
          intCIP: l.intCIP,
          intQUANTITY: qte,
          intPRICEUNITAIR: itemPu,
          intPRICE: qte * itemPu,
          strREF: l.strREF,
        );
      }
    }
    return const VenteOk(null);
  }

  @override
  Future<VenteResult<void>> removeItem(String itemId) async {
    await _wait();
    for (final l in sales.values) {
      l.removeWhere((x) => x.lgPREENREGISTREMENTDETAILID == itemId);
    }
    return const VenteOk(null);
  }

  @override
  Future<VenteResult<void>> terminerPrevente(String venteId) async {
    terminerCalls++;
    await _wait();
    if (terminerMode == _Mode.caisse) return const VenteRefused('Désolé votre caisse est fermée. Veuillez l\'ouvrir');
    statut[venteId] = 'is_Process';
    return const VenteOk(null);
  }

  @override
  Future<VenteResult<void>> updateClient(String venteId, String clientId) async {
    clients.add(clientId);
    await _wait();
    return const VenteOk(null);
  }

  @override
  Future<VenteResult<Map<String, dynamic>>> cloturerVno({
    required String venteId,
    required SaleSummary summary,
    required String typeReglementId,
    required String clientId,
    required String userVendeurId,
    int? montantRecu,
    int? montantRemis,
  }) async {
    clotureCalls++;
    await _wait();
    if (statut[venteId] == 'is_Closed') return const VenteRefused('Cette vente a déjà été clôturée');
    switch (clotureMode) {
      case _Mode.caisse:
        return const VenteRefused('Désolé votre caisse est fermée. Veuillez l\'ouvrir avant de proceder à validation');
      case _Mode.lost:
        statut[venteId] = 'is_Closed';
        return const VenteFailed('Le serveur met trop de temps à répondre.', maybeApplied: true);
      default:
        statut[venteId] = 'is_Closed';
        return const VenteOk({'success': true});
    }
  }

  @override
  Future<VenteResult<List<PaymentMethod>>> paymentMethods() async {
    await _wait();
    return VenteOk([PaymentMethod(id: '1', name: 'Espèces'), PaymentMethod(id: '10', name: 'WAVE'), PaymentMethod(id: '7', name: 'ORANGE')]);
  }

  @override
  Future<VenteResult<List<PaymentMethodQr>>> paymentMethodsWithQr() async => const VenteOk([]);

  @override
  Future<VenteResult<List<PreventeListItem>>> preventes() async {
    await _wait();
    return VenteOk(preventeList);
  }

  @override
  Future<VenteResult<Map<String, dynamic>>> fullSale(String venteId) async {
    await _wait();
    final s = statut[venteId];
    if (s == null) return const VenteFailed('Vente introuvable ou réponse illisible.');
    return VenteOk({'strSTATUT': s});
  }

  // --- Non utilisés par ce menu ---
  @override
  Future<VenteResult<List<PreventeListItem>>> ventesByType(String typeVenteId) => throw UnimplementedError();
  @override
  Future<VenteResult<List<ClientAssurance>>> searchClients(String query, {required String typeClientId}) => throw UnimplementedError();
  @override
  Future<VenteResult<List<TiersPayantAssurance>>> searchTiersPayants(String query, {required bool carnet}) => throw UnimplementedError();
  @override
  Future<VenteResult<List<AyantDroit>>> ayantDroits(String clientId) => throw UnimplementedError();
  @override
  Future<VenteResult<AyantDroit>> createAyantDroit({required String clientId, required String firstName, required String lastName, required String numSecu}) =>
      throw UnimplementedError();
  @override
  Future<VenteResult<ClientAssurance>> createClientAssurance(
          {required String firstName, required String lastName, required String numSecu, required String tiersPayantId, required int pourcentage}) =>
      throw UnimplementedError();
  @override
  Future<VenteResult<ClientAssurance>> createClientCarnet(
          {required String firstName, required String lastName, required String numSecu, required String tiersPayantId}) =>
      throw UnimplementedError();
  @override
  Future<VenteResult<ClientAssurance>> addTiersPayantToClient({required ClientAssurance client, required Map<String, dynamic> newTiersPayantPayload}) =>
      throw UnimplementedError();
  @override
  Future<VenteResult<ClientAssurance>> updateClientAssurance({required ClientAssurance client, required List<Map<String, dynamic>> tiersPayantsPayload}) =>
      throw UnimplementedError();
  @override
  Future<VenteResult<String>> addItemAssurance({
    required String produitId,
    required int qte,
    required int itemPu,
    required String clientId,
    required String ayantDroitId,
    required String natureVenteId,
    required String typeVenteId,
    required String? userVendeurId,
    required List<VenteTp> tierspayants,
    String? venteId,
  }) =>
      throw UnimplementedError();
  @override
  Future<VenteResult<AssuranceSaleSummary>> netAssurance({required String venteId, required List<VenteTp> tierspayants}) => throw UnimplementedError();
  @override
  Future<VenteResult<Map<String, dynamic>>> cloturerAssurance({
    required String venteId,
    required String clientId,
    required String ayantDroitId,
    required String natureVenteId,
    required String typeVenteId,
    required String? userVendeurId,
    required AssuranceSaleSummary summary,
    required String typeReglementId,
    required List<VenteTp> tierspayants,
    int? montantRecu,
    int? montantRemis,
  }) =>
      throw UnimplementedError();
}

class _Auth extends AuthProvider {
  _Auth() : super(ApiService(baseUrl: 'http://localhost'));
  @override
  User? get user => User(userId: 'U1', login: 'awa', firstName: 'Awa', lastName: 'Kouassi', officineName: 'TEST');
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(720, 1400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

/// Ouvre l'écran depuis un écran d'accueil (pour tester le retour arrière).
Future<void> _open(WidgetTester tester, _FakeGateway gw, {String? resumeVenteId, int initialTab = 0, bool pumpApp = true}) async {
  if (pumpApp) {
    final settings = SettingsProvider();
    await settings.loadSettings();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth()),
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(
                  builder: (_) => VenteScreen(gateway: gw, resumeVenteId: _resume, initialTabIndex: _tab),
                )),
                child: const Text('Ouvrir'),
              ),
            ),
          ),
        ),
      ),
    ));
  }
  _resume = resumeVenteId;
  _tab = initialTab;
  await tester.tap(find.text('Ouvrir'));
  await tester.pumpAndSettle();
}

String? _resume;
int _tab = 0;

/// Net à payer affiché dans le pied de l'écran (« 3 000 F », « — » si non calculé).
Finder _netText(String t) => find.byWidgetPredicate((w) => w is Text && w.key == const ValueKey('vente-net') && w.data == t);
Finder _net(int v) => _netText('${Constants.formatNumber(v)} F');

Finder get _field => find.byKey(const ValueKey('vente-recherche'));
Finder get _encaisser => find.byKey(const ValueKey('vente-encaisser'));
Finder get _enregistrer => find.byKey(const ValueKey('vente-enregistrer-prevente'));

bool _enabled(WidgetTester tester, Finder f) {
  return (tester.widget(f) as ButtonStyleButton).onPressed != null;
}

/// Recherche manuelle + quantité.
Future<void> _addManual(WidgetTester tester, String query, {String qty = '1'}) async {
  await tester.enterText(_field, query);
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
  await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField)), qty);
  await tester.tap(find.text('Ajouter'));
  await tester.pumpAndSettle();
}

/// Scan (douchette dans le champ) en mode scan rapide.
Future<void> _scan(WidgetTester tester, String code) async {
  await tester.enterText(_field, code);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pump();
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  setUp(() => SharedPreferences.setMockInitialValues({
        'enabled_payment_method_ids': ['1', '10'],
      }));

  testWidgets('parcours complet : ajout, modification, encaissement espèces (1 clôture, vente créée en prévente)', (tester) async {
    _phone(tester);
    final gw = _FakeGateway();
    await _open(tester, gw);

    await tester.enterText(_field, 'do');
    await tester.pump();
    expect(find.text('Saisissez au moins 3 caractères'), findsOneWidget);

    await _addManual(tester, 'doli', qty: '2');
    expect(find.text('DOLIPRANE 1000MG CP B/8'), findsOneWidget);
    expect(_net(3000), findsOneWidget);
    expect(gw.addPrevente, [true]);
    expect((await PendingSaleStore.load(VenteMenu.prevente))?.venteId, 'V1');

    // Modifier la ligne : quantité 0 refusée, 3 acceptée.
    await tester.tap(find.byTooltip('Modifier'));
    await tester.pumpAndSettle();
    final fields = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField));
    await tester.enterText(fields.first, '0');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(find.text('Entre 1 et 9999'), findsOneWidget);
    await tester.enterText(fields.first, '3');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(_net(4500), findsOneWidget);

    await tester.tap(_encaisser);
    await tester.pumpAndSettle();
    expect(find.text('ORANGE'), findsNothing); // mode non activé dans les réglages
    await tester.tap(find.text('Espèces'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('encaissement-recu')), '5000');
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const ValueKey('encaissement-monnaie'))).data, '${Constants.formatNumber(500)} F');
    await tester.tap(find.byKey(const ValueKey('encaissement-imprimer'))); // pas d'impression
    await tester.pump();
    await tester.tap(find.text('VALIDER L\'ENCAISSEMENT'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Vente encaissée'), findsOneWidget);

    expect(gw.clotureCalls, 1);
    expect(gw.clients, ['espèces']); // même règle qu'avant (seul « é » est remplacé)
    expect(gw.statut['V1'], 'is_Closed');
    expect(find.text('Le panier est vide'), findsOneWidget);
    expect(await PendingSaleStore.load(VenteMenu.prevente), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('« Enregistrer en prévente » : terminerprevente, aucune clôture', (tester) async {
    _phone(tester);
    final gw = _FakeGateway();
    await _open(tester, gw);
    await _addManual(tester, 'doli');
    await tester.tap(_enregistrer);
    await tester.pumpAndSettle();
    expect(find.text('Prévente enregistrée'), findsOneWidget);
    await tester.tap(find.text('Non'));
    await tester.pumpAndSettle();
    expect(gw.terminerCalls, 1);
    expect(gw.clotureCalls, 0);
    expect(gw.statut['V1'], 'is_Process');
    expect(await PendingSaleStore.load(VenteMenu.prevente), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('double scan rapide du 1ᵉʳ produit : une seule vente créée, « ajouté » après le serveur', (tester) async {
    _phone(tester);
    SharedPreferences.setMockInitialValues({'isQuickScanMode': true, 'enabled_payment_method_ids': ['1']});
    final gw = _FakeGateway()..delay = const Duration(milliseconds: 200);
    await _open(tester, gw);
    expect(find.text('SCAN RAPIDE ACTIF'), findsOneWidget);

    await _scan(tester, _doli.intCIP);
    await _scan(tester, _doli.intCIP);
    await tester.pump(const Duration(milliseconds: 250)); // 1ʳᵉ recherche finie, ajout en cours
    expect(find.textContaining('ajouté (+1)'), findsNothing);
    await tester.pumpAndSettle();

    expect(gw.creations, 1);
    expect(gw.addVenteIds, [null, 'V1']);
    expect(gw.sales['V1']!.length, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('3ᵉ scan du même produit : « Combien en reste-t-il ? » ; Annuler n\'ajoute rien', (tester) async {
    _phone(tester);
    SharedPreferences.setMockInitialValues({'isQuickScanMode': true});
    final gw = _FakeGateway()..delay = const Duration(milliseconds: 10);
    await _open(tester, gw);
    for (var i = 0; i < 2; i++) {
      await _scan(tester, _doli.intCIP);
      await tester.pumpAndSettle();
    }
    await _scan(tester, _doli.intCIP);
    await tester.pumpAndSettle();
    expect(find.textContaining('Combien en reste-t-il'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(gw.addVenteIds.length, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('panne pendant l\'ajout : pas de « ajouté », message de panne', (tester) async {
    _phone(tester);
    SharedPreferences.setMockInitialValues({'isQuickScanMode': true});
    final gw = _FakeGateway()..addMode = _Mode.failed;
    await _open(tester, gw);
    await _scan(tester, _doli.intCIP);
    await tester.pumpAndSettle();
    expect(find.textContaining('ajouté'), findsNothing);
    expect(find.textContaining('injoignable'), findsOneWidget);
    expect(find.text('Le panier est vide'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recherche en panne : « Recherche impossible » + Réessayer, jamais « introuvable »', (tester) async {
    _phone(tester);
    SharedPreferences.setMockInitialValues({'isQuickScanMode': true});
    final gw = _FakeGateway()..searchFails = true;
    await _open(tester, gw);
    await _scan(tester, _doli.intCIP);
    await tester.pumpAndSettle();
    expect(find.textContaining('Recherche impossible'), findsOneWidget);
    expect(find.textContaining('introuvable'), findsNothing);
    expect(find.text('Réessayer'), findsOneWidget);
    gw.searchFails = false;
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(gw.sales['V1']!.length, 1);

    await _scan(tester, '0000000000000');
    await tester.pumpAndSettle();
    expect(find.textContaining('Code 0000000000000 introuvable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('réponse perdue à l\'ajout : panier relu, pas de renvoi ni de doublon', (tester) async {
    _phone(tester);
    final gw = _FakeGateway();
    await _open(tester, gw);
    await _addManual(tester, 'doli');
    gw.addMode = _Mode.lost; // le serveur applique mais la réponse se perd
    await _addManual(tester, 'effer');
    expect(gw.addVenteIds.length, 2);
    expect(gw.sales['V1']!.length, 2);
    expect(find.text('EFFERALGAN 500MG'), findsOneWidget);
    expect(_net(2700), findsOneWidget);

    gw.addMode = _Mode.lostNotApplied; // rien appliqué : message, pas d'« ajouté »
    await _addManual(tester, 'effer');
    expect(gw.addVenteIds.length, 3);
    expect(gw.sales['V1']!.length, 2);
    expect(find.textContaining('Produit non ajouté'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refus du serveur : SON message est affiché', (tester) async {
    _phone(tester);
    final gw = _FakeGateway()..addMode = _Mode.refused;
    await _open(tester, gw);
    await _addManual(tester, 'doli');
    expect(find.text('Plafond de vente atteint pour ce produit'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('caisse fermée à l\'encaissement : proposition d\'ouvrir la caisse, vente non terminée', (tester) async {
    _phone(tester);
    final gw = _FakeGateway()..clotureMode = _Mode.caisse;
    await _open(tester, gw);
    await _addManual(tester, 'doli');
    await tester.tap(_encaisser);
    await tester.pumpAndSettle();
    await tester.tap(find.text('WAVE'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PAIEMENT REÇU — VALIDER'));
    await tester.pumpAndSettle();
    expect(find.text('Caisse Fermée'), findsOneWidget);
    await tester.tap(find.text('Non'));
    await tester.pumpAndSettle();
    expect(find.text('Caisse fermée : ouvrez-la avant de valider.'), findsOneWidget);
    await tester.tap(find.byTooltip('Retour'));
    await tester.pumpAndSettle();
    expect(find.text('DOLIPRANE 1000MG CP B/8'), findsOneWidget);
    expect(_enabled(tester, _encaisser), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('net non à jour : encaissement bloqué jusqu\'au recalcul', (tester) async {
    _phone(tester);
    final gw = _FakeGateway();
    await _open(tester, gw);
    await _addManual(tester, 'doli');
    gw.netFails = true;
    await _addManual(tester, 'effer');
    expect(find.textContaining('Net à payer non calculé'), findsWidgets);
    expect(_enabled(tester, _encaisser), isFalse);
    expect(_enabled(tester, _enregistrer), isFalse);
    expect(_netText('—'), findsOneWidget);

    gw.netFails = false;
    await tester.tap(find.text('Réessayer').first);
    await tester.pumpAndSettle();
    expect(_enabled(tester, _encaisser), isTrue);
    expect(_net(2700), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('panier non relu : ancien panier gardé + bandeau, encaissement bloqué', (tester) async {
    _phone(tester);
    final gw = _FakeGateway();
    await _open(tester, gw);
    await _addManual(tester, 'doli');
    gw.detailsFail = true;
    await _addManual(tester, 'effer');
    expect(find.text('DOLIPRANE 1000MG CP B/8'), findsOneWidget);
    expect(find.text('Le panier est vide'), findsNothing);
    expect(find.textContaining('Panier non relu'), findsWidgets);
    expect(_enabled(tester, _encaisser), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('double tap sur Encaisser puis VALIDER : une seule clôture', (tester) async {
    _phone(tester);
    final gw = _FakeGateway()..delay = const Duration(milliseconds: 100);
    await _open(tester, gw);
    await _addManual(tester, 'doli');
    await tester.tap(_encaisser);
    await tester.tap(_encaisser, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('MODE DE PAIEMENT'), findsOneWidget); // une seule page d'encaissement
    await tester.tap(find.text('WAVE'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('encaissement-imprimer')));
    await tester.pump();
    await tester.tap(find.text('PAIEMENT REÇU — VALIDER'));
    await tester.tap(find.byKey(const ValueKey('encaissement-valider')), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.textContaining('Vente encaissée'), findsOneWidget);
    expect(gw.clotureCalls, 1);
    expect(gw.clients, ['wave']);
    expect(tester.takeException(), isNull);
  });

  test('contrôleur : deux encaissements simultanés → une seule clôture ; réponse perdue → relecture', () async {
    SharedPreferences.setMockInitialValues({});
    final gw = _FakeGateway()..delay = const Duration(milliseconds: 5);
    final c = VenteController(gateway: gw);
    expect((await c.addProduct(_doli, 1)).isOk, isTrue);
    final m = PaymentMethod(id: '10', name: 'WAVE');
    final r = await Future.wait([
      c.encaisser(method: m, userId: 'U1', expectedChanges: c.changes),
      c.encaisser(method: m, userId: 'U1', expectedChanges: c.changes),
    ]);
    expect(r.every((x) => x.isOk), isTrue);
    expect(gw.clotureCalls, 1);

    // Réponse perdue à la clôture : la vente est relue (clôturée) → succès, sans 2ᵉ clôture.
    final gw2 = _FakeGateway()
      ..delay = const Duration(milliseconds: 5)
      ..clotureMode = _Mode.lost;
    final c2 = VenteController(gateway: gw2);
    await c2.addProduct(_doli, 1);
    final r2 = await c2.encaisser(method: m, userId: 'U1', expectedChanges: c2.changes);
    expect(r2.isOk, isTrue);
    expect(gw2.clotureCalls, 1);

    // Panier modifié entre la confirmation et la clôture : refusé.
    final gw3 = _FakeGateway()..delay = const Duration(milliseconds: 5);
    final c3 = VenteController(gateway: gw3);
    await c3.addProduct(_doli, 1);
    final before = c3.changes;
    await c3.addProduct(_effer, 1);
    expect((await c3.encaisser(method: m, userId: 'U1', expectedChanges: before)).isOk, isFalse);
    expect(gw3.clotureCalls, 0);
  });

  testWidgets('quitter en pleine vente : confirmation, vente mémorisée puis « Reprendre la vente ? »', (tester) async {
    _phone(tester);
    final gw = _FakeGateway();
    await _open(tester, gw);
    await _addManual(tester, 'doli');

    await tester.tap(find.byTooltip('Retour')); // flèche de l'en-tête
    await tester.pumpAndSettle();
    expect(find.text('Quitter la vente en cours ?'), findsOneWidget);
    await tester.tap(find.text('Rester'));
    await tester.pumpAndSettle();
    expect(find.text('DOLIPRANE 1000MG CP B/8'), findsOneWidget);

    await tester.tap(find.byTooltip('Retour')); // flèche de l'en-tête
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quitter'));
    await tester.pumpAndSettle();
    expect(find.text('Ouvrir'), findsOneWidget);

    await _open(tester, gw, pumpApp: false);
    expect(find.text('Reprendre la vente ?'), findsOneWidget);
    expect(find.textContaining('REF-V1'), findsOneWidget);
    await tester.tap(find.text('REPRENDRE'));
    await tester.pumpAndSettle();
    expect(find.text('DOLIPRANE 1000MG CP B/8'), findsOneWidget);
    await _addManual(tester, 'effer');
    expect(gw.creations, 1);
    expect(gw.addVenteIds.last, 'V1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('vente d\'une ordonnance (resumeVenteId) chargée au démarrage', (tester) async {
    _phone(tester);
    final gw = _FakeGateway();
    gw.sales['V9'] = [gw._line('V9', _effer, 2, 1200)];
    gw.statut['V9'] = 'pending';
    await _open(tester, gw, resumeVenteId: 'V9');
    expect(find.text('Reprendre la vente ?'), findsNothing);
    expect(find.text('EFFERALGAN 500MG'), findsOneWidget);
    expect(_net(2400), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('liste : vraie date, confirmation avant d\'ouvrir si un panier est en cours', (tester) async {
    _phone(tester);
    final gw = _FakeGateway();
    gw.sales['V7'] = [gw._line('V7', _effer, 1, 1200)];
    gw.statut['V7'] = 'is_Process';
    gw.preventeList = [
      PreventeListItem(
          lgPREENREGISTREMENTID: 'V7', heure: '09:41:12', dtUPDATED: '03/09/2026', intPRICE: 1200, strREF: 'PV-0007', userFullName: 'Awa', lgTYPEVENTEID: '1'),
      PreventeListItem(
          lgPREENREGISTREMENTID: 'V8', heure: '10:00:00', dtUPDATED: '05/09/2026', intPRICE: 900, strREF: 'PV-0008', userFullName: 'Koffi', lgTYPEVENTEID: '1'),
      PreventeListItem(
          lgPREENREGISTREMENTID: 'A1', heure: '10:00:00', dtUPDATED: '05/09/2026', intPRICE: 900, strREF: 'AS-0001', userFullName: 'Koffi', lgTYPEVENTEID: '2'),
    ];
    await _open(tester, gw);
    await _addManual(tester, 'doli');

    await tester.tap(find.byTooltip('Préventes à encaisser'));
    await tester.pumpAndSettle();
    expect(find.textContaining('03/09/2026 09:41'), findsOneWidget);
    expect(find.textContaining('05/09/2026 10:00'), findsOneWidget);
    expect(find.text('AS-0001'), findsNothing);
    // Plus récente en premier.
    expect(tester.getTopLeft(find.text('PV-0008')).dy, lessThan(tester.getTopLeft(find.text('PV-0007')).dy));

    await tester.tap(find.text('PV-0007'));
    await tester.pumpAndSettle();
    expect(find.text('Un panier est en cours'), findsOneWidget);
    await tester.tap(find.text('LA GARDER ET REVENIR'));
    await tester.pumpAndSettle();
    // Retour au panier, inchangé.
    expect(find.text('PV-0007'), findsNothing);
    expect(find.text('DOLIPRANE 1000MG CP B/8'), findsOneWidget);

    await tester.tap(find.byTooltip('Préventes à encaisser'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PV-0007'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ouvrir PV-0007 sans l\'enregistrer'));
    await tester.pumpAndSettle();
    expect(find.text('EFFERALGAN 500MG'), findsOneWidget);
    expect(find.text('DOLIPRANE 1000MG CP B/8'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('aucun mode de règlement activé : message clair', (tester) async {
    _phone(tester);
    SharedPreferences.setMockInitialValues({'enabled_payment_method_ids': <String>[]});
    final gw = _FakeGateway();
    await _open(tester, gw);
    await _addManual(tester, 'doli');
    await tester.tap(_encaisser);
    await tester.pumpAndSettle();
    expect(find.textContaining('Aucun mode de règlement n\'est activé'), findsOneWidget);
    expect(find.text('OUVRIR LES RÉGLAGES'), findsOneWidget);
    await tester.tap(find.text('RETOUR'));
    await tester.pumpAndSettle();
    expect(gw.clotureCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('suppression d\'une ligne avec confirmation', (tester) async {
    _phone(tester);
    final gw = _FakeGateway();
    await _open(tester, gw);
    await _addManual(tester, 'doli');
    await tester.tap(find.byTooltip('Supprimer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Non'));
    await tester.pumpAndSettle();
    expect(gw.sales['V1']!.length, 1);
    await tester.tap(find.byTooltip('Supprimer'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Supprimer'));
    await tester.pumpAndSettle();
    expect(gw.sales['V1'], isEmpty);
    expect(find.text('Le panier est vide'), findsOneWidget);
    expect(await PendingSaleStore.load(VenteMenu.prevente), isNull);
    expect(tester.takeException(), isNull);
  });

  test('date de la liste : format serveur dd/MM/yyyy + heure', () {
    PreventeListItem it(String d, String h) =>
        PreventeListItem(lgPREENREGISTREMENTID: 'x', heure: h, dtUPDATED: d, intPRICE: 0, strREF: '', userFullName: '', lgTYPEVENTEID: '1');
    expect(preventeDateLabel(it('03/09/2026', '09:41:12')), '03/09/2026 09:41');
    expect(preventeDateLabel(it('2026-09-03', '')), '03/09/2026');
    expect(preventeDateLabel(it('illisible', '10:00')), 'illisible 10:00');
  });
}
