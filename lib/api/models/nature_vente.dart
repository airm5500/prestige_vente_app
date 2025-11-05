// lib/api/models/nature_vente.dart
// 02/11/2025 15:20
class NatureVente {
  final String lgNATUREVENTEID;
  final String strLIBELLE;

  NatureVente({
    required this.lgNATUREVENTEID,
    required this.strLIBELLE,
  });

  factory NatureVente.fromJson(Map<String, dynamic> json) {
    return NatureVente(
      lgNATUREVENTEID: json['lgNATUREVENTEID'] ?? '',
      strLIBELLE: json['strLIBELLE'] ?? '',
    );
  }
}