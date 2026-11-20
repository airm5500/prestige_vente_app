// lib/ventes/core/taux_affiches.dart
// 5.1.0 — Taux des organismes AFFICHÉS pour une vente (ticket local, récapitulatif de la vente), comme le web.
//
// Retour du pharmacien (20/11/2026) : client à deux organismes, 80 % et 30 % ; le ticket imprimait « 80 % » et
// « 30 % » (110 %). Le web (ticket du serveur, ConversionTicket.clients → CreditLigne.tauxAffiches, depuis le
// 05/11) ne dépasse jamais 100 % : le complémentaire affiche 20 %.
//
// Règle (identique à CreditLigne.tauxAffiches du serveur), dans l'ordre de passage des organismes de la vente :
//  - taux affiché = min(taux, 100 − somme des taux déjà affichés), jamais négatif ;
//  - le DERNIER organisme (s'il y en a plusieurs) dont le total tombe à un ou deux points de 100 % affiche le reste
//    exact (70 % + 29 % → 70 % + 30 %), comme le serveur.
// Seul l'affichage change : les parts (montants) et les taux envoyés au serveur restent ceux du contrat. Les écrans
// de choix du client et du contrat gardent le taux du contrat.

/// Taux affichés, dans l'ordre de [taux] (ordre de passage des organismes).
List<int> tauxAffiches(List<int> taux) {
  final res = <int>[];
  var cumul = 0;
  for (var i = 0; i < taux.length; i++) {
    var t = taux[i] < 0 ? 0 : taux[i];
    final dernier = i == taux.length - 1;
    if (cumul + t > 100 || (dernier && i > 0 && (cumul + t - 100).abs() <= 2)) {
      t = 100 - cumul < 0 ? 0 : 100 - cumul;
    }
    res.add(t);
    cumul += t;
  }
  return res;
}
