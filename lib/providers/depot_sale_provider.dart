import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/depot_model.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/services/product_finder.dart';

class DepotSaleProvider with ChangeNotifier, PagedProductSearchHost {
  final ApiService _apiService;

  // État de la vente
  String? _currentSaleId;
  String? get currentSaleId => _currentSaleId;
  String? _currentSaleRef;
  String? get currentSaleRef => _currentSaleRef;

  DepotModel? _selectedDepot;
  DepotModel? get selectedDepot => _selectedDepot;

  List<SaleLine> _cartItems = [];
  List<SaleLine> get cartItems => _cartItems;

  // --- GESTION RECHERCHE ---
  /// Code → produit exact (EAN-13 → CIP7…) ; texte → liste par pages (« 50 sur 120 »).
  @override
  late final PagedProductSearch productSearch = PagedProductSearch(() => _apiService);
  List<ProductSearchResult> get searchResults => productSearch.items;

  /// Échec de la dernière recherche (réseau/serveur) : ≠ « produit introuvable ».
  String? get searchError => productSearch.error;

  /// Code inconnu : « Code X introuvable (essayé aussi Y) ».
  String? get searchNotFound => productSearch.notFound;

  bool _isLoading = false;
  bool get isLoading => _isLoading;
  String _errorMessage = '';
  String get errorMessage => _errorMessage;

  int _totalAmount = 0;
  int get totalAmount => _totalAmount;

  /// Panier non relu depuis le serveur après une opération : affiché tel quel mais
  /// la clôture est bloquée tant qu'il n'est pas actualisé.
  String? _cartError;
  String? get cartError => _cartError;

  /// Clôture en cours (empêche une double clôture).
  bool _isClosing = false;
  bool get isClosing => _isClosing;

  bool _isQuickScanMode = false;
  bool get isQuickScanMode => _isQuickScanMode;

  // Les ajouts sont faits l'un après l'autre (scan rapide) : jamais deux créations de vente.
  Future<void> _addQueue = Future.value();

  DepotSaleProvider(this._apiService);

  void toggleQuickScanMode() {
    _isQuickScanMode = !_isQuickScanMode;
    notifyListeners();
  }

  // --- Recherche Produits ---
  Future<void> searchProducts(String query) async {
    _isLoading = true;
    notifyListeners();
    try {
      await productSearch.run(query);
      if (productSearch.error != null) _errorMessage = productSearch.error!;
    } catch (e) {
      productSearch.clear();
      productSearch.error = "Recherche impossible : $e";
      _errorMessage = productSearch.error!;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearSearchResults() {
    productSearch.clear();
    notifyListeners();
  }

  // --- Gestion Dépôt ---
  void selectDepot(DepotModel depot) {
    _selectedDepot = depot;
    notifyListeners();
  }

  void resetSale() {
    _currentSaleId = null;
    _selectedDepot = null;
    _cartItems = [];
    productSearch.clear();
    _totalAmount = 0;
    _errorMessage = '';
    _cartError = null;
    _currentSaleRef = null;
    notifyListeners();
  }

  /// Charge une vente en cours. Renvoie `false` (avec [errorMessage]) si elle n'a pas pu être chargée.
  Future<bool> loadExistingSale(String saleId) async {
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();
    var ok = false;
    try {
      final data = await _apiService.getDepotSaleDetails(saleId);
      if (data != null) {
        _currentSaleId = saleId;
        _currentSaleRef = data['strREF']?.toString();
        if (data['magasin'] is Map) {
          _selectedDepot = DepotModel.fromJson(Map<String, dynamic>.from(data['magasin'] as Map));
        }
        ok = await _refreshCart();
        if (!ok) _errorMessage = _cartError ?? "Impossible de charger les lignes de la vente";
      } else {
        _errorMessage = "Impossible de charger la vente (réseau ou serveur indisponible).";
      }
    } catch (e) {
      _errorMessage = "Impossible de charger la vente";
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return ok;
  }

  // --- Ajout au Panier ---
  Future<bool> addToCart(ProductSearchResult product, {int qty = 1}) {
    final run = _addQueue.then((_) => _addProductInternal(product, qty));
    _addQueue = run.then((_) {}, onError: (_) {});
    return run;
  }

  // Logique interne d'ajout
  Future<bool> _addProductInternal(ProductSearchResult product, int quantity) async {
    if (_selectedDepot == null) {
      _errorMessage = "Veuillez sélectionner un dépôt d'abord.";
      notifyListeners();
      return false;
    }

    _isLoading = true;
    notifyListeners();
    bool success = false;

    try {
      if (_currentSaleId == null) {
        // Premier ajout -> Création vente
        final result = await _apiService.addFirstDepotItem(
          clientId: _selectedDepot!.lgCLIENTID,
          emplacementId: _selectedDepot!.lgEMPLACEMENTID,
          typeDepotId: _selectedDepot!.lgTYPEDEPOTID,
          produitId: product.lgFAMILLEID,
          itemPu: product.intPRICE,
          qte: quantity,
        );

        if (result != null && result['lgPREENREGISTREMENTID'] != null) {
          _currentSaleId = result['lgPREENREGISTREMENTID'];
          _currentSaleRef = result['strREF'];
          success = true;
        }
      } else {
        // Ajout suivant
        success = await _apiService.addNextDepotItem(
          venteId: _currentSaleId!,
          clientId: _selectedDepot!.lgCLIENTID,
          emplacementId: _selectedDepot!.lgEMPLACEMENTID,
          typeDepotId: _selectedDepot!.lgTYPEDEPOTID,
          produitId: product.lgFAMILLEID,
          itemPu: product.intPRICE,
          qte: quantity,
        );
      }

      if (success) {
        await _refreshCart();
      } else {
        _errorMessage = "Produit non ajouté : le serveur n'a pas enregistré la ligne (réseau ou serveur indisponible).";
      }
    } catch (e) {
      _errorMessage = "Erreur technique: $e";
      success = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return success;
  }

  // --- Modification / Suppression ---
  Future<bool> updateItem(SaleLine item, int newQty, int newPrice) async {
    _isLoading = true;
    notifyListeners();
    var success = false;
    try {
      success = await _apiService.updateDepotItem(
        itemId: item.lgPREENREGISTREMENTDETAILID,
        produitId: item.lgFAMILLEID,
        itemPu: newPrice,
        qte: newQty,
      );
      if (success) {
        await _refreshCart();
      } else {
        _errorMessage = "Ligne non modifiée : le serveur n'a pas enregistré la modification.";
      }
    } catch (e) {
      success = false;
      _errorMessage = "Ligne non modifiée : $e";
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return success;
  }

  Future<bool> removeItem(String itemId) async {
    _isLoading = true;
    notifyListeners();
    var success = false;
    try {
      success = await _apiService.removeDepotItem(itemId);
      if (success) {
        await _refreshCart();
      } else {
        _errorMessage = "Ligne non supprimée : le serveur n'a pas confirmé la suppression.";
      }
    } catch (e) {
      success = false;
      _errorMessage = "Ligne non supprimée : $e";
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return success;
  }

  Future<bool> closeSale() async {
    if (_currentSaleId == null || _selectedDepot == null) return false;
    if (_isClosing) return false;
    _isClosing = true;
    _isLoading = true;
    notifyListeners();
    var success = false;
    try {
      success = await _apiService.closeDepotSale(
        venteId: _currentSaleId!,
        clientId: _selectedDepot!.lgCLIENTID,
      );
      if (success) {
        resetSale();
      } else {
        _errorMessage = "Vente NON clôturée : le serveur n'a pas confirmé (réseau ou serveur indisponible). Elle reste en cours.";
      }
    } catch (e) {
      success = false;
      _errorMessage = "Vente NON clôturée : $e";
    } finally {
      _isClosing = false;
      _isLoading = false;
      notifyListeners();
    }
    return success;
  }

  /// Relit le panier depuis le serveur (bouton « Réessayer »).
  Future<bool> refreshCart() async {
    _isLoading = true;
    notifyListeners();
    final ok = await _refreshCart();
    _isLoading = false;
    notifyListeners();
    return ok;
  }

  // Relit les lignes : en cas d'échec, le panier affiché est conservé et [cartError] est renseigné.
  Future<bool> _refreshCart() async {
    if (_currentSaleId == null) return true;
    try {
      final items = await _apiService.fetchDepotSaleItems(_currentSaleId!);
      _cartItems = items;
      _totalAmount = items.fold(0, (sum, item) => sum + item.intPRICE);
      _cartError = null;
      notifyListeners();
      return true;
    } catch (e) {
      _cartError = "Panier non actualisé : ${e is ApiLoadException ? e.message : e}";
      notifyListeners();
      return false;
    }
  }

  // --- GESTION DE LA LISTE DES VENTES EN COURS ---

  List<DepotSaleListItem> _ongoingSales = [];
  List<DepotSaleListItem> get ongoingSales => _ongoingSales;

  /// Échec du chargement de la liste (≠ aucune vente en cours).
  String? _listError;
  String? get listError => _listError;

  Future<void> fetchOngoingSales() async {
    _isLoading = true;
    notifyListeners();
    try {
      // 1. Récupération brute depuis l'API
      final rawList = await _apiService.fetchDepotSales();

      // 2. On ne garde que les ventes ayant un montant > 0
      _ongoingSales = rawList.where((sale) => sale.intPRICE > 0).toList();
      _listError = null;
    } on ApiLoadException catch (e) {
      // La liste précédente est conservée, l'erreur est affichée.
      _listError = e.message;
      _errorMessage = "Erreur chargement liste: ${e.message}";
    } catch (e) {
      _listError = "Impossible de charger les ventes dépôt : $e";
      _errorMessage = "Erreur chargement liste: $e";
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Supprime la vente courante (vide) sur le serveur. Renvoie `false` si le serveur ne l'a pas supprimée.
  Future<bool> deleteCurrentSale() async {
    var ok = true;
    if (_currentSaleId != null) {
      try {
        ok = await _apiService.deleteSale(_currentSaleId!); // Appel API
      } catch (_) {
        ok = false;
      }
      resetSale(); // Nettoyage local
    }
    return ok;
  }
}
