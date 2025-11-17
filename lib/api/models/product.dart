// lib/api/models/product.dart
// 09/11/2025 21:10 (Ajout intPAF manquant)
class ProductSearchResult {
  final String lgFAMILLEID;
  final String strNAME;
  final String intCIP;
  final int intPRICE;
  final int intNUMBERAVAILABLE;
  final String strLIBELLEE;
  // MODIFICATION : Ajout du champ manquant (Prix d'Achat)
  final int intPAF;

  ProductSearchResult({
    required this.lgFAMILLEID,
    required this.strNAME,
    required this.intCIP,
    required this.intPRICE,
    required this.intNUMBERAVAILABLE,
    required this.strLIBELLEE,
    // MODIFICATION : Ajout au constructeur
    required this.intPAF,
  });

  factory ProductSearchResult.fromJson(Map<String, dynamic> json) {
    return ProductSearchResult(
      lgFAMILLEID: json['lgFAMILLEID'] ?? '',
      strNAME: json['strNAME'] ?? '',
      intCIP: json['intCIP'] ?? '',
      intPRICE: json['intPRICE'] ?? 0,
      intNUMBERAVAILABLE: json['intNUMBERAVAILABLE'] ?? 0,
      strLIBELLEE: json['strLIBELLEE'] ?? '',
      // MODIFICATION : Lecture du champ depuis l'API
      intPAF: json['intPAF'] ?? 0,
    );
  }
}