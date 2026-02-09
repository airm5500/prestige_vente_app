import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/depot_model.dart';
import 'package:prestige_vente_app/api/models/product.dart';
//import 'package:prestige_vente_app/api/models/product_search_result.dart'; // Assurez-vous d'importer ceci
import 'package:prestige_vente_app/api/models/sale.dart';

class DepotSaleProvider with ChangeNotifier {
  final ApiService _apiService;

  // État de la vente
  String? _currentSaleId;
  String? get currentSaleId => _currentSaleId;
  String? _currentSaleRef;
  String? get currentSaleRef => _currentSaleRef;

  DepotModel? _selectedDepot;
  DepotModel? get selectedDepot => _selectedDepot;

  List<SaleLine> _cartItems = [];
  List<SaleLine> get cartItems => _cartItems;

  // --- NOUVEAU : GESTION RECHERCHE ---
  List<ProductSearchResult> _searchResults = [];
  List<ProductSearchResult> get searchResults => _searchResults;

  bool _isLoading = false;
  bool get isLoading => _isLoading;
  String _errorMessage = '';
  String get errorMessage => _errorMessage;

  int _totalAmount = 0;
  int get totalAmount => _totalAmount;

  bool _isQuickScanMode = false;
  bool get isQuickScanMode => _isQuickScanMode;

  DepotSaleProvider(this._apiService);

  void toggleQuickScanMode() {
    _isQuickScanMode = !_isQuickScanMode;
    notifyListeners();
  }

  // --- Recherche Produits ---
  Future<void> searchProducts(String query) async {
    _isLoading = true;
    notifyListeners();
    try {
      // Appel à l'API pour chercher
      _searchResults = await _apiService.searchProducts(query);
    } catch (e) {
      _searchResults = [];
      _errorMessage = "Erreur recherche: $e";
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearSearchResults() {
    _searchResults = [];
    notifyListeners();
  }

  // --- Gestion Dépôt ---
  void selectDepot(DepotModel depot) {
    _selectedDepot = depot;
    notifyListeners();
  }

  void resetSale() {
    _currentSaleId = null;
    _selectedDepot = null;
    _cartItems = [];
    _searchResults = [];
    _totalAmount = 0;
    _errorMessage = '';
    _currentSaleRef = null;
    notifyListeners();
  }

  Future<void> loadExistingSale(String saleId) async {
    _isLoading = true;
    notifyListeners();
    try {
      final data = await _apiService.getDepotSaleDetails(saleId);
      if (data != null) {
        _currentSaleId = saleId;
        _currentSaleRef = data['strREF'];
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

  // --- Ajout au Panier (Alias pour compatibilité) ---
  // L'écran appelle often 'addToCart(product, qty: x)', on adapte ici
  Future<bool> addToCart(ProductSearchResult product, {int qty = 1}) async {
    return _addProductInternal(product, qty);
  }

  // Logique interne d'ajout (anciennement addProduct)
  Future<bool> _addProductInternal(ProductSearchResult product, int quantity) async {
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
        // Premier ajout -> Création vente
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
        // Ajout suivant
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

  // --- Modification / Suppression ---
  Future<bool> updateItem(SaleLine item, int newQty, int newPrice) async {
    _isLoading = true;
    notifyListeners();
    final success = await _apiService.updateDepotItem(
      itemId: item.lgPREENREGISTREMENTDETAILID,
      produitId: item.lgFAMILLEID,
      itemPu: newPrice,
      qte: newQty,
    );
    if (success) await _refreshCart();
    else _errorMessage = "Impossible de modifier la ligne";
    _isLoading = false;
    notifyListeners();
    return success;
  }

  Future<bool> removeItem(String itemId) async {
    _isLoading = true;
    notifyListeners();
    final success = await _apiService.removeDepotItem(itemId);
    if (success) await _refreshCart();
    else _errorMessage = "Impossible de supprimer la ligne";
    _isLoading = false;
    notifyListeners();
    return success;
  }

  Future<bool> closeSale() async {
    if (_currentSaleId == null || _selectedDepot == null) return false;
    _isLoading = true;
    notifyListeners();
    final success = await _apiService.closeDepotSale(
      venteId: _currentSaleId!,
      clientId: _selectedDepot!.lgCLIENTID,
    );
    if (success) resetSale();
    else _errorMessage = "Erreur lors de la clôture";
    _isLoading = false;
    notifyListeners();
    return success;
  }

  Future<void> _refreshCart() async {
    if (_currentSaleId == null) return;
    final items = await _apiService.fetchSaleItems(_currentSaleId!);
    _cartItems = items;
    _totalAmount = items.fold(0, (sum, item) => sum + item.intPRICE);
    notifyListeners();
  }

  // --- GESTION DE LA LISTE DES VENTES EN COURS ---

  // CORRECTION : On utilise le bon type 'DepotSaleListItem'
  List<DepotSaleListItem> _ongoingSales = [];
  List<DepotSaleListItem> get ongoingSales => _ongoingSales;

  Future<void> fetchOngoingSales() async {
    _isLoading = true;
    notifyListeners();
    try {
      // 1. Récupération brute depuis l'API
      final rawList = await _apiService.fetchDepotSales();

      // 2. FILTRE MAGIQUE : On ne garde que les ventes ayant un montant > 0
      // CORRECTION : On utilise '.intPRICE' qui est le champ réel du modèle
      _ongoingSales = rawList.where((sale) => sale.intPRICE > 0).toList();

    } catch (e) {
      _errorMessage = "Erreur chargement liste: $e";
      _ongoingSales = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteCurrentSale() async {
    if (_currentSaleId != null) {
      await _apiService.deleteSale(_currentSaleId!); // Appel API
      resetSale(); // Nettoyage local
    }
  }
}