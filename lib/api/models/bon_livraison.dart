// lib/api/models/bon_livraison.dart
// 18/10/2025 15:56
class BonLivraison {
  final String id;
  final String ref;
  final String grossiste;
  final String date;
  final int nbreLignes;
  final int montantTotal;
  final String statutTraitement;
  final String strStatut; // Le champ pour le filtre

  BonLivraison({
    required this.id,
    required this.ref,
    required this.grossiste,
    required this.date,
    required this.nbreLignes,
    required this.montantTotal,
    required this.statutTraitement,
    required this.strStatut,
  });

  factory BonLivraison.fromJson(Map<String, dynamic> json) {
    return BonLivraison(
      id: json['lg_BON_LIVRAISON_ID'] ?? '',
      ref: json['str_REF_LIVRAISON'] ?? '',
      grossiste: json['str_GROSSISTE_LIBELLE'] ?? '',
      date: json['dt_DATE_LIVRAISON'] ?? '',
      nbreLignes: json['int_NBRE_LIGNE_BL_DETAIL'] ?? 0,
      montantTotal: json['PRIX_ACHAT_TOTAL'] ?? 0,
      statutTraitement: json['statutTraitement'] ?? 'A_FAIRE',
      strStatut: json['str_STATUT'] ?? '',
    );
  }
}