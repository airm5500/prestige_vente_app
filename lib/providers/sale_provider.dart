// lib/providers/sale_provider.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/api/models/user.dart';
import 'package:prestige_vente_app/api/models/payment_method_qr.dart';

class SaleProvider with ChangeNotifier {
  ApiService _apiService;
  ApiService get apiService => _apiService;

  SaleProvider(this._apiService) {
    _loadScanSettings();
  }

  void updateApiService(ApiService newApiService) {
    _apiService = newApiService;
  }

  bool _isLoading = false;
  String? _errorMessage;
  String? _currentVenteId;
  List<SaleItemDetail> _cartItems = [];
  SaleSummary _saleSummary = SaleSummary();
  List<ProductSearchResult> _searchResults = [];
  List<PreventeListItem> _preventes = [];
  bool _isLoadingPreventes = false;
  List<PaymentMethodQr> _paymentMethodsWithQr = [];
  // CORRECTION : Variable inutile supprimée

  bool _isQuickScanMode = false;
  bool get isQuickScanMode => _isQuickScanMode;

  Future<void> _loadScanSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _isQuickScanMode = prefs.getBool('isQuickScanMode') ?? false;
    notifyListeners();
  }

  Future<void> toggleQuickScanMode() async {
    _isQuickScanMode = !_isQuickScanMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isQuickScanMode', _isQuickScanMode);
    notifyListeners();
  }

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get currentVenteId => _currentVenteId;
  List<SaleItemDetail> get cartItems => _cartItems;
  SaleSummary get saleSummary => _saleSummary;
  List<ProductSearchResult> get searchResults => _searchResults;
  List<PreventeListItem> get preventes => _preventes;
  bool get isLoadingPreventes => _isLoadingPreventes;
  List<PaymentMethodQr> get paymentMethodsWithQr => _paymentMethodsWithQr;

  Future<void> fetchPaymentMethodsWithQr() async {
    if (_paymentMethodsWithQr.isNotEmpty) return;
    try {
      _paymentMethodsWithQr = await _apiService.getPaymentMethodsWithQr();
    } catch (e) {
      debugPrint("Error fetching QR methods: $e");
    } finally {
      notifyListeners();
    }
  }

  Future<void> fetchPreventes() async {
    if (_isLoadingPreventes) return;
    try {
      _isLoadingPreventes = true;
      _preventes.clear();
      notifyListeners();
      List<PreventeListItem> fetchedPreventes = await _apiService.getPreventes();
      fetchedPreventes = fetchedPreventes.where((p) => p.lgTYPEVENTEID == "1").toList();
      final uniquePreventesMap = <String, PreventeListItem>{};
      for (final prevente in fetchedPreventes) {
        uniquePreventesMap.putIfAbsent(prevente.lgPREENREGISTREMENTID, () => prevente);
      }
      _preventes = uniquePreventesMap.values.toList();
      _preventes.sort((a, b) {
        try {
          final format = DateFormat('dd/MM/yyyy HH:mm:ss');
          final dateTimeA = format.parse('${a.dtUPDATED} ${a.heure}');
          final dateTimeB = format.parse('${b.dtUPDATED} ${b.heure}');
          return dateTimeB.compareTo(dateTimeA);
        } catch (e) { return 0; }
      });
    } finally {
      _isLoadingPreventes = false;
      notifyListeners();
    }
  }

  void startNewSale() {
    _currentVenteId = null;
    _cartItems = [];
    _saleSummary = SaleSummary();
    _searchResults = [];
    _errorMessage = null;
    notifyListeners();
  }

  void clearSearchResults() {
    _searchResults = [];
    notifyListeners();
  }

  Future<void> searchProducts(String query) async {
    if (query.length < 3) {
      _searchResults = [];
      notifyListeners();
      return;
    }
    _setLoading(true);
    // 1. On récupère TOUS les résultats
    List<ProductSearchResult> results = await _apiService.searchProducts(query);

    // 2. FILTRAGE RV (LOGIQUE AJOUTÉE)
    // On récupère le réglage directement depuis les SharedPreferences pour être sûr
    // (ou via une injection de SettingsProvider si vous préférez)
    final prefs = await SharedPreferences.getInstance();
    final bool hideRv = prefs.getBool('hide_rv_products') ?? true; // True par défaut

    if (hideRv) {
      // On retire tout ce qui commence par "RV " (insensible à la casse)
      results.removeWhere((p) => p.strNAME.toUpperCase().startsWith("RV "));
    }

    // 3. On affecte le résultat filtré
    _searchResults = results;
    _setLoading(false);
  }

  Future<void> addProductToCart(ProductSearchResult product, int quantity, {bool isPrevente = false}) async {
    _setLoading(true);
    final newVenteId = await _apiService.addItemToSale(
        produitId: product.lgFAMILLEID,
        qte: quantity,
        itemPu: product.intPRICE,
        venteId: _currentVenteId,
        isPrevente: isPrevente);
    if (newVenteId != null) {
      _currentVenteId = newVenteId;
      await _refreshCartAndSummary();
    }
    _setLoading(false);
  }

  Future<void> removeProductFromCart(String itemId) async {
    _setLoading(true);
    if (await _apiService.removeItemFromSale(itemId)) {
      await _refreshCartAndSummary();
    }
    _setLoading(false);
  }

  Future<void> updateCartItem(SaleItemDetail item, int newQuantity, int newPrice) async {
    _setLoading(true);
    if (await _apiService.updateSaleItem(itemId: item.lgPREENREGISTREMENTDETAILID, produitId: item.lgFAMILLEID, qte: newQuantity, itemPu: newPrice)) {
      await _refreshCartAndSummary();
    }
    _setLoading(false);
  }

  Future<Map<String, dynamic>> cloturerVente(PaymentMethod paymentMethod, User currentUser, {int? montantRecu, int? montantRemis}) async {
    if (_currentVenteId == null) return {"success": false, "msg": "ID manquant"};
    _setLoading(true);
    final clientId = paymentMethod.name.toLowerCase().replaceAll(' ', '').replaceAll('é', 'e');
    await _apiService.updateClientForSale(_currentVenteId!, clientId);
    final result = await _apiService.cloturerVente(
      venteId: _currentVenteId!, summary: _saleSummary, typeReglementId: paymentMethod.id,
      clientId: clientId, userVendeurId: currentUser.userId, montantRecu: montantRecu, montantRemis: montantRemis,
    );
    _setLoading(false);
    return result;
  }

  Future<bool> terminerPrevente() async {
    if (_currentVenteId == null) return false;
    _setLoading(true);
    final success = await _apiService.terminerPrevente(_currentVenteId!);
    _setLoading(false);
    return success;
  }

  Future<void> loadPrevente(String preventeId) async {
    _setLoading(true);
    startNewSale();
    _currentVenteId = preventeId;
    await _refreshCartAndSummary();
    _setLoading(false);
  }

  Future<void> _refreshCartAndSummary() async {
    if (_currentVenteId != null) {
      final results = await Future.wait([
        _apiService.getSaleDetails(_currentVenteId!),
        _apiService.calculateNet(_currentVenteId!),
      ]);
      _cartItems = results[0] as List<SaleItemDetail>;
      _saleSummary = (results[1] as SaleSummary?) ?? _saleSummary;
    }
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  Future<List<PreventeListItem>> fetchPreventesByType(String typeVenteId) async {
    try {
      final response = await _apiService.request(
        method: 'GET',
        url: '/ventestats/preventes',
        queryParameters: {
          'statut': 'ALL',
          'limit': 50,
          'page': 1,
          'start': 0,
          'query': '',
        },
      );

      final List<PreventeListItem> results = [];
      if (response['data'] != null) {
        final data = response['data'];
        if (data is List) {
          for (var item in data) {
            if (item['lgTYPEVENTEID'].toString() == typeVenteId) {
              results.add(PreventeListItem.fromJson(item));
            }
          }
        } else if (data is Map) {
          data.forEach((key, value) {
            if (value['lgTYPEVENTEID'].toString() == typeVenteId) {
              results.add(PreventeListItem.fromJson(value));
            }
          });
        }
      }
      results.sort((a, b) {
        try {
          final dateA = DateFormat('dd/MM/yyyy').parse(a.dtUPDATED);
          final dateB = DateFormat('dd/MM/yyyy').parse(b.dtUPDATED);
          final compareDate = dateB.compareTo(dateA);
          if (compareDate != 0) return compareDate;
          return b.heure.compareTo(a.heure);
        } catch (e) { return 0; }
      });
      return results;
    } catch (e) {
      debugPrint("Erreur fetchPreventesByType: $e");
      return [];
    }
  }

  // CORRECTION : Appel sur l'endpoint /ventestats/{id} qui renvoie le JSON complet
  Future<Map<String, dynamic>?> fetchFullSaleDetails(String venteId) async {
    try {
      final response = await _apiService.request(
        method: 'GET',
        url: '/ventestats/$venteId',
      );

      // La réponse est souvent encapsulée dans { "data": { ... }, "success": true }
      if (response != null && response['data'] != null) {
        return response['data'];
      }
      return null;
    } catch (e) {
      debugPrint("Erreur fetchFullSaleDetails: $e");
      return null;
    }
  }
}
