// lib/support/support_centre.dart
// Centre de support : envoi des anomalies de l'app mobile à l'API EXISTANTE du serveur
// (POST /api/v1/support/events, session de l'app), au même format que l'application web.
//
// - Contexte joint (payloadJson) : application, version, terminal (T-XXXXXX + modèle), utilisateur (login),
//   écran, fil d'Ariane (15 dernières actions : navigation + appels API, sans paramètres).
// - Anti-tempête comme le web : 20 envois automatiques au plus par session, jamais deux fois la même paire
//   messageCourt|urlOuEcran ; en plus, 30 par heure au plus.
// - File locale : un envoi qui échoue (hors ligne, session absente, serveur ancien sans la route) est gardé
//   et renvoyé au retour en ligne / à la connexion. L'échec d'un envoi n'est JAMAIS lui-même signalé.
// - Serveur sans la route (404) : envoi automatique suspendu proprement (file conservée), noté au journal.
// - Réglage « Envoyer automatiquement les anomalies au centre de support » : activé par défaut (comme le
//   web), désactivable par l'administrateur. Les signalements manuels partent toujours.
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/support/support_event.dart';
import 'package:prestige_vente_app/support/support_file.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Réponse du serveur à un envoi.
enum SupportReponse {
  /// {success:true} : enregistré (traitement asynchrone côté serveur).
  ok,

  /// Refus définitif ({success:false} autre que la session) : non renvoyé.
  rejete,

  /// Session absente / expirée : gardé, renvoyé après la connexion.
  session,

  /// HTTP 404 : la version du serveur n'a pas le centre de support.
  routeAbsente,

  /// Serveur injoignable ou erreur 5xx : gardé, renvoyé plus tard.
  echec,
}

/// Issue d'un signalement (affichée à l'utilisateur pour un signalement manuel).
enum SupportIssue { envoye, enAttente, desactive, dejaSignale, limite, rejete }

typedef SupportEnvoi = Future<SupportReponse> Function(Map<String, Object?> corps);

/// Pièce jointe d'une demande de contact (≤ 10 Mo, limite du serveur).
class SupportPieceJointe {
  final String nom;
  final List<int> octets;
  const SupportPieceJointe(this.nom, this.octets);
  static const maxOctets = 10 * 1024 * 1024;
}

/// Demande de contact (POST /prestige/support-contact, multipart) : réponse et message du serveur.
typedef SupportContactEnvoi = Future<(SupportReponse, String)> Function({
  required String objet,
  required String message,
  required String moduleConcerne,
  required String urgence,
  List<SupportPieceJointe> pieces,
});

/// Lecture d'une réponse de POST /support/events (ou /support-contact).
SupportReponse lireReponseSupport(int status, Object? data) {
  if (status == 404) return SupportReponse.routeAbsente;
  if (status == 401 || status == 403) return SupportReponse.session;
  if (status >= 500 || status == 0) return SupportReponse.echec;
  if (status >= 400) return SupportReponse.rejete;
  final body = data is String ? _json(data) : data;
  if (body is Map) {
    if (body['success'] == true) return SupportReponse.ok;
    final msg = '${body['msg'] ?? body['message'] ?? ''}'.toLowerCase();
    if (msg.contains('connect') || msg.contains('session')) return SupportReponse.session;
    return SupportReponse.rejete;
  }
  // Page HTML (connexion) au lieu du JSON : session perdue.
  return SupportReponse.session;
}

Object? _json(String s) {
  final i = s.indexOf('{');
  final j = s.lastIndexOf('}');
  if (i < 0 || j <= i) return null;
  try {
    return jsonDecode(s.substring(i, j + 1));
  } catch (_) {
    return null;
  }
}

class SupportCentre extends ChangeNotifier {
  SupportCentre({SupportFileStore? file, DateTime Function()? clock, this.envoi, this.actif = true})
      : file = file ?? MemorySupportFileStore(),
        _clock = clock ?? DateTime.now;

  /// Instance de l'appli : INACTIVE par défaut (tests des autres modules inchangés) ; main() la remplace.
  static SupportCentre instance = SupportCentre(actif: false);

  /// Centre en service (faux : aucun signalement, aucun envoi, aucune ligne de journal).
  final bool actif;

  static const application = 'Prestige Mobile';

  /// Version de l'app (identique à pubspec.yaml, vérifiée par les tests).
  static const version = '1.2.0';

  static const maxAutoSession = 20;
  static const maxParHeure = 30;
  static const maxFile = 50;
  static const dureeFile = Duration(days: 7);
  static const maxEssais = 8;

  final SupportFileStore file;
  final DateTime Function() _clock;

  /// Envoi au serveur (null : pas encore relié, l'événement attend dans la file).
  SupportEnvoi? envoi;

  /// Demande de contact avec pièces jointes (null : pas encore relié).
  SupportContactEnvoi? contact;

  /// Réglage « Envoyer automatiquement les anomalies au centre de support ».
  bool envoiAuto = true;

  /// Le serveur a répondu 404 : pas de centre de support sur cette version (envoi automatique suspendu).
  bool routeAbsente = false;

  /// Le terminal est-il hors ligne ? (branché sur la surveillance du serveur).
  bool Function() horsLigne = () => false;

  /// Login de l'utilisateur connecté (le serveur le déduit de la session ; mis ici en contexte).
  String login = '';

  /// Écran affiché (nom du widget de la page).
  String ecran = '';

  final List<String> _fil = [];
  final Set<String> _vus = {};
  final List<DateTime> _envoisHeure = [];
  int _autoSession = 0;
  bool _renvoiEnCours = false;
  int _enAttente = 0;

  /// Nombre d'événements dans la file locale.
  int get enAttente => _enAttente;

  List<String> get filAriane => List.unmodifiable(_fil);

  // ---------------------------------------------------------------------------
  // Réglage
  // ---------------------------------------------------------------------------

  static const prefEnvoiAuto = 'support_envoi_auto';

  Future<void> chargerReglage() async {
    try {
      final p = await SharedPreferences.getInstance();
      envoiAuto = p.getBool(prefEnvoiAuto) ?? true;
    } catch (_) {}
    await _compter();
  }

  Future<void> reglerEnvoiAuto(bool v) async {
    envoiAuto = v;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(prefEnvoiAuto, v);
    } catch (_) {}
    _journal(v ? 'Envoi automatique des anomalies activé' : 'Envoi automatique des anomalies désactivé');
  }

  // ---------------------------------------------------------------------------
  // Fil d'Ariane (comme le web : « HH:mm:ss  action », 15 au plus, 200 caractères)
  // ---------------------------------------------------------------------------

  void noterAction(String action) {
    final a = action.trim();
    if (a.isEmpty) return;
    _fil.add(tronquer('${DateFormat('HH:mm:ss').format(_clock())}  $a', BornesSupport.actionFil));
    while (_fil.length > BornesSupport.filAriane) {
      _fil.removeAt(0);
    }
  }

  /// Appel API : « API GET /prestige/api/v1/vente/search » (jamais les paramètres).
  void noterApi(String methode, String url) => noterAction('API ${methode.toUpperCase()} ${SupportFiltre.chemin(url)}');

  void noterEcran(String nom) {
    if (nom.isEmpty) return;
    ecran = nom;
    noterAction('Écran $nom');
  }

  /// Nouvelle session (connexion) : compteurs anti-tempête remis à zéro, comme un rechargement de page web.
  void nouvelleSession(String login) {
    this.login = login;
    _vus.clear();
    _autoSession = 0;
  }

  // ---------------------------------------------------------------------------
  // Contexte
  // ---------------------------------------------------------------------------

  Map<String, Object?> contexteTechnique() {
    final j = JournalTerminal.instance;
    return {
      'application': application,
      'version': version,
      'terminal': {'id': j.terminalId, 'modele': j.terminalNom},
      'utilisateur': login,
      'ecran': ecran,
    };
  }

  Map<String, Object?> payload(SupportEvent e) => {
        ...e.donnees,
        if (e.contexte) ...contexteTechnique() else ...{'application': application, 'version': version},
        if (e.contexte) 'fil_ariane': List.of(_fil),
      };

  // ---------------------------------------------------------------------------
  // Signalement
  // ---------------------------------------------------------------------------

  /// Remonte [e] au centre de support (jamais d'exception : le support ne gêne jamais l'utilisateur).
  Future<SupportIssue> signaler(SupportEvent e) async {
    if (!actif) return SupportIssue.desactive;
    try {
      if (e.auto) {
        if (!envoiAuto) return SupportIssue.desactive;
        if (_vus.contains(e.cle)) return SupportIssue.dejaSignale;
        if (_autoSession >= maxAutoSession) return SupportIssue.limite;
        final now = _clock();
        _envoisHeure.removeWhere((d) => now.difference(d) > const Duration(hours: 1));
        if (_envoisHeure.length >= maxParHeure) return SupportIssue.limite;
        _vus.add(e.cle);
        _autoSession++;
        _envoisHeure.add(now);
      }
      final corps = corpsSupport(e, payload(e));
      final issue = await _envoyerOuGarder(corps);
      final quoi = e.auto ? 'Anomalie' : 'Signalement';
      _journal(issue == SupportIssue.envoye ? '$quoi transmis au centre de support' : '$quoi en attente d\'envoi au centre de support',
          motif: '${corps['niveau']} ${corps['module']} : ${corps['messageCourt']}');
      return issue;
    } catch (err) {
      debugPrint('Centre de support : $err');
      return SupportIssue.enAttente;
    }
  }

  Future<SupportIssue> _envoyerOuGarder(Map<String, Object?> corps) async {
    final f = envoi;
    if (f == null || routeAbsente || _safe(horsLigne)) {
      await _garder(corps);
      return SupportIssue.enAttente;
    }
    final r = await _appeler(f, corps);
    switch (r) {
      case SupportReponse.ok:
        return SupportIssue.envoye;
      case SupportReponse.rejete:
        return SupportIssue.rejete;
      case SupportReponse.routeAbsente:
        _marquerRouteAbsente();
        await _garder(corps);
        return SupportIssue.enAttente;
      case SupportReponse.session:
      case SupportReponse.echec:
        await _garder(corps);
        return SupportIssue.enAttente;
    }
  }

  static Future<SupportReponse> _appeler(SupportEnvoi f, Map<String, Object?> corps) async {
    try {
      return await f(corps);
    } catch (_) {
      return SupportReponse.echec;
    }
  }

  void _marquerRouteAbsente() {
    if (routeAbsente) return;
    routeAbsente = true;
    notifyListeners();
    _journal('Centre de support absent de ce serveur : envoi automatique suspendu (file conservée)');
  }

  /// Nouvelle adresse de serveur : la route est de nouveau essayée.
  void serveurChange() {
    if (!routeAbsente) return;
    routeAbsente = false;
    notifyListeners();
  }

  Future<void> _garder(Map<String, Object?> corps) async {
    final now = _clock();
    final l = (await file.lire()).where((e) => now.difference(e.at) <= dureeFile).toList();
    l.add(SupportEnAttente(id: '${now.microsecondsSinceEpoch}-${l.length}', at: now, corps: corps));
    while (l.length > maxFile) {
      l.removeAt(0);
    }
    await file.ecrire(l);
    _enAttente = l.length;
    notifyListeners();
  }

  Future<void> _compter() async {
    try {
      _enAttente = (await file.lire()).length;
      notifyListeners();
    } catch (_) {}
  }

  /// Renvoie la file (retour en ligne, connexion, bouton « Renvoyer »). [forcer] : essaie même si la route
  /// était absente (nouvelle tentative explicite). Renvoie le nombre d'événements transmis.
  Future<int> renvoyer({bool forcer = false}) async {
    final f = envoi;
    if (!actif || f == null || _renvoiEnCours || _safe(horsLigne)) return 0;
    if (routeAbsente && !forcer) return 0;
    _renvoiEnCours = true;
    var envoyes = 0;
    try {
      final now = _clock();
      var l = (await file.lire()).where((e) => now.difference(e.at) <= dureeFile).toList();
      if (l.isEmpty) {
        await file.ecrire(l);
        _enAttente = 0;
        return 0;
      }
      if (forcer) routeAbsente = false;
      final restants = <SupportEnAttente>[];
      var arret = false;
      for (final e in l) {
        if (arret) {
          restants.add(e);
          continue;
        }
        final r = await _appeler(f, e.corps);
        switch (r) {
          case SupportReponse.ok:
            envoyes++;
          case SupportReponse.rejete:
            break;
          case SupportReponse.routeAbsente:
            _marquerRouteAbsente();
            restants.add(e);
            arret = true;
          case SupportReponse.session:
          case SupportReponse.echec:
            final x = e.avecEssai();
            if (x.essais < maxEssais) restants.add(x);
            arret = true; // pas d'insistance : on réessaiera au prochain retour en ligne
        }
      }
      l = restants;
      await file.ecrire(l);
      _enAttente = l.length;
      if (envoyes > 0) _journal('$envoyes anomalie(s) en attente transmise(s) au centre de support');
      return envoyes;
    } catch (_) {
      return envoyes;
    } finally {
      _renvoiEnCours = false;
      notifyListeners();
    }
  }

  void _journal(String action, {String motif = ''}) {
    try {
      JournalTerminal.instance.noter(type: TypeJournal.support, action: action, resultat: ResultatJournal.info, motif: motif);
    } catch (_) {}
  }

  static bool _safe(bool Function() f) {
    try {
      return f();
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Raccourcis des anomalies connues
  // ---------------------------------------------------------------------------

  /// Anomalie de synchronisation hors ligne (rapport d'anomalies H2 / H3), format de VenteCtr.js :
  /// APPLICATION / WARN, payloadJson {vente | operation, issue, explication}.
  Future<SupportIssue> anomalieSynchro({
    required String module,
    required String quoi,
    required String nature,
    required String motif,
    String? vente,
    String? operation,
    List<String> masquer = const [],
  }) {
    var m = motif;
    for (final s in masquer) {
      if (s.trim().length >= 2) m = m.replaceAll(s.trim(), '***');
    }
    return signaler(SupportEvent(
      type: TypeSupport.application,
      niveau: NiveauSupport.warn,
      module: module,
      messageCourt: 'Synchronisation hors ligne : $quoi refusé(e) ($nature)',
      urlOuEcran: 'SYNCHRO ${module == 'VENTE' ? 'ventes hors ligne' : 'stock hors ligne'}',
      stack: 'Envoi de la file hors ligne refusé par le serveur. Motif : $m',
      donnees: {
        if (vente != null) 'vente': vente,
        if (operation != null) 'operation': operation,
        'issue': nature,
        'explication': 'Opération saisie hors ligne sur le terminal, refusée à l\'envoi au retour du serveur '
            '(rapport d\'anomalies du terminal). Motif du serveur : $m',
      },
    ));
  }
}

/// Envoi réel : Dio dédié (même session que l'app, aucun intercepteur de l'app : un échec n'est jamais
/// re-signalé ni compté comme une coupure), réponses non levées.
class DioSupportEnvoi {
  final String Function() baseUrl;
  Dio? _dio;
  DioSupportEnvoi(this.baseUrl);

  Dio get dio {
    final d = _dio ??= (Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      sendTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      validateStatus: (_) => true,
    ))
      ..interceptors.add(CookieManager(DioClient.cookieJar)));
    d.options.baseUrl = baseUrl();
    return d;
  }

  Future<SupportReponse> call(Map<String, Object?> corps) async {
    try {
      final r = await dio.post('/support/events',
          data: corps, options: Options(contentType: Headers.jsonContentType, extra: {SupportCles.ignorer: true}));
      return lireReponseSupport(r.statusCode ?? 0, r.data);
    } catch (_) {
      return SupportReponse.echec;
    }
  }
}

extension DioSupportContact on DioSupportEnvoi {
  /// Racine de l'application : « http://hôte:port/prestige » (l'API est sous /api/v1).
  String get racine => baseUrl().replaceFirst(RegExp(r'/api/v1/?$'), '');

  Future<(SupportReponse, String)> contacter({
    required String objet,
    required String message,
    required String moduleConcerne,
    required String urgence,
    List<SupportPieceJointe> pieces = const [],
  }) async {
    try {
      final form = FormData.fromMap({
        'objet': objet,
        'message': message,
        'moduleConcerne': moduleConcerne,
        'urgence': urgence,
      });
      // Champs du formulaire web (pieceJointe1, pieceJointe2) ; le serveur prend toute partie avec un nom de fichier.
      var n = 0;
      for (final p in pieces) {
        if (p.octets.isEmpty || p.octets.length > SupportPieceJointe.maxOctets) continue;
        form.files.add(MapEntry('pieceJointe${++n}', MultipartFile.fromBytes(p.octets, filename: p.nom)));
      }
      final r = await dio.post('$racine/support-contact',
          data: form, options: Options(responseType: ResponseType.plain, extra: {SupportCles.ignorer: true}));
      final code = lireReponseSupport(r.statusCode ?? 0, '${r.data ?? ''}');
      final body = _json('${r.data ?? ''}');
      final msg = body is Map ? '${body['msg'] ?? ''}' : '';
      return (code, msg);
    } catch (_) {
      return (SupportReponse.echec, '');
    }
  }
}

/// Clés partagées avec la capture (évite un import circulaire).
abstract final class SupportCles {
  /// Requête à ne jamais signaler (envois du support lui-même, sondages).
  static const ignorer = 'support_ignorer';
}
