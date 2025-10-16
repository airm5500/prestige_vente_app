// lib/providers/delivery_control_provider.dart
// 16/10/2025 10:57
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

  // MODIFICATION : Ce Map ne sert plus qu'à stocker les NOUVELLES saisies
  Map<String, Map<String, int>> _checkedQuantitiesPerOrder = {};

  bool get isLoading => _isLoading;
  List<Commande> get commandes => _commandes;
  Commande? get selectedCommande => _selectedCommande;
  List<CommandeItem> get items => _items;

  Map<String, int> get checkedQuantities => _selectedCommande != null ? _checkedQuantitiesPerOrder[_selectedCommande!.id] ?? {} : {};

  // MODIFICATION : La logique utilise maintenant les données du serveur
  bool get isCurrentOrderCompleted {
    if (_selectedCommande == null) return false;
    // On vérifie le statut de la commande chargée depuis le serveur
    return _selectedCommande!.isChecked;
  }

  bool isOrderCompleted(String orderId) {
    final commande = _commandes.firstWhere((c) => c.id == orderId, orElse: () => Commande(id: '', ref: '', grossiste: '', date: '', nbreProduit: -1, prixAchatTotal: 0, statut: '', isChecked: false));
    return commande.isChecked;
  }

  bool isOrderInProgress(String orderId) {
    final quantities = _checkedQuantitiesPerOrder[orderId] ?? {};
    // En cours si on a commencé à saisir mais que la commande n'est pas marquée comme terminée par le serveur
    return quantities.isNotEmpty && !isOrderCompleted(orderId);
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

    // MODIFICATION : On pré-remplit les quantités avec les données du serveur
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