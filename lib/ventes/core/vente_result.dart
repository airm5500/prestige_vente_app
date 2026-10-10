// lib/ventes/core/vente_result.dart
// Résultat d'un appel serveur des ventes : réussi, refusé par le serveur (avec SON message),
// ou en échec réseau (avec l'indication « peut-être appliqué » pour ne jamais renvoyer à l'aveugle).

sealed class VenteResult<T> {
  const VenteResult();

  bool get isOk => this is VenteOk<T>;
  T? get valueOrNull => switch (this) { VenteOk<T>(:final value) => value, _ => null };

  /// Message à afficher (null si réussi).
  String? get message => switch (this) {
        VenteOk<T>() => null,
        VenteRefused<T>(:final message) => message,
        VenteFailed<T>(:final message) => message,
      };

  /// L'opération a pu être appliquée côté serveur malgré l'échec (réponse perdue) :
  /// relire l'état avant de proposer « Réessayer ».
  bool get uncertain => this is VenteFailed<T> && (this as VenteFailed<T>).maybeApplied;

  VenteResult<R> map<R>(R Function(T value) f) => switch (this) {
        VenteOk<T>(:final value) => VenteOk<R>(f(value)),
        VenteRefused<T>(:final message, :final code) => VenteRefused<R>(message, code: code),
        VenteFailed<T>(:final message, :final maybeApplied) => VenteFailed<R>(message, maybeApplied: maybeApplied),
      };
}

class VenteOk<T> extends VenteResult<T> {
  final T value;
  const VenteOk(this.value);
}

/// Le serveur a répondu et refusé (plafond, bon déjà utilisé, caisse fermée…).
class VenteRefused<T> extends VenteResult<T> {
  final String message;
  final String? code;
  const VenteRefused(this.message, {this.code});

  /// Caisse fermée (message du serveur Prestige).
  bool get caisseFermee => message.toLowerCase().contains('caisse est ferm');

  /// Vente déjà clôturée (le serveur protège contre la double clôture).
  bool get dejaCloturee {
    final m = message.toLowerCase();
    return m.contains('déjà clôtur') || m.contains('deja clotur') || m.contains('déjà été clôtur') || (code ?? '').toLowerCase().contains('cloture');
  }
}

/// Pas de réponse exploitable (réseau, délai, session, réponse illisible).
class VenteFailed<T> extends VenteResult<T> {
  final String message;

  /// true si la requête a pu atteindre le serveur (délai de réponse dépassé, connexion coupée en cours).
  final bool maybeApplied;
  const VenteFailed(this.message, {this.maybeApplied = false});
}
