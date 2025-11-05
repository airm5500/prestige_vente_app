// lib/api/models/type_vente.dart
// 02/11/2025 15:20
class TypeVente {
  final String lgTYPEVENTEID;
  final String strNAME;
  final String strDESCRIPTION;

  TypeVente({
    required this.lgTYPEVENTEID,
    required this.strNAME,
    required this.strDESCRIPTION,
  });

  factory TypeVente.fromJson(Map<String, dynamic> json) {
    return TypeVente(
      lgTYPEVENTEID: json['lgTYPEVENTEID'] ?? '',
      strNAME: json['strNAME'] ?? '',
      strDESCRIPTION: json['strDESCRIPTION'] ?? '',
    );
  }
}