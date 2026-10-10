// lib/horsligne/catalogue_sync.dart
// Mise à jour de la copie locale (hors ligne, étape H1) : téléchargement complet par pages avec
// les MÊMES routes que l'appli (/vente/search « % », /client/all, /client/tiers-payants/…,
// /common/reglement, /modereglement/all). Chaque catégorie est d'abord entièrement téléchargée,
// puis écrite en une transaction : si la synchro échoue au milieu, l'ancienne copie reste utilisable.
// Au démarrage (après connexion) si la copie a plus de 12 h, puis toutes les 30 min quand en ligne.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart';

/// Appel GET du serveur : renvoie le corps JSON ; lève [CatalogueSyncException] en cas d'échec.
typedef CatalogueFetch = Future<Map<String, dynamic>> Function(String path, Map<String, dynamic> query);

class CatalogueSyncException implements Exception {
  final String message;

  /// Le serveur n'a pas répondu (inutile d'essayer les catégories suivantes).
  final bool network;
  const CatalogueSyncException(this.message, {this.network = false});
  @override
  String toString() => message;
}

class CatalogueSync extends ChangeNotifier {
  final LocalStore store;
  CatalogueFetch? fetch;
  final DateTime Function() _clock;

  /// Taille des pages téléchargées.
  final int pageSize;

  CatalogueSync({required this.store, this.fetch, DateTime Function()? clock, this.pageSize = 500}) : _clock = clock ?? DateTime.now;

  static const Duration maxAge = Duration(hours: 12);
  static const Duration autoInterval = Duration(minutes: 30);

  bool _running = false;
  String? _etape;
  int _done = 0;
  int? _total;
  String? _error;
  final List<String> _warnings = [];
  LocalStats _stats = const LocalStats();
  bool _statsLoaded = false;
  String? _storeError;
  DateTime? _lastRun;
  Duration? _lastDuration;
  Timer? _auto;

  bool get running => _running;

  /// Étape en cours (« Produits », « Clients assurance »…).
  String? get etape => _etape;
  int get done => _done;
  int? get total => _total;

  /// Avancement de l'étape en cours (null si inconnu).
  double? get progress => _total == null || _total == 0 ? null : (_done / _total!).clamp(0, 1).toDouble();
  String? get error => _error;
  List<String> get warnings => List.unmodifiable(_warnings);
  LocalStats get stats => _stats;
  bool get statsLoaded => _statsLoaded;

  /// Base locale illisible (ex. SQLite indisponible).
  String? get storeError => _storeError;
  DateTime? get lastRun => _lastRun;
  Duration? get lastDuration => _lastDuration;

  /// Date du catalogue produits local (null : jamais synchronisé).
  DateTime? get catalogueAt => _stats.lastSync[CatalogueCategorie.produits];

  Future<LocalStats> refreshStats() async {
    try {
      _stats = await store.stats();
      _storeError = null;
    } catch (e) {
      _storeError = 'Copie locale indisponible : $e';
    }
    _statsLoaded = true;
    notifyListeners();
    return _stats;
  }

  /// La copie produits a-t-elle plus de [age] (ou n'existe pas) ?
  bool isStale([Duration age = maxAge]) {
    final at = catalogueAt;
    return at == null || _clock().difference(at) > age;
  }

  /// Synchro si la copie est trop ancienne (démarrage).
  Future<bool> syncIfStale() async {
    if (!_statsLoaded) await refreshStats();
    if (!isStale()) return true;
    return syncAll();
  }

  /// Synchro automatique toutes les 30 min tant que [online] est vrai (sans rien afficher).
  void startAuto(bool Function() online) {
    _auto?.cancel();
    _auto = Timer.periodic(autoInterval, (_) {
      if (online() && !_running && fetch != null) syncAll();
    });
  }

  void stopAuto() {
    _auto?.cancel();
    _auto = null;
  }

  @override
  void dispose() {
    stopAuto();
    super.dispose();
  }

  /// Télécharge et enregistre toutes les catégories ; false si l'une a échoué
  /// (les catégories déjà enregistrées restent à jour, les autres gardent l'ancienne copie).
  Future<bool> syncAll() async {
    final f = fetch;
    if (f == null) {
      _error = 'Serveur non configuré.';
      notifyListeners();
      return false;
    }
    if (_running) return false;
    _running = true;
    _error = null;
    _warnings.clear();
    final t0 = _clock();
    final sw = Stopwatch()..start();
    notifyListeners();
    final errors = <String>[];
    try {
      for (final c in CatalogueCategorie.values) {
        try {
          final rows = await _download(f, c);
          await store.replace(c, rows, _clock());
        } on CatalogueSyncException catch (e) {
          errors.add('${c.label} : ${e.message}');
          if (e.network) break;
        } catch (e) {
          errors.add('${c.label} : $e');
        }
      }
    } finally {
      _running = false;
      _etape = null;
      _done = 0;
      _total = null;
      _lastRun = t0;
      _lastDuration = sw.elapsed;
      _error = errors.isEmpty ? null : errors.join('\n');
      await refreshStats();
    }
    return errors.isEmpty;
  }

  Future<List<Map<String, dynamic>>> _download(CatalogueFetch f, CatalogueCategorie c) async {
    _etape = c.label;
    _done = 0;
    _total = null;
    notifyListeners();
    switch (c) {
      case CatalogueCategorie.produits:
        return _pages(f, c, '/vente/search', {'query': '%'}, 'lgFAMILLEID');
      case CatalogueCategorie.clientsAssurance:
        return _pages(f, c, '/client/all', {'query': '%', 'typeClientId': '1'}, 'lgCLIENTID');
      case CatalogueCategorie.clientsCarnet:
        return _pages(f, c, '/client/all', {'query': '%', 'typeClientId': '2'}, 'lgCLIENTID');
      case CatalogueCategorie.tiersPayantsAssurance:
        return _pages(f, c, '/client/tiers-payants/assurance', {'query': '%'}, 'lgTIERSPAYANTID');
      case CatalogueCategorie.tiersPayantsCarnet:
        return _pages(f, c, '/client/tiers-payants/carnet', {'query': '%'}, 'lgTIERSPAYANTID');
      case CatalogueCategorie.modes:
        // Mêmes appels que l'appli (une seule page).
        final reglements = _data(await f('/common/reglement', {'page': 1, 'start': 0, 'limit': 25}), '/common/reglement');
        final qr = _data(await f('/modereglement/all', {'page': 1, 'start': 0, 'limit': 20}), '/modereglement/all');
        return [
          for (final r in reglements) {...r, '_kind': 'reglement'},
          for (final r in qr) {...r, '_kind': 'qr'},
        ];
    }
  }

  static List<Map<String, dynamic>> _data(Map<String, dynamic> body, String path) {
    final data = body['data'];
    if (data == null) return const [];
    if (data is! List) throw CatalogueSyncException('Réponse inattendue du serveur ($path).');
    return [for (final e in data) if (e is Map) Map<String, dynamic>.from(e)];
  }

  /// Toutes les pages d'une liste (doublons retirés par identifiant). Certaines routes ignorent
  /// start/limit et renvoient tout d'un coup : on s'arrête dès qu'une page n'apporte rien de nouveau.
  Future<List<Map<String, dynamic>>> _pages(CatalogueFetch f, CatalogueCategorie c, String path, Map<String, dynamic> query, String idKey) async {
    final out = <String, Map<String, dynamic>>{};
    var start = 0;
    int? total;
    while (true) {
      final body = await f(path, {...query, 'page': start ~/ pageSize + 1, 'start': start, 'limit': pageSize});
      final items = _data(body, path);
      total = int.tryParse('${body['total'] ?? ''}') ?? total;
      var added = 0;
      for (final e in items) {
        final id = '${e[idKey] ?? ''}';
        if (id.isEmpty || out.containsKey(id)) continue;
        out[id] = e;
        added++;
      }
      _done = out.length;
      _total = total;
      notifyListeners();
      if (items.length < pageSize || added == 0 || (total != null && out.length >= total)) break;
      start += pageSize;
    }
    if (total != null && out.length < total) _warnings.add('${c.label} : ${out.length} reçus sur $total annoncés.');
    return out.values.toList();
  }
}
