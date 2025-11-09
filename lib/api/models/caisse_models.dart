// lib/api/models/caisse_models.dart
// 09/11/2025 01:30

// Modèle pour: GET /billetage/ouventure-data
class OuvertureData {
  final String userFullName;
  final String userId;
  final int amount; // Fond de caisse initial
  final bool inUse;  // true si la caisse est déjà ouverte
  final String createAt;

  OuvertureData({
    required this.userFullName,
    required this.userId,
    required this.amount,
    required this.inUse,
    required this.createAt,
  });

  factory OuvertureData.fromJson(Map<String, dynamic> json) {
    return OuvertureData(
      userFullName: json['userFullName'] ?? '',
      userId: json['userId'] ?? '',
      amount: json['amount'] ?? 0,
      inUse: json['inUse'] ?? false,
      createAt: json['createAt'] ?? '',
    );
  }
}

// Modèle pour: GET /billetage/cloture-data
class ClotureData {
  final int totalAmount;
  final int cashFund; // Fond de caisse
  final int solde; // Solde théorique
  final String userFullName;
  final String userId;
  final String resumeCaisseId;
  final String caisseId;
  final String createAt;
  final String updateAt;

  ClotureData({
    required this.totalAmount,
    required this.cashFund,
    required this.solde,
    required this.userFullName,
    required this.userId,
    required this.resumeCaisseId,
    required this.caisseId,
    required this.createAt,
    required this.updateAt,
  });

  factory ClotureData.fromJson(Map<String, dynamic> json) {
    return ClotureData(
      totalAmount: json['totalAmount'] ?? 0,
      cashFund: json['cashFund'] ?? 0,
      solde: json['solde'] ?? 0,
      userFullName: json['userFullName'] ?? '',
      userId: json['userId'] ?? '',
      resumeCaisseId: json['resumeCaisseId'] ?? '',
      caisseId: json['caisseId'] ?? '',
      createAt: json['createAt'] ?? '',
      updateAt: json['updateAt'] ?? '',
    );
  }
}