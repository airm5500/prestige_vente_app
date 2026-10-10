// lib/horsligne/catalogue_sync.dart
// Mise à jour de la copie locale (hors ligne, étape H1) : téléchargement complet par pages avec
// les MÊMES routes que l'appli (/vente/search « % », /client/all, /client/tiers-payants/…,
// /common/reglement, /modereglement/all). Chaque catégorie est d'abord entièrement téléchargée,
// puis écrite en une transaction : si la synchro échoue au milieu, l'ancienne copie reste utilisable.
// Au démarrage (après connexion) si la copie a plus de 12 h, puis toutes les 30 min quand en ligne.
// Ne ralentit jamais l'appli : une mise à jour AUTOMATIQUE se met en pause avant chaque requête tant que
// l'utilisateur travaille ([ActiviteApp] : requête de l'appli en cours ou récente) et reprend ensuite ;
// la main est rendue entre deux pages ; jamais deux mises à jour à la fois ; la mise à jour manuelle
// est immédiate (elle lève la pause d'une mise à jour automatique en cours et l'attend).
// H5 (serveur avec `catalogueDelta`, voir catalogue_delta.dart) : produits = copie complète une fois par jour,
// sinon seulement les changements (toutes les 5 min en ligne, et dans la mise à jour automatique des 30 min).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:prestige_vente_app/horsligne/activite_app.dart';
import 'package:prestige_vente_app/horsligne/catalogue_delta.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart';

/// Appel GET du serveur : renvoie le corps JSON ; lève [CatalogueSyncException] en cas d'échec.
typedef CatalogueFetch = Future<Map<String, dynamic>> Function(String path, Map<String, dynamic> query);

/// H5 : GET /mobile/capacites (code HTTP et corps, sans lever d'exception pour un 401 / 404).
typedef CatalogueCapacites = Future<({int status, Object? body})> Function();

class CatalogueSyncException implements Exception {
  final String message;

  /// Le serveur n'a pas répondu (inutile d'essayer les catégories suivantes).
  final bool network;
  const CatalogueSyncException(this.message, {this.network = false});
  @override
  String toString() => message;
}

/// Copie complémentaire téléchargée à la suite du catalogue, avec les mêmes déclencheurs
/// (ex. stock hors ligne H3). Doit écrire en une transaction ; lève [CatalogueSyncException] si échec.
abstract class CatalogueExtension {
  String get label;
  Future<void> sync(CatalogueFetch fetch, void Function(String etape, int done, int? total) progress);

  /// « Vider la copie locale ».
  Future<void> clear();
}

class CatalogueSync extends ChangeNotifier {
  final LocalStore store;

  /// Copies complémentaires (téléchargées après les catégories du catalogue).
  final List<CatalogueExtension> extensions = [];
  CatalogueFetch? fetch;

  /// H5 : lecture des capacités du serveur (null : jamais de mise à jour différentielle).
  CatalogueCapacites? capacites;

  /// H5 : adresse du serveur (le curseur des changements ne vaut que pour ce serveur).
  String Function()? serveur;
  final DateTime Function() _clock;

  /// Taille des pages téléchargées.
  final int pageSize;

  /// Attente entre deux vérifications pendant une pause (utilisateur occupé).
  final Duration pause;

  /// L'utilisateur travaille-t-il ? (par défaut : [ActiviteApp.occupee]).
  final bool Function() occupee;

  CatalogueSync({required this.store, this.fetch, DateTime Function()? clock, this.pageSize = 500, this.pause = const Duration(milliseconds: 500), bool Function()? occupee})
      : _clock = clock ?? DateTime.now,
        occupee = occupee ?? (() => ActiviteApp.occupee);

  Future<bool>? _current;
  bool _auto0 = false;
  bool _enPause = false;

  /// Mise à jour automatique en pause (l'utilisateur travaille).
  bool get enPause => _enPause;

  /// Avant chaque requête : rend la main ; en automatique, attend que l'utilisateur ne travaille plus.
  Future<void> _entreRequetes() async {
    await Future<void>.delayed(Duration.zero);
    while (_auto0 && occupee()) {
      if (!_enPause) {
        _enPause = true;
        notifyListeners();
      }
      await Future<void>.delayed(pause);
    }
    if (_enPause) {
      _enPause = false;
      notifyListeners();
    }
  }

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
  Timer? _autoDelta;
  EtatDelta _delta = EtatDelta.vide;

  /// H5 : état de la mise à jour différentielle (curseur, dernière mise à jour, nb de produits modifiés).
  EtatDelta get delta => _delta;
  String get _serveurCle => serveur?.call() ?? '';

  /// H5 : les produits se mettent à jour par changements (copie complète faite avec la capacité, même serveur).
  bool get deltaActif => _delta.actifPour(_serveurCle);

  /// « Dernière mise à jour : il y a 3 min (12 produits modifiés) » (null sans mise à jour différentielle).
  String? get deltaLibelle => deltaActif ? _delta.libelle(_clock()) : null;

  bool get running => _running;

  /// Étape en cours (« Produits », « Clients assurance »…).
  String? get etape => _etape;
  int get done => _done;
  int? get total => _total;

  /// Avancement de l'étape en cours (null si inconnu).
  double? get progress => _total == null || _total == 0 ? null : (_done / _total!).clamp(0, 1).toDouble();

  int? _page;
  int? _nbPages;
  int _etapeNum = 0;
  int _etapesTotal = 0;

  /// Page en cours de l'étape (listes paginées) et nombre de pages annoncé (null si inconnu).
  int? get page => _page;
  int? get pages => _nbPages;

  /// Étape en cours (1…) sur le nombre d'étapes de la mise à jour (catégories + copies complémentaires).
  int get etapeNum => _etapeNum;
  int get etapesTotal => _etapesTotal;

  /// Avancement global de la mise à jour (0 à 1, toujours connu : barre déterminée).
  double get avancementGlobal {
    if (!_running || _etapesTotal == 0) return 0;
    final faites = (_etapeNum - 1).clamp(0, _etapesTotal);
    return ((faites + (progress ?? 0)) / _etapesTotal).clamp(0, 1).toDouble();
  }

  /// « Produits : page 3/20 (1 500 / 10 000) » ; null hors mise à jour.
  String? get progressionLabel {
    if (!_running) return null;
    final e = _etape ?? '…';
    final pg = _page == null ? '' : (_nbPages == null ? ' : page $_page' : ' : page $_page/$_nbPages');
    final n = _total == null ? (_done > 0 ? ' ($_done)' : '') : ' ($_done / $_total)';
    return '$e$pg$n';
  }
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
      _delta = EtatDelta.depuisMeta(await store.metas(CatalogueDelta.prefixe));
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

  /// Synchro si la copie est trop ancienne (démarrage) ; H5 : aussi si la vérification complète du jour manque.
  Future<bool> syncIfStale() async {
    if (!_statsLoaded) await refreshStats();
    if (!isStale() && !(deltaActif && _delta.completDu(_clock()))) return true;
    return syncAll(auto: true);
  }

  /// Synchro automatique toutes les 30 min tant que [online] est vrai (sans rien afficher) ;
  /// H5 : changements des produits toutes les 5 min (seulement si le serveur les propose).
  void startAuto(bool Function() online) {
    _auto?.cancel();
    _auto = Timer.periodic(autoInterval, (_) {
      if (online() && !_running && fetch != null) syncAll(auto: true);
    });
    _autoDelta?.cancel();
    _autoDelta = Timer.periodic(CatalogueDelta.intervalle, (_) {
      if (online() && !_running && fetch != null && deltaActif) syncChangements();
    });
  }

  void stopAuto() {
    _auto?.cancel();
    _auto = null;
    _autoDelta?.cancel();
    _autoDelta = null;
  }

  @override
  void dispose() {
    stopAuto();
    super.dispose();
  }

  /// Télécharge et enregistre toutes les catégories ; false si l'une a échoué
  /// (les catégories déjà enregistrées restent à jour, les autres gardent l'ancienne copie).
  /// [auto] : mise à jour automatique (pause tant que l'utilisateur travaille). Manuelle : immédiate ;
  /// si une mise à jour automatique est en cours, elle continue sans pause et on l'attend.
  Future<bool> syncAll({bool auto = false}) => _lancer(auto: auto);

  /// H5 : produits seulement (changements, ou copie complète si la vérification du jour est due) ;
  /// automatique (pause pendant l'activité). Sans mise à jour différentielle : rien.
  Future<bool> syncChangements() async {
    if (!_statsLoaded) await refreshStats();
    if (!deltaActif) return false;
    return _lancer(auto: true, produitsSeuls: true);
  }

  Future<bool> _lancer({required bool auto, bool produitsSeuls = false}) async {
    final f0 = fetch;
    if (f0 == null) {
      _error = 'Serveur non configuré.';
      notifyListeners();
      return false;
    }
    final cur = _current;
    if (_running && cur != null) {
      if (auto) return false;
      _auto0 = false;
      return cur;
    }
    if (_running) return false;
    _auto0 = auto;
    return _current = _syncAll((p, q) async {
      await _entreRequetes();
      return f0(p, q);
    }, produitsSeuls: produitsSeuls).whenComplete(() {
      _current = null;
      _auto0 = false;
      _enPause = false;
    });
  }

  Future<bool> _syncAll(CatalogueFetch f, {bool produitsSeuls = false}) async {
    _running = true;
    _etapeNum = 0;
    _etapesTotal = produitsSeuls ? 1 : CatalogueCategorie.values.length + extensions.length;
    _error = null;
    _warnings.clear();
    final t0 = _clock();
    final sw = Stopwatch()..start();
    notifyListeners();
    final errors = <String>[];
    var network = false;
    try {
      for (final c in produitsSeuls ? const [CatalogueCategorie.produits] : CatalogueCategorie.values) {
        try {
          if (c == CatalogueCategorie.produits) {
            await _produits(f, complet: !_auto0 && !produitsSeuls);
            continue;
          }
          final rows = await _download(f, c);
          await store.replace(c, rows, _clock());
        } on CatalogueSyncException catch (e) {
          errors.add('${c.label} : ${e.message}');
          if (network = e.network) break;
        } catch (e) {
          errors.add('${c.label} : $e');
        }
      }
      for (final x in network || produitsSeuls ? const <CatalogueExtension>[] : List.of(extensions)) {
        try {
          _etapeNum++;
          _page = null;
          _nbPages = null;
          await x.sync(f, _progress);
        } on CatalogueSyncException catch (e) {
          errors.add('${x.label} : ${e.message}');
          if (e.network) break;
        } catch (e) {
          errors.add('${x.label} : $e');
        }
      }
    } finally {
      _running = false;
      _etape = null;
      _done = 0;
      _total = null;
      _page = null;
      _nbPages = null;
      _etapeNum = 0;
      _lastRun = t0;
      _lastDuration = sw.elapsed;
      _error = errors.isEmpty ? null : errors.join('\n');
      await refreshStats();
    }
    return errors.isEmpty;
  }

  /// Produits. H5 actif et vérification du jour faite : changements seulement (repli sur la copie complète si le
  /// serveur ne les donne plus). Sinon copie complète d'origine ; avec la capacité, le curseur (horloge du serveur
  /// lue AVANT le téléchargement) est écrit dans la même transaction. [complet] : mise à jour manuelle.
  Future<void> _produits(CatalogueFetch f, {bool complet = false}) async {
    const c = CatalogueCategorie.produits;
    if (!complet && deltaActif && !_delta.completDu(_clock())) {
      try {
        await _changements(f);
        return;
      } on CatalogueSyncException catch (e) {
        if (e.network) rethrow;
        _etapeNum--; // repli : la copie complète reprend la même étape
      }
    }
    final cap = await _capaciteDelta();
    final rows = await _download(f, c);
    final now = _clock();
    final Map<String, String?> meta = switch (cap) {
      (ok: true, heure: final String h) => {
          CatalogueDelta.kCurseur: h,
          CatalogueDelta.kServeur: _serveurCle,
          CatalogueDelta.kComplet: now.toIso8601String(),
          CatalogueDelta.kMaj: now.toIso8601String(),
          CatalogueDelta.kN: null,
        },
      // Le serveur n'a pas (ou plus) la capacité : on oublie le curseur.
      (ok: false, heure: _) when _delta.curseur != null || _delta.complet != null => CatalogueDelta.oubli,
      _ => const {},
    };
    await store.replace(c, rows, now, meta: meta);
  }

  /// H5 : capacité et horloge du serveur. ok : true / false si clair, null si indéterminé (ou sans [capacites]).
  Future<({bool? ok, String? heure})> _capaciteDelta() async {
    final lire = capacites;
    if (lire == null) return (ok: null, heure: null);
    try {
      await _entreRequetes();
      final r = await lire();
      final ok = CatalogueDelta.capaciteDepuisReponse(r.status, r.body);
      final body = r.body;
      final h = ok == true && body is Map ? '${body['serveurMaintenant'] ?? ''}' : null;
      if (ok == true && CatalogueDelta.lireHeure(h) == null) return (ok: false, heure: null);
      return (ok: ok, heure: h);
    } catch (_) {
      return (ok: null, heure: null);
    }
  }

  /// H5 : changements depuis le curseur − 2 min, appliqués avec le nouveau curseur en une transaction.
  Future<void> _changements(CatalogueFetch f) async {
    _etapeNum++;
    _page = null;
    _nbPages = null;
    _progress('${CatalogueCategorie.produits.label} (changements)', 0, null);
    final ch = await telechargerChangements(f, _delta.curseur!, pageSize: pageSize, progress: (d, t) {
      // Même affichage que la copie complète : « page 2/3 (1 000 / 1 200) ».
      _page = d == 0 ? 1 : (d + pageSize - 1) ~/ pageSize;
      _nbPages = t == null ? null : (t == 0 ? 1 : (t + pageSize - 1) ~/ pageSize);
      _progress(_etape ?? '', d, t);
    });
    final now = _clock();
    await store.appliquerProduits(ch.upserts, ch.suppressions, now, meta: {
      CatalogueDelta.kCurseur: ch.serveurMaintenant,
      CatalogueDelta.kMaj: now.toIso8601String(),
      CatalogueDelta.kN: '${ch.nombre}',
    });
  }

  void _progress(String etape, int done, int? total) {
    _etape = etape;
    _done = done;
    _total = total;
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> _download(CatalogueFetch f, CatalogueCategorie c) async {
    _etape = c.label;
    _etapeNum++;
    _done = 0;
    _total = null;
    _page = null;
    _nbPages = null;
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
      // Page en cours de téléchargement (« page 3/20 »).
      _page = start ~/ pageSize + 1;
      notifyListeners();
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
      _nbPages = total == null ? null : (total <= 0 ? 1 : (total + pageSize - 1) ~/ pageSize);
      notifyListeners();
      if (items.length < pageSize || added == 0 || (total != null && out.length >= total)) break;
      start += pageSize;
    }
    if (total != null && out.length < total) _warnings.add('${c.label} : ${out.length} reçus sur $total annoncés.');
    return out.values.toList();
  }
}
