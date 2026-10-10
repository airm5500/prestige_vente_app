// lib/api/models/stock_report_models.dart
// 12/11/2025 09:00

// Lecture défensive des champs serveur (null, nombre en texte, décimal…).
String _str(dynamic v) => v == null ? '' : v.toString();
int _int(dynamic v) => v is num ? v.toInt() : (num.tryParse(_str(v).trim())?.toInt() ?? 0);

class Grossiste {
  final String id;
  final String libelle;

  Grossiste({required this.id, required this.libelle});

  factory Grossiste.fromJson(Map<String, dynamic> json) {
    return Grossiste(
      id: _str(json['id']),
      libelle: _str(json['libelle']).trim(),
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
      id: _str(json['id']),
      code: _str(json['code']),
      codeEan: _str(json['codeEan']),
      libelle: _str(json['libelle']),
      prixVente: _int(json['prixVente']),
      prixAchat: _int(json['prixAchat']),
      stock: _int(json['stock']),
      stockDetail: _int(json['stockDetail']),
      rayonLibelle: _str(json['rayonLibelle']),
      familleLibelle: _str(json['familleLibelle']),
      grossisteId: _str(json['grossisteId']),
      dateInventaire: _str(json['dateInventaire']),
      dateEntree: _str(json['dateEntree']),
      lastDateVente: _str(json['lastDateVente']),
      seuiRappro: _int(json['seuiRappro']),
      qteReappro: _int(json['qteReappro']),
      tva: _str(json['tva']),
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
