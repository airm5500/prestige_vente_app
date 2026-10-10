// Hors ligne (étape H1) : surveillance du serveur (3 échecs → injoignable, appui → hors ligne,
// retour automatique, premier plan seulement), synchro par pages (ancienne copie gardée si échec),
// recherche locale (commence par / contient / code exact + EAN → CIP7), recherche des nouveaux écrans
// hors ligne vs en ligne inchangée, bandeau global, rubrique Réglages, 360 px.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/accueil/recherche_globale_screen.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/client_assurance.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/tiers_payant_assurance.dart';
import 'package:prestige_vente_app/horsligne/catalogue_sync.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/horsligne_ui.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart';
import 'package:prestige_vente_app/horsligne/server_monitor.dart';
import 'package:prestige_vente_app/parametres/hors_ligne_page.dart';
import 'package:prestige_vente_app/parametres/parametres_logic.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/services/product_finder.dart';
import 'package:prestige_vente_app/services/search_mode.dart';
import 'package:prestige_vente_app/ventes/assurance/assurance_controller.dart';
import 'package:prestige_vente_app/ventes/carnet/carnet_controller.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _t0 = DateTime(2026, 10, 10, 8, 30);

Map<String, dynamic> _prod(String id, String name, String cip, {int stock = 3, String? ean}) => {
      'lgFAMILLEID': id,
      'strNAME': name,
      'intCIP': cip,
      'intPRICE': 1000,
      'intNUMBERAVAILABLE': stock,
      'strLIBELLEE': 'RAYON A',
      'intPAF': 800,
      'lgFAMILLEPARENTID': '',
      'boolDECONDITIONNE': 0,
      if (ean != null) 'codeEanFabriquant': ean,
    };

final _local = [
  _prod('d1', 'DOLIPRANE 1000MG CP B/8', '3017598'),
  _prod('d2', 'DOLIPRANE 500MG CP B/16', '3017599'),
  _prod('e1', 'EFFERALGAN 1000MG CP B/8', '3595548', ean: '6181100012345'),
  _prod('p1', 'PARACETAMOL DOLI 1000', '3595549'),
  _prod('a1', 'ÉLUDRIL PRO SOLUTION', '2223334'),
  _prod('b1', 'BETADINE 10% DERM', '4445556'),
];

Map<String, dynamic> _client(String id, String first, String last, String type) => {
      'lgCLIENTID': id,
      'strFIRSTNAME': first,
      'strLASTNAME': last,
      'fullName': '$first $last',
      'strNUMEROSECURITESOCIAL': '38$id',
      'strCODEINTERNE': 'C$id',
      'lgTYPECLIENTID': type,
      'tiersPayants': [],
    };

/// Faux serveur Prestige : produits paginés (start/limit), clients et tiers payants renvoyés
/// d'un coup (le vrai serveur ignore start/limit sur ces routes).
class _Server {
  List<Map<String, dynamic>> produits;
  List<Map<String, dynamic>> clientsA = [_client('1', 'AWA', 'KOUASSI', '1'), _client('2', 'JEAN', 'KONAN', '1')];
  List<Map<String, dynamic>> clientsC = [_client('3', 'MME', 'TRAORE', '2')];
  List<Map<String, dynamic>> tpA = [
    {'lgTIERSPAYANTID': 't1', 'strNAME': 'CMU', 'strFULLNAME': 'CMU'},
    {'lgTIERSPAYANTID': 't2', 'strNAME': 'MUGEFCI', 'strFULLNAME': 'MUGEFCI'},
  ];
  List<Map<String, dynamic>> tpC = [
    {'lgTIERSPAYANTID': 't3', 'strNAME': 'DEPOT GOKRA', 'strFULLNAME': 'DEPOT GOKRA'},
  ];
  int calls = 0;
  int? failAtCall;

  /// Total annoncé par /client/all (absent : la fin se voit à une page sans nouveauté).
  bool clientsTotal = true;
  final log = <String>[];

  _Server(this.produits);

  Future<Map<String, dynamic>> fetch(String path, Map<String, dynamic> q) async {
    calls++;
    log.add('$path ${q['typeClientId'] ?? ''}${q['start']}');
    if (failAtCall != null && calls >= failAtCall!) throw const CatalogueSyncException('Serveur injoignable.', network: true);
    switch (path) {
      case '/vente/search':
        expect(q['query'], '%');
        final start = q['start'] as int, limit = q['limit'] as int;
        expect(q['page'], start ~/ limit + 1);
        return {'total': produits.length, 'data': produits.skip(start).take(limit).toList()};
      case '/client/all':
        final l = q['typeClientId'] == '2' ? clientsC : clientsA;
        return {if (clientsTotal) 'total': l.length, 'data': l};
      case '/client/tiers-payants/assurance':
        return {'success': true, 'total': tpA.length, 'data': tpA};
      case '/client/tiers-payants/carnet':
        return {'success': true, 'total': tpC.length, 'data': tpC};
      case '/common/reglement':
        return {
          'total': 2,
          'data': [
            {'lgTYPEREGLEMENTID': '1', 'strNAME': 'Espèces'},
            {'lgTYPEREGLEMENTID': '10', 'strNAME': 'Wave'},
          ],
        };
      case '/modereglement/all':
        return {
          'total': 1,
          'data': [
            {'id': 'q1', 'name': 'WAVE', 'typeReglementId': '10', 'mobileMoney': true},
          ],
        };
    }
    throw CatalogueSyncException('route inconnue $path');
  }
}

List<Map<String, dynamic>> _catalogue(int n, {String prefix = 'PRODUIT'}) =>
    [for (var i = 0; i < n; i++) _prod('id$i', '$prefix ${i.toString().padLeft(5, '0')}', '${1000000 + i}', stock: i % 7)];

/// Faux serveur des recherches des écrans (stock 5 = serveur, 3 = copie locale).
List<ProductSearchResult> _serverLike(String query) {
  final re = likeRegExp(likePattern(query));
  return _local
      .map((m) => ProductSearchResult.fromJson({...m, 'intNUMBERAVAILABLE': 5}))
      .where((p) => re.hasMatch(foldText(p.strNAME)) || re.hasMatch(p.intCIP))
      .toList();
}

class _Api extends ApiService {
  _Api() : super(baseUrl: 'http://localhost');
  final sent = <String>[];

  @override
  Future<ProductPage> searchProductsPageOrFail(String query, int start, int limit) async {
    sent.add(query);
    final all = _serverLike(query);
    return ProductPage(all.skip(start).take(limit).toList(), all.length);
  }
}

class _Gw implements VenteGateway {
  final sent = <String>[];

  @override
  Future<VenteResult<ProductPage>> searchProductsPage(String query, int start, int limit) async {
    sent.add(query);
    final all = _serverLike(query);
    return VenteOk(ProductPage(all.skip(start).take(limit).toList(), all.length));
  }

  @override
  Future<VenteResult<List<ClientAssurance>>> searchClients(String query, {required String typeClientId}) async => const VenteOk([]);

  @override
  Future<VenteResult<List<TiersPayantAssurance>>> searchTiersPayants(String query, {required bool carnet}) async => const VenteOk([]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Instance de test (mémoire, horloge fixe) installée comme instance de l'appli.
Future<HorsLigne> _install({LocalStore? store, ServerPing? ping, DateTime Function()? clock}) async {
  final s = store ?? MemoryLocalStore();
  final c = clock ?? () => _t0;
  final hl = HorsLigne(monitor: ServerMonitor(ping: ping, clock: c), store: s, sync: CatalogueSync(store: s, clock: c));
  final previous = HorsLigne.instance;
  HorsLigne.instance = hl;
  addTearDown(() => HorsLigne.instance = previous);
  return hl;
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(720, 1400); // 360 x 700
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

/// Tests de recherche locale, exécutés sur les deux implémentations.
void _searchTests(String name, Future<LocalStore> Function() make) {
  group('recherche locale ($name)', () {
    late LocalStore store;
    setUp(() async {
      store = await make();
      await store.replace(CatalogueCategorie.produits, _local, _t0);
      final server = _Server(const []);
      await store.replace(CatalogueCategorie.clientsAssurance, server.clientsA, _t0);
      await store.replace(CatalogueCategorie.clientsCarnet, server.clientsC, _t0);
      await store.replace(CatalogueCategorie.tiersPayantsAssurance, server.tpA, _t0);
      await store.replace(CatalogueCategorie.modes, [
        {'lgTYPEREGLEMENTID': '1', 'strNAME': 'Espèces', '_kind': 'reglement'},
        {'id': 'q1', 'name': 'WAVE', '_kind': 'qr'},
      ], _t0);
    });

    List<String> names(ProductPage p) => p.items.map((e) => e.strNAME).toList();

    test('« Commence par » : début du nom, du CIP ; tri par nom ; pages', () async {
      expect(names(await store.searchProducts('DOLI', 0, 50)), ['DOLIPRANE 1000MG CP B/8', 'DOLIPRANE 500MG CP B/16']);
      expect(names(await store.searchProductsText('liprane', mode: SearchMode.commencePar)), isEmpty);
      expect(names(await store.searchProducts('35955', 0, 50)), ['EFFERALGAN 1000MG CP B/8', 'PARACETAMOL DOLI 1000']);
      final page = await store.searchProducts('%', 2, 2);
      expect(page.total, 6);
      expect(names(page), ['DOLIPRANE 500MG CP B/16', 'EFFERALGAN 1000MG CP B/8']);
      // Stock et prix connus.
      final d = (await store.searchProducts('DOLIPRANE 1000', 0, 50)).items.single;
      expect((d.lgFAMILLEID, d.intCIP, d.intPRICE, d.intNUMBERAVAILABLE, d.strLIBELLEE), ('d1', '3017598', 1000, 3, 'RAYON A'));
    });

    test('« Contient » (% devant et entre les mots), accents et majuscules ignorés', () async {
      expect(names(await store.searchProductsText('doli 1000', mode: SearchMode.contient)), ['DOLIPRANE 1000MG CP B/8', 'PARACETAMOL DOLI 1000']);
      expect((await store.searchProductsText('liprane', mode: SearchMode.contient)).total, 2);
      expect(names(await store.searchProducts('eludril', 0, 50)), ['ÉLUDRIL PRO SOLUTION']);
      // « Commence par » : % tapé neutralisé (comme en ligne).
      expect(names(await store.searchProductsText('BETADINE 10%', mode: SearchMode.commencePar)), ['BETADINE 10% DERM']);
      expect((await store.searchProductsText('%%', mode: SearchMode.contient)).total, 0);
    });

    test('code exact : CIP, EAN-13 34009 → CIP7, GTIN-14, EAN fabricant ; inconnu → null', () async {
      expect((await store.productByCode('3017598'))?.lgFAMILLEID, 'd1');
      expect((await store.productByCode('3400930175988'))?.lgFAMILLEID, 'd1');
      expect((await store.productByCode('03400930175988'))?.lgFAMILLEID, 'd1');
      expect((await store.productByCode('6181100012345'))?.lgFAMILLEID, 'e1');
      expect(await store.productByCode('9999999'), isNull);
      // Même logique que les écrans (ProductLookup.byCode sur la recherche locale).
      final r = await ProductLookup.byCode('3400930175988', (q, s, l) async => VenteOk(await store.searchProducts(q, s, l)));
      expect((r as VenteOk<CodeLookup>).value.exact?.lgFAMILLEID, 'd1');
    });

    test('clients, tiers payants, modes ; statistiques', () async {
      expect((await store.searchClients('kou', typeClientId: '1')).map((c) => c['lgCLIENTID']), ['1']);
      expect((await store.searchClients('%KON', typeClientId: '1')).map((c) => c['lgCLIENTID']), ['2']);
      expect(await store.searchClients('kou', typeClientId: '2'), isEmpty);
      expect((await store.searchClients('traore', typeClientId: '2')).single['fullName'], 'MME TRAORE');
      expect((await store.searchTiersPayants('mug', carnet: false)).single['lgTIERSPAYANTID'], 't2');
      expect((await store.modes(qr: false)).single['strNAME'], 'Espèces');
      expect((await store.modes(qr: true)).single['name'], 'WAVE');
      final s = await store.stats();
      expect(s.count(CatalogueCategorie.produits), 6);
      expect(s.clients, 3);
      expect(s.lastSync[CatalogueCategorie.produits], _t0);
      await store.clear();
      expect((await store.stats()).isEmpty, isTrue);
    });
  });
}

bool _ffiOk() {
  try {
    sqfliteFfiInit();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SearchModePrefs.mode.value = SearchMode.commencePar;
  });

  final ffi = _ffiOk() && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  _searchTests('mémoire', () async => MemoryLocalStore());
  if (ffi) {
    _searchTests('SQLite', () async => SqfliteLocalStore(factory: databaseFactoryFfi, path: inMemoryDatabasePath));
  }

  group('surveillance du serveur', () {
    test('3 échecs consécutifs → injoignable (depuis le 1ᵉʳ), appui → hors ligne, ping OK → en ligne', () async {
      var ok = false;
      var now = _t0;
      final m = ServerMonitor(ping: () async => ok, clock: () => now);
      await m.checkNow();
      now = now.add(const Duration(seconds: 30));
      await m.checkNow();
      expect(m.etat, EtatServeur.enLigne);
      now = now.add(const Duration(seconds: 30));
      await m.checkNow();
      expect(m.etat, EtatServeur.injoignable);
      expect(m.depuis, _t0);
      expect(m.isOffline, isFalse, reason: 'pas de bascule sans appui');

      m.goOffline(manuel: false);
      expect((m.etat, m.raison), (EtatServeur.horsLigne, RaisonHorsLigne.confirme));
      await m.checkNow();
      expect(m.isOffline, isTrue);

      ok = true;
      now = now.add(const Duration(minutes: 5));
      await m.checkNow();
      expect(m.etat, EtatServeur.enLigne);
      expect(m.retourAt, now);
      expect(m.echecs, 0);
    });

    test('une réponse entre deux échecs remet le compteur à zéro ; interrupteur manuel', () async {
      final m = ServerMonitor(ping: () async => false, clock: () => _t0);
      await m.checkNow();
      await m.checkNow();
      m.signalReachable();
      await m.checkNow();
      await m.checkNow();
      expect(m.etat, EtatServeur.enLigne);
      await m.checkNow();
      expect(m.etat, EtatServeur.injoignable);

      final m2 = ServerMonitor(ping: () async => true, clock: () => _t0);
      m2.goOffline();
      expect((m2.etat, m2.raison), (EtatServeur.horsLigne, RaisonHorsLigne.manuel));
      // Hors ligne manuel : le serveur répond, on RESTE hors ligne mais on le propose.
      await m2.checkNow();
      expect(m2.etat, EtatServeur.horsLigne);
      expect(m2.joignablePendantManuel, isTrue);
      m2.goOnline();
      await Future<void>.delayed(Duration.zero);
      expect(m2.etat, EtatServeur.enLigne);
    });

    testWidgets('ping toutes les 30 s au premier plan seulement ; échec d\'une opération → ping immédiat', (tester) async {
      var ok = true;
      final m = ServerMonitor(ping: () async => ok, clock: () => _t0);
      m.start();
      addTearDown(m.stop);
      await tester.pump(const Duration(seconds: 31));
      expect(m.pings, 1);
      await tester.pump(const Duration(seconds: 30));
      expect(m.pings, 2);

      // Arrière-plan : plus aucun ping.
      for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      await tester.pump(const Duration(minutes: 3));
      expect(m.pings, 2);
      expect(m.surveille, isFalse);
      // Retour au premier plan : ping immédiat, puis cadence de 30 s.
      for (final s in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      await tester.pump();
      expect(m.pings, 3);

      // Échec réseau d'une opération : vérification immédiate, puis 30 s entre deux pings (~1 min pour 3 échecs).
      ok = false;
      m.signalNetworkFailure();
      await tester.pump();
      expect((m.pings, m.echecs), (4, 1));
      m.signalNetworkFailure(); // déjà en cours de vérification : pas de rafale
      await tester.pump(const Duration(seconds: 29));
      expect(m.pings, 4);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 30));
      expect((m.pings, m.etat), (6, EtatServeur.injoignable));
      m.stop();
    });
  });

  group('synchro du catalogue', () {
    Future<void> syncTests(LocalStore store) async {
      final server = _Server(_catalogue(1234));
      final sync = CatalogueSync(store: store, fetch: server.fetch, clock: () => _t0, pageSize: 500);
      expect(await sync.syncAll(), isTrue, reason: sync.error);
      expect(server.log.where((l) => l.startsWith('/vente/search')), ['/vente/search 0', '/vente/search 500', '/vente/search 1000']);
      final s = sync.stats;
      expect(s.count(CatalogueCategorie.produits), 1234);
      expect((s.count(CatalogueCategorie.clientsAssurance), s.count(CatalogueCategorie.clientsCarnet)), (2, 1));
      expect((s.count(CatalogueCategorie.tiersPayantsAssurance), s.count(CatalogueCategorie.tiersPayantsCarnet)), (2, 1));
      expect(s.count(CatalogueCategorie.modes), 3);
      expect(sync.catalogueAt, _t0);
      expect(sync.warnings, isEmpty);

      // Nouvelle synchro qui échoue au milieu des produits : l'ancienne copie reste entière.
      final server2 = _Server(_catalogue(1500, prefix: 'NOUVEAU'))..failAtCall = 2;
      sync.fetch = server2.fetch;
      expect(await sync.syncAll(), isFalse);
      expect(sync.error, contains('Produits'));
      expect(server2.calls, 2, reason: 'serveur injoignable : on n\'essaie pas les catégories suivantes');
      expect(sync.stats.count(CatalogueCategorie.produits), 1234);
      expect((await store.searchProducts('PRODUIT 00123', 0, 50)).items.single.intCIP, '1000123');
      expect((await store.searchProducts('NOUVEAU', 0, 50)).total, 0);
    }

    test('par pages avec faux serveur, ancienne copie conservée si échec (mémoire)', () async {
      final store = MemoryLocalStore();
      await syncTests(store);
      // Écriture refusée : la copie précédente reste.
      store.failNextWrite = true;
      final sync = CatalogueSync(store: store, fetch: _Server(_catalogue(10, prefix: 'AUTRE')).fetch, clock: () => _t0);
      expect(await sync.syncAll(), isFalse);
      expect((await store.stats()).count(CatalogueCategorie.produits), 1234);
    });

    test('par pages, SQLite : transaction annulée si l\'écriture échoue', () async {
      final store = SqfliteLocalStore(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      await syncTests(store);
      // Ligne illisible au milieu de l'écriture : rien n'est remplacé.
      final bad = _catalogue(10, prefix: 'AUTRE')..add({..._prod('x', 'X', '1'), 'bizarre': Object()});
      await expectLater(store.replace(CatalogueCategorie.produits, bad, _t0), throwsA(anything));
      expect((await store.stats()).count(CatalogueCategorie.produits), 1234);
      expect((await store.searchProducts('AUTRE', 0, 50)).total, 0);
      await store.close();
    }, skip: ffi ? false : 'SQLite (ffi) indisponible');

    test('route qui ignore start/limit : pas de boucle ; synchro si la copie a plus de 12 h', () async {
      final store = MemoryLocalStore();
      final server = _Server(_catalogue(3))
        ..clientsA = [for (var i = 0; i < 700; i++) _client('$i', 'P$i', 'N$i', '1')]
        ..clientsTotal = false;
      var now = _t0;
      final sync = CatalogueSync(store: store, fetch: server.fetch, clock: () => now);
      expect(await sync.syncIfStale(), isTrue);
      expect(sync.stats.count(CatalogueCategorie.clientsAssurance), 700);
      expect(server.log.where((l) => l.startsWith('/client/all 1')).length, 2);
      final calls = server.calls;
      now = now.add(const Duration(hours: 11));
      expect(await sync.syncIfStale(), isTrue);
      expect(server.calls, calls, reason: 'copie de moins de 12 h');
      now = now.add(const Duration(hours: 2));
      await sync.syncIfStale();
      expect(server.calls, greaterThan(calls));
    });
  });

  group('recherche des nouveaux écrans', () {
    test('en ligne : serveur (inchangé) ; hors ligne : copie locale, serveur non appelé', () async {
      final hl = await _install();
      await hl.store.replace(CatalogueCategorie.produits, _local, _t0);
      final api = _Api();
      final search = PagedProductSearch(() => api);

      await search.run('doli');
      expect(api.sent, ['doli']);
      expect(search.items.map((p) => p.intNUMBERAVAILABLE).toSet(), {5});

      hl.monitor.goOffline();
      await search.run('doli');
      expect(api.sent, ['doli'], reason: 'aucun appel serveur hors ligne');
      expect(search.items.map((p) => p.strNAME), ['DOLIPRANE 1000MG CP B/8', 'DOLIPRANE 500MG CP B/16']);
      expect(search.items.map((p) => p.intNUMBERAVAILABLE).toSet(), {3});

      // Code scanné hors ligne : produit exact (EAN-13 → CIP7).
      await search.run('3400930175988');
      expect((search.byCode, search.items.single.lgFAMILLEID), (true, 'd1'));
      // « Contient » hors ligne.
      SearchModePrefs.mode.value = SearchMode.contient;
      await search.run('doli 1000');
      expect(search.items.map((p) => p.lgFAMILLEID), ['d1', 'p1']);
      expect(api.sent, ['doli']);
    });

    test('ventes (prévente, assurance, carnet) : searchPage local hors ligne seulement', () async {
      final hl = await _install();
      await hl.store.replace(CatalogueCategorie.produits, _local, _t0);
      final gw = _Gw();
      final pages = [
        VenteController(gateway: gw).searchPage,
        AssuranceController(gateway: gw, userId: 'U1').searchPage,
        CarnetController(gateway: gw, userId: 'U1').searchPage,
      ];
      for (final page in pages) {
        final r = await page('EFF', 0, 50);
        expect((r as VenteOk<ProductPage>).value.items.single.intNUMBERAVAILABLE, 5);
      }
      expect(gw.sent, ['EFF', 'EFF', 'EFF']);
      hl.monitor.goOffline();
      for (final page in pages) {
        final r = await page('EFF', 0, 50);
        expect((r as VenteOk<ProductPage>).value.items.single.intNUMBERAVAILABLE, 3);
      }
      expect(gw.sent.length, 3);
    });

    test('hors ligne sans copie locale : message clair (pas « introuvable »)', () async {
      final hl = await _install();
      hl.monitor.goOffline();
      final pager = ProductPager(offlineAware((q, s, l) async => const VenteOk(ProductPage([], 0))), 'doli');
      expect(await pager.loadMore(), isFalse);
      expect(pager.error, contains('aucun catalogue'));
    });

    testWidgets('recherche globale hors ligne : résultats locaux marqués « catalogue du … », 360 px', (tester) async {
      _phone(tester);
      final hl = await _install();
      await hl.store.replace(CatalogueCategorie.produits, _local, _t0);
      await hl.sync.refreshStats();
      hl.monitor.goOffline();
      final api = _Api();
      await tester.pumpWidget(MaterialApp(home: RechercheGlobaleScreen(menus: const [], onOpenMenu: (_) {}, api: () => api)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'doli');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(api.sent, isEmpty);
      expect(find.text('DOLIPRANE 1000MG CP B/8'), findsOneWidget);
      expect(find.text('Hors ligne : catalogue du 10/10 08:30 — stock connu à cette date'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // En ligne : rien de changé (pas de mention).
      hl.monitor.goOnline();
      await tester.enterText(find.byType(TextField), 'eff');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(api.sent, ['eff']);
      expect(find.byKey(const Key('note_catalogue_local')), findsNothing);
    });
  });

  group('bandeau', () {
    testWidgets('injoignable → [Continuer hors ligne] → hors ligne → de nouveau joignable, Navigator conservé, 360 px', (tester) async {
      _phone(tester);
      var ok = false;
      var now = DateTime(2026, 10, 10, 14, 32);
      final hl = await _install(ping: () async => ok, clock: () => now);
      await hl.store.replace(CatalogueCategorie.produits, _local, _t0);
      await hl.sync.refreshStats();
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: nav,
        builder: (context, child) => HorsLigneScope(horsLigne: hl, bindApp: false, child: child!),
        home: Scaffold(appBar: AppBar(title: const Text('Accueil')), body: const Text('corps')),
      ));
      nav.currentState!.push(MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('Vente')))));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('bandeau_injoignable')), findsNothing);

      // 2 échecs : rien ; 3ᵉ : bandeau, sans bascule.
      await hl.monitor.checkNow();
      now = now.add(const Duration(seconds: 30));
      await hl.monitor.checkNow();
      await tester.pump();
      expect(find.byKey(const Key('bandeau_injoignable')), findsNothing);
      now = now.add(const Duration(seconds: 30));
      await hl.monitor.checkNow();
      await tester.pump();
      expect(find.text('Serveur injoignable depuis 14:32'), findsOneWidget);
      expect(find.text('Vente'), findsOneWidget, reason: 'écran en cours conservé');
      expect(hl.offline, isFalse);

      await tester.tap(find.byKey(const Key('continuer_hors_ligne')));
      await tester.pump();
      expect(hl.offline, isTrue);
      expect(find.text('Hors ligne — catalogue du 10/10 08:30'), findsOneWidget);

      hl.ventesEnAttente.value = 0;
      await tester.pump();
      expect(find.text('Hors ligne — catalogue du 10/10 08:30 · 0 vente(s) en attente'), findsOneWidget);

      ok = true;
      await hl.monitor.checkNow();
      await tester.pump();
      expect(hl.offline, isFalse);
      expect(find.text('Serveur de nouveau joignable'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(find.byKey(const Key('bandeau_retour')), findsNothing);
      expect(find.text('Vente'), findsOneWidget);
      nav.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('Accueil'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('en ligne : aucun bandeau, mise en page identique', (tester) async {
      _phone(tester);
      final hl = await _install();
      Future<Rect> rectOf(bool scope) async {
        await tester.pumpWidget(MaterialApp(
          builder: scope ? (context, child) => HorsLigneScope(horsLigne: hl, bindApp: false, child: child!) : null,
          home: Scaffold(appBar: AppBar(title: const Text('Accueil'))),
        ));
        return tester.getRect(find.byType(AppBar));
      }

      final without = await rectOf(false);
      expect(await rectOf(true), without);
      expect(find.byType(HorsLigneBanner), findsNothing);
    });
  });

  testWidgets('branchement dans l\'appli : surveillance au premier plan, observateur des appels, rien affiché', (tester) async {
    final hl = await _install(ping: () async => true);
    final api = _Api();
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<ApiService>.value(value: api),
        ChangeNotifierProvider(create: (_) => AuthProvider(api)),
      ],
      child: MaterialApp(
        builder: (context, child) => HorsLigneScope(horsLigne: hl, child: child!),
        home: const Scaffold(body: Text('Accueil')),
      ),
    ));
    expect(hl.monitor.surveille, isTrue);
    expect(api.dio.interceptors.whereType<ServerMonitorInterceptor>().length, 1);
    expect(find.byType(HorsLigneBanner), findsNothing);
    await tester.pump(const Duration(seconds: 30));
    expect(hl.monitor.pings, 1);
    await tester.pumpWidget(const SizedBox());
    expect(hl.monitor.surveille, isFalse);
  });

  group('rubrique Réglages', () {
    test('rubrique « Hors ligne » trouvable, non verrouillée, résumé', () async {
      final hl = await _install();
      expect(Rubrique.values, contains(Rubrique.horsLigne));
      expect(Rubrique.horsLigne.locked, isFalse);
      expect(rubriqueMatches(Rubrique.horsLigne, '', 'coupure'), isTrue);
      expect(rubriqueMatches(Rubrique.horsLigne, '', 'copie locale'), isTrue);
      expect(horsLigneSummary(hl), 'En ligne · aucun catalogue local');
      await hl.store.replace(CatalogueCategorie.produits, _local, _t0);
      await hl.sync.refreshStats();
      hl.monitor.goOffline();
      expect(horsLigneSummary(hl), 'Hors ligne · catalogue du 10/10 08:30');
    });

    testWidgets('état, interrupteur, mise à jour, vider (confirmation), 360 px', (tester) async {
      _phone(tester);
      final hl = await _install(ping: () async => true);
      hl.sync.fetch = _Server(_catalogue(42)).fetch;
      await tester.pumpWidget(MaterialApp(home: HorsLignePage(horsLigne: hl)));
      await tester.pumpAndSettle();
      expect(find.text('En ligne : le serveur répond.'), findsOneWidget);
      expect(find.text('0 produits · 0 clients'), findsOneWidget);
      expect(find.text('jamais'), findsNWidgets(CatalogueCategorie.values.length));

      await tester.scrollUntilVisible(find.byKey(const Key('maj_copie')), 200);
      await tester.ensureVisible(find.byKey(const Key('maj_copie')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('maj_copie')));
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(find.text('Produits'), find.byType(ListView), const Offset(0, 300));
      expect(find.text('42 produits · 3 clients'), findsOneWidget);
      expect(find.text('10/10 08:30'), findsNWidgets(CatalogueCategorie.values.length));
      expect(find.text('Copie locale mise à jour.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5)); // fin du message
      await tester.pumpAndSettle();

      // Interrupteur manuel.
      await tester.dragUntilVisible(find.byType(Switch), find.byType(ListView), const Offset(0, 300));
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(hl.monitor.raison, RaisonHorsLigne.manuel);
      expect(find.textContaining('Hors ligne (choisi) depuis 10/10 08:30'), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const Key('maj_copie')), 200);
      await tester.ensureVisible(find.byKey(const Key('maj_copie')));
      await tester.pumpAndSettle();
      expect(tester.widget<ElevatedButton>(find.byKey(const Key('maj_copie'))).onPressed, isNull);
      await tester.dragUntilVisible(find.byType(Switch), find.byType(ListView), const Offset(0, 300));
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(hl.offline, isFalse);

      // Vider : confirmation d'abord.
      await tester.scrollUntilVisible(find.byKey(const Key('vider_copie')), 200);
      await tester.ensureVisible(find.byKey(const Key('vider_copie')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('vider_copie')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(hl.sync.stats.count(CatalogueCategorie.produits), 42);
      await tester.tap(find.byKey(const Key('vider_copie')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Vider'));
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(find.byKey(const Key('resume_copie')), find.byType(ListView), const Offset(0, 300));
      expect(find.text('0 produits · 0 clients'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
