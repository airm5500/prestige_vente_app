// lib/horsligne/stock/stock_queue.dart
// File PERSISTANTE des opérations stock saisies hors ligne (survit à un redémarrage : chaque
// changement est écrit tout de suite dans la base locale).
//
// Envoi JAMAIS automatique : [envoyer] est appelé après la confirmation de l'utilisateur, qui peut
// décocher les opérations déjà ressaisies sur le serveur (statut « ressaisie », gardées dans
// l'historique). Une opération à la fois, dans l'ordre de saisie ; un refus du serveur donne une
// ANOMALIE (motif conservé dans le rapport d'anomalies) ; une panne interrompt l'envoi sans rien perdre.
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_models.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_sender.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_store.dart';

/// Bilan d'un envoi.
class StockEnvoiResultat {
  final int envoyees;
  final int anomalies;
  final int ressaisies;
  final int restantes;

  /// Envoi interrompu (serveur injoignable, session expirée) : message à afficher.
  final String? interruption;
  const StockEnvoiResultat({this.envoyees = 0, this.anomalies = 0, this.ressaisies = 0, this.restantes = 0, this.interruption});

  String get resume => [
        if (envoyees > 0) '$envoyees envoyée(s)',
        if (anomalies > 0) '$anomalies anomalie(s)',
        if (ressaisies > 0) '$ressaisies marquée(s) ressaisie(s)',
        if (restantes > 0) '$restantes en attente',
        if (interruption != null) interruption!,
      ].join(' · ');
}

class StockQueue extends ChangeNotifier implements AnomalieSource {
  final StockStore store;
  final DateTime Function() _clock;

  /// Envoi vers le serveur (null : pas de serveur configuré).
  StockServer? server;

  StockQueue({required this.store, this.server, DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  List<StockOp> _ops = [];
  List<Anomalie> _anomalies = [];
  bool _loaded = false;
  bool _sending = false;
  String? _progress;
  String? _error;
  Future<void>? _loading;

  List<StockOp> get ops => List.unmodifiable(_ops);
  List<StockOp> get pending => _ops.where((o) => o.pending).toList();
  int get pendingCount => _ops.where((o) => o.pending).length;
  int get anomaliesNonTraitees => _anomalies.where((a) => !a.traitee).length;
  List<Anomalie> get anomaliesList => List.unmodifiable(_anomalies);
  bool get loaded => _loaded;
  bool get sending => _sending;

  /// « Envoi 2/5 : Réception BL … ».
  String? get progress => _progress;

  /// Avancement de l'envoi (0 à 1), null hors envoi.
  double? get avancement => _avancement;
  double? _avancement;

  /// Base locale illisible.
  String? get error => _error;

  DateTime get now => _clock();

  /// Charge la file depuis la base (une seule fois ; [force] pour relire).
  Future<void> load({bool force = false}) {
    if (_loaded && !force) return Future.value();
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<void> _load() async {
    try {
      _ops = await store.ops();
      _anomalies = await store.anomalies();
      _error = null;
    } catch (e) {
      _error = 'File des opérations illisible : $e';
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save(StockOp op) async {
    op.updatedAt = _clock();
    if (!_ops.any((o) => o.id == op.id)) _ops.add(op);
    await store.saveOp(op);
    notifyListeners();
  }

  /// Opération en attente (rien encore envoyé) de ce type et pour cet objet, à compléter.
  StockOp? _open(StockOpType type, String refId) => _ops
      .where((o) => o.type == type && o.refId == refId && o.pending && o.lines.every((l) => l.etat == StockLineEtat.pending))
      .lastOrNull;

  Future<StockOp> _openOrNew(StockOpType type, String refId, {String reference = '', String grossiste = '', Map<String, dynamic>? meta}) async {
    await load();
    final existing = _open(type, refId);
    if (existing != null) return existing;
    final at = _clock();
    return StockOp(id: StockOp.newId(at), type: type, createdAt: at, refId: refId, reference: reference, grossiste: grossiste, meta: meta);
  }

  String _lineKey(StockOp op) => '${op.id}-${op.lines.length + 1}-${_clock().microsecondsSinceEpoch.toRadixString(36)}';

  static final _iso = DateFormat('yyyy-MM-dd');

  // ---------------------------------------------------------------------------
  // Saisies hors ligne
  // ---------------------------------------------------------------------------

  /// Réception BL : un lot saisi (cumulé dans l'opération du BL).
  Future<StockOp> addReceptionLot({
    required String blId,
    required String blRef,
    String grossiste = '',
    required String detailId,
    String produitId = '',
    required String produit,
    required int qty,
    int ug = 0,
    required String numLot,
    DateTime? expiry,
  }) async {
    final op = await _openOrNew(StockOpType.reception, blId, reference: 'BL $blRef', grossiste: grossiste, meta: {'blRef': blRef});
    op.lines.add(StockOpLine(key: _lineKey(op), label: produit, data: {
      'detailId': detailId,
      'produitId': produitId,
      'qty': qty,
      'ug': ug,
      'numLot': numLot,
      'expiry': expiry == null ? '' : _iso.format(expiry),
    }));
    await _save(op);
    journalStockOp(op, 'lot saisi hors ligne', ligne: op.lines.last);
    return op;
  }

  /// Lots saisis hors ligne (pas encore envoyés) d'une ligne de BL : retirés de la file.
  Future<int> removeReceptionLots(String blId, String detailId) async {
    await load();
    var n = 0;
    for (final op in _ops.where((o) => o.type == StockOpType.reception && o.refId == blId && o.pending).toList()) {
      final before = op.lines.length;
      op.lines.removeWhere((l) => l.etat == StockLineEtat.pending && '${l.data['detailId']}' == detailId);
      n += before - op.lines.length;
      if (before != op.lines.length) journalStockOp(op, 'lots saisis hors ligne retirés (${before - op.lines.length})');
      if (op.lines.isEmpty) {
        await _delete(op);
      } else if (before != op.lines.length) {
        await _save(op);
      }
    }
    return n;
  }

  /// Pointage BL ([commande] false) ou contrôle de commande : quantité posée (la dernière saisie
  /// d'une ligne remplace la précédente). [base] : quantité pointée connue dans la copie locale.
  Future<StockOp> setPointage({
    required bool commande,
    required String refId,
    required String reference,
    String grossiste = '',
    required String detailId,
    required String produit,
    required int qty,
    int? base,
  }) async {
    final type = commande ? StockOpType.pointageCommande : StockOpType.pointageBl;
    final op = await _openOrNew(type, refId, reference: reference, grossiste: grossiste);
    final existing = op.lines.where((l) => '${l.data['detailId']}' == detailId).firstOrNull;
    if (existing != null) {
      existing.data['qty'] = qty;
    } else {
      op.lines.add(StockOpLine(key: _lineKey(op), label: produit, data: {'detailId': detailId, 'qty': qty, 'base': base}));
    }
    await _save(op);
    journalStockOp(op, 'quantité pointée hors ligne', ligne: op.lines.where((l) => '${l.data['detailId']}' == detailId).last);
    return op;
  }

  /// Date de péremption / lot d'un produit (fiche article).
  Future<StockOp> addPeremption({
    required String produitId,
    String cip = '',
    required String produit,
    required String numLot,
    required DateTime date,
    required int qty,
  }) async {
    final op = await _openOrNew(StockOpType.peremption, 'fiche-lots', reference: 'Fiche article');
    op.lines.add(StockOpLine(
        key: _lineKey(op), label: produit, data: {'produitId': produitId, 'cip': cip, 'numLot': numLot, 'date': _iso.format(date), 'qty': qty}));
    await _save(op);
    journalStockOp(op, 'lot / péremption saisi hors ligne', ligne: op.lines.last);
    return op;
  }

  /// Saisie de périmés.
  Future<StockOp> addPerime({
    required String produitId,
    String cip = '',
    required String produit,
    required String lot,
    required String date,
    required int qty,
  }) async {
    final op = await _openOrNew(StockOpType.perime, 'perimes', reference: 'Saisie périmés');
    op.lines.add(StockOpLine(key: _lineKey(op), label: produit, data: {'produitId': produitId, 'cip': cip, 'lot': lot, 'date': date, 'qty': qty}));
    await _save(op);
    journalStockOp(op, 'périmé saisi hors ligne', ligne: op.lines.last);
    return op;
  }

  /// Retire une ligne pas encore envoyée (périmés, retour…) ; supprime l'opération vide.
  Future<bool> removeLine(String lineKey) async {
    await load();
    for (final op in _ops.where((o) => o.pending).toList()) {
      final l = op.lines.where((l) => l.key == lineKey && l.etat == StockLineEtat.pending).firstOrNull;
      if (l == null) continue;
      op.lines.remove(l);
      op.lines.isEmpty ? await _delete(op) : await _save(op);
      journalStockOp(op, 'ligne retirée avant envoi (${l.label})');
      return true;
    }
    return false;
  }

  /// Nouveau retour fournisseur (créé sur le serveur au moment de l'envoi).
  Future<StockOp> createRetour({required String blId, required String blRef, String grossiste = '', String comment = ''}) async {
    await load();
    final at = _clock();
    final id = StockOp.newId(at);
    final marker = '[HL:${id.substring(id.length - 4)}${DateFormat('ddHHmm').format(at)}]';
    final c = comment.trim();
    final room = 50 - marker.length - 1;
    final op = StockOp(id: id, type: StockOpType.retour, createdAt: at, refId: blId, reference: 'BL $blRef', grossiste: grossiste, meta: {
      'blRef': blRef,
      'marker': marker,
      'comment': [if (c.isNotEmpty) c.length > room ? c.substring(0, room) : c, marker].join(' '),
      'commentSaisi': c,
    });
    return op;
  }

  /// Ajoute un produit au retour (Prestige cumule les quantités d'un même produit).
  Future<StockOp> addRetourLine(StockOp op, {required String produitId, required String produit, String cip = '', required String motifId, String motif = '', required int qty}) async {
    final existing = op.lines.where((l) => '${l.data['produitId']}' == produitId && l.etat == StockLineEtat.pending).firstOrNull;
    if (existing != null) {
      existing.data['qty'] = (existing.data['qty'] as num).toInt() + qty;
    } else {
      op.lines.add(StockOpLine(
          key: _lineKey(op), label: produit, data: {'produitId': produitId, 'cip': cip, 'motifId': motifId, 'motif': motif, 'qty': qty}));
    }
    await _save(op);
    journalStockOp(op, 'produit ajouté au retour hors ligne', ligne: StockOpLine(key: '', label: produit, data: {'produitId': produitId, 'qty': qty}));
    return op;
  }

  Future<bool> updateLineQty(String lineKey, int qty) async {
    await load();
    for (final op in _ops.where((o) => o.pending)) {
      final l = op.lines.where((l) => l.key == lineKey && l.etat == StockLineEtat.pending).firstOrNull;
      if (l == null) continue;
      l.data['qty'] = qty;
      await _save(op);
      journalStockOp(op, 'quantité modifiée hors ligne', ligne: StockOpLine(key: l.key, label: l.label, data: {...l.data, 'qty': qty}));
      return true;
    }
    return false;
  }

  /// Emplacement d'un produit (la dernière saisie remplace la précédente).
  Future<StockOp> setEmplacement({required String produitId, required String produit, required String rayonId, String rayon = ''}) async {
    final op = await _openOrNew(StockOpType.emplacement, 'emplacements', reference: 'Emplacements');
    final existing = op.lines.where((l) => '${l.data['produitId']}' == produitId).firstOrNull;
    if (existing != null) op.lines.remove(existing);
    op.lines.add(StockOpLine(key: _lineKey(op), label: produit, data: {'produitId': produitId, 'rayonId': rayonId, 'rayon': rayon}));
    await _save(op);
    journalStockOp(op, 'emplacement saisi hors ligne ($produit → $rayon)');
    return op;
  }

  Future<void> _delete(StockOp op) async {
    _ops.removeWhere((o) => o.id == op.id);
    await store.deleteOp(op.id);
    notifyListeners();
  }

  /// Opération par clé.
  StockOp? byId(String id) => _ops.where((o) => o.id == id).firstOrNull;

  /// Lignes encore à envoyer des opérations en attente d'un type (et d'un objet).
  List<StockOpLine> pendingLines(StockOpType type, {String? refId}) => [
        for (final op in _ops)
          if (op.type == type && op.pending && (refId == null || op.refId == refId))
            for (final l in op.lines)
              if (!l.done && l.etat != StockLineEtat.rejected) l,
      ];

  // ---------------------------------------------------------------------------
  // Envoi (après confirmation)
  // ---------------------------------------------------------------------------

  /// Marque des opérations « non envoyée — ressaisie sur le serveur » (gardées dans l'historique).
  Future<void> marquerRessaisies(Iterable<String> ids) async {
    await load();
    for (final id in ids) {
      final op = byId(id);
      if (op == null || !op.pending) continue;
      op.statut = StockOpStatut.ressaisie;
      op.motif = 'Non envoyée : ressaisie sur le serveur (choix de l\'utilisateur).';
      for (final l in op.toSend) {
        if (l.etat == StockLineEtat.pending) l.etat = StockLineEtat.ignored;
      }
      await _save(op);
      journalStockOp(op, 'non envoyée : ressaisie sur le serveur (décochée)');
    }
  }

  /// Envoie les opérations [selection] (dans l'ordre de saisie), une à la fois ; les opérations
  /// [ressaisies] sont marquées sans envoi. Les autres restent en attente.
  Future<StockEnvoiResultat> envoyer({required Set<String> selection, Set<String> ressaisies = const {}}) async {
    final srv = server;
    if (_sending) return const StockEnvoiResultat(interruption: 'Envoi déjà en cours.');
    // Pris AVANT toute attente : un second appel simultané est refusé (jamais deux envois).
    _sending = true;
    notifyListeners();
    var envoyees = 0, anomalies = 0;
    String? interruption;
    try {
      await load();
      await marquerRessaisies(ressaisies.difference(selection));
      final todo = _ops.where((o) => o.pending && selection.contains(o.id)).toList();
      if (todo.isNotEmpty && srv == null) {
        interruption = 'Serveur non configuré.';
      } else {
        final sender = StockSender(srv!, persist: store.saveOp, clock: _clock);
        for (var i = 0; i < todo.length; i++) {
          final op = todo[i];
          _progress = 'Envoi ${i + 1}/${todo.length} : ${op.type.label}${op.titre.isEmpty ? '' : ' — ${op.titre}'}';
          _avancement = i / todo.length;
          notifyListeners();
          op.sentAt ??= _clock();
          try {
            await sender.apply(op);
          } on StockStopException catch (e) {
            interruption = e.message;
            await _save(op);
            journalStockOp(op, 'envoi interrompu', resultat: ResultatJournal.echecReseau, motif: e.message, source: SourceJournal.fileHL);
            break;
          }
          final rejected = op.lines.where((l) => l.etat == StockLineEtat.rejected).toList();
          if (rejected.isEmpty) {
            op.statut = StockOpStatut.envoyee;
            op.motif = null;
            envoyees++;
            final deja = op.lines.isNotEmpty && op.lines.every((l) => l.etat == StockLineEtat.dejaApplique);
            journalStockOp(op, deja ? 'déjà sur le serveur (rien renvoyé)' : 'envoyée au serveur (${op.lines.length} ligne(s))',
                resultat: deja ? ResultatJournal.dejaApplique : ResultatJournal.ok, source: SourceJournal.fileHL);
          } else {
            op.statut = StockOpStatut.anomalie;
            op.motif = _motif(rejected);
            anomalies++;
            journalStockOp(op, 'refusée par le serveur (${rejected.length} ligne(s))', resultat: ResultatJournal.refus, motif: op.motif ?? '', source: SourceJournal.fileHL);
            await _anomalie(op, rejected);
          }
          await _save(op);
        }
      }
    } finally {
      _sending = false;
      _progress = null;
      _avancement = null;
      notifyListeners();
    }
    return StockEnvoiResultat(
      envoyees: envoyees,
      anomalies: anomalies,
      ressaisies: ressaisies.difference(selection).length,
      restantes: pendingCount,
      interruption: interruption,
    );
  }

  static String _motif(List<StockOpLine> rejected) {
    final motifs = rejected.map((l) => l.motif ?? 'Refusé').toSet();
    return motifs.length == 1 ? motifs.first : '${rejected.length} ligne(s) refusée(s) par le serveur';
  }

  Future<void> _anomalie(StockOp op, List<StockOpLine> rejected) async {
    final a = Anomalie(
      id: 'stock-${op.id}',
      source: 'stock',
      date: _clock(),
      type: op.type.label,
      reference: op.titre.isEmpty ? op.type.label : op.titre,
      motif: _motif(rejected),
      operationId: op.id,
      details: [
        for (final l in rejected) '${l.label}${_detail(op.type, l)} : ${l.motif ?? 'refusé'}',
        if (op.lines.length > rejected.length) '${op.lines.length - rejected.length} autre(s) ligne(s) enregistrée(s).',
      ],
    );
    _anomalies.removeWhere((x) => x.id == a.id);
    _anomalies.insert(0, a);
    await store.saveAnomalie(a);
  }

  static String _detail(StockOpType t, StockOpLine l) {
    final d = l.data;
    return switch (t) {
      StockOpType.reception => ' (${d['qty']}${(d['ug'] ?? 0) != 0 ? ' + ${d['ug']} UG' : ''}, lot ${d['numLot']})',
      StockOpType.peremption || StockOpType.perime => ' (${d['qty']}, lot ${d['numLot'] ?? d['lot']})',
      StockOpType.emplacement => ' (${d['rayon']})',
      _ => ' (${d['qty']})',
    };
  }

  // ---------------------------------------------------------------------------
  // Rapport d'anomalies (API générique, voir [AnomalieSource])
  // ---------------------------------------------------------------------------

  @override
  Future<List<Anomalie>> anomalies() async {
    await load();
    return anomaliesList;
  }

  @override
  Future<void> setTraitee(String id, bool traitee) async {
    final a = _anomalies.where((a) => a.id == id).firstOrNull;
    if (a == null) return;
    a.traitee = traitee;
    await store.saveAnomalie(a);
    notifyListeners();
  }

  /// Purge de l'historique : opérations TERMINÉES (envoyées, ressaisies) antérieures à [avant].
  /// Les opérations en attente ou en anomalie ne sont jamais effacées.
  Future<int> purger(DateTime avant) async {
    await load();
    var n = 0;
    for (final op in _ops.where((o) => o.statut == StockOpStatut.envoyee || o.statut == StockOpStatut.ressaisie).toList()) {
      if (!op.updatedAt.isBefore(avant)) continue;
      try {
        await store.deleteOp(op.id);
        _ops.removeWhere((o) => o.id == op.id);
        n++;
      } catch (_) {}
    }
    if (n > 0) notifyListeners();
    return n;
  }

  /// Nombre de lignes d'une opération (affichage).
  static int nbLignes(StockOp op) => op.lines.length;
}
