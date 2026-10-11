// lib/ordonnances/o4/segment_medicament.dart
// Étape O4 : « segment médicament » d'une ligne lue, seule chose retenue (et partagée) par l'apprentissage.
//
// Données de santé : on ne garde JAMAIS le texte lu complet. Le segment est la partie « médicament » de la ligne
// (nom, dosage, forme), normalisée (minuscules sans accents), bornée (4 mots, 40 caractères), sans posologie ni
// quantité. Une ligne qui ressemble à autre chose qu'un médicament (date, téléphone, e-mail, titre « Dr / Mme /
// Patient / Nom », adresse, âge, long nombre) n'est PAS apprise : null.
// Un nom de personne écrit seul ne peut pas être reconnu à coup sûr ; mais seule une ligne pour laquelle le
// pharmacien a validé un PRODUIT est apprise (voir apprentissage_o4.dart).
import 'package:prestige_vente_app/ordonnances/banc_essai/normalisation_produit.dart';

abstract final class SegmentMedicament {
  /// Mots au plus (marque, 2ᵉ mot, dosage, forme).
  static const int motsMax = 4;

  /// Longueur maximale du segment (caractères).
  static const int longueurMax = 40;

  /// Mots qui signalent une donnée personnelle / administrative : la ligne n'est pas apprise.
  static const _interdits = <String>{
    'dr', 'docteur', 'doc', 'pr', 'professeur', 'mme', 'madame', 'mr', 'monsieur', 'mlle', 'mademoiselle', 'm',
    'patient', 'patiente', 'nom', 'prenom', 'prenoms', 'ne', 'nee', 'age', 'ans', 'mois', 'tel', 'telephone', 'cel',
    'cell', 'portable', 'bp', 'rue', 'avenue', 'av', 'boulevard', 'bd', 'quartier', 'villa', 'lot', 'clinique',
    'hopital', 'chu', 'cabinet', 'centre', 'signature', 'cachet', 'assure', 'assuree', 'matricule', 'email', 'mail',
    'date', 'le', 'fait', 'abidjan', 'dakar', 'ordonnance', 'medecin', 'infirmier', 'sage', 'femme', 'enfant de',
  };

  /// Début de posologie / quantité : la suite de la ligne est ignorée.
  static final _posologie = RegExp(
    r'(\s[x×]\s*\d|\d\s*[x×]\s*\d|\d+\s*(?:fois|f)\s*/|/\s*j\b|/\s*jour|\bpar\s+jour|\bpdt\b|\bpendant\b|\bmatin\b|\bmidi\b|'
    r'\bsoir\b|\bfois\b|\b\d+\s*(?:cp|cps|cpr|comprimes?|gel|gelules?|doses?|gouttes?|gtt|sachets?|cuill\w*|cas|cac|amp|suppos?)\b|'
    r'\bqsp\b|->|→|=>|\b\d+\s*(?:bte|btes|bts|bt|boites?|fl|flacons?|tubes?)\b|\bjrs?\b|\bjours?\b|\bsemaines?\b)',
    caseSensitive: false,
  );

  static final _email = RegExp(r'@|\bwww\.|https?:');
  static final _telephone = RegExp(r'(?:\+?\d[\s.\-]?){8,}');
  static final _date = RegExp(r'\b\d{1,2}\s*[/.\-]\s*\d{1,2}\s*[/.\-]\s*\d{2,4}\b');
  static final _listePrefixe = RegExp(r'^\s*(?:\(?\d{1,2}\s*[).\-/°]|[-•*·>=①②③④⑤⑥⑦⑧⑨⑩]+)\s*');

  /// Segment médicament de [texteLu] (ligne lue, sans le numéro), ou null si la ligne n'est pas apprenable.
  static String? extraire(String texteLu) {
    var t = texteLu.trim();
    if (t.isEmpty || t.length > 120) return null;
    if (_email.hasMatch(t) || _telephone.hasMatch(t) || _date.hasMatch(t)) return null;
    t = t.replaceFirst(_listePrefixe, '');
    final p = _posologie.firstMatch(t);
    if (p != null) t = t.substring(0, p.start);
    t = NormalisationProduit.sansAccents(t);
    // Dosages collés ou séparés (« 1 g » → « 1g ») ; seuls lettres, chiffres et % / . , restent.
    t = t.replaceAll(RegExp(r'[^a-z0-9%/.,]+'), ' ').replaceAllMapped(RegExp(r'(\d)\s+(mg|g|ml|mcg|ui|mui|%)\b'), (m) => '${m[1]}${m[2]}');
    final mots = t.split(' ').map((m) => m.replaceAll(RegExp(r'^[/.,]+|[/.,]+$'), '')).where((m) => m.isNotEmpty).toList();
    if (mots.isEmpty) return null;
    for (final m in mots) {
      if (_interdits.contains(m)) return null;
      if (RegExp(r'\d{5,}').hasMatch(m)) return null; // long nombre (téléphone, matricule, CIP)
    }
    if (!mots.any((m) => RegExp(r'[a-z]{3,}').hasMatch(m))) return null;
    // Une ligne de plus de 6 mots est une phrase (mention, adresse), pas un médicament.
    if (mots.length > 6) return null;
    final out = <String>[];
    var longueur = 0;
    for (final m in mots.take(motsMax)) {
      if (longueur + m.length + (out.isEmpty ? 0 : 1) > longueurMax) break;
      out.add(m);
      longueur += m.length + (out.length > 1 ? 1 : 0);
    }
    if (out.isEmpty || !RegExp(r'[a-z]{3,}').hasMatch(out.first + out.skip(1).join())) return null;
    final s = out.join(' ');
    return s.length < 3 ? null : s;
  }

  /// Forme compacte (sans espaces) pour comparer deux segments.
  static String compact(String segment) => segment.replaceAll(' ', '');
}
