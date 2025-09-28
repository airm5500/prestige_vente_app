// lib/api/models/product_stats.dart
// 28/09/2025 02:20

// Modèle pour les données de vente annuelle d'un produit
class ProductAnnualSale {
  final String id;
  final String libelle;
  final String codeCip;
  final Map<String, int> monthlySales; // "janvier": 23, "fevrier": 18, etc.

  ProductAnnualSale({
    required this.id,
    required this.libelle,
    required this.codeCip,
    required this.monthlySales,
  });

  factory ProductAnnualSale.fromJson(Map<String, dynamic> json) {
    const months = [
      'janvier', 'fevrier', 'mars', 'avril', 'mai', 'juin',
      'juillet', 'aout', 'septembre', 'octobre', 'novembre', 'decembre'
    ];
    Map<String, int> sales = {};
    for (var month in months) {
      sales[month] = json[month] ?? 0;
    }

    return ProductAnnualSale(
      id: json['id'] ?? '',
      libelle: json['libelle'] ?? '',
      codeCip: json['codeCip'] ?? '',
      monthlySales: sales,
    );
  }
}

// Modèle pour les informations détaillées d'un produit
class ProductInfo {
  final String? prixAchat;
  final String? prixVente;
  final String? grossiste;
  final String? emplacement;
  // Ajoutez d'autres champs si l'API /info les renvoie

  ProductInfo({
    this.prixAchat,
    this.prixVente,
    this.grossiste,
    this.emplacement,
  });

  factory ProductInfo.fromJson(Map<String, dynamic> json) {
    // Note: La structure de cette réponse API n'était pas fournie.
    // J'adapte aux noms de champs les plus probables.
    return ProductInfo(
      prixAchat: json['prixAchat']?.toString(),
      prixVente: json['prixVente']?.toString(),
      grossiste: json['grossiste']?.toString(),
      emplacement: json['emplacement']?.toString(),
    );
  }
}