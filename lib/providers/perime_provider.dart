// lib/providers/perime_provider.dart
// 09/11/2025 18:45 (Ajout filtres date Pémimés)
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_horsligne.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_models.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/perime_models.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/services/product_finder.dart';

class PerimeProvider with ChangeNotifier, PagedProductSearchHost {
  ApiService _apiService;
  PerimeProvider(this._apiService);
  void updateApiService(ApiService newApiService) { _apiService = newApiService; }

  bool _isLoading = false;
  String? _errorMessage;
  String _successMessage = '';

  // --- Etat pour l'onglet "Recherche Périmés" ---
  List<ProduitPerime> _produitsPerimesList = [];
  PerimeMetaData? _metaData;
  int _nbreMoisFilter = 3;

  // --- Etat pour l'onglet "Saisie" ---
  /// Code → produit exact (EAN-13 → CIP7…) ; texte → liste par pages (« 50 sur 120 »).
  @override
  late final PagedProductSearch productSearch = PagedProductSearch(() => _apiService);
  ProductSearchResult? _selectedProduct;
  List<SaisieEnCoursItem> _saisieEnCoursList = [];
  List<SaisiePerimeItem> _saisieHistoryList = [];

  // --- Getters ---
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String get successMessage => _successMessage;

  List<ProduitPerime> get produitsPerimesList => _produitsPerimesList;
  PerimeMetaData? get metaData => _metaData;
  int get nbreMoisFilter => _nbreMoisFilter;

  List<ProductSearchResult> get productSearchResults => productSearch.items;

  /// Panne de la dernière recherche produit (≠ produit introuvable).
  String? get productSearchError => productSearch.error;

  /// Code inconnu : « Code X introuvable (essayé aussi Y) ».
  String? get productSearchNotFound => productSearch.notFound;
  ProductSearchResult? get selectedProduct => _selectedProduct;
  List<SaisieEnCoursItem> get saisieEnCoursList => _saisieEnCoursList;
  List<SaisiePerimeItem> get saisieHistoryList => _saisieHistoryList;

  // --- Actions ---
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String? message) {
    _errorMessage = message;
    notifyListeners();
  }

  void _setSuccess(String message) {
    _successMessage = message;
    notifyListeners();
  }

  void clearMessages() {
    _errorMessage = null;
    _successMessage = '';
  }

  // --- Méthodes pour "Recherche Périmés" ---
  Future<void> setNbreMois(int mois) async {
    _nbreMoisFilter = mois;
    notifyListeners();
    await loadProduitsPerimes();
  }

  Future<void> loadProduitsPerimes() async {
    if (HorsLigne.instance.offline) {
      // Hors ligne : pas de liste vide trompeuse.
      _produitsPerimesList = [];
      _metaData = null;
      _setError('Recherche des périmés : $kEnLigneUniquement.');
      return;
    }
    _setLoading(true);
    final result = await _apiService.getProduitsPerimes(_nbreMoisFilter);
    _produitsPerimesList = result['data'] as List<ProduitPerime>;
    _metaData = result['metaData'] as PerimeMetaData?;
    _setLoading(false);
  }

  // --- Méthodes pour "Saisie" ---
  Future<void> loadSaisieEnCours() async {
    _setLoading(true);
    if (HorsLigne.instance.offline) {
      // Hors ligne : copie du jour + saisies en attente d'envoi (H3).
      try {
        _saisieEnCoursList = await StockHorsLigne.instance.perimesEnCours();
      } on StockHorsLigneException catch (e) {
        _saisieEnCoursList = [];
        _errorMessage = e.message;
      }
      _setLoading(false);
      return;
    }
    _saisieEnCoursList = await _apiService.getSaisiePerimesEnCours();
    _setLoading(false);
  }

  // MODIFICATION : Accepte les filtres de date
  Future<void> loadSaisieHistory({String? dtStart, String? dtEnd}) async {
    if (HorsLigne.instance.offline) {
      _saisieHistoryList = [];
      _setError('Historique des saisies : $kEnLigneUniquement.');
      return;
    }
    _setLoading(true);
    _saisieHistoryList = await _apiService.getSaisiePerimesHistory(
      dtStart: dtStart,
      dtEnd: dtEnd,
    );
    _setLoading(false);
  }
  // FIN MODIFICATION

  Future<void> searchProduct(String query) async {
    if (query.length < 3) {
      productSearch.clear();
      notifyListeners();
      return;
    }
    _setLoading(true);
    await productSearch.run(query); // une recherche plus récente remplace celle-ci
    _isLoading = false;
    notifyListeners();
  }

  void selectProduct(ProductSearchResult product) {
    _selectedProduct = product;
    productSearch.clear();
    notifyListeners();
  }

  void clearSelection() {
    _selectedProduct = null;
    notifyListeners();
  }

  Future<void> addSaisieItem({
    required String lot,
    required String datePeremption, // Format AAAA-MM-JJ
    required int quantite,
  }) async {
    if (_selectedProduct == null) return;

    _setLoading(true);
    _setError(null);
    _setSuccess('');

    if (HorsLigne.instance.offline) {
      final p = _selectedProduct!;
      try {
        await StockHorsLigne.instance.queue.addPerime(
            produitId: p.lgFAMILLEID, cip: p.intCIP, produit: p.strNAME, lot: lot, date: datePeremption, qty: quantite);
        _setSuccess('Produit ajouté hors ligne : envoyé au retour du serveur.');
        await loadSaisieEnCours();
      } catch (e) {
        _setError('Hors ligne : saisie non enregistrée sur l\'appareil ($e).');
      }
      _isLoading = false;
      notifyListeners();
      return;
    }
    final result = await _apiService.addPerimeItem(
      produitId: _selectedProduct!.lgFAMILLEID,
      datePeremption: datePeremption,
      lot: lot,
      quantite: quantite,
    );

    if (result['success'] == true) {
      _setSuccess('Produit ajouté.');
      await loadSaisieEnCours(); // Recharge la liste
    } else {
      String msg = result['message'] ?? 'Erreur inconnue';
      msg = msg.replaceAll(RegExp(r'<[^>]*>'), ' '); // Retire HTML
      _setError(msg);
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> deleteSaisieItem(String itemId) async {
    if (itemId.startsWith(StockHorsLigne.perimeLocalPrefix)) {
      // Saisie faite hors ligne, pas encore envoyée : retirée de la file.
      final ok = await StockHorsLigne.instance.queue.removeLine(itemId.substring(StockHorsLigne.perimeLocalPrefix.length));
      ok ? _setSuccess('Produit retiré.') : _setError('Saisie déjà envoyée : suppression $kEnLigneUniquement.');
      await loadSaisieEnCours();
      return;
    }
    if (HorsLigne.instance.offline) {
      _setError('Retrait d\'une saisie enregistrée sur le serveur : $kEnLigneUniquement.');
      return;
    }
    _setLoading(true);
    final success = await _apiService.deletePerimeItem(itemId);
    if (success) {
      _setSuccess('Produit retiré.');
      await loadSaisieEnCours(); // Recharge la liste
    } else {
      _setError('Erreur lors de la suppression.');
    }
    _setLoading(false);
  }

  Future<bool> validateSaisie() async {
    if (_saisieEnCoursList.isEmpty) {
      _setError("La liste de saisie est vide.");
      return false;
    }

    if (HorsLigne.instance.offline) {
      _setError('Validation de la saisie : $kEnLigneUniquement.');
      return false;
    }
    final String batchId = _saisieEnCoursList.first.id;

    _setLoading(true);
    _setError(null);

    final success = await _apiService.closeSaisiePerimes(batchId);

    if (success) {
      _setSuccess('Saisie validée avec succès.');
      await loadSaisieEnCours(); // Va vider la liste
      await loadSaisieHistory(); // Va mettre à jour l'historique
      return true;
    } else {
      _setError('La validation a échoué.');
      _setLoading(false);
      return false;
    }
  }
}