// lib/services/prescription_parser.dart
// Extraction des lignes "médicament" d'une ordonnance à partir du texte reconnu (OCR),
// et rapprochement avec les produits du stock.
//
// Précision : quand la ligne porte un CIP (ordonnance éditée par un logiciel), c'est le
// CIP qui désigne le produit, jamais une ressemblance de nom. Sans CIP, un seul produit
// est proposé et marqué "à vérifier" ; l'opérateur confirme ou change.
import 'package:prestige_vente_app/services/datamatrix_parser.dart';

class PrescriptionLine {
  /// Désignation lue (colonne produit), ou ligne saisie / corrigée par l'opérateur.
  final String text;

  /// Requête de recherche par nom (nom sans dosage ni forme).
  final String query;

  /// Dosage lu, ex. "1000 mg" -> "1000".
  final String? dosage;

  /// CIP (7 chiffres) ou code 13 chiffres lu sur la ligne.
  final String? cip;

  /// Quantité prescrite lue (colonne Qté), sinon null.
  final int? quantity;

  /// Posologie lue, sinon null.
  final String? posology;

  const PrescriptionLine({
    required this.text,
    required this.query,
    this.dosage,
    this.cip,
    this.quantity,
    this.posology,
  });
}

class PrescriptionParser {
  PrescriptionParser._();

  static const _forms = <String>{
    'cp', 'cps', 'cpr', 'comp', 'comprime', 'comprimes', 'gel', 'gelule', 'gelules', 'caps',
    'capsule', 'capsules', 'sirop', 'sir', 'sachet', 'sachets', 'sach', 'amp', 'ampoule', 'ampoules',
    'inj', 'injectable', 'suppo', 'suppositoire', 'suppositoires', 'supp', 'pommade', 'pom', 'creme',
    'collyre', 'coll', 'gouttes', 'gtt', 'fl', 'flacon', 'flacons', 'sol', 'solution',
    'buv', 'buvable', 'susp', 'suspension', 'ovule', 'ovules', 'spray', 'aerosol', 'patch', 'lp',
    'effervescent', 'eff', 'effv', 'orodispersible', 'lyoc', 'tube', 'boite', 'bte', 'bt', 'sec', 'ped',
    'pediatrique', 'nourrisson', 'adulte', 'enfant', 'perf', 'poudre', 'pdre', 'granules', 'emulsion',
  };

  static const _units = <String>{'mg', 'g', 'gr', 'ml', 'mcg', 'µg', 'ug', 'ui', '%', 'mui', 'l', 'cl'};

  /// Mots qui signalent une ligne d'en-tête, d'identité, de tableau ou de posologie (non produit).
  static const _noiseWords = <String>{
    'docteur', 'dr', 'medecin', 'pr', 'professeur', 'clinique', 'hopital', 'chu', 'chr', 'centre',
    'cabinet', 'tel', 'telephone', 'cel', 'cell', 'fax', 'email', 'mail', 'bp', 'adresse', 'rue',
    'avenue', 'ordonnance', 'patient', 'patiente', 'nom', 'prenom', 'prenoms', 'age', 'ans', 'mois',
    'poids', 'kg', 'date', 'le', 'signature', 'cachet', 'renouveler', 'renouvelable', 'qsp',
    'pendant', 'jours', 'jour', 'semaine', 'semaines', 'fois', 'matin', 'midi', 'soir', 'coucher',
    'avant', 'apres', 'repas', 'prendre', 'par', 'toutes', 'heures', 'si', 'besoin', 'douleur',
    'fievre', 'specialiste', 'generaliste', 'ordre', 'inscrit', 'onmci', 'rccm', 'cnps', 'mutuelle',
    'assurance', 'matricule', 'sexe', 'service', 'consultation', 'diagnostic',
    // En-têtes de tableaux / documents édités par logiciel
    'client', 'produit', 'produits', 'cip', 'qte', 'quantite', 'servie', 'posologie', 'total',
    'prescrit', 'prescrits', 'prescrite', 'prescripteur', 'etablissement', 'observations', 'type',
    'pieces', 'piece', 'jointe', 'fiche', 'document', 'renseigne', 'designation', 'libelle',
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

  /// Nom comparable : minuscules, sans accents ni ponctuation, espaces uniques.
  static String comparableName(String s) => _tokens(s).join(' ');

  static final _dosageRe = RegExp(r'(\d+(?:[.,]\d+)?)\s*(mg|g|gr|ml|mcg|µg|ug|ui|mui|%)(?![a-z])', caseSensitive: false);
  static final _listPrefixRe = RegExp(r'^\s*(?:\d{1,2}\s*[).\-/]|[-•*·>]+)\s*');
  static final _cipRe = RegExp(r'(?<![\d/.,\-])(\d{13}|\d{7})(?![\d/.,%\-])');

  /// Extrait les lignes susceptibles de désigner un médicament.
  static List<PrescriptionLine> extract(List<String> rawLines) {
    final result = <PrescriptionLine>[];
    final seen = <String>{};
    for (final raw in rawLines) {
      final line = cleanLine(raw);
      if (line == null) continue;
      final candidate = parseLine(line);
      if (candidate == null) continue;
      final key = candidate.cip ?? normalize(candidate.query);
      if (seen.add(key)) result.add(candidate);
    }
    return result;
  }

  /// Nettoie une ligne OCR (puces, numérotation). `null` si vide.
  static String? cleanLine(String raw) {
    var s = raw.replaceAll(RegExp(r'[ \t]+$'), '').trim();
    s = s.replaceFirst(_listPrefixRe, '').trim();
    return s.length < 3 ? null : s;
  }

  /// Analyse une ligne (éventuellement une ligne de tableau : colonnes séparées
  /// par deux espaces ou plus). Renvoie un candidat produit, ou `null`.
  static PrescriptionLine? parseLine(String line, {bool force = false}) {
    // Saisie manuelle d'un CIP seul
    if (force && RegExp(r'^\d{7}$|^\d{13}$').hasMatch(line.trim())) {
      final code = line.trim();
      return PrescriptionLine(text: code, query: code, cip: code);
    }
    // 1. Ligne de tableau avec CIP : "EFFERALGAN 500MG CPR EFFV B/16  3257001  1  —  1CP par jour"
    for (final m in _cipRe.allMatches(line)) {
      final code = m.group(1)!;
      if (code.length == 13 && !DataMatrixParser.isValidGs1CheckDigit(code)) continue;
      final name = line.substring(0, m.start).trim().replaceAll(RegExp(r'[\s|:;,\-]+$'), '');
      if (!_isProductName(name, requireDosageOrForm: false)) continue;
      final after = line.substring(m.end).trim();
      final q = RegExp(r'^(\d{1,3})(?![\d.,]|\s*(?:mg|g|ml|cp|comp|gel|sach|%|ui))').firstMatch(after);
      final qty = q == null ? null : int.parse(q.group(1)!);
      var posology = (q == null ? after : after.substring(q.end)).trim();
      posology = posology.replaceFirst(RegExp(r'^(?:[—–\-|]+\s*|\d{1,3}\s{2,})+'), '').trim();
      return PrescriptionLine(
        text: name,
        query: _nameQuery(name),
        dosage: _dosage(name),
        cip: code,
        quantity: qty != null && qty > 0 ? qty : null,
        posology: posology.isEmpty ? null : posology,
      );
    }

    // 2. Sans CIP : on juge la première colonne (la posologie est souvent à droite).
    final columns = line.split(RegExp(r'\s{2,}'));
    final name = columns.first.trim();
    if (force) {
      final q = _nameQuery(name.isEmpty ? line : name);
      if (q.isEmpty) return null;
      return PrescriptionLine(text: name.isEmpty ? line : name, query: q, dosage: _dosage(line));
    }
    if (!_isProductName(name, requireDosageOrForm: true)) return null;
    final rest = columns.skip(1).join('  ').trim();
    return PrescriptionLine(
      text: name,
      query: _nameQuery(name),
      dosage: _dosage(name),
      posology: rest.isEmpty ? null : rest,
    );
  }

  static bool _isProductName(String name, {required bool requireDosageOrForm}) {
    final tokens = _tokens(name);
    if (tokens.isEmpty) return false;
    final letters = RegExp(r'[A-Za-zÀ-ÿ]').allMatches(name).length;
    if (letters < 3) return false;
    final hasDosage = _dosageRe.hasMatch(name);
    final hasForm = tokens.any(_forms.contains);
    final noise = tokens.where(_noiseWords.contains).length;
    // Posologie : "1 cp matin et soir", "2 fois par jour pendant 5 jours"
    if (RegExp(r'^\d+(?:[.,/]\d+)?\s*(?:cp|cps|comprim|gel|sachet|cuill|c\.|goutte|amp|suppo|inj|fois|x\b)', caseSensitive: false)
        .hasMatch(normalize(name))) {
      return false;
    }
    if (RegExp(r'\d{2}[ .]?\d{2}[ .]?\d{2}[ .]?\d{2}').hasMatch(name) && !hasDosage) return false; // téléphone
    if (RegExp(r'\d{1,2}[/.\-]\d{1,2}[/.\-]\d{2,4}').hasMatch(name) && !hasDosage) return false; // date
    if (noise > 0 && !(hasDosage && noise == 1)) return false;
    if (requireDosageOrForm && !hasDosage && !hasForm) return false;
    return true;
  }

  static String? _dosage(String s) => _dosageRe.firstMatch(s)?.group(1)?.replaceAll(',', '.');

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

  /// Requêtes de recherche par nom à essayer dans l'ordre (nom complet, puis premier mot).
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
    // Chaque mot de la désignation lue retrouvé dans le produit (forme, conditionnement...)
    for (final t in _tokens(line.text)) {
      if (!l.contains(t) && p.contains(t)) s += 2;
    }
    return s;
  }
}
