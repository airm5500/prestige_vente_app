// lib/providers/sale_provider.dart
// 11/11/2025 10:00 (Version Complete: Stock, Caisse, Focus, Auto-Open)
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/api/models/user.dart';
import 'package:prestige_vente_app/api/models/payment_method_qr.dart';

class SaleProvider with ChangeNotifier {
  ApiService _apiService;
  ApiService get apiService => _apiService;

  SaleProvider(this._apiService);

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
  bool _isLoadingPaymentMethodsQr = false;

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
    if (_paymentMethodsWithQr.isNotEmpty || _isLoadingPaymentMethodsQr) return;
    try {
      _isLoadingPaymentMethodsQr = true;
      _paymentMethodsWithQr = await _apiService.getPaymentMethodsWithQr();
    } catch (e) {
      print("Error in SaleProvider fetching QR methods: $e");
    } finally {
      _isLoadingPaymentMethodsQr = false;
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
      final uniquePreventesList = uniquePreventesMap.values.toList();

      uniquePreventesList.sort((a, b) {
        try {
          final format = DateFormat('dd/MM/yyyy HH:mm:ss');
          final dateTimeA = format.parse('${a.dtUPDATED} ${a.heure}');
          final dateTimeB = format.parse('${b.dtUPDATED} ${b.heure}');
          return dateTimeB.compareTo(dateTimeA);
        } catch (e) {
          return 0;
        }
      });

      _preventes = uniquePreventesList;
    } catch (e) {
      print("Erreur lors de la récupération des préventes: $e");
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

  // MODIFICATION : Méthode pour vider explicitement les résultats
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
    _searchResults.clear();
    _searchResults = await _apiService.searchProducts(query);
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
    } else {
      _errorMessage = "Erreur lors de l'ajout du produit.";
    }
    _setLoading(false);
  }

  Future<void> removeProductFromCart(String itemId) async {
    _setLoading(true);
    final success = await _apiService.removeItemFromSale(itemId);
    if (success) {
      await _refreshCartAndSummary();
    } else {
      _errorMessage = "Erreur lors de la suppression.";
    }
    _setLoading(false);
  }

  Future<void> updateCartItem(SaleItemDetail item, int newQuantity, int newPrice) async {
    _setLoading(true);
    final success = await _apiService.updateSaleItem(
        itemId: item.lgPREENREGISTREMENTDETAILID,
        produitId: item.lgFAMILLEID,
        qte: newQuantity,
        itemPu: newPrice);
    if (success) {
      await _refreshCartAndSummary();
    } else {
      _errorMessage = "Erreur de mise à jour.";
    }
    _setLoading(false);
  }

  Future<Map<String, dynamic>> cloturerVente(
      PaymentMethod paymentMethod,
      User currentUser, {
        int? montantRecu,
        int? montantRemis,
      }) async {
    if (_currentVenteId == null) return {"success": false, "msg": "ID de vente manquant."};
    _setLoading(true);

    final clientId = paymentMethod.name.toLowerCase().replaceAll(' ', '').replaceAll('é', 'e');

    await _apiService.updateClientForSale(_currentVenteId!, clientId);

    final result = await _apiService.cloturerVente(
      venteId: _currentVenteId!,
      summary: _saleSummary,
      typeReglementId: paymentMethod.id,
      clientId: clientId,
      userVendeurId: currentUser.userId,
      montantRecu: montantRecu,
      montantRemis: montantRemis,
    );

    if (result['success'] == false) {
      _errorMessage = result['msg'] ?? "La clôture de la vente a échoué.";
    }

    _setLoading(false);
    return result;
  }

  Future<bool> terminerPrevente() async {
    if (_currentVenteId == null) return false;
    _setLoading(true);
    final success = await _apiService.terminerPrevente(_currentVenteId!);
    if (!success) {
      _errorMessage = "La finalisation de la prévente a échoué.";
    }
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
      _errorMessage = null;
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}