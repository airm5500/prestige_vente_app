// Vente Carnet (nouvelle version) : parcours complet à 360 px, net automatique, double scan (1 seule vente),
// double tap Valider (1 seule clôture), panne / réponse perdue / refus, caisse fermée, net non à jour,
// panier non relu, quitter / reprendre, ayant droit (choisir / créer), création client relue, historique.
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
import 'package:prestige_vente_app/ventes/carnet/carnet_controller.dart';
import 'package:prestige_vente_app/ventes/carnet/carnet_history.dart';
import 'package:prestige_vente_app/ventes/carnet/vente_carnet_screen.dart';
import 'package:prestige_vente_app/ventes/core/pending_sale_store.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
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

final _tp = ClientTiersPayant(lgTIERSPAYANTID: 'TP1', tpFullName: 'CARNET MUGEF', taux: 80, numSecurity: 'M-001', compteTp: 'CT1', order: 1, principal: true);
final _client = ClientAssurance(
  lgCLIENTID: 'C1',
  fullName: 'KOUASSI Awa',
  strFIRSTNAME: 'KOUASSI',
  strLASTNAME: 'Awa',
  strNUMEROSECURITESOCIAL: 'M-001',
  tiersPayants: [_tp],
  ayantDroits: [],
);
AyantDroit _ad(String id, String nom, String prenom) => AyantDroit(
    lgAYANTSDROITSID: id, lgCLIENTID: 'C1', fullName: '$nom $prenom', strFIRSTNAME: nom, strLASTNAME: prenom, strNUMEROSECURITESOCIAL: 'M-001', strSEXE: '');

enum _Mode { ok, failed, lost, lostNotApplied, refused, caisse, bonUtilise }

class _Add {
  final String? venteId;
  final String ayantDroitId;
  final String typeVenteId;
  final String natureVenteId;
  final List<VenteTp> tps;
  _Add(this.venteId, this.ayantDroitId, this.typeVenteId, this.natureVenteId, this.tps);
}

class _FakeGateway implements VenteGateway {
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
  final Map<String, Map<String, dynamic>> fullSales = {};
  final List<_Add> adds = [];
  final List<String> clotureAyantDroits = [];
  final List<String> clotureReglements = [];
  final List<int?> clotureRecu = [];
  final List<List<VenteTp>> netTps = [];
  final List<({String first, String last, String numSecu})> createdClients = [];
  final List<({String first, String last, String numSecu})> createdAd = [];
  List<AyantDroit> serverAyantDroits = [_ad('C1', 'KOUASSI', 'Awa'), _ad('AD2', 'KOUASSI', 'Junior')];
  List<ClientAssurance> clientList = [_client];
  List<PreventeListItem> history = [];
  int creations = 0;
  int terminerCalls = 0;
  int clotureCalls = 0;
  bool searchFails = false;
  bool clientSearchFails = false;
  bool detailsFail = false;
  bool netFails = false;
  _Mode addMode = _Mode.ok;
  _Mode clotureMode = _Mode.ok;

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
  Future<VenteResult<List<ClientAssurance>>> searchClients(String query, {required String typeClientId}) async {
    await _wait();
    expect(typeClientId, '2');
    if (clientSearchFails) return const VenteFailed('Serveur injoignable (rechercher le client).');
    final q = query.toLowerCase();
    return VenteOk(clientList.where((c) => c.fullName.toLowerCase().contains(q)).toList());
  }

  @override
  Future<VenteResult<List<TiersPayantAssurance>>> searchTiersPayants(String query, {required bool carnet}) async {
    await _wait();
    expect(carnet, isTrue);
    return VenteOk([TiersPayantAssurance(lgTIERSPAYANTID: 'TP9', strFULLNAME: 'CARNET SODECI', strNAME: 'SODECI')]);
  }

  @override
  Future<VenteResult<ClientAssurance>> createClientCarnet(
      {required String firstName, required String lastName, required String numSecu, required String tiersPayantId}) async {
    createdClients.add((first: firstName, last: lastName, numSecu: numSecu));
    await _wait();
    return VenteOk(ClientAssurance(
      lgCLIENTID: 'C2',
      fullName: '$firstName $lastName',
      strFIRSTNAME: firstName,
      strLASTNAME: lastName,
      strNUMEROSECURITESOCIAL: numSecu,
      tiersPayants: [
        ClientTiersPayant(
            lgTIERSPAYANTID: tiersPayantId, tpFullName: 'CARNET SODECI', taux: 100, numSecurity: numSecu, compteTp: 'CT9', order: 1, principal: true)
      ],
      ayantDroits: [],
    ));
  }

  @override
  Future<VenteResult<List<AyantDroit>>> ayantDroits(String clientId) async {
    await _wait();
    return VenteOk(List.of(serverAyantDroits));
  }

  @override
  Future<VenteResult<AyantDroit>> createAyantDroit(
      {required String clientId, required String firstName, required String lastName, required String numSecu}) async {
    createdAd.add((first: firstName, last: lastName, numSecu: numSecu));
    await _wait();
    final ad = AyantDroit(
        lgAYANTSDROITSID: 'AD${serverAyantDroits.length + 1}',
        lgCLIENTID: clientId,
        fullName: '$firstName $lastName',
        strFIRSTNAME: firstName,
        strLASTNAME: lastName,
        strNUMEROSECURITESOCIAL: numSecu,
        strSEXE: '');
    serverAyantDroits = [...serverAyantDroits, ad];
    return VenteOk(ad);
  }

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
  }) async {
    adds.add(_Add(venteId, ayantDroitId, typeVenteId, natureVenteId, tierspayants));
    await _wait();
    final mode = addMode;
    if (mode == _Mode.failed) return const VenteFailed('Serveur injoignable (ajouter le produit).');
    if (mode == _Mode.refused) return const VenteRefused('Plafond du carnet atteint');
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
  Future<VenteResult<AssuranceSaleSummary>> netAssurance({required String venteId, required List<VenteTp> tierspayants}) async {
    netTps.add(tierspayants);
    await _wait();
    if (netFails) return const VenteFailed('Serveur injoignable (calculer le net).');
    final total = (sales[venteId] ?? const []).fold<int>(0, (s, i) => s + i.intPRICE);
    final tp = tierspayants.isEmpty ? 0 : total * tierspayants.first.taux ~/ 100;
    return VenteOk(AssuranceSaleSummary(
      montant: total,
      montantTp: tp,
      montantNet: total - tp,
      tierspayants: [for (final t in tierspayants) TiersPayantSummary(numBon: t.numBon, taux: t.taux, compteTp: t.compteTp, tpnet: tp)],
    ));
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
    statut[venteId] = 'is_Process';
    return const VenteOk(null);
  }

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
  }) async {
    clotureCalls++;
    clotureAyantDroits.add(ayantDroitId);
    clotureReglements.add(typeReglementId);
    clotureRecu.add(montantRecu);
    expect(typeVenteId, '3');
    await _wait();
    if (statut[venteId] == 'is_Closed') return const VenteRefused('Cette vente a déjà été clôturée');
    switch (clotureMode) {
      case _Mode.caisse:
        return const VenteRefused('Désolé votre caisse est fermée. Veuillez l\'ouvrir avant de proceder à validation');
      case _Mode.bonUtilise:
        return const VenteRefused('Le numéro de bon <b>B-123</b> est déjà utilisé');
      case _Mode.lost:
        statut[venteId] = 'is_Closed';
        return const VenteFailed('Le serveur met trop de temps à répondre.', maybeApplied: true);
      default:
        statut[venteId] = 'is_Closed';
        return const VenteOk({'success': true});
    }
  }

  @override
  Future<VenteResult<Map<String, dynamic>>> fullSale(String venteId) async {
    await _wait();
    final f = fullSales[venteId];
    final s = statut[venteId];
    if (f == null && s == null) return const VenteFailed('Vente introuvable ou réponse illisible.');
    return VenteOk({...?f, if (s != null) 'strSTATUT': s});
  }

  @override
  Future<VenteResult<List<PreventeListItem>>> ventesByType(String typeVenteId) async {
    await _wait();
    expect(typeVenteId, '3');
    return VenteOk(history);
  }

  // --- Non utilisés par ce menu ---
  @override
  Future<VenteResult<String>> addItemVno({required String produitId, required int qte, required int itemPu, String? venteId, required bool prevente}) =>
      throw UnimplementedError();
  @override
  Future<VenteResult<SaleSummary>> netVno(String venteId) => throw UnimplementedError();
  @override
  Future<VenteResult<void>> updateClient(String venteId, String clientId) => throw UnimplementedError();
  @override
  Future<VenteResult<Map<String, dynamic>>> cloturerVno({
    required String venteId,
    required SaleSummary summary,
    required String typeReglementId,
    required String clientId,
    required String userVendeurId,
    int? montantRecu,
    int? montantRemis,
  }) =>
      throw UnimplementedError();
  @override
  Future<VenteResult<List<PaymentMethod>>> paymentMethods() => throw UnimplementedError();
  @override
  Future<VenteResult<List<PaymentMethodQr>>> paymentMethodsWithQr() => throw UnimplementedError();
  @override
  Future<VenteResult<List<PreventeListItem>>> preventes() => throw UnimplementedError();
  @override
  Future<VenteResult<ClientAssurance>> createClientAssurance(
          {required String firstName, required String lastName, required String numSecu, required String tiersPayantId, required int pourcentage}) =>
      throw UnimplementedError();
  @override
  Future<VenteResult<ClientAssurance>> addTiersPayantToClient({required ClientAssurance client, required Map<String, dynamic> newTiersPayantPayload}) =>
      throw UnimplementedError();
  @override
  Future<VenteResult<ClientAssurance>> updateClientAssurance({required ClientAssurance client, required List<Map<String, dynamic>> tiersPayantsPayload}) =>
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

Future<void> _open(WidgetTester tester, _FakeGateway gw, {bool pumpApp = true}) async {
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
                onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => VenteCarnetScreen(gateway: gw))),
                child: const Text('Ouvrir'),
              ),
            ),
          ),
        ),
      ),
    ));
  }
  await tester.tap(find.text('Ouvrir'));
  await tester.pumpAndSettle();
}

Finder get _clientField => find.byKey(const ValueKey('carnet-client-recherche'));
Finder get _field => find.byKey(const ValueKey('vente-recherche'));
Finder get _valider => find.byKey(const ValueKey('carnet-valider'));
Finder get _prevente => find.byKey(const ValueKey('carnet-prevente'));
Finder get _bonField => find.byKey(const ValueKey('carnet-bon-CT1'));
String _net(int v) => 'Part client (net) : ${Constants.formatNumber(v)}';

bool _enabled(WidgetTester tester, Finder f) => (tester.widget(f) as ButtonStyleButton).onPressed != null;

/// Client → bon → étape produits.
Future<void> _toProducts(WidgetTester tester, {String bon = 'B-123'}) async {
  await tester.enterText(_clientField, 'kouassi');
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
  await tester.tap(find.text('KOUASSI Awa'));
  await tester.pumpAndSettle();
  await tester.enterText(_bonField, bon);
  await tester.tap(find.byKey(const ValueKey('carnet-continuer')));
  await tester.pumpAndSettle();
}

Future<void> _addManual(WidgetTester tester, String query, {String qty = '1'}) async {
  await tester.enterText(_field, query);
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
  await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField)), qty);
  await tester.tap(find.text('Ajouter'));
  await tester.pumpAndSettle();
}

Future<void> _scan(WidgetTester tester, String code) async {
  await tester.enterText(_field, code);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pump();
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('parcours complet : client, bon obligatoire, net automatique, validation (1 clôture, espèces)', (tester) async {
    _phone(tester);
    final gw = _FakeGateway();
    await _open(tester, gw);

    await tester.enterText(_clientField, 'kouassi');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('KOUASSI Awa'));
    await tester.pumpAndSettle();

    // Ayant droit = le client lui-même par défaut.
    expect(find.text('Le client lui-même'), findsOneWidget);
    // Bon obligatoire.
    await tester.enterText(_bonField, '   ');
    await tester.tap(find.byKey(const ValueKey('carnet-continuer')));
    await tester.pumpAndSettle();
    expect(find.text('Le N° de bon pour CARNET MUGEF est requis.'), findsOneWidget);
    await tester.enterText(_bonField, '  B-123 ');
    await tester.tap(find.byKey(const ValueKey('carnet-continuer')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Calculer'), findsNothing);
    await _addManual(tester, 'doli', qty: '2');
    expect(find.text('DOLIPRANE 1000MG CP B/8'), findsOneWidget);
    expect(find.text(_net(600)), findsOneWidget); // 3 000 - 80 %
    expect(gw.adds.single.typeVenteId, '3');
    expect(gw.adds.single.natureVenteId, '1');
    expect(gw.adds.single.ayantDroitId, 'C1');
    expect(gw.adds.single.tps.single, (compteTp: 'CT1', numBon: 'B-123', taux: 80));
    expect((await PendingSaleStore.load(VenteMenu.carnet))?.venteId, 'V1');

    // Modifier : 0 refusé, 3 accepté → net recalculé automatiquement.
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
    expect(find.text(_net(900)), findsOneWidget);

    await tester.tap(_valider);
    await tester.pumpAndSettle();
    expect(find.text('Vente carnet validée'), findsOneWidget);
    await tester.tap(find.text('Non'));
    await tester.pumpAndSettle();
    expect(gw.clotureCalls, 1);
    expect(gw.clotureReglements, ['1']);
    expect(gw.clotureRecu, [null]); // montant reçu = net (comme l'original)
    expect(gw.clotureAyantDroits, ['C1']);
    expect(_clientField, findsOneWidget); // retour à la recherche client
    expect(await PendingSaleStore.load(VenteMenu.carnet), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('« Enregistrer en prévente » : terminerprevente, aucune clôture', (tester) async {
    _phone(tester);
    final gw = _FakeGateway();
    await _open(tester, gw);
    await _toProducts(tester);
    await _addManual(tester, 'doli');
    await tester.tap(_prevente);
    await tester.pumpAndSettle();
    expect(find.text('Prévente carnet enregistrée'), findsOneWidget);
    await tester.tap(find.text('Non'));
    await tester.pumpAndSettle();
    expect(gw.terminerCalls, 1);
    expect(gw.clotureCalls, 0);
    expect(await PendingSaleStore.load(VenteMenu.carnet), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('double scan rapide du 1ᵉʳ produit : une seule vente créée, « ajouté » après le serveur', (tester) async {
    _phone(tester);
    SharedPreferences.setMockInitialValues({'isQuickScanMode': true});
    final gw = _FakeGateway()..delay = const Duration(milliseconds: 200);
    await _open(tester, gw);
    await _toProducts(tester);
    await _scan(tester, _doli.intCIP);
    await _scan(tester, _doli.intCIP);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.textContaining('ajouté (+1)'), findsNothing);
    await tester.pumpAndSettle();
    expect(gw.creations, 1);
    expect(gw.adds.map((a) => a.venteId).toList(), [null, 'V1']);
    expect(gw.sales['V1']!.length, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('double tap sur Valider : une seule clôture', (tester) async {
    _phone(tester);
    final gw = _FakeGateway()..delay = const Duration(milliseconds: 100);
    await _open(tester, gw);
    await _toProducts(tester);
    await _addManual(tester, 'doli');
    await tester.tap(_valider);
    await tester.tap(_valider, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Non'));
    await tester.pumpAndSettle();
    expect(gw.clotureCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('panne pendant l\'ajout : pas de « ajouté », message de panne', (tester) async {
    _phone(tester);
    SharedPreferences.setMockInitialValues({'isQuickScanMode': true});
    final gw = _FakeGateway()..addMode = _Mode.failed;
    await _open(tester, gw);
    await _toProducts(tester);
    await _scan(tester, _doli.intCIP);
    await tester.pumpAndSettle();
    expect(find.textContaining('ajouté'), findsNothing);
    expect(find.textContaining('injoignable'), findsOneWidget);
    expect(find.text('Le panier est vide'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('réponse perdue à l\'ajout : panier relu, pas de doublon', (tester) async {
    _phone(tester);
    final gw = _FakeGateway();
    await _open(tester, gw);
    await _toProducts(tester);
    await _addManual(tester, 'doli');
    gw.addMode = _Mode.lost;
    await _addManual(tester, 'effer');
    expect(gw.adds.length, 2);
    expect(gw.sales['V1']!.length, 2);
    expect(find.text('EFFERALGAN 500MG'), findsOneWidget);
    expect(find.text(_net(540)), findsOneWidget); // 2 700 - 80 %

    gw.addMode = _Mode.lostNotApplied;
    await _addManual(tester, 'effer');
    expect(gw.sales['V1']!.length, 2);
    expect(find.textContaining('Produit non ajouté'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refus du serveur : SON message est affiché', (tester) async {
    _phone(tester);
    final gw = _FakeGateway()..addMode = _Mode.refused;
    await _open(tester, gw);
    await _toProducts(tester);
    await _addManual(tester, 'doli');
    expect(find.text('Plafond du carnet atteint'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('caisse fermée à la validation : proposition d\'ouvrir la caisse, vente non terminée', (tester) async {
    _phone(tester);
    final gw = _FakeGateway()..clotureMode = _Mode.caisse;
    await _open(tester, gw);
    await _toProducts(tester);
    await _addManual(tester, 'doli');
    await tester.tap(_valider);
    await tester.pumpAndSettle();
    expect(find.text('Caisse Fermée'), findsOneWidget);
    await tester.tap(find.text('Non'));
    await tester.pumpAndSettle();
    expect(find.text('DOLIPRANE 1000MG CP B/8'), findsOneWidget);
    expect(_enabled(tester, _valider), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bon déjà utilisé à la validation : message du serveur, retour à l\'étape des bons', (tester) async {
    _phone(tester);
    final gw = _FakeGateway()..clotureMode = _Mode.bonUtilise;
    await _open(tester, gw);
    await _toProducts(tester);
    await _addManual(tester, 'doli');
    await tester.tap(_valider);
    await tester.pumpAndSettle();
    expect(find.text('Le numéro de bon B-123 est déjà utilisé'), findsOneWidget);
    expect(_bonField, findsOneWidget);

    gw.clotureMode = _Mode.ok;
    await tester.pump(const Duration(seconds: 5)); // fin du bandeau d'erreur
    await tester.pumpAndSettle();
    await tester.enterText(_bonField, 'B-124');
    await tester.tap(find.byKey(const ValueKey('carnet-continuer')));
    await tester.pumpAndSettle();
    expect(gw.netTps.last.single.numBon, 'B-124'); // net recalculé avec le nouveau bon
    await tester.tap(_valider);
    await tester.pumpAndSettle();
    expect(find.text('Vente carnet validée'), findsOneWidget);
    expect(gw.clotureCalls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('net non à jour : validation bloquée jusqu\'au recalcul', (tester) async {
    _phone(tester);
    final gw = _FakeGateway();
    await _open(tester, gw);
    await _toProducts(tester);
    await _addManual(tester, 'doli');
    gw.netFails = true;
    await _addManual(tester, 'effer');
    expect(find.textContaining('Net à payer non calculé'), findsWidgets);
    expect(_enabled(tester, _valider), isFalse);
    expect(_enabled(tester, _prevente), isFalse);
    expect(find.text('Part client (net) : —'), findsOneWidget);

    gw.netFails = false;
    await tester.tap(find.text('Réessayer').first);
    await tester.pumpAndSettle();
    expect(_enabled(tester, _valider), isTrue);
    expect(find.text(_net(540)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('panier non relu : ancien panier gardé + bandeau, validation bloquée', (tester) async {
    _phone(tester);
    final gw = _FakeGateway();
    await _open(tester, gw);
    await _toProducts(tester);
    await _addManual(tester, 'doli');
    gw.detailsFail = true;
    await _addManual(tester, 'effer');
    expect(find.text('DOLIPRANE 1000MG CP B/8'), findsOneWidget);
    expect(find.text('Le panier est vide'), findsNothing);
    expect(find.textContaining('Panier non relu'), findsWidgets);
    expect(_enabled(tester, _valider), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('suppression d\'une ligne avec confirmation', (tester) async {
    _phone(tester);
    final gw = _FakeGateway();
    await _open(tester, gw);
    await _toProducts(tester);
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
    expect(tester.takeException(), isNull);
  });

  testWidgets('quitter en pleine vente : confirmation, vente mémorisée puis « Reprendre la vente ? »', (tester) async {
    _phone(tester);
    final gw = _FakeGateway();
    await _open(tester, gw);
    await _toProducts(tester);
    await _addManual(tester, 'doli');

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Quitter la vente en cours ?'), findsOneWidget);
    await tester.tap(find.text('Rester'));
    await tester.pumpAndSettle();
    expect(find.text('DOLIPRANE 1000MG CP B/8'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quitter'));
    await tester.pumpAndSettle();
    expect(find.text('Ouvrir'), findsOneWidget);

    await _open(tester, gw, pumpApp: false);
    expect(find.text('Reprendre la vente ?'), findsOneWidget);
    expect(find.textContaining('REF-V1'), findsOneWidget);
    await tester.tap(find.text('Reprendre'));
    await tester.pumpAndSettle();
    expect(find.text('DOLIPRANE 1000MG CP B/8'), findsOneWidget);
    await _addManual(tester, 'effer');
    expect(gw.creations, 1);
    expect(gw.adds.last.venteId, 'V1');
    expect(gw.adds.last.tps.single.numBon, 'B-123');
    expect(gw.adds.last.ayantDroitId, 'C1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('ayant droit : en choisir un autre, en créer un (nom puis prénom dans le bon ordre)', (tester) async {
    _phone(tester);
    final gw = _FakeGateway();
    await _open(tester, gw);
    await tester.enterText(_clientField, 'kouassi');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('KOUASSI Awa'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Changer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('KOUASSI Junior'));
    await tester.pumpAndSettle();
    expect(find.text('KOUASSI Junior'), findsOneWidget);

    await tester.tap(find.text('Nouvel ayant droit'));
    await tester.pumpAndSettle();
    final f = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField));
    expect(tester.widget<TextFormField>(f.at(2)).controller?.text, 'M-001'); // matricule du client proposé
    await tester.tap(find.text('Créer'));
    await tester.pumpAndSettle();
    expect(find.text('Requis'), findsOneWidget); // nom obligatoire
    await tester.enterText(f.at(0), 'KOUASSI');
    await tester.enterText(f.at(1), 'Ange');
    await tester.tap(find.text('Créer'));
    await tester.pumpAndSettle();
    expect(gw.createdAd.single, (first: 'KOUASSI', last: 'Ange', numSecu: 'M-001'));
    expect(find.text('KOUASSI Ange'), findsOneWidget);

    await tester.enterText(_bonField, 'B-1');
    await tester.tap(find.byKey(const ValueKey('carnet-continuer')));
    await tester.pumpAndSettle();
    await _addManual(tester, 'doli');
    expect(gw.adds.single.ayantDroitId, 'AD3');
    await tester.tap(_valider);
    await tester.pumpAndSettle();
    expect(gw.clotureAyantDroits, ['AD3']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('client introuvable → création : carnet affiché pour relecture, création par « Créer le client »', (tester) async {
    _phone(tester);
    final gw = _FakeGateway();
    await _open(tester, gw);
    await tester.enterText(_clientField, 'DIABATE');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.textContaining('Aucun client carnet'), findsOneWidget);
    await tester.tap(find.text('Créer un nouveau client carnet'));
    await tester.pumpAndSettle();

    final f = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField));
    expect(tester.widget<TextFormField>(f.at(0)).controller?.text, 'DIABATE');
    await tester.enterText(f.at(1), 'Moussa');
    await tester.enterText(f.at(2), 'M-777');
    await tester.enterText(find.byKey(const ValueKey('carnet-recherche')), 'sod');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CARNET SODECI'));
    await tester.pumpAndSettle();
    // Choisir le carnet ne crée pas le client : il est affiché pour relecture.
    expect(find.byKey(const ValueKey('carnet-choisi')), findsOneWidget);
    expect(gw.createdClients, isEmpty);
    await tester.tap(find.text('Créer le client'));
    await tester.pumpAndSettle();
    expect(gw.createdClients.single, (first: 'DIABATE', last: 'Moussa', numSecu: 'M-777'));
    expect(find.byKey(const ValueKey('carnet-bon-CT9')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recherche client en panne : « Réessayer », jamais « introuvable » ni « Créer »', (tester) async {
    _phone(tester);
    final gw = _FakeGateway()..clientSearchFails = true;
    await _open(tester, gw);
    await tester.enterText(_clientField, 'kouassi');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.textContaining('Recherche impossible'), findsOneWidget);
    expect(find.text('Créer un nouveau client carnet'), findsNothing);
    expect(find.textContaining('Aucun client'), findsNothing);
    gw.clientSearchFails = false;
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.text('KOUASSI Awa'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('historique : « Reprendre la prévente » recharge client, bons et panier ; vente clôturée refusée', (tester) async {
    _phone(tester);
    final gw = _FakeGateway();
    gw.sales['V7'] = [gw._line('V7', _effer, 2, 1200)];
    gw.statut['V7'] = 'is_Process';
    gw.statut['V8'] = 'is_Closed';
    gw.fullSales['V7'] = {
      'strREF': 'REF-V7',
      'lgPREENREGISTREMENTID': 'V7',
      'intPRICE': 2400,
      'client': {
        'lgCLIENTID': 'C1',
        'strFIRSTNAME': 'KOUASSI',
        'strLASTNAME': 'Awa',
        'strNUMEROSECURITESOCIAL': 'M-001',
        'tiersPayants': [
          {'lgTIERSPAYANTID': 'TP1', 'tpFullName': 'CARNET MUGEF', 'taux': '80', 'numSecurity': 'M-001', 'compteTp': 'CT1', 'order': 1, 'principal': true}
        ],
      },
      'ayantDroit': {'lgAYANTSDROITSID': 'AD2', 'strFIRSTNAME': 'KOUASSI', 'strLASTNAME': 'Junior'},
      'tierspayants': [
        {'compteTp': 'CT1', 'numBon': 'B-77', 'taux': 80, 'tpnet': 1920}
      ],
    };
    gw.history = [
      PreventeListItem(
          lgPREENREGISTREMENTID: 'V8', heure: '10:00:00', dtUPDATED: '05/09/2026', intPRICE: 900, strREF: 'REF-V8', userFullName: 'Koffi', lgTYPEVENTEID: '3'),
      PreventeListItem(
          lgPREENREGISTREMENTID: 'V7', heure: '09:41:12', dtUPDATED: '03/09/2026', intPRICE: 2400, strREF: 'REF-V7', userFullName: 'Awa', lgTYPEVENTEID: '3'),
    ];
    await _open(tester, gw);
    await tester.tap(find.byKey(const ValueKey('carnet-historique')));
    await tester.pumpAndSettle();
    expect(find.textContaining('03/09/2026 09:41'), findsOneWidget);
    expect(find.text('Réimprimer'), findsNWidgets(2));

    await tester.tap(find.text('Reprendre la prévente').first); // V8 : clôturée
    await tester.pumpAndSettle();
    expect(find.textContaining('déjà clôturée'), findsOneWidget);
    expect(_clientField, findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('carnet-historique')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reprendre la prévente').last);
    await tester.pumpAndSettle();
    expect(find.text('EFFERALGAN 500MG'), findsOneWidget);
    expect(find.text(_net(480)), findsOneWidget);
    expect(gw.netTps.last.single.numBon, 'B-77');

    await _addManual(tester, 'doli');
    expect(gw.adds.single.venteId, 'V7');
    expect(gw.adds.single.ayantDroitId, 'AD2');
    expect(gw.creations, 0);
    expect(tester.takeException(), isNull);
  });

  test('réimpression : vraie référence transmise au ticket', () {
    final item =
        PreventeListItem(lgPREENREGISTREMENTID: 'V7', heure: '', dtUPDATED: '', intPRICE: 2400, strREF: 'REF-LISTE', userFullName: '', lgTYPEVENTEID: '3');
    final t = buildCarnetReprint(item, {
      'strREF': 'REF-V7',
      'intPRICE': '2400',
      'client': {'lgCLIENTID': 'C1', 'strFIRSTNAME': 'KOUASSI', 'strLASTNAME': 'Awa'},
      'tierspayants': [
        {'compteTp': 'CT1', 'numBon': 'B-77', 'taux': '80', 'tpnet': '1920'}
      ],
    });
    expect(t, isNotNull);
    expect(t!.summary.reference, 'REF-V7');
    expect(t.items.first.strREF, 'REF-V7'); // le ticket lit la référence sur la 1ʳᵉ ligne
    expect(t.summary.montantNet, 480);
    expect(t.ayantDroit.lgAYANTSDROITSID, 'C1');
    expect(buildCarnetReprint(item, {})!.items.first.strREF, 'REF-LISTE');
  });

  test('contrôleur : deux validations simultanées → une seule clôture ; réponse perdue → relecture', () async {
    SharedPreferences.setMockInitialValues({});
    Future<CarnetController> ready(_FakeGateway gw) async {
      final c = CarnetController(gateway: gw, userId: 'U1');
      c.selectClient(_client);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.validateBons({'CT1': 'B-1'}), isNull);
      expect((await c.addProduct(_doli, 1)).isOk, isTrue);
      return c;
    }

    final gw = _FakeGateway()..delay = const Duration(milliseconds: 5);
    final c = await ready(gw);
    final r = await Future.wait([c.valider(expectedChanges: c.changes), c.valider(expectedChanges: c.changes)]);
    expect(r.every((x) => x.isOk), isTrue);
    expect(gw.clotureCalls, 1);

    final gw2 = _FakeGateway()
      ..delay = const Duration(milliseconds: 5)
      ..clotureMode = _Mode.lost;
    final c2 = await ready(gw2);
    expect((await c2.valider(expectedChanges: c2.changes)).isOk, isTrue);
    expect(gw2.clotureCalls, 1);

    final gw3 = _FakeGateway()..delay = const Duration(milliseconds: 5);
    final c3 = await ready(gw3);
    final before = c3.changes;
    await c3.addProduct(_effer, 1);
    expect((await c3.valider(expectedChanges: before)).isOk, isFalse);
    expect(gw3.clotureCalls, 0);

    // Doublon de bons refusé.
    final c4 = CarnetController(gateway: _FakeGateway(), userId: 'U1');
    c4.selectClient(ClientAssurance(
      lgCLIENTID: 'C5',
      fullName: 'X',
      strFIRSTNAME: 'X',
      strLASTNAME: '',
      strNUMEROSECURITESOCIAL: '',
      tiersPayants: [
        _tp,
        ClientTiersPayant(lgTIERSPAYANTID: 'TP2', tpFullName: 'CARNET 2', taux: 20, numSecurity: '', compteTp: 'CT2', order: 2, principal: false)
      ],
      ayantDroits: [],
    ));
    expect(c4.validateBons({'CT1': 'B-1', 'CT2': 'b-1'})?.message, contains('deux fois'));
    await Future<void>.delayed(const Duration(milliseconds: 120));
  });
}
