// lib/providers/auth_provider.dart
// Mise à jour: Gestion du rôle Admin via str_LOGIN

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/officine.dart';
import 'package:prestige_vente_app/api/models/user.dart';
import 'package:prestige_vente_app/api/session_expiree.dart';
import 'package:prestige_vente_app/services/identifiants_securises.dart';
import 'package:prestige_vente_app/serveur/panne_serveur.dart';

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

  /// 4.3.2 : le dernier échec de [login] vient du serveur (indisponible, injoignable), pas des identifiants.
  /// 4.3.3 : panne du dernier échec de [login] (injoignable ≠ Prestige indisponible), ou null.
  PanneServeur? get dernierePanne => _apiService.dernierEchecConnexion?.panne;

  bool get dernierEchecServeur {
    final e = _apiService.dernierEchecConnexion;
    return e != null && !e.estRefus;
  }
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
    _officineDeLaConnexion = false;
    notifyListeners();

    try {
      final user = await _apiService.login(login, password);

      if (user != null) {
        _user = user;
        // AJOUT : On stocke le login qui a réussi
        _userLogin = login;
        _status = AuthStatus.Authenticated;
        // Nouvelle session : les requêtes parties avant sont rejouées, l'expiration est de nouveau surveillée.
        SessionExpiree.instance.connexionReussie();
        notifyListeners();
        return true;
      } else {
        _status = AuthStatus.Unauthenticated;
        // 4.3.2 : serveur indisponible (redéploiement : 404, 502/503, connexion refusée) ≠ mot de passe faux.
        final echec = _apiService.dernierEchecConnexion;
        _errorMessage = echec == null || echec.estRefus ? 'Login ou mot de passe incorrect.' : echec.message;
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
      final savedPassword = await IdentifiantsSecurises.instance.lire();

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
        SessionExpiree.instance.connexionReussie();
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

  /// Reconnexion SILENCIEUSE après expiration de la session sur le serveur (lib/api/session_expiree.dart) :
  /// seulement si « Rester connecté » est actif, que le mot de passe est dans le stockage sûr et qu'il s'agit
  /// du même compte. Jamais d'exception ; false si impossible ou refusée.
  Future<bool> reconnexionSilencieuse() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('stay_connected') != true) return false;
      final savedLogin = prefs.getString('saved_login');
      if (savedLogin == null || savedLogin.isEmpty) return false;
      if (_userLogin != null && _userLogin!.toLowerCase() != savedLogin.toLowerCase()) return false;
      final motDePasse = await IdentifiantsSecurises.instance.lire();
      if (motDePasse == null || motDePasse.isEmpty) return false;
      final user = await _apiService.login(savedLogin, motDePasse);
      if (user == null) return false;
      _user = user;
      _userLogin = savedLogin;
      _status = AuthStatus.Authenticated;
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Session expirée sans reconnexion possible : déconnexion LOCALE (pas d'appel au serveur, « Rester
  /// connecté » et files hors ligne conservés) avant le retour à l'écran de connexion.
  void sessionExpiree() {
    _user = null;
    _officine = null;
    _officineDeLaConnexion = false;
    _userLogin = null;
    _status = AuthStatus.Unauthenticated;
    notifyListeners();
  }

  Future<void> loadOfficineInfo() async {
    try {
      _officine = await _apiService.fetchOfficineInfo();
      notifyListeners();
    } catch (e) {
      print("Erreur chargement officine: $e");
    }
  }

  // ANO-09 (4.3.0) : l'officine lue par la connexion (GET /officine) sert à l'accueil qui s'ouvre JUSTE APRÈS cette
  // connexion, au lieu d'une 2e lecture identique. Un seul usage : tout autre accueil (connexion automatique,
  // retour, changement d'interface) relit l'officine comme avant.
  bool _officineDeLaConnexion = false;

  /// Chargements de la connexion : l'officine vient d'être lue (marque posée seulement si elle a été lue).
  void marquerOfficineDeLaConnexion() => _officineDeLaConnexion = _officine != null;

  /// Accueil : relit l'officine, sauf si la connexion qui l'ouvre vient de la lire (marque consommée).
  Future<void> loadOfficineInfoPourAccueil() async {
    final deja = _officineDeLaConnexion && _officine != null;
    _officineDeLaConnexion = false;
    if (deja) return;
    await loadOfficineInfo();
  }

  Future<void> logout() async {
    try {
      await _apiService.logout();
    } catch (e) {
      print("Erreur logout API: $e");
    }

    _user = null;
    _officine = null;
    _officineDeLaConnexion = false;
    // AJOUT : On nettoie le login
    _userLogin = null;
    _status = AuthStatus.Unauthenticated;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('stay_connected', false);

    notifyListeners();
  }
}