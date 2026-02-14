// lib/api/models/bon_livraison_item.dart

class BonLivraisonItem {
  final String id;
  final String produitId;
  final String nomProduit;
  final String cip;
  final int qteCommandee;
  final int qteRecue;       // int_QTE_RECUE (Qté validée/facturée)

  final int stockFinal;     // lg_FAMILLE_QTE_STOCK (Stock Actuel Temps Réel)
  final int stockInitialReel; // Stock_Init (Stock figé AVANT mouvement)
  final int freeQty;        // freeQty (Unités gratuites)

  final bool isChecked;
  final int checkedQuantity; // La quantité comptée par l'utilisateur
  final int prixAchat;
  final int prixVente;
  final String zoneGeoName;

  // Calcul du stock théorique cible pour le contrôle
  // Formule : Stock Avant + Entrées (Facturées + Gratuites)
  int get stockFinalTheorique => stockInitialReel + qteRecue + freeQty;

  BonLivraisonItem({
    required this.id,
    required this.produitId,
    required this.nomProduit,
    required this.cip,
    required this.qteCommandee,
    required this.qteRecue,
    required this.stockFinal,
    required this.stockInitialReel,
    required this.freeQty,
    required this.isChecked,
    required this.checkedQuantity,
    required this.prixAchat,
    required this.prixVente,
    required this.zoneGeoName,
  });

  factory BonLivraisonItem.fromJson(Map<String, dynamic> json) {
    String cipValue = json['lg_FAMILLE_CIP'] ?? '';
    if (cipValue.isEmpty) {
      cipValue = json['str_CODE_ARTICLE'] ?? '';
    }

    return BonLivraisonItem(
      id: json['lg_BON_LIVRAISON_DETAIL'] ?? '',
      produitId: json['lg_FAMILLE_ID'] ?? '',
      nomProduit: json['lg_FAMILLE_NAME'] ?? '',
      cip: cipValue,
      qteCommandee: (json['int_QTE_CMDE'] as num?)?.toInt() ?? 0,
      qteRecue: (json['int_QTE_RECUE'] as num?)?.toInt() ?? 0,

      // Stock Temps Réel (bouge avec les ventes)
      stockFinal: (json['lg_FAMILLE_QTE_STOCK'] as num?)?.toInt() ?? 0,

      // Stock Historique (figé) & UG
      stockInitialReel: (json['Stock_Init'] as num?)?.toInt() ?? 0,
      freeQty: (json['freeQty'] as num?)?.toInt() ?? 0,

      isChecked: json['checked'] ?? false,
      checkedQuantity: (json['quantiteSaisie'] ?? json['checkedQuantity'] as num?)?.toInt() ?? 0,
      prixAchat: (json['int_PA_REEL'] as num?)?.toInt() ?? 0,
      prixVente: (json['int_PRIX_VENTE'] as num?)?.toInt() ?? 0,
      zoneGeoName: json['lg_ZONE_GEO_NAME'] ?? 'Non défini',
    );
  }
}