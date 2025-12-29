// lib/api/models/reception_model.dart
class ReceptionBon {
  final String id;
  final String ref;
  final String grossiste;
  final String dateLivraison;
  final String dateCreation;
  final String statutTraitement;
  final int nbreLignes;
  final int montantHt;
  final List<ReceptionItem> details;

  ReceptionBon({
    required this.id,
    required this.ref,
    required this.grossiste,
    required this.dateLivraison,
    required this.dateCreation,
    required this.statutTraitement,
    required this.nbreLignes,
    required this.montantHt,
    required this.details,
  });

  factory ReceptionBon.fromJson(Map<String, dynamic> json) {
    var listDetails = json['bonLivraisonDetails'] as List? ?? [];
    List<ReceptionItem> items = listDetails.map((i) => ReceptionItem.fromJson(i)).toList();

    return ReceptionBon(
      id: json['lgBONLIVRAISONID'] ?? '',
      ref: json['strREFLIVRAISON'] ?? '',
      grossiste: json['fournisseurLibelle'] ?? '',
      dateLivraison: json['dtDATELIVRAISON'] ?? '',
      dateCreation: json['dtCREATED'] ?? '',
      statutTraitement: json['checked'] ?? 'NON_TRAITE',
      nbreLignes: items.length,
      montantHt: json['intHTTC'] ?? 0,
      details: items,
    );
  }
}

class ReceptionItem {
  final String id;
  final String produitId;
  final String nomProduit;
  final String cip;
  final String ean;
  final int qteCommandee;
  final int qteRecue;
  final int quantiteControle;
  final int prixAchat;
  final int prixVente;
  final String emplacement; // Ce champ est maintenant rempli directement

  ReceptionItem({
    required this.id,
    required this.produitId,
    required this.nomProduit,
    required this.cip,
    required this.ean,
    required this.qteCommandee,
    required this.qteRecue,
    required this.quantiteControle,
    required this.prixAchat,
    required this.prixVente,
    this.emplacement = '',
  });

  factory ReceptionItem.fromJson(Map<String, dynamic> json) {
    final produit = json['produit'] ?? {};

    return ReceptionItem(
      id: json['lgBONLIVRAISONDETAIL'] ?? '',
      produitId: produit['lg_FAMILLE_ID'] ?? '',
      nomProduit: produit['strNAME'] ?? '',
      cip: produit['intCIP'] ?? '',
      ean: produit['intEAN13'] ?? '',
      qteCommandee: json['intQTECMDE'] ?? 0,
      qteRecue: json['intQTERECUE'] ?? 0,
      quantiteControle: json['quantiteControle'] ?? 0,
      prixAchat: json['intPAF'] ?? 0,
      prixVente: json['intPRIXVENTE'] ?? 0,
      // NOUVEAU : Lecture directe du champ ajouté au backend
      emplacement: json['lgZONEGEONom'] ?? '',
    );
  }
}