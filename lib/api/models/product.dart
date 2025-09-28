// lib/api/models/product.dart
// 28/09/2025 01:40
class ProductSearchResult {
  final String lgFAMILLEID;
  final int intPRICE;
  final int intNUMBERAVAILABLE;
  final String strNAME;
  final String intCIP;

  ProductSearchResult({
    required this.lgFAMILLEID,
    required this.intPRICE,
    required this.intNUMBERAVAILABLE,
    required this.strNAME,
    required this.intCIP,
  });

  factory ProductSearchResult.fromJson(Map<String, dynamic> json) {
    return ProductSearchResult(
      lgFAMILLEID: json['lgFAMILLEID'],
      intPRICE: json['intPRICE'],
      intNUMBERAVAILABLE: json['intNUMBERAVAILABLE'],
      strNAME: json['strNAME'],
      intCIP: json['intCIP'],
    );
  }
}