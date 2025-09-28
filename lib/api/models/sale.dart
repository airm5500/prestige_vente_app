// lib/api/models/sale.dart
// 28/09/2025 01:41

// Pour les détails d'un article dans le panier
class SaleItemDetail {
  final String lgPREENREGISTREMENTDETAILID;
  final String lgFAMILLEID;
  final String strNAME;
  final String intCIP;
  final int intQUANTITY;
  final int intPRICEUNITAIR; // Prix unitaire de l'article
  final int intPRICE; // Montant total de la ligne (PU * Qte)

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
      lgPREENREGISTREMENTDETAILID: json['lgPREENREGISTREMENTDETAILID'],
      lgFAMILLEID: json['lgFAMILLEID'],
      strNAME: json['strNAME'],
      intCIP: json['intCIP'],
      intQUANTITY: json['intQUANTITY'],
      intPRICEUNITAIR: json['intPRICEUNITAIR'],
      intPRICE: json['intPRICE'],
    );
  }
}

// Pour la réponse après calcul du net à payer
class SaleSummary {
  final int montant;
  final int remise;
  final int montantNet;
  final String venteId;
  final String reference;

  SaleSummary({
    this.montant = 0,
    this.remise = 0,
    this.montantNet = 0,
    this.venteId = '',
    this.reference = '',
  });

  factory SaleSummary.fromNetResponse(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? {};
    return SaleSummary(
      montant: data['montant'] ?? 0,
      remise: data['remise'] ?? 0,
      montantNet: data['montantNet'] ?? 0,
      venteId: json['lgPREENREGISTREMENTID'] ?? '',
      reference: json['strREF'] ?? '',
    );
  }
}

// Pour la liste des préventes
class PreventeListItem {
  final String lgPREENREGISTREMENTID;
  final String heure;
  final String dtUPDATED;
  final int intPRICE;
  final String strREF;
  final String userFullName;

  PreventeListItem({
    required this.lgPREENREGISTREMENTID,
    required this.heure,
    required this.dtUPDATED,
    required this.intPRICE,
    required this.strREF,
    required this.userFullName,
  });

  factory PreventeListItem.fromJson(Map<String, dynamic> json) {
    return PreventeListItem(
      lgPREENREGISTREMENTID: json['lgPREENREGISTREMENTID'],
      heure: json['heure'],
      dtUPDATED: json['dtUPDATED'],
      intPRICE: json['intPRICE'],
      strREF: json['strREF'],
      userFullName: json['userFullName'],
    );
  }
}

// Pour les modes de règlement
class PaymentMethod {
  final String id;
  final String name;

  PaymentMethod({required this.id, required this.name});

  factory PaymentMethod.fromJson(Map<String, dynamic> json) {
    return PaymentMethod(
      id: json['lgTYPEREGLEMENTID'],
      name: json['strNAME'],
    );
  }
}