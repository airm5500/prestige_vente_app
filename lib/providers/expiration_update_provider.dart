// lib/providers/expiration_update_provider.dart
// 15/10/2025 23:50
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product.dart'; // Utilise le modèle de recherche rapide

class ExpirationUpdateProvider with ChangeNotifier {
  ApiService _apiService;

  ExpirationUpdateProvider(this._apiService);

  void updateApiService(ApiService newApiService) {
    _apiService = newApiService;
  }

  bool _isLoading = false;
  List<ProductSearchResult> _searchResults = [];
  // MODIFICATION : Le produit sélectionné est maintenant du type de la recherche rapide
  ProductSearchResult? _selectedProduct;
  String? _errorMessage;

  bool get isLoading => _isLoading;
  List<ProductSearchResult> get searchResults => _searchResults;
  ProductSearchResult? get selectedProduct => _selectedProduct;
  String? get errorMessage => _errorMessage;

  void clearSearch() {
    _searchResults = [];
    _selectedProduct = null;
    notifyListeners();
  }

  void clearSelection() {
    _selectedProduct = null;
    notifyListeners();
  }

  Future<void> search(String query) async {
    if (query.isEmpty) {
      clearSearch();
      return;
    }
    _isLoading = true;
    notifyListeners();
    // Utilise l'API de recherche rapide
    _searchResults = await _apiService.searchProducts(query);
    _isLoading = false;
    notifyListeners();
  }

  /// Recherche successivement chaque code (EAN-13, CIP7...) issu d'un DataMatrix
  /// et conserve les résultats du premier code qui trouve au moins un produit.
  Future<void> searchFirstMatch(List<String> queries) async {
    _isLoading = true;
    _searchResults = [];
    notifyListeners();
    for (final query in queries) {
      final results = await _apiService.searchProducts(query);
      if (results.isNotEmpty) {
        _searchResults = results;
        break;
      }
    }
    _isLoading = false;
    notifyListeners();
  }

  /// Comme [searchFirstMatch] mais sans modifier l'état de l'écran (contrôle en arrière-plan).
  Future<List<ProductSearchResult>> lookupFirstMatch(List<String> queries) async {
    for (final query in queries) {
      final results = await _apiService.searchProducts(query);
      if (results.isNotEmpty) return results;
    }
    return [];
  }

  // MODIFICATION : La sélection est maintenant une simple affectation, sans appel API
  void selectProduct(ProductSearchResult product) {
    _selectedProduct = product;
    _searchResults = []; // On cache les résultats
    notifyListeners();
  }

  Future<bool> submitUpdate({
    required String date,
    required String lot,
    required int quantity,
  }) async {
    if (_selectedProduct == null) return false;

    _isLoading = true;
    notifyListeners();

    final formattedDate = DateFormat('yyyy-MM-dd').format(DateFormat('dd/MM/yyyy').parse(date));

    final success = await _apiService.addLot(
      // MODIFICATION : Utilise l'ID du bon modèle
      produitId: _selectedProduct!.lgFAMILLEID,
      datePeremption: formattedDate,
      numLot: lot,
      quantity: quantity,
    );

    if (!success) {
      _errorMessage = "La mise à jour a échoué.";
    }

    _isLoading = false;
    notifyListeners();
    return success;
  }
}