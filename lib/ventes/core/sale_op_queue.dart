// lib/ventes/core/sale_op_queue.dart
// File d'opérations d'une vente : une seule opération à la fois (ajout, modification,
// suppression, calcul, clôture). Le 2ᵉ scan du 1ᵉʳ produit attend donc que la vente
// soit créée : jamais deux ventes pour un même panier, jamais deux clôtures.
import 'dart:async';

class SaleOpQueue {
  Future<void> _tail = Future.value();
  int _pending = 0;

  /// Nombre d'opérations en cours ou en attente.
  int get pending => _pending;
  bool get busy => _pending > 0;

  /// Exécute [op] après toutes les opérations déjà demandées.
  Future<T> run<T>(Future<T> Function() op) {
    _pending++;
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await op());
      } catch (e, st) {
        completer.completeError(e, st);
      } finally {
        _pending--;
      }
    });
    return completer.future;
  }

  /// Attend la fin de toutes les opérations demandées.
  Future<void> idle() => run(() async {});
}
