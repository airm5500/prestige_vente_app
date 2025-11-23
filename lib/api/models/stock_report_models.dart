// lib/api/models/stock_report_models.dart
// 12/11/2025 09:00

class Grossiste {
  final String id;
  final String libelle;

  Grossiste({required this.id, required this.libelle});

  factory Grossiste.fromJson(Map<String, dynamic> json) {
    return Grossiste(
      id: json['id'] ?? '',
      libelle: (json['libelle'] ?? '').trim(),
    );
  }
}

class StockReportItem {
  final String id;
  final String code; // CIP ou Code interne
  final String codeEan;
  final String libelle;
  final int prixVente;
  final int prixAchat;
  final int stock;
  final int stockDetail; // Optionnel selon API
  final String rayonLibelle;
  final String familleLibelle;
  final String grossisteId;
  final String dateInventaire;
  final String dateEntree;
  final String lastDateVente;
  final int seuiRappro;
  final int qteReappro;
  final String tva;

  StockReportItem({
    required this.id,
    required this.code,
    required this.codeEan,
    required this.libelle,
    required this.prixVente,
    required this.prixAchat,
    required this.stock,
    required this.stockDetail,
    required this.rayonLibelle,
    required this.familleLibelle,
    required this.grossisteId,
    required this.dateInventaire,
    required this.dateEntree,
    required this.lastDateVente,
    required this.seuiRappro,
    required this.qteReappro,
    required this.tva,
  });

  factory StockReportItem.fromJson(Map<String, dynamic> json) {
    return StockReportItem(
      id: json['id'] ?? '',
      code: json['code'] ?? '',
      codeEan: json['codeEan'] ?? '',
      libelle: json['libelle'] ?? '',
      prixVente: json['prixVente'] ?? 0,
      prixAchat: json['prixAchat'] ?? 0,
      stock: json['stock'] ?? 0,
      stockDetail: json['stockDetail'] ?? 0,
      rayonLibelle: json['rayonLibelle'] ?? '',
      familleLibelle: json['familleLibelle'] ?? '',
      grossisteId: json['grossisteId'] ?? '',
      dateInventaire: json['dateInventaire'] ?? '',
      dateEntree: json['dateEntree'] ?? '',
      lastDateVente: json['lastDateVente'] ?? '',
      seuiRappro: json['seuiRappro'] ?? 0,
      qteReappro: json['qteReappro'] ?? 0,
      tva: json['tva'] ?? '',
    );
  }
}

// Enum pour les filtres de stock
enum StockFilterType {
  EQUAL,
  LESS,
  GREATER,
  GREATER_EQUAL,
  LESS_EQUAL,
  // STOCK_LESS_THAN_SEUIL // Cas spécial
}