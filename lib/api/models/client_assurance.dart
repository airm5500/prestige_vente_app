// lib/api/models/client_assurance.dart
// 02/11/2025 15:20
import 'package:prestige_vente_app/api/models/ayant_droit.dart';

// Modèle pour un tiers payant rattaché à un client
class ClientTiersPayant {
  final String lgTIERSPAYANTID;
  final String tpFullName;
  final int taux;
  final String numSecurity;
  final String compteTp; // Ajout du compteTp
  final int order;
  final bool principal;

  ClientTiersPayant({
    required this.lgTIERSPAYANTID,
    required this.tpFullName,
    required this.taux,
    required this.numSecurity,
    required this.compteTp,
    required this.order,
    required this.principal,
  });

  factory ClientTiersPayant.fromJson(Map<String, dynamic> json) {
    return ClientTiersPayant(
      lgTIERSPAYANTID: json['lgTIERSPAYANTID'] ?? '',
      tpFullName: json['tpFullName'] ?? '',
      taux: json['taux'] ?? 0,
      numSecurity: json['numSecurity'] ?? json['strNUMEROSECURITESOCIAL'] ?? '',
      compteTp: json['compteTp'] ?? '',
      order: json['order'] ?? 1,
      principal: json['principal'] ?? false,
    );
  }
}

// Modèle principal pour le client (GET /client/all)
class ClientAssurance {
  final String lgCLIENTID;
  final String fullName;
  final String strFIRSTNAME;
  final String strLASTNAME;
  final String strNUMEROSECURITESOCIAL;
  final List<ClientTiersPayant> tiersPayants;
  final List<AyantDroit> ayantDroits; // Le client est son propre ayant droit par défaut

  ClientAssurance({
    required this.lgCLIENTID,
    required this.fullName,
    required this.strFIRSTNAME,
    required this.strLASTNAME,
    required this.strNUMEROSECURITESOCIAL,
    required this.tiersPayants,
    required this.ayantDroits,
  });

  factory ClientAssurance.fromJson(Map<String, dynamic> json) {
    var tiersPayantsList = <ClientTiersPayant>[];
    if (json['tiersPayants'] is List) {
      tiersPayantsList = (json['tiersPayants'] as List)
          .map((tp) => ClientTiersPayant.fromJson(tp))
          .toList();
    }

    var ayantDroitsList = <AyantDroit>[];
    if (json['ayantDroits'] is List) {
      ayantDroitsList = (json['ayantDroits'] as List)
          .map((ad) => AyantDroit.fromJson(ad))
          .toList();
    }

    // Si la liste de tiers payant est vide, on essaie de la remplir
    // avec les infos de la racine (cas d'un seul TP)
    if (tiersPayantsList.isEmpty && json['lgTIERSPAYANTID'] != null) {
      tiersPayantsList.add(ClientTiersPayant(
        lgTIERSPAYANTID: json['lgTIERSPAYANTID'],
        tpFullName: json['tpFullName'] ?? 'N/A', // Il manque tpFullName à la racine, à vérifier
        taux: json['intPOURCENTAGE'] ?? 0,
        numSecurity: json['strNUMEROSECURITESOCIAL'] ?? '',
        compteTp: json['compteTp'] ?? '',
        order: json['intPRIORITY'] ?? 1,
        principal: true,
      ));
    }


    return ClientAssurance(
      lgCLIENTID: json['lgCLIENTID'] ?? '',
      fullName: json['fullName'] ?? '',
      strFIRSTNAME: json['strFIRSTNAME'] ?? '',
      strLASTNAME: json['strLASTNAME'] ?? '',
      strNUMEROSECURITESOCIAL: json['strNUMEROSECURITESOCIAL'] ?? '',
      tiersPayants: tiersPayantsList,
      ayantDroits: ayantDroitsList,
    );
  }
}