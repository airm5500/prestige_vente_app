// lib/providers/product_update_provider.dart
// 29/10/2025 23:30
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/rayon.dart';
// MODIFICATION : Import pour les détails du produit
import 'package:prestige_vente_app/api/models/product_search_result.dart';

class ProductUpdateProvider with ChangeNotifier {
  ApiService _apiService;
  ProductUpdateProvider(this._apiService);
  void updateApiService(ApiService newApiService) { _apiService = newApiService; }

  bool _isLoading = false;
  List<ProductSearchResult> _searchResults = [];
  ProductSearchResult? _selectedProduct;
  // MODIFICATION : Ajout pour stocker les détails (qui contiennent l'EAN)
  ProductDetails? _selectedProductDetails;
  List<Rayon> _rayons = [];
  bool _rayonsLoaded = false;
  String? _errorMessage;

  bool get isLoading => _isLoading;
  List<ProductSearchResult> get searchResults => _searchResults;
  ProductSearchResult? get selectedProduct => _selectedProduct;
  // MODIFICATION : Getter pour les détails
  ProductDetails? get selectedProductDetails => _selectedProductDetails;
  List<Rayon> get rayons => _rayons;
  String? get errorMessage => _errorMessage;

  void clearAll() {
    _searchResults = [];
    _selectedProduct = null;
    _selectedProductDetails = null; // MODIFICATION
    _errorMessage = null;
    notifyListeners();
  }

  void clearSelection() {
    _selectedProduct = null;
    _selectedProductDetails = null; // MODIFICATION
    notifyListeners();
  }

  Future<void> search(String query) async {
    if (query.length < 3) {
      _searchResults = [];
      notifyListeners();
      return;
    }
    _isLoading = true;
    _selectedProduct = null;
    _selectedProductDetails = null; // MODIFICATION
    notifyListeners();
    _searchResults = await _apiService.searchProducts(query);
    _isLoading = false;
    notifyListeners();
  }

  // MODIFICATION : La sélection charge maintenant les détails complets
  Future<void> selectProduct(ProductSearchResult product) async {
    _isLoading = true;
    _selectedProduct = product;
    _selectedProductDetails = null; // On efface les anciens détails
    _searchResults = [];
    notifyListeners(); // Affiche le chargement et cache les résultats

    // On charge les détails (qui contiennent 'intEan13')
    _selectedProductDetails = await _apiService.getProductDetailsForSearch(product.intCIP);

    _isLoading = false;
    notifyListeners(); // Affiche le formulaire avec les détails
  }

  Future<bool> updateEAN(String ean) async {
    if (_selectedProduct == null) return false;
    _isLoading = true;
    notifyListeners();

    final success = await _apiService.updateLiteInfo({
      "id": _selectedProduct!.lgFAMILLEID,
      "codeEanFabriquant": ean,
    });

    _isLoading = false;
    if (!success) _errorMessage = "Échec de la mise à jour EAN.";
    notifyListeners();
    return success;
  }

  Future<void> loadRayons() async {
    if (_rayonsLoaded) return;
    _isLoading = true;
    notifyListeners();
    _rayons = await _apiService.getRayons();
    _rayonsLoaded = true;
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> updateEmplacement(String rayonId) async {
    if (_selectedProduct == null) return false;
    _isLoading = true;
    notifyListeners();

    final success = await _apiService.updateLiteInfo({
      "id": _selectedProduct!.lgFAMILLEID,
      "rayonId": rayonId,
    });

    _isLoading = false;
    if (!success) _errorMessage = "Échec de la mise à jour de l'emplacement.";
    notifyListeners();
    return success;
  }
}