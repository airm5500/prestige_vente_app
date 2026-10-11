// Pré-vente / Vente (étape 2, présentation) : écran de vente, page d'encaissement et liste des préventes
// en A / B / C à 360 px ; espèces (monnaie, touches rapides, montant aberrant), QR mobile money,
// caisse fermée, aucun mode activé, pas de réponse → Réessayer, double tap VALIDER = 1 clôture,
// « Un panier est en cours » (enregistrer en prévente), « Reprendre la vente ? ».
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/payment_method_qr.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/api/models/user.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/core/pending_sale_store.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/ventes/prevente/encaissement_page.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_controller.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_screen.dart';
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
final _smecta = _p('P3', 'SMECTA SACHETS B/30', '3400930000003', price: 600, stock: 1);

/// PNG 1×1 (QR factice).
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

enum _Cloture { ok, caisse, lostNotApplied, refused }

class _Gw implements VenteGateway {
  Duration delay = const Duration(milliseconds: 20);
  final catalog = [_doli, _smecta];
  final Map<String, List<SaleItemDetail>> sales = {};
  final Map<String, String> statut = {};
  int creations = 0;
  int clotureCalls = 0;
  int terminerCalls = 0;
  final List<({int? recu, int? remis, String type})> clotures = [];
  _Cloture clotureMode = _Cloture.ok;
  List<PreventeListItem> preventeList = [];

  Future<void> _wait() => Future.delayed(delay);

  SaleItemDetail line(String venteId, ProductSearchResult p, int qty, int pu) => SaleItemDetail(
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
    final q = query.toLowerCase();
    return VenteOk(catalog.where((p) => p.strNAME.toLowerCase().contains(q) || p.intCIP == query).toList());
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
      statut[id] = 'pending';
    }
    sales[id]!.add(line(id, catalog.firstWhere((p) => p.lgFAMILLEID == produitId), qte, itemPu));
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
  Future<VenteResult<void>> updateItem({required String itemId, required String produitId, required int qte, required int itemPu}) async =>
      const VenteOk(null);

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
  Future<VenteResult<void>> updateClient(String venteId, String clientId) async {
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
    clotures.add((recu: montantRecu, remis: montantRemis, type: typeReglementId));
    await _wait();
    if (statut[venteId] == 'is_Closed') return const VenteRefused('Cette vente a déjà été clôturée');
    switch (clotureMode) {
      case _Cloture.caisse:
        return const VenteRefused('Désolé votre caisse est fermée. Veuillez l\'ouvrir avant de proceder à validation');
      case _Cloture.lostNotApplied:
        return const VenteFailed('Le serveur met trop de temps à répondre.', maybeApplied: true);
      case _Cloture.refused:
        return const VenteRefused('<b>Montant</b> incohérent');
      case _Cloture.ok:
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
  Future<VenteResult<List<PaymentMethodQr>>> paymentMethodsWithQr() async => VenteOk([PaymentMethodQr(id: '10', name: 'WAVE', qrCode: _png)]);

  @override
  Future<VenteResult<List<PreventeListItem>>> preventes() async {
    await _wait();
    return VenteOk(preventeList);
  }

  @override
  Future<VenteResult<Map<String, dynamic>>> fullSale(String venteId) async {
    await _wait();
    final s = statut[venteId];
    if (s == null) return const VenteFailed('Vente introuvable.');
    return VenteOk({'strSTATUT': s});
  }

  // Non utilisés par ce menu.
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
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

Future<void> _app(WidgetTester tester, Widget Function() screen) async {
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

Future<void> _open(WidgetTester tester, _Gw gw, ListPresentation style, {int initialTab = 0}) =>
    _app(tester, () => VenteScreen(gateway: gw, presentation: style, initialTabIndex: initialTab));

Finder get _field => find.byKey(const ValueKey('vente-recherche'));
Finder get _encaisser => find.byKey(const ValueKey('vente-encaisser'));
Finder get _valider => find.byKey(const ValueKey('encaissement-valider'));

bool _enabled(WidgetTester tester, Finder f) => (tester.widget(f) as ButtonStyleButton).onPressed != null;

Future<void> _add(WidgetTester tester, String query, {String qty = '1', bool force = false}) async {
  await tester.enterText(_field, query);
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
  await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField)), qty);
  await tester.tap(find.text('Ajouter'));
  await tester.pumpAndSettle();
  if (force) {
    await tester.tap(find.text('Forcer'));
    await tester.pumpAndSettle();
  }
}

String _f(int v) => '${Constants.formatNumber(v)} F';

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  setUp(() => SharedPreferences.setMockInitialValues({
        'enabled_payment_method_ids': ['1', '10'],
      }));

  for (final style in ListPresentation.values) {
    testWidgets('écran de vente — ${style.label}', (tester) async {
      _phone(tester);
      final gw = _Gw();
      await _open(tester, gw, style);
      expect(find.text('Vente'), findsOneWidget);
      expect(find.text('Le panier est vide'), findsOneWidget);
      expect(find.text('Préventes à encaisser'), findsOneWidget); // raccourci du panier vide
      expect(find.text('PRÉVENTE'), findsOneWidget);
      expect(find.text('ENCAISSER'), findsOneWidget);
      expect(_enabled(tester, _encaisser), isFalse);

      await _add(tester, 'doli', qty: '2');
      await _add(tester, 'smecta', qty: '2', force: true); // stock 1 : forcé
      expect(find.text('DOLIPRANE 1000MG CP B/8'), findsOneWidget);
      expect(find.text('2 articles enregistrés sur le serveur'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('vente-net'))).data, _f(4200));
      expect(find.textContaining('stock dépassé'), findsOneWidget);
      expect(_enabled(tester, _encaisser), isTrue);
      switch (style) {
        case ListPresentation.dashboard:
          expect(find.text('boîtes'), findsOneWidget);
          expect(find.text('Réf. REF-V1 · non encaissée'), findsOneWidget);
          expect(find.text('Total à payer'), findsOneWidget);
        case ListPresentation.compact:
          expect(find.text('REF-V1 · 2 articles'), findsOneWidget);
          expect(find.text('Total · 4 boîtes'), findsOneWidget);
          expect(find.textContaining('glisser : supprimer'), findsOneWidget);
        case ListPresentation.guided:
          expect(find.text('Vérifier'), findsOneWidget);
          expect(find.text('ÉTAPE 3'), findsOneWidget);
          // Bouton principal ambre.
          final bg = tester.widget<ButtonStyleButton>(_encaisser).style?.backgroundColor?.resolve({});
          expect(bg, Pal.amber);
      }
      // Boutons Modifier / Supprimer d'au moins 44 px.
      final edit = tester.getSize(find.byTooltip('Modifier').first);
      expect(edit.height, greaterThanOrEqualTo(44));
      expect(edit.width, greaterThanOrEqualTo(44));
      expect(tester.takeException(), isNull);
    });

    testWidgets('encaissement espèces : monnaie, touches rapides, montant aberrant — ${style.label}', (tester) async {
      _phone(tester);
      SharedPreferences.setMockInitialValues({
        'enabled_payment_method_ids': ['1', '10'],
        'number_of_tickets': 2,
      });
      final gw = _Gw();
      await _open(tester, gw, style);
      await _add(tester, 'doli', qty: '3'); // 4 500 F
      await tester.tap(_encaisser);
      await tester.pumpAndSettle();

      expect(find.text('Encaissement'), findsOneWidget);
      expect(find.text('Total à payer'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('encaissement-total'))).data, _f(4500));
      expect(find.text('Espèces'), findsOneWidget);
      expect(find.text('WAVE'), findsOneWidget);
      expect(find.text('ORANGE'), findsNothing); // non activé
      expect(find.text('VALIDER L\'ENCAISSEMENT'), findsOneWidget);
      expect(_enabled(tester, _valider), isFalse); // montant reçu à saisir
      // Impression cochée par défaut, copies du réglage.
      expect(tester.widget<Checkbox>(find.byKey(const ValueKey('encaissement-imprimer'))).value, isTrue);
      expect(tester.widget<Text>(find.byKey(const ValueKey('encaissement-copies'))).data, '2');

      await tester.tap(find.text('Exact'));
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const ValueKey('encaissement-monnaie'))).data, _f(0));
      await tester.tap(find.text(Constants.formatNumber(10000)));
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const ValueKey('encaissement-monnaie'))).data, _f(5500));

      await tester.enterText(find.byKey(const ValueKey('encaissement-recu')), '4000');
      await tester.pump();
      expect(find.textContaining('Montant insuffisant'), findsOneWidget);
      expect(_enabled(tester, _valider), isFalse);
      await tester.enterText(find.byKey(const ValueKey('encaissement-recu')), '600000');
      await tester.pump();
      expect(find.text('Montant aberrant (erreur de scan ?)'), findsOneWidget);
      expect(_enabled(tester, _valider), isFalse);

      await tester.enterText(find.byKey(const ValueKey('encaissement-recu')), '5000');
      await tester.pump();
      expect(_enabled(tester, _valider), isTrue);
      expect(tester.takeException(), isNull);

      // Impression demandée : officine absente → message, aucune impression silencieuse.
      await tester.tap(_valider);
      await tester.pumpAndSettle();
      expect(gw.clotureCalls, 1);
      expect(gw.clotures.single, (recu: 5000, remis: 500, type: '1'));
      expect(find.text('Données officine manquantes : ticket non imprimé.'), findsOneWidget);
      expect(find.text('Le panier est vide'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('encaissement mobile money : QR sur la page — ${style.label}', (tester) async {
      _phone(tester);
      final gw = _Gw();
      await _open(tester, gw, style);
      await _add(tester, 'doli');
      await tester.tap(_encaisser);
      await tester.pumpAndSettle();
      await tester.tap(find.text('WAVE'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('encaissement-qr')), findsOneWidget);
      expect(find.text('Faites scanner ce QR au client'), findsOneWidget);
      expect(find.text('WAVE · ${_f(1500)}'), findsOneWidget);
      expect(find.text('PAIEMENT REÇU — VALIDER'), findsOneWidget);
      expect(find.byKey(const ValueKey('encaissement-recu')), findsNothing);
      // Case « Imprimer » sous le QR : la page défile.
      await tester.scrollUntilVisible(find.byKey(const ValueKey('encaissement-imprimer')), 100,
          scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
      await tester.ensureVisible(find.byKey(const ValueKey('encaissement-imprimer')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('encaissement-imprimer')));
      await tester.pump();
      await tester.tap(_valider);
      await tester.pumpAndSettle();
      expect(gw.clotures.single, (recu: null, remis: null, type: '10'));
      expect(find.textContaining('Vente encaissée'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('encaissement : caisse fermée sur la page + « Ouvrir » — ${style.label}', (tester) async {
      _phone(tester);
      final gw = _Gw()..clotureMode = _Cloture.caisse;
      await _open(tester, gw, style);
      await _add(tester, 'doli');
      await tester.tap(_encaisser);
      await tester.pumpAndSettle();
      await tester.tap(find.text('WAVE'));
      await tester.pumpAndSettle();
      await tester.tap(_valider);
      await tester.pumpAndSettle();
      expect(find.text('Caisse Fermée'), findsOneWidget); // proposition actuelle
      await tester.tap(find.text('Non'));
      await tester.pumpAndSettle();
      expect(find.text('Caisse fermée : ouvrez-la avant de valider.'), findsOneWidget);
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      expect(find.text('Caisse Fermée'), findsOneWidget);
      await tester.tap(find.text('Non'));
      await tester.pumpAndSettle();
      expect(find.text('Encaissement'), findsOneWidget); // on reste sur la page
      expect(gw.statut['V1'], 'pending');
      expect(tester.takeException(), isNull);
    });

    testWidgets('encaissement : aucun mode activé → message + Réglages — ${style.label}', (tester) async {
      _phone(tester);
      SharedPreferences.setMockInitialValues({'enabled_payment_method_ids': <String>[]});
      final settings = SettingsProvider();
      await settings.loadSettings();
      final c = VenteController(gateway: _Gw()..delay = Duration.zero);
      await tester.runAsync(() => c.addProduct(_doli, 1));
      var opened = 0;
      await tester.pumpWidget(ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          home: EncaissementPage(
            controller: c,
            userId: 'U1',
            expectedChanges: c.changes,
            summary: c.summary,
            itemCount: c.items.length,
            presentation: style,
            openSettings: (_) async => opened++,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Aucun mode de règlement activé'), findsOneWidget);
      expect(find.textContaining('Réglages › Modes de paiement'), findsOneWidget);
      await tester.tap(find.text('OUVRIR LES RÉGLAGES'));
      await tester.pumpAndSettle();
      expect(opened, 1);
      // Mode activé dans les Réglages : les tuiles apparaissent au retour.
      await settings.togglePaymentMethod('10', true);
      await tester.pumpAndSettle();
      expect(find.text('WAVE'), findsOneWidget);
      expect(find.text('PAIEMENT REÇU — VALIDER'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('encaissement : pas de réponse → vérification, « Vente non encaissée », RÉESSAYER', (tester) async {
    _phone(tester);
    final gw = _Gw()..clotureMode = _Cloture.lostNotApplied;
    await _open(tester, gw, ListPresentation.dashboard);
    await _add(tester, 'doli');
    await tester.tap(_encaisser);
    await tester.pumpAndSettle();
    await tester.tap(find.text('WAVE'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('encaissement-imprimer')));
    await tester.tap(_valider);
    await tester.pumpAndSettle();
    expect(find.text('Pas de réponse du serveur : la vente a été vérifiée.'), findsOneWidget);
    expect(find.text('Vente non encaissée'), findsOneWidget);
    expect(find.text('RÉESSAYER'), findsOneWidget);
    expect(find.text('RETOUR'), findsOneWidget);
    expect(gw.clotureCalls, 1);

    gw.clotureMode = _Cloture.ok;
    await tester.tap(find.text('RÉESSAYER'));
    await tester.pump(const Duration(milliseconds: 5));
    expect(find.text('VÉRIFICATION…'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(gw.clotureCalls, 2);
    expect(gw.statut['V1'], 'is_Closed');
    expect(find.textContaining('Vente encaissée'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('encaissement : refus du serveur affiché sur la page', (tester) async {
    _phone(tester);
    final gw = _Gw()..clotureMode = _Cloture.refused;
    await _open(tester, gw, ListPresentation.compact);
    await _add(tester, 'doli');
    await tester.tap(_encaisser);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exact'));
    await tester.pump();
    await tester.tap(_valider);
    await tester.pumpAndSettle();
    expect(find.text('Montant incohérent'), findsOneWidget);
    expect(find.text('Encaissement'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('double tap sur VALIDER : une seule clôture', (tester) async {
    _phone(tester);
    final gw = _Gw()..delay = const Duration(milliseconds: 120);
    await _open(tester, gw, ListPresentation.guided);
    await _add(tester, 'doli');
    await tester.tap(_encaisser);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exact'));
    await tester.tap(find.byKey(const ValueKey('encaissement-imprimer')));
    await tester.pump();
    await tester.tap(_valider);
    await tester.tap(_valider, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 10));
    await tester.tap(_valider, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(gw.clotureCalls, 1);
    expect(find.textContaining('Vente encaissée'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final style in ListPresentation.values) {
    testWidgets('liste des préventes — ${style.label}', (tester) async {
      _phone(tester);
      final gw = _Gw();
      gw.sales['V7'] = [gw.line('V7', _doli, 1, 1500)];
      gw.statut['V7'] = 'is_Process';
      gw.preventeList = [
        PreventeListItem(
            lgPREENREGISTREMENTID: 'V7', heure: '09:41:12', dtUPDATED: '10/10/2026', intPRICE: 1500, strREF: 'PV-0007', userFullName: 'Awa Kouassi', lgTYPEVENTEID: '1'),
        PreventeListItem(
            lgPREENREGISTREMENTID: 'V8', heure: '10:05:00', dtUPDATED: '10/10/2026', intPRICE: 12750, strREF: 'PV-0008', userFullName: 'Koffi', lgTYPEVENTEID: '1'),
      ];
      await _open(tester, gw, style, initialTab: 2); // ouverture directe de la liste (accueil)
      expect(find.text('Préventes à encaisser'), findsOneWidget);
      expect(find.text('2 préventes · ${_f(14250)}'), findsOneWidget);
      expect(find.text('10/10/2026 09:41'), findsOneWidget);
      expect(find.text('10/10/2026 10:05'), findsOneWidget);
      expect(find.text('À encaisser'), findsNWidgets(2));
      expect(find.text('Vendeur : Koffi'), findsOneWidget);
      expect(find.byTooltip('Réimprimer le ticket'), findsNWidgets(2));

      await tester.enterText(find.byKey(const ValueKey('preventes-recherche')), 'koffi');
      await tester.pump();
      expect(find.text('PV-0008'), findsOneWidget);
      expect(find.text('PV-0007'), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('preventes-recherche')), 'zzz');
      await tester.pump();
      expect(find.text('Aucune prévente pour « zzz »'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('preventes-recherche')), '0007');
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('PV-0007'));
      await tester.pumpAndSettle();
      expect(find.text('Préventes à encaisser'), findsNothing);
      expect(find.text('DOLIPRANE 1000MG CP B/8'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  // Retour client : après une vente validée, le curseur revient dans la recherche produit (vente suivante).
  bool rechercheActive(WidgetTester tester) =>
      tester.widget<EditableText>(find.descendant(of: _field, matching: find.byType(EditableText))).focusNode.hasFocus;

  for (final style in ListPresentation.values) {
    testWidgets('après « Prévente » enregistrée : curseur dans la recherche produit — ${style.label}', (tester) async {
      _phone(tester);
      final gw = _Gw();
      await _open(tester, gw, style);
      await _add(tester, 'doli');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(rechercheActive(tester), isFalse);
      await tester.tap(find.byKey(const ValueKey('vente-enregistrer-prevente')));
      await tester.pumpAndSettle();
      expect(find.text('Prévente enregistrée'), findsOneWidget);
      await tester.tap(find.text('Non'));
      await tester.pumpAndSettle();
      expect(gw.terminerCalls, 1);
      expect(find.text('Le panier est vide'), findsOneWidget);
      expect(rechercheActive(tester), isTrue);
      expect(tester.testTextInput.isVisible, isTrue); // clavier ouvert
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('après un encaissement : curseur dans la recherche produit', (tester) async {
    _phone(tester);
    final gw = _Gw();
    await _open(tester, gw, ListPresentation.dashboard);
    await _add(tester, 'doli');
    await tester.tap(_encaisser);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exact'));
    await tester.pump();
    await tester.tap(_valider);
    await tester.pumpAndSettle();
    expect(gw.clotureCalls, 1);
    expect(find.text('Le panier est vide'), findsOneWidget);
    expect(rechercheActive(tester), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('« Un panier est en cours » : l\'enregistrer en prévente puis ouvrir l\'autre', (tester) async {
    _phone(tester);
    final gw = _Gw();
    gw.sales['V7'] = [gw.line('V7', _smecta, 1, 600)];
    gw.statut['V7'] = 'is_Process';
    gw.preventeList = [
      PreventeListItem(
          lgPREENREGISTREMENTID: 'V7', heure: '09:41:12', dtUPDATED: '10/10/2026', intPRICE: 600, strREF: 'PV-0007', userFullName: 'Awa', lgTYPEVENTEID: '1'),
    ];
    await _open(tester, gw, ListPresentation.dashboard);
    await _add(tester, 'doli');
    await tester.tap(find.byTooltip('Préventes à encaisser'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PV-0007'));
    await tester.pumpAndSettle();
    expect(find.text('Un panier est en cours'), findsOneWidget);
    expect(find.textContaining('REF-V1 (1 article, ${_f(1500)})'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('L\'ENREGISTRER EN PRÉVENTE'));
    await tester.pumpAndSettle();
    expect(find.text('Prévente enregistrée'), findsOneWidget);
    await tester.tap(find.text('Non'));
    await tester.pumpAndSettle();
    expect(gw.terminerCalls, 1);
    expect(gw.statut['V1'], 'is_Process');
    expect(find.text('SMECTA SACHETS B/30'), findsOneWidget);
    expect(find.text('DOLIPRANE 1000MG CP B/8'), findsNothing);
    expect(gw.clotureCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('« Nouvelle vente » avec panier : la garder et revenir ne change rien', (tester) async {
    _phone(tester);
    final gw = _Gw();
    await _open(tester, gw, ListPresentation.compact);
    await _add(tester, 'doli');
    await tester.tap(find.byTooltip('Nouvelle vente'));
    await tester.pumpAndSettle();
    expect(find.text('Un panier est en cours'), findsOneWidget);
    await tester.tap(find.text('LA GARDER ET REVENIR'));
    await tester.pumpAndSettle();
    expect(find.text('DOLIPRANE 1000MG CP B/8'), findsOneWidget);
    await tester.tap(find.byTooltip('Nouvelle vente'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nouvelle vente sans l\'enregistrer'));
    await tester.pumpAndSettle();
    expect(find.text('Le panier est vide'), findsOneWidget);
    expect(gw.terminerCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('« Reprendre la vente ? » : PLUS TARD ne charge rien, la vente reste mémorisée', (tester) async {
    _phone(tester);
    final gw = _Gw();
    gw.sales['V5'] = [gw.line('V5', _doli, 2, 1500)];
    gw.statut['V5'] = 'pending';
    await PendingSaleStore.save(
        VenteMenu.prevente, PendingSale(venteId: 'V5', reference: 'PV-0005', itemCount: 1, total: 3000, savedAt: DateTime(2026, 10, 9, 18, 30)));
    await _open(tester, gw, ListPresentation.guided);
    expect(find.text('Reprendre la vente ?'), findsOneWidget);
    expect(find.textContaining('PV-0005 (1 article, ${_f(3000)})'), findsOneWidget);
    expect(find.text('REPRENDRE'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('PLUS TARD'));
    await tester.pumpAndSettle();
    expect(find.text('Le panier est vide'), findsOneWidget);
    expect((await PendingSaleStore.load(VenteMenu.prevente))?.venteId, 'V5');
    expect(tester.takeException(), isNull);
  });

  testWidgets('menu « Présentation » : choix mémorisé', (tester) async {
    _phone(tester);
    final gw = _Gw();
    await _app(tester, () => VenteScreen(gateway: gw));
    expect(find.text('boîtes'), findsOneWidget); // A par défaut
    await tester.tap(find.byTooltip('Présentation'));
    await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate((w) => w is CheckedPopupMenuItem<ListPresentation> && w.value == ListPresentation.compact));
    await tester.pumpAndSettle();
    expect(await PresentationPrefs.load(), ListPresentation.compact);
    expect(find.text('Toucher une ligne : modifier · glisser : supprimer'), findsNothing); // panier vide
    expect(find.byType(LightFigures), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
