// lib/paiements/prevente_payee.dart
// 4.15.0 — Demande 62, point 3b (branche serveur correctif/demande62-1911, fb0a3cc2) : prévente DÉJÀ PAYÉE par mobile
// money (à la borne), pas encore terminée : clôture automatique non demandée (`cloturer:false`) ou refusée (caisse du
// compte de la borne fermée, net modifié). Le comptoir la termine AVEC ce paiement, sans redemander l'argent.
//
// Contrat lu dans le code du serveur (la doc REPONSE_DEMANDE62 dit la même chose) :
//  - GET v1/ventestats/{id} et GET v1/ventestats/preventes (SalesStatsRessource.signalerPaiementsMobile) : pour une
//    prévente encore ouverte avec un paiement `statut = paye` et `cloture = 0`, la vente porte
//    `paiementMobile` {id, venteId, montant, operateur, operateurLibelle, typeReglement, referenceFournisseur, payeLe,
//    statut, …} et `typeReglementAttente` (7 Orange, 8 Moov, 9 MTN, 10 Wave) ; sans paiement, la réponse ne change pas ;
//  - POST v1/vente/cloturer/vno (SalesRessource) : refus `{success:false, paiementMobile:true, msg}` si le mode de
//    l'opérateur ne porte pas EXACTEMENT le montant payé (ClotureComptoir.refus) ; rien n'est écrit ; un complément
//    dans un autre mode reste possible si le net a augmenté ;
//  - assurance (cloturer/assurance) : aucun contrôle côté serveur ; le mobile n'affiche que le bandeau.
//
// RÉTROCOMPATIBILITÉ : un serveur sans la demande 62 n'envoie jamais `paiementMobile` : [PreventePayee.depuisVente]
// renvoie null et rien ne change. Aucun nom de client, numéro ni texte de ticket n'est journalisé ici.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/paiements/paiements_mobile.dart';
import 'package:prestige_vente_app/utils/constants.dart';

class PreventePayee {
  /// Identifiant du paiement (table paiement_mobile).
  final String id;

  /// Code de l'opérateur (orange, moov, mtn, wave).
  final String operateur;

  /// Nom affiché (« Wave », « Orange Money »…), celui du serveur.
  final String operateurLibelle;

  /// Mode de règlement Prestige de l'opérateur (« 10 » pour Wave).
  final String typeReglement;

  /// Montant reçu (F CFA).
  final int montant;

  /// Numéro de la transaction chez le fournisseur (peut être vide).
  final String reference;

  /// Date du paiement telle que le serveur l'envoie (« 2026-11-19 10:42:07.0 »).
  final String payeLe;

  const PreventePayee({
    required this.id,
    required this.operateur,
    required this.operateurLibelle,
    required this.typeReglement,
    required this.montant,
    this.reference = '',
    this.payeLe = '',
  });

  /// Lit `paiementMobile` (et `typeReglementAttente`) d'une vente de GET v1/ventestats/{id} ou d'une ligne de
  /// GET v1/ventestats/preventes. null : champ absent (serveur sans la demande 62, ou vente sans paiement), illisible,
  /// ou montant nul.
  static PreventePayee? depuisVente(Map<dynamic, dynamic>? vente) {
    if (vente == null) return null;
    final pm = vente['paiementMobile'];
    if (pm is! Map) return null;
    String t(Object? v) => v == null || '$v' == 'null' ? '' : '$v'.trim();
    final montant = pm['montant'] is num ? (pm['montant'] as num).toInt() : int.tryParse(t(pm['montant'])) ?? 0;
    if (montant <= 0) return null;
    final operateur = t(pm['operateur']).toLowerCase();
    var type = t(vente['typeReglementAttente']);
    if (type.isEmpty) type = t(pm['typeReglement']);
    if (type.isEmpty) type = typeReglementOperateur[operateur] ?? '';
    if (type.isEmpty) return null; // mode inconnu : rien à imposer
    final libelle = t(pm['operateurLibelle']);
    return PreventePayee(
      id: t(pm['id']),
      operateur: operateur,
      operateurLibelle: libelle.isNotEmpty ? libelle : (nomOperateur[operateur] ?? 'mobile money'),
      typeReglement: type,
      montant: montant,
      reference: t(pm['referenceFournisseur']),
      payeLe: t(pm['payeLe']),
    );
  }

  static String _f(int v) => '${Constants.formatNumber(v)} F';

  /// Date courte du paiement (« 19/11/2026 10:42 ») ; texte du serveur (16 caractères) s'il est illisible.
  String get dateCourte {
    final d = DateTime.tryParse(payeLe.replaceFirst(' ', 'T'));
    if (d != null) return DateFormat('dd/MM/yyyy HH:mm').format(d);
    return payeLe.length > 16 ? payeLe.substring(0, 16) : payeLe;
  }

  /// Bandeau, comme le web : « Déjà payée par Wave : 4 125 F · n° … · date ».
  String get bandeau => 'Déjà payée par $operateurLibelle : ${_f(montant)}'
      '${reference.isEmpty ? '' : ' · n° $reference'}'
      '${dateCourte.isEmpty ? '' : ' · $dateCourte'}';

  /// Consigne sous le bandeau, selon le net actuel de la vente.
  String consigne(int net) {
    if (net == montant) return 'Ne rien encaisser : « Terminer la vente » la termine avec ce paiement.';
    if (net > montant) {
      return 'Le net de la vente (${_f(net)}) a augmenté depuis le paiement : le mode $operateurLibelle porte '
          '${_f(montant)}, le complément (${_f(net - montant)}) dans un autre mode.';
    }
    return 'Le net de la vente (${_f(net)}) est inférieur au montant payé (${_f(montant)}) : la vente ne peut pas être '
        'terminée avec ce paiement. Remettez le panier au montant payé, ou voyez le responsable.';
  }

  /// Colonne / badge des listes de préventes, comme le web : « Payée Wave 4 125 F ».
  String get colonne => 'Payée $operateurLibelle ${_f(montant)}';
}

/// Bandeau « Déjà payée par … » (écran de vente, encaissement). [net] : net actuel de la vente (null : inconnu).
class PreventePayeeBandeau extends StatelessWidget {
  final PreventePayee payee;
  final int? net;
  const PreventePayeeBandeau({super.key, required this.payee, this.net});

  @override
  Widget build(BuildContext context) {
    final n = net;
    final ecart = n != null && n != payee.montant;
    final fond = ecart ? const Color(0xFFFFF4E0) : const Color(0xFFE3F6EF);
    final bord = ecart ? const Color(0xFFD97F06) : const Color(0xFF17795F);
    final texte = ecart ? const Color(0xFF6B3D00) : const Color(0xFF0F4F3C);
    return Container(
      key: const ValueKey('prevente-payee-bandeau'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: bord, width: 1.5),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(ecart ? Icons.warning_amber_rounded : Icons.verified, color: bord, size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(payee.bandeau, key: const ValueKey('prevente-payee-texte'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: texte)),
            if (n != null) ...[
              const SizedBox(height: 2),
              Text(payee.consigne(n), key: const ValueKey('prevente-payee-consigne'), style: TextStyle(fontSize: 13, color: texte)),
            ],
          ]),
        ),
      ]),
    );
  }
}
