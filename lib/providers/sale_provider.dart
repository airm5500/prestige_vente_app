// lib/providers/sale_provider.dart
// 28/09/2025 02:15
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';

class SaleProvider with ChangeNotifier {
  final ApiService _apiService;
  final ApiService apiService; // Public getter for easy access from UI

  SaleProvider(SettingsProvider settingsProvider)
      : _apiService = ApiService(baseUrl: settingsProvider.baseUrl),
        apiService = ApiService(baseUrl: settingsProvider.baseUrl);

  // --- ETAT ---
  bool _isLoading = false;
  String? _errorMessage;
  String? _currentVenteId;
  List<SaleItemDetail> _cartItems = [];
  SaleSummary _saleSummary = SaleSummary();
  List<ProductSearchResult> _searchResults = [];

  // --- GETTERS ---
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get currentVenteId => _currentVenteId;
  List<SaleItemDetail> get cartItems => _cartItems;
  SaleSummary get saleSummary => _saleSummary;
  List<ProductSearchResult> get searchResults => _searchResults;

  // --- ACTIONS ---

  /// Réinitialise l'état pour une nouvelle vente
  void startNewSale() {
    _currentVenteId = null;
    _cartItems = [];
    _saleSummary = SaleSummary();
    _searchResults = [];
    _errorMessage = null;
    notifyListeners();
  }

  /// Recherche de produits
  Future<void> searchProducts(String query) async {
    if (query.length < 3) {
      _searchResults = [];
      notifyListeners();
      return;
    }
    _setLoading(true);
    _searchResults = await _apiService.searchProducts(query);
    _setLoading(false);
  }

  /// Ajoute un produit au panier
  Future<void> addProductToCart(ProductSearchResult product, int quantity, {bool isPrevente = false}) async {
    _setLoading(true);

    final newVenteId = await _apiService.addItemToSale(
        produitId: product.lgFAMILLEID,
        qte: quantity,
        itemPu: product.intPRICE,
        venteId: _currentVenteId,
        isPrevente: isPrevente);

    if (newVenteId != null) {
      _currentVenteId = newVenteId;
      await _refreshCartAndSummary();
    } else {
      _errorMessage = "Erreur lors de l'ajout du produit.";
    }
    _setLoading(false);
  }

  /// Supprime un produit du panier
  Future<void> removeProductFromCart(String itemId) async {
    _setLoading(true);
    final success = await _apiService.removeItemFromSale(itemId);
    if (success) {
      await _refreshCartAndSummary();
    } else {
      _errorMessage = "Erreur lors de la suppression.";
    }
    _setLoading(false);
  }

  /// Met à jour un produit dans le panier
  Future<void> updateCartItem(SaleItemDetail item, int newQuantity, int newPrice) async {
    _setLoading(true);
    final success = await _apiService.updateSaleItem(
        itemId: item.lgPREENREGISTREMENTDETAILID,
        produitId: item.lgFAMILLEID,
        qte: newQuantity,
        itemPu: newPrice);

    if (success) {
      await _refreshCartAndSummary();
    } else {
      _errorMessage = "Erreur de mise à jour.";
    }
    _setLoading(false);
  }

  /// Clôture la vente
  Future<bool> cloturerVente(PaymentMethod paymentMethod) async {
    if (_currentVenteId == null) return false;
    _setLoading(true);

    final clientId = paymentMethod.name.toLowerCase().replaceAll(' ', '').replaceAll('é', 'e');

    final success = await _apiService.cloturerVente(
      venteId: _currentVenteId!,
      summary: _saleSummary,
      typeReglementId: paymentMethod.id,
      clientId: clientId,
    );

    if (!success) {
      _errorMessage = "La clôture de la vente a échoué.";
    }
    _setLoading(false);
    return success;
  }

  /// Termine la prévente
  Future<bool> terminerPrevente() async {
    if (_currentVenteId == null) return false;
    _setLoading(true);
    final success = await _apiService.terminerPrevente(_currentVenteId!);
    if (!success) {
      _errorMessage = "La finalisation de la prévente a échoué.";
    }
    _setLoading(false);
    return success;
  }

  /// Charge une prévente existante dans l'écran de vente
  Future<void> loadPrevente(String preventeId) async {
    _setLoading(true);
    startNewSale(); // On réinitialise l'état au cas où

    _currentVenteId = preventeId;
    await _refreshCartAndSummary(); // On charge les données de la prévente

    _setLoading(false);
  }

  // --- Méthodes privées ---

  /// Rafraîchit le panier et le résumé de la vente
  Future<void> _refreshCartAndSummary() async {
    if (_currentVenteId != null) {
      final results = await Future.wait([
        _apiService.getSaleDetails(_currentVenteId!),
        _apiService.calculateNet(_currentVenteId!),
      ]);
      _cartItems = results[0] as List<SaleItemDetail>;
      _saleSummary = (results[1] as SaleSummary?) ?? _saleSummary;
      _errorMessage = null;
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}