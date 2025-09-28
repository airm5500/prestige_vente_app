// lib/providers/product_stats_provider.dart
// 28/09/2025 02:22
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product_stats.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';

class ProductStatsProvider with ChangeNotifier {
  final ApiService _apiService;

  ProductStatsProvider(SettingsProvider settingsProvider)
      : _apiService = ApiService(baseUrl: settingsProvider.baseUrl);

  // --- ETAT ---
  bool _isLoading = false;
  List<ProductAnnualSale> _searchResults = [];
  ProductAnnualSale? _selectedProductSales;
  ProductInfo? _selectedProductInfo;

  // Données pour le graphique comparatif
  List<ProductAnnualSale> _comparisonData = [];
  bool _isComparisonLoading = false;
  bool _showComparisonChart = false;

  // --- GETTERS ---
  bool get isLoading => _isLoading;
  List<ProductAnnualSale> get searchResults => _searchResults;
  ProductAnnualSale? get selectedProductSales => _selectedProductSales;
  ProductInfo? get selectedProductInfo => _selectedProductInfo;
  List<ProductAnnualSale> get comparisonData => _comparisonData;
  bool get isComparisonLoading => _isComparisonLoading;
  bool get showComparisonChart => _showComparisonChart;

  // --- ACTIONS ---

  /// Efface la recherche et la sélection
  void clear() {
    _searchResults = [];
    _selectedProductSales = null;
    _selectedProductInfo = null;
    _comparisonData = [];
    _showComparisonChart = false;
    notifyListeners();
  }

  /// Recherche des produits
  Future<void> searchProducts(String query) async {
    // La recherche doit se faire a partir de 2 caracteres pour le nom ou 3 pour le cip
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

  /// Sélectionne un produit et charge ses détails
  Future<void> selectProduct(ProductAnnualSale productSales) async {
    _setLoading(true);
    _showComparisonChart = false; // Cache le graphique lors d'une nouvelle sélection
    _comparisonData = [];

    _selectedProductSales = productSales;
    // Charge les infos complémentaires (prix, emplacement...)
    _selectedProductInfo = await _apiService.getProductInfo(productSales.codeCip);

    _setLoading(false);
  }

  /// Charge les données des 2 années précédentes pour la comparaison
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

    // Ajoute l'année en cours aux données de comparaison
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