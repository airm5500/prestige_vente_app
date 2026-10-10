// lib/providers/ajustement_provider.dart
// Les échecs (réseau, serveur) sont exposés en messages clairs : une ligne n'est
// présentée comme enregistrée que si le serveur l'a confirmée.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/ajustement.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AjustementProvider with ChangeNotifier {
  final ApiService _apiService;

  String? _currentAjustementId;
  List<AjustementItem> _items = [];
  List<TypeAjustement> _typesAjustement = [];
  bool _isLoading = false; // envoi en cours (ajout de ligne ou clôture)
  String? _errorMessage;

  bool _typesLoading = false;
  String? _typesError;
  bool _itemsLoading = false;
  String? _itemsError;

  AjustementProvider(this._apiService);

  String? get currentAjustementId => _currentAjustementId;
  List<AjustementItem> get items => _items;
  List<TypeAjustement> get typesAjustement => _typesAjustement;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Chargement des motifs en cours / échec (≠ aucun motif).
  bool get typesLoading => _typesLoading;
  String? get typesError => _typesError;

  /// Rechargement des lignes en cours / échec (≠ aucune ligne).
  bool get itemsLoading => _itemsLoading;
  String? get itemsError => _itemsError;

  Future<void> loadTypesAjustement() async {
    _typesLoading = true;
    _typesError = null;
    notifyListeners();
    try {
      // En cas d'échec, on garde les motifs déjà chargés.
      _typesAjustement = await _apiService.getTypesAjustement();
    } on ApiLoadException catch (e) {
      _typesError = e.message;
    } catch (e) {
      _typesError = "Impossible de charger les motifs d'ajustement : $e";
    }
    _typesLoading = false;
    notifyListeners();
  }

  Future<List<ProductSearchResult>> searchProduct(String query) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hideRv = prefs.getBool('hide_rv_products') ?? true;

      final results = await _apiService.searchProducts(query);

      if (hideRv) {
        results.removeWhere((p) => p.strNAME.toUpperCase().startsWith("RV "));
      }
      return results;
    } catch (e) {
      return [];
    }
  }

  /// Recherche pour un scan : un échec réseau lève [ApiLoadException] (≠ produit introuvable).
  Future<List<ProductSearchResult>> searchProductForScan(String query) async {
    bool hideRv = true;
    try {
      hideRv = (await SharedPreferences.getInstance()).getBool('hide_rv_products') ?? true;
    } catch (_) {}
    final results = await _apiService.searchProductsOrFail(query);
    if (hideRv) {
      results.removeWhere((p) => p.strNAME.toUpperCase().startsWith("RV "));
    }
    return results;
  }

  Future<bool> addProduct({
    required ProductSearchResult product,
    required int quantity,
    required int typeAjustementId,
    String description = "",
  }) async {
    // Pas de double envoi : un seul ajout à la fois (sinon deux créations possibles).
    if (_isLoading) {
      _errorMessage = "Un envoi est déjà en cours. Patientez.";
      notifyListeners();
      return false;
    }
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // 1. DÉTERMINATION DE L'URL ET DU REFPARENT
      String url;
      String? refParent;

      if (_currentAjustementId == null) {
        // C'est le PREMIER produit -> CRÉATION
        url = '/ajustement/creeation';
        refParent = null;
      } else {
        // C'est un produit SUIVANT -> AJOUT ITEM
        url = '/ajustement/add/item';
        refParent = _currentAjustementId;
      }

      // 2. PRÉPARATION DES DONNÉES
      final Map<String, dynamic> payload = {
        "description": description,
        "refParent": refParent,
        "refTwo": product.lgFAMILLEID, // ID du produit
        "value": quantity,             // Quantité
        "valueFour": typeAjustementId, // Motif
        "valueTwo": product.intNUMBERAVAILABLE, // Stock avant
      };

      // 3. ENVOI DE LA REQUÊTE
      final response = await _apiService.request(
        method: 'POST',
        url: url,
        data: payload,
      );

      if (response is Map && response['success'] == true) {

        // Si c'était une création (premier produit), on récupère l'ID créé
        final data = response['data'];
        if (_currentAjustementId == null && data is Map && data['lgAJUSTEMENTID'] is String) {
          _currentAjustementId = data['lgAJUSTEMENTID'];
        }

        // Délai de sécurité pour l'écriture BDD
        await Future.delayed(const Duration(milliseconds: 300));

        // Rechargement de la liste
        await _refreshItems();

        _isLoading = false;
        notifyListeners();
        return true;
      } else if (response == null) {
        _errorMessage = "Ligne NON enregistrée : serveur injoignable ou erreur du serveur. "
            "Vérifiez le réseau, actualisez la liste puis réessayez.";
      } else {
        final msg = response is Map ? response['msg'] : null;
        _errorMessage = "Ligne refusée par le serveur : ${msg ?? 'raison inconnue'}";
      }
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = "Ligne NON enregistrée (erreur technique) : $e";
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Recharge les lignes de l'ajustement en cours (bouton « Réessayer » / « Actualiser »).
  Future<void> refreshItems() => _refreshItems();

  Future<void> _refreshItems() async {
    if (_currentAjustementId == null) return;
    _itemsLoading = true;
    _itemsError = null;
    notifyListeners();
    try {
      _items = await _apiService.getAjustementItems(_currentAjustementId!);
    } on ApiLoadException catch (e) {
      _itemsError = e.message;
    } catch (e) {
      _itemsError = "Impossible de charger les lignes d'ajustement : $e";
    }
    _itemsLoading = false;
    notifyListeners();
  }

  Future<bool> validateAjustement() async {
    if (_currentAjustementId == null) return false;
    if (_isLoading) return false; // pas de double clôture
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _apiService.request(
        method: 'PUT',
        url: '/ajustement/$_currentAjustementId',
        data: {"description": ""},
      );

      _isLoading = false;

      if (response is Map && response['success'] == true) {
        _currentAjustementId = null;
        _items = [];
        _itemsError = null;
        notifyListeners();
        return true;
      } else if (response == null) {
        _errorMessage = "Clôture NON confirmée : serveur injoignable ou erreur du serveur. "
            "L'ajustement reste en cours ; vérifiez le réseau puis réessayez.";
      } else {
        final msg = response is Map ? response['msg'] : null;
        _errorMessage = "Erreur validation: ${msg ?? 'Inconnue'}";
      }
      notifyListeners();
      return false;
    } catch (e) {
      _isLoading = false;
      _errorMessage = "Erreur technique: $e";
      notifyListeners();
      return false;
    }
  }
}
