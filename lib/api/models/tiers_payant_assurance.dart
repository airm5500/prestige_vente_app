// lib/api/models/tiers_payant_assurance.dart
// 02/11/2025 15:20
// Modèle pour GET /client/tiers-payants/assurance
class TiersPayantAssurance {
  final String lgTIERSPAYANTID;
  final String strFULLNAME;
  final String strNAME;

  TiersPayantAssurance({
    required this.lgTIERSPAYANTID,
    required this.strFULLNAME,
    required this.strNAME,
  });

  factory TiersPayantAssurance.fromJson(Map<String, dynamic> json) {
    return TiersPayantAssurance(
      lgTIERSPAYANTID: json['lgTIERSPAYANTID'] ?? '',
      strFULLNAME: json['strFULLNAME'] ?? '',
      strNAME: json['strNAME'] ?? '',
    );
  }
}