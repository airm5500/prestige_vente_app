// lib/serveur/panne_serveur.dart
// 4.3.3 — Deux pannes du serveur, affichées différemment partout (connexion, accueil, modules, borne, pointage) :
//
// 1. INJOIGNABLE : aucune réponse (délai dépassé, hôte inaccessible, réseau absent, connexion refusée = PC serveur
//    éteint ou Payara arrêté) → « Serveur injoignable. Vérifiez le Wi-Fi et que le PC serveur est allumé. »
// 2. INDISPONIBLE : le serveur répond mais Prestige n'est pas déployé (404 HTML ou vide de Payara, 502 / 503 / 504)
//    → « Serveur indisponible : Prestige est en cours de démarrage ou de redéploiement. Veuillez réessayer dans un
//    instant. »
// Mot de passe faux, erreur 500 et refus métier : inchangés.
//
// Un 404 de Payara a le même corps (page HTML « Error report ») que Prestige soit absent ou qu'une route manque sur
// un serveur ancien. Sur un tel 404 (corps HTML ou vide, jamais une réponse JSON de Prestige), [IntercepteurDeploiement]
// vérifie GET /officine (route publique de tous les serveurs Prestige) — aucune requête de plus en fonctionnement
// normal, une seule vérification partagée pour les 404 simultanés, résultat gardé 10 s :
//  - /officine répond → Prestige est déployé : le 404 est rendu tel quel (route vraiment absente, repli d'origine) ;
//  - /officine répond 404 / 502 / 503 / 504, ou ne répond pas → Prestige indisponible : la réponse devient un 503
//    marqué ([cleIndisponible]). Les replis « serveur ancien » ne la prennent donc jamais pour une route absente
//    (rien n'est mémorisé) : l'opération est simplement à réessayer.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:prestige_vente_app/serveur/nom_appareil.dart';

enum PanneServeur { injoignable, indisponible }

abstract final class MessagesServeur {
  static const titreInjoignable = 'Serveur injoignable';
  static const titreIndisponible = 'Serveur indisponible';
  static const detailInjoignable = 'Vérifiez le Wi-Fi et que le PC serveur est allumé.';
  static const detailIndisponible = 'Prestige est en cours de démarrage ou de redéploiement. Veuillez réessayer dans un instant.';

  /// « Serveur injoignable. Vérifiez le Wi-Fi et que le PC serveur est allumé. »
  static const injoignable = '$titreInjoignable. $detailInjoignable';

  /// « Serveur indisponible : Prestige est en cours de démarrage ou de redéploiement. Veuillez réessayer dans un instant. »
  static const indisponible = '$titreIndisponible : $detailIndisponible';

  static String message(PanneServeur p) => p == PanneServeur.injoignable ? injoignable : indisponible;
  static String titre(PanneServeur p) => p == PanneServeur.injoignable ? titreInjoignable : titreIndisponible;
  static String detail(PanneServeur p) => p == PanneServeur.injoignable ? detailInjoignable : detailIndisponible;
}

/// Codes d'une passerelle / d'un serveur d'applications sans Prestige prêt.
bool codePasserelle(int? code) => code == 502 || code == 503 || code == 504;

/// Marque posée par [IntercepteurDeploiement] sur une réponse « Prestige non déployé » (devenue 503).
const cleIndisponible = 'prestige_indisponible';

/// Réponse d'un serveur sans Prestige prêt (502 / 503 / 504, ou 404 de Payara vérifié par /officine).
bool reponseIndisponible(Response<dynamic>? r) => r != null && (codePasserelle(r.statusCode) || r.extra[cleIndisponible] == true);

/// Panne de disponibilité de [e] ; null si le serveur Prestige a répondu (refus, 401, 500…), si la requête a été
/// annulée, ou pour un échec HTTPS (certificat, protocole : messages propres).
PanneServeur? panneDe(Object? e) {
  if (e is DioException) {
    if (e.type == DioExceptionType.cancel || e.type == DioExceptionType.badCertificate || e.error is TlsException) return null;
    final r = e.response;
    if (r != null) return reponseIndisponible(r) ? PanneServeur.indisponible : null;
    return switch (e.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.connectionError =>
        PanneServeur.injoignable,
      _ => e.error is SocketException || e.error is HttpException || e.error is TimeoutException ? PanneServeur.injoignable : null,
    };
  }
  if (e is SocketException || e is TimeoutException || e is HttpException) return PanneServeur.injoignable;
  return null;
}

/// Corps qui ne vient pas de Prestige (page HTML de Payara, corps vide) : un 404 ainsi est à vérifier.
bool corpsNonPrestige(Object? data) {
  if (data == null) return true;
  if (data is List<int>) return data.isEmpty || _texteNonJson(utf8.decode(data, allowMalformed: true));
  if (data is Map || data is List) return false;
  return _texteNonJson('$data');
}

bool _texteNonJson(String t) {
  final s = t.trim();
  if (s.isEmpty) return true;
  if (s.startsWith('{') || s.startsWith('[')) {
    try {
      jsonDecode(s);
      return false;
    } catch (_) {
      return true;
    }
  }
  return true;
}

/// Vérification « Prestige est-il déployé ? » par GET /officine, partagée et gardée [validite].
abstract final class SondeDeploiement {
  static Duration validite = const Duration(seconds: 10);
  static Duration delai = const Duration(seconds: 6);
  static DateTime Function() horloge = DateTime.now;

  static final Map<String, ({bool deploye, DateTime at})> _connus = {};
  static final Map<String, Future<bool>> _enCours = {};

  /// Vérifications réellement envoyées (diagnostic, tests).
  static int sondes = 0;

  /// Racine de l'API (`http://hote:port/prestige/api/v1`) d'une adresse de requête, ou null.
  static String? racine(Uri uri) {
    final i = uri.path.indexOf('/api/v1');
    if (i < 0) return null;
    return '${uri.scheme}://${uri.authority}${uri.path.substring(0, i + 7)}';
  }

  /// Prestige répond-il à GET [racine]/officine ? (404 / 502 / 503 / 504 / pas de réponse : non). [transport] : celui
  /// du client qui a reçu le 404 (même chemin réseau, mêmes réglages HTTPS).
  static Future<bool> deploye(String racine, {HttpClientAdapter? transport}) {
    final c = _connus[racine];
    if (c != null && horloge().difference(c.at) <= validite) return Future.value(c.deploye);
    return _enCours[racine] ??= _verifier(racine, transport).then((ok) {
      _connus[racine] = (deploye: ok, at: horloge());
      return ok;
    }).whenComplete(() {
      _enCours.remove(racine); // (bloc : ne pas renvoyer la Future retirée, sinon attente d'elle-même)
    });
  }

  static Future<bool> _verifier(String racine, HttpClientAdapter? transport) async {
    sondes++;
    final d = IntercepteurPoste.brancher(Dio(BaseOptions(connectTimeout: delai, sendTimeout: delai, receiveTimeout: delai, validateStatus: (_) => true)));
    if (transport != null) d.httpClientAdapter = transport; // partagé : jamais fermé ici
    try {
      final r = await d.get<dynamic>('$racine/officine');
      final code = r.statusCode ?? 0;
      return code > 0 && code != 404 && !codePasserelle(code);
    } catch (_) {
      return false;
    } finally {
      if (transport == null) d.close(force: true);
    }
  }

  /// Oublie tout (changement de serveur, tests).
  static void vider() {
    _connus.clear();
    _enCours.clear();
  }
}

/// Routes présentes sur TOUT serveur Prestige : leur 404 prouve que Prestige n'est pas déployé (pas de vérification).
const _routesToujoursPresentes = ['/officine', '/user/auth'];

/// Intercepteur à poser sur chaque client HTTP de l'application (voir l'en-tête du fichier).
class IntercepteurDeploiement extends Interceptor {
  /// Client sur lequel l'intercepteur est posé : la vérification passe par son transport.
  final Dio? source;
  IntercepteurDeploiement({this.source});

  @override
  Future<void> onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) async {
    if (response.statusCode == 404 && await _indisponible(response)) return handler.next(_marquer(response));
    handler.next(response);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final r = err.response;
    if (r != null && r.statusCode == 404 && await _indisponible(r)) {
      return handler.next(DioException(
        requestOptions: err.requestOptions,
        response: _marquer(r),
        type: DioExceptionType.badResponse,
        message: MessagesServeur.indisponible,
      ));
    }
    handler.next(err);
  }

  Future<bool> _indisponible(Response<dynamic> r) async {
    if (!corpsNonPrestige(r.data)) return false;
    final uri = r.requestOptions.uri;
    if (_routesToujoursPresentes.any(uri.path.endsWith)) return true;
    final base = SondeDeploiement.racine(uri);
    if (base == null) return false;
    return !await SondeDeploiement.deploye(base, transport: source?.httpClientAdapter);
  }

  static Response<dynamic> _marquer(Response<dynamic> r) => Response<dynamic>(
        data: r.data,
        statusCode: 503,
        statusMessage: 'Prestige indisponible',
        headers: r.headers,
        requestOptions: r.requestOptions,
        redirects: r.redirects,
        isRedirect: r.isRedirect,
        extra: {...r.extra, cleIndisponible: true},
      );
}

/// Pose [IntercepteurDeploiement] sur [d] (une seule fois) et renvoie [d].
/// 4.7.0 : pose aussi [IntercepteurPoste] (nom de cet appareil, en-tête X-Poste) : tous les clients de Prestige
/// passent par ici.
Dio avecDeploiement(Dio d) {
  if (!d.interceptors.any((i) => i is IntercepteurDeploiement)) d.interceptors.add(IntercepteurDeploiement(source: d));
  IntercepteurPoste.brancher(d);
  return d;
}
