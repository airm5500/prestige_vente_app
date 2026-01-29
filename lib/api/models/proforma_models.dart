// lib/api/models/proforma_models.dart

class ProformaListItem {
  final String lgPREENREGISTREMENTID;
  final String strREF;
  final String strClientFullName;
  final String dtUPDATED;
  final String heure;
  final int intPRICE;
  final String strSTATUT;
  final String userFullName;
  final String clientId;

  ProformaListItem({
    required this.lgPREENREGISTREMENTID,
    required this.strREF,
    required this.strClientFullName,
    required this.dtUPDATED,
    required this.heure,
    required this.intPRICE,
    required this.strSTATUT,
    required this.userFullName,
    required this.clientId,
  });

  factory ProformaListItem.fromJson(Map<String, dynamic> json) {

    String cId = '';
    if (json['client'] != null && json['client']['lgCLIENTID'] != null) {
      cId = json['client']['lgCLIENTID'];
    }
    return ProformaListItem(
      lgPREENREGISTREMENTID: json['lgPREENREGISTREMENTID'] ?? '',
      strREF: json['strREF'] ?? '',
      strClientFullName: json['clientFullName'] ?? 'Client Inconnu',
      dtUPDATED: json['dtUPDATED'] ?? '',
      heure: json['heure'] ?? '',
      intPRICE: (json['intPRICE'] as num?)?.toInt() ?? 0,
      strSTATUT: json['strSTATUT'] ?? '',
      userFullName: json['userFullName'] ?? '',
      clientId: cId,
    );
  }
}

class TypeDevis {
  final String lgTYPEVENTEID;
  final String strNAME;
  final String strDESCRIPTION;

  TypeDevis({required this.lgTYPEVENTEID, required this.strNAME, required this.strDESCRIPTION});

  factory TypeDevis.fromJson(Map<String, dynamic> json) {
    return TypeDevis(
      lgTYPEVENTEID: json['lgTYPEVENTEID'] ?? '',
      strNAME: json['strNAME'] ?? '',
      strDESCRIPTION: json['strDESCRIPTION'] ?? '',
    );
  }
}

class ClientModel {
  final String lgCLIENTID;
  final String strFIRSTNAME;
  final String strLASTNAME;
  final String fullName;

  ClientModel({
    required this.lgCLIENTID,
    required this.strFIRSTNAME,
    required this.strLASTNAME,
    required this.fullName,
  });

  factory ClientModel.fromJson(Map<String, dynamic> json) {
    return ClientModel(
      lgCLIENTID: json['lgCLIENTID'] ?? '',
      strFIRSTNAME: json['strFIRSTNAME'] ?? '',
      strLASTNAME: json['strLASTNAME'] ?? '',
      fullName: json['fullName'] ?? "${json['strFIRSTNAME']} ${json['strLASTNAME']}",
    );
  }
}

// Dans lib/api/models/proforma_models.dart

class RemiseModel {
  final String lgREMISEID;
  final String strNAME;
  final String strCODE;
  final double dblTAUX;

  RemiseModel({
    required this.lgREMISEID,
    required this.strNAME,
    required this.strCODE,
    required this.dblTAUX,
  });

  factory RemiseModel.fromJson(Map<String, dynamic> json) {
    double taux = 0.0;

    // Gestion robuste du taux (qui est un objet dans votre JSON)
    if (json['dblTAUX'] is Map) {
      taux = (json['dblTAUX']['parsedValue'] as num?)?.toDouble() ?? 0.0;
    } else if (json['dblTAUX'] is num) {
      taux = (json['dblTAUX'] as num).toDouble();
    }

    return RemiseModel(
      lgREMISEID: json['lgREMISEID'] ?? '',
      strNAME: json['strNAME'] ?? '',
      strCODE: json['strCODE'] ?? '',
      dblTAUX: taux,
    );
  }

}