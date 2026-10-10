// lib/ordonnances/banc_essai/score_banc.dart
// Banc d'essai des ordonnances (O1) : vérité terrain et score « proposé vs attendu ».
// Pur Dart : par ordonnance trouvés / manqués / faux positifs ; global rappel, précision,
// ordonnances entièrement correctes (« 9/15 »).
import 'dart:convert';

import 'package:prestige_vente_app/ordonnances/banc_essai/normalisation_produit.dart';

/// Un produit attendu (saisi par le pharmacien).
class ProduitAttendu {
  final String nom;
  final String? posologie;
  final int? quantite;
  const ProduitAttendu(this.nom, {this.posologie, this.quantite});

  factory ProduitAttendu.fromJson(Map<String, dynamic> j) =>
      ProduitAttendu(j['nom'] as String, posologie: j['posologie'] as String?, quantite: (j['quantite'] as num?)?.toInt());

  Map<String, dynamic> toJson() => {'nom': nom, if (posologie != null) 'posologie': posologie, if (quantite != null) 'quantite': quantite};
}

/// Vérité d'une ordonnance (indexée par nom de fichier, ex. « ordonnance (3).jpeg »).
class VeriteOrdonnance {
  final String fichier;
  final List<ProduitAttendu> produits;

  /// Vérité non encore saisie : l'ordonnance est exclue du score (« vérité à compléter »).
  final bool aCompleter;

  /// Autre photo d'une ordonnance déjà dans le jeu (fichier d'origine) : exclue du score.
  final String? doublonDe;
  final String? remarque;

  const VeriteOrdonnance(this.fichier, this.produits, {this.aCompleter = false, this.doublonDe, this.remarque});

  bool get scorable => !aCompleter && doublonDe == null && produits.isNotEmpty;
}

/// Jeu de vérité terrain (asset JSON, sans aucune donnée patient / médecin).
class VeriteTerrain {
  final Map<String, VeriteOrdonnance> ordonnances;
  const VeriteTerrain(this.ordonnances);

  static const asset = 'assets/ordonnances/verite_terrain.json';

  factory VeriteTerrain.fromJsonString(String s) {
    final j = jsonDecode(s) as Map<String, dynamic>;
    final ords = j['ordonnances'] as Map<String, dynamic>;
    return VeriteTerrain({
      for (final e in ords.entries)
        cleFichier(e.key): VeriteOrdonnance(
          e.key,
          [for (final p in (e.value['produits'] as List? ?? const [])) ProduitAttendu.fromJson(p as Map<String, dynamic>)],
          aCompleter: e.value['aCompleter'] == true,
          doublonDe: e.value['doublonDe'] as String?,
          remarque: e.value['remarque'] as String?,
        ),
    });
  }

  /// Clé de recherche d'un fichier : nom seul, minuscules, sans extension
  /// (« /storage/…/Ordonnance (3).JPG » → « ordonnance (3) »).
  static String cleFichier(String chemin) {
    final nom = chemin.split(RegExp(r'[\\/]')).last.toLowerCase().trim();
    return nom.replaceFirst(RegExp(r'\.(jpe?g|png|webp|heic|bmp)$'), '');
  }

  VeriteOrdonnance? pour(String chemin) => ordonnances[cleFichier(chemin)];
}

/// Score d'une ordonnance.
class ScoreOrdonnance {
  final String fichier;

  /// null : pas de vérité (fichier inconnu ou vérité à compléter) → exclue du score global.
  final VeriteOrdonnance? verite;
  final List<String> proposes;

  /// Paires (attendu, proposé) retrouvées.
  final List<(ProduitAttendu, String)> trouves;
  final List<ProduitAttendu> manques;
  final List<String> fauxPositifs;

  /// Erreur du pipeline (lecture impossible…), sinon null.
  final String? erreur;

  const ScoreOrdonnance({
    required this.fichier,
    required this.verite,
    required this.proposes,
    this.trouves = const [],
    this.manques = const [],
    this.fauxPositifs = const [],
    this.erreur,
  });

  bool get compte => verite != null && verite!.scorable;
  int get attendus => compte ? verite!.produits.length : 0;

  /// Tout trouvé, aucun faux positif.
  bool get entierementCorrecte => compte && erreur == null && manques.isEmpty && fauxPositifs.isEmpty;

  String get statut {
    if (verite == null) return 'Pas de vérité terrain';
    if (verite!.doublonDe != null) return 'Doublon de ${verite!.doublonDe}';
    if (!verite!.scorable) return 'Vérité à compléter';
    if (erreur != null) return 'Erreur';
    return '${trouves.length}/${verite!.produits.length}';
  }
}

/// Score global d'un passage du banc.
class ScoreGlobal {
  final List<ScoreOrdonnance> ordonnances;
  const ScoreGlobal(this.ordonnances);

  Iterable<ScoreOrdonnance> get _comptees => ordonnances.where((o) => o.compte);

  int get nbComptees => _comptees.length;
  int get nbAttendus => _comptees.fold(0, (s, o) => s + o.attendus);
  int get nbTrouves => _comptees.fold(0, (s, o) => s + o.trouves.length);
  int get nbFauxPositifs => _comptees.fold(0, (s, o) => s + o.fauxPositifs.length);
  int get nbCorrectes => _comptees.where((o) => o.entierementCorrecte).length;

  /// Part des produits attendus retrouvés (0…1).
  double get rappel => nbAttendus == 0 ? 0 : nbTrouves / nbAttendus;

  /// Part des propositions justes (0…1) ; 1 si rien n'est proposé (aucune erreur).
  double get precision => nbTrouves + nbFauxPositifs == 0 ? 1 : nbTrouves / (nbTrouves + nbFauxPositifs);

  /// « 9/15 » : ordonnances entièrement correctes / ordonnances avec vérité.
  String get correctes => '$nbCorrectes/$nbComptees';

  static String pourcent(double v) => '${(v * 100).round()} %';
}

class BancScore {
  BancScore._();

  /// Compare les produits [proposes] par le pipeline à la [verite] (null : pas de vérité).
  /// Appariement glouton : chaque attendu prend la première proposition non utilisée qui lui correspond ;
  /// une proposition en double compte comme faux positif.
  static ScoreOrdonnance evaluer(String fichier, VeriteOrdonnance? verite, List<String> proposes, {String? erreur}) {
    if (verite == null || !verite.scorable) {
      return ScoreOrdonnance(fichier: fichier, verite: verite, proposes: proposes, erreur: erreur);
    }
    final norm = [for (final p in proposes) NormalisationProduit.normaliser(p)];
    final utilise = List<bool>.filled(proposes.length, false);
    final trouves = <(ProduitAttendu, String)>[];
    final manques = <ProduitAttendu>[];
    for (final a in verite.produits) {
      final na = NormalisationProduit.normaliser(a.nom);
      var idx = -1;
      for (var i = 0; i < norm.length; i++) {
        if (!utilise[i] && NormalisationProduit.correspond(na, norm[i])) {
          idx = i;
          break;
        }
      }
      if (idx < 0) {
        manques.add(a);
      } else {
        utilise[idx] = true;
        trouves.add((a, proposes[idx]));
      }
    }
    final fauxPositifs = [for (var i = 0; i < proposes.length; i++) if (!utilise[i]) proposes[i]];
    return ScoreOrdonnance(
      fichier: fichier,
      verite: verite,
      proposes: proposes,
      trouves: trouves,
      manques: manques,
      fauxPositifs: fauxPositifs,
      erreur: erreur,
    );
  }
}
