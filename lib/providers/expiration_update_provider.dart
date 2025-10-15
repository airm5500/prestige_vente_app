// lib/providers/expiration_update_provider.dart
// 15/10/2025 09:40
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/product_search_result.dart';

class ExpirationUpdateProvider with ChangeNotifier {
  ApiService _apiService;

  ExpirationUpdateProvider(this._apiService);

  void updateApiService(ApiService newApiService) {
    _apiService = newApiService;
  }

  bool _isLoading = false;
  // MODIFICATION : La liste de résultats utilise maintenant le modèle rapide
  List<ProductSearchResult> _searchResults = [];
  ProductDetails? _selectedProduct;
  String? _errorMessage;

  bool get isLoading => _isLoading;
  List<ProductSearchResult> get searchResults => _searchResults;
  ProductDetails? get selectedProduct => _selectedProduct;
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

  // MODIFICATION : La recherche utilise maintenant l'API rapide
  Future<void> search(String query) async {
    if (query.isEmpty) {
      clearSearch();
      return;
    }
    _isLoading = true;
    notifyListeners();
    // Utilise la recherche rapide
    _searchResults = await _apiService.searchProducts(query);
    _isLoading = false;
    notifyListeners();
  }

  // MODIFICATION : La sélection déclenche l'appel à l'API détaillée
  Future<void> selectProduct(ProductSearchResult product) async {
    _isLoading = true;
    _searchResults = []; // On cache la liste des résultats
    notifyListeners();

    // On appelle l'API détaillée pour obtenir toutes les infos
    final detailedResults = await _apiService.searchProductFiche(product.intCIP);
    if (detailedResults.isNotEmpty) {
      _selectedProduct = detailedResults.first;
    } else {
      _errorMessage = "Impossible de charger les détails du produit.";
    }

    _isLoading = false;
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
      produitId: _selectedProduct!.lgFamilleId,
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