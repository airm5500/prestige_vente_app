// Pré-vente Assurance (nouvelle version) : parcours complet à 360 px (Client → Couverture → Produits → Encaisser),
// net recalculé automatiquement, double scan (1 seule vente), double tap (1 seule clôture), panne / réponse
// perdue / refus, caisse fermée, net non à jour, panier non relu, quitter / reprendre, historique
// (Reprendre / Réimprimer avec la vraie référence), nom/prénom, ayant droit obligatoire, bons, 100 %.
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
import 'package:prestige_vente_app/ventes/assurance/assurance_controller.dart';
import 'package:prestige_vente_app/ventes/assurance/vente_assurance_screen.dart';
import 'package:prestige_vente_app/ventes/core/pending_sale_store.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/ventes/prevente/encaissement_page.dart';
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
                onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => VenteAssuranceScreen(gateway: gw))),
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

Finder get _field => find.byKey(const ValueKey('vente-recherche'));
Finder get _clientField => find.byKey(const ValueKey('assurance-client-recherche'));
Finder get _valider => find.byKey(const ValueKey('assurance-valider'));
Finder get _prevente => find.byKey(const ValueKey('assurance-prevente'));
Finder get _continuer => find.byKey(const ValueKey('assurance-continuer'));
Finder _bon(String compte) => find.byKey(ValueKey('assurance-bon-$compte'));
Finder get _adCard => find.byKey(const ValueKey('assurance-ayant-droit'));
Finder _inAdCard(String text) => find.descendant(of: _adCard, matching: find.text(text));
Finder get _encaissementValider => find.byKey(const ValueKey('encaissement-valider'));
Finder get _encaissementImprimer => find.byKey(const ValueKey('encaissement-imprimer'));

bool _enabled(WidgetTester tester, Finder f) => (tester.widget(f) as ButtonStyleButton).onPressed != null;

/// Part client affichée (sans « F »).
String _netText(WidgetTester tester) => ((tester.widget(find.byKey(const ValueKey('assurance-net'))) as Text).data ?? '').replaceAll(RegExp(r' F$'), '');

Future<void> _searchClient(WidgetTester tester, String q) async {
  await tester.enterText(_clientField, q);
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
}

/// Client → bons → étape Produits.
Future<void> _toProducts(WidgetTester tester, {String bon1 = 'B-1', String bon2 = 'B-2'}) async {
  await _searchClient(tester, 'kou');
  await tester.tap(find.text('KOUASSI Awa'));
  await tester.pumpAndSettle();
  await tester.enterText(_bon('CT1'), bon1);
  await tester.enterText(_bon('CT2'), bon2);
  await tester.pump(); // bouton activé dès que la saisie est complète
  await tester.tap(_continuer);
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

String _f(int v) => Constants.formatNumber(v);

/// L'aperçu « mode test » d'origine (ReceiptService, largeur fixe 300 px) déborde à 360 px :
/// défaut d'affichage existant, hors périmètre de ce menu ; seul ce débordement est toléré.
void _previewOverflow(WidgetTester tester) {
  final e = tester.takeException();
  expect(e == null || '$e'.contains('overflowed'), isTrue, reason: '$e');
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  setUp(() => SharedPreferences.setMockInitialValues({
        'enabled_payment_method_ids': ['1', '10'],
        'number_of_tickets_assurance': 1,
        'is_test_print_mode': true,
      }));

  testWidgets('parcours complet : client, bons, produits, net automatique, encaissement (1 clôture, 1 dialogue d\'impression)', (tester) async {
    _phone(tester);
    final gw = _FakeGateway();
    await _open(tester, gw);

    // Bon obligatoire : pas d'étape Produits sans bon.
    await _searchClient(tester, 'kou');
    await tester.tap(find.text('KOUASSI Awa'));
    await tester.pumpAndSettle();
    // Ayant droit = le client.
    expect(_inAdCard('KOUASSI Awa'), findsOneWidget);
    expect(_inAdCard('Mat. M-C1'), findsOneWidget);
    await tester.enterText(_bon('CT1'), '  B-1  ');
    await tester.pump(); // bouton activé dès que la saisie est complète
    await tester.tap(_continuer);
    await tester.pumpAndSettle();
    expect(find.text('Saisissez le n° de bon ASCOMA'), findsOneWidget);
    expect(_enabled(tester, _continuer), isFalse);
    await tester.enterText(_bon('CT2'), 'b-1');
    await tester.pump(); // bouton activé dès que la saisie est complète
    await tester.tap(_continuer);
    await tester.pumpAndSettle();
    expect(find.text('Le même N° de bon est saisi pour deux tiers payants.'), findsOneWidget);
    await tester.enterText(_bon('CT2'), 'B-2');
    await tester.pump(); // bouton activé dès que la saisie est complète
    await tester.tap(_continuer);
    await tester.pumpAndSettle();

    expect(find.text('Calculer le Net à Payer'), findsNothing);
    await _addManual(tester, 'doli', qty: '2');
    expect(find.text('DOLIPRANE 1000MG CP B/8'), findsOneWidget);
    // 3 000 : MCI 70 % = 2 100, ASCOMA 10 % = 300, part client 600 (calcul automatique).
    expect(_netText(tester), _f(600));
    expect(gw.netTps.last.map((t) => t.numBon).toList(), ['B-1', 'B-2']); // bons nettoyés
    expect((await PendingSaleStore.load(VenteMenu.assurance))?.venteId, 'V1');

    // Modifier la ligne : quantité 0 refusée, 3 acceptée → net recalculé.
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
    expect(_netText(tester), _f(900));
    expect(find.text('ENCAISSER ${_f(900)} F'), findsOneWidget);

    await tester.tap(_valider);
    await tester.pumpAndSettle();
    await tester.tap(find.text('WAVE'));
    await tester.pumpAndSettle();
    await tester.tap(_encaissementImprimer); // un seul choix d'impression, sur la page
    await tester.pump();
    await tester.tap(_encaissementValider);
    await tester.pumpAndSettle();
    expect(find.text('Vente validée ✓ (AS-V1)'), findsOneWidget);

    expect(gw.clotures.length, 1);
    expect(gw.clotures.single.typeReglementId, '10');
    expect(gw.clotures.single.net, 900);
    expect(gw.statut['V1'], 'is_Closed');
    expect(await PendingSaleStore.load(VenteMenu.assurance), isNull);
    expect(_clientField, findsOneWidget); // nouvelle vente
    expect(tester.takeException(), isNull);
  });

  testWidgets('espèces : le montant versé vaut confirmation ; prévente : terminerprevente sans clôture', (tester) async {
    _phone(tester);
    final gw = _FakeGateway();
    await _open(tester, gw);
    await _toProducts(tester);
    await _addManual(tester, 'doli');
    await tester.tap(_prevente);
    await tester.pumpAndSettle();
    expect(find.text('Prévente enregistrée'), findsOneWidget);
    await tester.tap(find.text('Ne pas imprimer'));
    await tester.pumpAndSettle();
    expect(gw.terminerCalls, 1);
    expect(gw.clotures, isEmpty);
    expect(gw.statut['V1'], 'is_Process');

    await _toProducts(tester);
    await _addManual(tester, 'doli');
    await tester.tap(_valider);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Espèces'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('encaissement-recu')), '500');
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const ValueKey('encaissement-monnaie'))).data, '${_f(200)} F');
    await tester.tap(_encaissementImprimer);
    await tester.pump();
    await tester.tap(_encaissementValider);
    await tester.pumpAndSettle();
    expect(find.text('Confirmation de paiement'), findsNothing);
    expect(find.textContaining('Vente validée'), findsOneWidget);
    expect(gw.clotures.single.typeReglementId, '1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('recherche client en panne : « Recherche impossible » + Réessayer, jamais « introuvable » ni « Créer »', (tester) async {
    _phone(tester);
    final gw = _FakeGateway()..clientSearchFails = true;
    await _open(tester, gw);
    await _searchClient(tester, 'kou');
    expect(find.textContaining('Recherche impossible'), findsOneWidget);
    expect(find.textContaining('introuvable'), findsNothing);
    expect(find.text('NOUVEAU CLIENT'), findsNothing);
    gw.clientSearchFails = false;
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.text('KOUASSI Awa'), findsOneWidget);

    await _searchClient(tester, 'zzz');
    expect(find.textContaining('Ce client est introuvable'), findsOneWidget);
    expect(find.text('NOUVEAU CLIENT'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('création client puis ayant droit : Nom → strFIRSTNAME, Prénom → strLASTNAME (même ordre)', (tester) async {
    _phone(tester);
    final gw = _FakeGateway();
    await _open(tester, gw);
    await _searchClient(tester, 'zzz');
    await tester.tap(find.text('NOUVEAU CLIENT'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('client-nom')), 'TRAORE');
    await tester.enterText(find.byKey(const ValueKey('client-prenom')), 'Moussa');
    await tester.enterText(find.byKey(const ValueKey('client-matricule')), 'M77');
    await tester.enterText(find.byKey(const ValueKey('assurance-tp-recherche')), 'saham');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SAHAM ASSURANCE'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('client-taux')), '0');
    await tester.tap(find.text('Créer'));
    await tester.pumpAndSettle();
    expect(find.text('Invalide (1-100)'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('client-taux')), '80');
    await tester.tap(find.text('Créer'));
    await tester.pumpAndSettle();
    expect(gw.createdClients.single, (first: 'TRAORE', last: 'Moussa'));
    expect(find.text('TRAORE Moussa'), findsOneWidget);

    await tester.tap(find.text('Nouvel ayant droit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('ad-nom')), 'TRAORE');
    await tester.enterText(find.byKey(const ValueKey('ad-prenom')), 'Fatou');
    await tester.enterText(find.byKey(const ValueKey('ad-matricule')), 'M78');
    await tester.tap(find.text('Créer'));
    await tester.pumpAndSettle();
    expect(gw.createdAds.single, (first: 'TRAORE', last: 'Fatou'));
    expect(_inAdCard('TRAORE Fatou'), findsOneWidget);
    expect(_inAdCard('Mat. M78'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('client sans ayant droit : étape Produits refusée tant qu\'aucun ayant droit n\'est choisi', (tester) async {
    _phone(tester);
    final gw = _FakeGateway()..clients = [_client(ads: const [])];
    await _open(tester, gw);
    await _searchClient(tester, 'kou');
    await tester.tap(find.text('KOUASSI Awa'));
    await tester.pumpAndSettle();
    expect(find.text('Aucun ayant droit : créez-en un'), findsOneWidget);
    await tester.enterText(_bon('CT1'), 'B-1');
    await tester.enterText(_bon('CT2'), 'B-2');
    await tester.pump(); // bouton activé dès que la saisie est complète
    await tester.tap(_continuer);
    await tester.pumpAndSettle();
    expect(find.textContaining('Choisissez ou créez un ayant droit'), findsOneWidget);
    expect(_field, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('taux modifié : net recalculé tout seul ; « Changer l\'assurance » demande confirmation', (tester) async {
    _phone(tester);
    final gw = _FakeGateway();
    await _open(tester, gw);
    await _toProducts(tester);
    await _addManual(tester, 'doli');
    expect(_netText(tester), _f(300));

    await tester.tap(find.byKey(const ValueKey('assurance-couverture')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('assurance-taux-CT1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('tp-edit-taux')), '101');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(find.text('Invalide (0-100)'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('tp-edit-taux')), '90');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(gw.netTps.last.firstWhere((t) => t.compteTp == 'CT1').taux, 90);
    await tester.pump(); // bouton activé dès que la saisie est complète
    await tester.tap(_continuer);
    await tester.pumpAndSettle();
    // 1 500 : 90 % + 10 % = 100 % → part client 0.
    expect(_netText(tester), _f(0));
    expect(find.text('VALIDER (0 F)'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('assurance-couverture')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('assurance-taux-CT1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Changer l\'assurance'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('assurance-tp-recherche')), 'saham');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SAHAM ASSURANCE'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(find.text('Modifier la fiche client ?'), findsOneWidget);
    await tester.tap(find.text('Annuler').last);
    await tester.pumpAndSettle();
    expect(gw.updateClientCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('assurance à 100 % : validation directe (part client 0), ticket « VENTE ASSURANCE » et non « CARNET »', (tester) async {
    _phone(tester);
    final gw = _FakeGateway()..clients = [_client(tps: [_ctp('TP1', 'MCI', 'CT1', 100, 1)])];
    await _open(tester, gw);
    await _searchClient(tester, 'kou');
    await tester.tap(find.text('KOUASSI Awa'));
    await tester.pumpAndSettle();
    await tester.enterText(_bon('CT1'), 'B-9');
    await tester.pump(); // bouton activé dès que la saisie est complète
    await tester.tap(_continuer);
    await tester.pumpAndSettle();
    await _addManual(tester, 'doli');
    expect(find.text('VALIDER (0 F)'), findsOneWidget);
    await tester.tap(_valider);
    await tester.pumpAndSettle();
    expect(find.text('Mode de règlement'), findsNothing);
    expect(find.byType(EncaissementPage), findsNothing); // rien à encaisser : pas de page
    // Confirmation simple, impression cochée (un seul choix).
    expect(find.text('Valider la vente ?'), findsOneWidget);
    expect(gw.clotures, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('assurance-zero-valider')));
    await tester.pumpAndSettle();
    expect(gw.clotures.single.typeReglementId, '1');
    expect(find.textContaining('Vente validée'), findsOneWidget);
    expect(find.text('Aperçu du Ticket'), findsOneWidget);
    _previewOverflow(tester);
    expect(find.text('VENTE ASSURANCE'), findsOneWidget);
    expect(find.text('VENTE CARNET'), findsNothing);
    expect(find.text('AS-V1'), findsOneWidget); // vraie référence
    await tester.tap(find.text('Fermer'));
    await tester.pumpAndSettle();
    expect(find.text('Réimpression'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('double scan rapide du 1ᵉʳ produit : une seule vente créée, « ajouté » après le serveur', (tester) async {
    _phone(tester);
    SharedPreferences.setMockInitialValues({'isQuickScanMode': true, 'enabled_payment_method_ids': ['1']});
    final gw = _FakeGateway()..delay = const Duration(milliseconds: 150);
    await _open(tester, gw);
    await _toProducts(tester);
    await _scan(tester, _doli.intCIP);
    await _scan(tester, _doli.intCIP);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('ajouté (+1)'), findsNothing);
    await tester.pumpAndSettle();
    expect(gw.creations, 1);
    expect(gw.addVenteIds, [null, 'V1']);
    expect(gw.sales['V1']!.length, 2);
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

  testWidgets('réponse perdue à l\'ajout : panier relu, pas de renvoi ni de doublon', (tester) async {
    _phone(tester);
    final gw = _FakeGateway();
    await _open(tester, gw);
    await _toProducts(tester);
    await _addManual(tester, 'doli');
    gw.addMode = _Mode.lost;
    await _addManual(tester, 'effer');
    expect(gw.addVenteIds.length, 2);
    expect(gw.sales['V1']!.length, 2);
    expect(find.text('EFFERALGAN 500MG'), findsOneWidget);
    expect(_netText(tester), _f(500));

    gw.addMode = _Mode.lostNotApplied;
    await _addManual(tester, 'effer');
    expect(gw.addVenteIds.length, 3);
    expect(gw.sales['V1']!.length, 2);
    expect(find.textContaining('Produit non ajouté'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refus du serveur : SON message est affiché (balises retirées)', (tester) async {
    _phone(tester);
    final gw = _FakeGateway()..addMode = _Mode.refused;
    await _open(tester, gw);
    await _toProducts(tester);
    await _addManual(tester, 'doli');
    expect(find.text('Plafond atteint pour ce tiers payant'), findsOneWidget);
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
    await tester.tap(find.text('WAVE'));
    await tester.pumpAndSettle();
    await tester.tap(_encaissementValider);
    await tester.pumpAndSettle();
    expect(find.text('Caisse Fermée'), findsOneWidget);
    await tester.tap(find.text('Non'));
    await tester.pumpAndSettle();
    expect(find.text('Caisse fermée : ouvrez-la avant de valider.'), findsOneWidget); // on reste sur la page
    await tester.tap(find.byTooltip('Retour')); // bouton retour de l'en-tête
    await tester.pumpAndSettle();
    expect(find.text('DOLIPRANE 1000MG CP B/8'), findsOneWidget);
    expect(_enabled(tester, _valider), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bon déjà utilisé à la validation : retour à l\'étape des bons avec le message du serveur', (tester) async {
    _phone(tester);
    final gw = _FakeGateway()..clotureMode = _Mode.bonUtilise;
    await _open(tester, gw);
    await _toProducts(tester);
    await _addManual(tester, 'doli');
    await tester.tap(_valider);
    await tester.pumpAndSettle();
    await tester.tap(find.text('WAVE'));
    await tester.pumpAndSettle();
    await tester.tap(_encaissementValider);
    await tester.pumpAndSettle();
    expect(find.byType(EncaissementPage), findsNothing); // page fermée : retour à la couverture
    expect(find.text('Le numéro de bon B-1 est déjà utilisé'), findsOneWidget);
    expect(_continuer, findsOneWidget);
    gw.clotureMode = _Mode.ok;
    await tester.enterText(_bon('CT1'), 'B-7');
    await tester.pump(); // bouton activé dès que la saisie est complète
    await tester.tap(_continuer);
    await tester.pumpAndSettle();
    expect(gw.netTps.last.first.numBon, 'B-7');
    expect(_enabled(tester, _valider), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('net non à jour : validation bloquée jusqu\'au recalcul (jamais l\'ancien net)', (tester) async {
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
    expect(_netText(tester), '—');

    gw.netFails = false;
    await tester.tap(find.text('Réessayer').first);
    await tester.pumpAndSettle();
    expect(_enabled(tester, _valider), isTrue);
    expect(_netText(tester), _f(500));
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

  testWidgets('double tap sur Encaisser puis VALIDER : une seule clôture', (tester) async {
    _phone(tester);
    final gw = _FakeGateway()..delay = const Duration(milliseconds: 100);
    await _open(tester, gw);
    await _toProducts(tester);
    await _addManual(tester, 'doli');
    await tester.tap(_valider);
    await tester.tap(_valider, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(EncaissementPage, skipOffstage: false), findsOneWidget); // une seule page
    await tester.tap(find.text('WAVE'));
    await tester.pumpAndSettle();
    await tester.tap(_encaissementImprimer);
    await tester.pump();
    await tester.tap(_encaissementValider);
    await tester.tap(_encaissementValider, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(gw.clotures.length, 1);
    expect(tester.takeException(), isNull);
  });

  test('contrôleur : deux validations simultanées → une seule clôture ; réponse perdue → relecture du statut', () async {
    SharedPreferences.setMockInitialValues({});
    Future<AssuranceController> ready(_FakeGateway gw) async {
      final c = AssuranceController(gateway: gw, userId: 'U1');
      await c.selectClient(_client());
      expect(c.validateCouverture({'CT1': 'B-1', 'CT2': 'B-2'}), isNull);
      expect((await c.addProduct(_doli, 1)).isOk, isTrue);
      await c.idle();
      return c;
    }

    final gw = _FakeGateway()..delay = const Duration(milliseconds: 5);
    final c = await ready(gw);
    final m = PaymentMethod(id: '10', name: 'WAVE');
    final r = await Future.wait([
      c.cloturer(method: m, expectedChanges: c.changes),
      c.cloturer(method: m, expectedChanges: c.changes),
    ]);
    expect(r.every((x) => x.isOk), isTrue);
    expect(gw.clotures.length, 1);

    final gw2 = _FakeGateway()
      ..delay = const Duration(milliseconds: 5)
      ..clotureMode = _Mode.lost;
    final c2 = await ready(gw2);
    expect((await c2.cloturer(method: m, expectedChanges: c2.changes)).isOk, isTrue);
    expect(gw2.clotures.length, 1);

    // TP modifié après la confirmation : refusé (net à recalculer).
    final gw3 = _FakeGateway()..delay = const Duration(milliseconds: 5);
    final c3 = await ready(gw3);
    final before = c3.changes;
    c3.updateTaux('CT1', 50);
    expect((await c3.cloturer(method: m, expectedChanges: before)).isOk, isFalse);
    expect(gw3.clotures, isEmpty);
    await c3.idle();
    expect(c3.netUpToDate, isTrue);
    expect(gw3.netTps.last.first.taux, 50);
  });

  testWidgets('quitter en pleine vente : confirmation, vente mémorisée puis « Reprendre la vente ? » (client, ayant droit, bons, panier)', (tester) async {
    _phone(tester);
    final gw = _FakeGateway();
    await _open(tester, gw);
    await _searchClient(tester, 'kou');
    await tester.tap(find.text('KOUASSI Awa'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('assurance-ayant-droit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('KOUASSI Junior (M-AD2)').last);
    await tester.pumpAndSettle();
    await tester.enterText(_bon('CT1'), 'B-1');
    await tester.enterText(_bon('CT2'), 'B-2');
    await tester.pump(); // bouton activé dès que la saisie est complète
    await tester.tap(_continuer);
    await tester.pumpAndSettle();
    await _addManual(tester, 'doli');

    await tester.tap(find.byTooltip('Retour')); // bouton retour de l'en-tête
    await tester.pumpAndSettle();
    expect(find.text('Quitter la vente en cours ?'), findsOneWidget);
    await tester.tap(find.text('Rester'));
    await tester.pumpAndSettle();
    expect(find.text('DOLIPRANE 1000MG CP B/8'), findsOneWidget);
    await tester.tap(find.byTooltip('Retour')); // bouton retour de l'en-tête
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quitter'));
    await tester.pumpAndSettle();
    expect(find.text('Ouvrir'), findsOneWidget);

    await _open(tester, gw, pumpApp: false);
    expect(find.text('Reprendre la vente ?'), findsOneWidget);
    expect(find.textContaining('AS-V1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('vente-reprendre')));
    await tester.pumpAndSettle();
    expect(find.text('DOLIPRANE 1000MG CP B/8'), findsOneWidget);
    expect(find.text('KOUASSI Awa → KOUASSI Junior'), findsOneWidget); // carte client : client → ayant droit
    expect(_netText(tester), _f(300));
    await _addManual(tester, 'effer');
    expect(gw.creations, 1);
    expect(gw.addVenteIds.last, 'V1');
    expect(gw.netTps.last.map((t) => t.numBon).toList(), ['B-1', 'B-2']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('historique : Réimprimer charge la vente (vraie référence, copies sans confirmation par copie) ; Reprendre ; vente clôturée', (tester) async {
    _phone(tester);
    final gw = _FakeGateway();
    gw.sales['V5'] = [gw._line('V5', _effer, 2, 1000)];
    gw.statut['V5'] = 'is_Process';
    gw.saleInfo['V5'] = (clientId: 'C1', adId: 'C1', tps: [(compteTp: 'CT1', numBon: 'B-55', taux: 70)]);
    gw.sales['V6'] = [gw._line('V6', _doli, 1, 1500)];
    gw.statut['V6'] = 'is_Closed';
    gw.saleInfo['V6'] = (clientId: 'C1', adId: 'C1', tps: [(compteTp: 'CT1', numBon: 'B-66', taux: 70)]);
    PreventeListItem it(String id, String ref, int price) =>
        PreventeListItem(lgPREENREGISTREMENTID: id, heure: '09:41:12', dtUPDATED: '03/09/2026', intPRICE: price, strREF: ref, userFullName: 'Awa', lgTYPEVENTEID: '2');
    gw.history = [it('V5', 'AS-V5', 2000), it('V6', 'AS-V6', 1500)];
    await _open(tester, gw);

    await tester.tap(find.byKey(const ValueKey('assurance-historique')));
    await tester.pumpAndSettle();
    expect(find.textContaining('03/09/2026 09:41'), findsWidgets);
    await tester.tap(find.text('Réimprimer').first);
    await tester.pumpAndSettle();
    expect(find.text('Réimprimer AS-V5'), findsOneWidget);
    await tester.tap(find.byTooltip('Plus de copies'));
    await tester.pump();
    expect(find.text('2 copies'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Imprimer'));
    await tester.pumpAndSettle();
    expect(find.text('Aperçu du Ticket'), findsOneWidget);
    _previewOverflow(tester);
    expect(find.text('PRE-VENTE ASSURANCE'), findsOneWidget);
    expect(find.text('AS-V5'), findsOneWidget);
    await tester.tap(find.text('Fermer'));
    await tester.pumpAndSettle();
    expect(find.text('Réimpression'), findsNothing); // 2ᵉ copie sans dialogue de confirmation
    expect(find.text('Aperçu du Ticket'), findsOneWidget);
    await tester.tap(find.text('Fermer'));
    await tester.pumpAndSettle();

    // Vente clôturée : reprise refusée avec un message clair.
    await tester.tap(find.byKey(const ValueKey('assurance-historique')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reprendre').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('déjà clôturée'), findsOneWidget);

    // Prévente : reprise ; le bon manquant (ASCOMA non utilisé ici) n'est pas inventé.
    await tester.tap(find.byKey(const ValueKey('assurance-historique')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reprendre').first);
    await tester.pumpAndSettle();
    expect(find.text('EFFERALGAN 500MG'), findsOneWidget);
    expect(find.text('MCI 70 % · bon B-55'), findsOneWidget); // carte client : seul le TP de la vente est actif
    expect(find.textContaining('ASCOMA'), findsNothing);
    expect(_netText(tester), _f(600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reprise : ayant droit non retrouvé → message clair, retour à l\'étape des bons', (tester) async {
    _phone(tester);
    final gw = _FakeGateway();
    gw.sales['V5'] = [gw._line('V5', _effer, 1, 1000)];
    gw.statut['V5'] = 'is_Process';
    gw.saleInfo['V5'] = (clientId: 'C1', adId: 'INCONNU', tps: [(compteTp: 'CT1', numBon: 'B-55', taux: 70)]);
    gw.history = [
      PreventeListItem(lgPREENREGISTREMENTID: 'V5', heure: '', dtUPDATED: '03/09/2026', intPRICE: 1000, strREF: 'AS-V5', userFullName: '', lgTYPEVENTEID: '2')
    ];
    await _open(tester, gw);
    await tester.tap(find.byKey(const ValueKey('assurance-historique')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reprendre'));
    await tester.pumpAndSettle();
    expect(find.text('Informations à compléter'), findsOneWidget);
    expect(find.textContaining('ayant droit'), findsWidgets);
    await tester.tap(find.text('Compléter'));
    await tester.pumpAndSettle();
    expect(_continuer, findsOneWidget);
    await tester.pump(); // bouton activé dès que la saisie est complète
    await tester.tap(_continuer);
    await tester.pumpAndSettle();
    expect(find.textContaining('Choisissez ou créez un ayant droit'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('suppression d\'une ligne avec confirmation, net recalculé', (tester) async {
    _phone(tester);
    final gw = _FakeGateway();
    await _open(tester, gw);
    await _toProducts(tester);
    await _addManual(tester, 'doli');
    await _addManual(tester, 'effer');
    expect(_netText(tester), _f(500));
    await tester.tap(find.byTooltip('Supprimer').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Non'));
    await tester.pumpAndSettle();
    expect(gw.sales['V1']!.length, 2);
    await tester.tap(find.byTooltip('Supprimer').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Supprimer'));
    await tester.pumpAndSettle();
    expect(gw.sales['V1']!.length, 1);
    expect(_netText(tester), _f(200));
    expect(tester.takeException(), isNull);
  });

  test('lecture /ventestats : nombres en texte, nom complet reconstitué, référence de secours', () {
    final d = AssuranceSaleData.parse({
      'client': {
        'lgCLIENTID': 'C1',
        'strFIRSTNAME': 'KOUASSI',
        'strLASTNAME': 'Awa',
        'tiersPayants': [
          {'compteTp': 'CT1', 'taux': '80', 'order': '1', 'tpFullName': 'MCI'}
        ]
      },
      'tierspayants': [
        {'compteTp': 'CT1', 'numBon': 'B1', 'taux': '80', 'tpnet': '800'}
      ],
      'intPRICE': '1000',
    }, venteId: 'V1', fallbackRef: 'AS-1');
    expect(d.client?.fullName, 'KOUASSI Awa');
    expect(d.client?.tiersPayants.single.taux, 80);
    expect(d.summary.montantNet, 200);
    expect(d.reference, 'AS-1');
    expect(d.ticketAyantDroit?.lgAYANTSDROITSID, 'C1');
    expect(AssuranceSaleData.parse(const {}, venteId: 'V').client, isNull);
  });
}
