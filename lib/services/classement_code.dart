// lib/services/classement_code.dart
// Classement des résultats d'une recherche par DÉBUT DE CODE (4.0.3, F3).
//
// Le serveur Prestige cherche « commence par » (LIKE 'saisie%') à la fois sur le NOM, le CIP et l'EAN fabricant
// (et en « Contient » : '%saisie' n'importe où), puis renvoie les produits triés par NOM (même tri que sa copie
// hors ligne, lib/horsligne/local_store.dart : ORDER BY nom). Pour une saisie en chiffres, le produit dont le CIP
// commence par ces chiffres arrive donc à la place alphabétique de son nom, derrière les produits dont le nom
// commence par ces chiffres ou dont l'EAN fabricant les contient — et tous les EAN-13 / CIP13 français commencent
// par « 34009 » : « 3400… » ramène presque tout le catalogue, et le bon produit peut même être sur une page
// suivante. De même, GET /info?search=<CIP> renvoie aussi les produits dont le CIP commence par ce CIP
// (« 8423349D » pour « 8423349 ») : prendre la PREMIÈRE ligne pouvait afficher un autre produit.
//
// Règle (saisie numérique seulement ; un texte n'est jamais réordonné) :
//   0. un code du produit est EXACTEMENT la saisie ;
//   1. son CIP (tel que renvoyé) commence par la saisie ;
//   2. un autre de ses codes commence par la saisie : CIP13 calculé d'un CIP7 (34009 + CIP7 + clé), CIP7 d'un
//      CIP13 34009…, EAN fabricant ;
//   3. le reste.
// À rang égal, l'ordre du serveur est conservé (classement stable).

final RegExp _chiffres = RegExp(r'^\d+$');
final RegExp _espaces = RegExp(r'\s');

/// Saisie en chiffres seuls (espaces ignorés), ou '' si la saisie contient autre chose (nom, joker, DataMatrix…).
String saisieNumerique(String saisie) {
  final d = saisie.replaceAll(_espaces, '');
  return _chiffres.hasMatch(d) ? d : '';
}

/// Clé de contrôle EAN-13 des 12 premiers chiffres [douze].
String cleEan13(String douze) {
  var somme = 0;
  for (var i = 0; i < douze.length; i++) {
    final c = douze.codeUnitAt(i) - 48;
    somme += i.isEven ? c : 3 * c;
  }
  return '${(10 - somme % 10) % 10}';
}

/// Codes d'un produit : son CIP tel quel, le CIP13 d'un CIP7 (34009 + CIP7 + clé), le CIP7 d'un CIP13 34009…,
/// puis les [autres] codes (EAN fabricant…). Codes vides ignorés, sans doublon.
List<String> codesProduit(String cip, [Iterable<String> autres = const []]) {
  final c = cip.trim();
  final out = <String>{};
  if (c.isNotEmpty) out.add(c);
  if (c.length == 7 && _chiffres.hasMatch(c)) out.add('34009$c${cleEan13('34009$c')}');
  if (c.length == 13 && c.startsWith('34009') && _chiffres.hasMatch(c)) out.add(c.substring(5, 12));
  for (final a in autres) {
    final t = a.trim();
    if (t.isNotEmpty) out.add(t);
  }
  return out.toList();
}

/// Rang d'un produit pour la saisie numérique [chiffres] (voir la règle en tête du fichier).
int rangCode(String chiffres, String cip, [Iterable<String> autres = const []]) {
  if (chiffres.isEmpty) return 3;
  final codes = codesProduit(cip, autres);
  if (codes.contains(chiffres)) return 0;
  if (cip.trim().startsWith(chiffres)) return 1;
  if (codes.any((c) => c.startsWith(chiffres))) return 2;
  return 3;
}

/// [items] classés pour la [saisie] : produits dont un code est la saisie, puis dont le CIP commence par la saisie,
/// puis dont un autre code commence par la saisie, puis le reste dans l'ordre du serveur. Saisie non numérique :
/// [items] renvoyée telle quelle (même liste).
List<T> classerParCode<T>(List<T> items, String saisie, String Function(T) cip, {Iterable<String> Function(T)? autres}) {
  final chiffres = saisieNumerique(saisie);
  if (chiffres.isEmpty || items.length < 2) return items;
  final rangs = [for (final p in items) rangCode(chiffres, cip(p), autres?.call(p) ?? const [])];
  final ordre = List<int>.generate(items.length, (i) => i)..sort((a, b) => rangs[a] != rangs[b] ? rangs[a] - rangs[b] : a - b);
  return [for (final i in ordre) items[i]];
}

/// Ligne d'une réponse « commence par » (GET /info?search=CIP, ventes annuelles…) qui correspond au produit de CIP
/// [cip] : même CIP exactement, sinon la mieux classée ([classerParCode]) ; null si [lignes] est vide.
T? ligneDuCode<T>(List<T> lignes, String cip, String Function(T) cipDe) {
  if (lignes.isEmpty) return null;
  final c = cip.trim();
  for (final l in lignes) {
    if (c.isNotEmpty && cipDe(l).trim() == c) return l;
  }
  return classerParCode(lignes, c, cipDe).first;
}
