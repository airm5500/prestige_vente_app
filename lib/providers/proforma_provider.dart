import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:prestige_vente_app/api/api_service.dart';
// C'est ici que sont vos modèles ClientModel, ClientCarnetModel, TypeDevis, RemiseModel...
import 'package:prestige_vente_app/api/models/proforma_models.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
// Il faut importer ceci pour que ProductSearchResult soit reconnu
//import 'package:prestige_vente_app/api/models/product_search_result.dart';

class ProformaProvider with ChangeNotifier {
  final ApiService _apiService;

  String? _currentSaleId;
  String? get currentSaleId => _currentSaleId;
  // Alias pour l'écran
  String? get currentProformaId => _currentSaleId;

  String? _currentSaleRef;
  String? get currentSaleRef => _currentSaleRef;

  TypeDevis? _selectedTypeDevis;
  TypeDevis? get selectedTypeDevis => _selectedTypeDevis;

  ClientModel? _selectedClient;
  ClientModel? get selectedClient => _selectedClient;

  RemiseModel? _selectedRemise;
  RemiseModel? get selectedRemise => _selectedRemise;

  List<SaleLine> _cartItems = [];
  List<SaleLine> get cartItems => _cartItems;

  List<ProductSearchResult> _searchResults = [];
  List<ProductSearchResult> get searchResults => _searchResults;

  List<ClientModel> _clientSearchResults = [];
  List<ClientModel> get clientSearchResults => _clientSearchResults;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String _errorMessage = '';
  String get errorMessage => _errorMessage;

  int _totalAmount = 0;
  int get totalAmount => _totalAmount;
  int _montantRemise = 0;
  int get montantRemise => _montantRemise;
  int _netAPayer = 0;
  int get netAPayer => _netAPayer;

  bool _isQuickScanMode = false;
  bool get isQuickScanMode => _isQuickScanMode;

  ProformaProvider(this._apiService) {
    _loadScanSettings();
  }

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

  // --- RECHERCHE DE PRODUITS ---
  Future<void> searchProducts(String query) async {
    if (query.length < 3) {
      _searchResults = [];
      notifyListeners();
      return;
    }
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      _searchResults = await _apiService.searchProducts(query);
    } catch (e) {
      _errorMessage = "Erreur de recherche produits: $e";
      _searchResults = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- RECHERCHE DE CLIENTS ---
  Future<void> searchClients(String query) async {
    if (query.isEmpty) {
      _clientSearchResults = [];
      notifyListeners();
      return;
    }

    if (_selectedTypeDevis == null) {
      _errorMessage = "Sélectionnez d'abord un Type de Devis.";
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      // ID "3" = Carnet
      if (_selectedTypeDevis!.lgTYPEVENTEID == "3") {
        final carnetClients = await _apiService.searchClientsCarnet(query);
        _clientSearchResults = carnetClients;
        if (carnetClients.isEmpty) _errorMessage = "Aucun client Carnet trouvé.";
      } else {
        // ID "1" = Comptant
        final comptantClients = await _apiService.searchClientsComptant(query);
        _clientSearchResults = comptantClients;
        if (comptantClients.isEmpty) _errorMessage = "Aucun client trouvé.";
      }
    } catch (e) {
      _errorMessage = "Erreur recherche client: $e";
      _clientSearchResults = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- SÉLECTIONS ---
  void setTypeDevis(TypeDevis? type) {
    _selectedTypeDevis = type;
    _selectedClient = null;
    _clientSearchResults = [];
    notifyListeners();
  }

  void setClient(ClientModel? client) {
    _selectedClient = client;
    _clientSearchResults = [];
    notifyListeners();
  }

  // --- ACTIONS PANIER ---
  Future<bool> addProduct(ProductSearchResult product, int quantity) async {
    if (_selectedTypeDevis == null || _selectedClient == null) {
      _errorMessage = "Sélectionnez d'abord un type de vente et un client.";
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      List<Map<String, dynamic>> tpList = [];

      // Gestion spécifique CARNET (ID "3")
      if (_selectedTypeDevis!.lgTYPEVENTEID == "3") {
        if (_selectedClient is ClientCarnetModel) {
          final clientCarnet = _selectedClient as ClientCarnetModel;

          if (clientCarnet.tiersPayants.isNotEmpty) {
            tpList = clientCarnet.tiersPayants.map((tp) => {
              "lgTIERSPAYANTID": tp.lgTIERSPAYANTID,
              "intPOURCENTAGE": tp.intPOURCENTAGE,
              "intPRIORITY": tp.intPRIORITY ?? 1,
              "lgCOMPTETIERSIAYANTID": tp.lgCOMPTETIERSIAYANTID ?? tp.lgTIERSPAYANTID,
            }).toList();
          } else {
            _errorMessage = "Erreur : Ce client Carnet n'a pas de Tiers-Payant configuré.";
            _isLoading = false;
            notifyListeners();
            return false;
          }
        } else {
          _errorMessage = "Erreur : Le client sélectionné n'est pas valide pour le Carnet.";
          _isLoading = false;
          notifyListeners();
          return false;
        }
      }

      bool success = false;

      // CAS 1 : Création de la proforma
      if (_currentSaleId == null) {
        final result = await _apiService.addFirstDevisItem(
          clientId: _selectedClient!.lgCLIENTID,
          typeVenteId: _selectedTypeDevis!.lgTYPEVENTEID,
          produitId: product.lgFAMILLEID,
          itemPu: product.intPRICE,
          qte: quantity,
          tiersPayants: tpList,
        );

        if (result != null && result['success'] == true) {
          _currentSaleId = result['data']['lgPREENREGISTREMENTID'];
          _currentSaleRef = result['data']['strREF'];
          success = true;
        } else {
          _errorMessage = "Erreur création proforma (API)";
        }
      }
      // CAS 2 : Ajout produit suivant
      else {
        success = await _apiService.addNextDevisItem(
          venteId: _currentSaleId!,
          clientId: _selectedClient!.lgCLIENTID,
          typeVenteId: _selectedTypeDevis!.lgTYPEVENTEID,
          produitId: product.lgFAMILLEID,
          itemPu: product.intPRICE,
          qte: quantity,
          tiersPayants: tpList,
        );
      }

      if (success) {
        await _refreshCart();
        _searchResults = [];
        _errorMessage = '';
      } else if (_errorMessage.isEmpty) {
        _errorMessage = "Impossible d'ajouter le produit.";
      }

      return success;

    } catch (e) {
      _errorMessage = "Erreur technique : $e";
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateItem(SaleLine item, int newQty, int newPrice) async {
    _isLoading = true;
    notifyListeners();
    final success = await _apiService.updateDepotItem(
      itemId: item.lgPREENREGISTREMENTDETAILID,
      produitId: item.lgFAMILLEID,
      itemPu: newPrice,
      qte: newQty,
    );

    if (success) {
      await _refreshCart();
      if (_selectedRemise != null) await applyRemise(_selectedRemise!);
    } else {
      _errorMessage = "Échec modification ligne.";
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
      if (_selectedRemise != null && _currentSaleId != null) {
        await applyRemise(_selectedRemise!);
      }
    } else {
      _errorMessage = "Échec suppression ligne.";
    }

    _isLoading = false;
    notifyListeners();
    return success;
  }

  // --- SUPPRESSION GLOBALE ---
  Future<void> deleteCurrentProforma() async {
    if (_currentSaleId != null) {
      try {
        await _apiService.deleteSale(_currentSaleId!);
        resetProforma();
      } catch (e) {
        print("Erreur suppression proforma: $e");
      }
    }
  }

  // --- REMISES ---
  Future<void> applyRemise(RemiseModel remise) async {
    if (_currentSaleId == null) return;
    _selectedRemise = remise;
    _isLoading = true;
    notifyListeners();

    try {
      await _apiService.applyRemise(venteId: _currentSaleId!, remiseId: remise.lgREMISEID);
      final calc = await _apiService.calculateNetProforma(venteId: _currentSaleId!, remiseId: remise.lgREMISEID);

      if (calc != null) {
        _montantRemise = (calc['remise'] as num).toInt();
        _netAPayer = (calc['montantNet'] as num).toInt();
        _totalAmount = (calc['montant'] as num).toInt();
      }
      await _refreshCart();
    } catch (e) {
      _errorMessage = "Erreur application remise: $e";
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _refreshCart() async {
    if (_currentSaleId == null) return;
    try {
      final items = await _apiService.fetchSaleItems(_currentSaleId!);
      _cartItems = items;

      if (_selectedRemise == null) {
        _totalAmount = items.fold(0, (sum, item) => sum + (item.intPRICEUNITAIR * item.intQUANTITY));
        _netAPayer = _totalAmount;
        _montantRemise = 0;
      }
    } catch (e) {
      _errorMessage = "Erreur rafraîchissement panier : $e";
    }
    notifyListeners();
  }

  void resetSale() {
    _currentSaleId = null;
    _currentSaleRef = null;
    _selectedTypeDevis = null;
    _selectedClient = null;
    _selectedRemise = null;
    _cartItems = [];
    _searchResults = [];
    _clientSearchResults = [];
    _totalAmount = 0;
    _montantRemise = 0;
    _netAPayer = 0;
    _errorMessage = '';
    notifyListeners();
  }

  void resetProforma() => resetSale();

  Future<void> loadExistingProforma(ProformaListItem item) async {
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();
    try {
      _currentSaleId = item.lgPREENREGISTREMENTID;
      _currentSaleRef = item.strREF;

      final clientDetails = await _apiService.getClientForSale(item.clientId, _currentSaleId!);

      if (clientDetails != null) {
        _selectedClient = clientDetails;
      } else {
        _selectedClient = ClientComptantModel(
            lgCLIENTID: item.clientId,
            strFIRSTNAME: item.strClientFullName.split(' ').first,
            strLASTNAME: item.strClientFullName.split(' ').skip(1).join(' '),
            strADRESSE: null
        );
      }

      String typeVenteId = (item.strTYPEVENTE.toUpperCase().contains("CARNET")) ? "3" : "1";

      _selectedTypeDevis = TypeDevis(
        lgTYPEVENTEID: typeVenteId,
        strNAME: item.strTYPEVENTE,
        strDESCRIPTION: "",
      );

      await _refreshCart();
    } catch (e) {
      _errorMessage = "Erreur chargement proforma : $e";
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearSearchResults() {
    _searchResults = [];
    _clientSearchResults = [];
    notifyListeners();
  }
}