// lib/providers/caisse_provider.dart
// 09/11/2025 01:30
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/caisse_models.dart';

class CaisseProvider with ChangeNotifier {
  ApiService _apiService;
  CaisseProvider(this._apiService);
  void updateApiService(ApiService newApiService) { _apiService = newApiService; }

  bool _isLoading = false;
  String? _errorMessage;
  OuvertureData? _ouvertureData;
  ClotureData? _clotureData;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  OuvertureData? get ouvertureData => _ouvertureData;
  ClotureData? get clotureData => _clotureData;

  // L'état principal pour savoir si la caisse est ouverte
  bool get isCaisseOuverte => _ouvertureData?.inUse ?? false;

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String? message) {
    _errorMessage = message;
    notifyListeners();
  }

  // Charge l'état actuel de la caisse
  Future<void> loadData() async {
    _setLoading(true);
    _setError(null);
    _clotureData = null; // Réinitialise les données de clôture

    _ouvertureData = await _apiService.getOuvertureData();

    // Si la caisse est déjà ouverte (inUse == true),
    // on charge aussi les données de clôture (pour voir le solde)
    if (_ouvertureData != null && _ouvertureData!.inUse) {
      _clotureData = await _apiService.getClotureData();
    }

    _setLoading(false);
  }

  // Ouvre la caisse (avec 0)
  Future<bool> ouvrirCaisse() async {
    _setLoading(true);
    _setError(null);

    final success = await _apiService.ouvrirCaisse();

    if (success) {
      await loadData(); // Recharge les données pour mettre à jour l'état
      return true;
    } else {
      _setError("Échec de l'ouverture de la caisse.");
      _setLoading(false);
      return false;
    }
  }

  // Recharge les données avant de montrer le dialogue de billetage
  Future<bool> prepareCloture() async {
    _setLoading(true);
    _setError(null);
    _clotureData = await _apiService.getClotureData();
    _setLoading(false);

    if (_clotureData == null) {
      _setError("Impossible de récupérer les données de clôture.");
      return false;
    }
    return true;
  }

  // Envoie le billetage et clôture
  Future<bool> cloturerCaisse(Map<String, int> billetage) async {
    if (_clotureData == null) {
      _setError("Données de clôture manquantes.");
      return false;
    }

    _setLoading(true);
    _setError(null);

    final success = await _apiService.cloturerCaisse(
      resumeCaisseId: _clotureData!.resumeCaisseId,
      billetage: billetage,
    );

    if (success) {
      await loadData(); // Recharge les données (la caisse sera fermée)
      return true;
    } else {
      _setError("Échec de la clôture de la caisse.");
      _setLoading(false);
      return false;
    }
  }
}