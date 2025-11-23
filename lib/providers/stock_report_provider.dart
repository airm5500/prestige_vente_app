// lib/providers/stock_report_provider.dart
// 12/11/2025 14:30 (Focus & Logique Filtre Stock)
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/rayon.dart';
import 'package:prestige_vente_app/api/models/stock_report_models.dart';

class StockReportProvider with ChangeNotifier {
  ApiService _apiService;
  StockReportProvider(this._apiService);
  void updateApiService(ApiService newApiService) { _apiService = newApiService; }

  bool _isLoading = false;
  List<StockReportItem> _reportItems = [];
  int _totalItems = 0;

  List<Rayon> _rayons = [];
  List<Grossiste> _grossistes = [];

  String _searchQuery = '';
  String _selectedRayonId = '';
  String _selectedGrossisteId = '';
  StockFilterType? _selectedStockFilter;
  String _stockValue = '';

  bool get isLoading => _isLoading;
  List<StockReportItem> get reportItems => _reportItems;
  int get totalItems => _totalItems;
  List<Rayon> get rayons => _rayons;
  List<Grossiste> get grossistes => _grossistes;

  String get searchQuery => _searchQuery;
  String get selectedRayonId => _selectedRayonId;
  String get selectedGrossisteId => _selectedGrossisteId;
  StockFilterType? get selectedStockFilter => _selectedStockFilter;
  String get stockValue => _stockValue;

  Future<void> loadFiltersData() async {
    if (_rayons.isNotEmpty && _grossistes.isNotEmpty) return;
    final results = await Future.wait([
      _apiService.getRayons(),
      _apiService.getGrossistes(),
    ]);
    _rayons = results[0] as List<Rayon>;
    _grossistes = results[1] as List<Grossiste>;
    notifyListeners();
  }

  Future<void> search({bool isRefresh = true}) async {
    // Si aucun filtre n'est défini, on ne charge rien
    if (_searchQuery.isEmpty &&
        _selectedRayonId.isEmpty &&
        _selectedGrossisteId.isEmpty &&
        _selectedStockFilter == null) {
      _reportItems = [];
      _totalItems = 0;
      notifyListeners();
      return;
    }

    if (isRefresh) {
      _reportItems = [];
      _setLoading(true);
    }

    // MODIFICATION (Point 2) : Construction intelligente du filtre stock
    String filterStr = '';
    String stockValToSend = '';

    // On n'envoie le filtre QUE si on a un Type ET une Valeur
    if (_selectedStockFilter != null && _stockValue.isNotEmpty) {
      filterStr = _selectedStockFilter.toString().split('.').last;
      stockValToSend = _stockValue;
    }
    // FIN MODIFICATION

    final result = await _apiService.getStockReport(
      query: _searchQuery,
      codeRayon: _selectedRayonId,
      codeGrossiste: _selectedGrossisteId,
      filtreStock: filterStr,
      stockValue: stockValToSend,
      page: 1,
      limit: 20,
    );

    _reportItems = result['data'];
    _totalItems = result['total'];
    _setLoading(false);
  }

  void updateFilters({
    String? query,
    String? rayonId,
    String? grossisteId,
    StockFilterType? filterType,
    String? stockValue,
  }) {
    if (query != null) _searchQuery = query;
    if (rayonId != null) _selectedRayonId = rayonId;
    if (grossisteId != null) _selectedGrossisteId = grossisteId;
    // Note : updateFilters est moins utilisé maintenant au profit des setters spécifiques
  }

  void setQuery(String val) { _searchQuery = val; search(); }
  void setRayon(String val) { _selectedRayonId = val; search(); }
  void setGrossiste(String val) { _selectedGrossisteId = val; search(); }

  // MODIFICATION (Point 2) : Gestion fine du déclenchement
  void setStockFilter(StockFilterType? type) {
    _selectedStockFilter = type;
    // Si on désactive le filtre (null) -> On lance la recherche (pour voir tout)
    // Si on active un filtre -> On ne lance QUE si une valeur est déjà saisie
    if (type == null || _stockValue.isNotEmpty) {
      search();
    } else {
      // Sinon on notifie juste pour mettre à jour l'UI (activer le champ valeur)
      notifyListeners();
    }
  }

  void setStockValue(String val) {
    _stockValue = val;
    // On lance la recherche si un type est sélectionné
    // Si la valeur est vide, search() gérera en ignorant le filtre (voir plus haut)
    if (_selectedStockFilter != null) {
      search();
    }
  }
  // FIN MODIFICATION

  void clearFilters() {
    _searchQuery = '';
    _selectedRayonId = '';
    _selectedGrossisteId = '';
    _selectedStockFilter = null;
    _stockValue = '';

    _reportItems = [];
    _totalItems = 0;

    notifyListeners();
  }

  String getGrossisteName(String id) {
    final g = _grossistes.firstWhere((element) => element.id == id, orElse: () => Grossiste(id: '', libelle: 'Inconnu'));
    return g.libelle;
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}