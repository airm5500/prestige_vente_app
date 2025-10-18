// lib/providers/bl_control_provider.dart
// 18/10/2025 16:41
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/bon_livraison.dart';
import 'package:prestige_vente_app/api/models/bon_livraison_item.dart';

class BlControlProvider with ChangeNotifier {
  ApiService _apiService;
  BlControlProvider(this._apiService);
  void updateApiService(ApiService newApiService) { _apiService = newApiService; }

  bool _isLoading = false;
  List<BonLivraison> _bonsLivraison = [];
  BonLivraison? _selectedBonLivraison;
  List<BonLivraisonItem> _items = [];

  Map<String, Map<String, int>> _checkedQuantitiesPerBl = {};

  String _currentBlQuery = '';
  String? _currentBlDtStart;
  String? _currentBlDtEnd;

  bool get isLoading => _isLoading;
  List<BonLivraison> get bonsLivraison => _bonsLivraison;
  BonLivraison? get selectedBonLivraison => _selectedBonLivraison;
  List<BonLivraisonItem> get items => _items;
  Map<String, int> get checkedQuantities => _selectedBonLivraison != null ? _checkedQuantitiesPerBl[_selectedBonLivraison!.id] ?? {} : {};
  bool get isCurrentBlCompleted { if (_selectedBonLivraison == null) return false; if (_selectedBonLivraison!.statutTraitement == "TERMINE") return true; if (_items.isEmpty) return false; return checkedQuantities.length == _items.length; }

  BonLivraison _findBl(String blId) {
    return _bonsLivraison.firstWhere((b) => b.id == blId,
        orElse: () => BonLivraison(id: '', ref: '', grossiste: '', date: '', nbreLignes: 0, montantTotal: 0, statutTraitement: 'A_FAIRE', strStatut: ''));
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

    notifyListeners();

    // MODIFICATION : On récupère directement la liste filtrée par le serveur.
    // Le filtre ".where(...)" a été supprimé.
    _bonsLivraison = await _apiService.getBonsLivraison(
      query: _currentBlQuery,
      dtStart: _currentBlDtStart,
      dtEnd: _currentBlDtEnd,
    );

    _isLoading = false;
    notifyListeners();
  }

  Future<void> selectBonLivraison(BonLivraison bl) async {
    _isLoading = true;
    _selectedBonLivraison = bl;
    _checkedQuantitiesPerBl.putIfAbsent(bl.id, () => {});
    notifyListeners();

    _items = await _apiService.getBonLivraisonItems(bl.id);

    for (var item in _items) {
      if (item.isChecked) {
        _checkedQuantitiesPerBl[bl.id]![item.id] = item.checkedQuantity;
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  void updateCheckedQuantity(String detailId, int quantity) {
    if (_selectedBonLivraison == null) return;
    _checkedQuantitiesPerBl[_selectedBonLivraison!.id]![detailId] = quantity;
    notifyListeners();
    _apiService.postBonItemCheckedQuantity(detailId: detailId, quantity: quantity);
  }
}