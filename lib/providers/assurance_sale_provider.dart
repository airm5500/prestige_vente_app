// lib/providers/assurance_sale_provider.dart
// 09/11/2025 03:00 (Gestion Erreur Caisse Fermée)
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/client_assurance.dart';
import 'package:prestige_vente_app/api/models/ayant_droit.dart';
import 'package:prestige_vente_app/api/models/tiers_payant_assurance.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/api/models/assurance_sale_summary.dart';

enum AssuranceStep {
  clientSearch,
  bonAndAyantDroit,
  productSearch
}

class ActiveTiersPayant {
  ClientTiersPayant originalData;
  int taux;

  ActiveTiersPayant({required this.originalData, required this.taux});

  String get compteTp => originalData.compteTp;
  String get tpFullName => originalData.tpFullName;
  String get numSecurity => originalData.numSecurity;
}


class AssuranceSaleProvider with ChangeNotifier {
  final ApiService _apiService;
  final String _authenticatedUserId;

  static const String _natureVenteId = "1";
  static const String _typeVenteId = "2";

  bool _isLoading = false;
  String? _errorMessage;
  AssuranceStep _currentStep = AssuranceStep.clientSearch;

  List<ClientAssurance> _clientSearchResults = [];
  ClientAssurance? _selectedClient;
  List<AyantDroit> _ayantDroitList = [];
  AyantDroit? _selectedAyantDroit;

  List<ActiveTiersPayant> _activeTiersPayants = [];

  List<TiersPayantAssurance> _tiersPayantSearchResults = [];
  Map<String, String> _bonNumbers = {};

  List<ProductSearchResult> _productSearchResults = [];
  String? _currentVenteId;
  List<SaleItemDetail> _cartItems = [];
  AssuranceSaleSummary? _saleSummary;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  AssuranceStep get currentStep => _currentStep;

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

  AssuranceSaleProvider(this._apiService, this._authenticatedUserId);

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


  void startNewAssuranceSale() {
    _isLoading = false;
    _errorMessage = null;
    _currentStep = AssuranceStep.clientSearch;
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

  // --- ÉTAPE 1: GESTION CLIENT (Inchangé) ---
  Future<void> searchClient(String query) async {
    if (query.length < 2) {
      _clientSearchResults = [];
      notifyListeners();
      return;
    }
    _setLoading(true);
    _clientSearchResults = await _apiService.searchClientAssurance(query);
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
        ActiveTiersPayant(originalData: tp, taux: tp.taux)
    ).toList();

    _bonNumbers = {};
    for (var tp in _activeTiersPayants) {
      _bonNumbers[tp.compteTp] = "";
    }

    try {
      _selectedAyantDroit = client.ayantDroits.firstWhere(
              (ad) => ad.lgAYANTSDROITSID == client.lgCLIENTID
      );
    } catch (e) {
      _selectedAyantDroit = client.ayantDroits.isNotEmpty ? client.ayantDroits.first : null;
    }
    _ayantDroitList = client.ayantDroits;

    _currentStep = AssuranceStep.bonAndAyantDroit;
    _setLoading(false);
  }

  void returnToClientSearch() {
    startNewAssuranceSale();
  }

  Future<List<TiersPayantAssurance>> searchTiersPayantAssurance(String query) async {
    if (query.length < 3) {
      _tiersPayantSearchResults = [];
      notifyListeners();
      return [];
    }
    _tiersPayantSearchResults = await _apiService.searchTiersPayantsAssurance(query);
    notifyListeners();
    return _tiersPayantSearchResults;
  }

  Future<bool> createClient(String firstName, String lastName, String numSecu, TiersPayantAssurance tiersPayant, int pourcentage) async {
    _setLoading(true);
    _setError(null);

    final newClient = await _apiService.createClientAssurance(
      firstName: firstName, // Nom
      lastName: lastName,   // Prénom
      numSecu: numSecu,
      tiersPayantId: tiersPayant.lgTIERSPAYANTID,
      pourcentage: pourcentage,
    );
    if (newClient != null) {
      await selectClient(newClient);
      return true;
    } else {
      _setError("Échec de la création du client.");
      _setLoading(false);
      return false;
    }
  }

  Future<bool> addTiersPayantToClient(TiersPayantAssurance tiersPayant, String numSecu, int pourcentage) async {
    if (_selectedClient == null) return false;

    if (_selectedClient!.tiersPayants.any((tp) => tp.lgTIERSPAYANTID == tiersPayant.lgTIERSPAYANTID)) {
      _setError("${tiersPayant.strNAME} est déjà associé à ce client.");
      notifyListeners();
      return false;
    }

    _setLoading(true);
    _setError(null);

    final Map<String, dynamic> newTpPayload = {
      "bIsAbsolute": false,
      "compteTp": "",
      "dbPLAFONDENCOURS": 0,
      "lgTIERSPAYANTID": tiersPayant.lgTIERSPAYANTID,
      "numSecurity": numSecu,
      "order": _selectedClient!.tiersPayants.length + 1,
      "taux": pourcentage,
      "tpFullName": tiersPayant.strFULLNAME
    };

    final updatedClient = await _apiService.addTiersPayantToClient(
        existingClient: _selectedClient!,
        newTiersPayantPayload: newTpPayload
    );

    if (updatedClient != null) {
      await selectClient(updatedClient);
      return true;
    } else {
      _setError("Échec de l'ajout du tiers payant.");
      _setLoading(false);
      return false;
    }
  }

  // --- ÉTAPE 2: GESTION AYANT DROIT ET BONS (Inchangé) ---
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

  void toggleTiersPayant(ClientTiersPayant tp, bool isActive) {
    if (isActive) {
      if (_activeTiersPayants.indexWhere((atp) => atp.originalData.compteTp == tp.compteTp) == -1) {
        _activeTiersPayants.add(ActiveTiersPayant(originalData: tp, taux: tp.taux));
        _bonNumbers[tp.compteTp] = "";
      }
    } else {
      _activeTiersPayants.removeWhere((atp) => atp.originalData.compteTp == tp.compteTp);
      _bonNumbers.remove(tp.compteTp);
    }
    _saleSummary = null;
    notifyListeners();
  }

  void updateTiersPayantTaux(String compteTp, int newTaux) {
    try {
      final tp = _activeTiersPayants.firstWhere((atp) => atp.originalData.compteTp == compteTp);
      tp.taux = newTaux;
      _saleSummary = null;
      notifyListeners();
    } catch (e) {
      // Ne devrait pas arriver
    }
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
    _currentStep = AssuranceStep.productSearch;
    notifyListeners();
    return true;
  }


  void returnToBonStep() {
    _currentStep = AssuranceStep.bonAndAyantDroit;
    _saleSummary = null;
    notifyListeners();
  }

  // --- ÉTAPE 3: GESTION DU PANIER (Inchangé) ---
  Future<void> searchProducts(String query) async {
    if (query.length < 3) {
      _productSearchResults = [];
      notifyListeners();
      return;
    }
    _setLoading(true);
    _productSearchResults = await _apiService.searchProducts(query);
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
        "taux": tp.taux
      };
    }).toList();
  }

  Future<void> addProductToCart(ProductSearchResult product, int quantity) async {
    if (_selectedClient == null || _selectedAyantDroit == null) {
      _setError("Aucun client ou ayant droit sélectionné.");
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
      natureVenteId: _natureVenteId,
      typeVenteId: _typeVenteId,
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

  // --- ÉTAPE 4: CALCUL NET (Inchangé) ---
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

    // NOTE: La validation du N° Bon n'est pas gérée ici,
    // l'API 'terminerPrevente' ne semble pas la supporter.
    final success = await _apiService.terminerPrevente(_currentVenteId!);
    if (!success) {
      _setError("La finalisation de la prévente a échoué.");
      _saleSummary = null;
    }
    _setLoading(false);
    return success;
  }

  Future<List<PaymentMethod>> getFilteredPaymentMethods() async {
    final allMethods = await _apiService.getPaymentMethods();
    const allowedIds = {"3", "8", "9", "7", "10"};
    return allMethods.where((m) => allowedIds.contains(m.id)).toList();
  }

  // MODIFICATION : Renvoie maintenant Map<String, dynamic>
  Future<Map<String, dynamic>> cloturerVente(PaymentMethod? paymentMethod) async {
    if (_currentVenteId == null || _selectedClient == null || _selectedAyantDroit == null || _saleSummary == null) {
      _setError("Données de vente incomplètes.");
      return {"success": false, "msg": "Données de vente incomplètes."};
    }

    final PaymentMethod finalPaymentMethod = paymentMethod ?? PaymentMethod(id: '1', name: 'ESPECES');

    _setLoading(true);
    _setError(null);
    notifyListeners();

    final tiersPayantPayload = _buildTiersPayantPayload();

    final Map<String, dynamic> result = await _apiService.cloturerVenteAssurance(
      venteId: _currentVenteId!,
      clientId: _selectedClient!.lgCLIENTID,
      ayantDroitId: _selectedAyantDroit!.lgAYANTSDROITSID,
      natureVenteId: _natureVenteId,
      typeVenteId: _typeVenteId,
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
        _currentStep = AssuranceStep.bonAndAyantDroit;
        _saleSummary = null;

      } else {
        _setError(errorMsg);
      }
    }

    _setLoading(false);
    return result; // Renvoie la réponse complète
  }
}