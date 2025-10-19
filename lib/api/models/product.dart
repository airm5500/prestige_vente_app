// lib/api/models/product.dart
// 19/10/2025 01:10
class ProductSearchResult {
  final String lgFAMILLEID;
  final String strNAME;
  final String intCIP;
  final int intPRICE;
  final int intNUMBERAVAILABLE;
  // MODIFICATION : Ajout du champ manquant
  final String strLIBELLEE;

  ProductSearchResult({
    required this.lgFAMILLEID,
    required this.strNAME,
    required this.intCIP,
    required this.intPRICE,
    required this.intNUMBERAVAILABLE,
    // MODIFICATION : Ajout au constructeur
    required this.strLIBELLEE,
  });

  factory ProductSearchResult.fromJson(Map<String, dynamic> json) {
    return ProductSearchResult(
      lgFAMILLEID: json['lgFAMILLEID'] ?? '',
      strNAME: json['strNAME'] ?? '',
      intCIP: json['intCIP'] ?? '',
      intPRICE: json['intPRICE'] ?? 0,
      intNUMBERAVAILABLE: json['intNUMBERAVAILABLE'] ?? 0,
      // MODIFICATION : Lecture du champ depuis l'API
      strLIBELLEE: json['strLIBELLEE'] ?? '',
    );
  }
}