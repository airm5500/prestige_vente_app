// lib/services/prescription_parser.dart
// Extraction des lignes "médicament" d'une ordonnance à partir du texte reconnu (OCR),
// et classement des produits du stock par ressemblance avec la ligne lue.
//
// Principe : l'OCR ne remplace pas la lecture du pharmacien. Les lignes proposées
// sont modifiables, et tout le texte lu reste consultable pour ajouter une ligne oubliée.

class PrescriptionLine {
  /// Texte de la ligne tel que lu (ou corrigé par l'opérateur).
  final String text;

  /// Requête envoyée à la recherche produit (nom sans dosage ni forme).
  final String query;

  /// Dosage lu, ex. "1000 mg" -> "1000".
  final String? dosage;

  const PrescriptionLine({required this.text, required this.query, this.dosage});
}

class PrescriptionParser {
  PrescriptionParser._();

  static const _forms = <String>{
    'cp', 'cps', 'cpr', 'comp', 'comprime', 'comprimes', 'gel', 'gelule', 'gelules', 'caps',
    'capsule', 'capsules', 'sirop', 'sir', 'sachet', 'sachets', 'sach', 'amp', 'ampoule', 'ampoules',
    'inj', 'injectable', 'suppo', 'suppositoire', 'suppositoires', 'supp', 'pommade', 'pom', 'creme',
    'collyre', 'coll', 'gouttes', 'gtt', 'fl', 'flacon', 'flacons', 'sol', 'solution',
    'buv', 'buvable', 'susp', 'suspension', 'ovule', 'ovules', 'spray', 'aerosol', 'patch', 'lp',
    'effervescent', 'eff', 'orodispersible', 'lyoc', 'tube', 'boite', 'bte', 'bt', 'sec', 'ped',
    'pediatrique', 'nourrisson', 'adulte', 'enfant', 'perf', 'poudre', 'pdre', 'granules', 'emulsion',
  };

  static const _units = <String>{'mg', 'g', 'gr', 'ml', 'mcg', 'µg', 'ug', 'ui', '%', 'mui', 'l', 'cl'};

  /// Mots qui signalent une ligne d'en-tête, d'identité ou de posologie (non produit).
  static const _noiseWords = <String>{
    'docteur', 'dr', 'medecin', 'pr', 'professeur', 'clinique', 'hopital', 'chu', 'chr', 'centre',
    'cabinet', 'tel', 'telephone', 'cel', 'cell', 'fax', 'email', 'mail', 'bp', 'adresse', 'rue',
    'avenue', 'ordonnance', 'patient', 'patiente', 'nom', 'prenom', 'prenoms', 'age', 'ans', 'mois',
    'poids', 'kg', 'date', 'le', 'signature', 'cachet', 'renouveler', 'renouvelable', 'qsp',
    'pendant', 'jours', 'jour', 'semaine', 'semaines', 'fois', 'matin', 'midi', 'soir', 'coucher',
    'avant', 'apres', 'repas', 'prendre', 'par', 'toutes', 'heures', 'si', 'besoin', 'douleur',
    'fievre', 'specialiste', 'generaliste', 'ordre', 'inscrit', 'onmci', 'rccm', 'cnps', 'mutuelle',
    'assurance', 'matricule', 'sexe', 'service', 'consultation', 'diagnostic',
  };

  static String normalize(String s) {
    const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿÀÂÄÁÃÅÇÉÈÊËÍÌÎÏÑÓÒÔÖÕÚÙÛÜÝ';
    const to = 'aaaaaaceeeeiiiinooooouuuuyyAAAAAACEEEEIIIINOOOOOUUUUY';
    final b = StringBuffer();
    for (final ch in s.split('')) {
      final i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    return b.toString().toLowerCase();
  }

  static List<String> _tokens(String s) =>
      normalize(s).split(RegExp(r'[^a-z0-9%µ]+')).where((t) => t.isNotEmpty).toList();

  static final _dosageRe = RegExp(r'(\d+(?:[.,]\d+)?)\s*(mg|g|gr|ml|mcg|µg|ug|ui|mui|%)(?![a-z])', caseSensitive: false);
  static final _listPrefixRe = RegExp(r'^\s*(?:\d{1,2}\s*[).\-/]|[-•*·>]+)\s*');

  /// Extrait les lignes susceptibles de désigner un médicament.
  static List<PrescriptionLine> extract(List<String> rawLines) {
    final result = <PrescriptionLine>[];
    final seen = <String>{};
    for (final raw in rawLines) {
      final line = cleanLine(raw);
      if (line == null) continue;
      final candidate = parseLine(line);
      if (candidate == null) continue;
      if (seen.add(normalize(candidate.query))) result.add(candidate);
    }
    return result;
  }

  /// Nettoie une ligne OCR (puces, numérotation, espaces). `null` si vide.
  static String? cleanLine(String raw) {
    var s = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    s = s.replaceFirst(_listPrefixRe, '').trim();
    return s.length < 3 ? null : s;
  }

  /// Analyse une ligne : renvoie un candidat produit, ou `null` si la ligne
  /// ressemble à un en-tête, une identité ou une posologie.
  static PrescriptionLine? parseLine(String line, {bool force = false}) {
    final tokens = _tokens(line);
    if (tokens.isEmpty) return null;

    final hasDosage = _dosageRe.hasMatch(line);
    final hasForm = tokens.any(_forms.contains);
    final noise = tokens.where(_noiseWords.contains).length;
    final letters = RegExp(r'[A-Za-zÀ-ÿ]').allMatches(line).length;

    if (!force) {
      if (letters < 3) return null;
      // Posologie : "1 cp matin et soir", "2 fois par jour pendant 5 jours"
      if (RegExp(r'^\d+(?:[.,/]\d+)?\s*(?:cp|cps|comprim|gel|sachet|cuill|c\.|goutte|amp|suppo|inj|fois|x\b)', caseSensitive: false)
          .hasMatch(normalize(line))) {
        return null;
      }
      if (RegExp(r'\d{2}[ .]?\d{2}[ .]?\d{2}[ .]?\d{2}').hasMatch(line) && !hasDosage) return null; // téléphone
      if (RegExp(r'\d{1,2}[/.\-]\d{1,2}[/.\-]\d{2,4}').hasMatch(line) && !hasDosage) return null; // date
      if (noise > 0 && !(hasDosage && noise == 1)) return null;
      if (!hasDosage && !hasForm) return null;
    }

    final query = _nameQuery(line);
    if (query.isEmpty) return null;
    final m = _dosageRe.firstMatch(line);
    final dosage = m?.group(1)?.replaceAll(',', '.');
    return PrescriptionLine(text: line, query: query, dosage: dosage);
  }

  /// Nom commercial / DCI : mots avant le premier dosage ou la première forme.
  static String _nameQuery(String line) {
    final words = line.split(RegExp(r'\s+'));
    final kept = <String>[];
    for (final w in words) {
      final n = normalize(w).replaceAll(RegExp(r'[^a-z0-9%µ]'), '');
      if (n.isEmpty) continue;
      if (RegExp(r'^\d').hasMatch(n)) break; // début du dosage / quantité
      if (_forms.contains(n) || _units.contains(n)) break;
      kept.add(w.replaceAll(RegExp(r'''[^A-Za-zÀ-ÿ0-9\-']'''), ''));
      if (kept.length == 3) break;
    }
    return kept.where((w) => w.isNotEmpty).join(' ');
  }

  /// Requêtes de recherche à essayer dans l'ordre (nom complet, puis premier mot).
  static List<String> searchQueries(PrescriptionLine line) {
    final q = line.query.trim();
    final first = q.split(' ').first;
    return {q, if (first.length >= 4) first}.toList();
  }

  /// Score de ressemblance entre la ligne de l'ordonnance et un nom de produit.
  static int score(PrescriptionLine line, String productName) {
    final p = _tokens(productName).toSet();
    final l = _tokens(line.query);
    var s = 0;
    for (final t in l) {
      if (p.contains(t)) {
        s += 10;
      } else if (p.any((x) => x.startsWith(t) || t.startsWith(x) && x.length >= 4)) {
        s += 5;
      }
    }
    final d = line.dosage;
    if (d != null) {
      final dn = d.endsWith('.0') ? d.substring(0, d.length - 2) : d;
      if (RegExp('(^|[^0-9])${RegExp.escape(dn)}([^0-9]|\$)').hasMatch(normalize(productName))) s += 8;
    }
    final lineTokens = _tokens(line.text);
    for (final f in lineTokens.where(_forms.contains)) {
      if (p.contains(f)) s += 2;
    }
    return s;
  }
}
