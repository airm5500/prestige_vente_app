// lib/providers/auth_provider.dart
// Mise à jour: Gestion du rôle Admin via str_LOGIN

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  // AJOUT : Variable pour stocker le login (ex: "admin")
  String? _userLogin;

  AuthStatus get status => _status;
  User? get user => _user;
  Officine? get officine => _officine;
  String? get errorMessage => _errorMessage;

  // AJOUT : Getter pour vérifier si c'est l'administrateur
  // On compare en minuscule pour éviter les problèmes de casse (Admin, admin, ADMIN)
  bool get isAdmin => _userLogin?.toLowerCase() == "admin";

  AuthProvider(this._apiService);

  void updateApiService(ApiService newApiService) {
    _apiService = newApiService;
  }

  Future<bool> login(String login, String password) async {
    _status = AuthStatus.Loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _apiService.login(login, password);

      if (user != null) {
        _user = user;
        // AJOUT : On stocke le login qui a réussi
        _userLogin = login;
        _status = AuthStatus.Authenticated;
        notifyListeners();
        return true;
      } else {
        _status = AuthStatus.Unauthenticated;
        _errorMessage = 'Login ou mot de passe incorrect.';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _status = AuthStatus.Unauthenticated;
      _errorMessage = 'Erreur de connexion: $e';
      notifyListeners();
      return false;
    }
  }

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
      final user = await _apiService.login(savedLogin, savedPassword);

      if (user != null) {
        _user = user;
        // AJOUT : On restaure aussi le login
        _userLogin = savedLogin;
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
    try {
      _officine = await _apiService.fetchOfficineInfo();
      notifyListeners();
    } catch (e) {
      print("Erreur chargement officine: $e");
    }
  }

  Future<void> logout() async {
    try {
      await _apiService.logout();
    } catch (e) {
      print("Erreur logout API: $e");
    }

    _user = null;
    _officine = null;
    // AJOUT : On nettoie le login
    _userLogin = null;
    _status = AuthStatus.Unauthenticated;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('stay_connected', false);

    notifyListeners();
  }
}