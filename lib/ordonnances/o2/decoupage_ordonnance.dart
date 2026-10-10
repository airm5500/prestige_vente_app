// lib/ordonnances/o2/decoupage_ordonnance.dart
// Étape O2 : découpage d'une ordonnance par lignes numérotées (1. / 1) / ① / (1) / - / •).
// Chaque médicament reçoit la posologie des lignes suivantes (« 1cp x 2/j pdt 5 jrs ») et la quantité
// (« 01 bte », « → 02 bts ») ; en-têtes, tampons, signatures, dates, téléphones et noms sont ignorés.
// Sans aucune ligne numérotée, le découpage d'origine (PrescriptionParser.extract) est utilisé tel quel :
// le candidat ne fait jamais moins que la référence sur une ordonnance non numérotée.
// Pur Dart (testé avec des textes SYNTHÉTIQUES).
import 'package:prestige_vente_app/services/prescription_parser.dart';

/// Un médicament découpé (avant rapprochement avec le catalogue).
class LigneDecoupee {
  final String nom;
  final String? posologie;
  final int? quantite;
  const LigneDecoupee(this.nom, {this.posologie, this.quantite});

  @override
  String toString() => '$nom | ${posologie ?? '-'} | ${quantite ?? '-'}';
}

class DecoupageOrdonnance {
  DecoupageOrdonnance._();

  /// Marqueur de ligne numérotée ou de puce en début de ligne.
  static final _marqueur = RegExp(
    r'^\s*(?:[①-⑳➀-➉❶-❿]|\(\s*0?\d{1,2}\s*\)|0?\d{1,2}\s*[).°:\-–](?!\d)|0?\d{1,2}\s*\.(?!\d)|[-–—•*·=>»]+(?!\d))\s*',
  );

  /// « 01 Clavam » : numéro suivi directement d'un mot (cercle lu comme « 01 »).
  static final _numeroMot = RegExp(r'^\s*0?\d{1,2}\s+(?=[A-Za-zÀ-ÿ]{3,})');

  /// Unités de posologie / quantité : un nombre suivi de ces mots n'est pas un numéro de ligne.
  static const _unitesPoso = <String>{
    'cp', 'cps', 'comp', 'comprime', 'comprimes', 'gel', 'gelule', 'gelules', 'sachet', 'sachets', 'sach', 'amp',
    'ampoule', 'ampoules', 'cuil', 'cuillere', 'cuilleres', 'cac', 'cas', 'goutte', 'gouttes', 'gtt', 'dose', 'doses',
    'ml', 'mg', 'suppo', 'suppos', 'pulv', 'pulverisation', 'pulverisations', 'bain', 'bains', 'application',
    'applications', 'appl', 'inj', 'injection', 'fois', 'bte', 'btes', 'bts', 'bt', 'boite', 'boites', 'fl', 'flacon',
    'flacons', 'tube', 'tubes', 'jour', 'jours', 'jrs', 'semaine', 'semaines', 'mois', 'heures', 'h',
  };

  static final _posoDebut = RegExp(
    r'^\s*(?:\d+(?:[.,/]\d+)?\s*(?:cp|cps|comp|gel|gelule|sachet|sach|amp|ampoule|cuil|cac|cas|c\.|goutte|gtt|gte|dose|ml|suppo|pulv|bain|appl|application|inj|fois|x|×|\*)|une?\s+(?:goutte|cuill|comprim|gelule|ampoule|application|pulv|dose|sachet|bain|suppo)|(?:matin|midi|soir|au coucher)\b)',
  );

  /// Début de posologie au milieu d'une ligne (« Curam 1g 1cp x 3/j »).
  static final _posoMilieu = RegExp(
    r'(?:\s|^)(\d+(?:[.,]\d+)?\s*(?:cp|cps|gel|gelule|sachet|sach|amp|cuil|goutte|gtt|dose|suppo|pulv|bain)\b\s*(?:[x×*]|par|le|matin|soir|/)|\d\s*[x×*]\s*\d\s*/\s*j|\d\s*/\s*j(?:our|r)?\b|\bpdt\b|\bpendant\b|\bune?\s+(?:goutte|cuill|comprim|gelule|ampoule|application|pulv)|\bfois par jour\b)',
  );

  static final _posoIndice = RegExp(
    r'\d\s*[x×*]\s*\d|\d\s*/\s*j\b|/\s*jour|\bpar jour\b|\bpdt\b|\bpendant\b|\bjrs?\b|\bjours?\b|\bfois\b|\bmatin\b|\bsoir\b|\bmidi\b|\bcoucher\b',
  );

  static final _quantite = RegExp(
    r'(?:[-–—=]*>|→|—|–)?\s*\(?\s*(\d{1,2})\s*(?:btes?|bts?|boites?|bt|fl|flacons?|tubes?|b)\b\.?\s*\)?',
  );

  static const _bruit = <String>{
    'ordonnance', 'medicale', 'medical', 'clinique', 'polyclinique', 'hopital', 'chu', 'chr', 'centre', 'cabinet',
    'docteur', 'dr', 'medecin', 'pr', 'professeur', 'tel', 'telephone', 'cel', 'cell', 'fax', 'email', 'mail', 'bp',
    'rue', 'avenue', 'abidjan', 'ivoire', 'onmci', 'oncdci', 'signature', 'cachet', 'priere', 'ramener',
    'consultation', 'patient', 'patiente', 'nom', 'prenom', 'prenoms', 'age', 'ans', 'poids', 'date', 'groupe',
    'service', 'sexe', 'matricule', 'assurance', 'mutuelle', 'specialiste', 'generaliste', 'chirurgien', 'dentiste',
    'pediatre', 'ophtalmologiste', 'diagnostic', 'renouveler', 'renouvelable', 'cocody', 'plateau', 'plateaux',
    'marcory', 'yopougon', 'abobo', 'treichville', 'koumassi', 'adjame', 'riviera', 'inscrit', 'ordre', 'rccm', 'cnps',
  };

  static final _date = RegExp(r'\d{1,2}\s*[/.\-]\s*\d{1,2}\s*[/.\-]\s*\d{2,4}');
  static final _telephone = RegExp(r'\d{2}[ .]?\d{2}[ .]?\d{2}[ .]?\d{2}');

  static String _n(String s) => PrescriptionParser.normalize(s);
  static List<String> _mots(String s) => _n(s).split(RegExp(r'[^a-z0-9]+')).where((t) => t.isNotEmpty).toList();

  /// Ligne d'en-tête, de tampon, d'identité, de date ou de téléphone.
  static bool estBruit(String ligne) {
    final n = _n(ligne);
    if (n.contains('@') || n.contains('www') || n.contains('.com')) return true;
    if (_mots(ligne).any(_bruit.contains)) return true;
    if (_date.hasMatch(n) && !_posoIndice.hasMatch(n)) return true;
    if (_telephone.hasMatch(n) && !_posoIndice.hasMatch(n)) return true;
    return false;
  }

  /// Ligne de posologie (prise, fréquence, durée).
  static bool estPosologie(String ligne) {
    final n = _n(ligne).trim();
    if (_posoDebut.hasMatch(n)) return true;
    if (!_posoIndice.hasMatch(n)) return false;
    // « pdt 5 jrs », « x 2/j », « pendant 5 jours » ; mais pas « Predni 20 cp 3cp x 1/j » (nom en tête).
    final premier = _mots(n).firstOrNull ?? '';
    return premier.length < 4 || _motsPoso.contains(premier) || _unitesPoso.contains(premier);
  }

  static const _motsPoso = <String>{
    'pendant', 'durant', 'puis', 'matin', 'midi', 'soir', 'avant', 'apres', 'coucher', 'chaque', 'toutes', 'tous',
    'pdt', 'repas', 'renouveler', 'jusqu', 'dans', 'une', 'deux', 'trois', 'quatre', 'demi',
  };

  /// Retire le marqueur de début (numéro, cercle, puce). null : pas de marqueur.
  static String? sansMarqueur(String ligne) {
    final m = _marqueur.firstMatch(ligne);
    if (m != null && m.end > 0) return ligne.substring(m.end);
    final w = _numeroMot.firstMatch(ligne);
    if (w != null) {
      final suite = ligne.substring(w.end);
      final premier = _mots(suite).firstOrNull ?? '';
      if (!_unitesPoso.contains(premier)) return suite;
    }
    return null;
  }

  /// Quantité (« 01 bte », « → 02 bts ») et texte restant.
  static (int?, String) extraireQuantite(String ligne) {
    final n = _n(ligne);
    final m = _quantite.firstMatch(n);
    if (m == null) return (null, ligne);
    final q = int.tryParse(m.group(1)!);
    // Positions identiques : normalize ne change pas la longueur (accents remplacés un pour un).
    final reste = n.length == ligne.length ? ligne.replaceRange(m.start, m.end, ' ') : ligne;
    return (q != null && q > 0 ? q : null, reste.replaceAll(RegExp(r'\s{2,}'), ' ').trim());
  }

  /// Nom nettoyé : ponctuation des bords, « : 24 : » final, et lettre isolée en tête
  /// (tiret ou puce mal lus : « L KALEORID LP » → « KALEORID LP »).
  static String _nettoyerNom(String s) => s
      .replaceFirst(RegExp(r'^\s*[A-Za-z|!]\s+(?=[A-Za-zÀ-ÿ]{3,})'), '')
      .replaceAll(RegExp(r'^[\s:;,\-–—.]+|[\s:;,\-–—.]+$'), '').replaceAll(RegExp(r'\s+:\s*\d*\s*:?\s*$'), '').trim();

  static bool _nomValide(String nom) => RegExp(r'[A-Za-zÀ-ÿ]').allMatches(nom).length >= 3 && !estBruit(nom);

  /// Sépare « nom … posologie » sur une même ligne.
  static (String, String?) _separerPosologie(String texte) {
    final n = _n(texte);
    final m = _posoMilieu.firstMatch(n);
    if (m == null || m.start == 0) return (texte, null);
    final debut = m.start + (n[m.start] == ' ' ? 1 : 0);
    return (texte.substring(0, debut), texte.substring(debut).trim());
  }

  /// Découpage structuré ; liste vide si l'ordonnance n'a aucune ligne numérotée exploitable.
  static List<LigneDecoupee> decouper(List<String> lignes) {
    final out = <_Item>[];
    _Item? courant;
    var attenteNom = false; // « 1. » seul sur sa ligne : le nom suit
    for (final brute in lignes) {
      final ligne = brute.trim();
      if (ligne.isEmpty) continue;
      final reste = sansMarqueur(ligne);
      if (reste != null) {
        final (q, sansQ) = extraireQuantite(reste);
        if (estPosologie(sansQ) || (sansQ.isEmpty && q != null)) {
          // Puce devant une posologie / quantité : elle complète le médicament en cours.
          courant?.ajouterPoso(sansQ);
          if (courant != null) courant.quantite ??= q;
          continue;
        }
        if (estBruit(reste)) continue;
        final (nom, poso) = _separerPosologie(sansQ);
        final propre = _nettoyerNom(nom);
        if (propre.isEmpty && RegExp(r'^\s*[\d①-⑳(]').hasMatch(ligne)) {
          attenteNom = true;
          courant = null;
          continue;
        }
        if (!_nomValide(propre)) continue;
        courant = _Item(propre)..quantite = q;
        if (poso != null) courant.ajouterPoso(poso);
        out.add(courant);
        attenteNom = false;
        continue;
      }
      if (estBruit(ligne)) continue;
      final (q, sansQ) = extraireQuantite(ligne);
      if (estPosologie(sansQ) || (sansQ.isEmpty && q != null)) {
        if (courant != null) {
          if (sansQ.isNotEmpty) courant.ajouterPoso(sansQ);
          courant.quantite ??= q;
        }
        continue;
      }
      if (attenteNom) {
        final (nom, poso) = _separerPosologie(sansQ);
        final propre = _nettoyerNom(nom);
        if (_nomValide(propre)) {
          courant = _Item(propre)..quantite = q;
          if (poso != null) courant.ajouterPoso(poso);
          out.add(courant);
        }
        attenteNom = false;
        continue;
      }
      // Ligne non numérotée : produit seulement si le découpage d'origine la reconnaît (dosage ou forme).
      if (out.isNotEmpty && PrescriptionParser.parseLine(PrescriptionParser.cleanLine(sansQ) ?? '') != null) {
        final (nom, poso) = _separerPosologie(sansQ);
        courant = _Item(_nettoyerNom(nom))..quantite = q;
        if (poso != null) courant.ajouterPoso(poso);
        out.add(courant);
      }
    }
    return [for (final i in out) LigneDecoupee(i.nom, posologie: i.posologie, quantite: i.quantite)];
  }

  /// Lignes « médicament » pour la correspondance catalogue (même type que [PrescriptionParser.extract]).
  /// Sans ligne numérotée : exactement [PrescriptionParser.extract].
  static List<PrescriptionLine> extraire(List<String> lignes) {
    final decoupees = decouper(lignes);
    if (decoupees.isEmpty) return PrescriptionParser.extract(lignes);
    final out = <PrescriptionLine>[];
    final vus = <String>{};
    for (final d in decoupees) {
      final base = PrescriptionParser.parseLine(d.nom, force: true);
      if (base == null) continue;
      final cle = base.cip ?? PrescriptionParser.normalize(base.query);
      if (!vus.add(cle)) continue;
      out.add(PrescriptionLine(
        text: base.text,
        query: base.query,
        dosage: base.dosage,
        cip: base.cip,
        quantity: d.quantite ?? base.quantity,
        posology: d.posologie ?? base.posology,
      ));
    }
    return out.isEmpty ? PrescriptionParser.extract(lignes) : out;
  }
}

class _Item {
  final String nom;
  String? posologie;
  int? quantite;
  _Item(this.nom);

  void ajouterPoso(String p) {
    final t = p.trim();
    if (t.isEmpty) return;
    posologie = posologie == null ? t : '$posologie $t';
  }
}
