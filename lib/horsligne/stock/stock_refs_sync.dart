// lib/horsligne/stock/stock_refs_sync.dart
// Copie « stock » (H3), téléchargée à la suite du catalogue avec les MÊMES déclencheurs (après la
// connexion si > 12 h, toutes les 30 min en ligne, bouton « Mettre à jour maintenant ») et les MÊMES
// routes que les écrans :
//   BL à entrer  : /commande/list-bons statut=enable          (Réception BL)
//   BL entrés    : /commande/list-bons statut=is_Closed, 3 j  (Pointage BL, Retours fournisseurs)
//   lignes de BL : /commande/bon/items/{id}                    (les deux listes ci-dessus)
//   contrôle     : /etat-control-bon/list, 3 j                 (Contrôle réception, lignes incluses)
//   commandes    : /commande/list + /commande/list/passees     (Réception, Contrôle livraison)
//   lignes cmde  : /commande/commande-en-cours-items           (Contrôle livraison)
//   référentiels : /common/grossiste, /common/motifs-retour, /common/rayons, /gestionperime/saisie-encours
// Tout est d'abord téléchargé, puis écrit en UNE transaction : en cas d'échec, l'ancienne copie reste.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/horsligne/catalogue_sync.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_models.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_store.dart';

class StockRefSync extends ChangeNotifier implements CatalogueExtension {
  final StockStore store;
  final DateTime Function() _clock;

  /// Profondeur de la copie des BL entrés en stock et du contrôle réception : les 3 DERNIERS JOURS
  /// (aujourd'hui compris). Les écrans hors ligne affichent par défaut le jour même.
  static const int jours = 3;

  /// Téléchargements de lignes en parallèle.
  final int parallel;

  StockRefSync({required this.store, DateTime Function()? clock, this.parallel = 4}) : _clock = clock ?? DateTime.now;

  StockRefStats _stats = const StockRefStats();
  bool _loaded = false;
  String? _error;

  StockRefStats get stats => _stats;
  bool get loaded => _loaded;
  String? get error => _error;

  @override
  String get label => 'Stock (BL, commandes, retours)';

  Future<StockRefStats> refreshStats() async {
    try {
      _stats = await store.refStats();
      _error = null;
    } catch (e) {
      _error = 'Copie stock indisponible : $e';
    }
    _loaded = true;
    notifyListeners();
    return _stats;
  }

  @override
  Future<void> clear() async {
    await store.clearRefs();
    await refreshStats();
  }

  static final _iso = DateFormat('yyyy-MM-dd');

  static List<Map<String, dynamic>> _data(Map<String, dynamic> body, String path) {
    final data = body['data'];
    if (data == null) return [];
    if (data is! List) throw CatalogueSyncException('Réponse inattendue du serveur ($path).');
    return [for (final e in data) if (e is Map) Map<String, dynamic>.from(e)];
  }

  @override
  Future<void> sync(CatalogueFetch fetch, void Function(String etape, int done, int? total) progress) async {
    try {
      final rows = await download(fetch, progress);
      await store.replaceRefs(rows, _clock());
    } finally {
      await refreshStats();
    }
  }

  /// Télécharge toute la copie (sans l'enregistrer).
  Future<Map<StockRef, List<Map<String, dynamic>>>> download(CatalogueFetch f,
      [void Function(String etape, int done, int? total)? progress]) async {
    void step(String e, [int done = 0, int? total]) => progress?.call(e, done, total);
    final now = _clock();
    final today = DateTime(now.year, now.month, now.day);
    String d(int days) => _iso.format(today.subtract(Duration(days: days)));
    Future<List<Map<String, dynamic>>> get(String path, Map<String, dynamic> q) async => _data(await f(path, q), path);

    step('BL à entrer en stock');
    final aEntrer = await get('/commande/list-bons', {'query': '', 'start': 0, 'limit': 500, 'statut': 'enable'});

    step('BL entrés en stock');
    Future<List<Map<String, dynamic>>> closed(int days) => get('/commande/list-bons', {
          'query': '',
          'page': 1,
          'start': 0,
          'limit': 9999,
          'statut': 'is_Closed',
          'dtStart': d(days),
          'dtEnd': d(0),
        });
    // Deux lectures (3 jours / jour) : le serveur filtre sur la date d'entrée en stock, absente
    // de la réponse ; on note la tranche pour reproduire hors ligne les périodes des écrans.
    final mois = await closed(jours - 1);
    final jour = {for (final r in await closed(0)) StockRef.blsClotures.idOf(r)};
    int tranche(String id) => jour.contains(id) ? 0 : jours - 1;
    for (final r in mois) {
      r['_hl_jours'] = tranche(StockRef.blsClotures.idOf(r));
    }

    step('Contrôle réception');
    final controle = await get('/etat-control-bon/list', {
      'search': '',
      'grossisteId': '',
      'page': 1,
      'start': 0,
      'limit': 9999,
      'group': '[{"property":"fournisseurId","direction":"ASC"}]',
      'sort': '[{"property":"fournisseurId","direction":"ASC"}]',
      'dtStart': d(jours - 1),
      'dtEnd': d(0),
    });
    // Date d'entrée en stock exacte quand le contrôle réception la donne (dtUPDATED).
    final maj = {for (final c in controle) StockRef.controleReception.idOf(c): '${c['dtUPDATED'] ?? ''}'};
    for (final r in mois) {
      final m = maj[StockRef.blsClotures.idOf(r)];
      if (m != null && m.isNotEmpty) r['_hl_maj'] = m;
    }

    // Lignes des BL (à entrer + entrés), quelques lectures en parallèle.
    final blIds = <String>{for (final r in [...aEntrer, ...mois]) StockRef.blsAEntrer.idOf(r)}..remove('');
    final lignes = await _each('Lignes de BL', blIds.toList(), step, (id) async {
      final items = await get('/commande/bon/items/$id', {'page': 1, 'start': 0, 'limit': 9999, 'query': '', 'filtre': 'ALL'});
      return [for (final l in items) {...l, '_parent': id}];
    });

    step('Commandes');
    final params = {'page': 1, 'start': 0, 'limit': 200, 'query': ''};
    final encours = await get('/commande/list', params);
    final passees = await get('/commande/list/passees', params);
    final commandes = [
      for (final c in encours) {...c, '_hl_passee': false},
      for (final c in passees) {...c, '_hl_passee': true},
    ];
    final orderIds = [for (final c in encours) StockRef.commandes.idOf(c)]..removeWhere((e) => e.isEmpty);
    final lignesCmd = await _each('Lignes de commandes', orderIds, step, (id) async {
      final items = await get('/commande/commande-en-cours-items', {'orderId': id, 'page': 1, 'start': 0, 'limit': 9999});
      return [for (final l in items) {...l, '_parent': id}];
    });

    step('Grossistes, motifs, emplacements');
    final grossistes = await get('/common/grossiste', {'query': '', 'page': 1, 'start': 0, 'limit': 9999});
    final motifs = await get('/common/motifs-retour', {});
    final rayons = await get('/common/rayons', {'query': '', 'page': 1, 'start': 0, 'limit': 9999});
    final perimes = await get('/gestionperime/saisie-encours', {'page': 1, 'start': 0, 'limit': 999});
    final jourPerimes = _iso.format(today);
    for (final p in perimes) {
      p['_hl_jour'] = jourPerimes;
    }

    return {
      StockRef.blsAEntrer: aEntrer,
      StockRef.blsClotures: mois,
      StockRef.lignesBl: lignes,
      StockRef.controleReception: controle,
      StockRef.commandes: commandes,
      StockRef.lignesCommandes: lignesCmd,
      StockRef.grossistes: grossistes,
      StockRef.motifsRetour: motifs,
      StockRef.rayons: rayons,
      StockRef.perimesEnCours: perimes,
    };
  }

  Future<List<Map<String, dynamic>>> _each(String etape, List<String> ids, void Function(String, [int, int?]) step,
      Future<List<Map<String, dynamic>>> Function(String id) one) async {
    final out = <Map<String, dynamic>>[];
    var done = 0;
    step(etape, 0, ids.length);
    for (var i = 0; i < ids.length; i += parallel) {
      final chunk = ids.sublist(i, i + parallel > ids.length ? ids.length : i + parallel);
      for (final rows in await Future.wait(chunk.map(one))) {
        out.addAll(rows);
      }
      done += chunk.length;
      step(etape, done, ids.length);
    }
    return out;
  }
}
