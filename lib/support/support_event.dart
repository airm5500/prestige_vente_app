// lib/support/support_event.dart
// Centre de support : événement envoyé à POST /api/v1/support/events (API EXISTANTE du serveur, inchangée).
// Même format que l'application web (general/app.js, VenteCtr.js) pour être traité de la même façon :
// déduplication par signature (type|module|message|1ʳᵉ ligne de la pile|écran), tickets automatiques
// (FATAL, ou ERROR au-delà du seuil), e-mail. Bornes du serveur : messageCourt 500, urlOuEcran 255,
// stack 4000 (extrait gardé en base), payloadJson 4000 (chaîne JSON). Type ≤ 50, module ≤ 100.
//
// Aucune donnée sensible ne part : mots de passe, jetons, cookies, données patient / ordonnance
// (voir [SupportFiltre]).
import 'dart:convert';

/// Niveaux acceptés par le serveur (normalizeNiveau) : un autre texte y devient INFO.
abstract final class NiveauSupport {
  static const info = 'INFO';
  static const warn = 'WARN';
  static const error = 'ERROR';
  static const fatal = 'FATAL';
  static const tous = [info, warn, error, fatal];
}

/// Types utilisés (texte libre côté serveur, borné à 50).
abstract final class TypeSupport {
  /// Erreur Flutter non gérée (équivalent des erreurs « JS » du web).
  static const mobile = 'MOBILE';

  /// Échec HTTP inattendu : format « AJAX » du web.
  static const ajax = 'AJAX';

  /// Signalement métier / manuel : format « APPLICATION » du web (VenteCtr.signalerReponsePerdue).
  static const application = 'APPLICATION';
}

/// Bornes du serveur (SupportEventServiceImpl.buildEvent / extraitStack).
abstract final class BornesSupport {
  static const type = 50;
  static const module = 100;
  static const messageCourt = 500;
  static const urlOuEcran = 255;
  static const stack = 4000;
  static const payloadJson = 4000;
  static const filAriane = 15;
  static const actionFil = 200;
}

/// Coupe [s] à [n] caractères (sans casser une paire UTF-16).
String tronquer(String s, int n) {
  if (s.length <= n) return s;
  var fin = n;
  if (fin > 0 && s.codeUnitAt(fin - 1) >= 0xD800 && s.codeUnitAt(fin - 1) <= 0xDBFF) fin--;
  return s.substring(0, fin);
}

/// Filtre des données sensibles (mots de passe, jetons, cookies, patients, ordonnances).
abstract final class SupportFiltre {
  /// Clés JSON jamais transmises (comparaison sans casse, sur une partie du nom).
  static final RegExp clesSensibles = RegExp(
    r'pass|pwd|token|jeton|cookie|session|auth|secret|pin|'
    r'client|patient|assure|ayant|nom|prenom|name|firstname|lastname|fullname|'
    r'secu|matricule|naissance|birth|telephone|phone|mobile|adresse|address|mail|'
    r'ordonnance|prescription|prescripteur|medecin|bon|carte|badge|empreinte|fingerprint',
    caseSensitive: false,
  );

  /// Clés qu'on garde dans un corps de réponse d'erreur (message du serveur, code).
  static const clesReponse = {'success', 'msg', 'message', 'error', 'status', 'code', 'errors'};

  static final List<(RegExp, String)> _motifs = [
    // En-tête « Bearer xxx »
    (RegExp(r'Bearer\s+[A-Za-z0-9._\-]+', caseSensitive: false), 'Bearer ***'),
    // « password=xxx », « mot de passe : xxx », « token: xxx », « Cookie: JSESSIONID=… »
    (RegExp(r'(password|passwd|pwd|mot de passe|token|jeton|secret|authorization|cookie|set-cookie|jsessionid|code pin|pin)(\s*["]?\s*[:=]\s*["]?)([^\s",;&}]+)', caseSensitive: false), r'$1$2***'),
    // Adresse e-mail
    (RegExp(r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}'), '***@***'),
    // N° de sécurité sociale / téléphone
    // (9 à 15 chiffres, espaces / points permis) ; les identifiants techniques plus longs restent lisibles.
    (RegExp(r'(?<![A-Za-z0-9_\-])\+?\d(?:[ .]?\d){8,14}(?![A-Za-z0-9_\-])'), '###'),
  ];

  /// Texte libre nettoyé (balises HTML retirées, secrets masqués).
  static String texte(String s, {bool html = false}) {
    var t = s;
    if (html) {
      t = t.replaceAll(RegExp(r'<(script|style)[^>]*>.*?</\1>', caseSensitive: false, dotAll: true), ' ');
      t = t.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'[ \t]+'), ' ');
      t = t.replaceAll(RegExp(r'\n\s*\n+'), '\n').trim();
    }
    for (final (re, rep) in _motifs) {
      t = t.replaceAllMapped(re, (m) => _remplacer(rep, m));
    }
    return t;
  }

  static String _remplacer(String modele, Match m) =>
      modele.replaceAllMapped(RegExp(r'\$(\d)'), (g) => m.group(int.parse(g.group(1)!)) ?? '');

  /// URL sans hôte ni paramètres (une recherche peut porter un nom de patient).
  static String chemin(String url) {
    final u = Uri.tryParse(url);
    if (u == null) return tronquer(url.split('?').first, BornesSupport.urlOuEcran);
    final p = u.path.isEmpty ? '/' : u.path;
    return tronquer(p, BornesSupport.urlOuEcran);
  }

  /// Valeur JSON sans clé sensible (récursif, profondeur bornée).
  static Object? json(Object? v, {int profondeur = 0}) {
    if (profondeur > 6) return '…';
    if (v is Map) {
      return {
        for (final e in v.entries)
          if (!clesSensibles.hasMatch('${e.key}')) '${e.key}': json(e.value, profondeur: profondeur + 1),
      };
    }
    if (v is List) return [for (final x in v.take(20)) json(x, profondeur: profondeur + 1)];
    if (v is String) return texte(v);
    return v;
  }

  /// Corps d'une réponse d'erreur : JSON réduit au message du serveur ; HTML / texte nettoyé.
  static String? corpsReponse(Object? data) {
    if (data == null) return null;
    if (data is Map) {
      final garde = <String, Object?>{
        for (final e in data.entries)
          if (clesReponse.contains('${e.key}'.toLowerCase())) '${e.key}': json(e.value),
      };
      if (garde.isEmpty) return null;
      return tronquer(jsonEncode(garde), BornesSupport.stack);
    }
    if (data is List) return null;
    String s;
    if (data is List<int>) {
      try {
        s = utf8.decode(data, allowMalformed: true);
      } catch (_) {
        return null;
      }
    } else {
      s = '$data';
    }
    if (s.trim().isEmpty) return null;
    final t = s.trimLeft();
    if (t.startsWith('{')) {
      try {
        return corpsReponse(jsonDecode(t));
      } catch (_) {}
    }
    return tronquer(texte(s, html: t.startsWith('<') || s.contains('</')), BornesSupport.stack);
  }
}

/// Événement du centre de support (corps JSON de POST /support/events).
class SupportEvent {
  final String type;
  final String niveau;
  final String module;
  final String messageCourt;
  final String urlOuEcran;
  final String? stack;

  /// Données métier jointes (ex. {vente, issue, explication}) ; complétées du contexte à l'envoi.
  final Map<String, Object?> donnees;

  /// Envoi automatique (soumis au réglage et aux limites anti-tempête) ou signalement manuel.
  final bool auto;

  /// Joindre le contexte technique (application, version, terminal, utilisateur, écran, fil d'Ariane).
  final bool contexte;

  const SupportEvent({
    required this.type,
    required this.niveau,
    required this.module,
    required this.messageCourt,
    this.urlOuEcran = '',
    this.stack,
    this.donnees = const {},
    this.auto = true,
    this.contexte = true,
  });

  /// Clé anti-répétition du web : messageCourt|urlOuEcran.
  String get cle => '$messageCourt|$urlOuEcran';
}

/// Corps JSON envoyé (bornes du serveur, payloadJson TOUJOURS une chaîne JSON valide).
Map<String, Object?> corpsSupport(SupportEvent e, Map<String, Object?> payload) {
  final stack = e.stack == null ? null : SupportFiltre.texte(e.stack!);
  return {
    'type': tronquer(e.type, BornesSupport.type),
    'niveau': NiveauSupport.tous.contains(e.niveau) ? e.niveau : NiveauSupport.info,
    'module': tronquer(e.module, BornesSupport.module),
    'messageCourt': tronquer(SupportFiltre.texte(e.messageCourt).trim(), BornesSupport.messageCourt),
    'urlOuEcran': tronquer(e.urlOuEcran, BornesSupport.urlOuEcran),
    'stack': (stack == null || stack.trim().isEmpty) ? null : tronquer(stack, BornesSupport.stack),
    'payloadJson': payloadBorne(payload),
  };
}

/// Encode [payload] en ≤ 4000 caractères en restant du JSON valide : le fil d'Ariane est raccourci
/// (plus anciennes actions d'abord), puis les textes longs, en dernier recours un résumé.
String payloadBorne(Map<String, Object?> payload, {int max = BornesSupport.payloadJson}) {
  final p = Map<String, Object?>.from(payload);
  var s = jsonEncode(p);
  if (s.length <= max) return s;
  final fil = p['fil_ariane'];
  if (fil is List) {
    final l = List<Object?>.from(fil);
    while (l.isNotEmpty && s.length > max) {
      l.removeAt(0);
      p['fil_ariane'] = List<Object?>.from(l);
      s = jsonEncode(p);
    }
    if (s.length <= max) return s;
  }
  for (final k in p.keys.toList()) {
    final v = p[k];
    if (v is String && v.length > 300) {
      p[k] = '${tronquer(v, 300)}…';
      s = jsonEncode(p);
      if (s.length <= max) return s;
    }
  }
  final resume = <String, Object?>{
    for (final k in ['application', 'version', 'ecran', 'vente', 'operation', 'issue'])
      if (p[k] is String || p[k] is num) k: p[k] is String ? tronquer(p[k] as String, 300) : p[k],
    'tronque': true,
  };
  s = jsonEncode(resume);
  return s.length <= max ? s : jsonEncode({'tronque': true});
}
