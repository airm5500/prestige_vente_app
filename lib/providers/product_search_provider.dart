// lib/providers/product_search_provider.dart
// 28/09/2025 02:32
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product_search_result.dart';
import 'package:prestige_vente_app/api/models/product_stats.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';

// Classe pour stocker les données agrégées pour le graphique
class MonthlyComparisonData {
  final int sales;
  final int orders;
  final int orderFrequency;
  MonthlyComparisonData({this.sales = 0, this.orders = 0, this.orderFrequency = 0});
}

class ProductSearchProvider with ChangeNotifier {
  final ApiService _apiService;

  ProductSearchProvider(SettingsProvider settingsProvider)
      : _apiService = ApiService(baseUrl: settingsProvider.baseUrl);

  // --- ETAT ---
  bool _isLoading = false;
  List<ProductDetails> _searchResults = [];
  ProductDetails? _selectedProduct;
  List<MonthlyComparisonData> _comparisonData = [];

  // --- GETTERS ---
  bool get isLoading => _isLoading;
  List<ProductDetails> get searchResults => _searchResults;
  ProductDetails? get selectedProduct => _selectedProduct;
  List<MonthlyComparisonData> get comparisonData => _comparisonData;
  bool get hasComparisonData => _comparisonData.isNotEmpty;

  // --- ACTIONS ---

  void clear() {
    _searchResults = [];
    _selectedProduct = null;
    _comparisonData = [];
    notifyListeners();
  }

  Future<void> search(String query) async {
    if (query.isEmpty) {
      clear();
      return;
    }
    _setLoading(true);
    _selectedProduct = null;
    _searchResults = await _apiService.searchProductFiche(query);
    _setLoading(false);
  }

  Future<void> selectProduct(ProductDetails product) async {
    _setLoading(true);
    _selectedProduct = product;
    _searchResults = []; // On cache les résultats de recherche
    await _loadComparisonData(product);
    _setLoading(false);
  }

  Future<void> _loadComparisonData(ProductDetails product) async {
    final year = DateTime.now().year;
    final startDate = '$year-01-01';
    final endDate = '$year-12-31';

    // Appels API en parallèle
    final results = await Future.wait([
      _apiService.getProductOrderHistory(product.lgFamilleId, startDate, endDate),
      _apiService.getAnnualSales(product.intCip, year),
    ]);

    final orders = results[0] as List<ProductOrderHistory>;
    final salesData = results[1] as List<ProductAnnualSale>;
    final sales = salesData.isNotEmpty ? salesData.first.monthlySales : <String, int>{};

    // Traitement des données
    List<MonthlyComparisonData> monthlyData = List.generate(12, (_) => MonthlyComparisonData());

    // Agréger les commandes par mois
    for (var order in orders) {
      try {
        final date = DateFormat('dd/MM/yyyy HH:mm').parse(order.dtEntree);
        final monthIndex = date.month - 1;
        monthlyData[monthIndex] = MonthlyComparisonData(
          sales: monthlyData[monthIndex].sales,
          orders: monthlyData[monthIndex].orders + order.intNumber,
          orderFrequency: monthlyData[monthIndex].orderFrequency + 1,
        );
      } catch (e) {
        print("Could not parse date: ${order.dtEntree}");
      }
    }

    // Intégrer les ventes
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

    _comparisonData = monthlyData;
  }

  int _monthNameToInt(String name) {
    const months = ['janvier', 'fevrier', 'mars', 'avril', 'mai', 'juin', 'juillet', 'aout', 'septembre', 'octobre', 'novembre', 'decembre'];
    return months.indexOf(name.toLowerCase());
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}