// lib/providers/product_stats_provider.dart
// 28/09/2025 03:33
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product_stats.dart';

class ProductStatsProvider with ChangeNotifier {
  final ApiService _apiService;

  ProductStatsProvider(this._apiService);

  bool _isLoading = false;
  List<ProductAnnualSale> _searchResults = [];
  ProductAnnualSale? _selectedProductSales;
  ProductInfo? _selectedProductInfo;
  List<ProductAnnualSale> _comparisonData = [];
  bool _isComparisonLoading = false;
  bool _showComparisonChart = false;

  bool get isLoading => _isLoading;
  List<ProductAnnualSale> get searchResults => _searchResults;
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
    _searchResults = await _apiService.getAnnualSales(query, DateTime.now().year);
    _setLoading(false);
  }

  Future<void> selectProduct(ProductAnnualSale productSales) async {
    _setLoading(true);
    _showComparisonChart = false;
    _comparisonData = [];
    _selectedProductSales = productSales;
    _selectedProductInfo = await _apiService.getProductInfo(productSales.codeCip);
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