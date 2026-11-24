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

  /// 4.5.1 : code d'un refus de DROIT (HTTP 403 `interdit`) : rien n'a été enregistré, ne pas réessayer.
  static const codeInterdit = 'interdit';

  /// Droit manquant (le compte n'a pas le droit de cette action).
  bool get interdit => code == codeInterdit;

  /// 5.5.0 (transmission du 24/11/2026) : HTTP 423 `horlogeBloquee` — l'heure du serveur est fausse, il refuse toute
  /// écriture sans rien exécuter. Message du serveur affiché tel quel ; pas de relance ; une vente en FILE n'est
  /// jamais mise « à vérifier » : elle reste en attente et repart après le déblocage (même X-Client-Ref).
  static const codeHorloge = 'horlogeBloquee';

  /// Écriture refusée : heure du serveur fausse.
  bool get horlogeBloquee => code == codeHorloge;

  /// 4.15.0 (demande 62) : code d'un refus de clôture d'une prévente déjà payée par mobile money
  /// (`{success:false, paiementMobile:true, msg}`) : message du serveur affiché tel quel, vente gardée.
  static const codePaiementMobile = 'paiementMobile';

  /// Refus de clôture : prévente déjà payée par mobile money, à terminer avec ce paiement.
  bool get paiementMobile => code == codePaiementMobile;

  /// 4.15.2 (demande 64) : panier VERROUILLÉ par un paiement mobile money payé (« Cette prévente est déjà payée par
  /// Wave (4125 F) : le panier ne peut plus être modifié… ») ou en cours (« … : le panier ne peut pas être modifié
  /// pendant le paiement. »), `{success:false, msg}` : rien n'a été écrit ; message affiché tel quel, panier relu.
  bool get panierVerrouille => message.toLowerCase().contains('le panier ne peut');

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
