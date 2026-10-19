// lib/serveur/client_prestige.dart
// Client JSON commun aux modules Réserve, Analyse posologie et Fiche client.
//
// - Même SESSION que l'application (pot à cookies partagé de DioClient : JSESSIONID posé par /user/auth) ;
//   les routes v1/reserve, v1/suggestion-reserve, v1/posos et v1/ordonnance-client n'acceptent que le cookie.
// - AUCUN journal des requêtes ni des réponses (pas de LogInterceptor) : les fiches clients contiennent des
//   données de santé, elles ne doivent jamais apparaître dans les journaux.
// - Délais d'attente bornés : jamais d'attente infinie.
// - Les erreurs sont typées pour que l'écran les distingue :
//     ServeurInjoignable (réseau, délai) / ServeurIndisponible (Prestige non déployé, 4.3.3)  ≠  SessionExpiree (HTTP 401)  ≠  RefusMetier (HTTP 200 success:false)
//     ≠  ErreurHttp (404, 500…)  ≠  ReponseIllisible.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/api/session_expiree.dart' as session_globale;
import 'package:prestige_vente_app/serveur/adresse_serveur.dart';
import 'package:prestige_vente_app/serveur/panne_serveur.dart';
import 'package:prestige_vente_app/api/utilisateur_session.dart';

/// Erreur d'un appel au serveur Prestige (message prêt à afficher, en français).
sealed class ErreurPrestige implements Exception {
  const ErreurPrestige();
  String get message;
  @override
  String toString() => message;
}

/// Le serveur n'a pas répondu (Wi-Fi, données mobiles, serveur arrêté, délai dépassé).
class ServeurInjoignable extends ErreurPrestige {
  /// Délai dépassé APRÈS l'envoi de la demande : le serveur a peut-être exécuté l'opération.
  final bool resultatIncertain;
  final bool delai;
  const ServeurInjoignable({this.delai = false, this.resultatIncertain = false});
  /// 4.3.3 : même message pour un délai dépassé, un réseau absent ou une connexion refusée (PC serveur éteint,
  /// Payara arrêté) — lib/serveur/panne_serveur.dart.
  @override
  String get message => MessagesServeur.injoignable;
}

/// 4.3.3 : le serveur répond mais Prestige n'est pas déployé (404 de Payara vérifié par /officine, 502 / 503 / 504) :
/// même conduite qu'un serveur injoignable (rien n'a été fait, réessayer plus tard), message distinct. Jamais pris
/// pour une « route absente » d'un serveur ancien.
class ServeurIndisponible extends ServeurInjoignable {
  const ServeurIndisponible();
  @override
  String get message => MessagesServeur.indisponible;
}

/// HTTPS (4.1.0) : connexion sécurisée refusée (certificat non reconnu, ou port qui ne parle pas HTTPS). La
/// requête n'est jamais partie. Sous-classe de [ServeurInjoignable] (même conduite : rien n'a été fait, réessayer
/// plus tard / hors ligne) mais message et titre distincts.
class ConnexionSecuriseeRefusee extends ServeurInjoignable {
  final ErreurTls nature;
  const ConnexionSecuriseeRefusee(this.nature);
  @override
  String get message => nature.explication;
}

/// HTTP 401 : la session Prestige a expiré (ou un autre appareil s'est connecté avec ce compte).
class SessionExpiree extends ErreurPrestige {
  const SessionExpiree();
  @override
  String get message => 'Session expirée : reconnectez-vous.';
}

/// Refus métier : HTTP 200 avec `success:false` (le message du serveur est affiché tel quel).
class RefusMetier extends ErreurPrestige {
  @override
  final String message;
  final String? code;
  const RefusMetier(this.message, {this.code});
}

/// Réponse HTTP en erreur (404 : fonction absente de ce serveur ; 5xx : erreur du serveur).
class ErreurHttp extends ErreurPrestige {
  final int status;

  /// 4.3.0 : message du serveur pour un droit manquant (HTTP 403 `{success:false, interdit:true, msg:"Droit
  /// manquant : …"}`, réponse du serveur du 15/10/2026) ; jamais une déconnexion.
  final String? detail;
  const ErreurHttp(this.status, {this.detail});

  /// Refus d'un droit (403 `interdit:true`) : ni session expirée, ni panne.
  bool get droitManquant => status == 403 && (detail ?? '').isNotEmpty;

  @override
  String get message => switch (status) {
        403 when droitManquant => detail!,
        403 => 'Accès refusé par le serveur (code 403).',
        404 => 'Cette fonction n\'existe pas sur ce serveur Prestige (code 404) : il doit être mis à jour.',
        _ => 'Erreur du serveur (code $status). Réessayez ; si cela persiste, prévenez l\'administrateur.',
      };
}

/// Réponse que l'application ne sait pas lire (page HTML, JSON tronqué…).
class ReponseIllisible extends ErreurPrestige {
  const ReponseIllisible();
  @override
  String get message => 'Réponse inattendue du serveur. Réessayez ; si cela persiste, prévenez l\'administrateur.';
}

/// Texte renvoyé par Prestige quand la session manque (filtre d'authentification ou ressource).
const String messageDeconnecte = 'Veuillez vous connecter';

class ClientPrestige {
  /// Adresse de l'API (`http://ip:port/prestige/api/v1`), relue à chaque appel (changement de serveur).
  final String Function() baseUrl;
  final Duration delaiConnexion;
  final Duration delaiReponse;

  /// Appelé à chaque HTTP 401 (mécanisme de session de l'application : la fusion peut y brancher
  /// l'intercepteur global de reconnexion). L'appel échoue de toute façon avec [SessionExpiree].
  static void Function()? surSessionExpiree;

  ClientPrestige(this.baseUrl, {this.delaiConnexion = const Duration(seconds: 8), this.delaiReponse = const Duration(seconds: 25)});

  Dio? _dio;

  Dio get _client {
    final d = _dio ??= Dio(BaseOptions(
      connectTimeout: delaiConnexion,
      sendTimeout: delaiConnexion,
      receiveTimeout: delaiReponse,
      validateStatus: (_) => true,
      responseType: ResponseType.plain,
    ))
      ..interceptors.add(CookieManager(DioClient.cookieJar));
    // Session expirée : même mécanisme global que le reste de l'application (reconnexion silencieuse si
    // « Rester connecté », requête rejouée une fois — le filtre serveur refuse AVANT d'exécuter, donc sans
    // double création — sinon retour à l'écran de connexion).
    if (!d.interceptors.any((i) => i is session_globale.IntercepteurSession)) {
      d.interceptors.add(session_globale.IntercepteurSession(d));
    }
    avecDeploiement(d);
    IntercepteurUtilisateur.brancher(d);
    d.options.baseUrl = baseUrl();
    return d;
  }

  Future<Map<String, dynamic>> get(String chemin, [Map<String, dynamic> query = const {}]) async =>
      _objet(await _envoyer((d) => d.get<String>(chemin, queryParameters: query), idempotent: true));

  /// GET dont la réponse est un tableau JSON nu (ex. motifs de suggestion).
  Future<List<dynamic>> getListe(String chemin, [Map<String, dynamic> query = const {}]) async {
    final v = await _envoyer((d) => d.get<String>(chemin, queryParameters: query), idempotent: true);
    if (v is List) return v;
    if (v is Map) {
      _verifierSucces(v);
      for (final k in const ['data', 'results']) {
        if (v[k] is List) return v[k] as List;
      }
    }
    throw const ReponseIllisible();
  }

  /// [idempotent] : faux pour une création (un délai dépassé après l'envoi rend le résultat incertain).
  /// [clientRef] (4.6.1) : en-tête `X-Client-Ref` (même clé = même réponse sur un serveur qui la gère ; un serveur
  /// plus ancien ignore l'en-tête).
  Future<Map<String, dynamic>> post(String chemin, Object? corps,
          {bool idempotent = false, Map<String, dynamic> query = const {}, String? clientRef}) async =>
      _objet(await _envoyer(
          (d) => d.post<String>(chemin,
              data: jsonEncode(corps ?? const {}),
              queryParameters: query,
              options: clientRef == null ? _json : Options(headers: {'Content-Type': 'application/json', 'X-Client-Ref': clientRef})),
          idempotent: idempotent));

  Future<Map<String, dynamic>> put(String chemin, [Object? corps, bool idempotent = true]) async => _objet(await _envoyer(
      (d) => d.put<String>(chemin, data: corps == null ? null : jsonEncode(corps), options: _json),
      idempotent: idempotent));

  Future<Map<String, dynamic>> delete(String chemin, [Map<String, dynamic> query = const {}]) async =>
      _objet(await _envoyer((d) => d.delete<String>(chemin, queryParameters: query), idempotent: true));

  static final Options _json = Options(headers: {'Content-Type': 'application/json'});

  Map<String, dynamic> _objet(Object? v) {
    if (v is! Map) throw const ReponseIllisible();
    final m = Map<String, dynamic>.from(v);
    _verifierSucces(m);
    return m;
  }

  static void _verifierSucces(Map m) {
    if (m['success'] == false || m['success'] == 'false') {
      final msg = '${m['message'] ?? m['msg'] ?? m['errors'] ?? ''}'.trim();
      if (msg == messageDeconnecte) {
        surSessionExpiree?.call();
        throw const SessionExpiree();
      }
      final code = '${m['code'] ?? ''}'.trim();
      throw RefusMetier(msg.isEmpty ? 'Opération refusée par le serveur.' : msg, code: code.isEmpty ? null : code);
    }
  }

  Future<Object?> _envoyer(Future<Response<String>> Function(Dio d) f, {required bool idempotent}) async {
    final Response<String> r;
    try {
      r = await f(_client);
    } on DioException catch (e) {
      final apresEnvoi = e.type == DioExceptionType.receiveTimeout || (e.type == DioExceptionType.sendTimeout);
      final delai = e.type == DioExceptionType.connectionTimeout || apresEnvoi;
      if (e.type == DioExceptionType.cancel) rethrow;
      final tls = ErreurTls.de(e);
      if (tls != null) throw ConnexionSecuriseeRefusee(tls);
      throw ServeurInjoignable(delai: delai, resultatIncertain: apresEnvoi && !idempotent);
    } on SocketException {
      throw const ServeurInjoignable();
    } on TlsException catch (e) {
      throw ConnexionSecuriseeRefusee(ErreurTls.de(e) ?? ErreurTls.certificat);
    } on TimeoutException {
      throw ServeurInjoignable(delai: true, resultatIncertain: !idempotent);
    }
    final status = r.statusCode ?? 0;
    if (reponseIndisponible(r)) throw const ServeurIndisponible();
    if (status == 401) {
      surSessionExpiree?.call();
      throw const SessionExpiree();
    }
    if (status == 403) throw ErreurHttp(403, detail: messageDroitManquant(r.data));
    // 4.5.1 : session passée à un autre compte (409 sessionChangee) : rien n'a été exécuté.
    final change = sessionChangeeDe(status, r.data);
    if (change != null) throw RefusMetier(change, code: 'sessionChangee');
    if (status < 200 || status >= 300) throw ErreurHttp(status);
    final texte = (r.data ?? '').trim();
    if (texte.isEmpty) throw const ReponseIllisible();
    try {
      return jsonDecode(texte);
    } catch (_) {
      throw const ReponseIllisible();
    }
  }
}

/// Message d'un refus de droit du serveur (HTTP 403 `{interdit:true, msg}`) ; null pour un autre 403 (filtre de
/// connexion, page HTML…).
String? messageDroitManquant(Object? corps) {
  Object? j = corps;
  if (j is String) {
    try {
      j = jsonDecode(j);
    } catch (_) {
      return null;
    }
  }
  if (j is! Map || (j['interdit'] != true && j['interdit'] != 'true')) return null;
  final m = '${j['msg'] ?? j['message'] ?? ''}'.trim();
  return m.isEmpty ? 'Droit manquant : demandez-le à l\'administrateur de Prestige.' : m;
}
