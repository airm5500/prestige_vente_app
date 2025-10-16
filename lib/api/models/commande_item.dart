// lib/api/models/commande_item.dart
// 16/10/2025 10:56
class CommandeItem {
  final String id;
  final String produitId;
  final String nomProduit;
  final String cip;
  final int qteCommandee;
  final int prixAchat;
  // MODIFICATION : Ajout des champs
  final bool isChecked;
  final int checkedQuantity;

  CommandeItem({
    required this.id,
    required this.produitId,
    required this.nomProduit,
    required this.cip,
    required this.qteCommandee,
    required this.prixAchat,
    required this.isChecked,
    required this.checkedQuantity,
  });

  factory CommandeItem.fromJson(Map<String, dynamic> json) {
    String cipValue = json['lg_FAMILLE_CIP'] ?? '';
    if (cipValue.isEmpty) {
      cipValue = json['str_CODE_ARTICLE'] ?? '';
    }

    return CommandeItem(
      id: json['lg_ORDERDETAIL_ID'] ?? '',
      produitId: json['lg_FAMILLE_ID'] ?? '',
      nomProduit: json['lg_FAMILLE_NAME'] ?? '',
      cip: cipValue,
      qteCommandee: json['int_NUMBER'] ?? 0,
      prixAchat: json['prixAchat'] ?? 0,
      // MODIFICATION : Lecture des nouveaux champs
      isChecked: json['checked'] ?? false,
      checkedQuantity: json['checkedQuantity'] ?? 0,
    );
  }
}