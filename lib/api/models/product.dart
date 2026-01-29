// lib/api/models/product.dart
class ProductSearchResult {
  final String lgFAMILLEID;
  final String strNAME;
  final String intCIP;
  final int intPRICE;
  final int intNUMBERAVAILABLE;
  final String strLIBELLEE;
  final int intPAF;

  // AJOUTS NON-BLOQUANTS (Pour Vente Dépôt)
  final String strDESCRIPTION;
  final bool boolDECONDITIONNE;
  final String lgFAMILLEPARENTID;

  ProductSearchResult({
    required this.lgFAMILLEID,
    required this.strNAME,
    required this.intCIP,
    required this.intPRICE,
    required this.intNUMBERAVAILABLE,
    required this.strLIBELLEE,
    required this.intPAF,
    // Initialisation par défaut pour ne pas casser les autres fichiers
    this.strDESCRIPTION = '',
    this.boolDECONDITIONNE = false,
    this.lgFAMILLEPARENTID = '',
  });

  factory ProductSearchResult.fromJson(Map<String, dynamic> json) {
    return ProductSearchResult(
      lgFAMILLEID: json['lgFAMILLEID'] ?? '',
      strNAME: json['strNAME'] ?? '',
      intCIP: json['intCIP'] ?? '',
      intPRICE: (json['intPRICE'] as num?)?.toInt() ?? 0, // Cast sécurisé
      intNUMBERAVAILABLE: (json['intNUMBERAVAILABLE'] as num?)?.toInt() ?? 0,
      strLIBELLEE: json['strLIBELLEE'] ?? '',
      intPAF: (json['intPAF'] as num?)?.toInt() ?? 0,

      // Nouveaux champs avec valeurs par défaut
      strDESCRIPTION: json['strDESCRIPTION'] ?? '',
      boolDECONDITIONNE: json['boolDECONDITIONNE'] == true || json['boolDECONDITIONNE'] == 1 || json['boolDECONDITIONNE'] == "1",
      lgFAMILLEPARENTID: json['lgFAMILLEPARENTID'] ?? '',
    );
  }
}