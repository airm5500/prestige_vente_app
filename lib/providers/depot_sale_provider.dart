// lib/providers/depot_sale_provider.dart
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/depot_model.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart'; // Pour SaleLine


class DepotSaleProvider with ChangeNotifier {
  final ApiService _apiService;

  // État de la vente en cours
  String? _currentSaleId;
  String? get currentSaleId => _currentSaleId;

  // AJOUT : Variable pour stocker la référence visible (ex: 260127_00005)
  String? _currentSaleRef;
  String? get currentSaleRef => _currentSaleRef;

  DepotModel? _selectedDepot;
  DepotModel? get selectedDepot => _selectedDepot;

  List<SaleLine> _cartItems = [];
  List<SaleLine> get cartItems => _cartItems;

  bool _isLoading = false;
  bool get isLoading => _isLoading;
  String _errorMessage = '';
  String get errorMessage => _errorMessage;

  int _totalAmount = 0;
  int get totalAmount => _totalAmount;

  DepotSaleProvider(this._apiService);

  // --- Gestion du Dépôt (Client) ---
  void selectDepot(DepotModel depot) {
    _selectedDepot = depot;
    notifyListeners();
  }

  void resetSale() {
    _currentSaleId = null;
    _selectedDepot = null;
    _cartItems = [];
    _totalAmount = 0;
    _errorMessage = '';
    _currentSaleRef = null; // Reset de la ref
    notifyListeners();
  }

  // --- Actions Vente ---

  // Initialiser une vente existante (Modification)
  Future<void> loadExistingSale(String saleId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final data = await _apiService.getDepotSaleDetails(saleId);
      if (data != null) {
        _currentSaleId = saleId;
        _currentSaleRef = data['strREF'];

        // Reconstitution de l'objet DepotModel à partir des détails de la vente
        // Note: Le backend renvoie l'objet 'magasin' qui correspond aux infos du dépôt
        if (data['magasin'] != null) {
          _selectedDepot = DepotModel.fromJson(data['magasin']);
        }

        await _refreshCart();
      }
    } catch (e) {
      _errorMessage = "Impossible de charger la vente";
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Ajouter un produit (Logique conditionnelle)
  Future<bool> addProduct(ProductSearchResult product, int quantity) async {
    if (_selectedDepot == null) {
      _errorMessage = "Veuillez sélectionner un dépôt d'abord.";
      notifyListeners();
      return false;
    }

    _isLoading = true;
    notifyListeners();
    bool success = false;

    try {
      if (_currentSaleId == null) {
        // PREMIER AJOUT -> Création de la vente (/vente/add/depot)
        final result = await _apiService.addFirstDepotItem(
          clientId: _selectedDepot!.lgCLIENTID,
          emplacementId: _selectedDepot!.lgEMPLACEMENTID,
          typeDepotId: _selectedDepot!.lgTYPEDEPOTID,
          produitId: product.lgFAMILLEID,
          itemPu: product.intPRICE,
          qte: quantity,
        );

        if (result != null && result['lgPREENREGISTREMENTID'] != null) {
          _currentSaleId = result['lgPREENREGISTREMENTID'];
          _currentSaleRef = result['strREF'];
          success = true;
        }
      } else {
        // AJOUT SUIVANT -> (/vente/add/item)
        success = await _apiService.addNextDepotItem(
          venteId: _currentSaleId!,
          clientId: _selectedDepot!.lgCLIENTID,
          emplacementId: _selectedDepot!.lgEMPLACEMENTID,
          typeDepotId: _selectedDepot!.lgTYPEDEPOTID,
          produitId: product.lgFAMILLEID,
          itemPu: product.intPRICE,
          qte: quantity,
        );
      }

      if (success) {
        await _refreshCart();
      } else {
        _errorMessage = "Erreur lors de l'ajout du produit";
      }
    } catch (e) {
      _errorMessage = "Erreur technique: $e";
      success = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return success;
  }

  // Mettre à jour (Quantité ou Prix)
  Future<bool> updateItem(SaleLine item, int newQty, int newPrice) async {
    _isLoading = true;
    notifyListeners();

    final success = await _apiService.updateDepotItem(
      itemId: item.lgPREENREGISTREMENTDETAILID,
      produitId: item.lgFAMILLEID,
      itemPu: newPrice, // Le backend permet de modifier le prix (cf logs)
      qte: newQty,
    );

    if (success) {
      await _refreshCart();
    } else {
      _errorMessage = "Impossible de modifier la ligne";
    }

    _isLoading = false;
    notifyListeners();
    return success;
  }

  // Supprimer un article
  Future<bool> removeItem(String itemId) async {
    _isLoading = true;
    notifyListeners();

    final success = await _apiService.removeDepotItem(itemId);

    if (success) {
      await _refreshCart();
    } else {
      _errorMessage = "Impossible de supprimer la ligne";
    }

    _isLoading = false;
    notifyListeners();
    return success;
  }

  // Clôturer la vente
  Future<bool> closeSale() async {
    if (_currentSaleId == null || _selectedDepot == null) return false;

    _isLoading = true;
    notifyListeners();

    final success = await _apiService.closeDepotSale(
      venteId: _currentSaleId!,
      clientId: _selectedDepot!.lgCLIENTID,
    );

    if (success) {
      // Si succès, on reset tout pour la prochaine vente
      resetSale();
    } else {
      _errorMessage = "Erreur lors de la clôture de la vente";
    }

    _isLoading = false;
    notifyListeners();
    return success;
  }

  // Méthode interne pour recharger le panier complet
  Future<void> _refreshCart() async {
    if (_currentSaleId == null) return;

    // Récupérer les items (/vente/deatails)
    final items = await _apiService.fetchSaleItems(_currentSaleId!);
    _cartItems = items;

    // Recalcul du total localement ou via les items
    _totalAmount = items.fold(0, (sum, item) => sum + item.intPRICE);

    notifyListeners();
  }
}