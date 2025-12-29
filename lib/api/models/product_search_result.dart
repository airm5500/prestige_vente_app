// lib/api/models/product_search_result.dart
// 11/11/2025 12:15 (Séparation stricte EAN Fabricant vs EAN13)

// Modèle pour les données détaillées d'un produit
class ProductDetails {
  final String lgFamilleId;
  final String intCip;
  final String strName;
  final int intPrice;
  final int intPaf;
  final String intEan13;         // Code EAN13 standard (souvent le CIP ou interne)
  final String codeEanFabriquant; // Code EAN Fabricant spécifique (peut être vide)
  final String lgZoneGeoId;
  final int intNumber;
  final String dtCreated;
  final String dtLastInventaire;
  final String dtDateLivraison;
  final String dtLastEntree;
  final String dtLastVente;
  final int intNumberDetail;
  final String dtPeremption;
  final Map<String, int> produitState;
  final int boolDeconditionneExist;

  ProductDetails({
    required this.lgFamilleId,
    required this.intCip,
    required this.strName,
    required this.intPrice,
    required this.intPaf,
    required this.intEan13,
    required this.codeEanFabriquant, // Nouveau champ requis
    required this.lgZoneGeoId,
    required this.intNumber,
    required this.dtCreated,
    required this.dtLastInventaire,
    required this.dtDateLivraison,
    required this.dtLastEntree,
    required this.dtLastVente,
    required this.intNumberDetail,
    required this.dtPeremption,
    required this.produitState,
    required this.boolDeconditionneExist,
  });

  factory ProductDetails.fromJson(Map<String, dynamic> json) {
    return ProductDetails(
      lgFamilleId: json['lg_FAMILLE_ID'] ?? '',
      intCip: json['int_CIP']?.toString() ?? '',
      strName: json['str_NAME'] ?? 'N/A',
      intPrice: json['int_PRICE'] ?? 0,
      intPaf: json['int_PAF'] ?? 0,

      // Lecture stricte des champs sans mélange
      intEan13: json['int_EAN13'] ?? 'N/A',
      codeEanFabriquant: json['codeEanFabriquant'] ?? '',

      lgZoneGeoId: json['lg_ZONE_GEO_ID'] ?? 'N/A',
      intNumber: json['int_NUMBER'] ?? 0,
      dtCreated: json['dt_CREATED'] ?? 'N/A',
      dtLastInventaire: json['dt_LAST_INVENTAIRE'] ?? 'N/A',
      dtDateLivraison: json['dt_DATE_LIVRAISON'] ?? 'N/A',
      dtLastEntree: json['dt_LAST_ENTREE'] ?? 'N/A',
      dtLastVente: json['dt_LAST_VENTE'] ?? 'N/A',
      intNumberDetail: json['int_NUMBERDETAIL'] ?? 0,
      dtPeremption: json['dtPEREMPTION'] ?? 'N/A',
      produitState: {
        'enCommande': json['produitState']?['enCommande'] ?? 0,
        'entree': json['produitState']?['entree'] ?? 0,
        'enSuggestion': json['produitState']?['enSuggestion'] ?? 0,
      },
      boolDeconditionneExist: json['bool_DECONDITIONNE_EXIST'] ?? 0,
    );
  }
}

// Modèle pour une ligne de l'historique de commande
class ProductOrderHistory {
  final String dtEntree;
  final int intNumber;

  ProductOrderHistory({required this.dtEntree, required this.intNumber});

  factory ProductOrderHistory.fromJson(Map<String, dynamic> json) {
    return ProductOrderHistory(
      dtEntree: json['dt_ENTREE'] ?? '',
      intNumber: json['int_NUMBER'] ?? 0,
    );
  }
}