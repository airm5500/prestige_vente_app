// lib/ordonnances/o5/lecture_avancee.dart
// Étape O5 : « lecture avancée » en ligne, avec consentement (patch serveur docs/serveur/O5_lecture_avancee.patch).
//
// L'appli n'a AUCUNE clé : elle envoie l'image (zone des médicaments recadrée et masquée, sans métadonnées, voir
// masquage_o5.dart) au SERVEUR PRESTIGE, POST /mobile/ordonnances/lecture-avancee ; le serveur appelle le fournisseur
// (Claude par défaut, Google Cloud Vision possible) avec sa clé, n'enregistre pas l'image et renvoie seulement les
// lignes de médicaments {nom, dosage, forme, posologie, quantite, confiance}. Ces lignes passent ensuite par le
// découpage et la correspondance catalogue O3 / O4 comme une lecture ML Kit ; rien n'entre au panier sans validation.
//
// - Désactivée par défaut ; activation dans Réglages › Ventes (code administrateur) avec écran de consentement.
// - Disponible seulement si le serveur annonce `lectureAvancee: true` (GET /mobile/capacites) et en ligne.
// - Une seule lecture à la fois, délai maximal, aucune relance automatique ; journal du terminal (type « Lecture
//   avancée », résultat Info) : date, utilisateur, taille, résultat — jamais l'image ni le texte.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Une ligne de médicament lue par le service.
class LigneAvancee {
  final String nom, dosage, forme, posologie, quantite;
  final double confiance;
  const LigneAvancee({required this.nom, this.dosage = '', this.forme = '', this.posologie = '', this.quantite = '', this.confiance = 0.5});

  static LigneAvancee? fromJson(Object? j) {
    if (j is! Map) return null;
    String s(String k) => '${j[k] ?? ''}'.trim();
    final nom = s('nom');
    if (nom.length < 2) return null;
    final c = j['confiance'];
    return LigneAvancee(
      nom: nom,
      dosage: s('dosage'),
      forme: s('forme'),
      posologie: s('posologie'),
      quantite: s('quantite'),
      confiance: c is num ? c.toDouble().clamp(0.0, 1.0) : 0.5,
    );
  }

  /// Ligne « médicament » pour le découpage O2 : « 1. Curam 1 g cp  02 bte ».
  String ligneProduit(int numero) {
    final q = int.tryParse(RegExp(r'\d+').firstMatch(quantite)?.group(0) ?? '');
    return [
      '$numero. $nom',
      if (dosage.isNotEmpty) dosage,
      if (forme.isNotEmpty) forme,
      if (q != null && q > 0) ' ${q.toString().padLeft(2, '0')} bte',
    ].join(' ');
  }
}

/// Résultat d'une lecture avancée.
class ResultatLectureAvancee {
  final List<LigneAvancee> lignes;
  final String? erreur;
  final double? coutEstime;
  final int? quotaRestant;
  const ResultatLectureAvancee({this.lignes = const [], this.erreur, this.coutEstime, this.quotaRestant});

  bool get ok => erreur == null;

  /// Lignes de texte pour le découpage O2 / la correspondance O3 : produit numéroté, puis sa posologie.
  List<String> get texte => [
        for (var i = 0; i < lignes.length; i++) ...[
          lignes[i].ligneProduit(i + 1),
          if (lignes[i].posologie.isNotEmpty) lignes[i].posologie,
        ],
      ];
}

/// Accès au serveur (Dio en production, faux serveur dans les tests). Panne réseau : exception.
abstract class ServeurLectureAvancee {
  String get adresse;
  Future<({int status, Object? body})> capacites();
  Future<({int status, Object? body})> lire(Uint8List jpeg);
}

class DioServeurLectureAvancee implements ServeurLectureAvancee {
  final ApiService api;
  Dio? _dio;
  DioServeurLectureAvancee(this.api);

  @override
  String get adresse => api.dio.options.baseUrl;

  Dio get _d {
    final d = _dio ??= Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 30),
      // Délai du serveur (30 s par défaut) + marge ; aucune relance automatique.
      receiveTimeout: const Duration(seconds: 45),
      validateStatus: (_) => true,
    ))
      ..interceptors.add(CookieManager(DioClient.cookieJar));
    d.options.baseUrl = adresse;
    return d;
  }

  @override
  Future<({int status, Object? body})> capacites() async {
    final r = await _d.get('/mobile/capacites');
    return (status: r.statusCode ?? 0, body: r.data);
  }

  @override
  Future<({int status, Object? body})> lire(Uint8List jpeg) async {
    final r = await _d.post(LectureAvancee.route,
        data: Stream.fromIterable([jpeg]),
        options: Options(contentType: 'image/jpeg', headers: {Headers.contentLengthHeader: jpeg.length}));
    return (status: r.statusCode ?? 0, body: r.data);
  }
}

class LectureAvancee {
  static const String route = '/mobile/ordonnances/lecture-avancee';
  static const _kActive = 'ordonnance_o5_lecture_avancee_v1';
  static const _kConsentement = 'ordonnance_o5_consentement_v1';

  /// Instance de l'appli (remplaçable dans les tests).
  static LectureAvancee instance = LectureAvancee();

  LectureAvancee({this.serveur, bool Function()? enLigne, DateTime Function()? horloge})
      : enLigne = enLigne ?? (() => true),
        horloge = horloge ?? DateTime.now;

  ServeurLectureAvancee? serveur;
  bool Function() enLigne;
  DateTime Function() horloge;

  /// Lecture avancée activée (consentement donné). Désactivée par défaut.
  final ValueNotifier<bool> active = ValueNotifier<bool>(false);

  /// Capacité du serveur courant (null : inconnue).
  final ValueNotifier<bool?> capacite = ValueNotifier<bool?>(null);

  /// Lecture en cours (une seule à la fois).
  final ValueNotifier<bool> enCours = ValueNotifier<bool>(false);

  DateTime? consentementLe;
  ({String serveur, bool ok, DateTime at})? _cache;

  void brancher(ApiService api, {required bool Function() enLigne}) {
    if (serveur == null || serveur is DioServeurLectureAvancee) serveur = DioServeurLectureAvancee(api);
    this.enLigne = enLigne;
  }

  Future<void> charger() async {
    try {
      final p = await SharedPreferences.getInstance();
      active.value = p.getBool(_kActive) ?? false;
      consentementLe = DateTime.tryParse(p.getString(_kConsentement) ?? '');
    } catch (_) {}
  }

  /// Activation APRÈS l'écran de consentement (date gardée) ; désactivation à tout moment.
  Future<void> definir(bool v) async {
    active.value = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kActive, v);
      if (v) {
        consentementLe = horloge();
        await p.setString(_kConsentement, consentementLe!.toIso8601String());
      }
    } catch (_) {}
    JournalTerminal.instance.noter(
      type: TypeJournal.lectureAvancee,
      action: v ? 'Lecture avancée activée (consentement donné)' : 'Lecture avancée désactivée',
      resultat: ResultatJournal.info,
    );
  }

  /// GET /mobile/capacites → `lectureAvancee` (oui gardé 30 min, non 5 min, indéterminé jamais gardé).
  static bool? capaciteDepuisReponse(int status, Object? body) {
    if (status == 200 && body is Map) return body['lectureAvancee'] == true;
    if (status == 404) return false;
    if (status == 401 && body is Map && body.containsKey('expire')) return false;
    return null;
  }

  Future<bool?> verifierCapacite() async {
    final s = serveur;
    if (s == null) return null;
    final c = _cache, now = horloge();
    if (c != null && c.serveur == s.adresse && now.difference(c.at) < (c.ok ? const Duration(minutes: 30) : const Duration(minutes: 5))) {
      capacite.value = c.ok;
      return c.ok;
    }
    bool? r;
    try {
      final rep = await s.capacites();
      r = capaciteDepuisReponse(rep.status, rep.body);
    } catch (_) {
      r = null;
    }
    if (r != null) {
      _cache = (serveur: s.adresse, ok: r, at: now);
      capacite.value = r;
    }
    return r;
  }

  /// Le bouton est montré : consentement donné et serveur compatible (même hors ligne, alors désactivé).
  bool get proposee => active.value && capacite.value == true;

  /// Utilisable maintenant : proposée et en ligne.
  bool get utilisable => proposee && _safe(enLigne);

  static bool _safe(bool Function() f) {
    try {
      return f();
    } catch (_) {
      return false;
    }
  }

  static String _taille(int octets) => '${(octets / 1024).toStringAsFixed(0)} Ko';

  /// Envoie l'image (déjà recadrée, masquée et confirmée par l'utilisateur). Jamais deux à la fois, jamais relancée.
  Future<ResultatLectureAvancee> lire(Uint8List jpeg, {String origine = 'écran Ordonnance'}) async {
    final s = serveur;
    if (!active.value) return const ResultatLectureAvancee(erreur: 'Lecture avancée désactivée (Réglages).');
    if (s == null || capacite.value != true) return const ResultatLectureAvancee(erreur: 'Le serveur ne propose pas la lecture avancée.');
    if (!_safe(enLigne)) return const ResultatLectureAvancee(erreur: 'Disponible en ligne uniquement.');
    if (enCours.value) return const ResultatLectureAvancee(erreur: 'Une lecture avancée est déjà en cours.');
    enCours.value = true;
    ResultatLectureAvancee res;
    try {
      final r = await s.lire(jpeg);
      final b = r.body;
      if (r.status == 200 && b is Map && b['success'] == true && b['lignes'] is List) {
        res = ResultatLectureAvancee(
          lignes: (b['lignes'] as List).map(LigneAvancee.fromJson).whereType<LigneAvancee>().toList(),
          coutEstime: b['coutEstime'] is num ? (b['coutEstime'] as num).toDouble() : null,
          quotaRestant: b['quotaRestant'] is num ? (b['quotaRestant'] as num).toInt() : null,
        );
      } else {
        final msg = b is Map && b['msg'] != null ? '${b['msg']}' : null;
        res = ResultatLectureAvancee(
          erreur: switch (r.status) {
            401 || 403 => 'Session expirée : reconnectez-vous.',
            404 => 'Le serveur ne propose pas la lecture avancée.',
            _ => msg ?? 'Lecture avancée impossible (code ${r.status}).',
          },
        );
        if (r.status == 404 || r.status == 503) {
          _cache = null;
          capacite.value = r.status == 404 ? false : null;
        }
      }
    } on DioException catch (e) {
      res = ResultatLectureAvancee(
          erreur: e.type == DioExceptionType.receiveTimeout ? 'Le service de lecture met trop de temps à répondre.' : 'Serveur injoignable.');
    } catch (e) {
      res = const ResultatLectureAvancee(erreur: 'Lecture avancée impossible.');
    } finally {
      enCours.value = false;
    }
    final cout = res.coutEstime == null ? '' : ', coût estimé ${res.coutEstime!.toStringAsFixed(4)} \$';
    JournalTerminal.instance.noter(
      type: TypeJournal.lectureAvancee,
      action: 'Lecture avancée ($origine)',
      resultat: ResultatJournal.info,
      motif: res.ok
          ? 'image ${_taille(jpeg.length)}, ${res.lignes.length} médicament(s) lu(s)$cout'
          : 'image ${_taille(jpeg.length)}, échec : ${res.erreur}',
    );
    return res;
  }

  /// Oublie l'état (tests).
  @visibleForTesting
  void reinitialiser() {
    active.value = false;
    capacite.value = null;
    enCours.value = false;
    consentementLe = null;
    _cache = null;
  }
}
