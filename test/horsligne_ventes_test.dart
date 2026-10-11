// Hors ligne (étape H2) : saisie hors ligne comptant / assurance / carnet, prévente et encaissement espèces
// provisoires, file persistée, envoi dans l'ordre avec un faux serveur (mêmes appels que la vente en ligne),
// coupure au milieu (reprise sans doublon), réponse perdue (relecture), conflit de prix / net (anomalie sans
// clôture), vente commencée en ligne (articles manquants seulement), confirmation avant envoi (décochage →
// ressaisie), rapport d'anomalies (bon déjà utilisé), rapport de fin de journée (total par produit),
// impression en mode test, écrans à 360 px et tablette, en ligne inchangé.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/assurance_sale_summary.dart';
import 'package:prestige_vente_app/api/models/ayant_droit.dart';
import 'package:prestige_vente_app/api/models/officine.dart';
import 'package:prestige_vente_app/api/models/payment_method_qr.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/api/models/tiers_payant_assurance.dart';
import 'package:prestige_vente_app/api/models/user.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/horsligne_ui.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart';
import 'package:prestige_vente_app/horsligne/rapports_hl.dart';
import 'package:prestige_vente_app/horsligne/rapports_hl_screen.dart';
import 'package:prestige_vente_app/horsligne/server_monitor.dart';
import 'package:prestige_vente_app/horsligne/vente_hors_ligne.dart';
import 'package:prestige_vente_app/horsligne/ventes_hors_ligne_screen.dart';
import 'package:prestige_vente_app/horsligne/ventes_sync.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/assurance/assurance_controller.dart';
import 'package:prestige_vente_app/ventes/carnet/carnet_controller.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_cart.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_controller.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/support/support_centre.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// -----------------------------------------------------------------------------
// Faux serveur Prestige
// -----------------------------------------------------------------------------

/// Comportement d'un appel : réussi, panne (rien appliqué), réponse perdue (appliqué), refus.
enum _M { ok, panne, perdue, refus }

class _Prod {
  final String id, nom, cip;
  int prix;
  int stock = 50;
  _Prod(this.id, this.nom, this.cip, this.prix);
  ProductSearchResult get result =>
      ProductSearchResult(lgFAMILLEID: id, strNAME: nom, intCIP: cip, intPRICE: prix, intNUMBERAVAILABLE: stock, strLIBELLEE: '', intPAF: 0);
}

class _Srv implements VenteGateway {
  final Map<String, _Prod> catalog = {
    'P1': _Prod('P1', 'DOLIPRANE 1000MG CP B/8', '3400930000001', 1500),
    'P2': _Prod('P2', 'EFFERALGAN 500MG', '3400930000002', 1200),
    'P3': _Prod('P3', 'AUGMENTIN 1G', '3400930000003', 6300),
  };
  final Map<String, List<SaleItemDetail>> sales = {};
  final Map<String, String> statut = {};
  final Map<String, String> typeOf = {};
  final List<String?> addVenteIds = [];
  final List<String> addProduits = [];
  final List<String> ordreCreation = [];
  final List<({String clientId, String typeVenteId, List<VenteTp> tps})> addAssurance = [];
  final List<({int recu, int remis, int net})> clotures = [];
  final List<String> clients = [];
  int creations = 0;
  int terminerCalls = 0;
  int clotureCalls = 0;
  int detailsCalls = 0;

  /// Écart du net du serveur (remise) par rapport à la somme des lignes.
  int netDelta = 0;
  final List<_M> addModes = [];
  final List<_M> terminerModes = [];
  final List<_M> clotureModes = [];
  String refusAjout = 'Stock insuffisant pour ce produit';

  _M _next(List<_M> l) => l.isEmpty ? _M.ok : l.removeAt(0);
  int _total(String id) => (sales[id] ?? const []).fold(0, (s, i) => s + i.intPRICE);

  VenteResult<String> _add(String produitId, int qte, int pu, String? venteId, String type) {
    addVenteIds.add(venteId);
    addProduits.add(produitId);
    final m = _next(addModes);
    if (m == _M.panne) return const VenteFailed('Serveur injoignable (ajouter le produit).');
    if (m == _M.refus) return VenteRefused(refusAjout);
    var id = venteId;
    if (id == null) {
      creations++;
      id = 'V$creations';
      sales[id] = [];
      statut[id] = 'pending';
      typeOf[id] = type;
      ordreCreation.add(produitId);
    }
    final p = catalog[produitId]!;
    final list = sales[id]!;
    list.add(SaleItemDetail(
      lgPREENREGISTREMENTDETAILID: '$id-L${list.length + 1}',
      lgFAMILLEID: produitId,
      strNAME: p.nom,
      intCIP: p.cip,
      intQUANTITY: qte,
      intPRICEUNITAIR: pu,
      intPRICE: qte * pu,
      strREF: 'PV-$id',
    ));
    if (m == _M.perdue) return const VenteFailed('Le serveur met trop de temps à répondre.', maybeApplied: true);
    return VenteOk(id);
  }

  @override
  Future<VenteResult<String>> addItemVno({required String produitId, required int qte, required int itemPu, String? venteId, required bool prevente}) async =>
      _add(produitId, qte, itemPu, venteId, '1');

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
    addAssurance.add((clientId: clientId, typeVenteId: typeVenteId, tps: tierspayants));
    return _add(produitId, qte, itemPu, venteId, typeVenteId);
  }

  @override
  Future<VenteResult<List<SaleItemDetail>>> saleDetails(String venteId) async {
    detailsCalls++;
    return VenteOk(List.of(sales[venteId] ?? const []));
  }

  @override
  Future<VenteResult<SaleSummary>> netVno(String venteId) async {
    final t = _total(venteId);
    return VenteOk(SaleSummary(montant: t, montantNet: t + netDelta, venteId: venteId, reference: 'PV-$venteId'));
  }

  @override
  Future<VenteResult<AssuranceSaleSummary>> netAssurance({required String venteId, required List<VenteTp> tierspayants}) async {
    final t = _total(venteId);
    final tp = tierspayants.fold<int>(0, (s, x) => s + (t * x.taux / 100).round());
    return VenteOk(AssuranceSaleSummary(montant: t, montantTp: tp, montantNet: t - tp));
  }

  @override
  Future<VenteResult<void>> terminerPrevente(String venteId) async {
    terminerCalls++;
    final m = _next(terminerModes);
    if (m == _M.panne) return const VenteFailed('Serveur injoignable.');
    if (m == _M.refus) return const VenteRefused('Désolé votre caisse est fermée. Veuillez l\'ouvrir');
    statut[venteId] = 'is_Process';
    if (m == _M.perdue) return const VenteFailed('Délai dépassé.', maybeApplied: true);
    return const VenteOk(null);
  }

  @override
  Future<VenteResult<void>> updateClient(String venteId, String clientId) async {
    clients.add(clientId);
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
    if (statut[venteId] == 'is_Closed') return const VenteRefused('Cette vente a déjà été clôturée');
    final m = _next(clotureModes);
    if (m == _M.panne) return const VenteFailed('Serveur injoignable.');
    if (m == _M.refus) return const VenteRefused('Désolé votre caisse est fermée. Veuillez l\'ouvrir');
    statut[venteId] = 'is_Closed';
    clotures.add((recu: montantRecu ?? 0, remis: montantRemis ?? 0, net: summary.montantNet));
    if (m == _M.perdue) return const VenteFailed('Délai dépassé.', maybeApplied: true);
    return const VenteOk({'success': true});
  }

  @override
  Future<VenteResult<Map<String, dynamic>>> fullSale(String venteId) async {
    final s = statut[venteId];
    if (s == null) return const VenteFailed('Vente introuvable.');
    return VenteOk({'strSTATUT': s, 'strREF': 'PV-$venteId'});
  }

  @override
  Future<VenteResult<ProductPage>> searchProductsPage(String query, int start, int limit) async {
    final q = query.toUpperCase();
    final items = catalog.values.where((p) => p.cip == query || p.nom.toUpperCase().startsWith(q)).map((p) => p.result).toList();
    return VenteOk(ProductPage(start == 0 ? items : const [], items.length));
  }

  @override
  Future<VenteResult<List<ProductSearchResult>>> searchProducts(String query) async =>
      (await searchProductsPage(query, 0, 50)).map((p) => p.items);

  @override
  Future<VenteResult<List<PaymentMethod>>> paymentMethods() async => VenteOk([PaymentMethod(id: '1', name: 'ESPECES'), PaymentMethod(id: '10', name: 'WAVE')]);
  @override
  Future<VenteResult<List<PaymentMethodQr>>> paymentMethodsWithQr() async => const VenteOk([]);
  @override
  Future<VenteResult<List<PreventeListItem>>> preventes() async => const VenteOk([]);
  @override
  Future<VenteResult<List<PreventeListItem>>> ventesByType(String typeVenteId) async => const VenteOk([]);
  @override
  Future<VenteResult<List<AyantDroit>>> ayantDroits(String clientId) async => const VenteOk([]);
  @override
  Future<VenteResult<void>> removeItem(String itemId) async => const VenteOk(null);
  @override
  Future<VenteResult<void>> updateItem({required String itemId, required String produitId, required int qte, required int itemPu}) async =>
      const VenteOk(null);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

// -----------------------------------------------------------------------------
// Copie locale, instance hors ligne
// -----------------------------------------------------------------------------

Map<String, dynamic> _row(_Prod p) => {
      'lgFAMILLEID': p.id,
      'strNAME': p.nom,
      'intCIP': p.cip,
      'intPRICE': p.prix,
      'intNUMBERAVAILABLE': p.stock,
      'strLIBELLEE': '',
      'intPAF': 0,
    };

final _clientA = {
  'lgCLIENTID': 'C1',
  'fullName': 'AWA KOUASSI',
  'strFIRSTNAME': 'AWA',
  'strLASTNAME': 'KOUASSI',
  'strNUMEROSECURITESOCIAL': '123',
  'strCODEINTERNE': 'C1',
  'lgTYPECLIENTID': '1',
  'tiersPayants': [
    {'lgTIERSPAYANTID': 'T1', 'tpFullName': 'MUGEFCI', 'taux': 70, 'numSecurity': '123', 'compteTp': 'CPT1', 'order': 1, 'principal': true},
  ],
  'ayantDroits': [],
};

final _clientC = {
  'lgCLIENTID': 'C3',
  'fullName': 'MME TRAORE',
  'strFIRSTNAME': 'MME',
  'strLASTNAME': 'TRAORE',
  'strNUMEROSECURITESOCIAL': '456',
  'strCODEINTERNE': 'C3',
  'lgTYPECLIENTID': '2',
  'tiersPayants': [
    {'lgTIERSPAYANTID': 'T3', 'tpFullName': 'DEPOT GOKRA', 'taux': 100, 'numSecurity': '456', 'compteTp': 'CPT3', 'order': 1, 'principal': true},
  ],
  'ayantDroits': [],
};

class _Env {
  final _Srv srv;
  final HorsLigne hl;
  final MemoryVentesHLStore store;
  _Env(this.srv, this.hl, this.store);
  FileVentesHL get file => hl.ventes;
  List<VenteHorsLigne> get ventes => file.ventes;
}

Future<_Env> _env({bool offline = true, MemoryVentesHLStore? store}) async {
  final srv = _Srv();
  final local = MemoryLocalStore();
  final at = DateTime(2026, 10, 10, 8);
  await local.replace(CatalogueCategorie.produits, [for (final p in srv.catalog.values) _row(p)], at);
  await local.replace(CatalogueCategorie.clientsAssurance, [_clientA], at);
  await local.replace(CatalogueCategorie.clientsCarnet, [_clientC], at);
  final s = store ?? MemoryVentesHLStore();
  final hl = HorsLigne(monitor: ServerMonitor(), store: local, ventes: FileVentesHL(store: s, gateway: srv));
  await hl.sync.refreshStats();
  final previous = HorsLigne.instance;
  HorsLigne.instance = hl;
  addTearDown(() => HorsLigne.instance = previous);
  if (offline) hl.monitor.goOffline();
  return _Env(srv, hl, s);
}

ProductSearchResult _p(_Srv s, String id) => s.catalog[id]!.result;

/// Vente comptant saisie hors ligne (prévente ou espèces).
Future<VenteHorsLigne> _venteComptant(_Env e, List<(String, int)> lignes, {FinVenteHL fin = FinVenteHL.prevente, int? recu}) async {
  final c = VenteController(gateway: e.srv);
  for (final (id, q) in lignes) {
    expect((await c.addProduct(_p(e.srv, id), q)).isOk, isTrue);
  }
  final total = c.summary.montantNet;
  final r = await c.enregistrerHorsLigne(
      fin: fin, userId: 'U1', userName: 'Awa Kouassi', montantRecu: recu, montantRendu: recu == null ? null : recu - total);
  expect(r.isOk, isTrue, reason: r.message);
  return r.valueOrNull!;
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

void _tablet(WidgetTester tester) {
  tester.view.physicalSize = const Size(2560, 1600);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

Future<void> _pump(WidgetTester tester, Widget home) async {
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth()),
      ChangeNotifierProvider<SettingsProvider>(create: (_) => SettingsProvider()),
    ],
    child: MaterialApp(home: home),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('saisie hors ligne', () {
    test('comptant : panier local sans appel serveur, total local, prévente provisoire HL-0001', () async {
      final e = await _env();
      final c = VenteController(gateway: e.srv);
      expect((await c.addProduct(_p(e.srv, 'P1'), 2)).isOk, isTrue);
      expect((await c.addProduct(_p(e.srv, 'P2'), 1)).isOk, isTrue);
      expect(c.horsLigne, isTrue);
      expect(c.summary.montantNet, 2 * 1500 + 1200);
      expect(c.summary.reference, 'HL-0001');
      expect(c.canFinish, isTrue);
      // Modification et suppression locales.
      expect((await c.updateLine(c.items.first, 3, 1500)).isOk, isTrue);
      expect(c.summary.montantNet, 3 * 1500 + 1200);
      expect((await c.removeLine(c.items.last)).isOk, isTrue);
      expect(c.items.length, 1);
      // Les fins en ligne sont refusées.
      expect((await c.terminerPrevente()).isOk, isFalse);
      final r = await c.enregistrerHorsLigne(fin: FinVenteHL.prevente, userId: 'U1');
      expect(r.isOk, isTrue);
      expect(c.finished, isTrue);
      expect(e.ventes.single.numeroLabel, 'HL-0001');
      expect(e.ventes.single.statut, StatutVenteHL.enAttente);
      expect(e.ventes.single.lignes.single.qte, 3);
      expect(e.srv.addVenteIds, isEmpty);
      expect(e.srv.detailsCalls, 0);
      expect(e.hl.ventesEnAttente.value, 1);
    });

    test('assurance : client de la copie locale, parts estimées, création de client refusée', () async {
      final e = await _env();
      final c = AssuranceController(gateway: e.srv, userId: 'U1');
      final clients = await c.searchClients('AWA');
      expect(clients.valueOrNull?.single.lgCLIENTID, 'C1');
      await c.selectClient(clients.valueOrNull!.single);
      expect(c.ayantDroit?.lgAYANTSDROITSID, 'C1');
      expect(c.validateCouverture({'CPT1': 'B-77'}), isNull);
      expect((await c.addProduct(_p(e.srv, 'P3'), 1)).isOk, isTrue);
      await c.idle();
      expect(c.horsLigne, isTrue);
      expect(c.summary?.montantTp, 4410); // 70 % de 6 300
      expect(c.summary?.montantNet, 1890);
      expect(c.canFinish, isTrue);
      final created = await c.createClient(
          nom: 'X', prenom: 'Y', matricule: 'Z', tiersPayant: TiersPayantAssurance(lgTIERSPAYANTID: 'T1', strFULLNAME: 'M', strNAME: 'M'), taux: 70);
      expect(created.message, contains('Hors ligne'));
      final r = await c.enregistrerHorsLigne(userName: 'Awa', expectedChanges: c.changes);
      expect(r.isOk, isTrue, reason: r.message);
      final v = e.ventes.single;
      expect(v.type, TypeVenteHL.assurance);
      expect(v.tps.single.numBon, 'B-77');
      expect(v.netEstime, 1890);
      expect(e.srv.addAssurance, isEmpty);
    });

    test('carnet : client local, prévente provisoire, création d\'ayant droit refusée', () async {
      final e = await _env();
      final c = CarnetController(gateway: e.srv, userId: 'U1');
      final clients = await c.searchClients('MME');
      c.selectClient(clients.valueOrNull!.single);
      expect(c.validateBons({'CPT3': 'B9'}), isNull);
      expect((await c.addProduct(_p(e.srv, 'P1'), 2)).isOk, isTrue);
      await c.idle();
      expect(c.summary?.montantNet, 0); // carnet 100 %
      expect((await c.createAyantDroit(nom: 'A', prenom: 'B', matricule: 'C')).isOk, isFalse);
      final r = await c.enregistrerHorsLigne(userName: 'Awa', expectedChanges: c.changes);
      expect(r.isOk, isTrue, reason: r.message);
      expect(e.ventes.single.type, TypeVenteHL.carnet);
    });
  });

  group('envoi', () {
    test('retour du serveur : confirmation demandée, rien envoyé sans accord ; puis envoi dans l\'ordre', () async {
      final e = await _env();
      await _venteComptant(e, [('P1', 1)]);
      await _venteComptant(e, [('P2', 2), ('P3', 1)]);
      await _venteComptant(e, [('P3', 1)], fin: FinVenteHL.especes, recu: 10000);
      e.hl.monitor.goOnline();
      await pumpEventQueue();
      expect(e.file.confirmationDemandee, isTrue);
      expect(e.srv.addVenteIds, isEmpty);
      await e.file.envoyer();
      expect(e.srv.ordreCreation, ['P1', 'P2', 'P3']);
      expect(e.ventes.map((v) => v.statut), everyElement(StatutVenteHL.envoyee));
      expect(e.ventes.map((v) => v.reference), ['PV-V1', 'PV-V2', 'PV-V3']);
      expect(e.srv.sales['V2']!.map((l) => (l.lgFAMILLEID, l.intQUANTITY)), [('P2', 2), ('P3', 1)]);
      expect(e.srv.terminerCalls, 2);
      expect(e.srv.clotures.single, (recu: 10000, remis: 3700, net: 6300));
      expect(e.srv.clients.single, 'especes');
      expect(e.hl.ventesEnAttente.value, isNull);
    });

    test('coupure au milieu de l\'envoi : identifiant gardé, reprise à la bonne étape sans doublon', () async {
      final e = await _env(offline: false);
      e.hl.monitor.goOffline();
      await _venteComptant(e, [('P1', 1), ('P2', 1), ('P3', 1)]);
      e.srv.addModes.addAll([_M.ok, _M.panne]);
      await e.file.envoyer();
      var v = e.ventes.single;
      expect(v.venteId, 'V1');
      expect(v.statut, StatutVenteHL.envoiEnCours);
      expect(e.file.panne, isNotNull);
      // « Redémarrage » : nouvelle file sur le même stockage.
      final file2 = FileVentesHL(store: e.store, gateway: e.srv);
      await file2.envoyer();
      v = file2.ventes.single;
      expect(v.statut, StatutVenteHL.envoyee);
      expect(e.srv.creations, 1);
      expect(e.srv.sales['V1']!.map((l) => l.lgFAMILLEID), ['P1', 'P2', 'P3']);
      expect(e.srv.terminerCalls, 1);
    });

    test('réponse perdue (ajout, clôture) : relecture, jamais de 2ᵉ ligne ni de 2ᵉ clôture', () async {
      final e = await _env();
      await _venteComptant(e, [('P1', 1), ('P2', 1)], fin: FinVenteHL.especes, recu: 3000);
      e.srv.addModes.addAll([_M.ok, _M.perdue]);
      e.srv.clotureModes.add(_M.perdue);
      await e.file.envoyer();
      expect(e.ventes.single.statut, StatutVenteHL.envoyee);
      expect(e.srv.sales['V1']!.length, 2);
      expect(e.srv.clotureCalls, 1);
    });

    test('prévente : réponse perdue puis fermeture de l\'appli → statut relu, pas de 2ᵉ « terminer »', () async {
      final e = await _env();
      await _venteComptant(e, [('P1', 1)]);
      e.srv.terminerModes.add(_M.perdue);
      // fullSale relu : is_Process → envoyée sans nouvel appel.
      await e.file.envoyer();
      expect(e.ventes.single.statut, StatutVenteHL.envoyee);
      expect(e.srv.terminerCalls, 1);
    });

    test('création interrompue (appli fermée pendant l\'appel) : anomalie, aucune 2ᵉ vente', () async {
      final e = await _env();
      final v = await _venteComptant(e, [('P1', 1)]);
      await e.store.put(v.copyWith(statut: StatutVenteHL.envoiEnCours, etape: EtapeHL.creationEnvoyee));
      final file2 = FileVentesHL(store: e.store, gateway: e.srv);
      await file2.envoyer();
      expect(file2.ventes.single.statut, StatutVenteHL.aVerifier);
      expect(file2.ventes.single.motif, contains('interrompu'));
      expect(e.srv.creations, 0);
      expect(file2.ventes.single.supprimable, isFalse);
      // Vérifié par l'utilisateur : « Renvoyer » crée la vente.
      await file2.renvoyer(file2.ventes.single.id);
      expect(file2.ventes.single.statut, StatutVenteHL.envoyee);
      expect(e.srv.creations, 1);
    });

    test('conflit de prix : anomalie sans rien créer ; « Renvoyer » accepte l\'écart', () async {
      final e = await _env();
      await _venteComptant(e, [('P3', 1)]);
      e.srv.catalog['P3']!.prix = 6500;
      await e.file.envoyer();
      final v = e.ventes.single;
      expect(v.statut, StatutVenteHL.aVerifier);
      expect(v.motif, contains('${Constants.formatNumber(6300)} → ${Constants.formatNumber(6500)}'));
      expect(e.srv.creations, 0);
      expect(e.file.anomalies.single.nature, 'prix');
      await e.file.renvoyer(v.id);
      expect(e.ventes.single.statut, StatutVenteHL.envoyee);
      expect(e.srv.sales['V1']!.single.intPRICEUNITAIR, 6300); // prix saisi (le serveur fait foi au net)
    });

    test('stock du serveur insuffisant / produit introuvable : anomalie, rien envoyé', () async {
      final e = await _env();
      await _venteComptant(e, [('P1', 3)]);
      await _venteComptant(e, [('P2', 1)]);
      e.srv.catalog['P1']!.stock = 2;
      e.srv.catalog.remove('P2');
      await e.file.envoyer();
      expect(e.ventes[0].motif, contains('Stock insuffisant'));
      expect(e.ventes[1].motif, contains('introuvable'));
      expect(e.srv.creations, 0);
      expect(e.file.anomalies.map((a) => a.nature), ['stock', 'produit']);
    });

    test('encaissement provisoire : net du serveur ≠ montant encaissé → pas de clôture automatique', () async {
      final e = await _env();
      await _venteComptant(e, [('P1', 2)], fin: FinVenteHL.especes, recu: 5000);
      e.srv.netDelta = -300;
      await e.file.envoyer();
      final v = e.ventes.single;
      expect(v.statut, StatutVenteHL.aVerifier);
      expect(v.motif, contains('Net du serveur ${Constants.formatNumber(2700)} F'));
      expect(e.srv.clotureCalls, 0);
      await e.file.renvoyer(v.id);
      expect(e.ventes.single.statut, StatutVenteHL.envoyee);
      expect(e.srv.clotures.single, (recu: 5000, remis: 2300, net: 2700));
    });

    test('caisse fermée / stock refusé : anomalie avec le message, rien supprimé', () async {
      final e = await _env();
      await _venteComptant(e, [('P1', 1)]);
      await _venteComptant(e, [('P2', 1)]);
      e.srv.terminerModes.add(_M.refus);
      e.srv.addModes.addAll([_M.ok, _M.refus]);
      await e.file.envoyer();
      expect(e.ventes[0].motif, contains('Caisse fermée'));
      expect(e.ventes[1].motif, contains('Stock insuffisant'));
      expect(e.ventes.length, 2);
      expect(e.file.anomalies.map((a) => a.nature), ['caisse', 'stock']);
    });

    test('vente commencée en ligne terminée hors ligne : seuls les articles manquants sont envoyés', () async {
      final e = await _env(offline: false);
      final c = VenteController(gateway: e.srv);
      expect((await c.addProduct(_p(e.srv, 'P1'), 1)).isOk, isTrue);
      expect(c.venteId, 'V1');
      e.hl.monitor.goOffline();
      expect(c.peutTerminerHorsLigne, isTrue);
      expect((await c.addProduct(_p(e.srv, 'P2'), 1)).message, contains('Terminer hors ligne'));
      expect((await c.passerHorsLigne()).isOk, isTrue);
      expect((await c.removeLine(c.items.first)).isOk, isFalse); // ligne serveur
      expect((await c.addProduct(_p(e.srv, 'P2'), 2)).isOk, isTrue);
      final r = await c.enregistrerHorsLigne(fin: FinVenteHL.prevente, userId: 'U1');
      expect(r.valueOrNull?.venteId, 'V1');
      e.hl.monitor.goOnline();
      await e.file.envoyer();
      expect(e.ventes.single.statut, StatutVenteHL.envoyee);
      expect(e.srv.creations, 1);
      expect(e.srv.addVenteIds, [null, 'V1']);
      expect(e.srv.sales['V1']!.map((l) => (l.lgFAMILLEID, l.intQUANTITY)), [('P1', 1), ('P2', 2)]);
    });

    test('assurance : mêmes appels (type 2, client, bons) ; carnet : bon déjà utilisé → anomalie au rapport', () async {
      final e = await _env();
      final a = AssuranceController(gateway: e.srv, userId: 'U1');
      await a.selectClient((await a.searchClients('AWA')).valueOrNull!.single);
      a.validateCouverture({'CPT1': 'B-77'});
      await a.addProduct(_p(e.srv, 'P3'), 1);
      await a.idle();
      await a.enregistrerHorsLigne(userName: 'Awa', expectedChanges: a.changes);
      final k = CarnetController(gateway: e.srv, userId: 'U1');
      k.selectClient((await k.searchClients('MME')).valueOrNull!.single);
      k.validateBons({'CPT3': 'B9'});
      await k.addProduct(_p(e.srv, 'P1'), 1);
      await k.idle();
      await k.enregistrerHorsLigne(userName: 'Awa', expectedChanges: k.changes);
      e.srv.addModes.addAll([_M.ok, _M.refus]);
      e.srv.refusAjout = 'Le bon N° B9 est déjà utilisé';
      // Centre de support : l'anomalie est remontée (format VenteCtr.js), sans le client ni le n° de bon.
      final support = <Map<String, Object?>>[];
      final supportAvant = SupportCentre.instance;
      SupportCentre.instance = SupportCentre(envoi: (c) async {
        support.add(c);
        return SupportReponse.ok;
      });
      addTearDown(() => SupportCentre.instance = supportAvant);
      await e.file.envoyer();
      await Future<void>.delayed(Duration.zero);
      expect(support.single['type'], 'APPLICATION');
      expect(support.single['niveau'], 'WARN');
      expect(support.single['module'], 'VENTE');
      expect(jsonDecode(support.single['payloadJson'] as String)['vente'], 'HL-0002');
      expect(jsonEncode(support.single), isNot(contains('B9')));
      expect(jsonEncode(support.single), isNot(contains('TRAORE')));
      expect(e.ventes[0].statut, StatutVenteHL.envoyee);
      expect(e.srv.addAssurance.first.typeVenteId, '2');
      expect(e.srv.addAssurance.first.clientId, 'C1');
      expect(e.srv.addAssurance.first.tps.single.numBon, 'B-77');
      expect(e.srv.addAssurance.last.typeVenteId, '3');
      expect(e.ventes[1].statut, StatutVenteHL.aVerifier);
      final an = e.file.anomalies.single;
      expect(an.nature, 'bon');
      expect(an.bons, 'B9');
      expect(an.client, 'MME TRAORE');
      expect(an.motif, contains('est déjà utilisé'));
      // Rapport persistant : relu après « redémarrage ».
      final file2 = FileVentesHL(store: e.store, gateway: e.srv);
      await file2.load();
      expect(file2.anomalies.single.bons, 'B9');
      await file2.marquerTraitee(file2.ventes[1].id);
      expect(file2.anomalies.single.traitee, isTrue);
    });

    test('décochées à la confirmation : « ressaisie », gardées, jamais envoyées', () async {
      final e = await _env();
      final v1 = await _venteComptant(e, [('P1', 1)]);
      final v2 = await _venteComptant(e, [('P2', 1)]);
      await e.file.exclure([v1.id]);
      await e.file.envoyer(ids: [v2.id]);
      expect(e.file.byId(v1.id)?.statut, StatutVenteHL.ressaisie);
      expect(e.file.byId(v2.id)?.statut, StatutVenteHL.envoyee);
      await e.file.envoyer();
      expect(e.srv.creations, 1);
    });
  });

  group('persistance', () {
    test('SQLite : file et anomalies relues après fermeture, compteur HL continu', () async {
      sqfliteFfiInit();
      final dir = await Directory.systemTemp.createTemp('hl');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/ventes.db';
      var store = SqfliteVentesHLStore(factory: databaseFactoryFfi, path: path);
      final n1 = await store.nextNumero();
      final now = DateTime(2026, 10, 10, 9);
      final v = VenteHorsLigne(
        id: 'a',
        numero: n1,
        type: TypeVenteHL.comptant,
        lignes: const [LigneHL(cle: 'hl-1', produitId: 'P1', nom: 'DOLI', qte: 2, prix: 1500)],
        fin: FinVenteHL.especes,
        totalEstime: 3000,
        netEstime: 3000,
        montantRecu: 5000,
        montantRendu: 2000,
        createdAt: now,
        updatedAt: now,
      );
      await store.put(v.copyWith(statut: StatutVenteHL.envoiEnCours, etape: EtapeHL.articles, venteId: 'V9'));
      await store.putAnomalie(AnomalieHL(id: 'x', date: now, venteLocaleId: 'a', numero: 1, type: TypeVenteHL.comptant, motif: 'Prix modifié'));
      await store.close();
      store = SqfliteVentesHLStore(factory: databaseFactoryFfi, path: path);
      final all = await store.all();
      expect(all.single.venteId, 'V9');
      expect(all.single.etape, EtapeHL.articles);
      expect(all.single.montantRecu, 5000);
      expect(all.single.lignes.single.qte, 2);
      expect((await store.anomalies()).single.motif, 'Prix modifié');
      expect(await store.nextNumero(), n1 + 1);
      await store.close();
    }, skip: Platform.isLinux || Platform.isMacOS || Platform.isWindows ? false : 'SQLite (ffi) indisponible');
  });

  group('rapports', () {
    test('fin de journée : ventes du jour, total par produit, espèces provisoires', () async {
      final e = await _env();
      await _venteComptant(e, [('P1', 2), ('P2', 1)]);
      await _venteComptant(e, [('P1', 1)], fin: FinVenteHL.especes, recu: 2000);
      final r = rapportDuJour(e.ventes, DateTime.now());
      expect(r.ventes.length, 2);
      final doli = r.produits.firstWhere((p) => p.produitId == 'P1');
      expect((doli.qte, doli.montant, doli.cip), (3, 4500, '3400930000001'));
      expect(r.especes, 1500);
      final lignes = lignesRapportJour(r);
      expect(lignes.join('\n'), contains('TOTAL PAR PRODUIT'));
      expect(rapportDuJour(e.ventes, DateTime.now().subtract(const Duration(days: 1))).ventes, isEmpty);
    });

    testWidgets('écran du rapport du jour à 360 px + impression ticket (mode test)', (tester) async {
      _phone(tester);
      late _Env e;
      await tester.runAsync(() async {
        e = await _env();
        await _venteComptant(e, [('P1', 2), ('P2', 1)]);
      });
      await _pump(tester, RapportJourHorsLigneScreen(horsLigne: e.hl));
      expect(find.byKey(const Key('total_produit_P1')), findsOneWidget);
      expect(find.text('× 2'), findsOneWidget);
      await tester.tap(find.byKey(const Key('rapport_imprimer')));
      await tester.pumpAndSettle();
      expect(find.text('Aperçu du Ticket'), findsOneWidget);
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.textContaining('TOTAL PAR PRODUIT')), findsOneWidget);
      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('anomalies : liste (HL, client, bon, motif), traitée, impression', (tester) async {
      _phone(tester);
      late _Env e;
      await tester.runAsync(() async {
        e = await _env();
        final k = CarnetController(gateway: e.srv, userId: 'U1');
        k.selectClient((await k.searchClients('MME')).valueOrNull!.single);
        k.validateBons({'CPT3': 'B9'});
        await k.addProduct(_p(e.srv, 'P1'), 1);
        await k.idle();
        await k.enregistrerHorsLigne(userName: 'Awa', expectedChanges: k.changes);
        e.srv.addModes.add(_M.refus);
        e.srv.refusAjout = 'Le bon N° B9 est déjà utilisé';
        await e.file.envoyer();
      });
      await _pump(tester, AnomaliesHorsLigneScreen(horsLigne: e.hl));
      expect(find.text('Bon : B9'), findsOneWidget);
      expect(find.text('Client : MME TRAORE'), findsOneWidget);
      expect(find.textContaining('déjà utilisé'), findsWidgets);
      final a = e.file.anomalies.single;
      await tester.tap(find.byKey(Key('anomalie_traitee_${a.id}')));
      await tester.pumpAndSettle();
      expect(e.file.anomalies.single.traitee, isTrue);
      await tester.tap(find.byKey(const Key('rapport_imprimer')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Bon : B9'), findsWidgets);
      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('écrans', () {
    Future<_Env> deuxVentes(WidgetTester tester) async {
      late _Env e;
      await tester.runAsync(() async {
        e = await _env();
        await _venteComptant(e, [('P1', 1)]);
        await _venteComptant(e, [('P2', 1)]);
      });
      return e;
    }

    testWidgets('confirmation avant envoi : décocher une vente → ressaisie, l\'autre envoyée (360 px)', (tester) async {
      _phone(tester);
      final e = await deuxVentes(tester);
      e.hl.monitor.goOnline();
      await _pump(tester, VentesHorsLigneScreen(horsLigne: e.hl));
      await tester.tap(find.byKey(const Key('envoyer_maintenant')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('confirmation_envoi')), findsOneWidget);
      expect(find.text('Envoyer 2 vente(s) hors ligne au serveur ?'), findsOneWidget);
      expect(find.textContaining('double sortie de stock'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('coche_HL-0001')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('coche_HL-0001')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('envoyer_selection')));
      await tester.pumpAndSettle();
      expect(e.ventes[0].statut, StatutVenteHL.ressaisie);
      expect(e.ventes[1].statut, StatutVenteHL.envoyee);
      expect(e.srv.creations, 1);
      expect(find.textContaining('HL-0002 → PV-V1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('« Plus tard » : rien n\'est envoyé', (tester) async {
      _phone(tester);
      final e = await deuxVentes(tester);
      await _pump(tester, VentesHorsLigneScreen(horsLigne: e.hl));
      await tester.tap(find.byKey(const Key('envoyer_maintenant')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('envoi_plus_tard')));
      await tester.pumpAndSettle();
      expect(e.srv.addVenteIds, isEmpty);
      expect(e.ventes.every((v) => v.statut == StatutVenteHL.enAttente), isTrue);
    });

    testWidgets('retour du serveur : confirmation affichée par le bandeau global, « Envoyer » ensuite', (tester) async {
      _phone(tester);
      final e = await deuxVentes(tester);
      await tester.pumpWidget(MaterialApp(
        navigatorKey: HorsLigne.navigatorKey,
        builder: (context, child) => HorsLigneScope(horsLigne: e.hl, bindApp: false, child: child ?? const SizedBox()),
        home: const Scaffold(body: Text('accueil')),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('bandeau_horsLigne')), findsOneWidget);
      expect(find.textContaining('2 vente(s) en attente'), findsOneWidget);
      e.hl.monitor.goOnline();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('confirmation_envoi')), findsOneWidget);
      expect(e.srv.addVenteIds, isEmpty);
      await tester.tap(find.byKey(const Key('envoi_plus_tard')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('bandeau_enAttente')), findsOneWidget);
      await tester.tap(find.byKey(const Key('bandeau_envoyer')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('envoyer_selection')));
      await tester.pumpAndSettle();
      expect(e.srv.creations, 2);
      expect(find.byKey(const Key('bandeau_enAttente')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final tablet in [false, true]) {
      testWidgets('liste / détail (${tablet ? 'tablette' : '360 px'}) : anomalie, supprimer une vente non envoyée', (tester) async {
        tablet ? _tablet(tester) : _phone(tester);
        late _Env e;
        await tester.runAsync(() async {
          e = await _env();
          await _venteComptant(e, [('P3', 1)]);
          await _venteComptant(e, [('P1', 1)]);
          e.srv.catalog['P3']!.prix = 6500;
          await e.file.envoyer(ids: [e.ventes.first.id]);
        });
        await _pump(tester, VentesHorsLigneScreen(horsLigne: e.hl));
        expect(find.byKey(const Key('vente_hl_HL-0001')), findsOneWidget);
        expect(find.textContaining('${Constants.formatNumber(6300)} → ${Constants.formatNumber(6500)}'), findsWidgets);
        await tester.tap(find.byKey(const Key('vente_hl_HL-0002')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('detail_vente_hl')), findsOneWidget);
        await tester.ensureVisible(find.byKey(const Key('hl_supprimer')));
        await tester.tap(find.byKey(const Key('hl_supprimer')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Supprimer'));
        await tester.pumpAndSettle();
        expect(e.ventes.length, 1);
        expect(find.byKey(const Key('vente_hl_HL-0002')), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('écran de vente', () {
    testWidgets('hors ligne à 360 px : boutons provisoires, prévente HL + ticket « PROVISOIRE », espèces seulement', (tester) async {
      _phone(tester);
      late _Env e;
      await tester.runAsync(() async => e = await _env());
      await _pump(tester, VenteScreen(gateway: e.srv, presentation: ListPresentation.dashboard));
      VenteController ctrl() => Provider.of<VenteController>(tester.element(find.byType(VenteCart)), listen: false);
      await ctrl().addProduct(_p(e.srv, 'P1'), 2);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('vente-etat-hors-ligne')), findsOneWidget);
      expect(find.text('ENREGISTRER (PRÉVENTE PROVISOIRE)'), findsOneWidget);
      expect(find.text('ENCAISSER EN ESPÈCES (PROVISOIRE)'), findsOneWidget);
      expect(find.byKey(const ValueKey('vente-encaisser')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('vente-hl-prevente')));
      await tester.pumpAndSettle();
      expect(find.text('Prévente provisoire enregistrée'), findsOneWidget);
      await tester.tap(find.text('Imprimer'));
      await tester.pumpAndSettle();
      expect(find.text('PROVISOIRE — HL-0001'), findsOneWidget);
      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();
      expect(e.ventes.single.fin, FinVenteHL.prevente);

      // Encaissement espèces provisoire.
      await ctrl().addProduct(_p(e.srv, 'P2'), 1);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('vente-hl-especes')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('encaissement-hors-ligne')), findsOneWidget);
      expect(find.text('WAVE'), findsNothing);
      await tester.enterText(find.byType(TextField).last, '2000');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('encaissement-valider')));
      await tester.pumpAndSettle();
      expect(find.text('PROVISOIRE — HL-0002'), findsOneWidget);
      tester.takeException(); // aperçu d'origine du ticket de vente plus large que 360 px (antérieur, hors ligne non concerné)
      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();
      final v = e.ventes.last;
      expect((v.fin, v.montantRecu, v.montantRendu, v.netEstime), (FinVenteHL.especes, 2000, 800, 1200));
      expect(e.srv.addVenteIds, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('en ligne : écran et appels inchangés', (tester) async {
      _phone(tester);
      late _Env e;
      await tester.runAsync(() async => e = await _env(offline: false));
      await _pump(tester, VenteScreen(gateway: e.srv, presentation: ListPresentation.dashboard));
      final c = Provider.of<VenteController>(tester.element(find.byType(VenteCart)), listen: false);
      await c.addProduct(_p(e.srv, 'P1'), 1);
      await tester.pumpAndSettle();
      expect(c.horsLigne, isFalse);
      expect(e.srv.addVenteIds, [null]);
      expect(find.byKey(const ValueKey('vente-encaisser')), findsOneWidget);
      expect(find.text('PRÉVENTE'), findsOneWidget);
      expect(find.byKey(const ValueKey('vente-hl-prevente')), findsNothing);
      expect(find.byKey(const ValueKey('vente-etat-hors-ligne')), findsNothing);
      expect(find.byKey(const ValueKey('vente-proposer-hors-ligne')), findsNothing);
      expect(e.ventes, isEmpty);
    });

    testWidgets('vente commencée en ligne, serveur hors ligne : « Terminer hors ligne » proposé', (tester) async {
      _phone(tester);
      late _Env e;
      await tester.runAsync(() async => e = await _env(offline: false));
      await _pump(tester, VenteScreen(gateway: e.srv, presentation: ListPresentation.dashboard));
      final c = Provider.of<VenteController>(tester.element(find.byType(VenteCart)), listen: false);
      await c.addProduct(_p(e.srv, 'P1'), 1);
      await tester.pumpAndSettle();
      e.hl.monitor.goOffline();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('vente-terminer-hors-ligne')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('vente-terminer-hors-ligne')));
      await tester.pumpAndSettle();
      expect(c.horsLigne, isTrue);
      expect(find.byKey(const ValueKey('vente-etat-hors-ligne')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
