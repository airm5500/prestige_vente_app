// lib/api/models/ayant_droit.dart
// 02/11/2025 15:20
class AyantDroit {
  final String lgAYANTSDROITSID;
  final String lgCLIENTID;
  final String fullName;
  final String strFIRSTNAME;
  final String strLASTNAME;
  final String strNUMEROSECURITESOCIAL;
  final String strSEXE;
  final String? dtNAISSANCE;

  AyantDroit({
    required this.lgAYANTSDROITSID,
    required this.lgCLIENTID,
    required this.fullName,
    required this.strFIRSTNAME,
    required this.strLASTNAME,
    required this.strNUMEROSECURITESOCIAL,
    required this.strSEXE,
    this.dtNAISSANCE,
  });

  factory AyantDroit.fromJson(Map<String, dynamic> json) {
    return AyantDroit(
      lgAYANTSDROITSID: json['lgAYANTSDROITSID'] ?? '',
      lgCLIENTID: json['lgCLIENTID'] ?? '',
      fullName: json['fullName'] ?? '',
      strFIRSTNAME: json['strFIRSTNAME'] ?? '',
      strLASTNAME: json['strLASTNAME'] ?? '',
      strNUMEROSECURITESOCIAL: json['strNUMEROSECURITESOCIAL'] ?? '',
      strSEXE: json['strSEXE'] ?? '',
      dtNAISSANCE: json['dtNAISSANCE'],
    );
  }
}