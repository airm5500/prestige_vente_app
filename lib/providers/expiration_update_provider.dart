// lib/providers/expiration_update_provider.dart
// 15/10/2025 23:50
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_horsligne.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product.dart'; // Utilise le modèle de recherche rapide
import 'package:prestige_vente_app/services/product_finder.dart';

class ExpirationUpdateProvider with ChangeNotifier, PagedProductSearchHost {
  ApiService _apiService;

  ExpirationUpdateProvider(this._apiService);

  void updateApiService(ApiService newApiService) {
    _apiService = newApiService;
  }

  bool _isLoading = false;

  /// Code → produit exact (EAN-13 → CIP7…) ; texte → liste par pages (« 50 sur 120 »).
  @override
  late final PagedProductSearch productSearch = PagedProductSearch(() => _apiService);
  // MODIFICATION : Le produit sélectionné est maintenant du type de la recherche rapide
  ProductSearchResult? _selectedProduct;
  String? _errorMessage;

  bool get isLoading => _isLoading;
  List<ProductSearchResult> get searchResults => productSearch.items;

  /// Panne de la dernière recherche (≠ produit introuvable).
  String? get searchError => productSearch.error;

  /// Code inconnu : « Code X introuvable (essayé aussi Y) ».
  String? get searchNotFound => productSearch.notFound;
  ProductSearchResult? get selectedProduct => _selectedProduct;
  String? get errorMessage => _errorMessage;

  void clearSearch() {
    productSearch.clear();
    _selectedProduct = null;
    notifyListeners();
  }

  void clearSelection() {
    _selectedProduct = null;
    notifyListeners();
  }

  Future<void> search(String query) async {
    if (query.isEmpty) {
      clearSearch();
      return;
    }
    _isLoading = true;
    notifyListeners();
    // Code → produit exact ; texte → 1ʳᵉ page (la suite se charge en faisant défiler)
    await productSearch.run(query); // une recherche plus récente remplace celle-ci
    _isLoading = false;
    notifyListeners();
  }

  /// Recherche successivement chaque code (EAN-13, CIP7...) issu d'un DataMatrix :
  /// le produit exact dès qu'un code le désigne, sinon les produits trouvés.
  /// Une panne est exposée dans [searchError] (≠ produit introuvable).
  Future<void> searchFirstMatch(List<String> queries) async {
    _isLoading = true;
    productSearch.clear();
    notifyListeners();
    await productSearch.runCodes(queries);
    _isLoading = false;
    notifyListeners();
  }

  /// Comme [searchFirstMatch] mais sans modifier l'état de l'écran (contrôle en arrière-plan).
  /// En cas de panne : liste vide (aucun avertissement affiché).
  Future<List<ProductSearchResult>> lookupFirstMatch(List<String> queries) async {
    final check = PagedProductSearch(() => _apiService);
    await check.runCodes(queries);
    return check.items;
  }

  // MODIFICATION : La sélection est maintenant une simple affectation, sans appel API
  void selectProduct(ProductSearchResult product) {
    _selectedProduct = product;
    productSearch.clear(); // On cache les résultats
    notifyListeners();
  }

  Future<bool> submitUpdate({
    required String date,
    required String lot,
    required int quantity,
  }) async {
    if (_selectedProduct == null) return false;

    _isLoading = true;
    notifyListeners();

    final formattedDate = DateFormat('yyyy-MM-dd').format(DateFormat('dd/MM/yyyy').parse(date));
    if (HorsLigne.instance.offline) {
      // Hors ligne : enregistré sur l'appareil, envoyé au retour du serveur (H3).
      final p = _selectedProduct!;
      var ok = true;
      try {
        await StockHorsLigne.instance.queue.addPeremption(
            produitId: p.lgFAMILLEID, cip: p.intCIP, produit: p.strNAME, numLot: lot, date: DateFormat('dd/MM/yyyy').parse(date), qty: quantity);
      } catch (e) {
        ok = false;
        _errorMessage = 'Hors ligne : mise à jour non enregistrée sur l\'appareil ($e).';
      }
      _isLoading = false;
      notifyListeners();
      return ok;
    }

    final success = await _apiService.addLot(
      // MODIFICATION : Utilise l'ID du bon modèle
      produitId: _selectedProduct!.lgFAMILLEID,
      datePeremption: formattedDate,
      numLot: lot,
      quantity: quantity,
    );

    if (!success) {
      _errorMessage = "La mise à jour a échoué.";
    }

    _isLoading = false;
    notifyListeners();
    return success;
  }
}