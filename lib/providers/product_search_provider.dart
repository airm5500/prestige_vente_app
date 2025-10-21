// lib/providers/product_search_provider.dart
// 20/10/2025 10:17
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product_search_result.dart';
import 'package:prestige_vente_app/api/models/product_info.dart';
import 'package:prestige_vente_app/api/models/product_stats.dart';

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

  List<ProductInfo> _searchResults = [];
  ProductInfo? _selectedProductInfo;
  ProductDetails? _selectedProductDetails;
  List<MonthlyComparisonData> _comparisonData = [];

  bool get isLoading => _isLoading;
  List<ProductInfo> get searchResults => _searchResults;
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

    _searchResults = await _apiService.searchProductInfoForSearch(query);
    _isLoading = false;
    notifyListeners();
  }

  Future<void> selectProduct(ProductInfo product) async {
    _isLoading = true;
    _selectedProductInfo = product;
    _searchResults = [];
    notifyListeners();

    final results = await Future.wait([
      _apiService.getProductDetailsForSearch(product.codeCip),
      _loadComparisonData(product.produitId, product.codeCip),
    ]);

    _selectedProductDetails = results[0] as ProductDetails?;
    _comparisonData = results[1] as List<MonthlyComparisonData>;

    _isLoading = false;
    notifyListeners();
  }

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