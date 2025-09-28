// lib/providers/sale_provider.dart
// 28/09/2025 19:48
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/api/models/user.dart';

class SaleProvider with ChangeNotifier {
  final ApiService _apiService;
  ApiService get apiService => _apiService;

  SaleProvider(this._apiService);

  bool _isLoading = false;
  String? _errorMessage;
  String? _currentVenteId;
  List<SaleItemDetail> _cartItems = [];
  SaleSummary _saleSummary = SaleSummary();
  List<ProductSearchResult> _searchResults = [];
  List<PreventeListItem> _preventes = [];
  bool _isLoadingPreventes = false;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get currentVenteId => _currentVenteId;
  List<SaleItemDetail> get cartItems => _cartItems;
  SaleSummary get saleSummary => _saleSummary;
  List<ProductSearchResult> get searchResults => _searchResults;
  List<PreventeListItem> get preventes => _preventes;
  bool get isLoadingPreventes => _isLoadingPreventes;

  Future<void> fetchPreventes() async {
    _isLoadingPreventes = true;
    // CORRECTION : On vide la liste avant de notifier l'UI du chargement.
    // L'ancienne liste ne sera plus affichée pendant le rafraîchissement.
    _preventes.clear();
    notifyListeners();

    List<PreventeListItem> fetchedPreventes = await _apiService.getPreventes();

    fetchedPreventes.sort((a, b) {
      try {
        final format = DateFormat('dd/MM/yyyy HH:mm:ss');
        final dateTimeA = format.parse('${a.dtUPDATED} ${a.heure}');
        final dateTimeB = format.parse('${b.dtUPDATED} ${b.heure}');
        return dateTimeB.compareTo(dateTimeA);
      } catch (e) {
        return 0;
      }
    });

    _preventes = fetchedPreventes;
    _isLoadingPreventes = false;
    notifyListeners();
  }

  void startNewSale() {
    _currentVenteId = null;
    _cartItems = [];
    _saleSummary = SaleSummary();
    _searchResults = [];
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> searchProducts(String query) async {
    if (query.length < 3) {
      _searchResults = [];
      notifyListeners();
      return;
    }
    _setLoading(true);
    _searchResults.clear();
    _searchResults = await _apiService.searchProducts(query);
    _setLoading(false);
  }

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

  Future<bool> cloturerVente(PaymentMethod paymentMethod, User currentUser) async {
    if (_currentVenteId == null) return false;
    _setLoading(true);

    final clientId = paymentMethod.name.toLowerCase().replaceAll(' ', '').replaceAll('é', 'e');

    await _apiService.updateClientForSale(_currentVenteId!, clientId);

    final success = await _apiService.cloturerVente(
      venteId: _currentVenteId!,
      summary: _saleSummary,
      typeReglementId: paymentMethod.id,
      clientId: clientId,
      userVendeurId: currentUser.userId,
    );

    if (!success) {
      _errorMessage = "La clôture de la vente a échoué. Vérifiez les logs du serveur.";
    }

    _setLoading(false);
    return success;
  }

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

  Future<void> loadPrevente(String preventeId) async {
    _setLoading(true);
    startNewSale();
    _currentVenteId = preventeId;
    await _refreshCartAndSummary();
    _setLoading(false);
  }

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