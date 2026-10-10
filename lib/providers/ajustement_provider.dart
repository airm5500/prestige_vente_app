// lib/providers/ajustement_provider.dart
// Les échecs (réseau, serveur) sont exposés en messages clairs : une ligne n'est
// présentée comme enregistrée que si le serveur l'a confirmée.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/ajustement.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/services/product_finder.dart';
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

  Future<bool> _hideRv() async {
    try {
      return (await SharedPreferences.getInstance()).getBool('hide_rv_products') ?? true;
    } catch (_) {
      return true;
    }
  }

  static bool _isRv(ProductSearchResult p) => p.strNAME.toUpperCase().startsWith("RV ");

  /// Nouvelle recherche produit (fenêtre de recherche) : code → produit exact (EAN-13 → CIP7…),
  /// texte → liste par pages (« 50 sur 120 »). Les « RV » sont masqués selon le réglage.
  Future<PagedProductSearch> newProductSearch() async {
    final hideRv = await _hideRv();
    return PagedProductSearch(() => _apiService, visible: hideRv ? (p) => !_isRv(p) : null);
  }

  /// Première page de résultats pour [query] (liste vide en cas d'échec).
  Future<List<ProductSearchResult>> searchProduct(String query) async {
    try {
      final search = await newProductSearch();
      await search.run(query);
      return search.items;
    } catch (e) {
      return [];
    }
  }

  /// Message du dernier scan sans résultat : « Code X introuvable (essayé aussi Y) ».
  String? _scanNotFound;
  String? get scanNotFound => _scanNotFound;

  /// Recherche pour un scan (produit exact, avec les variantes EAN-13 → CIP7…) :
  /// un échec réseau lève [ApiLoadException] (≠ produit introuvable).
  Future<List<ProductSearchResult>> searchProductForScan(String query) async {
    final search = await newProductSearch();
    await search.run(query, asCode: true);
    if (search.error != null) throw ApiLoadException(search.error!);
    _scanNotFound = search.notFound;
    return search.items;
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
