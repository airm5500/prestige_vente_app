// lib/api/models/commande.dart
// 16/10/2025 10:00
class Commande {
  final String id;
  final String ref;
  final String grossiste;
  final String date;
  final int nbreProduit;
  final int prixAchatTotal;
  final String statut;

  Commande({
    required this.id,
    required this.ref,
    required this.grossiste,
    required this.date,
    required this.nbreProduit,
    required this.prixAchatTotal,
    required this.statut,
  });

  factory Commande.fromJson(Map<String, dynamic> json) {
    return Commande(
      id: json['lg_ORDER_ID'],
      ref: json['str_REF_ORDER'],
      grossiste: json['str_GROSSISTE_LIBELLE'],
      date: json['dt_CREATED'],
      nbreProduit: json['int_NBRE_PRODUIT'],
      prixAchatTotal: json['PRIX_ACHAT_TOTAL'],
      statut: json['str_STATUT'],
    );
  }
}