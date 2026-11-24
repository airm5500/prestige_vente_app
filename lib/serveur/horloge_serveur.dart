// lib/serveur/horloge_serveur.dart
// 5.5.0 — Transmission du serveur du 24/11/2026 (branche serveur plan/24112026) : HEURE DU SERVEUR FAUSSE.
//
// Quand l'heure du PC serveur est fausse, Prestige refuse TOUTE écriture (POST / PUT / DELETE / PATCH, sauf
// v1/user/auth, v1/user/auth-badge, v1/user/logout et v1/horloge/*) par HTTP 423
// `{"success":false, "horlogeBloquee":true, "msg":"Opération refusée : l'heure du serveur est fausse. …"}`, AVANT de
// rien exécuter. Les lectures (GET) restent permises. Ce n'est ni une panne réseau, ni une erreur inconnue, ni un
// serveur en panne :
//  - le `msg` du serveur est affiché TEL QUEL ([horlogeBloqueeDe]) ;
//  - aucune relance automatique de l'écriture refusée (pas de boucle) ;
//  - une opération mise en file (ventes / stock / pointages hors ligne, avec leur `X-Client-Ref`) RESTE dans la file,
//    jamais « à vérifier » ni « refusée » : elle repart après le déblocage (même clé, aucun doublon) ;
//  - aucun contournement n'est proposé : seul l'administrateur (ou la tâche Windows du serveur) remet l'heure.
// [HorlogeServeur] retient l'état « bloqué » (constaté par un 423, ou par `GET v1/horloge/public`) ; le déblocage
// (écriture de nouveau acceptée, ou `GET v1/horloge/public` = OK / REGULARISATION) prévient les files, qui proposent
// l'envoi comme au retour du serveur (rien n'est envoyé sans accord).
// Journal du terminal : la CATÉGORIE seulement (« horloge du serveur bloquée »), jamais le `msg` ni la requête.
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:prestige_vente_app/api/utilisateur_session.dart' show corpsJson;
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';

/// Code HTTP du refus « heure du serveur fausse ».
const int codeHorlogeBloquee = 423;

/// Texte affiché si le serveur n'a pas donné de `msg` (jamais de contournement proposé).
const String messageHorlogeParDefaut =
    'Opération refusée : l\'heure du serveur est fausse. Prévenez l\'administrateur de Prestige pour qu\'il la corrige.';

/// Motif écrit au journal du terminal pour ce refus (catégorie seulement, jamais le `msg` du serveur).
const String motifJournalHorloge = 'Heure du serveur fausse (HTTP 423 horlogeBloquee)';

/// Titre court (bandeaux, boîtes de dialogue).
const String titreHorlogeBloquee = 'Heure du serveur fausse';

/// Message du refus « heure du serveur fausse » (HTTP 423 `{horlogeBloquee:true, msg}`), null sinon.
String? horlogeBloqueeDe(int? statut, Object? corps) {
  if (statut != codeHorlogeBloquee) return null;
  Object? c = corps;
  if (c is List<int>) {
    try {
      c = utf8.decode(c, allowMalformed: true);
    } catch (_) {
      return null;
    }
  }
  final j = corpsJson(c);
  if (j == null || (j['horlogeBloquee'] != true && j['horlogeBloquee'] != 'true')) return null;
  final m = '${j['msg'] ?? j['message'] ?? ''}'.trim();
  return m.isEmpty ? messageHorlogeParDefaut : m;
}

/// Message du refus « heure du serveur fausse » d'une erreur Dio (réponse 423), null sinon.
String? horlogeBloqueeDeErreur(Object? e) =>
    e is DioException ? horlogeBloqueeDe(e.response?.statusCode, e.response?.data) : null;

/// Routes que le serveur laisse passer même horloge bloquée (une réponse réussie n'y prouve rien).
bool routeHorsBlocage(String chemin) {
  var p = chemin;
  final q = p.indexOf('?');
  if (q >= 0) p = p.substring(0, q);
  return p.endsWith('/user/auth') || p.endsWith('/user/auth-badge') || p.endsWith('/user/logout') || p.contains('/horloge/');
}

bool _ecriture(String methode) => const {'POST', 'PUT', 'DELETE', 'PATCH'}.contains(methode.toUpperCase());

/// État de `GET v1/horloge/public` (sans session).
enum EtatHorloge { ok, bloque, regularisation }

/// Réponse de `GET v1/horloge/public` : `{"etat": "OK"|"BLOQUE"|"REGULARISATION", "serveur": "24/11/2026 20:52"}`.
class HorlogePublique {
  final EtatHorloge etat;

  /// Heure du serveur telle qu'il la donne (« 24/11/2026 20:52 »), vide si absente.
  final String serveur;
  const HorlogePublique(this.etat, this.serveur);

  /// null : réponse inconnue (404 = serveur ancien, sans la route : rien à afficher).
  static HorlogePublique? depuis(int? statut, Object? corps) {
    if (statut != 200) return null;
    final j = corpsJson(corps is List<int> ? utf8.decode(corps, allowMalformed: true) : corps);
    if (j == null) return null;
    final e = switch ('${j['etat'] ?? ''}'.trim().toUpperCase()) {
      'OK' => EtatHorloge.ok,
      'BLOQUE' => EtatHorloge.bloque,
      'REGULARISATION' => EtatHorloge.regularisation,
      _ => null,
    };
    return e == null ? null : HorlogePublique(e, '${j['serveur'] ?? ''}'.trim());
  }

  /// Écritures refusées par le serveur.
  bool get bloque => etat == EtatHorloge.bloque;

  /// Texte du bandeau de l'écran de connexion (null : rien à afficher ; REGULARISATION : écritures permises).
  String? get texteBandeau => bloque
      ? 'L\'heure du serveur Prestige est fausse${serveur.isEmpty ? '' : ' (serveur : $serveur)'} : ventes, encaissements, '
          'pointages et réceptions sont refusés tant que l\'administrateur ne l\'a pas corrigée.'
      : null;
}

/// État « heure du serveur fausse » de l'application (une instance, remplaçable dans les tests).
class HorlogeServeur extends ChangeNotifier {
  HorlogeServeur({DateTime Function()? horloge}) : _horloge = horloge ?? DateTime.now;

  static HorlogeServeur instance = HorlogeServeur();

  final DateTime Function() _horloge;

  bool _bloquee = false;
  String? _message;
  DateTime? _depuis;

  /// Le serveur refuse les écritures (dernier constat).
  bool get bloquee => _bloquee;

  /// Dernier `msg` reçu du serveur (affichage seulement ; jamais journalisé).
  String get message => _message ?? messageHorlogeParDefaut;
  DateTime? get depuis => _depuis;

  /// Diagnostic (tests) : refus 423 reçus, passages à « bloqué » et déblocages.
  int refus = 0;
  int blocages = 0;
  int deblocages = 0;

  /// Un 423 `horlogeBloquee` vient d'être reçu.
  void signaler(String message) {
    refus++;
    _message = message;
    if (_bloquee) return;
    _bloquee = true;
    _depuis = _horloge();
    blocages++;
    _noter('Écritures refusées : heure du serveur fausse (horloge bloquée)', ResultatJournal.refus);
    notifyListeners();
  }

  /// Le serveur accepte de nouveau les écritures (écriture réussie, ou horloge/public = OK / REGULARISATION).
  void debloquer() {
    if (!_bloquee) return;
    _bloquee = false;
    _depuis = null;
    deblocages++;
    _noter('Heure du serveur corrigée : écritures de nouveau acceptées', ResultatJournal.info);
    notifyListeners();
  }

  /// Applique la réponse de `GET v1/horloge/public` (null : serveur ancien ou réponse inconnue → rien).
  void appliquer(HorlogePublique? h) {
    if (h == null) return;
    if (h.bloque) {
      if (_bloquee) return;
      _bloquee = true;
      _depuis = _horloge();
      blocages++;
      _noter('Heure du serveur fausse (horloge/public)', ResultatJournal.info);
      notifyListeners();
    } else {
      debloquer();
    }
  }

  /// `GET v1/horloge/public` sur [dio] (adresse `…/api/v1`), sans session ; null : 404 (serveur ancien), autre
  /// réponse, ou pas de réponse. Jamais d'exception.
  static Future<HorlogePublique?> lirePublique(Dio dio, {String? baseUrl}) async {
    try {
      final base = (baseUrl ?? dio.options.baseUrl).replaceAll(RegExp(r'/+$'), '');
      final r = await dio.get<dynamic>('$base/horloge/public',
          options: Options(validateStatus: (_) => true, sendTimeout: const Duration(seconds: 5), receiveTimeout: const Duration(seconds: 5)));
      return HorlogePublique.depuis(r.statusCode, r.data);
    } catch (_) {
      return null;
    }
  }

  /// Après un 423 : vérification légère (GET horloge/public) pour savoir si l'heure a été corrigée ; appelée par la
  /// surveillance du serveur (cadence existante de 30 s), jamais en boucle serrée. Aucune écriture n'est rejouée ici.
  Future<void> verifierSiBloquee(Dio dio, {String? baseUrl}) async {
    if (!_bloquee) return;
    appliquer(await lirePublique(dio, baseUrl: baseUrl));
  }

  void _noter(String action, ResultatJournal r) {
    try {
      JournalTerminal.instance.noter(type: TypeJournal.reseau, action: action, resultat: r, motif: motifJournalHorloge);
    } catch (_) {}
  }

  /// Tests : état initial.
  @visibleForTesting
  void reinitialiser() {
    _bloquee = false;
    _message = null;
    _depuis = null;
    refus = blocages = deblocages = 0;
  }
}

/// Observe les réponses (sans les modifier) : 423 `horlogeBloquee` → [HorlogeServeur.signaler] ; écriture acceptée
/// (2xx, hors routes jamais bloquées) → [HorlogeServeur.debloquer]. Posé sur chaque client par `avecDeploiement`.
class IntercepteurHorloge extends Interceptor {
  IntercepteurHorloge({HorlogeServeur Function()? etat}) : _etat = etat ?? (() => HorlogeServeur.instance);
  final HorlogeServeur Function() _etat;

  static Dio brancher(Dio d) {
    if (!d.interceptors.any((i) => i is IntercepteurHorloge)) d.interceptors.add(IntercepteurHorloge());
    return d;
  }

  void _observer(Response<dynamic>? r) {
    if (r == null) return;
    final m = horlogeBloqueeDe(r.statusCode, r.data);
    if (m != null) return _etat().signaler(m);
    final code = r.statusCode ?? 0;
    final o = r.requestOptions;
    if (code >= 200 && code < 300 && _ecriture(o.method) && !routeHorsBlocage(o.uri.path)) _etat().debloquer();
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    _observer(response);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _observer(err.response);
    handler.next(err);
  }
}
