// lib/api/models/bon_livraison_item.dart
// 19/10/2025 03:00
class BonLivraisonItem {
  final String id;
  final String produitId;
  final String nomProduit;
  final String cip;
  final int qteCommandee;
  final int qteRecue;
  final int stockInitial; // Ce champ contient lg_FAMILLE_QTE_STOCK
  final bool isChecked;
  final int checkedQuantity;
  final int prixAchat;

  // MODIFICATION : Le stock théorique EST le stockInitial (qui est lg_FAMILLE_QTE_STOCK)
  int get stockTheorique => stockInitial;

  BonLivraisonItem({
    required this.id,
    required this.produitId,
    required this.nomProduit,
    required this.cip,
    required this.qteCommandee,
    required this.qteRecue,
    required this.stockInitial,
    required this.isChecked,
    required this.checkedQuantity,
    required this.prixAchat,
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
      qteCommandee: json['int_QTE_CMDE'] ?? 0,
      qteRecue: json['int_QTE_RECUE'] ?? 0,
      stockInitial: json['lg_FAMILLE_QTE_STOCK'] ?? 0,
      isChecked: json['checked'] ?? false,
      checkedQuantity: json['checkedQuantity'] ?? 0,
      prixAchat: json['int_PA_REEL'] ?? 0,
    );
  }
}