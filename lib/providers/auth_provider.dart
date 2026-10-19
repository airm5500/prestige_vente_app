// lib/providers/auth_provider.dart
// Mise à jour: Gestion du rôle Admin via str_LOGIN

import 'package:dio/dio.dart' show Options;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/api/utilisateur_session.dart';
import 'package:prestige_vente_app/connexion/changement_utilisateur.dart';
import 'package:prestige_vente_app/droits/droits_vente.dart';
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
        await _ouvrirSession(user);
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
        await _ouvrirSession(user);
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
      await _ouvrirSession(user);
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
    // 4.5.1 : droits oubliés ; le panier est effacé seulement si un AUTRE compte se connecte ensuite.
    UtilisateurSession.id = null;
    DroitsVente.instance.oublier();
    _user = null;
    _officine = null;
    _officineDeLaConnexion = false;
    _userLogin = null;
    _status = AuthStatus.Unauthenticated;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 4.5.1 — Droits de vente et compte de la session (demande du serveur du 19/10/2026)
  // ---------------------------------------------------------------------------

  /// Dernier compte connecté sur cet appareil (mémoire) : un AUTRE compte efface le panier du précédent.
  String? _dernierUtilisateur;

  /// Délai maximal de la lecture des droits à la connexion (la connexion n'attend pas davantage).
  static Duration delaiDroits = const Duration(seconds: 8);

  /// Lecture des droits de vente (GET v1/user/droits) ; remplaçable dans les tests à faux ApiService.
  static Future<void> Function(ApiService api, String utilisateur) lireDroitsVente =
      (api, utilisateur) => DroitsVente.instance.actualiser(api.dio, utilisateur: utilisateur);

  /// Connexion acceptée (mot de passe, connexion automatique, reconnexion silencieuse, borne) : en-tête
  /// X-Prestige-Utilisateur, panier du compte précédent effacé si le compte change, droits lus.
  /// Augmente à chaque session ouverte (une déconnexion lente n'efface jamais la session suivante).
  int _generationSession = 0;

  Future<void> _ouvrirSession(User u) async {
    _generationSession++;
    if (_dernierUtilisateur != null && _dernierUtilisateur != u.userId) {
      UtilisateurSession.id = null;
      await EtatLocalVente.effacer();
    }
    _dernierUtilisateur = u.userId;
    UtilisateurSession.id = u.userId.isEmpty ? null : u.userId;
    try {
      await lireDroitsVente(_apiService, u.userId).timeout(delaiDroits);
    } catch (_) {}
  }

  /// Retour de l'application au premier plan : droits relus (jamais d'exception).
  Future<void> relireDroits() async {
    final u = _user;
    if (u == null || _status != AuthStatus.Authenticated) return;
    try {
      await lireDroitsVente(_apiService, u.userId);
    } catch (_) {}
  }

  /// 409 `sessionChangee` : la session du serveur est maintenant celle d'un autre compte. Compte relu
  /// (GET v1/user/account) et droits relus ; si le compte a changé, le panier du précédent est effacé (files hors
  /// ligne gardées). Compte illisible : déconnexion locale (écran de connexion).
  Future<void> relireSessionChangee() async {
    User? lu;
    // L'en-tête de l'ancien compte serait refusé (409) : la lecture du compte de la session part sans lui.
    UtilisateurSession.id = null;
    try {
      final r = await _apiService.dio.get<dynamic>('/user/account', options: Options(validateStatus: (_) => true));
      final info = r.data is Map ? (r.data as Map)['accountInfo'] : null;
      // AccountInfoDTO du serveur : lg_USER_ID, str_LOGIN, str_FIRST_NAME, str_LAST_NAME (noms JSON du DTO).
      String champ(Map m, String json, String java) => '${m[json] ?? m[java] ?? ''}';
      if ((r.statusCode ?? 0) == 200 && info is Map && champ(info, 'lg_USER_ID', 'lgUSERID').isNotEmpty) {
        lu = User(
          userId: champ(info, 'lg_USER_ID', 'lgUSERID'),
          login: champ(info, 'str_LOGIN', 'strLOGIN'),
          firstName: champ(info, 'str_FIRST_NAME', 'strFIRSTNAME'),
          lastName: champ(info, 'str_LAST_NAME', 'strLASTNAME'),
          officineName: _user?.officineName ?? '',
        );
      }
    } catch (_) {}
    if (lu == null) {
      UtilisateurSession.id = null;
      _dernierUtilisateur = null;
      await EtatLocalVente.effacer();
      sessionExpiree();
      return;
    }
    if (_user?.userId != lu.userId) {
      UtilisateurSession.id = null;
      await EtatLocalVente.effacer();
      _userLogin = lu.login;
    }
    _dernierUtilisateur = lu.userId;
    UtilisateurSession.id = lu.userId;
    _user = lu;
    _status = AuthStatus.Authenticated;
    try {
      await lireDroitsVente(_apiService, lu.userId).timeout(delaiDroits);
    } catch (_) {}
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
    final generation = _generationSession;
    try {
      await _apiService.logout();
    } catch (e) {
      print("Erreur logout API: $e");
    }
    // 4.5.1 : une connexion a eu lieu pendant la fermeture de session (écran de connexion déjà affiché) : la nouvelle
    // session, son panier et ses droits ne sont jamais effacés par cette déconnexion (la connexion d'un autre compte a
    // déjà effacé l'état du précédent).
    if (generation != _generationSession) return;
    // 4.5.1 (changement d'utilisateur sur un téléphone partagé) : session fermée sur le serveur (POST v1/user/logout
    // ci-dessus), cookies vidés, panier / vente à reprendre / vendeur choisi / droits effacés avant la connexion
    // suivante. Les files hors ligne restent (chaque vente garde son compte).
    try {
      await DioClient.cookieJar.deleteAll();
    } catch (_) {}
    UtilisateurSession.id = null;
    _dernierUtilisateur = null;
    await EtatLocalVente.effacer();

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