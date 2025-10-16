// lib/api/models/commande_item.dart
// 16/10/2025 10:01
class CommandeItem {
  final String id;
  final String produitId;
  final String nomProduit;
  final String cip;
  final int qteCommandee;
  final int prixAchat;

  CommandeItem({
    required this.id,
    required this.produitId,
    required this.nomProduit,
    required this.cip,
    required this.qteCommandee,
    required this.prixAchat,
  });

  factory CommandeItem.fromJson(Map<String, dynamic> json) {
    return CommandeItem(
      id: json['lg_ORDERDETAIL_ID'],
      produitId: json['lg_FAMILLE_ID'],
      nomProduit: json['lg_FAMILLE_NAME'],
      cip: json['lg_FAMILLE_CIP'],
      qteCommandee: json['int_NUMBER'],
      prixAchat: json['prixAchat'],
    );
  }
}