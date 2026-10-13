// lib/serveur/json_tolerant.dart
// Lecture tolérante des réponses JSON de Prestige : champ absent, nul ou d'un type inattendu
// (nombre envoyé en texte, booléen en 0/1…) ne fait jamais planter l'écran.

/// Texte (vide si absent ou nul).
String txt(Object? v) => v == null ? '' : (v is String ? v : '$v').trim();

/// Texte, ou null si vide.
String? txtOuNull(Object? v) {
  final s = txt(v);
  return s.isEmpty || s == 'null' ? null : s;
}

/// Entier (null si absent ou illisible). « 12 », 12, 12.0, « 12,0 » → 12.
int? entier(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.isFinite ? v.round() : null;
  if (v is bool) return null;
  final s = '$v'.trim().replaceAll(',', '.');
  if (s.isEmpty) return null;
  return int.tryParse(s) ?? double.tryParse(s)?.round();
}

/// Entier, 0 par défaut.
int entier0(Object? v) => entier(v) ?? 0;

/// Décimal (null si absent ou illisible).
double? decimal(Object? v) {
  if (v == null || v is bool) return null;
  if (v is num) return v.isFinite ? v.toDouble() : null;
  final s = '$v'.trim().replaceAll(',', '.');
  if (s.isEmpty) return null;
  final d = double.tryParse(s);
  return d != null && d.isFinite ? d : null;
}

/// Booléen : true, « true », 1, « 1 », « O », « oui ».
bool booleen(Object? v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = txt(v).toLowerCase();
  return s == 'true' || s == '1' || s == 'o' || s == 'oui' || s == 'y' || s == 'yes';
}

/// Objet JSON (vide si autre chose).
Map<String, dynamic> objet(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// Liste d'objets JSON (les éléments qui ne sont pas des objets sont ignorés).
List<Map<String, dynamic>> objets(Object? v) =>
    v is List ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)] : const <Map<String, dynamic>>[];

/// Liste de textes (les valeurs vides sont ignorées).
List<String> textes(Object? v) => v is List ? [for (final e in v) if (txt(e).isNotEmpty) txt(e)] : const <String>[];
