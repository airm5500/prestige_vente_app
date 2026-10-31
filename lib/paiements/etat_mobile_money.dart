// lib/paiements/etat_mobile_money.dart
// 4.10.2 — retour du pharmacien du 31/10 : « quand je coche "proposer paiement par Mobile Money" je ne vois pas [le
// choix] à la fin de la prévente ou vente ». Le paiement mobile money (QR du montant exact, agrégateur) n'est proposé
// que si TOUTES les conditions de la borne / de l'encaissement sont réunies ; cette ligne d'état dit laquelle manque,
// sous l'option (écrans d'administration seulement, jamais sur l'écran client de la borne) :
//   1. réglage coché sur cet appareil ;
//   2. serveur joignable ;
//   3. GET v1/paiements-mobile/capacites : module présent (404 = serveur ancien) et au moins un opérateur (liste vide =
//      aucun compte de paiement configuré sur le serveur : variables PRESTIGE_PAIEMENTS_* + redémarrage) ;
//   4. droit de clôture du compte qui paie (borne : l'utilisateur borne ; règle 4.5.1) : P_SM_CLOTURER_CAISSE,
//      P_SM_DEPOT_EXTENSION ou P_BT_MODIFICATION_DE_VENTE ; droits inconnus (serveur ancien) : pas d'obstacle.
// Les capacités sont relues à chaque vérification (jamais seulement au démarrage).
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/droits/droits_vente.dart';
import 'package:prestige_vente_app/paiements/paiements_mobile.dart';
import 'package:prestige_vente_app/serveur/panne_serveur.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';

enum EtatMobileMoney { desactive, horsLigne, serveurAncien, sansCompte, sansDroit, propose, erreur }

class DiagnosticMobileMoney {
  final EtatMobileMoney etat;

  /// Opérateurs annoncés par le serveur (codes : orange, wave…).
  final List<String> operateurs;

  /// Compte qui paie (borne : utilisateur borne) ; nommé dans le message « sans droit ».
  final String compte;

  /// Le compte est celui de la borne (formulation du message).
  final bool borne;

  /// Autre obstacle constaté en même temps (droit manquant quand le serveur n'a pas non plus de compte de paiement).
  final bool droitManquantAussi;

  /// Détail d'une erreur inattendue (code HTTP…).
  final String detail;

  const DiagnosticMobileMoney(this.etat,
      {this.operateurs = const [], this.compte = '', this.borne = true, this.droitManquantAussi = false, this.detail = ''});

  bool get propose => etat == EtatMobileMoney.propose;

  static const messageDesactive = 'Désactivé : le client paie à la caisse (ticket de prévente).';
  static const messageHorsLigne = 'Serveur injoignable : impossible de vérifier.';
  static const messageServeurAncien = 'Serveur sans module Mobile Money (version ancienne).';
  static const messageSansCompte = 'Mobile Money activé, mais le serveur Prestige n\'a pas de compte de paiement configuré '
      '(agrégateur). Les modes Wave / Orange de la caisse ne suffisent pas : faites configurer le compte de paiement du '
      'serveur, puis redémarrez-le.';

  String get _messageSansDroit => 'Mobile Money activé, mais le compte ${borne ? 'de la borne ' : ''}« $compte » n\'a pas le droit de '
      'clôturer : donnez-lui P_SM_CLOTURER_CAISSE (ou P_SM_DEPOT_EXTENSION, P_BT_MODIFICATION_DE_VENTE).';

  /// Ligne d'état affichée sous l'option (écrans d'administration).
  String get message => switch (etat) {
        EtatMobileMoney.desactive => messageDesactive,
        EtatMobileMoney.horsLigne => messageHorsLigne,
        EtatMobileMoney.serveurAncien => messageServeurAncien,
        EtatMobileMoney.sansCompte => droitManquantAussi ? '$messageSansCompte\n$_messageSansDroit' : messageSansCompte,
        EtatMobileMoney.sansDroit => _messageSansDroit,
        EtatMobileMoney.propose => 'Proposé au client : ${operateurs.map((o) => nomOperateur[o] ?? o).join(', ')}.',
        EtatMobileMoney.erreur => 'Vérification impossible${detail.isEmpty ? '' : ' : ${detail.endsWith('.') ? detail.substring(0, detail.length - 1) : detail}'}.',
      };
}

/// Diagnostic à partir des mêmes conditions que la borne et l'encaissement. [capacites] : GET
/// v1/paiements-mobile/capacites relu maintenant ; [droits] : droits du compte qui paie (null : inconnus, serveur
/// sans GET v1/user/droits) ; non appelés si l'option est décochée.
Future<DiagnosticMobileMoney> diagnostiquerMobileMoney({
  required bool actif,
  required bool horsLigne,
  required Future<VenteResult<CapacitesPM>> Function() capacites,
  required Future<Set<String>?> Function() droits,
  required String compte,
  bool borne = true,
}) async {
  if (!actif) return const DiagnosticMobileMoney(EtatMobileMoney.desactive);
  if (horsLigne) return const DiagnosticMobileMoney(EtatMobileMoney.horsLigne);
  final r = await capacites();
  final List<String> ops;
  switch (r) {
    case VenteOk(:final value):
      ops = value.operateurs;
    case VenteRefused(:final code) when code == '404':
      return const DiagnosticMobileMoney(EtatMobileMoney.serveurAncien);
    case VenteFailed(:final message) when _reseau(message):
      return const DiagnosticMobileMoney(EtatMobileMoney.horsLigne);
    default:
      return DiagnosticMobileMoney(EtatMobileMoney.erreur, detail: r.message ?? '');
  }
  Set<String>? d;
  try {
    d = await droits();
  } catch (_) {
    d = null;
  }
  final droit = d == null || d.any(DroitsVente.terminerVenteDroits.contains);
  if (ops.isEmpty) {
    return DiagnosticMobileMoney(EtatMobileMoney.sansCompte, compte: compte, borne: borne, droitManquantAussi: !droit);
  }
  if (!droit) return DiagnosticMobileMoney(EtatMobileMoney.sansDroit, operateurs: ops, compte: compte, borne: borne);
  return DiagnosticMobileMoney(EtatMobileMoney.propose, operateurs: ops, compte: compte, borne: borne);
}

bool _reseau(String? m) {
  final t = (m ?? '').toLowerCase();
  return t.contains('injoignable') || t.contains(MessagesServeur.indisponible.toLowerCase());
}

/// Ligne d'état (écrans d'administration : Réglages › Paiements, assistant et administration de PrestigePOS) :
/// pictogramme, [titre] en gras, message. Le texte porte [cle] (tests).
class LigneEtatMobileMoney extends StatelessWidget {
  final String titre;
  final DiagnosticMobileMoney d;
  final String cle;
  final EdgeInsets padding;
  const LigneEtatMobileMoney({super.key, required this.titre, required this.d, required this.cle, this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 10)});

  @override
  Widget build(BuildContext context) {
    final neutre = d.etat == EtatMobileMoney.desactive;
    return Padding(
      padding: padding,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(d.propose ? Icons.check_circle : (neutre ? Icons.remove_circle_outline : Icons.info),
            size: 20, color: d.propose ? Pal.green : (neutre ? Pal.muted : const Color(0xFFB45309))),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              if (titre.isNotEmpty) TextSpan(text: '$titre : ', style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: d.message),
            ]),
            key: ValueKey(cle),
            style: const TextStyle(fontSize: 13.5, color: Pal.ink),
          ),
        ),
      ]),
    );
  }
}
