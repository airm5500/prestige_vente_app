// lib/providers/delivery_control_provider.dart
// 18/10/2025 14:30
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/commande.dart';
import 'package:prestige_vente_app/api/models/commande_item.dart';

class DeliveryControlProvider with ChangeNotifier {
  ApiService _apiService;
  DeliveryControlProvider(this._apiService);
  void updateApiService(ApiService newApiService) { _apiService = newApiService; }

  bool _isLoading = false;
  List<Commande> _commandes = [];
  Commande? _selectedCommande;
  List<CommandeItem> _items = [];

  final Map<String, Map<String, int>> _checkedQuantitiesPerOrder = {};

  bool get isLoading => _isLoading;
  List<Commande> get commandes => _commandes;
  Commande? get selectedCommande => _selectedCommande;
  List<CommandeItem> get items => _items;

  Map<String, int> get checkedQuantities => _selectedCommande != null ? _checkedQuantitiesPerOrder[_selectedCommande!.id] ?? {} : {};

  // La fonction que votre code recherche est ici
  bool get isCurrentOrderCompleted {
    if (_selectedCommande == null) return false;
    // La commande est considérée comme "terminée" localement si
    // le statut du serveur est "TERMINE" OU si l'utilisateur vient de cocher tous les articles
    if (_selectedCommande!.statutTraitement == "TERMINE") return true;
    if (_items.isEmpty) return false;
    return checkedQuantities.length == _items.length;
  }

  bool isOrderCompleted(String orderId) {
    // Utilise orElse pour éviter les erreurs si la commande n'est pas trouvée
    final commande = _commandes.firstWhere((c) => c.id == orderId,
        orElse: () => Commande(id: '', ref: '', grossiste: '', date: '', nbreProduit: -1, prixAchatTotal: 0, statut: '', statutTraitement: "A_FAIRE"));
    return commande.statutTraitement == "TERMINE";
  }

  bool isOrderInProgress(String orderId) {
    final commande = _commandes.firstWhere((c) => c.id == orderId,
        orElse: () => Commande(id: '', ref: '', grossiste: '', date: '', nbreProduit: -1, prixAchatTotal: 0, statut: '', statutTraitement: "A_FAIRE"));
    return commande.statutTraitement == "EN_COURS";
  }

  Future<void> fetchCommandes() async {
    _isLoading = true;
    notifyListeners();
    _commandes = await _apiService.getCommandes();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> selectCommande(Commande commande) async {
    _isLoading = true;
    _selectedCommande = commande;
    _checkedQuantitiesPerOrder.putIfAbsent(commande.id, () => {});
    notifyListeners();

    _items = await _apiService.getCommandeItems(commande.id);

    for (var item in _items) {
      if (item.isChecked) {
        _checkedQuantitiesPerOrder[commande.id]![item.id] = item.checkedQuantity;
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  void updateCheckedQuantity(String detailId, int quantity) {
    if (_selectedCommande == null) return;
    _checkedQuantitiesPerOrder[_selectedCommande!.id]![detailId] = quantity;
    notifyListeners();
    _apiService.postCheckedQuantity(detailId: detailId, quantity: quantity);
  }
}