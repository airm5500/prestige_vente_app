// lib/api/utilisateur_session.dart
// 4.5.1 — Demande du serveur du 19/10/2026 (sécurité des ventes, docs/serveur/DEMANDE_SERVEUR_DROITS_VENTE_2026-10-19.md) :
//
// - En-tête `X-Prestige-Utilisateur` = `str_USER_ID` reçu à la connexion, sur CHAQUE requête de tous les clients HTTP
//   de l'application ([IntercepteurUtilisateur]). Le serveur (filtre UtilisateurOngletFilter) le compare au compte de
//   la session : si la session a changé de compte entre-temps, il répond 409 `{success:false, sessionChangee:true,
//   msg}` SANS RIEN EXÉCUTER. Sans en-tête (avant la connexion, serveur ancien), rien ne change.
// - 409 `sessionChangee` : [SessionChangee] prévient l'application une seule fois par rafale (message affiché, compte
//   et droits relus, retour à l'accueil, panier du compte précédent effacé ; files hors ligne gardées), branché par
//   lib/connexion/changement_utilisateur.dart. L'appel refusé échoue normalement chez l'appelant : rien n'a été fait.
// - 403 `interdit` (droit manquant) : jamais une déconnexion (seul 401 = session absente) ; [refusDeDroit] lit le
//   message du serveur.
// Valeurs en MÉMOIRE seulement (jamais sur disque).
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

class UtilisateurSession {
  UtilisateurSession._();

  /// Nom de l'en-tête lu par le serveur (filtre UtilisateurOngletFilter).
  static const entete = 'X-Prestige-Utilisateur';

  /// `str_USER_ID` du compte connecté (null : personne, ou déconnecté).
  static String? id;
}

/// Corps JSON d'une réponse (texte ou objet), null s'il n'est pas un objet.
Map<String, dynamic>? corpsJson(Object? corps) {
  Object? j = corps;
  if (j is String) {
    final t = j.trim();
    if (!t.startsWith('{')) return null;
    try {
      j = jsonDecode(t);
    } catch (_) {
      return null;
    }
  }
  return j is Map ? Map<String, dynamic>.from(j) : null;
}

bool _vrai(Object? v) => v == true || v == 'true';

/// Message d'un refus de droit (HTTP 403 `{interdit:true, msg}`), null sinon (autre 403, 401…).
String? refusDeDroit(int? statut, Object? corps) {
  if (statut != 403) return null;
  final j = corpsJson(corps);
  if (j == null || !_vrai(j['interdit'])) return null;
  final m = '${j['msg'] ?? j['message'] ?? ''}'.trim();
  return m.isEmpty ? 'Action non autorisée pour ce compte : demandez le droit à l\'administrateur de Prestige.' : m;
}

/// Message d'une session qui a changé de compte (HTTP 409 `{sessionChangee:true, msg}`), null sinon.
String? sessionChangeeDe(int? statut, Object? corps) {
  if (statut != 409) return null;
  final j = corpsJson(corps);
  if (j == null || !_vrai(j['sessionChangee'])) return null;
  final m = '${j['msg'] ?? j['message'] ?? ''}'.trim();
  return m.isEmpty ? SessionChangee.messageParDefaut : m;
}

/// Prévient l'application d'un 409 `sessionChangee` (une seule fois par rafale de requêtes refusées).
class SessionChangee {
  SessionChangee();

  static SessionChangee instance = SessionChangee();

  static const messageParDefaut = 'Un autre compte s\'est connecté sur cet appareil. Rien n\'a été enregistré.';

  /// Branché par l'application (lib/connexion/changement_utilisateur.dart).
  Future<void> Function(String message) traiter = (_) async {};

  /// Diagnostic (tests) : 409 reçus, traitements lancés.
  int recus = 0;
  int traitements = 0;

  Future<void>? _enCours;

  void signaler(String message) {
    recus++;
    if (_enCours != null) return;
    traitements++;
    _enCours = Future(() => traiter(message)).catchError((_) {}).whenComplete(() => _enCours = null);
  }

  /// Tests : attendre la fin du traitement en cours.
  Future<void> attendre() => _enCours ?? Future.value();
}

/// Routes où l'en-tête n'a pas de sens (connexion : le compte va changer).
bool _sansEntete(String chemin) {
  var p = chemin;
  final q = p.indexOf('?');
  if (q >= 0) p = p.substring(0, q);
  return p.endsWith('/user/auth') || p.endsWith('/user/auth-badge');
}

/// À ajouter à CHAQUE client Dio qui parle au serveur Prestige.
class IntercepteurUtilisateur extends Interceptor {
  IntercepteurUtilisateur({String? Function()? utilisateur, SessionChangee Function()? session})
      : _utilisateur = utilisateur ?? (() => UtilisateurSession.id),
        _session = session ?? (() => SessionChangee.instance);

  final String? Function() _utilisateur;
  final SessionChangee Function() _session;

  /// Ajoute l'intercepteur s'il n'y est pas déjà.
  static Dio brancher(Dio d) {
    if (!d.interceptors.any((i) => i is IntercepteurUtilisateur)) d.interceptors.add(IntercepteurUtilisateur());
    return d;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final id = _utilisateur();
    if (id != null && id.isNotEmpty && !_sansEntete(options.uri.path)) {
      options.headers[UtilisateurSession.entete] = id;
    } else {
      options.headers.remove(UtilisateurSession.entete);
    }
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final m = sessionChangeeDe(response.statusCode, response.data);
    if (m != null) _session().signaler(m);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final m = sessionChangeeDe(err.response?.statusCode, err.response?.data);
    if (m != null) _session().signaler(m);
    handler.next(err);
  }
}
