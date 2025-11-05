// lib/providers/assurance_sale_provider.dart
// 02/11/2025 15:50 (Corrigé)
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/client_assurance.dart';
import 'package:prestige_vente_app/api/models/ayant_droit.dart';
import 'package:prestige_vente_app/api/models/tiers_payant_assurance.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/api/models/assurance_sale_summary.dart';

// Les étapes du processus de vente assurance
enum AssuranceStep {
  clientSearch, // Étape 1: Recherche/Création Client
  bonAndAyantDroit, // Étape 2: Saisie des N° de bon / Choix Ayant Droit
  productSearch // Étape 3: Ajout des produits
}

class AssuranceSaleProvider with ChangeNotifier {
  final ApiService _apiService;
  final String _authenticatedUserId; // ID de l'utilisateur connecté

  // --- IDs Statiques (selon vos spécifications) ---
  static const String _natureVenteId = "1"; // PRESCRIPTION
  static const String _typeVenteId = "2"; // ASSURANCE_MUTUELLE

  // --- États de chargement et d'erreur ---
  bool _isLoading = false;
  String? _errorMessage;

  // --- État de l'étape actuelle ---
  AssuranceStep _currentStep = AssuranceStep.clientSearch;

  // --- État: Client et Ayants Droit ---
  List<ClientAssurance> _clientSearchResults = [];
  ClientAssurance? _selectedClient;
  List<AyantDroit> _ayantDroitList = [];
  AyantDroit? _selectedAyantDroit;

  // --- État: Tiers Payants et N° de Bon ---
  List<TiersPayantAssurance> _tiersPayantSearchResults = [];
  Map<String, String> _bonNumbers = {}; // { compteTpId: "numBon" }

  // --- État: Vente et Panier ---
  List<ProductSearchResult> _productSearchResults = [];
  String? _currentVenteId;
  List<SaleItemDetail> _cartItems = [];
  AssuranceSaleSummary? _saleSummary;

  // --- Getters Publics ---
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  AssuranceStep get currentStep => _currentStep;

  List<ClientAssurance> get clientSearchResults => _clientSearchResults;
  ClientAssurance? get selectedClient => _selectedClient;
  List<AyantDroit> get ayantDroitList => _ayantDroitList;
  AyantDroit? get selectedAyantDroit => _selectedAyantDroit;

  List<TiersPayantAssurance> get tiersPayantSearchResults => _tiersPayantSearchResults;
  Map<String, String> get bonNumbers => _bonNumbers;

  List<ProductSearchResult> get productSearchResults => _productSearchResults;
  String? get currentVenteId => _currentVenteId;
  List<SaleItemDetail> get cartItems => _cartItems;
  AssuranceSaleSummary? get saleSummary => _saleSummary;

  // --- Constructeur ---
  AssuranceSaleProvider(this._apiService, this._authenticatedUserId);

  // --- Méthodes de Gestion d'État ---

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String? message) {
    _errorMessage = message;
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
    _tiersPayantSearchResults = [];
    _bonNumbers = {};
    _productSearchResults = [];
    _currentVenteId = null;
    _cartItems = [];
    _saleSummary = null;
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

    // Initialiser la map des numéros de bon
    _bonNumbers = {};
    for (var tp in client.tiersPayants) {
      _bonNumbers[tp.compteTp] = "";
    }

    // *** CORRECTION DE L'ERREUR 1 ***
    // Le client est son propre ayant droit par défaut
    // On le cherche dans la liste des ayants droits fournie
    try {
      // Essaye de trouver le client lui-même dans la liste des ayants droits
      _selectedAyantDroit = client.ayantDroits.firstWhere(
              (ad) => ad.lgAYANTSDROITSID == client.lgCLIENTID
      );
    } catch (e) {
      // Si non trouvé (ou si la liste est vide), on prend le premier ou null
      _selectedAyantDroit = client.ayantDroits.isNotEmpty ? client.ayantDroits.first : null;
    }
    _ayantDroitList = client.ayantDroits;
    // *** FIN CORRECTION ***

    _currentStep = AssuranceStep.bonAndAyantDroit;
    _setLoading(false);
  }

  void returnToClientSearch() {
    startNewAssuranceSale(); // Recommence tout
  }

  Future<void> searchTiersPayantAssurance(String query) async {
    if (query.length < 2) {
      _tiersPayantSearchResults = [];
      notifyListeners();
      return;
    }
    // Pas de _setLoading pour ne pas bloquer l'UI de création client
    _tiersPayantSearchResults = await _apiService.searchTiersPayantsAssurance(query);
    notifyListeners();
  }

  Future<bool> createClient(String firstName, String lastName, String numSecu, TiersPayantAssurance tiersPayant, int pourcentage) async {
    _setLoading(true);
    _setError(null);
    final newClient = await _apiService.createClientAssurance(
      firstName: firstName,
      lastName: lastName,
      numSecu: numSecu,
      tiersPayantId: tiersPayant.lgTIERSPAYANTID,
      pourcentage: pourcentage,
    );
    if (newClient != null) {
      await selectClient(newClient); // Sélectionne le client nouvellement créé
      return true;
    } else {
      _setError("Échec de la création du client.");
      _setLoading(false);
      return false;
    }
  }

  Future<bool> addTiersPayantToClient(TiersPayantAssurance tiersPayant, String numSecu, int pourcentage) async {
    if (_selectedClient == null) return false;
    _setLoading(true);
    _setError(null);

    final updatedClient = await _apiService.addTiersPayantToClient(
        clientId: _selectedClient!.lgCLIENTID,
        firstName: _selectedClient!.strFIRSTNAME,
        lastName: _selectedClient!.strLASTNAME,
        tiersPayantId: tiersPayant.lgTIERSPAYANTID,
        numSecu: numSecu,
        pourcentage: pourcentage,
        order: _selectedClient!.tiersPayants.length + 1,
        compteTp: "" // Le serveur va générer le compteTp
    );

    if (updatedClient != null) {
      // Met à jour le client sélectionné avec les nouveaux TPs
      await selectClient(updatedClient);
      return true;
    } else {
      _setError("Échec de l'ajout du tiers payant.");
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

  void selectAyantDroit(AyantDroit ayantDroit) {
    _selectedAyantDroit = ayantDroit;
    notifyListeners();
  }

  Future<bool> createAyantDroit(String firstName, String lastName, String numSecu) async {
    if (_selectedClient == null) return false;
    _setLoading(true);
    _setError(null);

    final newAyantDroit = await _apiService.createAyantDroit(
      clientId: _selectedClient!.lgCLIENTID,
      firstName: firstName,
      lastName: lastName,
      numSecu: numSecu,
    );

    if (newAyantDroit != null) {
      await loadAyantDroits(); // Recharge la liste
      _selectedAyantDroit = newAyantDroit; // Le sélectionne
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
      notifyListeners();
    }
  }

  bool validateBonsAndProceed() {
    _setError(null);
    for (var bon in _bonNumbers.values) {
      if (bon.isEmpty) {
        _setError("Tous les numéros de bon sont requis.");
        notifyListeners();
        return false;
      }
    }
    _currentStep = AssuranceStep.productSearch;
    notifyListeners();
    return true;
  }

  void returnToBonStep() {
    _currentStep = AssuranceStep.bonAndAyantDroit;
    _saleSummary = null; // Efface le calcul net précédent
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
    _productSearchResults = await _apiService.searchProducts(query);
    _setLoading(false);
  }

  void clearProductSearch() {
    _productSearchResults = [];
    notifyListeners();
  }

  List<Map<String, dynamic>> _buildTiersPayantPayload() {
    if (_selectedClient == null) return [];

    return _selectedClient!.tiersPayants.map((tp) {
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
    _saleSummary = null; // Invalide le calcul net après modif panier
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
    }
    _setLoading(false);
    return success;
  }

  Future<List<PaymentMethod>> getFilteredPaymentMethods() async {
    final allMethods = await _apiService.getPaymentMethods();
    // Filtre pour garder uniquement les 5 modes spécifiés
    const allowedIds = {"3", "8", "9", "7", "10"};
    return allMethods.where((m) => allowedIds.contains(m.id)).toList();
  }

  Future<bool> cloturerVente(PaymentMethod paymentMethod) async {
    if (_currentVenteId == null || _selectedClient == null || _selectedAyantDroit == null || _saleSummary == null) {
      _setError("Données de vente incomplètes.");
      return false;
    }

    _setLoading(true);
    _setError(null);

    final tiersPayantPayload = _buildTiersPayantPayload();

    final success = await _apiService.cloturerVenteAssurance(
      venteId: _currentVenteId!,
      clientId: _selectedClient!.lgCLIENTID,
      ayantDroitId: _selectedAyantDroit!.lgAYANTSDROITSID,
      natureVenteId: _natureVenteId,
      typeVenteId: _typeVenteId,
      userVendeurId: _authenticatedUserId,
      summary: _saleSummary!,
      typeReglementId: paymentMethod.id,
      tierspayants: tiersPayantPayload,
    );

    if (!success) {
      _setError("La clôture de la vente a échoué.");
    }
    _setLoading(false);
    return success;
  }
}