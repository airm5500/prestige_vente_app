// lib/ordonnances/banc_essai/pipeline_ordonnance.dart
// Pipeline de lecture d'ordonnance « image → produits proposés », interface commune pour comparer
// au banc d'essai la RÉFÉRENCE (scan actuel) et les CANDIDATS des étapes O2–O4.
//
// Un pipeline ne renvoie que les noms de produits proposés (et le nombre de lignes lues) :
// jamais le texte reconnu, qui peut contenir des noms de patient ou de médecin.
import 'dart:io';

import 'package:prestige_vente_app/services/ocr_service.dart';
import 'package:prestige_vente_app/services/prescription_matcher.dart';
import 'package:prestige_vente_app/services/prescription_parser.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';

/// Résultat d'un pipeline sur une image.
class ResultatPipeline {
  /// Noms des produits du catalogue proposés (dans l'ordre des lignes).
  final List<String> produits;

  /// Lignes « médicament » détectées (rapprochées ou non).
  final int lignesDetectees;

  /// Lignes détectées sans produit du catalogue.
  final int lignesSansProduit;

  /// Panne (lecture, recherche…), sinon null.
  final String? erreur;

  const ResultatPipeline({required this.produits, this.lignesDetectees = 0, this.lignesSansProduit = 0, this.erreur});
}

/// Lecture d'une ordonnance (image) jusqu'aux produits proposés.
abstract class PipelineOrdonnance {
  /// Identifiant stable (historique des scores), ex. « reference », « o2 ».
  String get id;

  /// Nom affiché, ex. « Référence (scan actuel) ».
  String get libelle;

  Future<ResultatPipeline> analyser(String cheminImage);
}

/// Lit le texte d'une image (lignes regroupées). Par défaut : ML Kit ([OcrService.readImageFile]).
typedef LecteurTexte = Future<List<String>> Function(String cheminImage);

/// Prépare l'image avant lecture (renvoie le chemin d'un fichier TEMPORAIRE, supprimé après lecture).
typedef PreparationImage = Future<String> Function(String chemin);

/// Rapproche une ligne du catalogue : nom du produit retenu, ou null. Par défaut : [PrescriptionMatcher.match].
typedef RapprochementLigne = Future<({String? produit, String? panne})> Function(PrescriptionLine ligne);

/// Découpe le texte lu en lignes « médicament ». Par défaut : [PrescriptionParser.extract].
typedef DecoupageLignes = List<PrescriptionLine> Function(List<String> lignes);

/// Pipeline « texte lu → lignes → correspondance catalogue », paramétrable étape par étape
/// (lecture, découpage, recherche) : la référence et les candidats ne diffèrent que par une étape.
class PipelineTexteCatalogue implements PipelineOrdonnance {
  @override
  final String id;
  @override
  final String libelle;
  final LecteurTexte lecteur;
  final DecoupageLignes decoupage;

  /// Recherche par pages dans le catalogue (en ligne : serveur ; hors ligne : copie locale).
  final ProductPageSearch recherche;

  /// Préparation de l'image avant lecture (ex. contraste, O2) ; renvoie le chemin d'un fichier temporaire.
  final PreparationImage? preparation;

  /// Correspondance catalogue (ex. O3) ; null : [PrescriptionMatcher.match] sur [recherche].
  final RapprochementLigne? rapprochement;

  const PipelineTexteCatalogue({
    required this.id,
    required this.libelle,
    required this.lecteur,
    required this.decoupage,
    required this.recherche,
    this.preparation,
    this.rapprochement,
  });

  /// Le scan d'ordonnance ACTUEL, sans aucune modification : ML Kit, [PrescriptionParser.extract],
  /// puis [PrescriptionMatcher.match] (mêmes appels que l'écran Ordonnance).
  factory PipelineTexteCatalogue.reference(ProductPageSearch recherche, {LecteurTexte? lecteur}) => PipelineTexteCatalogue(
        id: 'reference',
        libelle: 'Référence (scan actuel)',
        lecteur: lecteur ?? OcrService.readImageFile,
        decoupage: PrescriptionParser.extract,
        recherche: recherche,
      );

  @override
  Future<ResultatPipeline> analyser(String cheminImage) async {
    List<String> texte;
    String? temporaire;
    try {
      if (preparation != null) temporaire = await preparation!(cheminImage);
      texte = await lecteur(temporaire ?? cheminImage);
    } catch (e) {
      return ResultatPipeline(produits: const [], erreur: 'Lecture impossible : ${e.runtimeType}');
    } finally {
      if (temporaire != null && temporaire != cheminImage) {
        try {
          final f = File(temporaire);
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
    }
    final lignes = decoupage(texte);
    final produits = <String>[];
    var sans = 0;
    String? panne;
    for (final l in lignes) {
      final ({String? produit, String? panne}) r;
      if (rapprochement != null) {
        r = await rapprochement!(l);
      } else {
        final m = await PrescriptionMatcher.match(l, recherche);
        r = (produit: m.chosen?.strNAME, panne: m.failure);
      }
      if (r.produit == null) {
        sans++;
        panne ??= r.panne;
      } else {
        produits.add(r.produit!);
      }
    }
    return ResultatPipeline(
      produits: produits,
      lignesDetectees: lignes.length,
      lignesSansProduit: sans,
      erreur: panne == null ? null : 'Recherche catalogue : $panne',
    );
  }
}
