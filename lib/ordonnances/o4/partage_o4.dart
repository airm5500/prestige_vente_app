// lib/ordonnances/o4/partage_o4.dart
// Étape O4 : partage des apprentissages entre terminaux via le serveur (patch docs/serveur/O4_corrections_ordonnances.patch).
//
// Serveur avec le patch : GET /app-vente/capacites (repli : ancien /mobile/capacites, préfixe détecté par
// routes_app_vente.dart et utilisé pour les routes suivantes) → `ordonnanceCorrections: true`, puis
//  - POST /app-vente/ordonnances/corrections {corrections:[{cle, segment, produitId, cip, nom, at}]} : envoi par lot,
//    idempotent (la clé `cle` est générée ici, un renvoi ne crée rien de plus) ;
//  - GET /app-vente/ordonnances/corrections?depuis=&jusqua=&start=&limit= : validations des autres terminaux, en
//    différentiel avec l'horloge du SERVEUR (comme H5 : curseur = serveurMaintenant, chevauchement 2 min, clés déjà
//    appliquées ignorées).
// Seul le SEGMENT médicament est envoyé (jamais le texte lu complet ni donnée patient).
// Sans la capacité, ou partage désactivé dans les Réglages : apprentissage sur l'appareil seulement, rien n'est
// envoyé ni demandé. Hors ligne : les validations attendent dans une file et partent au retour du serveur, sans
// confirmation (ce ne sont pas des opérations de stock ou de caisse) ; envoi / attente notés dans le journal du
// terminal (résultat « info »).
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/horsligne/catalogue_delta.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/horsligne/routes_app_vente.dart';
import 'package:prestige_vente_app/ordonnances/o4/apprentissage_o4.dart';
import 'package:prestige_vente_app/ordonnances/o4/segment_medicament.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Une validation à partager.
class CorrectionO4 {
  final String cle;
  final String segment;
  final String produitId;
  final String cip;
  final String nom;
  final DateTime at;
  const CorrectionO4({required this.cle, required this.segment, required this.produitId, this.cip = '', this.nom = '', required this.at});

  Map<String, dynamic> toJson() => {
        'cle': cle,
        'segment': segment,
        'produitId': produitId,
        if (cip.isNotEmpty) 'cip': cip,
        if (nom.isNotEmpty) 'nom': nom.length > 100 ? nom.substring(0, 100) : nom,
        'at': CatalogueDelta.ecrireHeure(at),
      };

  static CorrectionO4? fromJson(Object? j) {
    if (j is! Map) return null;
    final cle = '${j['cle'] ?? ''}', s = '${j['segment'] ?? ''}', p = '${j['produitId'] ?? ''}';
    if (cle.isEmpty || s.isEmpty || p.isEmpty) return null;
    String t(Object? v) => v == null ? '' : '$v';
    return CorrectionO4(
      cle: cle,
      segment: s,
      produitId: p,
      cip: t(j['cip']),
      nom: t(j['nom']),
      at: CatalogueDelta.lireHeure(t(j['at'])) ?? DateTime.now(),
    );
  }
}

/// Accès au serveur (Dio en production, faux serveur dans les tests). Une panne réseau lève une exception.
abstract class ServeurCorrections {
  /// Adresse du serveur (le curseur et la capacité sont liés à elle).
  String get adresse;
  Future<({int status, Object? body})> capacites();
  Future<({int status, Object? body})> envoyer(List<Map<String, dynamic>> lot);
  Future<({int status, Object? body})> changements(Map<String, dynamic> query);
}

/// Session habituelle de l'application (cookies), comme H4 / H5.
class DioServeurCorrections implements ServeurCorrections {
  final ApiService api;
  Dio? _dio;
  DioServeurCorrections(this.api);

  @override
  String get adresse => api.dio.options.baseUrl;

  Dio get _d {
    final d = _dio ??= Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      validateStatus: (_) => true,
    ))
      ..interceptors.add(CookieManager(DioClient.cookieJar));
    d.options.baseUrl = adresse;
    return d;
  }

  @override
  Future<({int status, Object? body})> capacites() async {
    // /app-vente/capacites, repli sur l'ancien /mobile/capacites (voir routes_app_vente.dart).
    final r = await RoutesAppVente.lireCapacites(adresse, (chemin) async {
      final x = await _d.get(chemin);
      return (status: x.statusCode ?? 0, body: x.data);
    });
    return (status: r.status, body: r.body);
  }

  @override
  Future<({int status, Object? body})> envoyer(List<Map<String, dynamic>> lot) async {
    final r = await _d.post(PartageO4.routePour(adresse), data: {'corrections': lot});
    return (status: r.statusCode ?? 0, body: r.data);
  }

  @override
  Future<({int status, Object? body})> changements(Map<String, dynamic> query) async {
    final r = await _d.get(PartageO4.routePour(adresse), queryParameters: query);
    return (status: r.statusCode ?? 0, body: r.data);
  }
}

/// Bilan d'une synchronisation (tests, écran de gestion).
class BilanPartage {
  final int envoyees;
  final int recues;
  final String? erreur;
  const BilanPartage({this.envoyees = 0, this.recues = 0, this.erreur});
}

class PartageO4 {
  /// Route des corrections (préfixe actuel `/app-vente` ; [routePour] : préfixe détecté pour un serveur).
  static const String route = '${RoutesAppVente.prefixe}/ordonnances/corrections';
  static String routePour(String serveur) => RoutesAppVente.ordonnancesCorrections(RoutesAppVente.prefixePour(serveur));
  static const int lot = 200;
  static const int page = 500;
  static const int clesMax = 5000;

  static const _kChoix = 'ordonnance_o4_partage_v1';
  static const _kFile = 'ordonnance_o4_file_v1';
  static const _kCurseur = 'ordonnance_o4_curseur_v1';
  static const _kCles = 'ordonnance_o4_cles_v1';
  static const _kTerminal = 'ordonnance_o4_terminal_v1';

  /// Instance de l'appli (remplaçable dans les tests).
  static PartageO4 instance = PartageO4();

  PartageO4({this.serveur, bool Function()? enLigne, Future<ApprentissagesO4> Function()? apprentissages, DateTime Function()? horloge})
      : enLigne = enLigne ?? (() => true),
        apprentissages = apprentissages ?? ApprentissagesO4.charger,
        horloge = horloge ?? DateTime.now;

  ServeurCorrections? serveur;
  bool Function() enLigne;
  Future<ApprentissagesO4> Function() apprentissages;
  DateTime Function() horloge;

  /// Choix de l'utilisateur (Réglages) ; null : par défaut = activé si le serveur a la capacité.
  final ValueNotifier<bool?> choix = ValueNotifier<bool?>(null);

  /// Capacité connue du serveur courant (null : pas encore vérifiée / indéterminée).
  final ValueNotifier<bool?> capacite = ValueNotifier<bool?>(null);

  /// Validations en attente d'envoi.
  final ValueNotifier<int> enAttente = ValueNotifier<int>(0);

  ({String serveur, bool ok, DateTime at})? _cache;
  bool _charge = false;
  String _terminal = '';
  List<CorrectionO4> _file = [];
  Future<BilanPartage>? _encours;

  /// Partage effectif : choix de l'utilisateur, sinon capacité du serveur.
  bool get actif => choix.value ?? (capacite.value == true);

  /// Branche le partage sur l'application (session courante).
  void brancher(ApiService api, {required bool Function() enLigne}) {
    if (serveur == null || serveur is DioServeurCorrections) serveur = DioServeurCorrections(api);
    this.enLigne = enLigne;
  }

  Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  Future<void> charger() async {
    if (_charge) return;
    _charge = true;
    final p = await _prefs();
    if (p == null) return;
    choix.value = p.getBool(_kChoix);
    _terminal = p.getString(_kTerminal) ?? '';
    if (_terminal.isEmpty) {
      final r = Random.secure();
      _terminal = List.generate(10, (_) => 'abcdefghijkmnpqrstuvwxyz23456789'[r.nextInt(32)]).join();
      await p.setString(_kTerminal, _terminal);
    }
    try {
      _file = (jsonDecode(p.getString(_kFile) ?? '[]') as List).map(CorrectionO4.fromJson).whereType<CorrectionO4>().toList();
    } catch (_) {
      _file = [];
    }
    enAttente.value = _file.length;
  }

  /// Préfixe des clés de ce terminal (ses propres validations, renvoyées par le serveur, sont ignorées).
  String get prefixe => 'O4-$_terminal-';

  Future<void> _sauverFile() async {
    enAttente.value = _file.length;
    await (await _prefs())?.setString(_kFile, jsonEncode([for (final c in _file) c.toJson()]));
  }

  /// Réglages : partager ou non. Désactivé : la file est vidée, plus rien n'est envoyé ni reçu.
  Future<void> definirPartage(bool v) async {
    await charger();
    choix.value = v;
    await (await _prefs())?.setBool(_kChoix, v);
    if (!v) {
      _file = [];
      await _sauverFile();
    } else {
      unawaited(synchroniser());
    }
  }

  /// Le pharmacien a validé [produitId] pour une ligne lue [texteLu] (écran Ordonnance) : apprentissage local,
  /// puis mise en file pour les autres terminaux (si le partage n'est pas désactivé et que le serveur ne l'a pas
  /// refusé). Renvoie le segment appris, ou null si la ligne n'est pas apprenable (filtrage).
  Future<String?> enregistrerValidation({required String texteLu, required String produitId, String cip = '', String nom = ''}) async {
    final segment = SegmentMedicament.extraire(texteLu);
    if (segment == null || produitId.isEmpty) return null;
    final a = await apprentissages();
    final at = horloge();
    await a.apprendre(segment: segment, produitId: produitId, cip: cip, nom: nom, at: at);
    await charger();
    if (choix.value != false && capacite.value != false) {
      final r = Random();
      _file.add(CorrectionO4(
        cle: '$prefixe${at.millisecondsSinceEpoch.toRadixString(36)}-${r.nextInt(1 << 30).toRadixString(36)}',
        segment: segment,
        produitId: produitId,
        cip: cip,
        nom: nom,
        at: at,
      ));
      await _sauverFile();
    }
    return segment;
  }

  /// GET …/capacites → `ordonnanceCorrections` (oui gardé 30 min, non 5 min, indéterminé jamais gardé).
  static bool? capaciteDepuisReponse(int status, Object? body) {
    if (status == 200 && body is Map) return body['ordonnanceCorrections'] == true;
    if (status == 404) return false;
    if (status == 401 && body is Map && body.containsKey('expire')) return false;
    return null;
  }

  Future<bool?> verifierCapacite() async {
    final s = serveur;
    if (s == null) return null;
    final c = _cache;
    final now = horloge();
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

  /// Oublie la capacité mémorisée (changement de serveur, tests).
  void oublierCapacite() {
    _cache = null;
    capacite.value = null;
  }

  /// Envoie la file puis reçoit les validations des autres terminaux (une seule synchronisation à la fois).
  Future<BilanPartage> synchroniser() => _encours ??= _synchroniser().whenComplete(() => _encours = null);

  Future<BilanPartage> _synchroniser() async {
    final s = serveur;
    if (s == null || !_safe(enLigne)) return const BilanPartage();
    await charger();
    if (choix.value == false) return const BilanPartage();
    final cap = await verifierCapacite();
    if (cap != true) {
      if (cap == false && _file.isNotEmpty) {
        // Serveur sans le patch : apprentissage local seulement.
        _file = [];
        await _sauverFile();
      }
      return const BilanPartage();
    }
    if (!actif) return const BilanPartage();
    var envoyees = 0;
    String? erreur;
    while (_file.isNotEmpty) {
      final paquet = _file.take(lot).toList();
      try {
        final r = await s.envoyer([for (final c in paquet) c.toJson()]);
        final b = r.body;
        if (r.status != 200 || b is! Map || b['success'] != true) {
          erreur = 'code ${r.status}';
          break;
        }
        final cles = {for (final c in paquet) c.cle};
        _file.removeWhere((c) => cles.contains(c.cle));
        await _sauverFile();
        envoyees += paquet.length;
        final deja = b['dejaConnus'] is num ? (b['dejaConnus'] as num).toInt() : 0;
        final rejetes = b['rejetes'] is List ? (b['rejetes'] as List).length : 0;
        _journal('Apprentissages ordonnances partagés',
            '${paquet.length} validation(s) envoyée(s)${deja > 0 ? ', $deja déjà connue(s)' : ''}${rejetes > 0 ? ', $rejetes refusée(s)' : ''}');
      } catch (e) {
        erreur = 'serveur injoignable';
        break;
      }
    }
    if (erreur != null) {
      _journal('Apprentissages ordonnances en attente', '${_file.length} validation(s) à envoyer ($erreur) : nouvel essai au retour du serveur');
      return BilanPartage(envoyees: envoyees, erreur: erreur);
    }
    final (recues, err2) = await _recevoir(s);
    return BilanPartage(envoyees: envoyees, recues: recues, erreur: err2);
  }

  Future<(int, String?)> _recevoir(ServeurCorrections s) async {
    final p = await _prefs();
    if (p == null) return (0, null);
    String? curseur;
    try {
      final c = jsonDecode(p.getString(_kCurseur) ?? '{}');
      if (c is Map && c['serveur'] == s.adresse && CatalogueDelta.lireHeure('${c['curseur']}') != null) curseur = '${c['curseur']}';
    } catch (_) {}
    final cles = <String>[];
    try {
      cles.addAll((jsonDecode(p.getString(_kCles) ?? '[]') as List).map((e) => '$e'));
    } catch (_) {}
    final connues = cles.toSet();
    final a = await apprentissages();
    String? jusqua;
    var start = 0;
    var recues = 0;
    try {
      while (true) {
        final r = await s.changements({
          if (curseur != null) 'depuis': CatalogueDelta.depuis(curseur),
          if (jusqua != null) 'jusqua': jusqua,
          'start': start,
          'limit': page,
        });
        final b = r.body;
        if (r.status != 200 || b is! Map || b['success'] != true || b['data'] is! List) return (recues, 'code ${r.status}');
        final t = '${b['serveurMaintenant'] ?? ''}';
        if (CatalogueDelta.lireHeure(t) == null) return (recues, 'réponse inattendue');
        jusqua ??= t;
        final data = b['data'] as List;
        for (final e in data) {
          final c = CorrectionO4.fromJson(e);
          if (c == null || c.cle.startsWith(prefixe) || connues.contains(c.cle)) continue;
          if (c.segment.length > 60) continue;
          connues.add(c.cle);
          cles.add(c.cle);
          await a.apprendre(segment: c.segment, produitId: c.produitId, cip: c.cip, nom: c.nom, at: c.at, partagee: true);
          recues++;
        }
        start += data.length;
        final total = b['total'] is num ? (b['total'] as num).toInt() : null;
        if (data.length < page || data.isEmpty || (total != null && start >= total)) break;
      }
    } catch (_) {
      return (recues, 'serveur injoignable');
    }
    if (cles.length > clesMax) cles.removeRange(0, cles.length - clesMax);
    await p.setString(_kCles, jsonEncode(cles));
    await p.setString(_kCurseur, jsonEncode({'serveur': s.adresse, 'curseur': jusqua}));
    if (recues > 0) _journal('Apprentissages ordonnances reçus', '$recues validation(s) d\'autres terminaux');
    return (recues, null);
  }

  void _journal(String action, String motif) {
    try {
      JournalTerminal.instance.noter(type: TypeJournal.ordonnance, action: action, resultat: ResultatJournal.info, motif: motif);
    } catch (_) {}
  }

  static bool _safe(bool Function() f) {
    try {
      return f();
    } catch (_) {
      return false;
    }
  }

  /// Oublie tout l'état (tests).
  @visibleForTesting
  void reinitialiser() {
    _charge = false;
    _file = [];
    _cache = null;
    _encours = null;
    choix.value = null;
    capacite.value = null;
    enAttente.value = 0;
  }
}
