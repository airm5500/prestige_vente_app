// lib/ordonnances/banc_essai/normalisation_produit.dart
// Banc d'essai des ordonnances (étape O1) : normalisation d'un nom de produit pour comparer
// « ce que le pipeline propose » à « ce que le pharmacien a saisi » (vérité terrain).
// Pur Dart, sans dépendance à l'interface.
//
// Règles :
// - casse, accents, ponctuation, traits d'union ignorés (« Bio-Ritmo » = « BIORITMO ») ;
// - formes et conditionnements ignorés (cp, gél, sp, susp, amp, suppo, collyre, B/20…) ;
// - dosages comparés à part : s'ils sont présents des deux côtés, au moins un doit être commun
//   (1 g = 1000 mg) ;
// - marque comparée avec une tolérance d'écart de lettres (Levenshtein) et de préfixe ;
// - qualificatifs qui changent le produit (Plus, Pro, Forte, T, AB, MTS…) : doivent concorder ;
// - « (?) » (lecture incertaine) et texte entre parenthèses ignorés pour la comparaison.

class NomProduitNormalise {
  /// Texte d'origine.
  final String texte;

  /// Mots du nom (marque d'abord), sans forme ni dosage ni qualificatif.
  final List<String> mots;

  /// Qualificatifs qui distinguent deux produits (plus, pro, forte, t…).
  final Set<String> qualificatifs;

  /// Dosages en valeurs comparables (« 1g » → {1, 1000}).
  final Set<String> dosages;

  /// La ligne portait « (?) » : lecture incertaine.
  final bool incertain;

  const NomProduitNormalise({
    required this.texte,
    required this.mots,
    required this.qualificatifs,
    required this.dosages,
    required this.incertain,
  });

  /// Mot principal (marque / DCI), vide si aucun.
  String get marque => mots.isEmpty ? '' : mots.first;

  /// Clé lisible, ex. « eludril +pro ».
  String get cle => [...mots.take(1), ...(qualificatifs.toList()..sort()).map((q) => '+$q')].join(' ');

  @override
  String toString() => cle;
}

class NormalisationProduit {
  NormalisationProduit._();

  /// Formes, voies, conditionnements et mots de liaison : ignorés.
  static const formes = <String>{
    'cp', 'cps', 'cpr', 'cpm', 'comp', 'comprime', 'comprimes', 'gel', 'gelule', 'gelules', 'gels', 'caps',
    'capsule', 'capsules', 'sp', 'sirop', 'sir', 'susp', 'suspension', 'sachet', 'sachets', 'sach',
    'amp', 'ampoule', 'ampoules', 'inj', 'injectable', 'injection', 'suppo', 'suppos', 'suppositoire',
    'suppositoires', 'supp', 'pommade', 'pom', 'pde', 'creme', 'collyre', 'coll', 'gouttes', 'gtt', 'fl',
    'flacon', 'flacons', 'sol', 'solution', 'buv', 'buvable', 'buvale', 'spray', 'aerosol', 'patch',
    'effervescent', 'effervescents', 'eff', 'effv', 'orodispersible', 'lyoc', 'tube', 'boite', 'boites', 'bte',
    'btes', 'bt', 'bts', 'b', 'perf', 'poudre', 'pdre', 'granules', 'emulsion', 'kit', 'oral', 'orale',
    'ou', 'et', 'de', 'du', 'la', 'le', 'des', 'en', 'a', 'pour', 'avec', 'nasal', 'nasale', 'lavage',
    'pulverisation', 'dose', 'doses', 'unidose', 'unidoses', 'adulte', 'adultes', 'sec', 'secable',
  };

  /// Qualificatifs qui changent le produit : présents d'un côté, ils doivent l'être de l'autre.
  static const qualificatifsStricts = <String>{'plus', 'pro', 'forte', 'fort', 't', 'ab', 'mts', 'duo', 'denk', 'max', 'codeine'};

  /// Qualificatifs exigés seulement s'ils figurent dans la vérité (le catalogue peut les omettre ou non).
  static const qualificatifsSouples = <String>{'pediatrique', 'ped', 'nourrisson', 'enfant', 'enfants', 'junior', 'lp', 'retard'};

  static const _unites = <String>{'mg', 'g', 'gr', 'ml', 'mcg', 'ug', 'ui', 'mui', 'm', 'kg', 'l', 'cl', '%'};

  /// Minuscules sans accents.
  static String sansAccents(String s) {
    const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæÀÂÄÁÃÅÇÉÈÊËÍÌÎÏÑÓÒÔÖÕÚÙÛÜÝŒÆ';
    const to = 'aaaaaaceeeeiiiinooooouuuuyyoaAAAAAACEEEEIIIINOOOOOUUUUYOA';
    final b = StringBuffer();
    for (final r in s.runes) {
      final c = String.fromCharCode(r);
      final i = from.indexOf(c);
      b.write(i >= 0 ? to[i] : c);
    }
    return b.toString().toLowerCase();
  }

  static final _dosageRe = RegExp(r'(\d+(?:[.,]\d+)?)\s*(mg|mcg|ug|µg|ui|mui|ml|gr|g|m|%)?(?![a-z])');

  static String _nombre(String n) {
    final v = double.tryParse(n.replaceAll(',', '.'));
    if (v == null) return n;
    return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  }

  /// Normalise un nom de produit (vérité ou proposition).
  static NomProduitNormalise normaliser(String texte) {
    final incertain = texte.contains('(?)');
    // Texte entre parenthèses : remarque (« (ampoule buvale) », « (?) »).
    var s = sansAccents(texte).replaceAll(RegExp(r'\([^)]*\)'), ' ');
    // Conditionnement « B/20 », « bte de 30 », « x30 ».
    s = s.replaceAll(RegExp(r'\bb\s*/\s*\d+'), ' ').replaceAll(RegExp(r'\bx\s*\d+\b'), ' ');
    // Traits d'union entre lettres : « bio-ritmo » → « bioritmo », « spasmo-apotel » → « spasmoapotel ».
    s = s.replaceAllMapped(RegExp(r'([a-z])-(?=[a-z])'), (m) => m.group(1)!);

    final dosages = <String>{};
    // Dosages composés « 80/480 », « 400/80 ».
    s = s.replaceAllMapped(RegExp(r'(\d+(?:[.,]\d+)?)\s*/\s*(\d+(?:[.,]\d+)?)'), (m) {
      dosages.add(_nombre(m.group(1)!));
      dosages.add(_nombre(m.group(2)!));
      return ' ';
    });
    s = s.replaceAllMapped(_dosageRe, (m) {
      final n = _nombre(m.group(1)!);
      final unite = m.group(2);
      dosages.add(n);
      if (unite == 'g' || unite == 'gr') {
        final v = double.tryParse(m.group(1)!.replaceAll(',', '.'));
        if (v != null) dosages.add(_nombre((v * 1000).toString()));
      }
      return ' ';
    });

    final mots = <String>[];
    final qualificatifs = <String>{};
    for (final t in s.split(RegExp(r'[^a-z0-9]+'))) {
      if (t.isEmpty) continue;
      if (qualificatifsStricts.contains(t) || qualificatifsSouples.contains(t)) {
        qualificatifs.add(t == 'ped' ? 'pediatrique' : (t == 'fort' ? 'forte' : (t == 'enfants' ? 'enfant' : t)));
        continue;
      }
      if (formes.contains(t) || _unites.contains(t)) continue;
      if (RegExp(r'^\d').hasMatch(t)) continue;
      if (t.length < 2) continue;
      mots.add(t);
    }
    return NomProduitNormalise(texte: texte, mots: mots, qualificatifs: qualificatifs, dosages: dosages, incertain: incertain);
  }

  /// Distance d'édition (insertion, suppression, substitution).
  static int levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    var cur = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      cur[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        final del = prev[j] + 1, ins = cur[j - 1] + 1, sub = prev[j - 1] + cost;
        cur[j] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
      }
      final t = prev;
      prev = cur;
      cur = t;
    }
    return prev[b.length];
  }

  /// Écart de lettres toléré selon la longueur du mot : ≤ 3 : 0 ; 4-6 : 1 ; ≥ 7 : 2.
  static int tolerance(int longueur) => longueur <= 3 ? 0 : (longueur <= 6 ? 1 : 2);

  /// Deux mots se ressemblent : écart de lettres toléré, ou l'un commence par l'autre (≥ 5 lettres).
  static bool motsProches(String a, String b) {
    if (a == b) return true;
    final court = a.length <= b.length ? a : b;
    final long = a.length <= b.length ? b : a;
    if (court.length >= 5 && long.startsWith(court)) return true;
    return levenshtein(a, b) <= tolerance(court.length);
  }

  /// La proposition [propose] correspond-elle au produit attendu [attendu] ?
  static bool correspond(NomProduitNormalise attendu, NomProduitNormalise propose) {
    if (attendu.marque.isEmpty || propose.mots.isEmpty) return false;
    // Marque attendue retrouvée parmi les mots proposés (ou les deux premiers mots collés : « bio ritmo »).
    final candidats = <String>[
      ...propose.mots,
      if (propose.mots.length >= 2) propose.mots[0] + propose.mots[1],
    ];
    final marques = <String>[attendu.marque, if (attendu.mots.length >= 2) attendu.mots[0] + attendu.mots[1]];
    if (!marques.any((m) => candidats.any((c) => motsProches(m, c)))) return false;
    // Qualificatifs stricts : mêmes de part et d'autre.
    final qa = attendu.qualificatifs.intersection(qualificatifsStricts);
    final qp = propose.qualificatifs.intersection(qualificatifsStricts);
    if (qa.length != qp.length || !qa.containsAll(qp)) return false;
    // Qualificatifs souples : exigés s'ils sont attendus.
    for (final q in attendu.qualificatifs.intersection(_souplesNormalises)) {
      if (!propose.qualificatifs.contains(q)) return false;
    }
    // Dosage : s'il est connu des deux côtés, au moins une valeur commune.
    if (attendu.dosages.isNotEmpty && propose.dosages.isNotEmpty && attendu.dosages.intersection(propose.dosages).isEmpty) {
      return false;
    }
    return true;
  }

  static final _souplesNormalises = <String>{'pediatrique', 'nourrisson', 'enfant', 'junior', 'lp', 'retard'};

  /// Raccourci sur des textes bruts.
  static bool correspondTexte(String attendu, String propose) => correspond(normaliser(attendu), normaliser(propose));
}
