// lib/utils/journal_debug.dart
// 4.7.1 — journal de la console sans secret ni donnée de client ou de patient.
//  - Requêtes HTTP (mode DÉBOGAGE seulement, [JournalHttpDebug]) : méthode, chemin (sans paramètres), statut et durée.
//    Jamais de corps (identifiants de connexion, ventes, clients, ordonnances), d'en-têtes (cookies, Authorization,
//    jetons, X-Client-Ref, X-Poste), ni de paramètres de la requête (recherche d'un client, d'un produit…).
//  - Erreurs ([journalErreur]) : contexte et TYPE de l'erreur (DioException : type, statut, méthode et chemin). Le
//    message d'une exception peut recopier une réponse du serveur (FormatException d'un JSON), une adresse avec ses
//    paramètres ou un contenu lu (QR d'un badge) : il n'est jamais écrit.
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

final RegExp _segmentRoute = RegExp(r'^([A-Za-z_\-]+|v\d+)$');

/// Chemin sans paramètres ni fragment, et sans valeur : un segment qui n'est pas un nom de route (lettres, tirets ;
/// ou v1) est remplacé par « * » (identifiant de vente, clé de licence, clé X-Client-Ref…). Ex. /vente/V-1 → /vente/*.
String cheminSansParametres(Uri u) =>
    u.pathSegments.isEmpty ? '/' : '/${[for (final s in u.pathSegments) _segmentRoute.hasMatch(s) ? s : '*'].join('/')}';

/// Résumé d'une erreur, sans son message.
String resumeErreur(Object e) {
  if (e is DioException) {
    final o = e.requestOptions;
    final statut = e.response?.statusCode;
    return 'DioException ${e.type.name}${statut == null ? '' : ', HTTP $statut'} · ${o.method} ${cheminSansParametres(o.uri)}';
  }
  return e.runtimeType.toString();
}

/// Écrit « contexte : type de l'erreur » dans la console (jamais le message de l'erreur).
void journalErreur(String contexte, Object e) => debugPrint('$contexte : ${resumeErreur(e)}');

/// Journal des requêtes HTTP du mode débogage : méthode, chemin, statut, durée. Rien d'autre.
class JournalHttpDebug extends Interceptor {
  JournalHttpDebug({void Function(String)? ecrire}) : _ecrire = ecrire ?? ((l) => debugPrint(l));
  final void Function(String) _ecrire;
  static const _debut = 'journal_debug_debut';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_debut] = DateTime.now().millisecondsSinceEpoch;
    handler.next(options);
  }

  String _duree(RequestOptions o) {
    final d = o.extra[_debut];
    return d is int ? ' (${DateTime.now().millisecondsSinceEpoch - d} ms)' : '';
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final o = response.requestOptions;
    _ecrire('HTTP ${o.method} ${cheminSansParametres(o.uri)} → ${response.statusCode}${_duree(o)}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final o = err.requestOptions;
    final s = err.response?.statusCode;
    _ecrire('HTTP ${o.method} ${cheminSansParametres(o.uri)} → ${s ?? err.type.name}${_duree(o)}');
    handler.next(err);
  }
}
