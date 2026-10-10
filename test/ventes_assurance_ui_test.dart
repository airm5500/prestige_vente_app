// Pré-vente Assurance (étape 3, présentation) : étapes Client → Couverture → Produits → Encaisser en
// A / B / C à 360 px, carte client permanente, « CONTINUER » désactivé avec la raison exacte, répartition
// toujours visible (« Calcul… »), page d'encaissement (part client > 0), validation 0 F (confirmation
// simple), double tap = 1 clôture, retour par la barre d'étapes, menu « Présentation » transmis.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/assurance_sale_summary.dart';
import 'package:prestige_vente_app/api/models/ayant_droit.dart';
import 'package:prestige_vente_app/api/models/client_assurance.dart';
import 'package:prestige_vente_app/api/models/officine.dart';
import 'package:prestige_vente_app/api/models/payment_method_qr.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/api/models/tiers_payant_assurance.dart';
import 'package:prestige_vente_app/api/models/user.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/assurance/vente_assurance_screen.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/ventes/prevente/encaissement_page.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
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
final _effer = _p('P2', 'EFFERALGAN 500MG', '3400930000002', price: 1000);

ClientTiersPayant _ctp(String id, String name, String compte, int taux, int order) =>
    ClientTiersPayant(lgTIERSPAYANTID: id, tpFullName: name, taux: taux, numSecurity: 'MAT-$compte', compteTp: compte, order: order, principal: order == 1);

AyantDroit _ad(String id, String first, String last) =>
    AyantDroit(lgAYANTSDROITSID: id, lgCLIENTID: 'C1', fullName: '$first $last', strFIRSTNAME: first, strLASTNAME: last, strNUMEROSECURITESOCIAL: 'M-$id', strSEXE: '');

ClientAssurance _client({List<AyantDroit>? ads, List<ClientTiersPayant>? tps}) => ClientAssurance(
      lgCLIENTID: 'C1',
      fullName: 'KOUASSI Awa',
      strFIRSTNAME: 'KOUASSI',
      strLASTNAME: 'Awa',
      strNUMEROSECURITESOCIAL: 'MAT1',
      tiersPayants: tps ?? [_ctp('TP1', 'MCI', 'CT1', 70, 1), _ctp('TP2', 'ASCOMA', 'CT2', 10, 2)],
      ayantDroits: ads ?? [_ad('C1', 'KOUASSI', 'Awa'), _ad('AD2', 'KOUASSI', 'Junior')],
    );

enum _Mode { ok, failed, lost, lostNotApplied, refused, caisse, bonUtilise }

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

  Duration delay = const Duration(milliseconds: 40);
  final List<ProductSearchResult> catalog = [_doli, _effer];
  List<ClientAssurance> clients = [_client()];
  List<AyantDroit> serverAyantDroits = [];
  final Map<String, List<SaleItemDetail>> sales = {};
  final Map<String, String> statut = {};
  final Map<String, ({String clientId, String adId, List<VenteTp> tps})> saleInfo = {};
  final List<String?> addVenteIds = [];
  final List<List<VenteTp>> netTps = [];
  final List<({String typeReglementId, List<VenteTp> tps, int net})> clotures = [];
  final List<({String first, String last})> createdClients = [];
  final List<({String first, String last})> createdAds = [];
  int updateClientCalls = 0;
  int creations = 0;
  int terminerCalls = 0;
  bool searchFails = false;
  bool clientSearchFails = false;
  bool detailsFail = false;
  bool netFails = false;
  _Mode addMode = _Mode.ok;
  _Mode clotureMode = _Mode.ok;
  List<PreventeListItem> history = [];

  Future<void> _wait() => Future.delayed(delay);

  SaleItemDetail _line(String venteId, ProductSearchResult p, int qty, int pu) => SaleItemDetail(
        lgPREENREGISTREMENTDETAILID: '$venteId-L${(sales[venteId]?.length ?? 0) + 1}',
        lgFAMILLEID: p.lgFAMILLEID,
        strNAME: p.strNAME,
        intCIP: p.intCIP,
        intQUANTITY: qty,
        intPRICEUNITAIR: pu,
        intPRICE: qty * pu,
        strREF: 'AS-$venteId',
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
    if (clientSearchFails) return const VenteFailed('Serveur injoignable (rechercher le client).');
    final q = query.toLowerCase();
    return VenteOk(clients.where((c) => c.fullName.toLowerCase().contains(q)).toList());
  }

  @override
  Future<VenteResult<List<TiersPayantAssurance>>> searchTiersPayants(String query, {required bool carnet}) async {
    await _wait();
    return VenteOk([
      TiersPayantAssurance(lgTIERSPAYANTID: 'TP9', strFULLNAME: 'SAHAM ASSURANCE', strNAME: 'SAHAM'),
      TiersPayantAssurance(lgTIERSPAYANTID: 'TP2', strFULLNAME: 'ASCOMA', strNAME: 'ASCOMA'),
    ].where((t) => t.strFULLNAME.toLowerCase().contains(query.toLowerCase())).toList());
  }

  @override
  Future<VenteResult<List<AyantDroit>>> ayantDroits(String clientId) async {
    await _wait();
    return VenteOk(List.of(serverAyantDroits));
  }

  @override
  Future<VenteResult<AyantDroit>> createAyantDroit({required String clientId, required String firstName, required String lastName, required String numSecu}) async {
    createdAds.add((first: firstName, last: lastName));
    await _wait();
    final ad = AyantDroit(
        lgAYANTSDROITSID: 'AD${createdAds.length + 10}',
        lgCLIENTID: clientId,
        fullName: '$firstName $lastName',
        strFIRSTNAME: firstName,
        strLASTNAME: lastName,
        strNUMEROSECURITESOCIAL: numSecu,
        strSEXE: '');
    serverAyantDroits.add(ad);
    return VenteOk(ad);
  }

  @override
  Future<VenteResult<ClientAssurance>> createClientAssurance(
      {required String firstName, required String lastName, required String numSecu, required String tiersPayantId, required int pourcentage}) async {
    createdClients.add((first: firstName, last: lastName));
    await _wait();
    return VenteOk(ClientAssurance(
      lgCLIENTID: 'C2',
      fullName: '$firstName $lastName',
      strFIRSTNAME: firstName,
      strLASTNAME: lastName,
      strNUMEROSECURITESOCIAL: numSecu,
      tiersPayants: [_ctp(tiersPayantId, 'SAHAM ASSURANCE', 'CT9', pourcentage, 1)],
      ayantDroits: [
        AyantDroit(
            lgAYANTSDROITSID: 'C2',
            lgCLIENTID: 'C2',
            fullName: '$firstName $lastName',
            strFIRSTNAME: firstName,
            strLASTNAME: lastName,
            strNUMEROSECURITESOCIAL: numSecu,
            strSEXE: '')
      ],
    ));
  }

  @override
  Future<VenteResult<ClientAssurance>> updateClientAssurance({required ClientAssurance client, required List<Map<String, dynamic>> tiersPayantsPayload}) async {
    updateClientCalls++;
    await _wait();
    return VenteOk(client);
  }

  @override
  Future<VenteResult<ClientAssurance>> addTiersPayantToClient({required ClientAssurance client, required Map<String, dynamic> newTiersPayantPayload}) async {
    updateClientCalls++;
    await _wait();
    return VenteOk(client);
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
    addVenteIds.add(venteId);
    await _wait();
    final mode = addMode;
    if (mode == _Mode.failed) return const VenteFailed('Serveur injoignable (ajouter le produit).');
    if (mode == _Mode.refused) return const VenteRefused('<b>Plafond</b> atteint pour ce tiers payant');
    if (mode == _Mode.caisse) return const VenteRefused('Désolé votre caisse est fermée');
    if (mode == _Mode.lostNotApplied) return const VenteFailed('Le serveur met trop de temps à répondre.', maybeApplied: true);
    var id = venteId;
    if (id == null) {
      creations++;
      id = 'V$creations';
      sales[id] = [];
      statut[id] = 'pending';
      saleInfo[id] = (clientId: clientId, adId: ayantDroitId, tps: tierspayants);
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
    final parts = [
      for (final tp in tierspayants) TiersPayantSummary(numBon: tp.numBon, taux: tp.taux, compteTp: tp.compteTp, tpnet: total * tp.taux ~/ 100),
    ];
    final tp = parts.fold<int>(0, (s, t) => s + t.tpnet).clamp(0, total);
    return VenteOk(AssuranceSaleSummary(montant: total, montantTp: tp, montantNet: total - tp, tierspayants: parts));
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
            strREF: l.strREF);
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
    clotures.add((typeReglementId: typeReglementId, tps: tierspayants, net: summary.montantNet));
    await _wait();
    if (statut[venteId] == 'is_Closed') return const VenteRefused('Cette vente a déjà été clôturée');
    switch (clotureMode) {
      case _Mode.caisse:
        return const VenteRefused('Désolé votre caisse est fermée. Veuillez l\'ouvrir avant de proceder à validation');
      case _Mode.bonUtilise:
        return const VenteRefused('Le numéro de bon <b>B-1</b> est déjà utilisé');
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
    return VenteOk([PaymentMethod(id: '1', name: 'Espèces'), PaymentMethod(id: '10', name: 'WAVE')]);
  }

  @override
  Future<VenteResult<List<PaymentMethodQr>>> paymentMethodsWithQr() async => const VenteOk([]);

  @override
  Future<VenteResult<List<PreventeListItem>>> ventesByType(String typeVenteId) async {
    await _wait();
    return VenteOk(history.where((h) => h.lgTYPEVENTEID == typeVenteId).toList());
  }

  /// /ventestats/{id} : client, ayant droit, TP et bons de la vente.
  @override
  Future<VenteResult<Map<String, dynamic>>> fullSale(String venteId) async {
    await _wait();
    final s = statut[venteId];
    if (s == null) return const VenteFailed('Vente introuvable ou réponse illisible.');
    final info = saleInfo[venteId];
    final c = clients.first;
    final ad = c.ayantDroits.where((a) => a.lgAYANTSDROITSID == info?.adId).firstOrNull;
    final total = (sales[venteId] ?? const []).fold<int>(0, (s, i) => s + i.intPRICE);
    return VenteOk({
      'strSTATUT': s,
      'strREF': 'AS-$venteId',
      'lgPREENREGISTREMENTID': venteId,
      'intPRICE': '$total',
      'client': {
        'lgCLIENTID': c.lgCLIENTID,
        'strFIRSTNAME': c.strFIRSTNAME,
        'strLASTNAME': c.strLASTNAME,
        'strNUMEROSECURITESOCIAL': c.strNUMEROSECURITESOCIAL,
        'tiersPayants': [
          for (final tp in c.tiersPayants)
            {'lgTIERSPAYANTID': tp.lgTIERSPAYANTID, 'tpFullName': tp.tpFullName, 'taux': '${tp.taux}', 'numSecurity': tp.numSecurity, 'compteTp': tp.compteTp, 'order': tp.order}
        ],
      },
      if (ad != null)
        'ayantDroit': {'lgAYANTSDROITSID': ad.lgAYANTSDROITSID, 'strFIRSTNAME': ad.strFIRSTNAME, 'strLASTNAME': ad.strLASTNAME, 'strNUMEROSECURITESOCIAL': ad.strNUMEROSECURITESOCIAL},
      'tierspayants': [
        for (final tp in info?.tps ?? const <VenteTp>[]) {'compteTp': tp.compteTp, 'numBon': tp.numBon, 'taux': tp.taux, 'tpnet': total * tp.taux ~/ 100}
      ],
    });
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
  Future<VenteResult<List<PreventeListItem>>> preventes() => throw UnimplementedError();
  @override
  Future<VenteResult<ClientAssurance>> createClientCarnet({required String firstName, required String lastName, required String numSecu, required String tiersPayantId}) =>
      throw UnimplementedError();
}

class _Auth extends AuthProvider {
  _Auth() : super(ApiService(baseUrl: 'http://localhost'));
  @override
  User? get user => User(userId: 'U1', login: 'awa', firstName: 'Awa', lastName: 'Kouassi', officineName: 'TEST');
  @override
  Officine? get officine => Officine(fullName: 'KONAN KOU', nomComplet: 'PHCIE TEST');
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(720, 1400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}


Future<void> _open(WidgetTester tester, _FakeGateway gw, ListPresentation? style) async {
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
              onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => VenteAssuranceScreen(gateway: gw, presentation: style))),
              child: const Text('Ouvrir'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Ouvrir'));
  await tester.pumpAndSettle();
}

Finder get _field => find.byKey(const ValueKey('vente-recherche'));
Finder get _clientField => find.byKey(const ValueKey('assurance-client-recherche'));
Finder get _valider => find.byKey(const ValueKey('assurance-valider'));
Finder get _prevente => find.byKey(const ValueKey('assurance-prevente'));
Finder get _continuer => find.byKey(const ValueKey('assurance-continuer'));
Finder get _raison => find.byKey(const ValueKey('assurance-continuer-raison'));
Finder get _carte => find.byKey(const ValueKey('assurance-carte-client'));
Finder get _adCard => find.byKey(const ValueKey('assurance-ayant-droit'));
Finder get _pageValider => find.byKey(const ValueKey('encaissement-valider'));
Finder get _pageImprimer => find.byKey(const ValueKey('encaissement-imprimer'));
Finder _bon(String compte) => find.byKey(ValueKey('assurance-bon-$compte'));
Finder _etape(int i) => find.byKey(ValueKey('assurance-etape-$i'));

bool _enabled(WidgetTester tester, Finder f) => (tester.widget(f) as ButtonStyleButton).onPressed != null;
Color? _bg(WidgetTester tester, Finder f) => tester.widget<ButtonStyleButton>(f).style?.backgroundColor?.resolve({});
String _text(WidgetTester tester, Finder f) => tester.widget<Text>(f).data ?? '';
String _net(WidgetTester tester) => _text(tester, find.byKey(const ValueKey('assurance-net')));
String _f(int v) => '${Constants.formatNumber(v)} F';

Future<void> _searchClient(WidgetTester tester, String q) async {
  await tester.enterText(_clientField, q);
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
}

Future<void> _toCouverture(WidgetTester tester) async {
  await _searchClient(tester, 'kou');
  await tester.tap(find.text('KOUASSI Awa'));
  await tester.pumpAndSettle();
}

Future<void> _toProducts(WidgetTester tester, {bool ascoma = true}) async {
  await _toCouverture(tester);
  await tester.enterText(_bon('CT1'), 'B-1');
  if (ascoma) await tester.enterText(_bon('CT2'), 'B-2');
  await tester.pump();
  await tester.tap(_continuer);
  await tester.pumpAndSettle();
}

/// Recherche + fenêtre de quantité ; [settle] = attendre la réponse du serveur.
Future<void> _add(WidgetTester tester, String query, {String qty = '1', bool settle = true}) async {
  await tester.enterText(_field, query);
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
  await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField)), qty);
  await tester.tap(find.text('Ajouter'));
  if (settle) await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  setUp(() => SharedPreferences.setMockInitialValues({
        'enabled_payment_method_ids': ['1', '10'],
        'number_of_tickets_assurance': 2,
      }));

  for (final style in ListPresentation.values) {
    testWidgets('étape Client : recherche dans l\'en-tête, cartes, panne ≠ introuvable — ${style.label}', (tester) async {
      _phone(tester);
      final gw = _FakeGateway();
      await _open(tester, gw, style);
      expect(find.text('Vente assurance'), findsOneWidget);
      for (var i = 0; i < 4; i++) {
        expect(_etape(i), findsOneWidget);
      }
      expect(find.text('Couverture'), findsOneWidget);
      expect(find.text('Encaisser'), findsOneWidget);
      expect(find.text('Nom ou matricule du client'), findsOneWidget);
      expect(find.text('HISTORIQUE'), findsOneWidget); // Reprendre / Réimprimer
      expect(find.text('NOUVEAU CLIENT'), findsNothing);
      expect(find.text(style == ListPresentation.guided ? 'Étape 1 sur 4' : 'Choisir le client'), findsOneWidget);

      await _searchClient(tester, 'kou');
      expect(find.text('KOUASSI Awa'), findsOneWidget);
      if (style == ListPresentation.compact) {
        expect(find.text('Mat. MAT1 · MCI 70 % · ASCOMA 10 %'), findsOneWidget);
      } else {
        expect(find.text('Mat. MAT1'), findsOneWidget);
        expect(find.text('MCI 70 %'), findsOneWidget);
        expect(find.text('ASCOMA 10 %'), findsOneWidget);
        expect(find.text('Choisir'), findsOneWidget);
      }
      expect(find.text('NOUVEAU CLIENT'), findsNothing);

      // Panne : bandeau « Réessayer », jamais « introuvable » ni « Nouveau client ».
      gw.clientSearchFails = true;
      await _searchClient(tester, 'kouas');
      expect(find.textContaining('Recherche impossible'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
      expect(find.textContaining('introuvable'), findsNothing);
      expect(find.text('NOUVEAU CLIENT'), findsNothing);

      // Le serveur répond « aucun client » : « + NOUVEAU CLIENT » en bas.
      gw.clientSearchFails = false;
      await _searchClient(tester, 'zzz');
      expect(find.textContaining('Ce client est introuvable'), findsOneWidget);
      expect(find.text('NOUVEAU CLIENT'), findsOneWidget);
      if (style == ListPresentation.guided) expect(_bg(tester, find.byKey(const ValueKey('assurance-nouveau-client'))), Pal.amber);
      expect(tester.takeException(), isNull);
    });

    testWidgets('étape Couverture : ayant droit, TP en cartes, CONTINUER désactivé avec la raison — ${style.label}', (tester) async {
      _phone(tester);
      final gw = _FakeGateway();
      await _open(tester, gw, style);
      await _toCouverture(tester);
      expect(find.textContaining('KOUASSI Awa · Mat. MAT1'), findsOneWidget);
      expect(find.descendant(of: _adCard, matching: find.text('KOUASSI Awa')), findsOneWidget);
      expect(find.descendant(of: _adCard, matching: find.text('Changer')), findsOneWidget);
      expect(find.text('Nouvel ayant droit'), findsOneWidget);
      expect(find.text('70 %'), findsOneWidget); // taux ✎
      expect(find.text('10 %'), findsOneWidget);
      expect(find.text('Ajouter un tiers payant au client', skipOffstage: false), findsOneWidget); // en bas de la liste

      // Bons manquants : en rouge, bouton désactivé, raison exacte affichée.
      expect(find.text('N° de bon — obligatoire'), findsNWidgets(2));
      expect(_enabled(tester, _continuer), isFalse);
      expect(_text(tester, _raison), 'Saisissez le n° de bon MCI');
      await tester.enterText(_bon('CT1'), 'B-1');
      await tester.pumpAndSettle();
      expect(_text(tester, _raison), 'Saisissez le n° de bon ASCOMA');
      expect(find.text('N° de bon — obligatoire'), findsOneWidget);
      await tester.enterText(_bon('CT2'), ' b-1 ');
      await tester.pumpAndSettle();
      expect(_text(tester, _raison), 'Le même N° de bon est saisi pour deux tiers payants.');
      expect(_enabled(tester, _continuer), isFalse);
      await tester.enterText(_bon('CT2'), 'B-2');
      await tester.pumpAndSettle();
      expect(_raison, findsNothing);
      expect(_enabled(tester, _continuer), isTrue);
      expect(find.text('N° de bon — obligatoire'), findsNothing);
      if (style == ListPresentation.guided) expect(_bg(tester, _continuer), Pal.amber);

      // Ayant droit : « Changer ».
      await tester.tap(_adCard);
      await tester.pumpAndSettle();
      await tester.tap(find.text('KOUASSI Junior (M-AD2)'));
      await tester.pumpAndSettle();
      expect(find.descendant(of: _adCard, matching: find.text('KOUASSI Junior')), findsOneWidget);

      // Retour à l'étape Client par la barre : confirmation.
      await tester.tap(_etape(0));
      await tester.pumpAndSettle();
      expect(find.text('Changer de client ?'), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(_continuer, findsOneWidget);

      await tester.tap(_continuer);
      await tester.pumpAndSettle();
      expect(_field, findsOneWidget);
      expect(find.descendant(of: _carte, matching: find.text('KOUASSI Awa → KOUASSI Junior')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('étape Produits : carte client permanente, répartition (« Calcul… »), retour à la couverture — ${style.label}', (tester) async {
      _phone(tester);
      final gw = _FakeGateway();
      await _open(tester, gw, style);
      await _toProducts(tester);
      expect(find.text('Produits'), findsWidgets);
      expect(find.descendant(of: _carte, matching: find.text('KOUASSI Awa')), findsOneWidget);
      expect(find.descendant(of: _carte, matching: find.textContaining('MCI 70 % · bon B-1')), findsOneWidget);
      expect(find.descendant(of: _carte, matching: find.textContaining('ASCOMA 10 % · bon B-2')), findsOneWidget);
      expect(find.descendant(of: _carte, matching: find.text('Couverture')), findsOneWidget);
      expect(find.text('Le panier est vide'), findsOneWidget);
      // Répartition visible même panier vide.
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('MCI (70 %)'), findsOneWidget);
      expect(find.text('ASCOMA (10 %)'), findsOneWidget);
      expect(find.text('Part client'), findsOneWidget);
      expect(_net(tester), '0 F');
      expect(find.text('PRÉVENTE'), findsOneWidget);
      expect(find.text('ENCAISSER'), findsOneWidget);
      expect(_enabled(tester, _valider), isFalse);
      expect(_enabled(tester, _prevente), isFalse);

      await _add(tester, 'doli', qty: '2');
      expect(find.textContaining('enregistré sur le serveur'), findsOneWidget);
      expect(_net(tester), _f(600));

      // Ajout suivant : « Calcul… » pendant le recalcul, boutons désactivés (jamais l'ancien net).
      await _add(tester, 'effer', settle: false);
      var calcul = false;
      for (var i = 0; i < 20 && !calcul; i++) {
        await tester.pump(const Duration(milliseconds: 10));
        calcul = find.text('Calcul…').evaluate().isNotEmpty;
        expect(_enabled(tester, _valider), isFalse);
      }
      expect(calcul, isTrue);
      expect(find.byKey(const ValueKey('assurance-etat-envoi')), findsOneWidget);
      await tester.pumpAndSettle();
      // 4 000 : MCI 70 % = 2 800, ASCOMA 10 % = 400, part client 800.
      expect(find.text(_f(4000)), findsOneWidget);
      expect(find.text(_f(2800)), findsOneWidget);
      expect(find.text(_f(400)), findsOneWidget);
      expect(_net(tester), _f(800));
      expect(find.text('ENCAISSER ${_f(800)}'), findsOneWidget);
      expect(_enabled(tester, _valider), isTrue);
      expect(_enabled(tester, _prevente), isTrue);
      expect(find.text('2 articles enregistrés sur le serveur · net à jour'), findsOneWidget);
      switch (style) {
        case ListPresentation.dashboard:
          final edit = tester.getSize(find.byTooltip('Modifier').first);
          expect(edit.height, greaterThanOrEqualTo(44));
        case ListPresentation.compact:
          expect(find.textContaining('glisser : supprimer'), findsOneWidget);
        case ListPresentation.guided:
          expect(_bg(tester, _valider), Pal.amber);
          expect(find.textContaining('Étape 3 sur 4'), findsOneWidget);
      }

      // Retour à la couverture par la barre d'étapes : bons conservés, panier intact.
      await tester.tap(_etape(1));
      await tester.pumpAndSettle();
      expect(_continuer, findsOneWidget);
      expect(find.descendant(of: _bon('CT1'), matching: find.text('B-1')), findsOneWidget);
      await tester.tap(_continuer);
      await tester.pumpAndSettle();
      expect(find.text('EFFERALGAN 500MG'), findsOneWidget);
      expect(_net(tester), _f(800));
      expect(tester.takeException(), isNull);
    });

    testWidgets('encaissement sur une page (part client > 0), copies du réglage Assurance — ${style.label}', (tester) async {
      _phone(tester);
      final gw = _FakeGateway();
      await _open(tester, gw, style);
      await _toProducts(tester);
      await _add(tester, 'doli'); // 1 500 : part client 300
      expect(find.text('ENCAISSER ${_f(300)}'), findsOneWidget);
      await tester.tap(_valider);
      await tester.pumpAndSettle();

      expect(find.byType(EncaissementPage), findsOneWidget);
      expect(find.text('Encaissement'), findsOneWidget);
      expect(find.text('Part client à payer'), findsOneWidget);
      expect(_text(tester, find.byKey(const ValueKey('encaissement-total'))), _f(300));
      expect(_etape(3), findsOneWidget); // barre d'étapes du menu, étape Encaisser
      expect(find.text('Espèces'), findsOneWidget);
      expect(find.text('WAVE'), findsOneWidget);
      expect(tester.widget<Checkbox>(_pageImprimer).value, isTrue);
      expect(_text(tester, find.byKey(const ValueKey('encaissement-copies'))), '2'); // « Nombre de tickets (Assurance) »
      if (style == ListPresentation.guided) expect(_bg(tester, _pageValider), Pal.amber);

      await tester.tap(find.text('Exact'));
      await tester.pump();
      expect(_text(tester, find.byKey(const ValueKey('encaissement-monnaie'))), _f(0));
      await tester.ensureVisible(_pageImprimer);
      await tester.pumpAndSettle();
      await tester.tap(_pageImprimer);
      await tester.pump();
      await tester.tap(_pageValider);
      await tester.pumpAndSettle();
      expect(gw.clotures.length, 1);
      expect(gw.clotures.single.typeReglementId, '1');
      expect(gw.clotures.single.net, 300);
      expect(find.text('Vente validée ✓ (AS-V1)'), findsOneWidget);
      expect(_clientField, findsOneWidget); // nouvelle vente
      expect(tester.takeException(), isNull);
    });

    testWidgets('part client 0 F : « VALIDER (0 F) », confirmation simple, pas de page d\'encaissement — ${style.label}', (tester) async {
      _phone(tester);
      final gw = _FakeGateway()..clients = [_client(tps: [_ctp('TP1', 'MCI', 'CT1', 100, 1)])];
      await _open(tester, gw, style);
      await _toProducts(tester, ascoma: false);
      await _add(tester, 'doli');
      expect(_net(tester), '0 F');
      expect(find.text('VALIDER (0 F)'), findsOneWidget);
      if (style == ListPresentation.guided) expect(_bg(tester, _valider), Pal.amber);
      await tester.tap(_valider);
      await tester.pumpAndSettle();
      expect(find.byType(EncaissementPage), findsNothing);
      expect(find.text('Valider la vente ?'), findsOneWidget);
      expect(_text(tester, find.byKey(const ValueKey('assurance-zero-copies'))), '2');
      expect(gw.clotures, isEmpty);
      await tester.tap(find.byKey(const ValueKey('assurance-zero-imprimer')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('assurance-zero-valider')));
      await tester.pumpAndSettle();
      expect(gw.clotures.single.typeReglementId, '1');
      expect(gw.clotures.single.net, 0);
      expect(find.textContaining('Vente validée'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Annuler la confirmation 0 F : rien n\'est clôturé', (tester) async {
    _phone(tester);
    final gw = _FakeGateway()..clients = [_client(tps: [_ctp('TP1', 'MCI', 'CT1', 100, 1)])];
    await _open(tester, gw, ListPresentation.dashboard);
    await _toProducts(tester, ascoma: false);
    await _add(tester, 'doli');
    await tester.tap(_valider);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(gw.clotures, isEmpty);
    expect(_enabled(tester, _valider), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('double tap ENCAISSER puis double tap VALIDER sur la page : une seule page, une seule clôture', (tester) async {
    _phone(tester);
    final gw = _FakeGateway()..delay = const Duration(milliseconds: 100);
    await _open(tester, gw, ListPresentation.guided);
    await _toProducts(tester);
    await _add(tester, 'doli');
    await tester.tap(_valider);
    await tester.tap(_valider, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(EncaissementPage, skipOffstage: false), findsOneWidget);
    await tester.tap(find.text('WAVE'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(_pageImprimer);
    await tester.pumpAndSettle();
    await tester.tap(_pageImprimer);
    await tester.pump();
    await tester.tap(_pageValider);
    await tester.tap(_pageValider, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 10));
    await tester.tap(_pageValider, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(gw.clotures.length, 1);
    expect(gw.clotures.single.typeReglementId, '10');
    expect(find.textContaining('Vente validée'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('double tap VALIDER (0 F) : une seule confirmation, une seule clôture', (tester) async {
    _phone(tester);
    final gw = _FakeGateway()
      ..delay = const Duration(milliseconds: 100)
      ..clients = [_client(tps: [_ctp('TP1', 'MCI', 'CT1', 100, 1)])];
    await _open(tester, gw, ListPresentation.compact);
    await _toProducts(tester, ascoma: false);
    await _add(tester, 'doli');
    await tester.tap(_valider);
    await tester.tap(_valider, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Valider la vente ?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('assurance-zero-imprimer')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('assurance-zero-valider')));
    await tester.tap(find.byKey(const ValueKey('assurance-zero-valider')), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(gw.clotures.length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('client sans ayant droit : CONTINUER désactivé, raison affichée', (tester) async {
    _phone(tester);
    final gw = _FakeGateway()..clients = [_client(ads: const [])];
    await _open(tester, gw, ListPresentation.guided);
    await _toCouverture(tester);
    await tester.enterText(_bon('CT1'), 'B-1');
    await tester.enterText(_bon('CT2'), 'B-2');
    await tester.pump();
    expect(find.text('Aucun ayant droit : créez-en un'), findsOneWidget);
    expect(_text(tester, _raison), 'Choisissez ou créez un ayant droit (patient) avant de continuer.');
    expect(_enabled(tester, _continuer), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('menu « Présentation » : choix mémorisé et transmis à la page d\'encaissement', (tester) async {
    _phone(tester);
    final gw = _FakeGateway();
    await _open(tester, gw, null);
    expect(find.byType(NavyHeader), findsOneWidget); // A par défaut
    await tester.tap(find.byTooltip('Présentation'));
    await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate((w) => w is CheckedPopupMenuItem<ListPresentation> && w.value == ListPresentation.compact));
    await tester.pumpAndSettle();
    expect(await PresentationPrefs.load(), ListPresentation.compact);
    expect(find.byType(NavyHeader), findsNothing);
    await _toProducts(tester);
    expect(find.byType(NavyHeader), findsNothing);
    await _add(tester, 'doli');
    await tester.tap(_valider);
    await tester.pumpAndSettle();
    expect(find.byType(EncaissementPage), findsOneWidget);
    expect(find.byType(NavyHeader), findsNothing); // B transmis à la page
    expect(find.text('Part client à payer'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(gw.clotures, isEmpty);
    expect(_enabled(tester, _valider), isTrue);
    expect(tester.takeException(), isNull);
  });
}
