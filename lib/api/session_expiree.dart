// lib/api/session_expiree.dart
// Session expirée côté serveur (Prestige : sessions expirées après KEY_DUREE_SESSION_MINUTES minutes sans
// requête — 720 = 12 h par défaut ; routes publiques sans cookie ; session créée seulement à POST v1/user/auth).
// Le filtre AuthenticationFilter répond alors 401 « Veuillez vous connecter » (texte) SANS exécuter la requête.
//
// Intercepteur GLOBAL du client Dio partagé (DioClient) — routes non publiques, utilisateur connecté :
// 1) « Rester connecté » actif et mot de passe dans le stockage sûr : RECONNEXION SILENCIEUSE une seule fois
//    (verrou : une seule reconnexion pour toutes les requêtes en vol), puis la requête d'origine est REJOUÉE
//    une fois (sûr : un 401 du filtre signifie que la requête n'a pas été exécutée) ; journal du terminal
//    (type connexion, jamais de secret) ;
// 2) sinon, ou si la reconnexion échoue : déconnexion locale et RETOUR À L'ÉCRAN DE CONNEXION avec
//    « Votre session a expiré, reconnectez-vous » ; les files hors ligne (ventes HL, stock, pointage,
//    support) ne sont pas touchées et reprennent après la reconnexion ;
// 3) jamais de boucle : pas d'interception de la connexion elle-même ni des routes publiques, une seule
//    tentative par requête (requête rejouée marquée), une requête partie avant une reconnexion réussie
//    est simplement rejouée (pas de deuxième reconnexion).
import 'dart:async';

import 'package:dio/dio.dart';

class SessionExpiree {
  SessionExpiree();

  /// Instance de l'application (remplaçable dans les tests).
  static SessionExpiree instance = SessionExpiree();

  /// Message affiché sur l'écran de connexion.
  static const message = 'Votre session a expiré, reconnectez-vous';

  /// Un utilisateur est connecté (sinon rien n'est intercepté : lancement, connexion, licence…).
  bool Function() connecte = () => false;

  /// Reconnexion silencieuse (identifiants mémorisés) : true si réussie, false si impossible ou refusée.
  Future<bool> Function() reconnecter = () async => false;

  /// Déconnexion locale et retour à l'écran de connexion avec [message].
  void Function(String message) versConnexion = (_) {};

  /// Journal du terminal (type connexion) — jamais de secret.
  void Function(String action, {required bool ok, String motif}) journal = (_, {required ok, motif = ''}) {};

  /// Délai maximal de la reconnexion silencieuse.
  Duration delai = const Duration(seconds: 20);

  /// Numéro de session : augmente à chaque connexion réussie (manuelle ou silencieuse).
  int generation = 0;

  /// Diagnostic (tests) : reconnexions silencieuses tentées, requêtes rejouées.
  int reconnexions = 0;
  int rejouees = 0;

  Future<bool>? _enCours;
  bool _redirige = false;

  /// Reconnexion partagée : toutes les requêtes refusées en même temps attendent la même.
  Future<bool> reconnexionPartagee() => _enCours ??= _reconnecter().whenComplete(() => _enCours = null);

  Future<bool> _reconnecter() async {
    reconnexions++;
    bool ok;
    try {
      ok = await reconnecter().timeout(delai);
    } catch (_) {
      ok = false;
    }
    try {
      journal(ok ? 'Session expirée : reconnexion automatique réussie' : 'Session expirée : reconnexion automatique impossible',
          ok: ok, motif: ok ? '' : 'identifiants non mémorisés ou refusés');
    } catch (_) {}
    if (ok) generation++;
    return ok;
  }

  /// Retour à l'écran de connexion (une seule fois, jusqu'à la prochaine connexion réussie).
  void deconnecter() {
    if (_redirige) return;
    _redirige = true;
    try {
      journal('Session expirée : retour à l\'écran de connexion', ok: false, motif: 'reconnexion automatique impossible');
    } catch (_) {}
    versConnexion(message);
  }

  /// Connexion manuelle réussie : les requêtes parties avant sont rejouées, un nouveau retour à la connexion
  /// redevient possible.
  void connexionReussie() {
    _redirige = false;
    generation++;
  }
}

/// Routes publiques (ou avec leur propre client à jeton) : jamais interceptées.
bool routeSansSession(String path) {
  var p = path;
  final q = p.indexOf('?');
  if (q >= 0) p = p.substring(0, q);
  while (p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }
  const publiques = ['/user/auth', '/user/logout', '/licence/find', '/officine', '/app/info'];
  if (publiques.any(p.endsWith)) return true;
  // Téléphones à jeton (v1/mobile/…), espace produit et avis publics : routes ouvertes ou authentifiées autrement.
  return p.contains('/mobile/') || p.contains('/espace-produit/') || p.contains('/avis-public/');
}

/// Réponse du filtre de connexion : 401, ou 403 « Veuillez vous connecter » (texte).
bool refusDeSession(Response<dynamic>? r) {
  if (r == null) return false;
  if (r.statusCode == 401) return true;
  if (r.statusCode == 403) {
    final d = r.data;
    return d is String && d.toLowerCase().contains('vous connecter');
  }
  return false;
}

class IntercepteurSession extends Interceptor {
  final Dio dio;
  final SessionExpiree Function() _session;

  IntercepteurSession(this.dio, {SessionExpiree Function()? session}) : _session = session ?? (() => SessionExpiree.instance);

  static const cleRejouee = 'session_rejouee';
  static const cleGeneration = 'session_generation';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra.putIfAbsent(cleGeneration, () => _session().generation);
    handler.next(options);
  }

  @override
  Future<void> onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) async {
    // Requêtes qui acceptent tous les codes (validateStatus) : même traitement.
    if (!_aTraiter(response.requestOptions, response)) return handler.next(response);
    final r = await _rejouer(response.requestOptions);
    if (r != null) return handler.resolve(r);
    handler.next(response);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    if (!_aTraiter(err.requestOptions, err.response)) return handler.next(err);
    try {
      final r = await _rejouer(err.requestOptions);
      if (r != null) return handler.resolve(r);
    } on DioException catch (e) {
      return handler.next(e);
    }
    handler.next(err);
  }

  bool _aTraiter(RequestOptions o, Response<dynamic>? r) =>
      refusDeSession(r) && o.extra[cleRejouee] != true && !routeSansSession(o.uri.path) && _session().connecte();

  /// Reconnexion (partagée) puis requête rejouée une fois ; null : pas de reconnexion possible (retour à la
  /// connexion demandé). Une requête rejouée et de nouveau refusée est rendue telle quelle (pas de boucle).
  Future<Response<dynamic>?> _rejouer(RequestOptions o) async {
    final s = _session();
    final gen = o.extra[cleGeneration];
    // Partie avant une reconnexion déjà réussie : simplement rejouée avec la nouvelle session.
    final ok = (gen is int && gen < s.generation) ? true : await s.reconnexionPartagee();
    if (!ok) {
      s.deconnecter();
      return null;
    }
    final headers = Map<String, dynamic>.from(o.headers)..removeWhere((k, _) => k.toLowerCase() == 'cookie');
    final data = o.data is FormData ? (o.data as FormData).clone() : o.data;
    s.rejouees++;
    final r = await dio.fetch<dynamic>(o.copyWith(
      headers: headers,
      data: data,
      extra: {...o.extra, cleRejouee: true, cleGeneration: s.generation},
    ));
    return r;
  }
}
