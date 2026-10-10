// Vente Carnet — présentations A / B / C à 360 px : étapes Client, Bon & ayant droit, Produits,
// création client en page, carte client permanente, « Continuer » désactivé avec la raison,
// lignes non enregistrées (Réessayer sans doublon), « Calcul… », double tap VALIDER = 1 clôture.
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
import 'package:prestige_vente_app/ventes/carnet/carnet_frame.dart';
import 'package:prestige_vente_app/ventes/carnet/vente_carnet_screen.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProductSearchResult _p(String id, String name, String cip, {int price = 1500}) =>
    ProductSearchResult(lgFAMILLEID: id, strNAME: name, intCIP: cip, intPRICE: price, intNUMBERAVAILABLE: 10, strLIBELLEE: '', intPAF: 0);

// Noms longs : vérifient l'absence de débordement à 360 px.
final _doli = _p('P1', 'DOLIPRANE 1000MG COMPRIMES PELLICULES BOITE DE 8 SECABLES', '3400930000001');
final _effer = _p('P2', 'EFFERALGAN 500MG', '3400930000002', price: 1200);

final _tp = ClientTiersPayant(
    lgTIERSPAYANTID: 'TP1', tpFullName: 'CARNET MUGEF AGENTS ET RETRAITES', taux: 80, numSecurity: 'M-001', compteTp: 'CT1', order: 1, principal: true);
final _client = ClientAssurance(
  lgCLIENTID: 'C1',
  fullName: 'KOUASSI-N\'GUESSAN Awa Marie-Christine',
  strFIRSTNAME: 'KOUASSI-N\'GUESSAN',
  strLASTNAME: 'Awa Marie-Christine',
  strNUMEROSECURITESOCIAL: 'M-001',
  tiersPayants: [_tp],
  ayantDroits: [],
);
const _clientName = 'KOUASSI-N\'GUESSAN Awa Marie-Christine';
AyantDroit _ad(String id, String nom, String prenom) => AyantDroit(
    lgAYANTSDROITSID: id, lgCLIENTID: 'C1', fullName: '$nom $prenom', strFIRSTNAME: nom, strLASTNAME: prenom, strNUMEROSECURITESOCIAL: 'M-001', strSEXE: '');

enum _Mode { ok, failed, lostOnCreate, appliedButFailed }

class _Gw implements VenteGateway {
  Duration delay = const Duration(milliseconds: 30);
  final Map<String, List<SaleItemDetail>> sales = {};
  final Map<String, String> statut = {};
  final List<String?> adds = [];
  final List<({String first, String last, String numSecu})> createdClients = [];
  int creations = 0;
  int clotureCalls = 0;
  bool clientSearchFails = false;
  _Mode addMode = _Mode.ok;

  Future<void> _wait() => Future.delayed(delay);

  SaleItemDetail _line(String venteId, ProductSearchResult p, int qty, int pu) => SaleItemDetail(
        lgPREENREGISTREMENTDETAILID: '$venteId-L${(sales[venteId]?.length ?? 0) + 1}',
        lgFAMILLEID: p.lgFAMILLEID,
        strNAME: p.strNAME,
        intCIP: p.intCIP,
        intQUANTITY: qty,
        intPRICEUNITAIR: pu,
        intPRICE: qty * pu,
        strREF: 'PC-000415',
      );

  @override
  Future<VenteResult<List<ProductSearchResult>>> searchProducts(String query) async {
    await _wait();
    final q = query.toLowerCase();
    return VenteOk([_doli, _effer].where((p) => p.strNAME.toLowerCase().contains(q) || p.intCIP == query).toList());
  }

  @override
  Future<VenteResult<ProductPage>> searchProductsPage(String query, int start, int limit) async {
    final r = await searchProducts(query);
    return r.map((items) => ProductPage(start == 0 ? items : const [], items.length));
  }

  @override
  Future<VenteResult<List<ClientAssurance>>> searchClients(String query, {required String typeClientId}) async {
    await _wait();
    if (clientSearchFails) return const VenteFailed('Serveur injoignable (rechercher le client).');
    final q = query.toLowerCase();
    return VenteOk([_client].where((c) => c.fullName.toLowerCase().contains(q)).toList());
  }

  @override
  Future<VenteResult<List<TiersPayantAssurance>>> searchTiersPayants(String query, {required bool carnet}) async {
    await _wait();
    return VenteOk([TiersPayantAssurance(lgTIERSPAYANTID: 'TP9', strFULLNAME: 'SODECI — CARNET AGENTS ET AYANTS DROIT', strNAME: 'SODECI')]);
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
        ClientTiersPayant(lgTIERSPAYANTID: tiersPayantId, tpFullName: 'SODECI', taux: 100, numSecurity: numSecu, compteTp: 'CT9', order: 1, principal: true)
      ],
      ayantDroits: [],
    ));
  }

  @override
  Future<VenteResult<List<AyantDroit>>> ayantDroits(String clientId) async {
    await _wait();
    return VenteOk([_ad('C1', 'KOUASSI-N\'GUESSAN', 'Awa Marie-Christine'), _ad('AD2', 'KOUASSI', 'Junior')]);
  }

  @override
  Future<VenteResult<AyantDroit>> createAyantDroit(
          {required String clientId, required String firstName, required String lastName, required String numSecu}) async =>
      VenteOk(_ad('AD3', firstName, lastName));

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
    adds.add(venteId);
    await _wait();
    if (addMode == _Mode.failed) return const VenteFailed('Serveur injoignable (ajouter le produit).');
    var id = venteId;
    if (id == null) {
      creations++;
      id = 'V$creations';
      sales[id] = [];
      statut[id] = 'pending';
    }
    final p = [_doli, _effer].firstWhere((p) => p.lgFAMILLEID == produitId);
    sales[id]!.add(_line(id, p, qte, itemPu));
    if (addMode == _Mode.lostOnCreate) return const VenteFailed('Le serveur met trop de temps à répondre.', maybeApplied: true);
    // Ligne enregistrée mais réponse illisible (sans indication « peut-être appliqué »).
    if (addMode == _Mode.appliedButFailed) return const VenteFailed('Réponse illisible.');
    return VenteOk(id);
  }

  @override
  Future<VenteResult<List<SaleItemDetail>>> saleDetails(String venteId) async {
    await _wait();
    return VenteOk(List.of(sales[venteId] ?? const []));
  }

  @override
  Future<VenteResult<AssuranceSaleSummary>> netAssurance({required String venteId, required List<VenteTp> tierspayants}) async {
    await _wait();
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
  Future<VenteResult<void>> updateItem({required String itemId, required String produitId, required int qte, required int itemPu}) async =>
      const VenteOk(null);

  @override
  Future<VenteResult<void>> removeItem(String itemId) async => const VenteOk(null);

  @override
  Future<VenteResult<void>> terminerPrevente(String venteId) async {
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
    await _wait();
    if (statut[venteId] == 'is_Closed') return const VenteRefused('Cette vente a déjà été clôturée');
    statut[venteId] = 'is_Closed';
    return const VenteOk({'success': true});
  }

  @override
  Future<VenteResult<Map<String, dynamic>>> fullSale(String venteId) async {
    await _wait();
    final s = statut[venteId];
    if (s == null) return const VenteFailed('Vente introuvable.');
    return VenteOk({'strSTATUT': s});
  }

  @override
  Future<VenteResult<List<PreventeListItem>>> ventesByType(String typeVenteId) async => const VenteOk([]);

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

Future<void> _open(WidgetTester tester, _Gw gw, {ListPresentation? style}) async {
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
              onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => VenteCarnetScreen(gateway: gw, presentation: style))),
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

Finder get _clientField => find.byKey(const ValueKey('carnet-client-recherche'));
Finder get _continuer => find.byKey(const ValueKey('carnet-continuer'));
Finder get _valider => find.byKey(const ValueKey('carnet-valider'));
Finder get _prevente => find.byKey(const ValueKey('carnet-prevente'));
Finder get _bonField => find.byKey(const ValueKey('carnet-bon-CT1'));
Finder _netText(String t) => find.byWidgetPredicate((w) => w is Text && w.key == const ValueKey('carnet-net') && w.data == t);

bool _enabled(WidgetTester tester, Finder f) => (tester.widget(f) as ButtonStyleButton).onPressed != null;

Color? _bg(WidgetTester tester, Finder f) => (tester.widget(f) as ButtonStyleButton).style?.backgroundColor?.resolve({});

/// Bouton principal : ambre en C, bleu en A et B.
void _expectMainColor(WidgetTester tester, Finder f, ListPresentation style) =>
    expect(_bg(tester, f), style == ListPresentation.guided ? Pal.amber : Pal.navy);

void _expectSteps(ListPresentation style) {
  if (style == ListPresentation.guided) {
    expect(find.byType(StepsBar), findsOneWidget);
  } else {
    expect(find.byType(CarnetStepPills), findsOneWidget);
  }
}

Future<void> _searchClient(WidgetTester tester, String q) async {
  await tester.enterText(_clientField, q);
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
}

Future<void> _toBon(WidgetTester tester) async {
  await _searchClient(tester, 'kouassi');
  await tester.tap(find.text(_clientName));
  await tester.pumpAndSettle();
}

Future<void> _toProducts(WidgetTester tester, {String bon = 'B-123'}) async {
  await _toBon(tester);
  await tester.enterText(_bonField, bon);
  await tester.pump();
  await tester.tap(_continuer);
  await tester.pumpAndSettle();
}

Future<void> _addManual(WidgetTester tester, String query, {String qty = '1', bool settle = true}) async {
  await tester.enterText(find.byKey(const ValueKey('vente-recherche')), query);
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
  await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField)), qty);
  await tester.tap(find.text('Ajouter'));
  if (settle) await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final style in ListPresentation.values) {
    testWidgets('étape Client — ${style.label}', (tester) async {
      _phone(tester);
      final gw = _Gw();
      await _open(tester, gw, style: style);
      _expectSteps(style);
      expect(find.text('Vente carnet'), findsOneWidget);
      expect(_clientField, findsOneWidget);
      expect(find.byKey(const ValueKey('carnet-historique')), findsOneWidget);
      expect(find.text('+ NOUVEAU CLIENT'), findsNothing); // pas avant une réponse du serveur
      expect(find.byTooltip('Présentation'), findsOneWidget);

      await _searchClient(tester, 'kouassi');
      expect(find.text(_clientName), findsOneWidget);
      expect(find.text('Mat. M-001'), findsOneWidget);
      expect(find.textContaining('CARNET MUGEF AGENTS ET RETRAITES 80 %'), findsOneWidget);
      expect(find.text('Choisir'), findsOneWidget);
      expect(find.text('+ NOUVEAU CLIENT'), findsNothing); // le serveur a trouvé des clients

      await _searchClient(tester, 'zzzz');
      expect(find.textContaining('Aucun client carnet'), findsOneWidget);
      expect(find.text('+ NOUVEAU CLIENT'), findsOneWidget);

      gw.clientSearchFails = true;
      await _searchClient(tester, 'kouas');
      expect(find.textContaining('Recherche impossible'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
      expect(find.text('+ NOUVEAU CLIENT'), findsNothing); // panne ≠ « aucun client »
      expect(tester.takeException(), isNull);
    });

    testWidgets('nouveau client carnet en page — ${style.label}', (tester) async {
      _phone(tester);
      final gw = _Gw();
      await _open(tester, gw, style: style);
      await _searchClient(tester, 'DIABATE');
      await tester.tap(find.text('+ NOUVEAU CLIENT'));
      await tester.pumpAndSettle();

      expect(find.text('Nouveau client carnet'), findsOneWidget);
      expect(find.text('Nom *'), findsOneWidget);
      expect(find.text('Prénom(s) *'), findsOneWidget);
      expect(find.text('Matricule *'), findsOneWidget);
      expect(find.text('CARNET CHOISI'), findsOneWidget);
      expect(find.textContaining('Vérifiez avant d\'enregistrer'), findsOneWidget);
      expect(find.text('ANNULER'), findsOneWidget);
      final creer = find.byKey(const ValueKey('carnet-nc-creer'));
      expect(_enabled(tester, creer), isFalse); // carnet pas encore choisi
      expect(tester.widget<TextFormField>(find.byKey(const ValueKey('carnet-nc-nom'))).controller?.text, 'DIABATE');

      await tester.enterText(find.byKey(const ValueKey('carnet-nc-prenom')), 'Moussa');
      await tester.enterText(find.byKey(const ValueKey('carnet-nc-matricule')), '7781');
      await tester.enterText(find.byKey(const ValueKey('carnet-recherche')), 'sod');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SODECI — CARNET AGENTS ET AYANTS DROIT'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('carnet-choisi')), findsOneWidget);
      expect(find.text('Changer'), findsOneWidget);
      expect(gw.createdClients, isEmpty); // choisir le carnet ne crée rien
      expect(_enabled(tester, creer), isTrue);
      _expectMainColor(tester, creer, style);

      await tester.tap(find.text('CRÉER LE CLIENT'));
      await tester.pumpAndSettle();
      expect(gw.createdClients.single, (first: 'DIABATE', last: 'Moussa', numSecu: '7781'));
      expect(find.byKey(const ValueKey('carnet-bon-CT9')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('étape Bon & ayant droit — ${style.label}', (tester) async {
      _phone(tester);
      final gw = _Gw();
      await _open(tester, gw, style: style);
      await _toBon(tester);
      _expectSteps(style);

      // Le client est son propre ayant droit par défaut ; les autres se choisissent.
      expect(find.text('Le client lui-même'), findsOneWidget);
      expect(find.text('✓ Choisi'), findsOneWidget);
      expect(find.text('Choisir'), findsOneWidget);
      expect(find.text('Nouvel ayant droit'), findsOneWidget);
      // La saisie du bon a le focus : la carte client peut être hors de l'écran (liste défilée).
      expect(find.text('Changer de client', skipOffstage: false), findsOneWidget);

      // Continuer désactivé, avec la raison exacte.
      expect(_enabled(tester, _continuer), isFalse);
      expect(find.text('Le N° de bon pour CARNET MUGEF AGENTS ET RETRAITES est requis.'), findsOneWidget);
      await tester.enterText(_bonField, '   ');
      await tester.pump();
      expect(_enabled(tester, _continuer), isFalse);
      await tester.enterText(_bonField, ' B-123 ');
      await tester.pump();
      expect(_enabled(tester, _continuer), isTrue);
      expect(find.byKey(const ValueKey('carnet-continuer-raison')), findsNothing);
      _expectMainColor(tester, _continuer, style);

      await tester.tap(find.text('KOUASSI Junior'));
      await tester.pumpAndSettle();
      expect(find.text('✓ Choisi'), findsOneWidget);
      expect(find.text('Choisir'), findsOneWidget); // le client redevient « Choisir »
      await tester.tap(_continuer);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('vente-recherche')), findsOneWidget);
      expect(find.textContaining('→ KOUASSI Junior'), findsOneWidget); // carte client permanente
      expect(tester.takeException(), isNull);
    });

    testWidgets('étape Produits : carte client, panier, pied fixe — ${style.label}', (tester) async {
      _phone(tester);
      final gw = _Gw();
      await _open(tester, gw, style: style);
      await _toProducts(tester);

      final card = find.byKey(const ValueKey('carnet-carte-client'));
      expect(card, findsOneWidget);
      expect(find.descendant(of: card, matching: find.text(_clientName)), findsOneWidget);
      expect(find.descendant(of: card, matching: find.textContaining('CARNET MUGEF AGENTS ET RETRAITES 80 % · bon B-123')), findsOneWidget);
      expect(find.byKey(const ValueKey('carnet-retour-bons')), findsOneWidget);
      if (style == ListPresentation.guided) expect(find.byType(StepsBar), findsOneWidget);
      if (style == ListPresentation.compact) expect(find.byType(CarnetStepPills), findsOneWidget);
      expect(find.text('Le panier est vide'), findsOneWidget);
      expect(_enabled(tester, _valider), isFalse);

      await _addManual(tester, 'doli', qty: '2');
      await _addManual(tester, 'effer');
      expect(find.text(_doli.strNAME), findsOneWidget);
      expect(find.text('EFFERALGAN 500MG'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('Part carnet 80 %'), findsOneWidget);
      expect(find.text('Part client'), findsOneWidget);
      expect(find.text('${Constants.formatNumber(4200)} F'), findsWidgets); // 3 000 + 1 200
      expect(_netText('840 F'), findsOneWidget);
      expect(find.text('2 articles enregistrés sur le serveur'), findsOneWidget);
      expect(find.text('PRÉVENTE'), findsOneWidget);
      expect(find.text('VALIDER'), findsOneWidget);
      expect(_enabled(tester, _valider), isTrue);
      expect(_enabled(tester, _prevente), isTrue);
      _expectMainColor(tester, _valider, style);
      if (style == ListPresentation.compact) {
        expect(find.text('Toucher une ligne : modifier'), findsOneWidget);
      }

      // « ✎ Bon » : retour à l'étape des bons, puis retour aux produits.
      await tester.tap(find.byKey(const ValueKey('carnet-retour-bons')));
      await tester.pumpAndSettle();
      expect(_bonField, findsOneWidget);
      expect(find.text('Fixé à la création de la vente (panier déjà commencé).'), findsOneWidget);
      await tester.tap(_continuer);
      await tester.pumpAndSettle();
      expect(find.text('EFFERALGAN 500MG'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ligne non enregistrée : ambre, bloque VALIDER, « Réessayer » — ${style.label}', (tester) async {
      _phone(tester);
      final gw = _Gw();
      await _open(tester, gw, style: style);
      await _toProducts(tester);
      await _addManual(tester, 'doli');
      gw.addMode = _Mode.failed;
      await _addManual(tester, 'effer');
      expect(find.textContaining('injoignable'), findsOneWidget);
      expect(find.textContaining('non enregistrée'), findsWidgets);
      expect(find.text('1 ligne non enregistrée sur le serveur.'), findsOneWidget);
      expect(_enabled(tester, _valider), isFalse);
      expect(_enabled(tester, _prevente), isFalse);
      expect(find.text('1 ligne non enregistrée : touchez « Réessayer » ou retirez-la.'), findsOneWidget);

      gw.addMode = _Mode.ok;
      await tester.pump(const Duration(seconds: 7)); // fin du bandeau d'erreur
      await tester.pumpAndSettle();
      await tester.tap(find.text('Réessayer').first);
      await tester.pumpAndSettle();
      expect(gw.sales['V1']!.length, 2);
      expect(find.textContaining('non enregistrée'), findsNothing);
      expect(_enabled(tester, _valider), isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('« Réessayer » une ligne déjà enregistrée sur le serveur : relecture, aucun doublon', (tester) async {
    _phone(tester);
    final gw = _Gw();
    await _open(tester, gw);
    await _toProducts(tester);
    await _addManual(tester, 'doli');
    gw.addMode = _Mode.appliedButFailed; // la ligne est enregistrée mais la réponse est illisible
    await _addManual(tester, 'effer');
    expect(find.textContaining('non enregistrée'), findsWidgets);
    gw.addMode = _Mode.ok;
    final before = gw.adds.length;
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Réessayer').first);
    await tester.pumpAndSettle();
    expect(gw.adds.length, before); // rien renvoyé
    expect(gw.sales['V1']!.length, 2);
    expect(find.textContaining('déjà enregistré'), findsOneWidget);
    expect(_enabled(tester, _valider), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('vente peut-être créée sans réponse : pas de « Réessayer » (jamais de 2ᵉ vente)', (tester) async {
    _phone(tester);
    final gw = _Gw()..addMode = _Mode.lostOnCreate;
    await _open(tester, gw);
    await _toProducts(tester);
    await _addManual(tester, 'doli');
    expect(find.textContaining('peut-être été créée'), findsOneWidget);
    expect(find.textContaining('non enregistrée'), findsNothing);
    expect(gw.creations, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('« Calcul… » pendant le recalcul du net : PRÉVENTE et VALIDER désactivés', (tester) async {
    _phone(tester);
    final gw = _Gw();
    await _open(tester, gw);
    await _toProducts(tester);
    await _addManual(tester, 'doli');
    gw.delay = const Duration(milliseconds: 300);
    await _addManual(tester, 'effer', settle: false);
    await tester.pump(const Duration(milliseconds: 400)); // ajout fait, relecture + net en cours
    expect(_netText('Calcul…'), findsOneWidget);
    expect(_enabled(tester, _valider), isFalse);
    expect(_enabled(tester, _prevente), isFalse);
    await tester.pumpAndSettle();
    expect(_netText('540 F'), findsOneWidget);
    expect(_enabled(tester, _valider), isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final style in ListPresentation.values) {
    testWidgets('double tap sur VALIDER : une seule clôture — ${style.label}', (tester) async {
      _phone(tester);
      final gw = _Gw();
      await _open(tester, gw, style: style);
      await _toProducts(tester);
      await _addManual(tester, 'doli');
      gw.delay = const Duration(milliseconds: 150);
      await tester.tap(_valider);
      await tester.tap(_valider, warnIfMissed: false);
      await tester.pump();
      expect(_enabled(tester, _valider), isFalse);
      await tester.pumpAndSettle();
      expect(find.text('Vente carnet validée'), findsOneWidget);
      await tester.tap(find.text('Non'));
      await tester.pumpAndSettle();
      expect(gw.clotureCalls, 1);
      expect(_clientField, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('menu « Présentation » : choix mémorisé, barre d\'étapes C', (tester) async {
    _phone(tester);
    final gw = _Gw();
    await _open(tester, gw);
    expect(find.byType(CarnetStepPills), findsOneWidget); // A par défaut
    await tester.tap(find.byTooltip('Présentation'));
    await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate((w) => w is CheckedPopupMenuItem<ListPresentation> && w.value == ListPresentation.guided));
    await tester.pumpAndSettle();
    expect(await PresentationPrefs.load(), ListPresentation.guided);
    expect(find.byType(StepsBar), findsOneWidget);
    expect(find.text('Bon & ayant droit'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
