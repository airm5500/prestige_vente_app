// lib/providers/product_search_provider.dart
// 09/11/2025 21:15 (Correction Grossiste manquant)
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/product_info.dart';
import 'package:prestige_vente_app/api/models/product_stats.dart';
import 'package:prestige_vente_app/api/models/product_search_result.dart';

class MonthlyComparisonData {
  final int sales;
  final int orders;
  final int orderFrequency;
  MonthlyComparisonData({this.sales = 0, this.orders = 0, this.orderFrequency = 0});
}

class ProductSearchProvider with ChangeNotifier {
  ApiService _apiService;
  ProductSearchProvider(this._apiService);
  void updateApiService(ApiService newApiService) { _apiService = newApiService; }

  bool _isLoading = false;

  List<ProductSearchResult> _searchResults = [];
  ProductInfo? _selectedProductInfo;
  ProductDetails? _selectedProductDetails;
  List<MonthlyComparisonData> _comparisonData = [];

  bool get isLoading => _isLoading;
  List<ProductSearchResult> get searchResults => _searchResults;
  ProductInfo? get selectedProductInfo => _selectedProductInfo;
  ProductDetails? get selectedProductDetails => _selectedProductDetails;
  List<MonthlyComparisonData> get comparisonData => _comparisonData;
  bool get hasComparisonData => _comparisonData.isNotEmpty;

  void clear() {
    _searchResults = [];
    _selectedProductInfo = null;
    _selectedProductDetails = null;
    _comparisonData = [];
    notifyListeners();
  }

  Future<void> search(String query) async {
    if (query.isEmpty) {
      clear();
      return;
    }
    _isLoading = true;
    _selectedProductInfo = null;
    _selectedProductDetails = null;
    notifyListeners();

    _searchResults = await _apiService.searchProducts(query);
    _isLoading = false;
    notifyListeners();
  }

  // MODIFICATION : Corrigé pour charger TOUTES les infos
  Future<void> selectProduct(ProductSearchResult product) async {
    _isLoading = true;
    _searchResults = [];
    _selectedProductInfo = null; // Efface l'ancien
    notifyListeners();

    // Appelle les 3 APIs en parallèle
    final results = await Future.wait([
      // 1. Récupère les infos de base (dont 'grossiste')
      _apiService.getProductInfo(product.intCIP),
      // 2. Récupère les détails (pour 'ean', etc.)
      _apiService.getProductDetailsForSearch(product.intCIP),
      // 3. Charge les données du graphique
      _loadComparisonData(product.lgFAMILLEID, product.intCIP),
    ]);

    // Assigne les résultats
    _selectedProductInfo = results[0] as ProductInfo?;
    _selectedProductDetails = results[1] as ProductDetails?;
    _comparisonData = results[2] as List<MonthlyComparisonData>;

    _isLoading = false;
    notifyListeners();
  }
  // FIN MODIFICATION

  Future<List<MonthlyComparisonData>> _loadComparisonData(String productId, String cip) async {
    final year = DateTime.now().year;
    final startDate = '$year-01-01';
    final endDate = '$year-12-31';

    final results = await Future.wait([
      _apiService.getProductOrderHistory(productId, startDate, endDate),
      _apiService.getAnnualSales(cip, year),
    ]);

    final orders = results[0] as List<ProductOrderHistory>;
    final salesData = results[1] as List<ProductAnnualSale>;
    final sales = salesData.isNotEmpty ? salesData.first.monthlySales : <String, int>{};

    List<MonthlyComparisonData> monthlyData = List.generate(12, (_) => MonthlyComparisonData());

    for (var order in orders) {
      try {
        final date = DateFormat('dd/MM/yyyy HH:mm').parse(order.dtEntree);
        final monthIndex = date.month - 1;
        monthlyData[monthIndex] = MonthlyComparisonData(
          sales: monthlyData[monthIndex].sales,
          orders: monthlyData[monthIndex].orders + order.intNumber,
          orderFrequency: monthlyData[monthIndex].orderFrequency + 1,
        );
      } catch (e) { print("Could not parse date: ${order.dtEntree}"); }
    }

    sales.forEach((monthName, salesCount) {
      final monthIndex = _monthNameToInt(monthName);
      if(monthIndex != -1) {
        monthlyData[monthIndex] = MonthlyComparisonData(
          sales: salesCount,
          orders: monthlyData[monthIndex].orders,
          orderFrequency: monthlyData[monthIndex].orderFrequency,
        );
      }
    });

    return monthlyData;
  }

  int _monthNameToInt(String name) {
    const months = ['janvier', 'fevrier', 'mars', 'avril', 'mai', 'juin', 'juillet', 'aout', 'septembre', 'octobre', 'novembre', 'decembre'];
    return months.indexOf(name.toLowerCase());
  }
}