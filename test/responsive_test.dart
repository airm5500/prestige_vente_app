// Adaptation tablette (Sunmi) : à 360 × 800, rendu strictement identique à la version d'origine
// (textes et positions comparés à test/responsive_reference_360.json) ; à 800 × 1280 (tablette portrait)
// et 1280 × 800 (tablette paysage), en A / B / C : aucune erreur de rendu, contenu centré à largeur
// maximale, grilles de cartes, panier à droite de la recherche, rubriques à gauche des réglages.
// Régénérer la référence (sur la version d'origine seulement) :
//   flutter test test/responsive_test.dart --dart-define=RESPONSIVE_REF=ecrire
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/accueil/accueil_screen.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/assurance_sale_summary.dart';
import 'package:prestige_vente_app/api/models/ayant_droit.dart';
import 'package:prestige_vente_app/api/models/bon_livraison.dart';
import 'package:prestige_vente_app/api/models/client_assurance.dart';
import 'package:prestige_vente_app/api/models/licence_model.dart';
import 'package:prestige_vente_app/api/models/officine.dart';
import 'package:prestige_vente_app/api/models/payment_method_qr.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/api/models/user.dart';
import 'package:prestige_vente_app/parametres/parametres_screen.dart';
import 'package:prestige_vente_app/parametres/parametres_services.dart';
import 'package:prestige_vente_app/pointage/pointage_repository.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/bl_control_provider.dart';
import 'package:prestige_vente_app/providers/licence_provider.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/reception/reception_gateway.dart';
import 'package:prestige_vente_app/reception/reception_logic.dart';
import 'package:prestige_vente_app/reception/reception_models.dart';
import 'package:prestige_vente_app/screens/reception_bl/reception_home_screen.dart';
import 'package:prestige_vente_app/ventes/assurance/vente_assurance_screen.dart';
import 'package:prestige_vente_app/ventes/carnet/vente_carnet_screen.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/ventes/prevente/prevente_list.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/responsive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Tailles d'écran
// ---------------------------------------------------------------------------

const _phone = Size(360, 800);
const _portrait = Size(800, 1280);
const _paysage = Size(1280, 800);

void _screen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

// ---------------------------------------------------------------------------
// Serveur de vente simulé (comptant, assurance, carnet)
// ---------------------------------------------------------------------------

ProductSearchResult _p(String id, String name, String cip, {int price = 1500, int stock = 10}) =>
    ProductSearchResult(lgFAMILLEID: id, strNAME: name, intCIP: cip, intPRICE: price, intNUMBERAVAILABLE: stock, strLIBELLEE: '', intPAF: 0);

final _doli = _p('P1', 'DOLIPRANE 1000MG CP B/8', '3400930000001');
final _effer = _p('P2', 'EFFERALGAN 500MG', '3400930000002', price: 1000);

ClientTiersPayant _ctp(String id, String name, String compte, int taux, int order) =>
    ClientTiersPayant(lgTIERSPAYANTID: id, tpFullName: name, taux: taux, numSecurity: 'MAT-$compte', compteTp: compte, order: order, principal: order == 1);

AyantDroit _ad(String id, String first, String last) =>
    AyantDroit(lgAYANTSDROITSID: id, lgCLIENTID: 'C1', fullName: '$first $last', strFIRSTNAME: first, strLASTNAME: last, strNUMEROSECURITESOCIAL: 'M-$id', strSEXE: '');

class _Gw implements VenteGateway {
  /// Vente carnet : un seul tiers payant (champ de bon unique).
  final bool carnet;
  _Gw({this.carnet = false});

  final Map<String, List<SaleItemDetail>> sales = {};
  final Map<String, String> statut = {};
  int creations = 0;

  Future<void> _wait() => Future.delayed(const Duration(milliseconds: 20));

  ClientAssurance get client => ClientAssurance(
        lgCLIENTID: 'C1',
        fullName: 'KOUASSI Awa',
        strFIRSTNAME: 'KOUASSI',
        strLASTNAME: 'Awa',
        strNUMEROSECURITESOCIAL: 'MAT1',
        tiersPayants: carnet ? [_ctp('TP1', 'CARNET MUGEF', 'CT1', 80, 1)] : [_ctp('TP1', 'MCI', 'CT1', 70, 1), _ctp('TP2', 'ASCOMA', 'CT2', 10, 2)],
        ayantDroits: carnet ? [] : [_ad('C1', 'KOUASSI', 'Awa'), _ad('AD2', 'KOUASSI', 'Junior')],
      );

  SaleItemDetail line(String venteId, ProductSearchResult p, int qty) => SaleItemDetail(
        lgPREENREGISTREMENTDETAILID: '$venteId-L${(sales[venteId]?.length ?? 0) + 1}',
        lgFAMILLEID: p.lgFAMILLEID,
        strNAME: p.strNAME,
        intCIP: p.intCIP,
        intQUANTITY: qty,
        intPRICEUNITAIR: p.intPRICE,
        intPRICE: qty * p.intPRICE,
        strREF: 'REF-$venteId',
      );

  /// Vente comptant déjà commencée (reprise) : deux lignes.
  void seed(String id) {
    sales[id] = [];
    sales[id]!.add(line(id, _doli, 2));
    sales[id]!.add(line(id, _effer, 1));
    statut[id] = 'pending';
  }

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
  Future<VenteResult<List<SaleItemDetail>>> saleDetails(String venteId) async {
    await _wait();
    return VenteOk(List.of(sales[venteId] ?? const []));
  }

  @override
  Future<VenteResult<SaleSummary>> netVno(String venteId) async {
    await _wait();
    final total = (sales[venteId] ?? const []).fold<int>(0, (s, i) => s + i.intPRICE);
    return VenteOk(SaleSummary(montant: total, montantNet: total, venteId: venteId, reference: 'REF-$venteId'));
  }

  @override
  Future<VenteResult<Map<String, dynamic>>> fullSale(String venteId) async {
    await _wait();
    final s = statut[venteId];
    if (s == null) return const VenteFailed('Vente introuvable.');
    return VenteOk({'strSTATUT': s});
  }

  @override
  Future<VenteResult<List<PaymentMethod>>> paymentMethods() async {
    await _wait();
    return VenteOk([
      PaymentMethod(id: '1', name: 'Espèces'),
      PaymentMethod(id: '10', name: 'WAVE'),
      PaymentMethod(id: '7', name: 'ORANGE'),
      PaymentMethod(id: '4', name: 'CHEQUE'),
    ]);
  }

  @override
  Future<VenteResult<List<PaymentMethodQr>>> paymentMethodsWithQr() async => const VenteOk([]);

  @override
  Future<VenteResult<List<PreventeListItem>>> preventes() async => const VenteOk([]);

  @override
  Future<VenteResult<List<PreventeListItem>>> ventesByType(String typeVenteId) async => const VenteOk([]);

  @override
  Future<VenteResult<List<ClientAssurance>>> searchClients(String query, {required String typeClientId}) async {
    await _wait();
    return VenteOk([client].where((c) => c.fullName.toLowerCase().contains(query.toLowerCase())).toList());
  }

  @override
  Future<VenteResult<List<AyantDroit>>> ayantDroits(String clientId) async {
    await _wait();
    return VenteOk(carnet ? [_ad('C1', 'KOUASSI', 'Awa'), _ad('AD2', 'KOUASSI', 'Junior')] : const []);
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
    await _wait();
    var id = venteId;
    if (id == null) {
      creations++;
      id = 'V$creations';
      sales[id] = [];
      statut[id] = 'pending';
    }
    sales[id]!.add(line(id, [_doli, _effer].firstWhere((p) => p.lgFAMILLEID == produitId), qte));
    return VenteOk(id);
  }

  @override
  Future<VenteResult<AssuranceSaleSummary>> netAssurance({required String venteId, required List<VenteTp> tierspayants}) async {
    await _wait();
    final total = (sales[venteId] ?? const []).fold<int>(0, (s, i) => s + i.intPRICE);
    final parts = [
      for (final tp in tierspayants) TiersPayantSummary(numBon: tp.numBon, taux: tp.taux, compteTp: tp.compteTp, tpnet: total * tp.taux ~/ 100),
    ];
    final tp = parts.fold<int>(0, (s, t) => s + t.tpnet).clamp(0, total);
    return VenteOk(AssuranceSaleSummary(montant: total, montantTp: tp, montantNet: total - tp, tierspayants: parts));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

class _Auth extends AuthProvider {
  _Auth() : super(ApiService(baseUrl: 'http://localhost'));
  @override
  User? get user => User(userId: 'U1', login: 'awa', firstName: 'Awa', lastName: 'Kouassi', officineName: 'TEST');
  @override
  Officine? get officine => Officine(fullName: 'KONAN KOU', nomComplet: 'PHCIE TEST');
}

/// Ouvre [screen] par-dessus une page d'accueil (bouton Retour comme dans l'application).
Future<void> _push(WidgetTester tester, Widget Function() screen) async {
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
              onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => screen())),
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

Future<void> _addProduct(WidgetTester tester, String query, {String qty = '1'}) async {
  await tester.enterText(find.byKey(const ValueKey('vente-recherche')), query);
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
  await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField)), qty);
  await tester.tap(find.text('Ajouter'));
  await tester.pumpAndSettle();
}

Future<void> _searchClient(WidgetTester tester, Key field, String q) async {
  await tester.enterText(find.byKey(field), q);
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
}

// --- Écrans de l'échantillon ---

Future<void> _vente(WidgetTester tester, ListPresentation style) async {
  final gw = _Gw()..seed('V9');
  await _push(tester, () => VenteScreen(gateway: gw, presentation: style, resumeVenteId: 'V9'));
}

Future<void> _encaissement(WidgetTester tester, ListPresentation style) async {
  await _vente(tester, style);
  await tester.tap(find.byKey(const ValueKey('vente-encaisser')));
  await tester.pumpAndSettle();
}

Future<void> _assurance(WidgetTester tester, ListPresentation style) async {
  final gw = _Gw();
  await _push(tester, () => VenteAssuranceScreen(gateway: gw, presentation: style));
  await _searchClient(tester, const ValueKey('assurance-client-recherche'), 'kou');
  await tester.tap(find.text('KOUASSI Awa'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('assurance-bon-CT1')), 'B-1');
  await tester.enterText(find.byKey(const ValueKey('assurance-bon-CT2')), 'B-2');
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('assurance-continuer')));
  await tester.pumpAndSettle();
  await _addProduct(tester, 'doli', qty: '2');
}

Future<void> _carnet(WidgetTester tester, ListPresentation style) async {
  final gw = _Gw(carnet: true);
  await _push(tester, () => VenteCarnetScreen(gateway: gw, presentation: style));
  await _searchClient(tester, const ValueKey('carnet-client-recherche'), 'kouassi');
  await tester.tap(find.text('KOUASSI Awa'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('carnet-bon-CT1')), 'B-123');
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('carnet-continuer')));
  await tester.pumpAndSettle();
  await _addProduct(tester, 'doli', qty: '2');
}

final _preventes = [
  for (var i = 0; i < 5; i++)
    PreventeListItem(
        lgPREENREGISTREMENTID: 'p$i', heure: '09:1$i:00', dtUPDATED: '10/10/2026', intPRICE: 1000 * (i + 1), strREF: 'PV-00$i', userFullName: 'Koffi', lgTYPEVENTEID: '1'),
];

Future<void> _preventeList(WidgetTester tester, ListPresentation style) =>
    _push(tester, () => PreventeListScreen(load: () async => VenteOk(_preventes), onSelect: (_) async => false, presentation: style));

// --- Accueil ---

class _AccueilApi extends ApiService {
  _AccueilApi() : super(baseUrl: 'http://localhost');

  @override
  Future<Officine?> fetchOfficineInfo() async => Officine(fullName: 'KONAN KOU', nomComplet: 'PHARMACIE LES PALMIERS');

  @override
  Future<List<PreventeListItem>> getPreventes() async => _preventes.take(3).toList();

  @override
  Future<List<BonLivraison>> getBonsLivraison({String query = '', String? dtStart, String? dtEnd}) async => [
        BonLivraison(id: 'b1', ref: 'BL1', grossiste: 'LABOREX', date: '', nbreLignes: 3, montantTotal: 0, statutTraitement: 'EN_COURS', strStatut: ''),
        BonLivraison(id: 'b2', ref: 'BL2', grossiste: 'COPHARMED', date: '', nbreLignes: 3, montantTotal: 0, statutTraitement: 'A_FAIRE', strStatut: ''),
      ];
}

class _Licence extends LicenceProvider {
  _Licence(super.api);
  @override
  LicenceStatus get status => LicenceStatus.valid;
  @override
  LicenceModel? get licence => LicenceModel(id: '1', dateStart: '', dateEnd: '', typeLicence: '');
  @override
  int get remainingDays => 21;
  @override
  Future<bool> mustBlockAccess() async => false;
  @override
  void checkReminders(BuildContext context) {}
}

Future<void> _accueil(WidgetTester tester, ListPresentation style) async {
  final api = _AccueilApi();
  final settings = SettingsProvider();
  await settings.saveMenuConfig(const [], const []);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsProvider>.value(value: settings),
      Provider<ApiService>.value(value: api),
      ChangeNotifierProvider<LicenceProvider>.value(value: _Licence(api)),
      ChangeNotifierProvider(create: (_) => AuthProvider(api)),
      ChangeNotifierProvider(create: (_) => SaleProvider(api)),
      ChangeNotifierProvider(create: (_) => BlControlProvider(api)),
    ],
    child: MaterialApp(home: AccueilScreen(presentation: style, serverCheck: () async => true)),
  ));
  await tester.pumpAndSettle();
}

// --- Réglages ---

Future<void> _reglages(WidgetTester tester, ListPresentation style) async {
  SharedPreferences.setMockInitialValues({'presentation_listes_v1': style.name});
  final api = ApiService(baseUrl: 'http://localhost');
  final settings = SettingsProvider();
  await settings.loadSettings();
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsProvider>.value(value: settings),
      Provider<ApiService>.value(value: api),
      ChangeNotifierProvider<LicenceProvider>(create: (_) => LicenceProvider(api)),
      ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider(api)),
      ChangeNotifierProvider<SaleProvider>(create: (_) => SaleProvider(api)),
    ],
    child: MaterialApp(
      home: ParametresScreen(
        services: ParametresServices(
          adminCheck: (_) async => true,
          printTestTicket: (_) async {},
          hardwareInfo: () async => {'manufacturer': 'SUNMI', 'model': 'V2s', 'android': '11', 'sdk': 30},
          pointageRepository: MemoryPointageRepository(),
          afterServerSaved: (_) {},
          organiserAccueil: () => const Scaffold(body: Text('ORGANISER (test)')),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

// --- Réception BL ---

class _Reception implements ReceptionGateway {
  @override
  Future<List<ReceptionBl>> bls({String query = ''}) async => const [
        ReceptionBl(id: 'bl1', ref: 'BL-778', grossiste: 'LABOREX'),
        ReceptionBl(id: 'bl2', ref: 'BL-779', grossiste: 'COPHARMED'),
        ReceptionBl(id: 'bl3', ref: 'BL-780', grossiste: 'DPCI'),
      ];

  @override
  Future<List<ReceptionOrder>> orders() async => const [
        ReceptionOrder(id: 'o1', ref: 'CMD-12', grossiste: 'COPHARMED', products: 3, amount: 45000, statut: 'passed'),
        ReceptionOrder(id: 'o2', ref: 'CMD-13', grossiste: 'LABOREX', products: 5, amount: 72000, statut: 'passed'),
        ReceptionOrder(id: 'o3', ref: 'CMD-14', grossiste: 'DPCI', products: 2, amount: 18000, statut: 'passed'),
        ReceptionOrder(id: 'o4', ref: 'CMD-15', grossiste: 'TEDIS', products: 7, amount: 99000, statut: 'passed'),
      ];

  @override
  Future<List<ReceptionLine>> lines(String blId, {String query = ''}) async =>
      [ReceptionLine(detailId: 'd-$blId', produitId: 'p1', name: 'DOLIPRANE 1000MG CP', code: '3595583', ordered: 24, blRef: blId)];

  @override
  Future<bool> canValidate() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

Future<void> _receptionBl(WidgetTester tester, ListPresentation style) async {
  await tester.pumpWidget(MaterialApp(
    home: ReceptionHomeScreen(gateway: _Reception(), settings: const ReceptionSettings(), clock: () => DateTime(2026, 10, 10, 9), presentation: style),
  ));
  await tester.pumpAndSettle();
}

typedef _Open = Future<void> Function(WidgetTester tester, ListPresentation style);

final Map<String, _Open> _sample = {
  'vente': _vente,
  'encaissement': _encaissement,
  'assurance': _assurance,
  'carnet': _carnet,
  'accueil': _accueil,
  'reglages': _reglages,
  'reception_bl': _receptionBl,
  'preventes': _preventeList,
};

// ---------------------------------------------------------------------------
// Empreinte du rendu : chaque texte affiché et sa place exacte
// ---------------------------------------------------------------------------

String _today() {
  try {
    return DateFormat('EEE d MMMM', 'fr_FR').format(DateTime.now());
  } catch (_) {
    return DateFormat('dd/MM/yyyy').format(DateTime.now());
  }
}

List<String> _fingerprint(WidgetTester tester) {
  final today = _today();
  final out = <String>[];
  for (final e in find.byType(RichText).evaluate()) {
    final ro = e.renderObject;
    if (ro is! RenderParagraph || !ro.attached || !ro.hasSize) continue;
    final o = ro.localToGlobal(Offset.zero);
    String f(double v) => v.toStringAsFixed(1);
    final text = ro.text.toPlainText().replaceAll(today, '<date>');
    out.add('$text @ ${f(o.dx)},${f(o.dy)} ${f(ro.size.width)}x${f(ro.size.height)}');
  }
  return out;
}

const _refMode = String.fromEnvironment('RESPONSIVE_REF');
final _refFile = File('test/responsive_reference_360.json');

/// Rendu moyen : contenu dans la colonne centrée de 720 dp.
void _expectCentered(WidgetTester tester, Finder f, Size size) {
  final r = tester.getRect(f);
  final inset = (size.width - 720) / 2;
  expect(r.left, greaterThanOrEqualTo(inset), reason: 'contenu centré à 720 dp');
  expect(r.right, lessThanOrEqualTo(size.width - inset), reason: 'contenu centré à 720 dp');
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  setUp(() => SharedPreferences.setMockInitialValues({
        'enabled_payment_method_ids': ['1', '10', '7', '4'],
      }));

  group('Points de rupture', () {
    test('compact < 600, moyen 600-899, large ≥ 900', () {
      expect(Responsive.classOf(360), WindowClass.compact);
      expect(Responsive.classOf(599.9), WindowClass.compact);
      expect(Responsive.classOf(600), WindowClass.medium);
      expect(Responsive.classOf(899), WindowClass.medium);
      expect(Responsive.classOf(900), WindowClass.expanded);
      expect(Responsive.classOf(1280), WindowClass.expanded);
      expect(Responsive.maxWidth(WindowClass.compact), isNull);
      expect(Responsive.maxWidth(WindowClass.medium), 720);
      expect(Responsive.maxWidth(WindowClass.expanded), 960);
    });

    testWidgets('cardRows : identique en une colonne, rangées de N cartes sinon', (tester) async {
      final cards = [for (var i = 0; i < 5; i++) Text('c$i')];
      expect(cardRows(cards, 1), same(cards));
      final rows = cardRows(cards, 3);
      expect(rows, hasLength(2));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ListView(children: rows))));
      expect(tester.getTopLeft(find.text('c0')).dy, tester.getTopLeft(find.text('c2')).dy);
      expect(tester.getTopLeft(find.text('c3')).dy, greaterThan(tester.getTopLeft(find.text('c0')).dy));
    });

    for (final size in [_phone, _portrait, _paysage]) {
      testWidgets('dialogues : largeur raisonnable — ${size.width.toInt()} px', (tester) async {
        _screen(tester, size);
        await tester.pumpWidget(MaterialApp(
          builder: (context, child) => ResponsiveTheme(child: child!),
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: ctx,
                    builder: (_) => AlertDialog(title: const Text('Titre'), content: Text('Un texte assez long pour remplir toute la largeur disponible de la fenêtre ' * 4)),
                  ),
                  child: const Text('Ouvrir'),
                ),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('Ouvrir'));
        await tester.pumpAndSettle();
        final w = tester.getSize(find.descendant(of: find.byType(AlertDialog), matching: find.byType(Material)).first).width;
        if (size.width < 600) {
          expect(w, size.width - 80); // inchangé : marges d'origine (40 px)
        } else {
          expect(w, lessThanOrEqualTo(Responsive.dialogMaxWidth));
        }
        expect(tester.takeException(), isNull);
      });
    }
  });

  // -------------------------------------------------------------------------
  // 360 × 800 : rendu identique à l'origine
  // -------------------------------------------------------------------------
  group('360 × 800 : rendu identique', () {
    final Map<String, dynamic> reference = _refFile.existsSync() ? jsonDecode(_refFile.readAsStringSync()) as Map<String, dynamic> : {};
    final Map<String, List<String>> written = {};

    tearDownAll(() {
      if (_refMode == 'ecrire') {
        final sorted = {for (final k in (written.keys.toList()..sort())) k: written[k]};
        _refFile.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(sorted));
      }
    });

    for (final entry in _sample.entries) {
      for (final style in ListPresentation.values) {
        final id = '${entry.key}/${style.name}';
        testWidgets('$id : mêmes textes aux mêmes places', (tester) async {
          _screen(tester, _phone);
          await entry.value(tester, style);
          expect(tester.takeException(), isNull);
          final fp = _fingerprint(tester);
          expect(fp, isNotEmpty);
          if (_refMode == 'ecrire') {
            written[id] = fp;
            return;
          }
          expect(reference.containsKey(id), isTrue, reason: 'référence absente pour $id');
          expect(fp, List<String>.from(reference[id] as List), reason: 'rendu modifié à 360 px pour $id');
        });
      }
    }
  });

  // -------------------------------------------------------------------------
  // Tablettes : aucune erreur, contenu centré, disposition adaptée
  // -------------------------------------------------------------------------
  for (final size in [_portrait, _paysage]) {
    final large = size.width >= 900;
    final label = large ? 'tablette paysage 1280 × 800' : 'tablette portrait 800 × 1280';
    group(label, () {
      for (final entry in _sample.entries) {
        for (final style in ListPresentation.values) {
          testWidgets('${entry.key} — ${style.label} : rendu sans erreur', (tester) async {
            _screen(tester, size);
            await entry.value(tester, style);
            expect(tester.takeException(), isNull);
          });
        }
      }

      for (final style in ListPresentation.values) {
        testWidgets('vente — ${style.label} : ${large ? 'recherche à gauche, panier à droite' : 'une colonne centrée'}', (tester) async {
          _screen(tester, size);
          await _vente(tester, style);
          final search = find.byKey(const ValueKey('vente-recherche'));
          final cart = find.text('DOLIPRANE 1000MG CP B/8');
          expect(search, findsOneWidget);
          expect(cart, findsOneWidget);
          if (large) {
            expect(find.byKey(const ValueKey('vente-panneau-recherche')), findsOneWidget);
            expect(tester.getRect(search).right, lessThan(tester.getRect(cart).left));
          } else {
            expect(find.byKey(const ValueKey('vente-panneau-recherche')), findsNothing);
            expect(tester.getRect(search).bottom, lessThan(tester.getRect(cart).top));
            _expectCentered(tester, search, size);
            _expectCentered(tester, cart, size);
          }
          // Actions fixées : centrées à la largeur du contenu.
          final enc = tester.getRect(find.byKey(const ValueKey('vente-encaisser')));
          final pre = tester.getRect(find.byKey(const ValueKey('vente-enregistrer-prevente')));
          expect((pre.left - (size.width - enc.right)).abs(), lessThan(2));
          expect(enc.right, lessThan(size.width - 40));
          expect(tester.takeException(), isNull);
        });

        testWidgets('encaissement — ${style.label} : ${large ? 'modes en 4 colonnes, résumé à côté' : 'modes en 2 colonnes'}', (tester) async {
          _screen(tester, size);
          await _encaissement(tester, style);
          final tops = [for (final m in ['Espèces', 'WAVE', 'ORANGE', 'CHEQUE']) tester.getTopLeft(find.text(m).first).dy];
          if (large) {
            expect(tops.toSet(), hasLength(1), reason: '4 modes sur une rangée');
            final resume = find.byKey(const ValueKey('encaissement-resume'));
            expect(resume, findsOneWidget);
            expect(tester.getRect(resume).left, greaterThan(tester.getRect(find.text('CHEQUE').first).right));
          } else {
            expect(tops.toSet(), hasLength(2), reason: '2 modes par rangée');
            expect(find.byKey(const ValueKey('encaissement-resume')), findsNothing);
          }
          expect(tester.takeException(), isNull);
        });

        testWidgets('assurance — ${style.label} : ${large ? 'carte client et recherche à gauche, panier à droite' : 'carte client dans l\'en-tête'}', (tester) async {
          _screen(tester, size);
          await _assurance(tester, style);
          final card = find.byKey(const ValueKey('assurance-carte-client'));
          final line = find.text('DOLIPRANE 1000MG CP B/8');
          expect(card, findsOneWidget);
          expect(line, findsOneWidget);
          if (large) {
            expect(tester.getRect(card).right, lessThan(tester.getRect(line).left));
            expect(tester.getRect(find.byKey(const ValueKey('vente-recherche'))).right, lessThan(tester.getRect(line).left));
          } else {
            expect(tester.getRect(card).bottom, lessThan(tester.getRect(line).top));
          }
          expect(tester.takeException(), isNull);
        });

        testWidgets('carnet — ${style.label} : ${large ? 'client et recherche à gauche, panier à droite' : 'une colonne'}', (tester) async {
          _screen(tester, size);
          await _carnet(tester, style);
          final search = find.byKey(const ValueKey('vente-recherche'));
          final line = find.text('DOLIPRANE 1000MG CP B/8');
          if (large) {
            expect(tester.getRect(search).right, lessThan(tester.getRect(line).left));
            expect(find.byKey(const ValueKey('carnet-panneau-client')), findsOneWidget);
          } else {
            expect(tester.getRect(search).bottom, lessThan(tester.getRect(line).top));
          }
          expect(tester.takeException(), isNull);
        });

        testWidgets('préventes — ${style.label} : cartes en ${style == ListPresentation.compact ? 1 : (large ? 3 : 2)} colonne(s)', (tester) async {
          _screen(tester, size);
          await _preventeList(tester, style);
          final y0 = tester.getTopLeft(find.text('PV-000')).dy;
          final sameRow = [for (var i = 0; i < 5; i++) if (tester.getTopLeft(find.text('PV-00$i')).dy == y0) i];
          expect(sameRow.length, style == ListPresentation.compact ? 1 : (large ? 3 : 2));
          expect(tester.takeException(), isNull);
        });

        testWidgets('réception BL — ${style.label} : contenu centré, cartes en grille', (tester) async {
          _screen(tester, size);
          await _receptionBl(tester, style);
          if (style != ListPresentation.compact) {
            final a = tester.getTopLeft(find.textContaining('CMD-12').first);
            final b = tester.getTopLeft(find.textContaining('CMD-13').first);
            expect((a.dy - b.dy).abs(), lessThan(24), reason: 'deux commandes sur la même rangée');
            expect(b.dx, greaterThan(a.dx));
          } else {
            expect(tester.getTopLeft(find.textContaining('CMD-12').first).dx, greaterThan(40)); // centré
          }
          expect(tester.takeException(), isNull);
        });

        testWidgets('accueil — ${style.label} : familles, favoris et cloche de notifications', (tester) async {
          _screen(tester, size);
          await _accueil(tester, style);
          if (style == ListPresentation.dashboard) {
            final grids = tester.widgetList<GridView>(find.byType(GridView)).map((g) => (g.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount).crossAxisCount).toList();
            expect(grids.last, large ? 8 : 6, reason: 'tuiles des familles');
            // Retour client : « À faire maintenant » remplacé par la cloche de l'en-tête.
            expect(find.byKey(const ValueKey('accueil-a-faire')), findsNothing);
            expect(find.byKey(const Key('accueil_cloche')), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        });

        testWidgets('réglages — ${style.label} : ${large ? 'rubriques à gauche, contenu à droite' : 'page de rubrique'}', (tester) async {
          _screen(tester, size);
          await _reglages(tester, style);
          await tester.tap(find.byKey(const Key('rubrique_impression')));
          await tester.pumpAndSettle();
          if (large) {
            expect(find.byKey(const Key('rubrique_impression')), findsOneWidget, reason: 'liste toujours visible');
            final page = find.byKey(const ValueKey('reglages-detail'));
            expect(page, findsOneWidget);
            expect(tester.getRect(find.byKey(const Key('rubrique_impression'))).right, lessThanOrEqualTo(tester.getRect(page).left));
            expect(find.descendant(of: page, matching: find.text('Impression')), findsWidgets);
            expect(find.descendant(of: page, matching: find.byTooltip('Retour')), findsNothing);
          } else {
            expect(find.byKey(const Key('rubrique_impression')), findsNothing, reason: 'page ouverte par-dessus');
            expect(find.byTooltip('Retour'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        });
      }
    });
  }
}
