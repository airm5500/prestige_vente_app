// lib/providers/quantity_sync.dart
// Suivi des quantités contrôlées envoyées au serveur : chaque envoi attend la réponse ;
// une quantité refusée ou non transmise reste marquée « non enregistrée » jusqu'à un nouvel essai réussi.
import 'package:flutter/foundation.dart';

mixin QuantitySync on ChangeNotifier {
  /// Quantités non enregistrées sur le serveur, par ligne (valeur à renvoyer).
  final Map<String, int> _unsynced = {};

  /// Lignes dont l'envoi est en cours.
  final Set<String> _sending = {};

  bool _retrying = false;

  /// Envois en cours (pour les attendre avant de quitter un écran).
  final Set<Future<bool>> _inFlight = {};

  Map<String, int> get unsyncedQuantities => Map.unmodifiable(_unsynced);
  int get unsyncedCount => _unsynced.length;
  bool isUnsynced(String detailId) => _unsynced.containsKey(detailId);
  bool isSending(String detailId) => _sending.contains(detailId);
  bool get isRetrying => _retrying;

  /// Valeur locale actuelle d'une ligne (pour ignorer la réponse d'un envoi dépassé).
  int? localQuantity(String detailId);

  /// Envoie la quantité et attend la réponse ; `true` si le serveur l'a enregistrée.
  Future<bool> sendQuantity(String detailId, int quantity, Future<bool> Function() post) {
    final f = _send(detailId, quantity, post);
    _inFlight.add(f);
    f.whenComplete(() => _inFlight.remove(f));
    return f;
  }

  /// Attend la fin des envois en cours.
  Future<void> waitForPendingSends() async {
    while (_inFlight.isNotEmpty) {
      await Future.wait(List.of(_inFlight));
    }
  }

  Future<bool> _send(String detailId, int quantity, Future<bool> Function() post) async {
    _sending.add(detailId);
    notifyListeners();
    bool ok;
    try {
      ok = await post();
    } catch (_) {
      ok = false;
    }
    _sending.remove(detailId);
    // Une saisie plus récente sur la même ligne décide de l'état : on ignore une réponse dépassée.
    if (localQuantity(detailId) == quantity) {
      if (ok) {
        _unsynced.remove(detailId);
      } else {
        _unsynced[detailId] = quantity;
      }
    }
    notifyListeners();
    return ok;
  }

  /// Renvoie toutes les quantités non enregistrées ; renvoie le nombre restant en échec.
  Future<int> retryUnsynced(Future<bool> Function(String detailId, int quantity) post) async {
    if (_retrying || _unsynced.isEmpty) return _unsynced.length;
    _retrying = true;
    notifyListeners();
    try {
      for (final e in Map.of(_unsynced).entries) {
        await sendQuantity(e.key, e.value, () => post(e.key, e.value));
      }
    } finally {
      _retrying = false;
      notifyListeners();
    }
    return _unsynced.length;
  }

  void clearUnsynced() {
    _unsynced.clear();
    _sending.clear();
  }
}
