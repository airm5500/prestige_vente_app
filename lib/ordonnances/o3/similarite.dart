// lib/ordonnances/o3/similarite.dart
// Étape O3 : ressemblance entre un mot LU (écriture manuscrite + OCR) et un nom du catalogue.
// - distance d'édition pondérée : les confusions fréquentes de l'écriture / de la lecture coûtent moins
//   (u/n, rn/m, cl/d, a/o, i/l/1, e/c, o/0…) ;
// - phonétique adaptée au français (ph = f, qu = k, ce/ci = se/si, eau/au = o, ou = u, lettres finales muettes…).
// Pur Dart, sans allocation dans la boucle principale (performance : 10 000 produits par ligne).
import 'dart:math' as math;
import 'dart:typed_data';

class Similarite {
  Similarite._();

  /// Paires de lettres souvent confondues (coût de substitution réduit).
  static const _confusions = <String>[
    'un', 'nu', 'ao', 'oa', 'il', 'li', 'i1', '1i', 'l1', '1l', 'ec', 'ce', 'o0', '0o', 'ae', 'ea', 'nm', 'mn', 'rn',
    'nr', 'vu', 'uv', 'bh', 'hb', 'gq', 'qg', 'tf', 'ft', 'sz', 'zs', 's5', '5s', 'b6', '6b', 'g9', '9g', 'z2', '2z',
    'ij', 'ji', 'ei', 'ie', 'oe', 'eo', 'au', 'ua', 'ou', 'uo', 'kh', 'hk', 'yi', 'iy', 'ck', 'kc', 'tl', 'lt', 'rv',
    'vr', 'bd', 'db', 'pq', 'qp', 'ny', 'yn',
  ];

  static final Uint8List _cout = () {
    final t = Uint8List(128 * 128)..fillRange(0, 128 * 128, 10);
    for (var i = 0; i < 128; i++) {
      t[i * 128 + i] = 0;
    }
    for (final p in _confusions) {
      t[p.codeUnitAt(0) * 128 + p.codeUnitAt(1)] = 4;
    }
    return t;
  }();

  /// Groupes de lettres lus comme une seule (« rn » ↔ « m », « cl » ↔ « d », « vv » ↔ « w », « ii » ↔ « u »).
  static const _groupes = <String, String>{'rn': 'm', 'cl': 'd', 'vv': 'w', 'ii': 'u', 'nn': 'm', 'iu': 'm', 'lo': 'b'};

  /// Table « deux lettres lues pour une » : (x, y) → z (0 si aucune).
  static final Uint8List _groupeTable = () {
    final t = Uint8List(128 * 128);
    for (final e in _groupes.entries) {
      t[e.key.codeUnitAt(0) * 128 + e.key.codeUnitAt(1)] = e.value.codeUnitAt(0);
    }
    return t;
  }();

  static int _c(int a, int b) => (a < 128 && b < 128) ? _cout[a * 128 + b] : (a == b ? 0 : 10);

  static Int32List _prev = Int32List(64), _cur = Int32List(64), _avant = Int32List(64);

  /// Distance d'édition pondérée (en dixièmes : 10 = une lettre complètement différente).
  static int distance(String a, String b) {
    final n = a.length, m = b.length;
    if (n == 0) return m * 10;
    if (m == 0) return n * 10;
    if (_prev.length <= m) {
      _prev = Int32List(m + 1);
      _cur = Int32List(m + 1);
      _avant = Int32List(m + 1);
    }
    var prev = _prev, cur = _cur, avant = _avant;
    for (var j = 0; j <= m; j++) {
      prev[j] = j * 10;
    }
    for (var i = 1; i <= n; i++) {
      cur[0] = i * 10;
      final ca = a.codeUnitAt(i - 1);
      for (var j = 1; j <= m; j++) {
        final cb = b.codeUnitAt(j - 1);
        var v = prev[j - 1] + _c(ca, cb);
        final del = prev[j] + 10, ins = cur[j - 1] + 10;
        if (del < v) v = del;
        if (ins < v) v = ins;
        // Deux lettres lues pour une (« rn » → « m ») ou l'inverse.
        if (i >= 2 && j >= 1 && _groupe(a.codeUnitAt(i - 2), ca, cb)) {
          final g = avant[j - 1] + 4;
          if (g < v) v = g;
        }
        if (j >= 2 && i >= 1 && _groupe(b.codeUnitAt(j - 2), cb, ca)) {
          final g = prev[j - 2] + 4;
          if (g < v) v = g;
        }
        cur[j] = v;
      }
      final t = avant;
      avant = prev;
      prev = cur;
      cur = t;
    }
    final r = prev[m];
    _prev = prev;
    _cur = cur;
    _avant = avant;
    return r;
  }

  static bool _groupe(int x, int y, int z) => x < 128 && y < 128 && z != 0 && _groupeTable[x * 128 + y] == z;

  /// Ressemblance 0…1 de deux mots (1 = identiques).
  static double ressemblance(String a, String b) {
    if (a == b) return 1;
    final l = math.max(a.length, b.length);
    if (l == 0) return 0;
    return math.max(0, 1 - distance(a, b) / (10 * l));
  }

  /// Ressemblance d'un mot lu [lu] avec le DÉBUT d'un mot du catalogue [nom] (mot tronqué, abrégé :
  /// « pediat » → « pediatrique »). Le reste non lu de [nom] n'est pas pénalisé, si [lu] fait ≥ 5 lettres.
  static double ressemblanceDebut(String lu, String nom) {
    if (lu.length < 5 || nom.length <= lu.length) return ressemblance(lu, nom);
    return math.max(ressemblance(lu, nom), ressemblance(lu, nom.substring(0, lu.length)) * 0.95);
  }

  /// Clé phonétique française simplifiée.
  static String phonetique(String mot) {
    var s = mot.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    if (s.isEmpty) return s;
    const regles = <(String, String)>[
      ('eau', 'o'), ('au', 'o'), ('ph', 'f'), ('qu', 'k'), ('ck', 'k'), ('ch', 'x'), ('sh', 'x'), ('gu', 'g'),
      ('th', 't'), ('ou', 'u'), ('oi', 'wa'), ('ai', 'e'), ('ei', 'e'), ('ey', 'e'), ('ay', 'e'), ('em', 'an'),
      ('en', 'an'), ('am', 'an'), ('y', 'i'), ('w', 'v'), ('z', 's'), ('x', 'ks'),
    ];
    for (final (a, b) in regles) {
      s = s.replaceAll(a, b);
    }
    s = s.replaceAllMapped(RegExp(r'c(?=[eiy])'), (_) => 's').replaceAll('c', 'k');
    s = s.replaceAllMapped(RegExp(r'g(?=[eiy])'), (_) => 'j');
    s = s.replaceAll('h', '');
    // Lettres doublées, finales muettes.
    s = s.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m.group(1)!);
    if (s.length > 3) s = s.replaceFirst(RegExp(r'[estdx]+$'), '');
    return s;
  }
}
