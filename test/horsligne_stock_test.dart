// Hors ligne (étape H3) — stock : copie étendue (BL, commandes, motifs… téléchargée avec le catalogue,
// transactionnelle, affichée dans Réglages), file persistante (survit au redémarrage), envoi une
// opération à la fois et idempotent (coupure au milieu → « déjà appliqué », jamais de doublon),
// confirmation avec décochage (« ressaisie »), anomalies (BL déjà clôturé, déjà pointé) dans l'écran
// commun « Anomalies de synchronisation », actions désactivées hors ligne, aucune modification en ligne.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/bon_livraison.dart';
import 'package:prestige_vente_app/api/models/bon_livraison_item.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/horsligne/activite_app.dart';
import 'package:prestige_vente_app/horsligne/catalogue_sync.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/horsligne_ui.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart';
import 'package:prestige_vente_app/horsligne/rapports_hl_screen.dart';
import 'package:prestige_vente_app/horsligne/server_monitor.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_gateways.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_horsligne.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_models.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_sender.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_store.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_ui.dart';
import 'package:prestige_vente_app/horsligne/vente_hors_ligne.dart';
import 'package:prestige_vente_app/horsligne/ventes_sync.dart';
import 'package:prestige_vente_app/providers/bl_control_provider.dart';
import 'package:prestige_vente_app/providers/delivery_control_provider.dart';
import 'package:prestige_vente_app/providers/perime_provider.dart';
import 'package:prestige_vente_app/providers/product_update_provider.dart';
import 'package:prestige_vente_app/providers/reception_provider.dart';
import 'package:prestige_vente_app/reception/reception_gateway.dart';
import 'package:prestige_vente_app/reception/reception_models.dart';
import 'package:prestige_vente_app/retour/retour_gateway.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _t0 = DateTime(2026, 10, 10, 8, 30);

Map<String, dynamic> _blLine(String id, String bl, String ref, String produitId, String name, {int ordered = 5, bool closed = false}) => {
      'lg_BON_LIVRAISON_DETAIL': id,
      'lg_FAMILLE_ID': produitId,
      'lg_FAMILLE_NAME': name,
      'lg_FAMILLE_CIP': '30${id.hashCode.abs() % 100000}',
      'int_QTE_CMDE': ordered,
      'int_QTE_RECUE': ordered,
      'int_QTE_RECUE_BIS': ordered,
      'quantiteSaisie': 0,
      'freeQty': 0,
      'lots': '',
      'datePeremption': '',
      'str_REF_LIVRAISON': ref,
      'str_STATUT': closed ? 'is_Closed' : 'enable',
      'lg_FAMILLE_QTE_STOCK': 10,
      'lg_ZONE_GEO_NAME': 'RAYON A',
      'checked': false,
    };

/// Serveur Prestige simulé (mêmes routes et mêmes réponses que le vrai, vérifiées sur le serveur de test).
class FakePrestige implements StockServer {
  final calls = <String>[];
  final closed = <String>{};
  final Map<String, List<Map<String, dynamic>>> lines = {
    'bl1': [_blLine('d1', 'bl1', 'BL-001', 'p1', 'DOLIPRANE 1000MG'), _blLine('d1b', 'bl1', 'BL-001', 'p3', 'EFFERALGAN 500')],
    'bl2': [_blLine('d2', 'bl2', 'BL-002', 'p2', 'AUGMENTIN 1G', ordered: 4, closed: true)],
  };
  final orderItems = <Map<String, dynamic>>[
    {'lg_ORDERDETAIL_ID': 'od1', 'lg_ORDER_ID': 'o1', 'lg_FAMILLE_ID': 'p1', 'lg_FAMILLE_NAME': 'DOLIPRANE 1000MG', 'int_NUMBER': 3, 'checked': false},
  ];
  bool orderEnCours = true;
  final lots = <Map<String, dynamic>>[];
  final perimes = <Map<String, dynamic>>[];
  final retours = <Map<String, dynamic>>[];
  final retourItems = <Map<String, dynamic>>[];
  final liteInfo = <Map<String, dynamic>>[];

  /// Coupe la connexion APRÈS avoir appliqué le prochain appel à ce chemin (réponse perdue).
  String? coupeApres;

  /// Serveur éteint.
  bool down = false;

  int count(String what) => calls.where((c) => c.contains(what)).length;

  Map<String, dynamic> _list(List<Map<String, dynamic>> l) => {'total': l.length, 'data': l};

  /// Lecture de la copie (même interface que la synchro du catalogue).
  Future<Map<String, dynamic>> fetch(String path, Map<String, dynamic> query) async {
    final r = await call('GET', path, query: query);
    return r.map;
  }

  @override
  Future<StockHttp> call(String method, String path, {Map<String, dynamic>? query, Object? data, Map<String, String>? headers}) async {
    if (down) throw const StockStopException('Serveur injoignable : envoi interrompu.');
    calls.add('$method $path');
    final d = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    final r = _route(method, path, query ?? const {}, d);
    if (coupeApres != null && path == coupeApres) {
      coupeApres = null;
      throw const StockStopException('Serveur injoignable : envoi interrompu.');
    }
    return r;
  }

  StockHttp _route(String method, String path, Map<String, dynamic> q, Map<String, dynamic> d) {
    if (method == 'GET' && path == '/commande/list-bons') {
      final enable = q['statut'] == 'enable';
      return StockHttp(200, _list([
        for (final e in lines.entries)
          if ((e.value.first['str_STATUT'] == 'enable' && !closed.contains(e.key)) == enable)
            {
              'lg_BON_LIVRAISON_ID': e.key,
              'str_REF_LIVRAISON': e.value.first['str_REF_LIVRAISON'],
              'str_GROSSISTE_LIBELLE': 'DPCI',
              'lg_GROSSISTE_ID': 'g1',
              'dt_DATE_LIVRAISON': '10/10/2026',
              'int_NBRE_LIGNE_BL_DETAIL': e.value.length,
              'str_STATUT': enable ? 'enable' : 'is_Closed',
              'statutTraitement': 'A_FAIRE',
            },
      ]));
    }
    if (method == 'GET' && path.startsWith('/commande/bon/items/')) {
      final id = path.split('/').last;
      return StockHttp(200, _list([
        for (final l in lines[id] ?? const <Map<String, dynamic>>[]) {...l, if (closed.contains(id)) 'str_STATUT': 'is_Closed'},
      ]));
    }
    if (path == '/commande/add-lot') {
      final l = lines.values.expand((x) => x).firstWhere((l) => l['lg_BON_LIVRAISON_DETAIL'] == d['idBonDetail']);
      final qty = (d['qty'] as num).toInt() + (d['freeQty'] as num).toInt();
      if ((l['quantiteSaisie'] as int) + (d['qty'] as num).toInt() > (l['int_QTE_CMDE'] as int)) {
        return const StockHttp(200, {'msg': 'La quantité réçue est supérieure à la quantité commantée.', 'success': false});
      }
      l['quantiteSaisie'] = (l['quantiteSaisie'] as int) + qty;
      l['lots'] = [if ('${l['lots']}'.isNotEmpty) l['lots'], d['numLot']].join(' | ');
      return const StockHttp(200, {'success': true});
    }
    if (path == '/commande/bon/items/checked-quantities') {
      final l = lines.values.expand((x) => x).where((l) => l['lg_BON_LIVRAISON_DETAIL'] == d['id']).firstOrNull;
      l?['checked'] = true;
      l?['checkedQuantity'] = d['checkedQuantity'];
      return const StockHttp(202, '');
    }
    if (method == 'GET' && path == '/commande/list') {
      return StockHttp(200, _list([if (orderEnCours) {'lg_ORDER_ID': 'o1', 'str_REF_ORDER': 'CMD-1', 'str_GROSSISTE_LIBELLE': 'DPCI'}]));
    }
    if (method == 'GET' && path == '/commande/list/passees') return StockHttp(200, _list([]));
    if (path == '/commande/commande-en-cours-items') return StockHttp(200, _list(orderItems));
    if (path == '/commande/item/checked-quantities') {
      final l = orderItems.firstWhere((l) => l['lg_ORDERDETAIL_ID'] == d['id']);
      l['checked'] = true;
      l['checkedQuantity'] = d['checkedQuantity'];
      return const StockHttp(200, {'success': true});
    }
    if (path == '/common/grossiste') return StockHttp(200, _list([{'id': 'g1', 'libelle': 'DPCI'}]));
    if (path == '/common/motifs-retour') return StockHttp(200, _list([{'lgMOTIFRETOUR': '01', 'strLIBELLE': 'colis avarié'}]));
    if (path == '/common/rayons') return StockHttp(200, _list([{'id': 'r1', 'libelle': 'RAYON A'}, {'id': 'r2', 'libelle': 'RAYON B'}]));
    if (path == '/etat-control-bon/list') {
      return StockHttp(200, _list([
        {
          'lgBONLIVRAISONID': 'bl2',
          'strREFLIVRAISON': 'BL-002',
          'fournisseurLibelle': 'DPCI',
          'dtDATELIVRAISON': '10/10/2026 00:00',
          'dtCREATED': '10/10/2026 08:00',
          'dtUPDATED': '10/10/2026 08:10',
          'checked': 'NON_TRAITE',
          'bonLivraisonDetails': [
            {'lgBONLIVRAISONDETAIL': 'd2', 'produit': {'strNAME': 'AUGMENTIN 1G', 'intCIP': '3000002'}, 'intQTECMDE': 4, 'intQTERECUE': 4, 'quantiteControle': 0},
          ],
        },
      ]));
    }
    if (path == '/gestionperime/saisie-encours') return StockHttp(200, _list(perimes));
    if (path == '/gestionperime/add') {
      perimes.add({'id': 'pe${perimes.length}', 'produitId': d['ref'], 'lot': d['refTwo'], 'quantity': d['value'], 'datePeremption': d['refParent']});
      return const StockHttp(200, {'success': true});
    }
    if (path == '/fichearticle/add-lot') {
      if (d['produitId'] == 'inconnu') return const StockHttp(500, 'NullPointerException');
      lots.add({'NUMLOT': d['numLot'], 'DATEPEREMPTION': _fr(d['datePeremption']), 'NUMBER': d['quantity'], 'NUMBERGT': 0});
      return const StockHttp(202, '');
    }
    if (path == '/lot/listlot') return StockHttp(200, _list(lots));
    if (path == '/retourfournisseur/new') {
      final id = 'R${retours.length + 1}';
      retours.add({'lg_RETOUR_FRS_ID': id, 'str_REF_RETOUR_FRS': '900${retours.length + 1}', 'str_COMMENTAIRE': d['strCOMMENTAIRE']});
      final it = (d['items'] as List).first as Map;
      retourItems.add({'retourId': id, 'produitId': it['produitId'], 'intNUMBERRETURN': it['intNUMBERRETURN']});
      return StockHttp(200, {'success': true, 'data': {'lgRETOURFRSID': id, 'strREFRETOURFRS': '900${retours.length}'}});
    }
    if (path == '/produit/retours-data') return StockHttp(200, {'total': retours.length, 'results': retours});
    if (path == '/retourfournisseur/add-item') {
      retourItems.add({'retourId': d['lgRETOURFRSID'], 'produitId': d['produitId'], 'intNUMBERRETURN': d['intNUMBERRETURN']});
      return const StockHttp(200, {'success': true});
    }
    if (path == '/retourfournisseur/retours-items') {
      return StockHttp(200, _list([for (final i in retourItems) if (i['retourId'] == q['retourId']) i]));
    }
    if (path == '/fichearticle/produit/update-lite-info') {
      liteInfo.add(d);
      return const StockHttp(202, '');
    }
    // Routes du catalogue (H1) : listes vides.
    return StockHttp(200, _list([]));
  }

  static String _fr(dynamic iso) {
    final d = DateTime.parse('$iso');
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }
}

class _Env {
  final FakePrestige srv;
  final HorsLigne hl;
  final StockHorsLigne stock;
  _Env(this.srv, this.hl, this.stock);
}

/// Instance de test (mémoire, horloge fixe) : copie stock téléchargée, état [offline].
Future<_Env> _env({bool offline = true, bool copie = true, StockStore? store}) async {
  final srv = FakePrestige();
  final local = MemoryLocalStore();
  final hl = HorsLigne(
      monitor: ServerMonitor(clock: () => _t0),
      store: local,
      sync: CatalogueSync(store: local, clock: () => _t0),
      ventes: FileVentesHL(store: MemoryVentesHLStore()));
  final stock = StockHorsLigne(store: store ?? MemoryStockStore(), server: srv, clock: () => _t0);
  stock.attach(hl);
  if (copie) await stock.refs.sync(srv.fetch, (_, __, ___) {});
  final prevHl = HorsLigne.instance;
  HorsLigne.instance = hl;
  StockHorsLigne.instance = stock;
  addTearDown(() {
    HorsLigne.instance = prevHl;
    StockHorsLigne.reset();
  });
  if (offline) hl.monitor.goOffline();
  srv.calls.clear();
  return _Env(srv, hl, stock);
}

/// Passerelle de réception « en ligne » : enregistre les appels.
class _OnlineReception implements ReceptionGateway {
  final calls = <String>[];
  @override
  Future<List<ReceptionBl>> bls({String query = ''}) async {
    calls.add('bls');
    return const [ReceptionBl(id: 'srv', ref: 'SRV-1')];
  }

  @override
  Future<ReceptionResult> addLot({required String detailId, required int quantity, required int freeQty, required String numLot, DateTime? expiry}) async {
    calls.add('addLot $detailId');
    return const ReceptionResult(true, 'Lot enregistré');
  }

  @override
  Future<ReceptionResult> createBl({required String orderId, required String ref, required DateTime date, required int amountHt, required int tva}) async {
    calls.add('createBl');
    return const ReceptionResult(true, 'BL créé');
  }

  @override
  Future<bool> canValidate() async => true;

  @override
  Future<ReceptionResult> validate(String blId) async {
    calls.add('validate');
    return const ReceptionResult(true);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// ApiService « en ligne » des écrans de pointage : enregistre les appels.
class _Api extends ApiService {
  _Api() : super(baseUrl: 'http://127.0.0.1:9');
  final calls = <String>[];

  @override
  Future<List<BonLivraison>> getBonsLivraison({String query = '', String? dtStart, String? dtEnd}) async {
    calls.add('getBonsLivraison');
    return [BonLivraison(id: 'srv', ref: 'SRV', grossiste: '', date: '', nbreLignes: 0, montantTotal: 0, statutTraitement: 'A_FAIRE', strStatut: '')];
  }

  @override
  Future<List<BonLivraisonItem>> getBonLivraisonItems(String blId) async {
    calls.add('getBonLivraisonItems');
    return [];
  }

  @override
  Future<bool> postBonItemCheckedQuantity({required String detailId, required int quantity}) async {
    calls.add('post $detailId $quantity');
    return true;
  }

  @override
  Future<bool> postCheckedQuantity({required String detailId, required int quantity}) async {
    calls.add('postCmd $detailId $quantity');
    return true;
  }
}

bool _ffiOk() {
  try {
    sqfliteFfiInit();
    return true;
  } catch (_) {
    return false;
  }
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(720, 1400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final ffi = _ffiOk() && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  group('copie locale étendue', () {
    test('téléchargée avec le catalogue (mêmes déclencheurs) : BL, lignes, commandes, motifs, rayons…', () async {
      final e = await _env(offline: false, copie: false);
      e.hl.sync.fetch = e.srv.fetch;
      expect(e.hl.sync.extensions, contains(e.stock.refs));
      expect(await e.hl.sync.syncAll(), isTrue);
      final s = e.stock.refs.stats;
      expect(s.count(StockRef.blsAEntrer), 1);
      expect(s.count(StockRef.blsClotures), 1);
      expect(s.count(StockRef.lignesBl), 3);
      expect(s.count(StockRef.controleReception), 1);
      expect(s.count(StockRef.commandes), 1);
      expect(s.count(StockRef.lignesCommandes), 1);
      expect(s.count(StockRef.grossistes), 1);
      expect(s.count(StockRef.motifsRetour), 1);
      expect(s.count(StockRef.rayons), 2);
      for (final c in StockRef.values) {
        expect(s.lastSync[c], _t0, reason: c.label);
      }
      // Date d'entrée en stock exacte reprise du contrôle réception.
      expect((await e.stock.store.ref(StockRef.blsClotures, 'bl2'))!['_hl_maj'], '10/10/2026 08:10');
    });

    test('transactionnelle : en cas d\'échec, l\'ancienne copie reste entière', () async {
      final store = MemoryStockStore();
      final e = await _env(offline: false, store: store);
      e.srv.lines['bl1']!.add(_blLine('d9', 'bl1', 'BL-001', 'p9', 'NOUVEAU'));
      store.failNextWrite = true;
      e.hl.sync.fetch = e.srv.fetch;
      expect(await e.hl.sync.syncAll(), isFalse);
      expect(e.hl.sync.error, contains('Stock'));
      expect(e.stock.refs.stats.count(StockRef.lignesBl), 3);
      e.srv.down = true;
      expect(await e.hl.sync.syncAll(), isFalse, reason: 'serveur injoignable');
      expect(e.stock.refs.stats.count(StockRef.lignesBl), 3);
    });

    testWidgets('Réglages › Hors ligne : nombre d\'éléments par catégorie et date', (tester) async {
      _phone(tester);
      final e = await tester.runAsync(() => _env(offline: false));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: StockHorsLigneSection(stock: e!.stock)))));
      await tester.pumpAndSettle();
      expect(find.text('Lignes de BL'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('compte_stock_lignesBl'))).data, '3');
      expect(tester.widget<Text>(find.byKey(const Key('compte_stock_rayons'))).data, '2');
      expect(find.text('10/10 08:30'), findsWidgets);
      expect(find.byKey(const Key('lien_operations_stock')), findsOneWidget);
    });
  });

  group('file persistante', () {
    test('les opérations survivent à un redémarrage (SQLite, migration nommée)', () async {
      final dir = await Directory.systemTemp.createTemp('h3_');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/hl.db';
      var local = SqfliteLocalStore(factory: databaseFactoryFfi, path: path);
      var q = StockHorsLigne(store: SqfliteStockStore(local), clock: () => _t0).queue;
      await q.addPerime(produitId: 'p1', produit: 'DOLIPRANE', lot: 'L1', date: '2026-12-31', qty: 2);
      await q.setPointage(commande: false, refId: 'bl2', reference: 'BL BL-002', detailId: 'd2', produit: 'AUGMENTIN', qty: 4);
      await q.setPointage(commande: false, refId: 'bl2', reference: 'BL BL-002', detailId: 'd2', produit: 'AUGMENTIN', qty: 3);
      // Le catalogue (H1) fonctionne toujours dans le même fichier.
      await local.replace(CatalogueCategorie.produits, [
        {'lgFAMILLEID': 'p1', 'strNAME': 'DOLIPRANE', 'intCIP': '3017598', 'intPRICE': 1000, 'intNUMBERAVAILABLE': 3}
      ], _t0);
      await local.close();

      local = SqfliteLocalStore(factory: databaseFactoryFfi, path: path);
      q = StockHorsLigne(store: SqfliteStockStore(local), clock: () => _t0).queue;
      await q.load();
      expect(q.pendingCount, 2);
      final pointage = q.pending.firstWhere((o) => o.type == StockOpType.pointageBl);
      expect(pointage.lines.single.data['qty'], 3, reason: 'la dernière saisie d\'une ligne remplace la précédente');
      expect((await local.stats()).count(CatalogueCategorie.produits), 1);
      // « Vider la copie locale » n'efface jamais la file.
      await local.clear();
      await SqfliteStockStore(local).clearRefs();
      await q.load(force: true);
      expect(q.pendingCount, 2);
      await local.close();
    }, skip: ffi ? false : 'SQLite (ffi) indisponible');
  });

  group('envoi idempotent, une opération à la fois', () {
    test('réception : coupure après l\'ajout du lot → relu sur le serveur, jamais renvoyé', () async {
      final e = await _env();
      final gw = OfflineReceptionGateway(_OnlineReception(), stock: e.stock);
      final r = await gw.addLot(detailId: 'd1', quantity: 2, freeQty: 1, numLot: 'LOT-A', expiry: DateTime(2027, 6, 30));
      expect(r.success, isTrue);
      expect(r.message, contains('hors ligne'));
      final lines = await gw.lines('bl1');
      expect(lines.firstWhere((l) => l.detailId == 'd1').entered, 3, reason: 'saisie hors ligne visible');
      expect(lines.firstWhere((l) => l.detailId == 'd1').lots, ['LOT-A']);
      // Contrôle conservé : pas plus que commandé.
      expect((await gw.addLot(detailId: 'd1', quantity: 9, freeQty: 0, numLot: 'X')).success, isFalse);

      e.hl.monitor.goOnline();
      final op = e.stock.queue.pending.single;
      e.srv.coupeApres = '/commande/add-lot';
      final r1 = await e.stock.queue.envoyer(selection: {op.id});
      expect(r1.interruption, isNotNull);
      expect(op.pending, isTrue);
      expect(op.lines.first.etat, StockLineEtat.sending);
      expect(e.srv.count('POST /commande/add-lot'), 1);

      final r2 = await e.stock.queue.envoyer(selection: {op.id});
      expect(r2.envoyees, 1);
      expect(op.statut, StockOpStatut.envoyee);
      expect(op.lines.first.etat, StockLineEtat.dejaApplique);
      expect(e.srv.count('POST /commande/add-lot'), 1, reason: 'aucun doublon');
      expect(e.srv.lines['bl1']!.first['quantiteSaisie'], 3);
    });

    test('retour fournisseur : coupure → produits relus sur le serveur, jamais ajoutés deux fois', () async {
      final e = await _env();
      final gw = OfflineRetourGateway(_FakeRetourOnline(), stock: e.stock);
      expect((await gw.motifs()).single.label, 'colis avarié');
      final bls = await gw.bls(from: DateTime(2026, 10, 10), to: DateTime(2026, 10, 10));
      expect(bls.single.ref, 'BL-002');
      final c = await gw.create(blRef: 'BL-002', produitId: 'p2', motifId: '01', quantity: 1, comment: 'casse');
      expect(c.success, isTrue);
      await gw.addItem(retourId: c.retour!.id, produitId: 'p2', motifId: '01', quantity: 1);
      expect((await gw.items(c.retour!.id)).single.quantity, 2, reason: 'cumul par produit comme Prestige');
      final op = e.stock.queue.byId(c.retour!.id)!;
      op.lines.add(StockOpLine(key: '${op.id}-x', label: 'AUTRE', data: {'produitId': 'p9', 'motifId': '01', 'qty': 1}));
      await e.stock.store.saveOp(op);

      e.hl.monitor.goOnline();
      // Coupure après l'ajout du 2ᵉ produit : relu dans retours-items, pas de second ajout.
      e.srv.coupeApres = '/retourfournisseur/add-item';
      expect((await e.stock.queue.envoyer(selection: {op.id})).interruption, isNotNull);
      final r = await e.stock.queue.envoyer(selection: {op.id});
      expect(r.envoyees, 1);
      expect(e.srv.count('/retourfournisseur/new'), 1, reason: 'aucun doublon');
      expect(e.srv.count('/retourfournisseur/add-item'), 1);
      expect(e.srv.retours.single['str_COMMENTAIRE'], allOf(startsWith('casse'), contains('[HL:')));
      expect(op.meta['retourRef'], '9001');
    });

    test('retour : réponse de création perdue et retour introuvable → anomalie, jamais de second retour', () async {
      final e = await _env();
      final gw = OfflineRetourGateway(_FakeRetourOnline(), stock: e.stock);
      final c = await gw.create(blRef: 'BL-002', produitId: 'p2', motifId: '01', quantity: 1);
      e.hl.monitor.goOnline();
      e.srv.coupeApres = '/retourfournisseur/new';
      await e.stock.queue.envoyer(selection: {c.retour!.id});
      // Prestige ne liste que les retours validés : le retour « en préparation » reste introuvable.
      e.srv.retours.first['str_COMMENTAIRE'] = '';
      final r = await e.stock.queue.envoyer(selection: {c.retour!.id});
      expect(r.anomalies, 1);
      expect(e.srv.count('/retourfournisseur/new'), 1);
      expect(e.stock.queue.anomaliesList.single.motif, contains('vérifiez sur Prestige'));
    });

    test('pointages, péremption, périmés, emplacement : même routes que les écrans', () async {
      final e = await _env();
      await e.stock.pointerBl('bl2', 'd2', 4);
      await e.stock.pointerCommande('o1', 'od1', 3);
      await e.stock.queue.addPeremption(produitId: 'p1', cip: '3017598', produit: 'DOLIPRANE', numLot: 'L7', date: DateTime(2027, 1, 31), qty: 5);
      await e.stock.queue.addPerime(produitId: 'p1', produit: 'DOLIPRANE', lot: 'L1', date: '2026-09-30', qty: 1);
      await e.stock.queue.setEmplacement(produitId: 'p1', produit: 'DOLIPRANE', rayonId: 'r2', rayon: 'RAYON B');
      e.hl.monitor.goOnline();
      final r = await e.stock.queue.envoyer(selection: {for (final o in e.stock.queue.pending) o.id});
      expect(r.envoyees, 5);
      expect(e.srv.lines['bl2']!.first['checkedQuantity'], 4);
      expect(e.srv.orderItems.first['checkedQuantity'], 3);
      expect(e.srv.lots.single['NUMLOT'], 'L7');
      expect(e.srv.perimes.single['quantity'], 1);
      expect(e.srv.liteInfo.single, {'id': 'p1', 'rayonId': 'r2'});
      // Ordre de saisie respecté.
      final posts = e.srv.calls.where((c) => c.startsWith('POST')).toList();
      expect(posts.first, 'POST /commande/bon/items/checked-quantities');
      expect(posts.last, 'POST /fichearticle/produit/update-lite-info');
    });

    test('serveur injoignable : rien n\'est marqué refusé, tout reste en attente', () async {
      final e = await _env();
      await e.stock.pointerBl('bl2', 'd2', 4);
      e.srv.down = true;
      final r = await e.stock.queue.envoyer(selection: {e.stock.queue.pending.single.id});
      expect(r.interruption, contains('injoignable'));
      expect(e.stock.queue.pendingCount, 1);
      expect(e.stock.queue.anomaliesList, isEmpty);
    });
  });

  group('anomalies', () {
    test('BL déjà clôturé sur le serveur → anomalie avec motif, gardée dans le rapport', () async {
      final e = await _env();
      final gw = OfflineReceptionGateway(_OnlineReception(), stock: e.stock);
      await gw.addLot(detailId: 'd1', quantity: 1, freeQty: 0, numLot: 'L1');
      e.srv.closed.add('bl1'); // entré en stock depuis un autre poste
      e.hl.monitor.goOnline();
      final op = e.stock.queue.pending.single;
      final r = await e.stock.queue.envoyer(selection: {op.id});
      expect(r.anomalies, 1);
      expect(op.statut, StockOpStatut.anomalie);
      expect(op.motif, contains('déjà clôturé'));
      expect(e.srv.count('POST /commande/add-lot'), 0);
      final a = (await e.stock.queue.anomalies()).single;
      expect(a.source, 'stock');
      expect(a.reference, 'BL BL-001 · DPCI');
      expect(a.traitee, isFalse);
      await e.stock.queue.setTraitee(a.id, true);
      expect(e.stock.queue.anomaliesNonTraitees, 0);
    });

    test('ligne déjà pointée sur le serveur avec une autre quantité → anomalie, non remplacée', () async {
      final e = await _env();
      await e.stock.pointerBl('bl2', 'd2', 4);
      e.srv.lines['bl2']!.first
        ..['checked'] = true
        ..['checkedQuantity'] = 2;
      e.hl.monitor.goOnline();
      final r = await e.stock.queue.envoyer(selection: {e.stock.queue.pending.single.id});
      expect(r.anomalies, 1);
      expect(e.stock.queue.anomaliesList.single.motif, contains('Déjà pointée sur le serveur (2)'));
      expect(e.srv.lines['bl2']!.first['checkedQuantity'], 2);
    });

    test('commande déjà transformée en BL, produit inconnu → anomalies', () async {
      final e = await _env();
      await e.stock.pointerCommande('o1', 'od1', 3);
      await e.stock.queue.addPeremption(produitId: 'inconnu', produit: 'X', numLot: 'L', date: DateTime(2027), qty: 1);
      e.srv.orderEnCours = false;
      e.hl.monitor.goOnline();
      final r = await e.stock.queue.envoyer(selection: {for (final o in e.stock.queue.pending) o.id});
      expect(r.anomalies, 2);
      final motifs = e.stock.queue.anomaliesList.map((a) => a.motif).join('\n');
      expect(motifs, contains('Commande plus en cours'));
      expect(motifs, contains('produit inconnu'));
    });

    testWidgets('écran commun « Anomalies de synchronisation » : ventes et stock', (tester) async {
      _phone(tester);
      final e = await tester.runAsync(() async {
        final e = await _env();
        await e.stock.pointerBl('bl2', 'd2', 4);
        e.srv.closed.add('bl2');
        e.srv.lines['bl2']!.first
          ..['checked'] = true
          ..['checkedQuantity'] = 1;
        e.hl.monitor.goOnline();
        await e.stock.queue.envoyer(selection: {e.stock.queue.pending.single.id});
        return e;
      });
      await tester.pumpWidget(MaterialApp(home: AnomaliesHorsLigneScreen(horsLigne: e!.hl, stock: e.stock)));
      await tester.pumpAndSettle();
      expect(find.text('OPÉRATIONS DE STOCK'), findsOneWidget);
      expect(find.textContaining('Déjà pointée sur le serveur'), findsWidgets);
      expect(find.text('1 anomalie(s) · 1 non traitée(s)'), findsOneWidget);
      await tester.tap(find.byKey(Key('anomalie_traitee_${e.stock.queue.anomaliesList.single.id}')));
      await tester.pumpAndSettle();
      expect(e.stock.queue.anomaliesList.single.traitee, isTrue);
    });
  });

  group('confirmation (jamais d\'envoi sans accord)', () {
    testWidgets('liste des opérations, décocher = « non envoyée — ressaisie sur le serveur »', (tester) async {
      _phone(tester);
      final e = await tester.runAsync(() async {
        final e = await _env();
        await e.stock.pointerBl('bl2', 'd2', 4);
        await e.stock.queue.addPerime(produitId: 'p1', produit: 'DOLIPRANE', lot: 'L1', date: '2026-09-30', qty: 1);
        e.hl.monitor.goOnline();
        return e;
      });
      final ops = e!.stock.queue.pending;
      await tester.pumpWidget(MaterialApp(home: StockEnvoiScreen(stock: e.stock)));
      await tester.pumpAndSettle();
      expect(find.text('Pointage BL'), findsOneWidget);
      expect(find.text('BL BL-002 · DPCI'), findsOneWidget);
      expect(find.text('10/10 08:30 · 1 ligne(s)'), findsNWidgets(2));
      expect(e.srv.calls, isEmpty, reason: 'rien envoyé avant la confirmation');

      await tester.tap(find.byKey(Key('coche_${ops[1].id}')));
      await tester.pump();
      expect(find.text('Envoyer 1 · 1 ressaisie(s)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirmer_envoi')));
      await tester.pumpAndSettle();
      expect(find.text('Opérations décochées'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Continuer'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(ops[0].statut, StockOpStatut.envoyee);
      expect(ops[1].statut, StockOpStatut.ressaisie);
      expect(e.srv.count('/gestionperime/add'), 0);
      expect(find.textContaining('1 envoyée(s)'), findsOneWidget);

      // Historique : statut « Non envoyée — ressaisie sur le serveur ».
      await tester.pumpWidget(MaterialApp(home: StockOperationsScreen(stock: e.stock)));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Non envoyée — ressaisie sur le serveur'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('Non envoyée — ressaisie sur le serveur'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Envoyée'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('Envoyée'), findsOneWidget);
    });

    testWidgets('« Plus tard » : rien n\'est envoyé, tout reste en attente', (tester) async {
      _phone(tester);
      final e = await tester.runAsync(() async {
        final e = await _env();
        await e.stock.pointerBl('bl2', 'd2', 4);
        e.hl.monitor.goOnline();
        return e;
      });
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) => TextButton(onPressed: () => ouvrirEnvoiStock(c, stock: e!.stock), child: const Text('go')))));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('plus_tard')));
      await tester.pumpAndSettle();
      expect(e!.stock.queue.pendingCount, 1);
      expect(e.srv.calls, isEmpty);
    });

    testWidgets('bandeau « opérations de stock en attente » (rien sans opération) ; hors ligne : envoi désactivé', (tester) async {
      _phone(tester);
      final e = await tester.runAsync(() => _env());
      await tester.pumpWidget(MaterialApp(
        navigatorKey: HorsLigne.navigatorKey,
        builder: (context, child) => HorsLigneScope(horsLigne: e!.hl, bindApp: false, child: child!),
        home: const Scaffold(body: Text('accueil')),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('bandeau_stock')), findsNothing);
      await tester.runAsync(() => e!.stock.pointerBl('bl2', 'd2', 4));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('bandeau_stock')), findsOneWidget);
      expect(find.text('1 opération(s) de stock enregistrée(s) hors ligne'), findsOneWidget);
      await tester.tap(find.byKey(const Key('bandeau_stock_action')));
      await tester.pumpAndSettle();
      expect(find.text('Opérations hors ligne (stock)'), findsOneWidget);
      final envoyer = tester.widget<ElevatedButton>(find.ancestor(of: find.text('Envoyer maintenant'), matching: find.byWidgetPredicate((w) => w is ElevatedButton)));
      expect(envoyer.onPressed, isNull);
      expect(find.text('Envoi : $kEnLigneUniquement'), findsOneWidget);
      expect(e!.srv.calls, isEmpty);
    });
  });

  group('hors ligne : écrans', () {
    test('sans copie locale : message clair, jamais une liste vide trompeuse', () async {
      final e = await _env(copie: false);
      final gw = OfflineReceptionGateway(_OnlineReception(), stock: e.stock);
      await expectLater(gw.bls(), throwsA(isA<StockHorsLigneException>().having((x) => x.message, 'message', contains('Réglages › Hors ligne'))));
      final p = BlControlProvider(_Api());
      await p.fetchBonsLivraison(dtStart: '2026-10-10', dtEnd: '2026-10-10');
      expect(p.loadError, contains('absents de cet appareil'));
    });

    test('actions impossibles hors ligne : « Disponible en ligne uniquement »', () async {
      final e = await _env();
      final online = _OnlineReception();
      final gw = OfflineReceptionGateway(online, stock: e.stock);
      expect((await gw.createBl(orderId: 'o1', ref: 'X', date: _t0, amountHt: 1, tva: 0)).message, contains(kEnLigneUniquement));
      expect(await gw.canValidate(), isFalse);
      expect((await gw.validate('bl1')).message, contains(kEnLigneUniquement));
      expect(online.calls, isEmpty);

      final perimes = PerimeProvider(_Api());
      await perimes.loadProduitsPerimes();
      expect(perimes.errorMessage, contains(kEnLigneUniquement));
      expect(perimes.produitsPerimesList, isEmpty);
      expect(await perimes.validateSaisie(), isFalse);

      final upd = ProductUpdateProvider(_Api());
      await upd.selectProduct(ProductSearchResult.fromJson({'lgFAMILLEID': 'p1', 'strNAME': 'DOLIPRANE', 'intCIP': '3017598', 'intPRICE': 1}));
      expect(await upd.updateEAN('123'), isFalse);
      expect(upd.errorMessage, contains(kEnLigneUniquement));
      // Emplacement : enregistré hors ligne (rayons de la copie).
      await upd.loadRayons();
      expect(upd.rayons.map((r) => r.libelle), ['RAYON A', 'RAYON B']);
      expect(await upd.updateEmplacement('r2'), isTrue);
      expect(e.stock.queue.pending.single.type, StockOpType.emplacement);
    });

    test('pointage BL, contrôle réception, contrôle livraison, périmés : copie + file', () async {
      final e = await _env();
      final api = _Api();
      final bl = BlControlProvider(api);
      await bl.fetchBonsLivraison(dtStart: '2026-10-10', dtEnd: '2026-10-10');
      expect(bl.bonsLivraison.single.ref, 'BL-002');
      await bl.selectBonLivraison(bl.bonsLivraison.single);
      expect(bl.items.single.nomProduit, 'AUGMENTIN 1G');
      expect(await bl.updateCheckedQuantity('d2', 4), isTrue);
      expect(bl.unsyncedCount, 0);

      final rec = ReceptionProvider(api);
      await rec.fetchReceptionBons(dtStart: '2026-10-01', dtEnd: '2026-10-10');
      expect(rec.receptionBons.single.details.single.quantiteControle, 4, reason: 'pointage hors ligne repris');

      final del = DeliveryControlProvider(api);
      await del.fetchCommandes();
      await del.selectCommande(del.commandes.single);
      expect(await del.updateCheckedQuantity('od1', 2), isTrue);

      final per = PerimeProvider(api);
      per.selectProduct(ProductSearchResult.fromJson({'lgFAMILLEID': 'p1', 'strNAME': 'DOLIPRANE', 'intCIP': '3017598', 'intPRICE': 1}));
      await per.addSaisieItem(lot: 'L1', datePeremption: '2026-09-30', quantite: 2);
      expect(per.saisieEnCoursList.single.produitLibelle, 'DOLIPRANE');
      await per.deleteSaisieItem(per.saisieEnCoursList.single.id);
      expect(per.saisieEnCoursList, isEmpty);

      expect(api.calls, isEmpty, reason: 'aucun appel au serveur hors ligne');
      expect(e.stock.queue.pending.map((o) => o.type), [StockOpType.pointageBl, StockOpType.pointageCommande]);
    });
  });

  group('mise à jour de la copie sans ralentir l\'appli', () {
    test('automatique : en pause pendant une opération en cours, reprise ensuite ; jamais deux à la fois', () async {
      var busy = true;
      final srv = FakePrestige();
      final local = MemoryLocalStore();
      final sync = CatalogueSync(store: local, clock: () => _t0, pause: const Duration(milliseconds: 5), occupee: () => busy);
      sync.extensions.add(StockHorsLigne(store: MemoryStockStore(), clock: () => _t0).refs);
      sync.fetch = srv.fetch;
      final f = sync.syncAll(auto: true);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(srv.calls, isEmpty, reason: 'aucune requête pendant l\'opération de l\'utilisateur');
      expect(sync.enPause, isTrue);
      expect(await sync.syncAll(auto: true), isFalse, reason: 'jamais deux mises à jour');
      busy = false;
      expect(await f, isTrue);
      expect(sync.enPause, isFalse);
      expect(srv.calls, isNotEmpty);
      expect(srv.calls.where((c) => c.contains('/commande/bon/items/')), isNotEmpty, reason: 'copie stock comprise');
    });

    test('manuelle : immédiate, même si l\'utilisateur travaille (lève la pause d\'une mise à jour auto)', () async {
      final srv = FakePrestige();
      final sync = CatalogueSync(store: MemoryLocalStore(), clock: () => _t0, pause: const Duration(milliseconds: 5), occupee: () => true);
      sync.fetch = srv.fetch;
      final auto = sync.syncAll(auto: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(srv.calls, isEmpty);
      expect(await sync.syncAll(), isTrue);
      expect(await auto, isTrue);
      expect(srv.calls, isNotEmpty);
    });

    test('activité de l\'appli : requête en cours ou récente = occupé', () async {
      ActiviteApp.reset();
      addTearDown(ActiviteApp.reset);
      ActiviteApp.calme = Duration.zero;
      expect(ActiviteApp.occupee, isFalse);
      ActiviteApp.debut();
      expect(ActiviteApp.occupee, isTrue);
      ActiviteApp.fin();
      expect(ActiviteApp.occupee, isFalse);
      ActiviteApp.calme = const Duration(seconds: 5);
      ActiviteApp.debut();
      ActiviteApp.fin();
      expect(ActiviteApp.occupee, isTrue, reason: 'délai de calme après une requête');
      ActiviteApp.calme = Duration.zero;
      var ecran = true;
      ActiviteApp.occupations.add(() => ecran);
      expect(ActiviteApp.occupee, isTrue);
      ecran = false;
      expect(ActiviteApp.occupee, isFalse);
    });
  });

  group('en ligne : aucune modification', () {
    test('passerelles et providers appellent le serveur comme avant, la file reste vide', () async {
      final e = await _env(offline: false);
      final online = _OnlineReception();
      final gw = OfflineReceptionGateway(online, stock: e.stock);
      expect((await gw.bls()).single.ref, 'SRV-1');
      expect((await gw.addLot(detailId: 'd1', quantity: 1, freeQty: 0, numLot: 'L')).message, 'Lot enregistré');
      expect((await gw.createBl(orderId: 'o', ref: 'r', date: _t0, amountHt: 1, tva: 0)).message, 'BL créé');
      expect(online.calls, ['bls', 'addLot d1', 'createBl']);

      final api = _Api();
      final bl = BlControlProvider(api);
      await bl.fetchBonsLivraison(dtStart: '2026-10-10', dtEnd: '2026-10-10');
      expect(bl.bonsLivraison.single.ref, 'SRV');
      await bl.selectBonLivraison(bl.bonsLivraison.single);
      expect(await bl.updateCheckedQuantity('x1', 2), isTrue);
      expect(api.calls, ['getBonsLivraison', 'getBonLivraisonItems', 'post x1 2']);
      expect(e.stock.queue.pendingCount, 0);
      expect(e.srv.calls, isEmpty);
    });
  });
}

/// Passerelle en ligne des retours : jamais appelée hors ligne (Fake lève une erreur sinon).
class _FakeRetourOnline extends Fake implements RetourGateway {}
