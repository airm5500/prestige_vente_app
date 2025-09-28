// lib/providers/auth_provider.dart
// 28/09/2025 00:28
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/officine.dart';
import 'package:prestige_vente_app/api/models/user.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';

enum AuthStatus { Uninitialized, Authenticated, Unauthenticated, Loading }

class AuthProvider with ChangeNotifier {
  final SettingsProvider _settingsProvider;
  late ApiService _apiService;

  AuthStatus _status = AuthStatus.Uninitialized;
  User? _user;
  Officine? _officine;
  String? _errorMessage;

  // Getters pour accéder à l'état depuis l'UI
  AuthStatus get status => _status;
  User? get user => _user;
  Officine? get officine => _officine;
  String? get errorMessage => _errorMessage;

  AuthProvider(this._settingsProvider) {
    // On initialise le service API avec l'URL de base des paramètres
    _apiService = ApiService(baseUrl: _settingsProvider.baseUrl);
  }

  // Méthode de connexion
  Future<bool> login(String login, String password) async {
    _status = AuthStatus.Loading;
    _errorMessage = null;
    notifyListeners();

    final user = await _apiService.login(login, password);

    if (user != null) {
      _user = user;
      _status = AuthStatus.Authenticated;
      // Après une connexion réussie, on charge les infos de la pharmacie
      await _loadOfficineInfo();
      notifyListeners();
      return true;
    } else {
      _status = AuthStatus.Unauthenticated;
      _errorMessage = 'Login ou mot de passe incorrect.';
      notifyListeners();
      return false;
    }
  }

  // Charge les informations de la pharmacie
  Future<void> _loadOfficineInfo() async {
    _officine = await _apiService.fetchOfficineInfo();
    notifyListeners();
  }

  // Méthode de déconnexion
  Future<void> logout() async {
    await _apiService.logout();
    _user = null;
    _officine = null;
    _status = AuthStatus.Unauthenticated;
    notifyListeners();
  }
}