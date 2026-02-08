// lib/providers/ajustement_provider.dart
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
  bool _isLoading = false;
  String? _errorMessage;

  AjustementProvider(this._apiService);

  String? get currentAjustementId => _currentAjustementId;
  List<AjustementItem> get items => _items;
  List<TypeAjustement> get typesAjustement => _typesAjustement;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadTypesAjustement() async {
    try {
      final response = await _apiService.request(
        method: 'GET',
        url: '/common/type-ajustements',
        queryParameters: {'limit': 9999},
      );
      if (response != null && response['data'] != null) {
        _typesAjustement = (response['data'] as List)
            .map((e) => TypeAjustement.fromJson(e))
            .toList();
        notifyListeners();
      }
    } catch (e) {
      print("Erreur loadTypesAjustement: $e");
    }
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

  Future<bool> addProduct({
    required ProductSearchResult product,
    required int quantity,
    required int typeAjustementId,
    String description = "",
  }) async {
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

      if (response != null && response['success'] == true) {

        // Si c'était une création (premier produit), on récupère l'ID créé
        if (_currentAjustementId == null && response['data'] != null) {
          _currentAjustementId = response['data']['lgAJUSTEMENTID'];
        }

        // Délai de sécurité pour l'écriture BDD
        await Future.delayed(const Duration(milliseconds: 300));

        // Rechargement de la liste
        await _refreshItems();

        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage = "Erreur API : ${response?['msg'] ?? 'Inconnue'}";
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = "Erreur technique: $e";
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> _refreshItems() async {
    if (_currentAjustementId == null) return;
    try {
      final response = await _apiService.request(
        method: 'GET',
        url: '/ajustement/items',
        queryParameters: {
          'ajustementId': _currentAjustementId,
          'limit': 100,
          'start': 0,
          'page': 1,
          // CORRECTION ANTI-CACHE : On ajoute un timestamp pour forcer une réponse fraîche
          '_dc': DateTime.now().millisecondsSinceEpoch.toString(),
        },
      );

      if (response != null && response['data'] != null) {
        _items = (response['data'] as List)
            .map((e) => AjustementItem.fromJson(e))
            .toList();

        // Optionnel : Trier pour voir le dernier ajouté en haut
        // _items.sort((a, b) => b.heure.compareTo(a.heure));

        notifyListeners();
      }
    } catch (e) {
      print("Erreur refreshItems: $e");
    }
  }

  Future<bool> validateAjustement() async {
    if (_currentAjustementId == null) return false;
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _apiService.request(
        method: 'PUT',
        url: '/ajustement/$_currentAjustementId',
        data: {"description": ""},
      );

      _isLoading = false;

      if (response != null && response['success'] == true) {
        _currentAjustementId = null;
        _items = [];
        notifyListeners();
        return true;
      } else {
        _errorMessage = "Erreur validation: ${response?['msg'] ?? 'Inconnue'}";
        notifyListeners();
        return false;
      }
    } catch (e) {
      _isLoading = false;
      _errorMessage = "Erreur technique: $e";
      notifyListeners();
      return false;
    }
  }
}