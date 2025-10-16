// lib/providers/delivery_control_provider.dart
// 16/10/2025 10:20
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

  // MODIFICATION : On mémorise les quantités par ID de commande
  // Le format est : { "id_commande_1": { "id_produit_A": 10, "id_produit_B": 5 }, "id_commande_2": { ... } }
  Map<String, Map<String, int>> _checkedQuantitiesPerOrder = {};

  bool get isLoading => _isLoading;
  List<Commande> get commandes => _commandes;
  Commande? get selectedCommande => _selectedCommande;
  List<CommandeItem> get items => _items;

  // MODIFICATION : Ce getter renvoie maintenant les quantités pour la commande SÉLECTIONNÉE
  Map<String, int> get checkedQuantities => _selectedCommande != null ? _checkedQuantitiesPerOrder[_selectedCommande!.id] ?? {} : {};

  // MODIFICATION : Ce getter vérifie si la commande SÉLECTIONNÉE est terminée
  bool get isCurrentOrderCompleted {
    if (_selectedCommande == null || _items.isEmpty) return false;
    final quantities = checkedQuantities;
    return quantities.length == _items.length;
  }

  // MODIFICATION : Nouvelle fonction pour vérifier si une commande spécifique est terminée
  bool isOrderCompleted(String orderId) {
    // On trouve la commande dans la liste pour connaitre le nombre d'items attendus
    final commande = _commandes.firstWhere((c) => c.id == orderId, orElse: () => Commande(id: '', ref: '', grossiste: '', date: '', nbreProduit: -1, prixAchatTotal: 0, statut: ''));
    if (commande.nbreProduit <= 0) return false;

    final quantities = _checkedQuantitiesPerOrder[orderId] ?? {};
    return quantities.length >= commande.nbreProduit;
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
    // On ne vide plus les quantités ici, on les conserve

    // On initialise le map pour cette commande si ce n'est pas déjà fait
    _checkedQuantitiesPerOrder.putIfAbsent(commande.id, () => {});

    notifyListeners();
    _items = await _apiService.getCommandeItems(commande.id);
    _isLoading = false;
    notifyListeners();
  }

  void updateCheckedQuantity(String detailId, int quantity) {
    if (_selectedCommande == null) return;

    // On met à jour la quantité dans le map de la commande actuelle
    _checkedQuantitiesPerOrder[_selectedCommande!.id]![detailId] = quantity;
    notifyListeners();

    _apiService.postCheckedQuantity(detailId: detailId, quantity: quantity);
  }

  // MODIFICATION: New function to check for in-progress orders
  bool isOrderInProgress(String orderId) {
    final quantities = _checkedQuantitiesPerOrder[orderId] ?? {};
    // It's in progress if at least one item is checked, but it's not yet completed.
    return quantities.isNotEmpty && !isOrderCompleted(orderId);
  }
}