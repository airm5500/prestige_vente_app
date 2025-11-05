// lib/api/models/ayant_droit.dart
// 05/11/2025 02:10 (Corrigé)
import 'package:flutter/foundation.dart'; // Import pour @override

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

  // MODIFICATION (Correction Erreur Point 4)
  // Permet au DropdownButton de comparer les instances
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is AyantDroit &&
        other.lgAYANTSDROITSID == lgAYANTSDROITSID;
  }

  @override
  int get hashCode => lgAYANTSDROITSID.hashCode;
}