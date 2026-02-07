// lib/providers/carnet_sale_provider.dart
// 09/11/2025 19:40 (Correction 'toggleTiersPayant' manquant)
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/client_assurance.dart';
import 'package:prestige_vente_app/api/models/ayant_droit.dart';
import 'package:prestige_vente_app/api/models/tiers_payant_assurance.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/api/models/assurance_sale_summary.dart';
import 'package:shared_preferences/shared_preferences.dart';

// On réutilise la même énumération que l'assurance
enum CarnetStep {
  clientSearch,
  bonAndAyantDroit,
  productSearch
}
// On réutilise le même modèle que l'assurance
class ActiveTiersPayant {
  ClientTiersPayant originalData;
  int taux; // Sera toujours 100

  ActiveTiersPayant({required this.originalData, required this.taux});

  String get compteTp => originalData.compteTp;
  String get tpFullName => originalData.tpFullName;
  String get numSecurity => originalData.numSecurity;
}


class CarnetSaleProvider with ChangeNotifier {
  final ApiService _apiService;
  final String _authenticatedUserId;

  // FIXÉ : Nature Vente "1" (PRESCRIPTION)
  static const String _natureVenteId = "1";
  // FIXÉ : Type Vente "3" (CARNET)
  static const String _typeVenteId = "3";

  bool _isLoading = false;
  String? _errorMessage;
  CarnetStep _currentStep = CarnetStep.clientSearch;

  List<ClientAssurance> _clientSearchResults = [];
  ClientAssurance? _selectedClient;

  AyantDroit? _selectedAyantDroit;
  List<AyantDroit> _ayantDroitList = [];

  List<ActiveTiersPayant> _activeTiersPayants = [];
  List<TiersPayantAssurance> _tiersPayantSearchResults = [];
  Map<String, String> _bonNumbers = {};

  List<ProductSearchResult> _productSearchResults = [];
  String? _currentVenteId;
  List<SaleItemDetail> _cartItems = [];
  AssuranceSaleSummary? _saleSummary;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  CarnetStep get currentStep => _currentStep;

  List<ClientAssurance> get clientSearchResults => _clientSearchResults;
  ClientAssurance? get selectedClient => _selectedClient;

  List<AyantDroit> get ayantDroitList => _ayantDroitList;
  AyantDroit? get selectedAyantDroit => _selectedAyantDroit;

  List<ActiveTiersPayant> get activeTiersPayants => _activeTiersPayants;
  List<TiersPayantAssurance> get tiersPayantSearchResults => _tiersPayantSearchResults;
  Map<String, String> get bonNumbers => _bonNumbers;

  List<ProductSearchResult> get productSearchResults => _productSearchResults;
  String? get currentVenteId => _currentVenteId;
  List<SaleItemDetail> get cartItems => _cartItems;
  AssuranceSaleSummary? get saleSummary => _saleSummary;

  CarnetSaleProvider(this._apiService, this._authenticatedUserId);

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String? message) {
    _errorMessage = message;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void startNewCarnetSale() {
    _isLoading = false;
    _errorMessage = null;
    _currentStep = CarnetStep.clientSearch;
    _clientSearchResults = [];
    _selectedClient = null;
    _ayantDroitList = [];
    _selectedAyantDroit = null;
    _activeTiersPayants = [];
    _tiersPayantSearchResults = [];
    _bonNumbers = {};
    _productSearchResults = [];
    _currentVenteId = null;
    _cartItems = [];
    _saleSummary = null;
    notifyListeners();
  }

  // --- AJOUT : GESTION MODE SCAN RAPIDE ---
  bool _isQuickScanMode = false;
  bool get isQuickScanMode => _isQuickScanMode;

  void toggleQuickScanMode() {
    _isQuickScanMode = !_isQuickScanMode;
    notifyListeners();
  }

  // --- ÉTAPE 1: GESTION CLIENT ---

  Future<void> searchClient(String query) async {
    if (query.length < 2) {
      _clientSearchResults = [];
      notifyListeners();
      return;
    }
    _setLoading(true);
    _clientSearchResults = await _apiService.searchClientCarnet(query);
    _setLoading(false);
  }

  void clearClientSearch() {
    _clientSearchResults = [];
    notifyListeners();
  }

  Future<void> selectClient(ClientAssurance client) async {
    _setLoading(true);
    _selectedClient = client;
    _clientSearchResults = [];

    _activeTiersPayants = client.tiersPayants.map((tp) =>
        ActiveTiersPayant(originalData: tp, taux: tp.taux) // 100%
    ).toList();

    _bonNumbers = {};
    for (var tp in _activeTiersPayants) {
      _bonNumbers[tp.compteTp] = "";
    }

    _ayantDroitList = client.ayantDroits;
    try {
      _selectedAyantDroit = client.ayantDroits.firstWhere(
              (ad) => ad.lgAYANTSDROITSID == client.lgCLIENTID
      );
    } catch (e) {
      _selectedAyantDroit = client.ayantDroits.isNotEmpty ? client.ayantDroits.first : null;
    }

    if (_selectedAyantDroit == null) {
      _selectedAyantDroit = AyantDroit(
          lgAYANTSDROITSID: client.lgCLIENTID,
          lgCLIENTID: client.lgCLIENTID,
          fullName: client.fullName,
          strFIRSTNAME: client.strFIRSTNAME,
          strLASTNAME: client.strLASTNAME,
          strNUMEROSECURITESOCIAL: client.strNUMEROSECURITESOCIAL,
          strSEXE: ""
      );
      _ayantDroitList.add(_selectedAyantDroit!);
    }

    _currentStep = CarnetStep.bonAndAyantDroit;
    _setLoading(false);
  }

  void returnToClientSearch() {
    startNewCarnetSale();
  }

  Future<List<TiersPayantAssurance>> searchTiersPayantCarnet(String query) async {
    if (query.length < 3) {
      _tiersPayantSearchResults = [];
      notifyListeners();
      return [];
    }
    _tiersPayantSearchResults = await _apiService.searchTiersPayantCarnet(query);
    notifyListeners();
    return _tiersPayantSearchResults;
  }

  Future<bool> createClient(String firstName, String lastName, String numSecu, TiersPayantAssurance tiersPayant) async {
    _setLoading(true);
    _setError(null);

    final newClient = await _apiService.createClientCarnet(
      firstName: firstName, // Nom
      lastName: lastName,   // Prénom
      numSecu: numSecu,
      tiersPayantId: tiersPayant.lgTIERSPAYANTID,
    );
    if (newClient != null) {
      await selectClient(newClient);
      return true;
    } else {
      _setError("Échec de la création du client carnet.");
      _setLoading(false);
      return false;
    }
  }

  // --- ÉTAPE 2: GESTION AYANT DROIT ET BONS ---

  Future<void> loadAyantDroits() async {
    if (_selectedClient == null) return;
    _setLoading(true);
    _ayantDroitList = await _apiService.getAyantDroits(_selectedClient!.lgCLIENTID);
    _setLoading(false);
  }

  void selectAyantDroit(AyantDroit? ayantDroit) {
    _selectedAyantDroit =ayantDroit;
    notifyListeners();
  }

  // MODIFICATION : Ajout de la fonction manquante
  void toggleTiersPayant(ClientTiersPayant tp, bool isActive) {
    if (isActive) {
      if (_activeTiersPayants.indexWhere((atp) => atp.originalData.compteTp == tp.compteTp) == -1) {
        _activeTiersPayants.add(ActiveTiersPayant(originalData: tp, taux: tp.taux));
        _bonNumbers[tp.compteTp] = "";
      }
    } else {
      // Sécurité : ne pas désactiver le dernier TP
      if (_activeTiersPayants.length > 1) {
        _activeTiersPayants.removeWhere((atp) => atp.originalData.compteTp == tp.compteTp);
        _bonNumbers.remove(tp.compteTp);
      }
    }
    _saleSummary = null;
    notifyListeners();
  }

  void updateTiersPayantTaux(String compteTp, int newTaux) {
    _saleSummary = null;
    notifyListeners();
  }

  Future<bool> createAyantDroit(String firstName, String lastName, String numSecu) async {
    if (_selectedClient == null) return false;
    _setLoading(true);
    _setError(null);

    final newAyantDroit = await _apiService.createAyantDroit(
      clientId: _selectedClient!.lgCLIENTID,
      firstName: firstName, // Nom
      lastName: lastName,   // Prénom
      numSecu: numSecu,
    );

    if (newAyantDroit != null) {
      await loadAyantDroits();
      try {
        _selectedAyantDroit = _ayantDroitList.firstWhere((ad) => ad.lgAYANTSDROITSID == newAyantDroit.lgAYANTSDROITSID);
      } catch(e) {
        _selectedAyantDroit = _ayantDroitList.isNotEmpty ? _ayantDroitList.first : null;
      }
      _setLoading(false);
      return true;
    } else {
      _setError("Échec de la création de l'ayant droit.");
      _setLoading(false);
      return false;
    }
  }

  void updateBonNumber(String compteTpId, String numBon) {
    if (_bonNumbers.containsKey(compteTpId)) {
      _bonNumbers[compteTpId] = numBon;
    }
  }

  bool validateBonsAndProceed() {
    _currentStep = CarnetStep.productSearch;
    notifyListeners();
    return true;
  }

  void returnToBonStep() {
    _currentStep = CarnetStep.bonAndAyantDroit;
    _saleSummary = null;
    notifyListeners();
  }

  // --- ÉTAPE 3: GESTION DU PANIER ---

  Future<void> searchProducts(String query) async {
    if (query.length < 3) {
      _productSearchResults = [];
      notifyListeners();
      return;
    }
    _setLoading(true);
    //_productSearchResults = await _apiService.searchProducts(query);
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
    _productSearchResults = results;
    _setLoading(false);
  }

  void clearProductSearch() {
    _productSearchResults = [];
    notifyListeners();
  }

  List<Map<String, dynamic>> _buildTiersPayantPayload() {
    return _activeTiersPayants.map((tp) {
      return {
        "compteTp": tp.compteTp,
        "numBon": _bonNumbers[tp.compteTp] ?? "",
        "taux": tp.taux // 100%
      };
    }).toList();
  }

  Future<void> addProductToCart(ProductSearchResult product, int quantity) async {
    if (_selectedClient == null) {
      _setError("Aucun client sélectionné.");
      return;
    }
    if (_selectedAyantDroit == null) {
      _setError("Erreur interne: Ayant droit non défini.");
      return;
    }

    _setLoading(true);
    _setError(null);
    final tiersPayantPayload = _buildTiersPayantPayload();

    final newVenteId = await _apiService.addAssuranceSaleItem(
      produitId: product.lgFAMILLEID,
      qte: quantity,
      itemPu: product.intPRICE,
      clientId: _selectedClient!.lgCLIENTID,
      ayantDroitId: _selectedAyantDroit!.lgAYANTSDROITSID,
      natureVenteId: _natureVenteId, // "1"
      typeVenteId: _typeVenteId,   // "3"
      userVendeurId: _authenticatedUserId,
      tierspayants: tiersPayantPayload,
      venteId: _currentVenteId,
    );

    if (newVenteId != null) {
      _currentVenteId = newVenteId;
      await _refreshCart();
    } else {
      _setError("Erreur lors de l'ajout du produit.");
    }
    clearProductSearch();
    _setLoading(false);
  }

  Future<void> _refreshCart() async {
    if (_currentVenteId == null) {
      _cartItems = [];
      notifyListeners();
      return;
    }
    _cartItems = await _apiService.getSaleDetails(_currentVenteId!);
    _saleSummary = null;
    notifyListeners();
  }

  Future<void> removeProductFromCart(String itemId) async {
    _setLoading(true);
    _setError(null);
    final success = await _apiService.removeItemFromSale(itemId);
    if (success) {
      await _refreshCart();
    } else {
      _setError("Erreur lors de la suppression.");
    }
    _setLoading(false);
  }

  Future<void> updateCartItem(SaleItemDetail item, int newQuantity, int newPrice) async {
    _setLoading(true);
    _setError(null);
    final success = await _apiService.updateSaleItem(
      itemId: item.lgPREENREGISTREMENTDETAILID,
      produitId: item.lgFAMILLEID,
      qte: newQuantity,
      itemPu: newPrice,
    );
    if (success) {
      await _refreshCart();
    } else {
      _setError("Erreur de mise à jour.");
    }
    _setLoading(false);
  }

  // --- ÉTAPE 4: CALCUL NET ---

  Future<void> calculateNet() async {
    if (_currentVenteId == null) return;
    _setLoading(true);
    _setError(null);
    _saleSummary = null;
    final tiersPayantPayload = _buildTiersPayantPayload();

    final summary = await _apiService.calculateNetAssurance(
      venteId: _currentVenteId!,
      tierspayants: tiersPayantPayload,
    );

    if (summary != null) {
      _saleSummary = summary;
    } else {
      _setError("Erreur lors du calcul du net.");
    }
    _setLoading(false);
  }

  // --- ÉTAPE 5 & 6: VALIDATION ---

  Future<bool> terminerPrevente() async {
    if (_currentVenteId == null) return false;
    _setLoading(true);
    _setError(null);

    final success = await _apiService.terminerPrevente(_currentVenteId!);
    if (!success) {
      _setError("La finalisation de la prévente a échoué.");
      _saleSummary = null;
    }
    _setLoading(false);
    return success;
  }

  Future<Map<String, dynamic>> cloturerVenteCarnet() async {
    if (_currentVenteId == null || _selectedClient == null || _saleSummary == null) {
      _setError("Données de vente incomplètes.");
      return {"success": false, "msg": "Données de vente incomplètes."};
    }
    if (_selectedAyantDroit == null) {
      _setError("Erreur interne: Ayant droit non défini.");
      return {"success": false, "msg": "Erreur interne: Ayant droit non défini."};
    }

    final PaymentMethod finalPaymentMethod = PaymentMethod(id: '1', name: 'ESPECES');

    _setLoading(true);
    _setError(null);
    notifyListeners();

    final tiersPayantPayload = _buildTiersPayantPayload();

    final Map<String, dynamic> result = await _apiService.cloturerVenteAssurance(
      venteId: _currentVenteId!,
      clientId: _selectedClient!.lgCLIENTID,
      ayantDroitId: _selectedAyantDroit!.lgAYANTSDROITSID,
      natureVenteId: _natureVenteId, // "1"
      typeVenteId: _typeVenteId,   // "3"
      userVendeurId: _authenticatedUserId,
      summary: _saleSummary!,
      typeReglementId: finalPaymentMethod.id,
      tierspayants: tiersPayantPayload,
    );

    if (result['success'] == false) {
      String errorMsg = result['msg'] ?? "La clôture de la vente a échoué.";

      if (errorMsg.contains("est déjà utilisé")) {
        errorMsg = errorMsg.replaceAll(RegExp(r'<[^>]*>'), '');
        _setError(errorMsg);
        _currentStep = CarnetStep.bonAndAyantDroit;
        _saleSummary = null;
      } else {
        _setError(errorMsg);
      }
    }

    _setLoading(false);
    return result;
  }
}