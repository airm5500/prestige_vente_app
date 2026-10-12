// Saisie dans une vente, clavier ouvert (retour client : « le clavier cache le bas, il faut appuyer sur
// la touche recherche pour voir le bas de l'écran ») :
// - en-tête réduit (tuiles / chiffres / étapes masqués ; articles · boîtes · total sur une ligne dans le pied) ;
// - panier redimensionné et visible, total + Prévente / Encaisser posés au-dessus du clavier ;
// - défiler le panier ou toucher hors champ ferme le clavier SANS retirer le curseur (douchette) ;
// - après une vente validée, le curseur revient dans la recherche (fonction existante conservée) ;
// - même mécanisme (opt-in) pour les cadres Assurance et Carnet ; écrans non concernés inchangés.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/payment_method_qr.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/api/models/user.dart';
import 'package:prestige_vente_app/horsligne/catalogue_sync.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart';
import 'package:prestige_vente_app/horsligne/server_monitor.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProductSearchResult _p(String id, String name, String cip, int price) =>
    ProductSearchResult(lgFAMILLEID: id, strNAME: name, intCIP: cip, intPRICE: price, intNUMBERAVAILABLE: 50, strLIBELLEE: '', intPAF: 0);

final _catalogue = [
  _p('P1', 'DOLIPRANE 1000MG CP B/8', '3400930000001', 1500),
  _p('P2', 'EFFERALGAN 500MG CP B/16', '3400930000002', 900),
  _p('P3', 'SMECTA SACHETS B/30', '3400930000003', 600),
];

class _Gw implements VenteGateway {
  final Map<String, List<SaleItemDetail>> sales = {};
  int creations = 0;
  int terminerCalls = 0;

  Future<void> _wait() => Future.delayed(const Duration(milliseconds: 20));

  @override
  Future<VenteResult<List<ProductSearchResult>>> searchProducts(String query) async {
    await _wait();
    final q = query.toLowerCase().replaceAll('%', ''); // « Commence par » / « Contient »
    return VenteOk(_catalogue.where((p) => p.strNAME.toLowerCase().contains(q) || p.intCIP == query).toList());
  }

  @override
  Future<VenteResult<ProductPage>> searchProductsPage(String query, int start, int limit) async {
    final r = await searchProducts(query);
    return r.map((items) => ProductPage(start == 0 ? items : const [], items.length));
  }

  @override
  Future<VenteResult<String>> addItemVno({required String produitId, required int qte, required int itemPu, String? venteId, required bool prevente}) async {
    await _wait();
    var id = venteId;
    if (id == null) {
      creations++;
      id = 'V$creations';
      sales[id] = [];
    }
    final p = _catalogue.firstWhere((p) => p.lgFAMILLEID == produitId);
    sales[id]!.add(SaleItemDetail(
      lgPREENREGISTREMENTDETAILID: '$id-L${sales[id]!.length + 1}',
      lgFAMILLEID: p.lgFAMILLEID,
      strNAME: p.strNAME,
      intCIP: p.intCIP,
      intQUANTITY: qte,
      intPRICEUNITAIR: itemPu,
      intPRICE: qte * itemPu,
      strREF: 'REF-$id',
    ));
    return VenteOk(id);
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
  Future<VenteResult<void>> terminerPrevente(String venteId) async {
    terminerCalls++;
    await _wait();
    return const VenteOk(null);
  }

  @override
  Future<VenteResult<List<PaymentMethodQr>>> paymentMethodsWithQr() async => const VenteOk([]);

  @override
  Future<VenteResult<List<PreventeListItem>>> preventes() async => const VenteOk([]);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Auth extends AuthProvider {
  _Auth() : super(ApiService(baseUrl: 'http://localhost'));
  @override
  bool get isAdmin => true;
  @override
  User? get user => User(userId: 'U1', login: 'awa', firstName: 'Awa', lastName: 'Kouassi', officineName: 'TEST');
}

/// Téléphone 360 × 700 dp.
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(720, 1400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

/// Clavier logiciel de 300 dp (viewInsets simulés) : zone visible 0 → 400 dp.
const _clavier = 300.0;
const _hautClavier = 700.0 - _clavier;
Future<void> _ouvrirClavier(WidgetTester tester) async {
  tester.view.viewInsets = const FakeViewPadding(bottom: _clavier * 2);
  await tester.pumpAndSettle();
}

Future<void> _fermerClavierSimule(WidgetTester tester) async {
  tester.view.resetViewInsets();
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester, _Gw gw, ListPresentation style) async {
  final settings = SettingsProvider();
  await settings.loadSettings();
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth()),
      ChangeNotifierProvider<SettingsProvider>.value(value: settings),
    ],
    child: MaterialApp(home: VenteScreen(gateway: gw, presentation: style)),
  ));
  await tester.pumpAndSettle();
}

Finder get _field => find.byKey(const ValueKey('vente-recherche'));

Future<void> _add(WidgetTester tester, String query) async {
  await tester.enterText(_field, query);
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
  await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField)), '1');
  await tester.tap(find.text('Ajouter'));
  await tester.pumpAndSettle();
}

bool _rechercheActive(WidgetTester tester) =>
    tester.widget<EditableText>(find.descendant(of: _field, matching: find.byType(EditableText))).focusNode.hasFocus;

String _f(int v) => '${Constants.formatNumber(v)} F';

/// Panier de 3 lignes, curseur dans la recherche, clavier ouvert.
Future<_Gw> _venteClavierOuvert(WidgetTester tester, ListPresentation style) async {
  _phone(tester);
  final gw = _Gw();
  await _open(tester, gw, style);
  await _add(tester, 'doli');
  await _add(tester, 'effer');
  await _add(tester, 'smecta');
  await tester.tap(_field);
  await tester.pump();
  expect(tester.testTextInput.isVisible, isTrue);
  await _ouvrirClavier(tester);
  return gw;
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Serveur joignable pendant tout le test (la recherche ne bascule pas sur la copie locale).
    final store = MemoryLocalStore();
    final previous = HorsLigne.instance;
    HorsLigne.instance = HorsLigne(monitor: ServerMonitor(ping: () async => true, seuil: 1), store: store, sync: CatalogueSync(store: store));
    addTearDown(() => HorsLigne.instance = previous);
  });

  for (final style in ListPresentation.values) {
    testWidgets('clavier ouvert — ${style.label} : en-tête réduit, panier et total visibles au-dessus du clavier', (tester) async {
      await _venteClavierOuvert(tester, style);
      // Total et fins de vente posés au-dessus du clavier.
      final pied = tester.getRect(find.byKey(const ValueKey('vente-pied-clavier')));
      expect(pied.bottom, lessThanOrEqualTo(_hautClavier + 0.5));
      final net = find.byKey(const ValueKey('vente-net'));
      expect(net, findsOneWidget);
      expect(tester.widget<Text>(net).data, _f(1500 + 900 + 600));
      expect(tester.getRect(net).bottom, lessThanOrEqualTo(_hautClavier));
      expect(find.byKey(const ValueKey('vente-encaisser')).hitTestable(), findsOneWidget);
      expect(find.byKey(const ValueKey('vente-enregistrer-prevente')).hitTestable(), findsOneWidget);
      // En-tête réduit : une seule ligne articles · boîtes · total (A, B) ; tuiles / chiffres / étapes masqués.
      expect(find.byType(KpiTile), findsNothing);
      expect(find.byType(LightFigures), findsNothing);
      expect(find.byType(StepsBar), findsNothing);
      // Articles · boîtes · total : une seule ligne, dans le pied au-dessus du clavier.
      expect(find.text('Total · 3 articles · 3 boîtes'), findsOneWidget);
      expect(tester.getRect(find.byKey(const ValueKey('vente-pied-resume'))).bottom, lessThanOrEqualTo(_hautClavier));
      // Panier visible entre l'en-tête et le pied (liste redimensionnée).
      final ligne = tester.getRect(find.text('DOLIPRANE 1000MG CP B/8'));
      expect(ligne.top, lessThan(pied.top));
      expect(find.text('DOLIPRANE 1000MG CP B/8').hitTestable(), findsOneWidget);
      expect(find.text('EFFERALGAN 500MG CP B/16').hitTestable(), findsOneWidget, reason: 'au moins deux lignes du panier visibles');
      expect(find.byKey(const ValueKey('vente-etat-ok')), findsNothing, reason: 'bandeau « enregistré ✓ » masqué clavier ouvert');
      expect(_rechercheActive(tester), isTrue);
      expect(tester.takeException(), isNull);

      // Clavier refermé : affichage complet d'origine.
      await _fermerClavierSimule(tester);
      expect(find.byKey(const ValueKey('vente-pied-clavier')), findsNothing);
      expect(find.byKey(const ValueKey('vente-pied-resume')), findsNothing);
      if (style == ListPresentation.dashboard) expect(find.byType(KpiTile), findsNWidgets(2));
      if (style == ListPresentation.compact) expect(find.byType(LightFigures), findsOneWidget);
      if (style == ListPresentation.guided) expect(find.byType(StepsBar), findsOneWidget);
      expect(find.byKey(const ValueKey('vente-net')), findsOneWidget);
      expect(find.byKey(const ValueKey('vente-etat-ok')), findsOneWidget);
      expect(_rechercheActive(tester), isTrue, reason: 'le champ n\'est jamais recréé');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('défiler le panier ferme le clavier, le curseur reste dans la recherche (douchette)', (tester) async {
    await _venteClavierOuvert(tester, ListPresentation.dashboard);
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.drag(find.text('DOLIPRANE 1000MG CP B/8'), const Offset(0, -80));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(_rechercheActive(tester), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('toucher hors champ ferme le clavier ; toucher le champ le rouvre', (tester) async {
    await _venteClavierOuvert(tester, ListPresentation.dashboard);
    // Toucher le champ lui-même : le clavier reste ouvert.
    await tester.tap(_field);
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    // Toucher hors champ (résumé du pied, sans action).
    await tester.tap(find.byKey(const ValueKey('vente-pied-resume')));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(_rechercheActive(tester), isTrue);
    await tester.tap(_field);
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clavier ouvert : « Prévente » validée depuis le pied, le curseur revient dans la recherche', (tester) async {
    final gw = await _venteClavierOuvert(tester, ListPresentation.compact);
    await tester.tap(find.byKey(const ValueKey('vente-enregistrer-prevente')));
    await tester.pumpAndSettle();
    expect(find.text('Prévente enregistrée'), findsOneWidget);
    await tester.tap(find.text('Non'));
    await tester.pumpAndSettle();
    expect(gw.terminerCalls, 1);
    expect(find.text('Le panier est vide'), findsOneWidget);
    expect(_rechercheActive(tester), isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(tester.takeException(), isNull);
  });

  group('Cadre commun (Assurance, Carnet) : PresentationScaffold.clavierCompact', () {
    Widget ecran({required bool clavierCompact, ListPresentation style = ListPresentation.guided}) => MaterialApp(
          home: PresentationScaffold(
            style: style,
            title: 'Assurance',
            subtitle: 'Étape 3 sur 4',
            actions: (_) => const [],
            steps: const StepsBar(active: 2, steps: [
              (title: 'Client', detail: '', onTap: null),
              (title: 'Produits', detail: '', onTap: null),
            ]),
            header: const [Text('ETAPES'), TextField(key: ValueKey('champ'))],
            compactHeader: const [Text('ETAPES'), TextField(key: ValueKey('champ'))],
            headerClavier: const [SizedBox.shrink(), TextField(key: ValueKey('champ'))],
            compactHeaderClavier: const [SizedBox.shrink(), TextField(key: ValueKey('champ'))],
            clavierCompact: clavierCompact,
            body: ListView(children: [for (var i = 0; i < 30; i++) SizedBox(height: 40, child: Text('ligne $i'))]),
            bottomNavigationBar: const SizedBox(key: ValueKey('pied'), height: 60, child: Text('VALIDER')),
          ),
        );

    for (final style in ListPresentation.values) {
      testWidgets('${style.label} : clavier ouvert, étapes masquées, pied au-dessus du clavier, champ conservé', (tester) async {
        _phone(tester);
        await tester.pumpWidget(ecran(clavierCompact: true, style: style));
        await tester.tap(find.byKey(const ValueKey('champ')));
        await tester.pump();
        final champ = tester.state(find.byKey(const ValueKey('champ')));
        await _ouvrirClavier(tester);
        expect(tester.getRect(find.byKey(const ValueKey('pied'))).bottom, lessThanOrEqualTo(_hautClavier + 0.5));
        expect(find.text('ETAPES'), findsNothing);
        expect(find.byType(StepsBar), findsNothing);
        expect(find.text('Étape 3 sur 4'), findsNothing);
        expect(tester.state(find.byKey(const ValueKey('champ'))), same(champ), reason: 'le champ garde son état et son focus');
        await tester.drag(find.text('ligne 1'), const Offset(0, -60));
        await tester.pump();
        expect(tester.testTextInput.isVisible, isFalse);
        await _fermerClavierSimule(tester);
        expect(find.text('ETAPES'), findsOneWidget);
        expect(tester.getRect(find.byKey(const ValueKey('pied'))).bottom, closeTo(700, 0.5));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('écran non concerné (sans clavierCompact) : affichage inchangé', (tester) async {
      _phone(tester);
      await tester.pumpWidget(ecran(clavierCompact: false));
      await _ouvrirClavier(tester);
      expect(find.text('ETAPES'), findsOneWidget);
      expect(find.byType(StepsBar), findsOneWidget);
      expect(tester.getRect(find.byKey(const ValueKey('pied'))).bottom, closeTo(700, 0.5));
      expect(tester.takeException(), isNull);
    });
  });
}
