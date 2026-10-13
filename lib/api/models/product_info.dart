// lib/api/models/product_info.dart
// 20/10/2025 10:00
import 'package:prestige_vente_app/api/models/stock_reserve.dart';

class ProductInfo {
  final String codeCip;
  final String emplacement;
  final String grossiste;
  final String libelle;
  final double moyenne;
  final double prixAchat;
  final double prixVente;
  final String produitId;
  final int stock;

  // Stock réserve (null : produit non géré en réserve, ou serveur ancien sans ces champs)
  final int? stockReserve;
  final int? seuilReserve;
  final int? seuilMiniRayon;

  ProductInfo({
    required this.codeCip,
    required this.emplacement,
    required this.grossiste,
    required this.libelle,
    required this.moyenne,
    required this.prixAchat,
    required this.prixVente,
    required this.produitId,
    required this.stock,
    this.stockReserve,
    this.seuilReserve,
    this.seuilMiniRayon,
  });

  /// Stock réserve et seuils (affichage, alerte de réapprovisionnement).
  StockReserve get reserve => StockReserve(stockReserve: stockReserve, seuilReserve: seuilReserve, seuilMiniRayon: seuilMiniRayon);

  factory ProductInfo.fromJson(Map<String, dynamic> json) {
    // Helper pour parser les nombres (int ou double)
    double toDouble(dynamic val) {
      if (val is int) return val.toDouble();
      if (val is String) return double.tryParse(val) ?? 0.0;
      return val ?? 0.0;
    }

    return ProductInfo(
      codeCip: json['codeCip']?.toString() ?? '',
      emplacement: json['emplacement']?.toString() ?? '',
      grossiste: json['grossiste']?.toString() ?? '',
      libelle: json['libelle']?.toString() ?? '',
      moyenne: toDouble(json['moyenne']),
      prixAchat: toDouble(json['prixAchat']),
      prixVente: toDouble(json['prixVente']),
      produitId: json['produitId']?.toString() ?? '',
      stock: json['stock'] ?? 0,
      // Lecture tolérante : absent, null, nombre, texte numérique, décimal.
      stockReserve: entierTolerant(json['stockReserve']),
      seuilReserve: entierTolerant(json['seuilReserve']),
      seuilMiniRayon: entierTolerant(json['seuilMiniRayon']),
    );
  }
}