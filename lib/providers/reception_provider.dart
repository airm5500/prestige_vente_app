// lib/providers/reception_provider.dart
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/reception_model.dart';

class ReceptionProvider with ChangeNotifier {
  ApiService _apiService;
  ReceptionProvider(this._apiService);

  void updateApiService(ApiService newApiService) {
    _apiService = newApiService;
  }

  bool _isLoading = false;
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
      print("Erreur fetchReceptionBons: $e");
    }

    _isLoading = false;
    notifyListeners();
  }

  void selectBon(ReceptionBon bon) {
    _selectedBon = bon;
    notifyListeners();
    // Plus besoin d'appeler _enrichSelectedBonLocations() ici !
  }

  void updateQuantity(String itemId, int quantity) {
    if (_selectedBon == null) return;

    if (!_checkedQuantitiesPerBon.containsKey(_selectedBon!.id)) {
      _checkedQuantitiesPerBon[_selectedBon!.id] = {};
    }
    _checkedQuantitiesPerBon[_selectedBon!.id]![itemId] = quantity;
    notifyListeners();

    _apiService.postBonItemCheckedQuantity(
      detailId: itemId,
      quantity: quantity,
    );
  }
}