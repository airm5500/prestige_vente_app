// lib/providers/reception_provider.dart
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/reception_model.dart';
import 'package:prestige_vente_app/providers/quantity_sync.dart';

class ReceptionProvider with ChangeNotifier, QuantitySync {
  ApiService _apiService;
  ReceptionProvider(this._apiService);

  void updateApiService(ApiService newApiService) {
    _apiService = newApiService;
  }

  bool _isLoading = false;

  /// Message si le dernier chargement de la liste a échoué (null si chargé, même vide).
  String? _loadError;
  String? get loadError => _loadError;
  List<ReceptionBon> _receptionBons = [];
  ReceptionBon? _selectedBon;

  final Map<String, Map<String, int>> _checkedQuantitiesPerBon = {};

  bool get isLoading => _isLoading;
  List<ReceptionBon> get receptionBons => _receptionBons;
  ReceptionBon? get selectedBon => _selectedBon;

  List<ReceptionBon> get bonsAFaire => _receptionBons.where((b) => b.statutTraitement != "TERMINE").toList();
  List<ReceptionBon> get bonsTermines => _receptionBons.where((b) => b.statutTraitement == "TERMINE").toList();

  Map<String, int> get currentCheckedQuantities {
    if (_selectedBon == null) return {};
    return _checkedQuantitiesPerBon[_selectedBon!.id] ?? {};
  }

  Future<void> fetchReceptionBons({String? dtStart, String? dtEnd, String query = ''}) async {
    _isLoading = true;
    _loadError = null;
    notifyListeners();

    try {
      _receptionBons = await _apiService.getReceptionBons(
        query: query,
        dtStart: dtStart,
        dtEnd: dtEnd,
      );

      for (var bon in _receptionBons) {
        _checkedQuantitiesPerBon.putIfAbsent(bon.id, () => {});
        for (var item in bon.details) {
          _checkedQuantitiesPerBon[bon.id]![item.id] = item.quantiteControle;
        }
      }
    } catch (e) {
      // La liste précédente reste affichée ; l'écran montre l'erreur avec « Réessayer ».
      _loadError = e is ApiLoadException ? e.message : 'Impossible de charger les bons : $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  void selectBon(ReceptionBon bon) {
    _selectedBon = bon;
    notifyListeners();
    // Plus besoin d'appeler _enrichSelectedBonLocations() ici !
  }

  @override
  int? localQuantity(String detailId) {
    for (final m in _checkedQuantitiesPerBon.values) {
      if (m.containsKey(detailId)) return m[detailId];
    }
    return null;
  }

  /// Enregistre la quantité localement puis attend le serveur ; `false` si elle n'est pas enregistrée.
  Future<bool> updateQuantity(String itemId, int quantity) async {
    if (_selectedBon == null) return false;

    if (!_checkedQuantitiesPerBon.containsKey(_selectedBon!.id)) {
      _checkedQuantitiesPerBon[_selectedBon!.id] = {};
    }
    _checkedQuantitiesPerBon[_selectedBon!.id]![itemId] = quantity;
    notifyListeners();

    return sendQuantity(itemId, quantity, () => _apiService.postBonItemCheckedQuantity(detailId: itemId, quantity: quantity));
  }

  Future<int> retryUnsyncedQuantities() =>
      retryUnsynced((id, q) => _apiService.postBonItemCheckedQuantity(detailId: id, quantity: q));
}