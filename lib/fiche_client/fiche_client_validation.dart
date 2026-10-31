// lib/fiche_client/fiche_client_validation.dart
// Contrôles de saisie de la fiche client (avant envoi ; le serveur revérifie avec les bornes du paramètre).
// Les bornes plausibles ci-dessous servent quand le paramètre n'en a pas dans Prestige, et resserrent celles
// du serveur si elles sont plus larges (une valeur hors de ces bornes est presque toujours une faute de frappe).
import 'package:prestige_vente_app/fiche_client/fiche_client_models.dart';

/// Longueur maximale des allergies (DossierClientService.MAX_ALLERGIES).
const int maxAllergies = 2000;

/// Longueur maximale d'un commentaire de mesure (tronqué par le serveur au-delà).
const int maxCommentaireMesure = 200;

/// Bornes plausibles par code de paramètre (unité du référentiel Prestige V6.9.70).
const Map<String, (double, double)> bornesPlausibles = {
  'GLYCEMIE_JEUN': (0.2, 6), // g/L
  'GLYCEMIE': (0.2, 6), // g/L
  'TENSION': (40, 260), // mmHg (systolique et diastolique)
  'FREQ_CARDIAQUE': (20, 250), // bpm
  'POIDS': (0.5, 350), // kg
  'TAILLE': (30, 250), // cm
  'TEMPERATURE': (30, 45), // °C
  'SPO2': (50, 100), // %
};

/// Bornes retenues pour un paramètre : intersection des bornes Prestige et des bornes plausibles.
(double?, double?) bornes(ParametreClinique p) {
  var min = p.saisieMin, max = p.saisieMax;
  final b = bornesPlausibles[p.code];
  if (b != null) {
    min = min == null ? b.$1 : (min < b.$1 ? b.$1 : min);
    max = max == null ? b.$2 : (max > b.$2 ? b.$2 : max);
    if (min > max) return (p.saisieMin, p.saisieMax); // référentiel incohérent : on laisse le serveur trancher
  }
  return (min, max);
}

/// Lit un nombre saisi (virgule ou point). Null si illisible.
double? lireNombre(String saisie) {
  final s = saisie.trim().replaceAll(',', '.').replaceAll(' ', '');
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(s)) return null;
  final v = double.tryParse(s);
  return v != null && v.isFinite ? v : null;
}

String _num(double v) {
  final s = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
  return s.replaceAll('.', ',');
}

/// Contrôle d'une valeur : null si valable, sinon le message.
String? validerValeur(String saisie, ParametreClinique p, {String? nom}) {
  final libelle = nom ?? p.libelle;
  final s = saisie.trim();
  if (s.isEmpty) return '$libelle : valeur obligatoire.';
  final v = lireNombre(s);
  if (v == null) return '$libelle : saisissez un nombre (ex. ${p.decimales > 0 ? '12,5' : '120'}).';
  final dec = s.replaceAll(',', '.').contains('.') ? s.replaceAll(',', '.').split('.').last.length : 0;
  if (dec > p.decimales) {
    return p.decimales == 0 ? '$libelle : nombre entier attendu.' : '$libelle : ${p.decimales} décimale(s) au plus.';
  }
  final (min, max) = bornes(p);
  final unite = p.unite.isEmpty ? '' : ' ${p.unite}';
  if (min != null && v < min) return '$libelle : ${_num(v)}$unite paraît trop bas (minimum ${_num(min)}$unite).';
  if (max != null && v > max) return '$libelle : ${_num(v)}$unite paraît trop haut (maximum ${_num(max)}$unite).';
  if (min == null && v <= 0) return '$libelle : la valeur doit être supérieure à 0.';
  return null;
}

/// Contrôle de la date de mesure : pas dans le futur (comme le serveur), pas avant l'an 2000.
String? validerDateMesure(DateTime d, {DateTime? maintenant}) {
  final now = maintenant ?? DateTime.now();
  if (d.isAfter(now.add(const Duration(minutes: 1)))) return 'La date de la mesure ne peut pas être dans le futur.';
  if (d.year < 2000) return 'Date de mesure trop ancienne.';
  return null;
}

/// Mesure à enregistrer (corps de POST client/{id}/mesures).
class SaisieMesure {
  final ParametreClinique parametre;
  final DateTime date;
  final String valeur;
  final String systoliqueG, diastoliqueG, systoliqueD, diastoliqueD;
  final String commentaire;

  const SaisieMesure({
    required this.parametre,
    required this.date,
    this.valeur = '',
    this.systoliqueG = '',
    this.diastoliqueG = '',
    this.systoliqueD = '',
    this.diastoliqueD = '',
    this.commentaire = '',
  });

  /// Tous les problèmes de la saisie (vide = valable).
  List<String> erreurs({DateTime? maintenant}) {
    final out = <String>[];
    final d = validerDateMesure(date, maintenant: maintenant);
    if (d != null) out.add(d);
    if (commentaire.trim().length > maxCommentaireMesure) out.add('Commentaire : $maxCommentaireMesure caractères au plus.');
    if (!parametre.tension) {
      final e = validerValeur(valeur, parametre);
      if (e != null) out.add(e);
      return out;
    }
    var bras = 0;
    for (final (cote, sys, dia) in [('gauche', systoliqueG, diastoliqueG), ('droit', systoliqueD, diastoliqueD)]) {
      if (sys.trim().isEmpty && dia.trim().isEmpty) continue;
      bras++;
      if (sys.trim().isEmpty || dia.trim().isEmpty) {
        out.add('Tension du bras $cote : saisissez la systolique ET la diastolique.');
        continue;
      }
      final es = validerValeur(sys, parametre, nom: 'Systolique (bras $cote)');
      final ed = validerValeur(dia, parametre, nom: 'Diastolique (bras $cote)');
      if (es != null) out.add(es);
      if (ed != null) out.add(ed);
      if (es == null && ed == null && lireNombre(dia)! >= lireNombre(sys)!) {
        out.add('Tension du bras $cote : la diastolique doit être inférieure à la systolique.');
      }
    }
    if (bras == 0) out.add('Saisissez la tension d\'au moins un bras (gauche ou droit).');
    return out;
  }

  /// Corps JSON (à n'envoyer que si [erreurs] est vide).
  Map<String, dynamic> toJson() {
    String deux(int v) => v.toString().padLeft(2, '0');
    final jour = '${date.year}-${deux(date.month)}-${deux(date.day)}T${deux(date.hour)}:${deux(date.minute)}';
    final corps = <String, dynamic>{'parametreId': parametre.id, 'date': jour};
    if (commentaire.trim().isNotEmpty) corps['commentaire'] = commentaire.trim();
    if (parametre.tension) {
      Map<String, dynamic>? bras(String s, String d) =>
          s.trim().isEmpty || d.trim().isEmpty ? null : {'systolique': lireNombre(s), 'diastolique': lireNombre(d)};
      final g = bras(systoliqueG, diastoliqueG), dr = bras(systoliqueD, diastoliqueD);
      if (g != null) corps['gauche'] = g;
      if (dr != null) corps['droite'] = dr;
    } else {
      corps['valeur'] = lireNombre(valeur);
    }
    return corps;
  }

}

/// Contrôle des allergies (texte libre).
String? validerAllergies(String texte) =>
    texte.trim().length > maxAllergies ? 'Allergies : $maxAllergies caractères au plus (${texte.trim().length} saisis).' : null;

/// 4.10.1 — date de naissance saisie « JJ/MM/AAAA » (ajout d'une date absente, POST client/{id}/identite) : mêmes
/// refus que le serveur (DossierClientService.completerIdentite et, 4.10.2, remplacerNaissance) : illisible, à venir,
/// avant 1900, plus de 130 ans. Null si elle est recevable.
String? validerNaissance(String saisie, {DateTime? maintenant}) => _naissance(saisie, maintenant ?? DateTime.now()).$1;

/// La date de naissance saisie (JJ/MM/AAAA), ou null si elle n'est pas recevable.
DateTime? lireNaissance(String saisie, {DateTime? maintenant}) => _naissance(saisie, maintenant ?? DateTime.now()).$2;

(String?, DateTime?) _naissance(String saisie, DateTime maintenant) {
  final s = saisie.trim();
  if (s.isEmpty) return ('Saisissez la date de naissance (JJ/MM/AAAA).', null);
  final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(s);
  if (m == null) return ('Date de naissance illisible : JJ/MM/AAAA attendu.', null);
  final j = int.parse(m[1]!), mo = int.parse(m[2]!), a = int.parse(m[3]!);
  final d = DateTime(a, mo, j);
  if (mo < 1 || mo > 12 || j < 1 || d.month != mo || d.day != j) return ('Cette date n\'existe pas (JJ/MM/AAAA).', null);
  if (d.isAfter(DateTime(maintenant.year, maintenant.month, maintenant.day))) {
    return ('La date de naissance ne peut pas être dans le futur.', null);
  }
  // 4.10.2 : âge au plus 130 ans (AGE_MAX du serveur, contrôle de la modification).
  var age = maintenant.year - a;
  if (maintenant.month < mo || (maintenant.month == mo && maintenant.day < j)) age--;
  if (age > 130) return ('La date de naissance donne plus de 130 ans.', null);
  if (a < 1900) return ('Date de naissance improbable (avant 1900).', null);
  return (null, d);
}
