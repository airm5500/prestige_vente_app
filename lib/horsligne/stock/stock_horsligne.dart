// lib/horsligne/stock/stock_horsligne.dart
// Point d'entrée du stock hors ligne (H3) : copie de référence, file des opérations, envoi.
// Les écrans et providers l'utilisent UNIQUEMENT quand l'état est « hors ligne »
// (HorsLigne.instance.offline) : en ligne, rien ne change.
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/api/models/bon_livraison.dart';
import 'package:prestige_vente_app/api/models/bon_livraison_item.dart';
import 'package:prestige_vente_app/api/models/commande.dart';
import 'package:prestige_vente_app/api/models/commande_item.dart';
import 'package:prestige_vente_app/api/models/perime_models.dart';
import 'package:prestige_vente_app/api/models/rayon.dart';
import 'package:prestige_vente_app/api/models/reception_model.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart';
import 'package:prestige_vente_app/horsligne/server_monitor.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_models.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_queue.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_refs_sync.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_sender.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_store.dart';

class StockHorsLigne {
  final StockStore store;
  final StockRefSync refs;
  final StockQueue queue;
  final DateTime Function() _clock;

  StockHorsLigne({required this.store, StockServer? server, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now,
        refs = StockRefSync(store: store, clock: clock),
        queue = StockQueue(store: store, server: server, clock: clock);

  /// Même fichier SQLite que le catalogue (migration nommée), sinon mémoire.
  factory StockHorsLigne.forStore(LocalStore local) =>
      StockHorsLigne(store: local is SqfliteLocalStore ? SqfliteStockStore(local) : MemoryStockStore());

  static StockHorsLigne? _instance;

  /// Instance de l'appli (remplaçable dans les tests).
  static StockHorsLigne get instance => _instance ??= StockHorsLigne.forStore(HorsLigne.instance.store);
  static set instance(StockHorsLigne? v) => _instance = v;

  /// Ouverture automatique de la confirmation d'envoi au retour du serveur (désactivable).
  static bool confirmerAuRetour = true;

  bool get offline => HorsLigne.instance.offline;
  DateTime get now => _clock();

  // ---------------------------------------------------------------------------
  // Branchement
  // ---------------------------------------------------------------------------

  HorsLigne? _attached;
  Dio? _dio;

  /// Ajoute la copie « stock » à la synchro du catalogue (mêmes déclencheurs) et charge la file.
  void attach(HorsLigne hl) {
    if (!hl.sync.extensions.contains(refs)) hl.sync.extensions.add(refs);
    if (identical(_attached, hl)) return;
    _attached = hl;
    queue.load();
    refs.refreshStats();
  }

  /// Envoi avec la même session (cookies) et la même adresse que l'appli.
  void bind(ApiService api) {
    final d = _dio ??= (Dio(BaseOptions(connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 30)))
      ..transformer = BackgroundTransformer()
      ..interceptors.add(CookieManager(DioClient.cookieJar)));
    d.options.baseUrl = api.dio.options.baseUrl;
    queue.server ??= DioStockServer(d);
  }

  /// Le serveur répond (envoi possible) ?
  static bool get enLigne => HorsLigne.instance.monitor.etat == EtatServeur.enLigne;

  // ---------------------------------------------------------------------------
  // Lecture de la copie (hors ligne)
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> rows(StockRef c, {String? parent}) async {
    if (!refs.loaded) await refs.refreshStats();
    if (refs.stats.lastSync[c] == null) {
      throw StockHorsLigneException('Hors ligne : « ${c.label} » absents de cet appareil. '
          'Mettez à jour la copie locale quand le serveur répond (Réglages › Hors ligne).');
    }
    return store.refs(c, parent: parent);
  }

  static final _iso = DateFormat('yyyy-MM-dd');
  static final _fr = DateFormat('dd/MM/yyyy');

  static DateTime? _day(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    try {
      return t.contains('/') ? _fr.parseLoose(t.split(' ').first) : _iso.parseLoose(t.substring(0, 10));
    } catch (_) {
      return null;
    }
  }

  DateTime get _today {
    final n = _clock();
    return DateTime(n.year, n.month, n.day);
  }

  /// BL entré en stock dans la période ? Date exacte si connue, sinon tranche (jour / 7 j / 30 j).
  bool _inPeriod(Map<String, dynamic> r, DateTime? from, DateTime? to) {
    if (from == null && to == null) return true;
    final d = _day('${r['_hl_maj'] ?? ''}');
    if (d != null) return (from == null || !d.isBefore(from)) && (to == null || !d.isAfter(to));
    final jours = (r['_hl_jours'] as num?)?.toInt() ?? StockRefSync.jours - 1;
    final (minAge, maxAge) = jours == 0 ? (0, 0) : jours <= 6 ? (1, 6) : (7, StockRefSync.jours - 1);
    final back = from == null ? StockRefSync.jours : _today.difference(from).inDays;
    final end = to == null ? 0 : _today.difference(to).inDays;
    return minAge <= back && maxAge >= end;
  }

  static bool _matchRef(String ref, String query) => query.trim().isEmpty || ref.toUpperCase().startsWith(query.trim().toUpperCase());

  /// Pointage BL : BL entrés en stock de la période (format de /commande/list-bons).
  Future<List<BonLivraison>> blsClotures({String query = '', String? dtStart, String? dtEnd}) async {
    final from = _day(dtStart ?? '');
    final to = _day(dtEnd ?? '');
    return [
      for (final r in await rows(StockRef.blsClotures))
        if (_matchRef('${r['str_REF_LIVRAISON'] ?? ''}', query) && _inPeriod(r, from, to)) BonLivraison.fromJson(r),
    ];
  }

  /// Lignes d'un BL, avec les pointages saisis hors ligne.
  Future<List<Map<String, dynamic>>> blLinesJson(String blId) async {
    final lines = await rows(StockRef.lignesBl, parent: blId);
    if (lines.isEmpty) throw const StockHorsLigneException('Hors ligne : les lignes de ce BL ne sont pas sur cet appareil.');
    final pointes = pointages(StockOpType.pointageBl, blId);
    for (final l in lines) {
      final q = pointes['${l['lg_BON_LIVRAISON_DETAIL']}'];
      if (q != null) {
        l['checked'] = true;
        l['checkedQuantity'] = q;
      }
    }
    return lines;
  }

  Future<List<BonLivraisonItem>> blItems(String blId) async => (await blLinesJson(blId)).map(BonLivraisonItem.fromJson).toList();

  /// Contrôle réception (format de /etat-control-bon/list), quantités contrôlées hors ligne comprises.
  Future<List<ReceptionBon>> controleReception({String query = '', String? dtStart, String? dtEnd}) async {
    final from = _day(dtStart ?? '');
    final to = _day(dtEnd ?? '');
    final out = <ReceptionBon>[];
    for (final r in await rows(StockRef.controleReception)) {
      final d = _day('${r['dtDATELIVRAISON'] ?? ''}');
      if (d != null && ((from != null && d.isBefore(from)) || (to != null && d.isAfter(to)))) continue;
      if (!_matchRef('${r['strREFLIVRAISON'] ?? ''}', query)) continue;
      final pointes = pointages(StockOpType.pointageBl, '${r['lgBONLIVRAISONID']}');
      if (pointes.isNotEmpty) {
        for (final l in (r['bonLivraisonDetails'] as List? ?? const [])) {
          final q = pointes['${(l as Map)['lgBONLIVRAISONDETAIL']}'];
          if (q != null) {
            l['quantiteControle'] = q;
            l['checked'] = true;
          }
        }
        if (r['checked'] == 'NON_TRAITE') r['checked'] = 'EN_COURS';
      }
      out.add(ReceptionBon.fromJson(r));
    }
    return out;
  }

  /// Contrôle livraison : commandes en cours (format de /commande/list).
  Future<List<Commande>> commandesEnCours() async =>
      [for (final r in await rows(StockRef.commandes)) if (r['_hl_passee'] != true) Commande.fromJson(r)];

  Future<List<CommandeItem>> commandeItems(String orderId) async {
    final lines = await rows(StockRef.lignesCommandes, parent: orderId);
    if (lines.isEmpty) throw const StockHorsLigneException('Hors ligne : les produits de cette commande ne sont pas sur cet appareil.');
    final pointes = pointages(StockOpType.pointageCommande, orderId);
    for (final l in lines) {
      final q = pointes['${l['lg_ORDERDETAIL_ID']}'];
      if (q != null) {
        l['checked'] = true;
        l['checkedQuantity'] = q;
      }
    }
    return lines.map(CommandeItem.fromJson).toList();
  }

  Future<List<Rayon>> rayons() async => (await rows(StockRef.rayons)).map(Rayon.fromJson).toList();

  /// Périmés en cours de saisie : copie du jour + saisies hors ligne (id « HL:<ligne> »).
  Future<List<SaisieEnCoursItem>> perimesEnCours() async {
    final today = _iso.format(_today);
    final copie = (await rows(StockRef.perimesEnCours)).where((r) => r['_hl_jour'] == today).map(SaisieEnCoursItem.fromJson);
    return [
      ...copie,
      for (final l in queue.pendingLines(StockOpType.perime))
        SaisieEnCoursItem(
          id: '$perimeLocalPrefix${l.key}',
          lot: '${l.data['lot']}',
          produitCip: '${l.data['cip'] ?? ''}',
          quantity: (l.data['qty'] as num).toInt(),
          produitId: '${l.data['produitId']}',
          stockInitial: 0,
          dateEntree: 'hors ligne',
          datePeremption: '${l.data['date']}',
          stockFinal: 0,
          produitLibelle: l.label,
        ),
    ];
  }

  static const perimeLocalPrefix = 'HL:';

  /// Quantités pointées hors ligne (en attente) d'un BL / d'une commande : ligne → quantité.
  Map<String, int> pointages(StockOpType type, String refId) =>
      {for (final l in queue.pendingLines(type, refId: refId)) '${l.data['detailId']}': (l.data['qty'] as num).toInt()};

  // ---------------------------------------------------------------------------
  // Saisies hors ligne (depuis les providers)
  // ---------------------------------------------------------------------------

  /// Pointage d'une ligne de BL (Pointage BL, Contrôle réception).
  /// [blId] null : retrouvé d'après la ligne.
  Future<void> pointerBl(String? blId, String detailId, int qty) async {
    blId ??= '${(await store.ref(StockRef.lignesBl, detailId))?['_parent'] ?? ''}';
    if (blId.isEmpty) {
      for (final c in await store.refs(StockRef.controleReception)) {
        if ((c['bonLivraisonDetails'] as List? ?? const []).any((l) => '${(l as Map)['lgBONLIVRAISONDETAIL']}' == detailId)) {
          blId = '${c['lgBONLIVRAISONID']}';
        }
      }
    }
    if (blId == null || blId.isEmpty) throw const StockHorsLigneException('Hors ligne : ligne de BL absente de la copie locale.');
    var bl = await store.ref(StockRef.blsClotures, blId) ?? await store.ref(StockRef.blsAEntrer, blId);
    final controle = await store.ref(StockRef.controleReception, blId);
    final line = await store.ref(StockRef.lignesBl, detailId);
    Map? cline;
    for (final l in (controle?['bonLivraisonDetails'] as List? ?? const [])) {
      if ('${(l as Map)['lgBONLIVRAISONDETAIL']}' == detailId) cline = l;
    }
    bl ??= {};
    final ref = '${bl['str_REF_LIVRAISON'] ?? controle?['strREFLIVRAISON'] ?? ''}';
    final grossiste = '${bl['str_GROSSISTE_LIBELLE'] ?? controle?['fournisseurLibelle'] ?? ''}';
    final produit = '${line?['lg_FAMILLE_NAME'] ?? (cline?['produit'] as Map?)?['strNAME'] ?? detailId}';
    int? base;
    if (line != null) {
      base = line['checked'] == true ? (line['checkedQuantity'] as num?)?.toInt() : null;
    } else if (cline != null) {
      base = cline['checked'] == true ? (cline['quantiteControle'] as num?)?.toInt() : null;
    }
    await queue.setPointage(
        commande: false, refId: blId, reference: 'BL $ref', grossiste: grossiste, detailId: detailId, produit: produit, qty: qty, base: base);
  }

  /// Contrôle d'une ligne de commande (Contrôle livraison).
  Future<void> pointerCommande(String? orderId, String detailId, int qty) async {
    final line = await store.ref(StockRef.lignesCommandes, detailId);
    orderId ??= '${line?['_parent'] ?? ''}';
    if (orderId.isEmpty) throw const StockHorsLigneException('Hors ligne : ligne de commande absente de la copie locale.');
    final c = await store.ref(StockRef.commandes, orderId) ?? const {};
    await queue.setPointage(
      commande: true,
      refId: orderId,
      reference: 'Commande ${c['str_REF_ORDER'] ?? ''}',
      grossiste: '${c['str_GROSSISTE_LIBELLE'] ?? ''}',
      detailId: detailId,
      produit: '${line?['lg_FAMILLE_NAME'] ?? detailId}',
      qty: qty,
      base: line?['checked'] == true ? (line?['checkedQuantity'] as num?)?.toInt() : null,
    );
  }

  /// Réinitialise (tests).
  @visibleForTesting
  static void reset() {
    _instance = null;
    confirmerAuRetour = true;
  }
}
