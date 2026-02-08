class TypeAjustement {
  final int id;
  final String libelle;

  TypeAjustement({required this.id, required this.libelle});

  factory TypeAjustement.fromJson(Map<String, dynamic> json) {
    return TypeAjustement(
      id: json['id'],
      libelle: json['libelle'],
    );
  }
}

class AjustementItem {
  final String lgAJUSTEMENTDETAILID;
  final String lgAJUSTEMENTID;
  final String lgFAMILLEID;
  final String strNAME;
  final String intCIP;
  final int intPRICE; // Prix de vente
  final int intPAF; // Prix d'achat
  final int intNUMBER; // Quantité ajustée (+/-)
  final int intNUMBERCURRENTSTOCK; // Stock avant
  final int intNUMBERAFTERSTOCK; // Stock après
  final String motifAjustement;
  final String operateur;
  final String dateOperation;
  final String heure;

  AjustementItem({
    required this.lgAJUSTEMENTDETAILID,
    required this.lgAJUSTEMENTID,
    required this.lgFAMILLEID,
    required this.strNAME,
    required this.intCIP,
    required this.intPRICE,
    required this.intPAF,
    required this.intNUMBER,
    required this.intNUMBERCURRENTSTOCK,
    required this.intNUMBERAFTERSTOCK,
    required this.motifAjustement,
    required this.operateur,
    required this.dateOperation,
    required this.heure,
  });

  factory AjustementItem.fromJson(Map<String, dynamic> json) {
    return AjustementItem(
      lgAJUSTEMENTDETAILID: json['lgAJUSTEMENTDETAILID'] ?? '',
      lgAJUSTEMENTID: json['lgAJUSTEMENTID'] ?? '',
      lgFAMILLEID: json['lgFAMILLEID'] ?? '',
      strNAME: json['strNAME'] ?? '',
      intCIP: json['intCIP'] ?? '',
      intPRICE: json['intPRICE'] ?? 0,
      intPAF: json['intPAF'] ?? 0,
      intNUMBER: json['intNUMBER'] ?? 0,
      intNUMBERCURRENTSTOCK: json['intNUMBERCURRENTSTOCK'] ?? 0,
      intNUMBERAFTERSTOCK: json['intNUMBERAFTERSTOCK'] ?? 0,
      motifAjustement: json['motifAjustement'] ?? '',
      operateur: json['operateur'] ?? '',
      dateOperation: json['dateOperation'] ?? '',
      heure: json['HEURE'] ?? '',
    );
  }
}