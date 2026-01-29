// lib/api/models/depot_model.dart
class DepotModel {
  final String lgCLIENTID;
  final String strFIRSTNAME;
  final String strLASTNAME;
  final String strNAME; // Nom complet souvent
  final String lgEMPLACEMENTID; // ID de l'emplacement (magasin)
  final String lgTYPEDEPOTID;
  final String descriptionTypeDepot;

  DepotModel({
    required this.lgCLIENTID,
    required this.strFIRSTNAME,
    required this.strLASTNAME,
    required this.strNAME,
    required this.lgEMPLACEMENTID,
    required this.lgTYPEDEPOTID,
    required this.descriptionTypeDepot,
  });

  factory DepotModel.fromJson(Map<String, dynamic> json) {
    return DepotModel(
      lgCLIENTID: json['lgCLIENTID'] ?? '',
      strFIRSTNAME: json['strFIRSTNAME'] ?? '',
      strLASTNAME: json['strLASTNAME'] ?? '',
      strNAME: json['strNAME'] ?? '',
      lgEMPLACEMENTID: json['lgEMPLACEMENTID'] ?? '',
      lgTYPEDEPOTID: json['lgTYPEDEPOTID'] ?? '',
      descriptionTypeDepot: json['desciptiontypedepot'] ?? '',
    );
  }

  String get fullName => "$strFIRSTNAME $strLASTNAME".trim().isEmpty ? strNAME : "$strFIRSTNAME $strLASTNAME";
}

class DepotSaleListItem {
  final String lgPREENREGISTREMENTID;
  final String strREF;
  final String strClientFullName;
  final String dtUPDATED;
  final String heure;
  final int intPRICE;
  final String strSTATUT;
  final String userFullName;

  DepotSaleListItem({
    required this.lgPREENREGISTREMENTID,
    required this.strREF,
    required this.strClientFullName,
    required this.dtUPDATED,
    required this.heure,
    required this.intPRICE,
    required this.strSTATUT,
    required this.userFullName,
  });

  factory DepotSaleListItem.fromJson(Map<String, dynamic> json) {
    return DepotSaleListItem(
      lgPREENREGISTREMENTID: json['lgPREENREGISTREMENTID'] ?? '',
      strREF: json['strREF'] ?? '',
      strClientFullName: json['clientFullName'] ?? 'Client Inconnu',
      dtUPDATED: json['dtUPDATED'] ?? '',
      heure: json['heure'] ?? '',
      intPRICE: (json['intPRICE'] as num?)?.toInt() ?? 0,
      strSTATUT: json['strSTATUT'] ?? '',
      userFullName: json['userFullName'] ?? '',
    );
  }
}