// lib/ventes/core/paiement_multiple.dart
// Paiement en plusieurs modes (2 maximum, limite du serveur) : répartition du net entre les modes.
// La somme des parts doit être EXACTEMENT le net (le serveur ne le vérifie pas) ; le dernier mode
// reçoit le reste ; un même mode une seule fois ; seules les espèces peuvent dépasser leur part
// (monnaie calculée sur la part espèces) ; les autres modes doivent être confirmés (« Reçu »).
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';

/// Monnaie rendue au-delà de laquelle le montant reçu est refusé (erreur de scan).
const int maxMonnaieRendue = 500000;

bool estEspeces(PaymentMethod m) => m.id == '1';

String _f(int v) => '${Constants.formatNumber(v)} F';

/// Un mode de la répartition : [montant] = sa part ; [recu] = montant reçu (espèces) ;
/// [confirme] = case « Reçu » cochée (autres modes).
class ReglementLigne {
  final PaymentMethod method;
  final int montant;
  final int? recu;
  final bool confirme;
  const ReglementLigne(this.method, this.montant, {this.recu, this.confirme = false});

  bool get especes => estEspeces(method);

  /// Monnaie à rendre sur la part espèces (0 si le reçu n'est pas correct).
  int get monnaie => especes && erreur == null ? (recu ?? 0) - montant : 0;

  /// null = ligne prête ; '' = à compléter ; sinon message.
  String? get erreur {
    if (montant <= 0) return 'Saisissez la part de ce mode';
    if (!especes) return confirme ? null : '';
    final r = recu;
    if (r == null) return '';
    if (r < montant) return 'Montant insuffisant : il manque ${_f(montant - r)}';
    if (r - montant > maxMonnaieRendue) return 'Montant aberrant (erreur de scan ?)';
    return null;
  }

  ReglementLigne copyWith({int? montant, int? recu, bool clearRecu = false, bool? confirme}) => ReglementLigne(
        method,
        montant ?? this.montant,
        recu: clearRecu ? null : (recu ?? this.recu),
        confirme: confirme ?? this.confirme,
      );
}

/// Répartition du net entre les modes (état de la page d'encaissement).
class PaiementMultiple {
  final int net;
  final int max;
  final List<ReglementLigne> _lignes = [];

  /// Commence avec un seul mode, qui couvre tout le net.
  PaiementMultiple(this.net, PaymentMethod premier, {this.max = maxReglements}) {
    _lignes.add(ReglementLigne(premier, net));
  }

  List<ReglementLigne> get lignes => List.unmodifiable(_lignes);
  int get total => _lignes.fold(0, (s, l) => s + l.montant);
  int get reste => net - total;
  bool contient(String methodId) => _lignes.any((l) => l.method.id == methodId);

  /// « + Ajouter un mode » : désactivé au maximum de modes ou si tout est réparti entre plusieurs modes.
  bool get peutAjouter => _lignes.length < max && (_lignes.length < 2 || reste > 0);

  /// Ajoute un mode (le dernier reçoit le reste). Au 1ᵉʳ ajout, le nouveau mode reçoit le net
  /// et la part du 1ᵉʳ mode est à saisir. Renvoie un message si refusé.
  String? ajouter(PaymentMethod m) {
    if (contient(m.id)) return '${m.name} est déjà dans les règlements.';
    if (!peutAjouter) return _lignes.length >= max ? '$max modes au maximum.' : 'Plus rien à répartir.';
    if (reste > 0) {
      _lignes.add(ReglementLigne(m, reste));
    } else {
      final last = _lignes.length - 1;
      _lignes[last] = _changer(_lignes[last], 0);
      _lignes.add(ReglementLigne(m, net - total));
    }
    return null;
  }

  /// Ligne dont le montant a changé : confirmation à refaire (le client doit payer le nouveau montant).
  ReglementLigne _changer(ReglementLigne l, int montant) =>
      l.montant == montant ? l : l.copyWith(montant: montant, confirme: false);

  int _somme(Iterable<int> idx) => idx.fold(0, (s, i) => s + _lignes[i].montant);

  /// Modifie la part du mode [i] : jamais au-delà du net ; le dernier mode reçoit le reste.
  /// Renvoie le message de correction si le montant a été corrigé.
  String? modifier(int i, int valeur) {
    if (i < 0 || i >= _lignes.length) return null;
    final last = _lignes.length - 1;
    var v = valeur < 0 ? 0 : valeur;
    String? msg;
    if (i == last) {
      final cap = net - _somme([for (var k = 0; k < last; k++) k]);
      if (v > cap) {
        msg = '${_f(v)} dépasse le reste (${_f(cap)}) : montant corrigé.';
        v = cap;
      }
      _lignes[i] = _changer(_lignes[i], v);
      return msg;
    }
    final cap = net - _somme([for (var k = 0; k < last; k++) if (k != i) k]);
    if (v > cap) {
      msg = '${_f(v)} dépasse le net à répartir (${_f(cap)}) : montant corrigé.';
      v = cap;
    }
    _lignes[i] = _changer(_lignes[i], v);
    _lignes[last] = _changer(_lignes[last], net - _somme([for (var k = 0; k < last; k++) k]));
    return msg;
  }

  /// Retire le mode [i] ; le dernier mode restant reçoit le reste.
  void retirer(int i) {
    if (_lignes.length < 2 || i < 0 || i >= _lignes.length) return;
    _lignes.removeAt(i);
    final last = _lignes.length - 1;
    _lignes[last] = _changer(_lignes[last], net - _somme([for (var k = 0; k < last; k++) k]));
  }

  /// « Tout en <mode> » : un seul mode pour tout le net.
  void toutEn(PaymentMethod m) {
    final keep = _lignes.where((l) => l.method.id == m.id).firstOrNull;
    _lignes
      ..clear()
      ..add(keep == null ? ReglementLigne(m, net) : _changer(keep, net));
  }

  /// « 50 / 50 » entre les deux modes (le dernier reçoit le reste).
  void moitie() {
    if (_lignes.length != 2) return;
    _lignes[0] = _changer(_lignes[0], net ~/ 2);
    _lignes[1] = _changer(_lignes[1], net - net ~/ 2);
  }

  void setRecu(int i, int? recu) {
    if (i < 0 || i >= _lignes.length) return;
    _lignes[i] = _lignes[i].copyWith(recu: recu, clearRecu: recu == null);
  }

  void setConfirme(int i, bool v) {
    if (i < 0 || i >= _lignes.length) return;
    _lignes[i] = _lignes[i].copyWith(confirme: v);
  }

  /// Paiements reçus (espèces correctes, autres modes cochés).
  int get nbRecus => _lignes.where((l) => l.erreur == null).length;

  /// Monnaie à rendre (part espèces seulement).
  int get monnaie => _lignes.fold(0, (s, l) => s + l.monnaie);

  /// Montant reçu du client : somme des parts + surplus espèces.
  int get montantRecu => total + monnaie;

  /// Pourquoi on ne peut pas valider (null = prêt).
  String? get blocage {
    final invalid = reglementsInvalides(reglements, net);
    if (invalid != null) return invalid;
    if (nbRecus < _lignes.length) return 'Paiement non reçu.';
    return null;
  }

  bool get valide => blocage == null;

  /// Mode principal (plus gros montant).
  ReglementLigne get principal => _lignes.reduce((a, b) => b.montant > a.montant ? b : a);

  List<VenteReglement> get reglements => reglementsDe(_lignes);
}

/// Règlements envoyés au serveur (montant reçu indiqué pour les espèces).
List<VenteReglement> reglementsDe(List<ReglementLigne> lignes) => [
      for (final l in lignes) (typeReglementId: l.method.id, montant: l.montant, montantVerse: l.especes ? l.recu : null),
    ];
