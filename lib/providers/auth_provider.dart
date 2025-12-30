// lib/providers/auth_provider.dart
// 30/12/2025 02:30 (Ajout tryAutoLogin pour correction erreur)
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart'; // AJOUT IMPORTANT
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

  // AJOUT : Méthode manquante pour l'auto-login
  Future<bool> tryAutoLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Vérifier si l'option "Rester connecté" est active
      if (!prefs.containsKey('stay_connected') ||
          prefs.getBool('stay_connected') == false) {
        _status = AuthStatus.Unauthenticated;
        notifyListeners();
        return false;
      }

      // 2. Récupérer les identifiants sauvegardés
      final savedLogin = prefs.getString('saved_login');
      final savedPassword = prefs.getString('saved_password');

      if (savedLogin == null || savedPassword == null) {
        _status = AuthStatus.Unauthenticated;
        notifyListeners();
        return false;
      }

      // 3. Tenter la connexion avec ces identifiants
      // Note : On ne passe pas par la méthode login() publique pour éviter
      // de déclencher le AuthStatus.Loading qui ferait clignoter l'écran
      final user = await _apiService.login(savedLogin, savedPassword);

      if (user != null) {
        _user = user;
        _status = AuthStatus.Authenticated;
        notifyListeners();
        return true;
      } else {
        _status = AuthStatus.Unauthenticated;
        notifyListeners();
        return false;
      }
    } catch (e) {
      print("Erreur AutoLogin: $e");
      _status = AuthStatus.Unauthenticated;
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

    // Optionnel : Si on se déconnecte manuellement, on peut vouloir
    // désactiver l'auto-login pour la prochaine fois
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('stay_connected', false);

    notifyListeners();
  }
}