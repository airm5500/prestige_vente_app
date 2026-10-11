// lib/rh/mobile_api.dart
// Voie A — l'employé pointe avec SON téléphone : API `v1/mobile` de Prestige (jeton Bearer).
//
// Sécurité (cahier serveur, § 4) :
// - client Dio SÉPARÉ : ni cookies de la session de l'appli, ni journal des requêtes / réponses ;
// - le jeton est gardé dans le stockage sécurisé du téléphone (flutter_secure_storage : Keystore Android),
//   jamais en clair, jamais dans les journaux ; le mot de passe n'est JAMAIS conservé ;
// - 401 {"expire": true} : jeton effacé, retour à la connexion (pas de rafraîchissement : 12 h par défaut).
// Pas de pointage hors ligne : l'heure est celle du serveur et le QR change chaque minute.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:prestige_vente_app/rh/rh_models.dart';

// ---------------------------------------------------------------------------
// Stockage du jeton
// ---------------------------------------------------------------------------

/// Coffre du jeton mobile (remplaçable pour les tests).
abstract class CoffreJeton {
  Future<String?> lire();
  Future<void> ecrire(String valeur);
  Future<void> effacer();
}

/// Stockage sécurisé du téléphone (Keystore Android / Keychain iOS).
class CoffreJetonSecurise implements CoffreJeton {
  static const _cle = 'prestige_rh_session_mobile_v1';
  final FlutterSecureStorage _stockage;
  const CoffreJetonSecurise([this._stockage = const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true))]);

  @override
  Future<String?> lire() async {
    try {
      return await _stockage.read(key: _cle);
    } catch (_) {
      // Coffre illisible (sauvegarde restaurée sur un autre appareil…) : nouvelle connexion.
      return null;
    }
  }

  @override
  Future<void> ecrire(String valeur) => _stockage.write(key: _cle, value: valeur);

  @override
  Future<void> effacer() async {
    try {
      await _stockage.delete(key: _cle);
    } catch (_) {}
  }
}

/// Coffre en mémoire (tests).
class CoffreJetonMemoire implements CoffreJeton {
  String? valeur;
  CoffreJetonMemoire([this.valeur]);
  @override
  Future<String?> lire() async => valeur;
  @override
  Future<void> ecrire(String v) async => valeur = v;
  @override
  Future<void> effacer() async => valeur = null;
}

// ---------------------------------------------------------------------------
// Transport (remplaçable pour les tests)
// ---------------------------------------------------------------------------

/// Réponse brute : code HTTP et corps JSON (null si illisible).
typedef ReponseHttp = ({int status, Map<String, dynamic>? body});

/// Appel HTTP de la voie A. Lève [MobileHorsLigne] si le serveur ne répond pas.
abstract class TransportMobile {
  Future<ReponseHttp> envoyer(String methode, String chemin, {Map<String, dynamic>? corps, String? jeton});
}

/// Dio dédié : base `<serveur>/api/v1/mobile/`, sans cookies ni journal (le jeton ne doit jamais être écrit).
class DioTransportMobile implements TransportMobile {
  final String Function() baseUrl;
  Dio? _dio;
  DioTransportMobile(this.baseUrl);

  Dio get _client {
    final d = _dio ??= Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      validateStatus: (_) => true,
      responseType: ResponseType.plain,
    ));
    d.options.baseUrl = '${baseUrl().replaceAll(RegExp(r'/+$'), '')}/mobile/';
    return d;
  }

  @override
  Future<ReponseHttp> envoyer(String methode, String chemin, {Map<String, dynamic>? corps, String? jeton}) async {
    try {
      final r = await _client.request<String>(
        chemin,
        data: corps == null ? null : jsonEncode(corps),
        options: Options(method: methode, headers: {
          if (corps != null) 'Content-Type': 'application/json',
          if (jeton != null) 'Authorization': 'Bearer $jeton',
        }),
      );
      Map<String, dynamic>? body;
      try {
        final o = jsonDecode(r.data ?? '');
        if (o is Map) body = Map<String, dynamic>.from(o);
      } catch (_) {}
      return (status: r.statusCode ?? 0, body: body);
    } on DioException catch (e) {
      if (e.response == null) throw const MobileHorsLigne();
      return (status: e.response?.statusCode ?? 0, body: null);
    }
  }
}

// ---------------------------------------------------------------------------
// Erreurs
// ---------------------------------------------------------------------------

/// Serveur injoignable : la voie A n'existe qu'en ligne.
class MobileHorsLigne implements Exception {
  const MobileHorsLigne();
  static const message = 'Disponible en ligne uniquement : le serveur Prestige ne répond pas.';
  @override
  String toString() => message;
}

/// Jeton refusé ou expiré (401) : le téléphone doit se reconnecter.
class MobileSessionExpiree implements Exception {
  final String message;
  const MobileSessionExpiree([this.message = 'Session du téléphone expirée : reconnectez-vous.']);
  @override
  String toString() => message;
}

/// Le serveur ne connaît pas l'API des téléphones (version plus ancienne : 404).
class MobileIndisponible implements Exception {
  const MobileIndisponible();
  static const message = 'Le pointage par téléphone n\'existe pas sur cette version du serveur Prestige.';
  @override
  String toString() => message;
}

/// Résultat d'un appel : succès, ou refus du serveur (message affiché tel quel).
class ResultatMobile<T> {
  final T? valeur;
  final String? refus;

  /// Connexion des téléphones désactivée par l'officine (KEY_MOBILE_ACTIF = 0).
  final bool moduleInactif;
  const ResultatMobile.ok(T this.valeur)
      : refus = null,
        moduleInactif = false;
  const ResultatMobile.refus(String this.refus, {this.moduleInactif = false}) : valeur = null;
  bool get ok => refus == null;
}

/// Message affiché quand l'officine a désactivé la connexion des téléphones.
const String messageModuleMobileInactif = 'Pointage mobile non activé sur le serveur.';

/// Refus « connexion des téléphones désactivée » (KEY_MOBILE_ACTIF = 0).
bool estModuleMobileInactif(String message) {
  final m = message.toLowerCase();
  return m.contains('téléphones est désactivée') || m.contains('telephones est desactivee');
}

// ---------------------------------------------------------------------------
// API
// ---------------------------------------------------------------------------

/// Résultat d'un pointage accepté : sens et heure DU SERVEUR.
class PointageAccepte {
  final SensPointage? sens;
  final String heure;
  final String message;
  const PointageAccepte({this.sens, required this.heure, required this.message});
}

class MobileApi extends ChangeNotifier {
  final TransportMobile transport;
  final CoffreJeton coffre;
  final DateTime Function() _clock;

  /// Identifiant STABLE de l'appareil (≤ 80 caractères) et nom affiché dans Prestige.
  final String Function() appareil;
  final String Function() nomAppareil;

  MobileApi({
    required this.transport,
    CoffreJeton? coffre,
    required this.appareil,
    required this.nomAppareil,
    DateTime Function()? clock,
  })  : coffre = coffre ?? const CoffreJetonSecurise(),
        _clock = clock ?? DateTime.now;

  SessionMobile? _session;
  bool _charge = false;

  /// Session en cours (null : connexion demandée).
  SessionMobile? get session => _session;

  /// Session reprise du coffre (null si absente ou expirée : le coffre est alors vidé).
  Future<SessionMobile?> reprendre() async {
    if (_charge) return _valide(_session);
    _charge = true;
    final brut = await coffre.lire();
    if (brut != null && brut.isNotEmpty) {
      try {
        final j = jsonDecode(brut);
        if (j is Map) {
          final m = Map<String, dynamic>.from(j);
          _session = SessionMobile.fromJson(m, jeton: '${m['jeton'] ?? ''}');
        }
      } catch (_) {
        _session = null;
      }
    }
    final s = _valide(_session);
    if (s == null && _session != null) await deconnecter();
    return s;
  }

  SessionMobile? _valide(SessionMobile? s) => s == null || s.jeton.isEmpty || s.expireA(_clock()) ? null : s;

  /// POST connexion. Le mot de passe n'est utilisé que pour cet appel, jamais conservé.
  Future<ResultatMobile<SessionMobile>> connexion(String login, String motDePasse) async {
    final app = appareil().trim();
    final r = await transport.envoyer('POST', 'connexion', corps: {
      'login': login.trim(),
      'motDePasse': motDePasse,
      'appareil': app.length > 80 ? app.substring(0, 80) : app,
      'nomAppareil': _borne(nomAppareil(), 80),
    });
    if (r.status == 404) throw const MobileIndisponible();
    final b = r.body;
    if (b == null) return ResultatMobile.refus('Réponse illisible du serveur (${r.status}).');
    if (b['success'] != true) {
      final m = _message(b, 'Connexion refusée.');
      return ResultatMobile.refus(estModuleMobileInactif(m) ? messageModuleMobileInactif : m, moduleInactif: estModuleMobileInactif(m));
    }
    final s = SessionMobile.fromJson(b);
    if (s.jeton.isEmpty) return const ResultatMobile.refus('Le serveur n\'a pas délivré de jeton.');
    _session = s;
    _charge = true;
    await coffre.ecrire(jsonEncode(s.toJson()));
    notifyListeners();
    return ResultatMobile.ok(s);
  }

  /// Le serveur connaît-il l'API des téléphones, et la connexion y est-elle active ?
  /// (POST connexion SANS identifiants : aucun appareil n'est enregistré, le serveur répond par un refus.)
  /// null : serveur injoignable.
  Future<({bool existe, bool actif})?> sonder() async {
    try {
      final r = await transport.envoyer('POST', 'connexion', corps: const {});
      if (r.status == 404) return (existe: false, actif: false);
      final m = r.body == null ? '' : _message(r.body!, '');
      return (existe: true, actif: !estModuleMobileInactif(m));
    } on MobileHorsLigne {
      return null;
    }
  }

  /// GET moi : droits et réglages relus (ils ont pu changer depuis la connexion).
  Future<SessionMobile> moi() async {
    final s = await _exiger();
    final b = await _appel('GET', 'moi', s);
    if (b['success'] != true) throw MobileSessionExpiree(_message(b, 'Session du téléphone refusée.'));
    final n = s.avec(SessionMobile.fromJson(b, jeton: s.jeton, expiration: s.expiration));
    _session = n;
    await coffre.ecrire(jsonEncode(n.toJson()));
    notifyListeners();
    return n;
  }

  /// POST pointages. [sens] null : le serveur prend l'inverse du dernier pointage (16 h).
  Future<ResultatMobile<PointageAccepte>> pointer({SensPointage? sens, String? code, PositionPointage? position}) async {
    final s = await _exiger();
    final b = await _appel('POST', 'pointages', s, corps: {
      if (sens != null) 'sens': sens.code,
      if (code != null && code.trim().isNotEmpty) 'code': code.trim(),
      if (position != null) ...{
        'latitude': position.latitude,
        'longitude': position.longitude,
        if (position.precision != null) 'precision': position.precision,
      },
    });
    if (b['success'] != true) return ResultatMobile.refus(_message(b, 'Pointage refusé.'));
    final heure = '${b['heure'] ?? ''}';
    final sensOk = sensDepuisCode(b['sens']);
    return ResultatMobile.ok(PointageAccepte(
      sens: sensOk,
      heure: heure,
      message: '${b['message'] ?? ''}'.trim().isNotEmpty ? '${b['message']}' : '${sensOk?.label ?? 'Pointage'} enregistrée à $heure.',
    ));
  }

  /// GET pointages : mes pointages des 16 dernières heures (toutes sources).
  Future<List<PointageMobile>> mesPointages() async {
    final s = await _exiger();
    final b = await _appel('GET', 'pointages', s);
    final d = b['data'];
    return [
      if (d is List)
        for (final x in d)
          if (x is Map) PointageMobile.fromJson(Map<String, dynamic>.from(x)),
    ];
  }

  /// Efface le jeton du téléphone (déconnexion, ou jeton refusé).
  Future<void> deconnecter() async {
    _session = null;
    await coffre.effacer();
    notifyListeners();
  }

  Future<SessionMobile> _exiger() async {
    final s = await reprendre();
    if (s == null) throw const MobileSessionExpiree('Connectez-vous pour pointer.');
    return s;
  }

  Future<Map<String, dynamic>> _appel(String methode, String chemin, SessionMobile s, {Map<String, dynamic>? corps}) async {
    final r = await transport.envoyer(methode, chemin, corps: corps, jeton: s.jeton);
    if (r.status == 401) {
      await deconnecter();
      throw MobileSessionExpiree(_message(r.body ?? const {}, 'Session du téléphone expirée : reconnectez-vous.'));
    }
    if (r.status == 404) throw const MobileIndisponible();
    final b = r.body;
    if (b == null) return {'success': false, 'message': 'Réponse illisible du serveur (${r.status}).'};
    return b;
  }

  static String _message(Map<String, dynamic> b, String defaut) {
    final m = '${b['message'] ?? b['msg'] ?? ''}'.trim();
    return m.isEmpty ? defaut : m;
  }

  static String _borne(String s, int n) => s.length > n ? s.substring(0, n) : s;
}
