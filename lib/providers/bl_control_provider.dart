// lib/providers/bl_control_provider.dart

import 'package:flutter/material.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_horsligne.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_models.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/bon_livraison.dart';
import 'package:prestige_vente_app/api/models/bon_livraison_item.dart';
import 'package:prestige_vente_app/providers/quantity_sync.dart';

class BlControlProvider with ChangeNotifier, QuantitySync {

  ApiService _apiService;

  BlControlProvider(this._apiService);

  void updateApiService(ApiService newApiService) {
    _apiService = newApiService;
  }

  bool _isLoading = false;

  /// Message si le dernier chargement de la liste des BL a échoué (null si chargé, même vide).
  String? _loadError;
  String? get loadError => _loadError;

  /// Message si le chargement des lignes du BL ouvert a échoué.
  String? _itemsError;
  String? get itemsError => _itemsError;

  List<BonLivraison> _bonsLivraison = [];

  BonLivraison? _selectedBonLivraison;

  List<BonLivraisonItem> _items = [];

  final Map<String, Map<String, int>> _checkedQuantitiesPerBl = {};

  String _currentBlQuery = '';

  String? _currentBlDtStart;

  String? _currentBlDtEnd;

  bool get isLoading => _isLoading;

  List<BonLivraison> get bonsLivraison => _bonsLivraison;

  BonLivraison? get selectedBonLivraison => _selectedBonLivraison;

  List<BonLivraisonItem> get items => _items;

  Map<String, int> get checkedQuantities => _selectedBonLivraison != null
      ? _checkedQuantitiesPerBl[_selectedBonLivraison!.id] ?? {}
      : {};

  List<String> get emplacements {
    if (_items.isEmpty) return [];
    final allEmplacements = _items.map((item) => item.zoneGeoName).toSet();
    return allEmplacements.toList()..sort();
  }

  bool get isCurrentBlCompleted {
    if (_selectedBonLivraison == null) return false;

    if (_selectedBonLivraison!.statutTraitement == "TERMINE") return true;

    if (_items.isEmpty) return false;

    return checkedQuantities.length == _items.length;
  }

  BonLivraison _findBl(String blId) {
    return _bonsLivraison.firstWhere(
            (b) => b.id == blId,
        orElse: () => BonLivraison(
            id: '',
            ref: '',
            grossiste: '',
            date: '',
            nbreLignes: 0,
            montantTotal: 0,
            statutTraitement: 'A_FAIRE',
            strStatut: ''
        )
    );
  }

  bool isBlCompleted(String blId) {
    return _findBl(blId).statutTraitement == "TERMINE";
  }

  bool isBlInProgress(String blId) {
    return _findBl(blId).statutTraitement == "EN_COURS";
  }

  Future<void> fetchBonsLivraison({String? query, String? dtStart, String? dtEnd}) async {
    _isLoading = true;
    _currentBlQuery = query ?? _currentBlQuery;
    _currentBlDtStart = dtStart;
    _currentBlDtEnd = dtEnd;
    _loadError = null;

    notifyListeners();

    try {
      // Hors ligne : copie locale (H3) ; en ligne : inchangé.
      _bonsLivraison = HorsLigne.instance.offline
          ? await StockHorsLigne.instance.blsClotures(query: _currentBlQuery, dtStart: _currentBlDtStart, dtEnd: _currentBlDtEnd)
          : await _apiService.getBonsLivraison(
              query: _currentBlQuery,
              dtStart: _currentBlDtStart,
              dtEnd: _currentBlDtEnd,
            );
    } catch (e) {
      // La liste précédente reste affichée ; l'écran montre l'erreur avec « Réessayer ».
      _loadError = e is ApiLoadException || e is StockHorsLigneException ? '$e' : 'Impossible de charger les BL : $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> selectBonLivraison(BonLivraison bl) async {
    _isLoading = true;
    _selectedBonLivraison = bl;

    _checkedQuantitiesPerBl.putIfAbsent(bl.id, () => {});
    _itemsError = null;
    _items = [];
    notifyListeners();

    try {
      _items = HorsLigne.instance.offline ? await StockHorsLigne.instance.blItems(bl.id) : await _apiService.getBonLivraisonItems(bl.id);
    } catch (e) {
      _itemsError = e is ApiLoadException || e is StockHorsLigneException ? '$e' : 'Impossible de charger les lignes du BL : $e';
    }

    // --- LA CORRECTION EST ICI ---
    // On restaure la valeur si :
    // 1. Le serveur dit explicitement que c'est "checked"
    // OU
    // 2. Le serveur renvoie une quantité saisie (checkedQuantity) > 0.
    // (Cela couvre le cas où l'utilisateur a saisi une valeur mais le backend
    // n'a pas encore passé le flag global à true pour une raison x ou y).
    for (var item in _items) {
      if (item.isChecked) {
        _checkedQuantitiesPerBl[bl.id]![item.id] = item.checkedQuantity;
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  @override
  int? localQuantity(String detailId) {
    for (final m in _checkedQuantitiesPerBl.values) {
      if (m.containsKey(detailId)) return m[detailId];
    }
    return null;
  }

  /// Enregistre la quantité localement puis attend le serveur ; `false` si elle n'est pas enregistrée.
  Future<bool> updateCheckedQuantity(String detailId, int quantity) async {
    if (_selectedBonLivraison == null) return false;

    _checkedQuantitiesPerBl[_selectedBonLivraison!.id]![detailId] = quantity;
    notifyListeners();

    final blId = _selectedBonLivraison!.id;
    return sendQuantity(detailId, quantity, () => _post(detailId, quantity, blId));
  }

  /// En ligne : envoi au serveur (inchangé). Hors ligne : file des opérations (envoyée plus tard).
  Future<bool> _post(String detailId, int quantity, [String? blId]) async {
    if (!HorsLigne.instance.offline) return _apiService.postBonItemCheckedQuantity(detailId: detailId, quantity: quantity);
    await StockHorsLigne.instance.pointerBl(blId, detailId, quantity);
    return true;
  }

  Future<int> retryUnsyncedQuantities() => retryUnsynced((id, q) => _post(id, q));
}