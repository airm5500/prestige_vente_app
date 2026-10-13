// lib/posos/posos_models.dart
// Analyse posologie (routes v1/posos/status et v1/posos/analyse de Prestige).
// Aide à la dispensation : jamais présentée comme un avis médical définitif.
// Mode démonstration (Posos non configuré) : résultats NON réels, signalés par un bandeau permanent.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/serveur/json_tolerant.dart';

/// Avertissement affiché sous tout résultat.
const String avertissementAnalyse =
    'Aide à la dispensation : ces alertes ne remplacent ni l\'avis du pharmacien ni celui du prescripteur.';

/// État de la passerelle Posos (GET v1/posos/status).
class PososStatut {
  final bool configuree;
  final String mode;
  const PososStatut({required this.configuree, required this.mode});

  factory PososStatut.fromJson(Map<String, dynamic> j) => PososStatut(configuree: booleen(j['configuree']), mode: txt(j['mode']).toLowerCase());

  /// Résultats non réels : mode démonstration déclaré, ou Posos non configuré (le serveur passe alors en démonstration).
  bool get demonstration => mode == 'demonstration' || mode == 'démonstration' || !configuree;
}

/// Niveaux de gravité, du plus grave au moins grave (même classement que le serveur, PososDemonstration.rang
/// et PososResultat.estMajeure ; une gravité inconnue n'est jamais minimisée).
enum NiveauGravite {
  contreIndication('Contre-indication', Color(0xFF9B1C1C), Color(0xFFFDECEC), Icons.dangerous),
  majeure('Majeure / déconseillée', Color(0xFFB45309), Color(0xFFFFF1D6), Icons.warning_amber),
  aVerifier('À vérifier', Color(0xFFB45309), Color(0xFFFFF1D6), Icons.help_outline),
  precaution('Précaution d\'emploi', Color(0xFF1F4F8F), Color(0xFFE3ECF7), Icons.info_outline),
  aPrendreEnCompte('À prendre en compte', Color(0xFF3D4B60), Color(0xFFE6EBF2), Icons.visibility),
  information('Information', Color(0xFF3D4B60), Color(0xFFF2F4F8), Icons.notes);

  final String libelle;
  final Color encre;
  final Color fond;
  final IconData icone;
  const NiveauGravite(this.libelle, this.encre, this.fond, this.icone);

  static NiveauGravite classer(String gravite, {bool estMajeure = false}) {
    final g = gravite.toLowerCase();
    if (g.contains('contre-indi') || g.contains('contre indi') || g.contains('contraindicat')) return contreIndication;
    if (g.contains('majeur') || g.contains('major') || g.contains('déconseill') || g.contains('deconseill') || g.contains('sévère') ||
        g.contains('severe') || g.contains('critique') || g.contains('high')) {
      return majeure;
    }
    if (g.contains('précaution') || g.contains('precaution')) return precaution;
    if (g.contains('prendre en compte')) return aPrendreEnCompte;
    if (g.contains('information') || g.contains('info') || g.contains('mineur') || g.contains('minor') || g.contains('faible') || g.contains('low')) {
      return information;
    }
    if (g.contains('modéré') || g.contains('modere') || g.contains('moderate') || g.contains('surveillance')) return precaution;
    // Gravité absente ou inconnue : jamais minimisée.
    return estMajeure ? majeure : aVerifier;
  }
}

/// Produit équivalent en rayon proposé par Prestige.
class EquivalentPosos {
  final String nom;
  final String cip;
  final int? prix;
  final int? stock;
  const EquivalentPosos({required this.nom, this.cip = '', this.prix, this.stock});

  factory EquivalentPosos.fromJson(Map<String, dynamic> j) =>
      EquivalentPosos(nom: txtOuNull(j['nom']) ?? txt(j['libelle']), cip: txt(j['cip']), prix: entier(j['prix']), stock: entier(j['stock']));
}

class AlertePosos {
  final String type;
  final String gravite;
  final String libelle;
  final String recommandation;
  final bool majeure;
  final List<String> produits;
  final List<String> proposer;
  final List<EquivalentPosos> equivalents;

  const AlertePosos({
    this.type = '',
    this.gravite = '',
    required this.libelle,
    this.recommandation = '',
    this.majeure = true,
    this.produits = const [],
    this.proposer = const [],
    this.equivalents = const [],
  });

  factory AlertePosos.fromJson(Map<String, dynamic> j) => AlertePosos(
        type: txt(j['type']),
        gravite: txt(j['gravite']),
        libelle: txtOuNull(j['libelle']) ?? 'Alerte sans libellé',
        recommandation: txt(j['recommandation']),
        // Absent : prudence (le serveur considère une alerte inconnue comme majeure).
        majeure: j.containsKey('majeure') ? booleen(j['majeure']) : true,
        produits: textes(j['produits']),
        proposer: textes(j['proposer']),
        equivalents: [for (final o in objets(j['equivalents'])) EquivalentPosos.fromJson(o)]..removeWhere((e) => e.nom.isEmpty),
      );

  NiveauGravite get niveau => NiveauGravite.classer(gravite, estMajeure: majeure);
}

/// Produit analysé (envoyé, ou relu par le serveur pour une vente).
class ProduitAnalyse {
  final String nom;
  final String cip;
  final int? quantite;
  final String posologie;
  const ProduitAnalyse({required this.nom, this.cip = '', this.quantite, this.posologie = ''});

  factory ProduitAnalyse.fromJson(Map<String, dynamic> j) =>
      ProduitAnalyse(nom: txt(j['nom']), cip: txt(j['cip']), quantite: entier(j['quantite']), posologie: txt(j['posologie']));

  Map<String, dynamic> toJson() => {
        'nom': nom,
        if (cip.isNotEmpty) 'cip': cip,
        if (quantite != null && quantite! > 0) 'quantite': quantite,
        if (posologie.trim().isNotEmpty) 'posologie': posologie.trim(),
      };
}

/// Contexte du patient (facultatif) : affine l'analyse.
class ContextePatient {
  final int? age;
  final String sexe; // '', 'M', 'F'
  final bool grossesse;
  final bool allaitement;
  final bool insuffisanceRenale;
  final bool insuffisanceHepatique;
  final int? poids;

  const ContextePatient({
    this.age,
    this.sexe = '',
    this.grossesse = false,
    this.allaitement = false,
    this.insuffisanceRenale = false,
    this.insuffisanceHepatique = false,
    this.poids,
  });

  bool get vide => age == null && sexe.isEmpty && !grossesse && !allaitement && !insuffisanceRenale && !insuffisanceHepatique && poids == null;

  /// null si vide : le serveur reprend alors le contexte de l'ordonnance éventuelle.
  Map<String, dynamic>? toJson() => vide
      ? null
      : {
          if (age != null) 'age': age,
          if (sexe.isNotEmpty) 'sexe': sexe,
          'grossesse': grossesse,
          'allaitement': allaitement,
          'insuffisanceRenale': insuffisanceRenale,
          'insuffisanceHepatique': insuffisanceHepatique,
          if (poids != null) 'poids': poids,
        };
}

/// Contrôle de l'âge saisi (années) : null si valable ou vide.
String? validerAge(String saisie) {
  final s = saisie.trim();
  if (s.isEmpty) return null;
  final v = int.tryParse(s);
  if (v == null || !RegExp(r'^\d+$').hasMatch(s)) return 'Âge : nombre entier d\'années.';
  if (v > 120) return 'Âge : 120 ans au plus.';
  return null;
}

/// Contrôle du poids saisi (kg entiers, comme le serveur) : null si valable ou vide.
String? validerPoids(String saisie) {
  final s = saisie.trim();
  if (s.isEmpty) return null;
  final v = int.tryParse(s);
  if (v == null || !RegExp(r'^\d+$').hasMatch(s)) return 'Poids : nombre entier de kg.';
  if (v < 1 || v > 300) return 'Poids : entre 1 et 300 kg.';
  return null;
}

/// Résultat d'une analyse.
class ResultatPosos {
  final bool disponible;
  final String message;
  final int nombreMajeures;
  final List<AlertePosos> alertes;
  final List<String> produitsNonReconnus;
  final bool demonstration;
  final String avertissement;
  final List<ProduitAnalyse> venteProduits;

  const ResultatPosos({
    required this.disponible,
    this.message = '',
    this.nombreMajeures = 0,
    this.alertes = const [],
    this.produitsNonReconnus = const [],
    this.demonstration = false,
    this.avertissement = '',
    this.venteProduits = const [],
  });

  factory ResultatPosos.fromJson(Map<String, dynamic> j) {
    final alertes = [for (final o in objets(j['alertes'])) AlertePosos.fromJson(o)];
    // Du plus grave au moins grave (ordre stable sinon).
    final tri = [for (var i = 0; i < alertes.length; i++) (i, alertes[i])]
      ..sort((a, b) {
        final c = a.$2.niveau.index.compareTo(b.$2.niveau.index);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    return ResultatPosos(
      disponible: j.containsKey('disponible') ? booleen(j['disponible']) : true,
      message: txt(j['message']),
      nombreMajeures: entier(j['nombreMajeures']) ?? alertes.where((a) => a.majeure).length,
      alertes: [for (final t in tri) t.$2],
      produitsNonReconnus: textes(j['produitsNonReconnus']),
      demonstration: booleen(j['demonstration']),
      avertissement: txt(j['avertissement']),
      venteProduits: [for (final o in objets(j['venteProduits'])) ProduitAnalyse.fromJson(o)]..removeWhere((p) => p.nom.isEmpty),
    );
  }

  /// Nombre d'alertes par niveau (affichage du résumé).
  Map<NiveauGravite, int> get parNiveau {
    final m = <NiveauGravite, int>{};
    for (final a in alertes) {
      m[a.niveau] = (m[a.niveau] ?? 0) + 1;
    }
    return m;
  }
}
