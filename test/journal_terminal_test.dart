// Journal du terminal, période par défaut, anti double-clic et barres de chargement :
// - copie des BL entrés : 3 DERNIERS JOURS ; écrans hors ligne : le JOUR par défaut ;
// - journal append-only des actions stock / caisse, en ligne (faux Dio) et hors ligne (files, panier) ;
// - totaux (encaissé par mode, quantités par produit) et export PDF non vide ;
// - anti double envoi : requête « unique » identique bloquée, une seule confirmation, un seul envoi ;
// - progression affichée (« page 3/20 », « Envoi 1/2 ») ; purge au-delà de 90 jours.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/horsligne/activite_app.dart';
import 'package:prestige_vente_app/horsligne/attente_ui.dart';
import 'package:prestige_vente_app/horsligne/catalogue_sync.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/horsligne_ui.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_interceptor.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_rapport.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_screen.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart';
import 'package:prestige_vente_app/horsligne/panier_hors_ligne.dart';
import 'package:prestige_vente_app/horsligne/server_monitor.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_horsligne.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_models.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_refs_sync.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_sender.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_store.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_ui.dart';
import 'package:prestige_vente_app/horsligne/vente_hors_ligne.dart';
import 'package:prestige_vente_app/horsligne/ventes_hors_ligne_screen.dart';
import 'package:prestige_vente_app/horsligne/ventes_sync.dart';
import 'package:prestige_vente_app/parametres/hors_ligne_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _t0 = DateTime(2026, 10, 10, 8, 30);

// -----------------------------------------------------------------------------
// Outils
// -----------------------------------------------------------------------------

/// Faux serveur HTTP pour Dio (réponses JSON par chemin).
class _Adapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions o) handler;
  final appels = <String>[];
  _Adapter(this.handler);

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    appels.add('${o.method} ${o.path}');
    return handler(o);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, [int code = 200]) =>
    ResponseBody.fromString(jsonEncode(body), code, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});

(Dio, _Adapter) _dio(JournalTerminal j, Future<ResponseBody> Function(RequestOptions o) handler) {
  final a = _Adapter(handler);
  final d = Dio(BaseOptions(baseUrl: 'http://srv:8080/laborex/api/v1'))
    ..httpClientAdapter = a
    ..interceptors.add(ActiviteInterceptor())
    ..interceptors.add(JournalInterceptor(journal: () => j));
  return (d, a);
}

VenteHorsLigne _vente(int n, DateTime at, {StatutVenteHL statut = StatutVenteHL.enAttente, FinVenteHL fin = FinVenteHL.especes, int net = 1500}) =>
    VenteHorsLigne(
      id: 'v$n',
      numero: n,
      type: TypeVenteHL.comptant,
      lignes: [LigneHL(cle: 'l$n', produitId: 'P$n', nom: 'PRODUIT $n', qte: 2, prix: net ~/ 2)],
      fin: fin,
      totalEstime: net,
      netEstime: net,
      statut: statut,
      createdAt: at,
      updatedAt: at,
      envoyeeAt: statut == StatutVenteHL.envoyee ? at : null,
      userName: 'Awa',
    );

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(720, 1400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

/// Journal d'essai installé comme instance de l'appli.
JournalTerminal _journal(DateTime Function() clock) {
  final prev = JournalTerminal.instance;
  final j = JournalTerminal(clock: clock)
    ..terminalId = 'T-TEST01'
    ..terminalNom = 'SUNMI V2'
    ..utilisateur = 'Awa';
  JournalTerminal.instance = j;
  addTearDown(() => JournalTerminal.instance = prev);
  return j;
}

/// Hors ligne d'essai (mémoire) installé comme instance de l'appli.
HorsLigne _hl({FileVentesHL? ventes, CatalogueSync? sync}) {
  final store = sync?.store ?? MemoryLocalStore();
  final hl = HorsLigne(monitor: ServerMonitor(), store: store, sync: sync ?? CatalogueSync(store: store), ventes: ventes ?? FileVentesHL(store: MemoryVentesHLStore()));
  final prev = HorsLigne.instance;
  HorsLigne.instance = hl;
  addTearDown(() => HorsLigne.instance = prev);
  return hl;
}

StockHorsLigne _stock({StockServer? server, DateTime Function()? clock}) {
  final s = StockHorsLigne(store: MemoryStockStore(), server: server, clock: clock);
  StockHorsLigne.instance = s;
  addTearDown(StockHorsLigne.reset);
  return s;
}

/// Faux serveur stock : emplacements (POST update-lite-info), réponse retenue par [gate].
class _StockSrv implements StockServer {
  final appels = <String>[];
  Completer<void>? gate;
  @override
  Future<StockHttp> call(String method, String path, {Map<String, dynamic>? query, Object? data}) async {
    appels.add('$method $path');
    if (gate != null) await gate!.future;
    final corps = <String, dynamic>{'success': true, 'data': <dynamic>[]}; // modifiable (comme une vraie réponse)
    return StockHttp(200, corps);
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    sqfliteFfiInit();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    JournalInterceptor.reset();
    ActiviteApp.reset();
    JournalTerminal.conservationJours = 90;
  });

  // ---------------------------------------------------------------------------
  group('période par défaut', () {
    test('copie des BL entrés : les 3 derniers jours (plus 30), tranche jour / veille', () async {
      expect(StockRefSync.jours, 3);
      final appels = <Map<String, dynamic>>[];
      Future<Map<String, dynamic>> fetch(String path, Map<String, dynamic> q) async {
        appels.add({'path': path, ...q});
        if (path == '/commande/list-bons' && q['statut'] == 'is_Closed') {
          final today = q['dtStart'] == '2026-10-10';
          return {
            'data': [
              {'lg_BON_LIVRAISON_ID': 'blJ', 'str_REF_LIVRAISON': 'BL-J'},
              if (!today) {'lg_BON_LIVRAISON_ID': 'blV', 'str_REF_LIVRAISON': 'BL-V'},
            ]
          };
        }
        return {'data': []};
      }

      final sync = StockRefSync(store: MemoryStockStore(), clock: () => _t0);
      final rows = await sync.download(fetch);
      final clos = appels.where((a) => a['path'] == '/commande/list-bons' && a['statut'] == 'is_Closed').toList();
      expect(clos.map((a) => a['dtStart']).toSet(), {'2026-10-08', '2026-10-10'}, reason: '3 jours (aujourd\'hui compris), plus de lecture 7 / 30 j');
      final controle = appels.firstWhere((a) => a['path'] == '/etat-control-bon/list');
      expect(controle['dtStart'], '2026-10-08');
      final bls = {for (final r in rows[StockRef.blsClotures]!) r['lg_BON_LIVRAISON_ID']: r['_hl_jours']};
      expect(bls, {'blJ': 0, 'blV': 2});
      expect(StockRef.blsClotures.label, contains('3 j'));
    });

    test('écran hors ligne : le jour par défaut, la période choisie montre les 3 jours copiés', () async {
      final s = _stock(clock: () => _t0);
      await s.store.replaceRefs({
        StockRef.blsClotures: [
          {'lg_BON_LIVRAISON_ID': 'blJ', 'str_REF_LIVRAISON': 'BL-J', '_hl_jours': 0},
          {'lg_BON_LIVRAISON_ID': 'blV', 'str_REF_LIVRAISON': 'BL-V', '_hl_jours': 2},
        ],
      }, _t0);
      await s.refs.refreshStats();
      final jour = await s.blsClotures(dtStart: '2026-10-10', dtEnd: '2026-10-10');
      expect(jour.map((b) => b.ref), ['BL-J']);
      final semaine = await s.blsClotures(dtStart: '2026-10-04', dtEnd: '2026-10-10');
      expect(semaine.map((b) => b.ref), ['BL-J', 'BL-V']);
    });

    testWidgets('Ventes hors ligne : ventes du jour par défaut (+ celles à envoyer), « Tout » montre l\'historique', (tester) async {
      _phone(tester);
      _journal(() => _t0);
      final file = FileVentesHL(store: MemoryVentesHLStore(), clock: () => _t0);
      final hl = _hl(ventes: file);
      await file.ajouter(_vente(1, _t0.subtract(const Duration(days: 5)), statut: StatutVenteHL.envoyee));
      await file.ajouter(_vente(2, _t0.subtract(const Duration(days: 2))));
      await file.ajouter(_vente(3, _t0.subtract(const Duration(hours: 1)), statut: StatutVenteHL.envoyee));
      await tester.pumpWidget(MaterialApp(home: VentesHorsLigneScreen(horsLigne: hl)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vente_hl_HL-0003')), findsOneWidget);
      expect(find.byKey(const Key('vente_hl_HL-0002')), findsOneWidget, reason: 'en attente : toujours affichée');
      expect(find.byKey(const Key('vente_hl_HL-0001')), findsNothing);
      expect(find.byKey(const Key('ventes_hl_masquees')), findsOneWidget);
      await tester.tap(find.byKey(const Key('periode_ventes_hl')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('periode_ventes_hl_tout')).last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vente_hl_HL-0001')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Journal du terminal : actions du jour par défaut, filtre période / type / recherche', (tester) async {
      _phone(tester);
      var now = _t0.subtract(const Duration(days: 1));
      final j = _journal(() => now);
      _hl();
      await j.noter(type: TypeJournal.encaissement, action: 'Hier', refServeur: 'PV-HIER', montant: 1000, modes: {'1': 1000});
      now = _t0;
      await j.noter(type: TypeJournal.encaissement, action: 'Aujourd\'hui', refServeur: 'PV-JOUR', montant: 2500, modes: {'1': 2500});
      await j.noter(type: TypeJournal.stock, action: 'Pointage BL', refServeur: 'BL-77', produits: const [JournalProduit(id: 'p1', nom: 'DOLIPRANE', qte: 4)]);
      await tester.pumpWidget(MaterialApp(home: JournalTerminalScreen(journal: j)));
      await tester.pumpAndSettle();
      expect(find.text('Hier'), findsNothing);
      expect(find.text('Aujourd\'hui'), findsWidgets);
      expect(find.text('2 action(s) · 0 refus · 0 échec(s) réseau'), findsOneWidget);
      await tester.tap(find.byKey(const Key('periode_journal_troisJours')));
      await tester.pumpAndSettle();
      expect(find.text('3 action(s) · 0 refus · 0 échec(s) réseau'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Hier'), 200,
          scrollable: find.descendant(of: find.byKey(const Key('liste_journal')), matching: find.byType(Scrollable)).first);
      expect(find.text('Hier'), findsOneWidget);
      await tester.drag(find.byKey(const Key('liste_journal')), const Offset(0, 3000));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('recherche_journal')), 'bl-77');
      await tester.pumpAndSettle();
      expect(find.text('1 action(s) · 0 refus · 0 échec(s) réseau'), findsOneWidget);
      expect(find.text('Pointage BL'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  group('journalisation en ligne (faux Dio)', () {
    test('vente, encaissement multi-modes, refus, échec réseau, connexion sans mot de passe', () async {
      final j = JournalTerminal(clock: () => _t0)..utilisateur = 'Awa';
      var refuse = false;
      final (dio, _) = _dio(j, (o) async {
        switch (o.path) {
          case '/vente/add/vno':
            return _json({'success': true, 'data': {'lgPREENREGISTREMENTID': 'V77'}});
          case '/vente/add/item':
            return _json({'success': true, 'data': {}});
          case '/vente/cloturer/vno':
            return refuse ? _json({'success': false, 'msg': 'Caisse fermée'}) : _json({'success': true, 'data': {}});
          case '/user/auth':
            return _json({'success': true, 'str_LOGIN': 'awa'});
          case '/commande/validerbl/BL9':
            throw DioException(requestOptions: o, type: DioExceptionType.connectionError);
        }
        return _json({'success': true});
      });
      await dio.post('/vente/add/vno', data: {'produitId': 'P1', 'qte': 2, 'itemPu': 1000, 'venteId': null});
      await dio.post('/vente/add/item', data: {'produitId': 'P2', 'qte': 1, 'itemPu': 500, 'venteId': 'V77'});
      await dio.post('/vente/cloturer/vno', data: {
        'venteId': 'V77',
        'montantPaye': 2500,
        'reglements': [
          {'montant': 1500, 'typeReglement': '1'},
          {'montant': 1000, 'typeReglement': '4'},
        ],
      });
      refuse = true;
      await dio.post('/vente/cloturer/vno', data: {'venteId': 'V78', 'montantPaye': 900, 'reglements': [{'montant': 900, 'typeReglement': '1'}]});
      await expectLater(dio.put('/commande/validerbl/BL9'), throwsA(isA<DioException>()));
      await dio.post('/user/auth', data: {'login': 'awa', 'password': 'secret123'});
      await dio.get('/vente/search', queryParameters: {'query': 'DOLI'}); // lecture : jamais journalisée

      final e = await j.lire();
      expect(e.map((x) => x.action), [
        'Création de vente + 1ʳᵉ ligne',
        'Ajout de ligne',
        'Clôture / encaissement comptant',
        'Clôture / encaissement comptant',
        'Réception : entrée en stock du BL',
        'Connexion',
      ]);
      expect(e[0].refServeur, 'V77');
      expect(e[0].produits.single.qte, 2);
      expect(e[0].montant, 2000);
      expect(e[2].modes, {'1': 1500, '4': 1000});
      expect(e[2].montant, 2500);
      expect(e[2].resultat, ResultatJournal.ok);
      expect(e[3].resultat, ResultatJournal.refus);
      expect(e[3].motif, 'Caisse fermée');
      expect(e[3].modes, isEmpty, reason: 'refusé : rien d\'encaissé');
      expect(e[4].resultat, ResultatJournal.echecReseau);
      expect(e[4].type, TypeJournal.stock);
      expect(e[4].refServeur, 'BL9');
      expect(e[5].utilisateur, 'awa');
      expect(e.every((x) => x.terminal.isEmpty || !x.terminal.contains('secret')), isTrue);
      expect(jsonEncode([for (final x in e) x.toJson()]), isNot(contains('secret123')), reason: 'aucun mot de passe dans le journal');
      expect(e.every((x) => x.source == SourceJournal.enLigne), isTrue);
      expect(ActiviteApp.enCours, 0);
    });

    test('anti double encaissement : clôture identique en cours bloquée, une seule part au serveur', () async {
      final j = JournalTerminal(clock: () => _t0);
      final gate = Completer<void>();
      final (dio, a) = _dio(j, (o) async {
        await gate.future;
        return _json({'success': true});
      });
      final body = {'venteId': 'V1', 'montantPaye': 1000, 'reglements': [{'montant': 1000, 'typeReglement': '1'}]};
      final premier = dio.post('/vente/cloturer/vno', data: body);
      await pumpEventQueue();
      Object? erreur;
      try {
        await dio.post('/vente/cloturer/vno', data: body);
      } catch (e) {
        erreur = e;
      }
      expect(erreur, isA<DioException>());
      expect((erreur as DioException).type, DioExceptionType.cancel);
      expect(erreur.message, JournalInterceptor.messageDoublon);
      gate.complete();
      await premier;
      expect(a.appels.where((c) => c.contains('cloturer')).length, 1);
      // Après la réponse, une nouvelle clôture (autre vente ou relance volontaire) repart normalement.
      await dio.post('/vente/cloturer/vno', data: {...body, 'venteId': 'V2'});
      final e = await j.lire();
      expect(e.map((x) => x.resultat), [ResultatJournal.doublonBloque, ResultatJournal.ok, ResultatJournal.ok]);
      expect(calculerTotaux(e).encaisse, 2000, reason: 'le doublon bloqué n\'est pas compté');
      expect(ActiviteApp.enCours, 0, reason: 'le compteur d\'activité n\'est pas bloqué par le refus');
    });

    test('envoi de la file hors ligne : requêtes marquées « envoi file HL » (jamais recomptées)', () async {
      final j = JournalTerminal(clock: () => _t0);
      final a = _Adapter((o) async => _json({'success': true}));
      final dio = Dio(BaseOptions(baseUrl: 'http://srv'))
        ..httpClientAdapter = a
        ..interceptors.add(JournalInterceptor(journal: () => j, fileEnCours: () => true));
      await dio.post('/vente/cloturer/vno',
          data: {'venteId': 'V1', 'montantPaye': 1500, 'reglements': [{'montant': 1500, 'typeReglement': '1'}]},
          options: Options(headers: {'X-Client-Ref': 'HL-0001'}));
      final e = (await j.lire()).single;
      expect(e.source, SourceJournal.fileHL);
      expect(e.refLocale, 'HL-0001');
      expect(calculerTotaux([e]).encaisse, 0);
    });

    test('HorsLigne.bind : intercepteur posé une seule fois', () {
      final hl = _hl();
      final api = ApiService(baseUrl: 'http://localhost');
      hl.bind(api);
      hl.bind(api);
      expect(api.dio.interceptors.whereType<JournalInterceptor>().length, 1);
    });
  });

  // ---------------------------------------------------------------------------
  group('journalisation hors ligne', () {
    test('ventes hors ligne : création (espèces + produits), ressaisie, suppression ; panier ; passage hors ligne', () async {
      final j = _journal(() => _t0);
      final file = FileVentesHL(store: MemoryVentesHLStore(), clock: () => _t0);
      final hl = _hl(ventes: file);
      await file.ajouter(_vente(1, _t0));
      await file.ajouter(_vente(2, _t0, fin: FinVenteHL.prevente, net: 800));
      await file.ajouter(_vente(3, _t0));
      await file.exclure(['v2']);
      expect(await file.supprimer('v3'), isTrue);
      final panier = PanierHorsLigne(numero: 9);
      panier.ajouter(ProductSearchResult.fromJson({'lgFAMILLEID': 'P5', 'strNAME': 'EFFERALGAN', 'intCIP': '123', 'intPRICE': 700, 'intNUMBERAVAILABLE': 3}), 2);
      hl.monitor.goOffline(manuel: true);
      await j.idle;
      final e = await j.lire();
      expect(e.map((x) => x.action), [
        'Vente hors ligne enregistrée (encaissée en espèces)',
        'Vente hors ligne enregistrée (prévente)',
        'Vente hors ligne enregistrée (encaissée en espèces)',
        'Non envoyée : ressaisie sur le serveur (décochée à la confirmation)',
        'Vente hors ligne supprimée (jamais envoyée)',
        'Ajout de ligne (hors ligne)',
        'Passage hors ligne (choisi)',
      ]);
      expect(e.first.refLocale, 'HL-0001');
      expect(e.first.modes, {'ESPECES (hors ligne)': 1500});
      expect(e.first.produits.single.qte, 2);
      expect(e[1].modes, isEmpty, reason: 'prévente : rien d\'encaissé');
      expect(e.take(5).every((x) => x.source == SourceJournal.horsLigne && x.utilisateur == 'Awa'), isTrue);
      expect(e[5].refLocale, 'HL-0009');
      expect(e.last.type, TypeJournal.reseau);
      final t = calculerTotaux(e);
      expect(t.parMode, {'ESPECES (hors ligne)': 3000});
    });

    test('opérations de stock : saisies, envoi (ok), ressaisie', () async {
      final j = _journal(() => _t0);
      final srv = _StockSrv();
      final s = _stock(server: srv, clock: () => _t0);
      final q = s.queue;
      await q.setEmplacement(produitId: 'p1', produit: 'DOLIPRANE', rayonId: 'r1', rayon: 'RAYON A');
      await q.addPerime(produitId: 'p2', produit: 'AUGMENTIN', lot: 'L1', date: '2026-12-01', qty: 3);
      final perimes = q.pending.firstWhere((o) => o.type == StockOpType.perime);
      final empl = q.pending.firstWhere((o) => o.type == StockOpType.emplacement);
      await q.envoyer(selection: {empl.id}, ressaisies: {perimes.id});
      await j.idle;
      final e = await j.lire();
      expect(e.map((x) => x.action), [
        'Emplacements : emplacement saisi hors ligne (DOLIPRANE → RAYON A)',
        'Saisie de périmés : périmé saisi hors ligne',
        'Saisie de périmés : non envoyée : ressaisie sur le serveur (décochée)',
        'Emplacements : envoyée au serveur (1 ligne(s))',
      ]);
      expect(e[1].produits.single.qte, 3);
      expect(e.last.source, SourceJournal.fileHL);
      expect(e.every((x) => x.type == TypeJournal.stock), isTrue);
    });

    test('SQLite : table dédiée (migration nommée), append-only, lecture filtrée, purge', () async {
      final local = SqfliteLocalStore(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      addTearDown(local.close);
      var now = _t0.subtract(const Duration(days: 120));
      final j = JournalTerminal(store: SqfliteJournalStore(local), clock: () => now)..utilisateur = 'Awa';
      await j.noter(type: TypeJournal.vente, action: 'Ancienne', refLocale: 'HL-0001');
      now = _t0;
      await j.noter(type: TypeJournal.encaissement, action: 'Récente', refServeur: 'PV-1', montant: 1200, modes: {'1': 1200});
      await j.noter(type: TypeJournal.stock, action: 'Stock', produits: const [JournalProduit(id: 'p1', qte: 5)]);
      expect((await j.lire()).length, 3);
      expect((await j.lire(JournalFiltre(du: _t0, au: _t0))).map((e) => e.action), ['Récente', 'Stock']);
      expect((await j.lire(const JournalFiltre(types: {TypeJournal.stock}))).single.produits.single.qte, 5);
      expect((await j.lire(const JournalFiltre(recherche: 'pv-1'))).single.montant, 1200);
      expect(await j.purger(), 1);
      expect(await j.store.compte(), 2);
      // Vider la copie locale ne touche pas au journal.
      await local.clear();
      expect(await j.store.compte(), 2);
    });
  });

  // ---------------------------------------------------------------------------
  group('totaux et export PDF', () {
    List<JournalEntree> entrees() => [
          JournalEntree(at: _t0, type: TypeJournal.encaissement, action: 'Clôture', refServeur: 'V1', montant: 5000, modes: const {'1': 5000}),
          JournalEntree(at: _t0, type: TypeJournal.encaissement, action: 'Clôture', refServeur: 'V2', montant: 5000, modes: const {'1': 2000, '2': 3000}),
          JournalEntree(
              at: _t0, type: TypeJournal.encaissement, action: 'Clôture', refServeur: 'V3', montant: 900, modes: const {'1': 900}, resultat: ResultatJournal.refus, motif: 'Caisse fermée'),
          JournalEntree(at: _t0, type: TypeJournal.encaissement, action: 'Clôture', refServeur: 'V4', montant: 700, modes: const {'1': 700}, source: SourceJournal.fileHL),
          JournalEntree(
              at: _t0,
              type: TypeJournal.venteHL,
              action: 'Vente hors ligne enregistrée',
              refLocale: 'HL-0001',
              montant: 1500,
              modes: const {'ESPECES (hors ligne)': 1500},
              produits: const [JournalProduit(id: 'P2', nom: 'EFFERALGAN', qte: 1)],
              source: SourceJournal.horsLigne),
          JournalEntree(at: _t0, type: TypeJournal.vente, action: 'Ajout', refServeur: 'V1', produits: const [JournalProduit(id: 'P1', nom: 'DOLIPRANE', qte: 2)]),
          JournalEntree(at: _t0, type: TypeJournal.vente, action: 'Modification', refServeur: 'V1', produits: const [JournalProduit(id: 'P1', nom: 'DOLIPRANE', qte: 3, remplace: true)]),
          JournalEntree(at: _t0, type: TypeJournal.vente, action: 'Ajout', refServeur: 'V2', produits: const [JournalProduit(id: 'P1', nom: 'DOLIPRANE', qte: 1)]),
          JournalEntree(at: _t0, type: TypeJournal.stock, action: 'Lot', refServeur: 'BL1', produits: const [JournalProduit(id: 'P1', nom: 'DOLIPRANE', qte: 10)]),
          JournalEntree(at: _t0, type: TypeJournal.stock, action: 'Pointage', refServeur: 'd1', produits: const [JournalProduit(id: 'P2', nom: 'EFFERALGAN', qte: 4, remplace: true)]),
          JournalEntree(at: _t0, type: TypeJournal.stock, action: 'Pointage', refServeur: 'd1', produits: const [JournalProduit(id: 'P2', nom: 'EFFERALGAN', qte: 6, remplace: true)]),
          JournalEntree(at: _t0, type: TypeJournal.connexion, action: 'Connexion', resultat: ResultatJournal.echecReseau),
        ];

    test('totaux encaissés par mode et quantités par produit', () {
      final t = calculerTotaux(entrees(), nomsModes: const {'1': 'ESPECES', '2': 'WAVE'});
      expect(t.parMode, {'ESPECES': 7000, 'WAVE': 3000, 'ESPECES (hors ligne)': 1500});
      expect(t.encaisse, 11500);
      final p1 = t.produits.firstWhere((p) => p.id == 'P1');
      expect((p1.vendu, p1.stock), (4, 10), reason: 'V1 : 2 puis modifié à 3 ; V2 : 1');
      final p2 = t.produits.firstWhere((p) => p.id == 'P2');
      expect((p2.vendu, p2.stock), (1, 6), reason: 'pointage : la dernière quantité remplace');
      expect((t.entrees, t.refus, t.echecs), (12, 1, 1));
      final ticket = lignesTicketJournal(t, terminal: 'T-TEST01', du: _t0, au: _t0);
      expect(ticket, contains('TOTAL : ${lignesTicketJournal(t, terminal: '').firstWhere((l) => l.startsWith('TOTAL')).substring(8)}'));
      expect(ticket.any((l) => l.startsWith('WAVE')), isTrue);
    });

    test('PDF non vide (en-tête, tableau, totaux), caractères compatibles', () async {
      final e = entrees();
      final bytes = await construirePdfJournal(
          entrees: e, totaux: calculerTotaux(e), officine: 'PHCIE NACHET', terminal: 'T-TEST01 · SUNMI V2', utilisateur: 'Awa', du: _t0, au: _t0, genereLe: _t0);
      expect(bytes.length, greaterThan(2000));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(pdfSafe('HL-0001 → V1 ${'1 500'} F…'), 'HL-0001 -> V1 1 500 F...');
    });

    testWidgets('écran : export PDF (bouton occupé pendant la génération), totaux affichés', (tester) async {
      _phone(tester);
      final j = _journal(() => _t0);
      _hl();
      await j.noter(type: TypeJournal.encaissement, action: 'Clôture', refServeur: 'V1', montant: 2500, modes: {'1': 2500});
      List<int>? pdf;
      final gate = Completer<void>();
      var appels = 0;
      await tester.pumpWidget(MaterialApp(
          home: JournalTerminalScreen(
              journal: j,
              partager: (b, f) async {
                appels++;
                pdf = b;
                await gate.future;
              })));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('total_encaisse_journal')), findsOneWidget);
      await tester.tap(find.byKey(const Key('journal_pdf')));
      for (var i = 0; i < 50 && pdf == null; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(pdf, isNotNull);
      expect(pdf!.length, greaterThan(1000));
      await tester.pump();
      // Pendant le partage : bouton désactivé + indicateur animé ; un second appui est ignoré.
      expect(find.descendant(of: find.byKey(const Key('journal_pdf')), matching: find.byType(CircularProgressIndicator)), findsOneWidget);
      await tester.tap(find.byKey(const Key('journal_pdf')));
      await tester.pump();
      expect(appels, 1);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byKey(const Key('journal_pdf')), matching: find.byType(CircularProgressIndicator)), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  group('anti double-clic', () {
    test('Verrou : une action à la fois', () async {
      final v = Verrou();
      final gate = Completer<int>();
      var n = 0;
      final a = v.executer(() {
        n++;
        return gate.future;
      });
      expect(await v.executer(() async => ++n), isNull);
      gate.complete(1);
      expect(await a, 1);
      expect(n, 1);
      expect(await v.executer(() async => ++n), 2);
    });

    test('stock : deux envois simultanés → un seul part', () async {
      _journal(() => _t0);
      final srv = _StockSrv()..gate = Completer<void>();
      final s = _stock(server: srv, clock: () => _t0);
      await s.queue.setEmplacement(produitId: 'p1', produit: 'DOLIPRANE', rayonId: 'r1', rayon: 'A');
      final id = s.queue.pending.single.id;
      final f1 = s.queue.envoyer(selection: {id});
      final r2 = await s.queue.envoyer(selection: {id});
      expect(r2.interruption, 'Envoi déjà en cours.');
      srv.gate!.complete();
      final r1 = await f1;
      expect(r1.envoyees, 1);
      expect(srv.appels.where((c) => c.contains('update-lite-info')).length, 1);
    });

    test('synchro de la copie : jamais deux à la fois (un 2ᵉ appui attend la même)', () async {
      final gate = Completer<void>();
      var appels = 0;
      final sync = CatalogueSync(
          store: MemoryLocalStore(),
          occupee: () => false,
          fetch: (p, q) async {
            appels++;
            await gate.future;
            return {'data': []};
          });
      final a = sync.syncAll();
      final b = sync.syncAll();
      expect(await sync.syncAll(auto: true), isFalse);
      gate.complete();
      expect(await a, await b);
      expect(appels, CatalogueCategorie.values.length + 1, reason: 'une seule série d\'appels (modes : 2 appels)');
    });

    testWidgets('confirmation d\'envoi : jamais ouverte deux fois ; double appui « Envoyer » sans effet de bord', (tester) async {
      _phone(tester);
      _journal(() => _t0);
      final file = FileVentesHL(store: MemoryVentesHLStore(), clock: () => _t0);
      final hl = _hl(ventes: file);
      await file.ajouter(_vente(1, _t0));
      await tester.pumpWidget(MaterialApp(home: VentesHorsLigneScreen(horsLigne: hl)));
      await tester.pumpAndSettle();
      final ctx = tester.element(find.byKey(const Key('liste_ventes_hl')));
      unawaited(confirmerEnvoiVentes(ctx, horsLigne: hl));
      unawaited(confirmerEnvoiVentes(ctx, horsLigne: hl));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('confirmation_envoi')), findsOneWidget);
      expect(confirmationEnvoiOuverte, isTrue);
      // « Plus tard » appuyé deux fois : la confirmation se ferme, l'écran reste.
      await tester.tap(find.byKey(const Key('envoi_plus_tard')));
      await tester.tap(find.byKey(const Key('envoi_plus_tard')), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('confirmation_envoi')), findsNothing);
      expect(find.byKey(const Key('liste_ventes_hl')), findsOneWidget, reason: 'l\'écran de dessous n\'est pas fermé');
      expect(confirmationEnvoiOuverte, isFalse);
      expect(file.ventes.single.statut, StatutVenteHL.enAttente);
      final conf = (await JournalTerminal.instance.lire(const JournalFiltre(types: {TypeJournal.confirmation}))).single;
      expect(conf.action, contains('reporté'));
      expect(conf.refLocale, 'HL-0001');
      expect(tester.takeException(), isNull);
    });

    testWidgets('écran d\'envoi stock : bouton désactivé pendant l\'envoi (« Envoi 1/1 » + barre)', (tester) async {
      _phone(tester);
      _journal(() => _t0);
      final srv = _StockSrv()..gate = Completer<void>();
      final s = _stock(server: srv, clock: () => _t0);
      _hl();
      await s.queue.setEmplacement(produitId: 'p1', produit: 'DOLIPRANE', rayonId: 'r1', rayon: 'A');
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) => Center(child: ElevatedButton(onPressed: () => ouvrirEnvoiStock(c, stock: s), child: const Text('ouvrir')))))));
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmer_envoi')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('progression_envoi_stock')), findsOneWidget);
      expect(find.textContaining('Envoi 1/1'), findsWidgets);
      expect(find.byKey(const Key('barre_envoi_stock')), findsOneWidget);
      expect(tester.widget<ElevatedButton>(find.byKey(const Key('confirmer_envoi'))).onPressed, isNull);
      expect(tester.widget<TextButton>(find.byKey(const Key('plus_tard'))).onPressed, isNull);
      srv.gate!.complete();
      await tester.pumpAndSettle();
      expect(srv.appels.where((c) => c.contains('update-lite-info')).length, 1);
      expect(find.byKey(const Key('barre_envoi_stock')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  group('progression affichée', () {
    testWidgets('mise à jour de la copie : « page 3/20 » dans Réglages, barre discrète dans le bandeau', (tester) async {
      _phone(tester);
      _journal(() => _t0);
      final gate = Completer<void>();
      final sync = CatalogueSync(
          store: MemoryLocalStore(),
          pageSize: 100,
          occupee: () => false,
          fetch: (path, q) async {
            if (path != '/vente/search') return {'data': []};
            final page = q['page'] as int;
            if (page == 3) await gate.future;
            return {
              'total': 2000,
              'data': [for (var i = 0; i < 100; i++) {'lgFAMILLEID': 'P$page-$i', 'strNAME': 'PRODUIT $page $i', 'intPRICE': 100}],
            };
          });
      final hl = _hl(sync: sync);
      _stock(clock: () => _t0);
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => HorsLigneScope(horsLigne: hl, bindApp: false, child: child!),
        home: HorsLignePage(horsLigne: hl),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('bandeau_maj_copie')), findsNothing);
      final fin = sync.syncAll();
      for (var i = 0; i < 50 && sync.page != 3; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      // Page 3 en cours de téléchargement (bloquée) : les 2 premières sont reçues.
      expect(sync.pages, 20);
      expect(sync.progressionLabel, 'Produits : page 3/20 (200 / 2000)');
      expect(sync.etapeNum, 1);
      expect(find.byKey(const Key('bandeau_maj_copie')), findsOneWidget);
      final barre = tester.widget<LinearProgressIndicator>(find.byKey(const Key('bandeau_maj_copie')));
      expect(barre.value, isNotNull, reason: 'barre déterminée : pas d\'animation infinie');
      await tester.scrollUntilVisible(find.byKey(const Key('progression_maj')), 200);
      expect(find.text('Produits : page 3/20 (200 / 2000)'), findsOneWidget);
      expect(find.byKey(const Key('barre_maj_globale')), findsOneWidget);
      expect(find.text('Mise à jour 1/${CatalogueCategorie.values.length + 1}'), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const Key('maj_copie')), 200);
      expect(find.text('Mise à jour en cours…'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(find.byKey(const Key('maj_copie'))).onPressed, isNull, reason: 'action bloquée pendant la mise à jour');
      gate.complete();
      await tester.pumpAndSettle();
      expect(await fin, isTrue);
      expect(find.byKey(const Key('bandeau_maj_copie')), findsNothing);
      expect(find.byKey(const Key('progression_maj')), findsNothing);
      expect(sync.stats.count(CatalogueCategorie.produits), 2000);
      expect(tester.takeException(), isNull);
    });

    test('envoi des ventes : « Envoi 2/5 » exposé par la file, avancement stock 0 → 1', () async {
      final srv = _StockSrv()..gate = Completer<void>();
      final s = _stock(server: srv, clock: () => _t0);
      _journal(() => _t0);
      await s.queue.setEmplacement(produitId: 'p1', produit: 'A', rayonId: 'r1', rayon: 'R1');
      await s.queue.addPerime(produitId: 'p2', produit: 'B', lot: 'L', date: '2026-12-01', qty: 1);
      final ids = {for (final o in s.queue.pending) o.id};
      final f = s.queue.envoyer(selection: ids);
      await pumpEventQueue();
      expect(s.queue.progress, startsWith('Envoi 1/2'));
      expect(s.queue.avancement, 0);
      srv.gate!.complete();
      await f;
      expect(s.queue.avancement, isNull);
      expect(s.queue.progress, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  group('conservation 90 jours', () {
    test('purge au-delà de 90 jours : journal, ventes et opérations TERMINÉES ; jamais ce qui est en attente', () async {
      var now = _t0.subtract(const Duration(days: 100));
      final j = _journal(() => now);
      final file = FileVentesHL(store: MemoryVentesHLStore(), clock: () => now);
      final hl = _hl(ventes: file);
      final s = _stock(server: _StockSrv(), clock: () => now);
      await j.noter(type: TypeJournal.vente, action: 'Très ancienne');
      await file.ajouter(_vente(1, now, statut: StatutVenteHL.envoyee));
      await file.ajouter(_vente(2, now)); // en attente : jamais purgée
      await s.queue.setEmplacement(produitId: 'p1', produit: 'A', rayonId: 'r1', rayon: 'R1');
      await s.queue.envoyer(selection: {s.queue.pending.single.id});
      await s.queue.addPerime(produitId: 'p2', produit: 'B', lot: 'L', date: '2026-12-01', qty: 1); // en attente
      now = _t0.subtract(const Duration(days: 80));
      await j.noter(type: TypeJournal.vente, action: 'Dans les 90 jours');
      await file.ajouter(_vente(3, now, statut: StatutVenteHL.envoyee));
      now = _t0;

      expect(JournalTerminal.conservationJours, 90);
      expect(j.limiteConservation, DateTime(2026, 7, 12));
      await hl.purgerHistorique();
      await s.queue.purger(j.limiteConservation);
      expect((await j.lire()).map((e) => e.action), ['Dans les 90 jours', ...(await j.lire()).skip(1).map((e) => e.action)]);
      expect((await j.lire()).any((e) => e.action == 'Très ancienne'), isFalse);
      expect(file.ventes.map((v) => v.numeroLabel), ['HL-0002', 'HL-0003']);
      expect(s.queue.ops.map((o) => o.type), [StockOpType.perime]);

      // Réglable (au moins 90 jours).
      await JournalTerminal.reglerConservation(30);
      expect(JournalTerminal.conservationJours, 90);
      await JournalTerminal.reglerConservation(180);
      expect(JournalTerminal.conservationJours, 180);
      JournalTerminal.conservationJours = 90;
      await JournalTerminal.chargerReglages();
      expect(JournalTerminal.conservationJours, 180, reason: 'réglage gardé sur l\'appareil');
      JournalTerminal.conservationJours = 90;
    });

    test('identité du terminal : créée une fois, gardée', () async {
      final j = JournalTerminal();
      await j.chargerIdentite(materiel: () async => {'manufacturer': 'SUNMI', 'model': 'V2s'});
      expect(j.terminalId, matches(RegExp(r'^T-[0-9A-Z]{6}$')));
      expect(j.terminalNom, 'SUNMI V2s');
      final k = JournalTerminal();
      await k.chargerIdentite();
      expect(k.terminalId, j.terminalId);
    });
  });
}
