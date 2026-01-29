// lib/providers/proforma_provider.dart
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/proforma_models.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/api/models/product.dart'; // Pour ProductSearchResult

class ProformaProvider with ChangeNotifier {
  final ApiService _apiService;

  String? _currentSaleId;
  String? get currentSaleId => _currentSaleId;

  String? _currentSaleRef;
  String? get currentSaleRef => _currentSaleRef;

  // Sélection Type & Client
  TypeDevis? _selectedTypeDevis;
  TypeDevis? get selectedTypeDevis => _selectedTypeDevis;

  ClientModel? _selectedClient;
  ClientModel? get selectedClient => _selectedClient;

  // Remise
  RemiseModel? _selectedRemise;
  RemiseModel? get selectedRemise => _selectedRemise;

  List<SaleLine> _cartItems = [];
  List<SaleLine> get cartItems => _cartItems;

  bool _isLoading = false;
  bool get isLoading => _isLoading;
  String _errorMessage = '';
  String get errorMessage => _errorMessage;

  int _totalAmount = 0;
  int get totalAmount => _totalAmount;
  int _montantRemise = 0; // Montant de la remise calculée
  int get montantRemise => _montantRemise;
  int _netAPayer = 0;
  int get netAPayer => _netAPayer;

  ProformaProvider(this._apiService);

  void setTypeDevis(TypeDevis? type) {
    _selectedTypeDevis = type;
    notifyListeners();
  }

  void setClient(ClientModel? client) {
    _selectedClient = client;
    notifyListeners();
  }

  void resetSale() {
    _currentSaleId = null;
    _currentSaleRef = null;
    _selectedTypeDevis = null;
    _selectedClient = null;
    _selectedRemise = null;
    _cartItems = [];
    _totalAmount = 0;
    _montantRemise = 0;
    _netAPayer = 0;
    _errorMessage = '';
    notifyListeners();
  }

  // Charger une proforma existante
  Future<void> loadExistingProforma(ProformaListItem item) async {
    _isLoading = true;
    notifyListeners();

    try {
      // 1. Initialisation de base avec les infos de la liste
      _currentSaleId = item.lgPREENREGISTREMENTID;
      _currentSaleRef = item.strREF;

      // 2. Chargement des produits (Panier)
      await _refreshCart();

      // 3. Chargement DÉTAILLÉ du client via l'API (Respect du processus point 4)
      // On utilise l'ID client qui vient de l'item de la liste
      final clientDetails = await _apiService.getClientForSale(item.clientId, _currentSaleId!);

      if (clientDetails != null) {
        _selectedClient = clientDetails;
      } else {
        // Fallback : Si l'API échoue, on utilise au moins le nom qu'on avait dans la liste
        _selectedClient = ClientModel(
            lgCLIENTID: item.clientId,
            strFIRSTNAME: '',
            strLASTNAME: '',
            fullName: item.strClientFullName
        );
      }

      // 4. (Optionnel) Si vous voulez pré-sélectionner le type de vente,
      // il faudrait que ProformaListItem contienne aussi le typeVenteId,
      // ou le déduire. Pour l'instant on garde le type par défaut ou null.

    } catch (e) {
      _errorMessage = "Erreur lors du rappel de la proforma: $e";
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Ajouter Produit
  Future<bool> addProduct(ProductSearchResult product, int quantity) async {
    if (_selectedTypeDevis == null || _selectedClient == null) {
      _errorMessage = "Veuillez sélectionner un Type et un Client.";
      notifyListeners();
      return false;
    }

    _isLoading = true;
    notifyListeners();
    bool success = false;

    try {
      if (_currentSaleId == null) {
        // Création (/vente/devis)
        final result = await _apiService.addFirstDevisItem(
          clientId: _selectedClient!.lgCLIENTID,
          typeVenteId: _selectedTypeDevis!.lgTYPEVENTEID,
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
        // Ajout (/vente/add/item)
        success = await _apiService.addNextDevisItem(
          venteId: _currentSaleId!,
          clientId: _selectedClient!.lgCLIENTID,
          typeVenteId: _selectedTypeDevis!.lgTYPEVENTEID,
          produitId: product.lgFAMILLEID,
          itemPu: product.intPRICE,
          qte: quantity,
        );
      }

      if (success) {
        await _refreshCart();
        // Si une remise était déjà sélectionnée, il faut recalculer le net
        if (_selectedRemise != null) {
          await applyRemise(_selectedRemise!);
        }
      }
    } catch (e) {
      _errorMessage = "Erreur ajout produit: $e";
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return success;
  }

  // Update & Remove (Utilisent les mêmes endpoints que Vente Dépôt "VNO")
  Future<bool> updateItem(SaleLine item, int newQty, int newPrice) async {
    _isLoading = true;
    notifyListeners();
    // On utilise les endpoints génériques VNO (voir logs)
    final success = await _apiService.updateDepotItem(
      itemId: item.lgPREENREGISTREMENTDETAILID,
      produitId: item.lgFAMILLEID,
      itemPu: newPrice,
      qte: newQty,
    );
    if (success) {
      await _refreshCart();
      if (_selectedRemise != null) await applyRemise(_selectedRemise!);
    }
    _isLoading = false;
    notifyListeners();
    return success;
  }

  Future<bool> removeItem(String itemId) async {
    _isLoading = true;
    notifyListeners();
    final success = await _apiService.removeDepotItem(itemId);
    if (success) {
      await _refreshCart();
      if (_selectedRemise != null) await applyRemise(_selectedRemise!);
    }
    _isLoading = false;
    notifyListeners();
    return success;
  }

  // Appliquer Remise
  // Dans lib/providers/proforma_provider.dart

  Future<void> applyRemise(RemiseModel remise) async {
    if (_currentSaleId == null) return;
    _selectedRemise = remise;
    _isLoading = true;
    notifyListeners();

    // 1. Appliquer la remise (Si cette méthode existe déjà et est identique, ok, sinon renommez-la aussi)
    await _apiService.applyRemise(venteId: _currentSaleId!, remiseId: remise.lgREMISEID);

    // 2. Calculer le Net (UTILISATION DE LA NOUVELLE MÉTHODE)
    // C'est ici qu'on change pour utiliser calculateNetProforma
    final calc = await _apiService.calculateNetProforma(venteId: _currentSaleId!, remiseId: remise.lgREMISEID);

    if (calc != null) {
      _montantRemise = (calc['remise'] as num).toInt();
      _netAPayer = (calc['montantNet'] as num).toInt();
      _totalAmount = (calc['montant'] as num).toInt();
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _refreshCart() async {
    if (_currentSaleId == null) return;
    final items = await _apiService.fetchSaleItems(_currentSaleId!);
    _cartItems = items;
    // Si pas de calcul net effectué, total brut simple
    if (_netAPayer == 0) {
      _totalAmount = items.fold(0, (sum, item) => sum + item.intPRICE);
      _netAPayer = _totalAmount;
    }
    notifyListeners();
  }
}