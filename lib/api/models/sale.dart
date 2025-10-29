// lib/api/models/sale.dart
// 30/10/2025 00:15
class SaleItemDetail {
  final String lgPREENREGISTREMENTDETAILID;
  final String lgFAMILLEID;
  final String strNAME;
  final String intCIP;
  final int intQUANTITY;
  final int intPRICEUNITAIR;
  final int intPRICE;

  SaleItemDetail({
    required this.lgPREENREGISTREMENTDETAILID,
    required this.lgFAMILLEID,
    required this.strNAME,
    required this.intCIP,
    required this.intQUANTITY,
    required this.intPRICEUNITAIR,
    required this.intPRICE,
  });

  factory SaleItemDetail.fromJson(Map<String, dynamic> json) {
    return SaleItemDetail(
      lgPREENREGISTREMENTDETAILID: json['lgPREENREGISTREMENTDETAILID'] ?? '',
      lgFAMILLEID: json['lgFAMILLEID'] ?? '',
      strNAME: json['strNAME'] ?? '',
      intCIP: json['intCIP'] ?? '',
      intQUANTITY: json['intQUANTITY'] ?? 0,
      intPRICEUNITAIR: json['intPRICEUNITAIR'] ?? 0,
      intPRICE: json['intPRICE'] ?? 0,
    );
  }
}

class SaleSummary {
  final int montant;
  final int remise;
  final int montantNet;
  final String venteId;
  final String reference;
  final int marge;
  final int montantTva;
  // Ajoutez d'autres champs de l'objet 'data' ici si nécessaire

  SaleSummary({
    this.montant = 0,
    this.remise = 0,
    this.montantNet = 0,
    this.venteId = '',
    this.reference = '',
    this.marge = 0,
    this.montantTva = 0,
  });

  factory SaleSummary.fromNetResponse(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? {};
    return SaleSummary(
      montant: data['montant'] ?? 0,
      remise: data['remise'] ?? 0,
      montantNet: data['montantNet'] ?? 0,
      marge: data['marge'] ?? 0,
      montantTva: data['montantTva'] ?? 0,
      venteId: json['lgPREENREGISTREMENTID'] ?? '',
      reference: json['strREF'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'montant': montant,
      'remise': remise,
      'montantNet': montantNet,
      'marge': marge,
      'montantTva': montantTva,
      'tierspayants': [], // Champ requis par l'API
    };
  }
}

class PreventeListItem {
  final String lgPREENREGISTREMENTID;
  final String heure;
  final String dtUPDATED;
  final int intPRICE;
  final String strREF;
  final String userFullName;
  // MODIFICATION : Ajout du champ pour le filtre
  final String lgTYPEVENTEID;

  PreventeListItem({
    required this.lgPREENREGISTREMENTID,
    required this.heure,
    required this.dtUPDATED,
    required this.intPRICE,
    required this.strREF,
    required this.userFullName,
    // MODIFICATION : Ajout au constructeur
    required this.lgTYPEVENTEID,
  });

  factory PreventeListItem.fromJson(Map<String, dynamic> json) {
    return PreventeListItem(
      lgPREENREGISTREMENTID: json['lgPREENREGISTREMENTID'] ?? '',
      heure: json['heure'] ?? '',
      dtUPDATED: json['dtUPDATED'] ?? '',
      intPRICE: json['intPRICE'] ?? 0,
      strREF: json['strREF'] ?? '',
      userFullName: json['userFullName'] ?? '',
      // MODIFICATION : Lecture du champ depuis l'API
      lgTYPEVENTEID: json['lgTYPEVENTEID'] ?? '',
    );
  }
}

class PaymentMethod {
  final String id;
  final String name;

  PaymentMethod({required this.id, required this.name});

  factory PaymentMethod.fromJson(Map<String, dynamic> json) {
    return PaymentMethod(
      id: json['lgTYPEREGLEMENTID'] ?? '',
      name: json['strNAME'] ?? '',
    );
  }
}