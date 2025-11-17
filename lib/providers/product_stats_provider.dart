// lib/providers/product_stats_provider.dart
// 09/11/2025 21:00 (Standardisation de la recherche)
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product_info.dart';
import 'package:prestige_vente_app/api/models/product_stats.dart';
// MODIFICATION : Import du modèle de recherche standard
import 'package:prestige_vente_app/api/models/product.dart';

class ProductStatsProvider with ChangeNotifier {
  ApiService _apiService;
  ProductStatsProvider(this._apiService);
  void updateApiService(ApiService newApiService) { _apiService = newApiService; }

  bool _isLoading = false;
  // MODIFICATION : Le résultat de recherche utilise le modèle standard
  List<ProductSearchResult> _searchResults = [];
  ProductAnnualSale? _selectedProductSales;
  ProductInfo? _selectedProductInfo;
  List<ProductAnnualSale> _comparisonData = [];
  bool _isComparisonLoading = false;
  bool _showComparisonChart = false;

  bool get isLoading => _isLoading;
  // MODIFICATION : Le getter renvoie le type standard
  List<ProductSearchResult> get searchResults => _searchResults;
  ProductAnnualSale? get selectedProductSales => _selectedProductSales;
  ProductInfo? get selectedProductInfo => _selectedProductInfo;
  List<ProductAnnualSale> get comparisonData => _comparisonData;
  bool get isComparisonLoading => _isComparisonLoading;
  bool get showComparisonChart => _showComparisonChart;

  void clear() {
    _searchResults = [];
    _selectedProductSales = null;
    _selectedProductInfo = null;
    _comparisonData = [];
    _showComparisonChart = false;
    notifyListeners();
  }

  Future<void> searchProducts(String query) async {
    bool isCip = int.tryParse(query) != null;
    if ((isCip && query.length < 3) || (!isCip && query.length < 2)) {
      _searchResults = [];
      notifyListeners();
      return;
    }
    _setLoading(true);
    // MODIFICATION : Utilise l'API de recherche standard
    _searchResults = await _apiService.searchProducts(query);
    _setLoading(false);
  }

  // MODIFICATION : La sélection se fait depuis un ProductSearchResult
  Future<void> selectProduct(ProductSearchResult product) async {
    _setLoading(true);
    _showComparisonChart = false;
    _comparisonData = [];
    _searchResults = []; // Cache la liste de recherche
    notifyListeners();

    // Charge les données spécifiques à cet écran (Stats et Info)
    final results = await Future.wait([
      _apiService.getAnnualSales(product.intCIP, DateTime.now().year),
      _apiService.getProductInfoForStats(product.intCIP)
    ]);

    final salesData = results[0] as List<ProductAnnualSale>;
    _selectedProductSales = salesData.isNotEmpty ? salesData.first : null;
    _selectedProductInfo = results[1] as ProductInfo?;

    _setLoading(false);
  }


  Future<void> loadComparisonData() async {
    if (_selectedProductSales == null) return;
    _isComparisonLoading = true;
    notifyListeners();
    final currentYear = DateTime.now().year;
    final yearsToFetch = [currentYear - 1, currentYear - 2];
    final List<ProductAnnualSale> historicData = [];
    for (int year in yearsToFetch) {
      final result = await _apiService.getAnnualSales(_selectedProductSales!.codeCip, year);
      if (result.isNotEmpty) {
        historicData.add(result.first);
      }
    }
    _comparisonData = [_selectedProductSales!, ...historicData];
    _showComparisonChart = true;
    _isComparisonLoading = false;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}