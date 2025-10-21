// lib/api/models/product_stats.dart
// 20/10/2025 10:10
class ProductAnnualSale {
  final String id;
  final String libelle;
  final String codeCip;
  final Map<String, int> monthlySales;

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

// L'ancienne classe ProductInfo en double a été supprimée de ce fichier.