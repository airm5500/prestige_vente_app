// lib/providers/auth_provider.dart
// 28/09/2025 21:06
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/officine.dart';
import 'package:prestige_vente_app/api/models/user.dart';

enum AuthStatus { Uninitialized, Authenticated, Unauthenticated, Loading }

class AuthProvider with ChangeNotifier {
  ApiService _apiService;

  AuthStatus _status = AuthStatus.Uninitialized;
  User? _user;
  Officine? _officine;
  String? _errorMessage;

  AuthStatus get status => _status;
  User? get user => _user;
  Officine? get officine => _officine;
  String? get errorMessage => _errorMessage;

  AuthProvider(this._apiService);

  // MODIFICATION : Ajout de cette méthode pour la mise à jour par ProxyProvider
  void updateApiService(ApiService newApiService) {
    _apiService = newApiService;
  }

  Future<bool> login(String login, String password) async {
    _status = AuthStatus.Loading;
    _errorMessage = null;
    notifyListeners();

    final user = await _apiService.login(login, password);

    if (user != null) {
      _user = user;
      _status = AuthStatus.Authenticated;
      notifyListeners();
      return true;
    } else {
      _status = AuthStatus.Unauthenticated;
      _errorMessage = 'Login ou mot de passe incorrect.';
      notifyListeners();
      return false;
    }
  }

  Future<void> loadOfficineInfo() async {
    _officine = await _apiService.fetchOfficineInfo();
    notifyListeners();
  }

  Future<void> logout() async {
    await _apiService.logout();
    _user = null;
    _officine = null;
    _status = AuthStatus.Unauthenticated;
    notifyListeners();
  }
}