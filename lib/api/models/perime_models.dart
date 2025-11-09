// lib/api/models/perime_models.dart
// 09/11/2025 17:30

// 1. Modèle pour la RECHERCHE (GET /fichearticle/perimes)
class PerimeMetaData {
  final int totalQuantiteLot;
  final int totalValeurAchat;
  final int totalValeurVente;

  PerimeMetaData({
    required this.totalQuantiteLot,
    required this.totalValeurAchat,
    required this.totalValeurVente,
  });

  factory PerimeMetaData.fromJson(Map<String, dynamic> json) {
    return PerimeMetaData(
      totalQuantiteLot: json['totalQuantiteLot'] ?? 0,
      totalValeurAchat: json['totalValeurAchat'] ?? 0,
      totalValeurVente: json['totalValeurVente'] ?? 0,
    );
  }
}

class ProduitPerime {
  final String libelleRayon;
  final String numLot;
  final String datePerement;
  final String libelleGrossiste;
  final String libelle;
  final String statut;
  final String libelleFamille;
  final int quantiteLot;
  final String codeCip;
  final int valeurVente;
  final int valeurAchat;

  ProduitPerime({
    required this.libelleRayon,
    required this.numLot,
    required this.datePerement,
    required this.libelleGrossiste,
    required this.libelle,
    required this.statut,
    required this.libelleFamille,
    required this.quantiteLot,
    required this.codeCip,
    required this.valeurVente,
    required this.valeurAchat,
  });

  factory ProduitPerime.fromJson(Map<String, dynamic> json) {
    return ProduitPerime(
      libelleRayon: json['libelleRayon'] ?? '',
      numLot: json['numLot'] ?? '',
      datePerement: json['datePerement'] ?? '',
      libelleGrossiste: json['libelleGrossiste'] ?? '',
      libelle: json['libelle'] ?? '',
      statut: json['statut'] ?? '',
      libelleFamille: json['libelleFamille'] ?? '',
      quantiteLot: json['quantiteLot'] ?? 0,
      codeCip: json['codeCip'] ?? '',
      valeurVente: json['valeurVente'] ?? 0,
      valeurAchat: json['valeurAchat'] ?? 0,
    );
  }
}


// 2. Modèle pour l'HISTORIQUE (GET /fichearticle/saisieperimes)
class SaisiePerimeItem {
  final String intCIP;
  final String strNAME;
  final int prixAchat;
  final int intPRICE;
  final int stockInitial;
  final int intQUANTITY; // qte sortie
  final int stockFinal;
  final String ticketNum; // Lot
  final String dtCREATED; // Date peremption
  final String dateOperation;
  final String libelleRayon;

  SaisiePerimeItem({
    required this.intCIP,
    required this.strNAME,
    required this.prixAchat,
    required this.intPRICE,
    required this.stockInitial,
    required this.intQUANTITY,
    required this.stockFinal,
    required this.ticketNum,
    required this.dtCREATED,
    required this.dateOperation,
    required this.libelleRayon,
  });

  factory SaisiePerimeItem.fromJson(Map<String, dynamic> json) {
    return SaisiePerimeItem(
      intCIP: json['intCIP'] ?? '',
      strNAME: json['strNAME'] ?? '',
      prixAchat: json['prixAchat'] ?? 0,
      intPRICE: json['intPRICE'] ?? 0,
      stockInitial: json['stockInitial'] ?? 0,
      intQUANTITY: json['intQUANTITY'] ?? 0,
      stockFinal: json['stockFinal'] ?? 0,
      ticketNum: json['ticketNum'] ?? '',
      dtCREATED: json['dtCREATED'] ?? '',
      dateOperation: json['dateOperation'] ?? '',
      libelleRayon: json['libelleRayon'] ?? '',
    );
  }
}


// 3. Modèle pour la SAISIE EN COURS (GET /gestionperime/saisie-encours)
class SaisieEnCoursItem {
  final String id; // ID de l'item (pour suppression)
  final String lot;
  final String produitCip;
  final int quantity;
  final String produitId;
  final int stockInitial;
  final String dateEntree;
  final String datePeremption;
  final int stockFinal;
  final String produitLibelle;

  SaisieEnCoursItem({
    required this.id,
    required this.lot,
    required this.produitCip,
    required this.quantity,
    required this.produitId,
    required this.stockInitial,
    required this.dateEntree,
    required this.datePeremption,
    required this.stockFinal,
    required this.produitLibelle,
  });

  factory SaisieEnCoursItem.fromJson(Map<String, dynamic> json) {
    return SaisieEnCoursItem(
      id: json['id'] ?? '',
      lot: json['lot'] ?? '',
      produitCip: json['produitCip'] ?? '',
      quantity: json['quantity'] ?? 0,
      produitId: json['produitId'] ?? '',
      stockInitial: json['stockInitial'] ?? 0,
      dateEntree: json['dateEntree'] ?? '',
      datePeremption: json['datePeremption'] ?? '',
      stockFinal: json['stockFinal'] ?? 0,
      produitLibelle: json['produitLibelle'] ?? '',
    );
  }
}