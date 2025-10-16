// lib/api/models/commande.dart
// 16/10/2025 10:55
class Commande {
  final String id;
  final String ref;
  final String grossiste;
  final String date;
  final int nbreProduit;
  final int prixAchatTotal;
  final String statut;
  // MODIFICATION : Ajout du champ 'checked'
  final bool isChecked;

  Commande({
    required this.id,
    required this.ref,
    required this.grossiste,
    required this.date,
    required this.nbreProduit,
    required this.prixAchatTotal,
    required this.statut,
    required this.isChecked,
  });

  factory Commande.fromJson(Map<String, dynamic> json) {
    return Commande(
      id: json['lg_ORDER_ID'] ?? '',
      ref: json['str_REF_ORDER'] ?? '',
      grossiste: json['str_GROSSISTE_LIBELLE'] ?? '',
      date: json['dt_CREATED'] ?? '',
      nbreProduit: json['int_NBRE_PRODUIT'] ?? 0,
      prixAchatTotal: json['PRIX_ACHAT_TOTAL'] ?? 0,
      statut: json['str_STATUT'] ?? '',
      // MODIFICATION : Lecture du champ 'checked'
      isChecked: json['checked'] ?? false,
    );
  }
}