// lib/providers/delivery_control_provider.dart
// 18/10/2025 14:30
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_horsligne.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_models.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/commande.dart';
import 'package:prestige_vente_app/api/models/commande_item.dart';
import 'package:prestige_vente_app/providers/quantity_sync.dart';

class DeliveryControlProvider with ChangeNotifier, QuantitySync {
  ApiService _apiService;
  DeliveryControlProvider(this._apiService);
  void updateApiService(ApiService newApiService) { _apiService = newApiService; }

  bool _isLoading = false;

  /// Message si le dernier chargement des commandes a échoué (null si chargé, même vide).
  String? _loadError;
  String? get loadError => _loadError;

  /// Message si le chargement des produits de la commande ouverte a échoué.
  String? _itemsError;
  String? get itemsError => _itemsError;
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
    _loadError = null;
    notifyListeners();
    try {
      // Hors ligne : copie locale (H3) ; en ligne : inchangé.
      _commandes = HorsLigne.instance.offline ? await StockHorsLigne.instance.commandesEnCours() : await _apiService.getCommandes();
    } catch (e) {
      // La liste précédente reste affichée ; l'écran montre l'erreur avec « Réessayer ».
      _loadError = e is ApiLoadException || e is StockHorsLigneException ? '$e' : 'Impossible de charger les commandes : $e';
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> selectCommande(Commande commande) async {
    _isLoading = true;
    _selectedCommande = commande;
    _checkedQuantitiesPerOrder.putIfAbsent(commande.id, () => {});
    _itemsError = null;
    _items = [];
    notifyListeners();

    try {
      _items = HorsLigne.instance.offline
          ? await StockHorsLigne.instance.commandeItems(commande.id)
          : await _apiService.getCommandeItems(commande.id);
    } catch (e) {
      _itemsError = e is ApiLoadException || e is StockHorsLigneException ? '$e' : 'Impossible de charger les produits : $e';
    }

    for (var item in _items) {
      if (item.isChecked) {
        _checkedQuantitiesPerOrder[commande.id]![item.id] = item.checkedQuantity;
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  @override
  int? localQuantity(String detailId) {
    for (final m in _checkedQuantitiesPerOrder.values) {
      if (m.containsKey(detailId)) return m[detailId];
    }
    return null;
  }

  /// Enregistre la quantité localement puis attend le serveur ; `false` si elle n'est pas enregistrée.
  Future<bool> updateCheckedQuantity(String detailId, int quantity) async {
    if (_selectedCommande == null) return false;
    _checkedQuantitiesPerOrder[_selectedCommande!.id]![detailId] = quantity;
    notifyListeners();
    final orderId = _selectedCommande!.id;
    return sendQuantity(detailId, quantity, () => _post(detailId, quantity, orderId));
  }

  /// En ligne : envoi au serveur (inchangé). Hors ligne : file des opérations (envoyée plus tard).
  Future<bool> _post(String detailId, int quantity, [String? orderId]) async {
    if (!HorsLigne.instance.offline) return _apiService.postCheckedQuantity(detailId: detailId, quantity: quantity);
    await StockHorsLigne.instance.pointerCommande(orderId, detailId, quantity);
    return true;
  }

  Future<int> retryUnsyncedQuantities() => retryUnsynced((id, q) => _post(id, q));
}