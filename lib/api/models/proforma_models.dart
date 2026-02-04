// lib/api/models/proforma_models.dart

/// Modèle pour les Tiers-Payants (Assurances) rattachés à un client
class TiersPayantModel {
  final String lgTIERSPAYANTID;
  final int intPOURCENTAGE;
  final int? intPRIORITY;
  final String? lgCOMPTETIERSIAYANTID;

  TiersPayantModel({
    required this.lgTIERSPAYANTID,
    required this.intPOURCENTAGE,
    this.intPRIORITY,
    this.lgCOMPTETIERSIAYANTID,
  });

  factory TiersPayantModel.fromJson(Map<String, dynamic> json) {
    return TiersPayantModel(
      lgTIERSPAYANTID: json['lgTIERSPAYANTID'] ?? '',
      intPOURCENTAGE: json['intPOURCENTAGE'] ?? json['taux'] ?? 0,
      intPRIORITY: json['intPRIORITY'] ?? json['order'] ?? 0,
      lgCOMPTETIERSIAYANTID: json['lgCOMPTETIERSIAYANTID'] ?? json['compteTp'],
    );
  }
}

/// Classe de base pour les clients (Polymorphisme)
class ClientModel {
  final String lgCLIENTID;
  final String strFIRSTNAME;
  final String strLASTNAME;

  ClientModel({
    required this.lgCLIENTID,
    required this.strFIRSTNAME,
    required this.strLASTNAME,
  });

  String get fullName => "$strFIRSTNAME $strLASTNAME";

  // Permet de récupérer une liste vide par défaut pour éviter les crashs si mal utilisé
  List<TiersPayantModel> get tiersPayants => [];
}

/// Modèle spécifique pour les clients CARNET (API /client/all?typeClientId=2)
class ClientCarnetModel extends ClientModel {
  final String? strCODEINTERNE;
  final String? strNUMEROSECURITESOCIAL;
  final List<TiersPayantModel> _tiersPayantsList;

  ClientCarnetModel({
    required String lgCLIENTID,
    required String strFIRSTNAME,
    required String strLASTNAME,
    this.strCODEINTERNE,
    this.strNUMEROSECURITESOCIAL,
    List<TiersPayantModel>? tiersPayants,
  }) : _tiersPayantsList = tiersPayants ?? [],
        super(lgCLIENTID: lgCLIENTID, strFIRSTNAME: strFIRSTNAME, strLASTNAME: strLASTNAME);

  @override
  List<TiersPayantModel> get tiersPayants => _tiersPayantsList;

  factory ClientCarnetModel.fromJson(Map<String, dynamic> json) {
    return ClientCarnetModel(
      lgCLIENTID: json['lgCLIENTID'] ?? '',
      strFIRSTNAME: json['strFIRSTNAME'] ?? '',
      strLASTNAME: json['strLASTNAME'] ?? '',
      strCODEINTERNE: json['strCODEINTERNE'],
      strNUMEROSECURITESOCIAL: json['strNUMEROSECURITESOCIAL'],
      tiersPayants: json['tiersPayants'] != null
          ? (json['tiersPayants'] as List)
          .map((i) => TiersPayantModel.fromJson(i))
          .toList()
          : [],
    );
  }
}

/// Modèle spécifique pour les clients COMPTANT (API /client/lambda)
class ClientComptantModel extends ClientModel {
  final String? strADRESSE;
  final String? lgTYPECLIENTID;
  final String? strSEXE;

  ClientComptantModel({
    required String lgCLIENTID,
    required String strFIRSTNAME,
    required String strLASTNAME,
    this.strADRESSE,
    this.lgTYPECLIENTID,
    this.strSEXE,
  }) : super(lgCLIENTID: lgCLIENTID, strFIRSTNAME: strFIRSTNAME, strLASTNAME: strLASTNAME);

  factory ClientComptantModel.fromJson(Map<String, dynamic> json) {
    return ClientComptantModel(
      lgCLIENTID: json['lgCLIENTID'] ?? '',
      strFIRSTNAME: json['strFIRSTNAME'] ?? '',
      strLASTNAME: json['strLASTNAME'] ?? '',
      strADRESSE: json['strADRESSE'],
      lgTYPECLIENTID: json['lgTYPECLIENTID'],
      strSEXE: json['strSEXE'],
    );
  }
}

class ProformaListItem {
  final String lgPREENREGISTREMENTID;
  final String strREF;
  final String strClientFullName;
  final String dtUPDATED;
  final String heure;
  final int intPRICE;
  final String strSTATUT;
  final String userFullName;
  final String strTYPEVENTE;
  final String clientId;

  ProformaListItem({
    required this.lgPREENREGISTREMENTID,
    required this.strREF,
    required this.strClientFullName,
    required this.dtUPDATED,
    required this.heure,
    required this.intPRICE,
    required this.strSTATUT,
    required this.strTYPEVENTE,
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
      strTYPEVENTE: json['strTYPEVENTE'] ?? '',
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