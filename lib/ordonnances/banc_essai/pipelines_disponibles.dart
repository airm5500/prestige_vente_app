// lib/ordonnances/banc_essai/pipelines_disponibles.dart
// Pipelines proposés au banc d'essai : la référence (scan actuel) d'abord, puis les candidats
// des étapes O2–O4 (ajoutés ici au fil des étapes).
import 'package:prestige_vente_app/ordonnances/banc_essai/pipeline_ordonnance.dart';
import 'package:prestige_vente_app/ordonnances/o2/decoupage_ordonnance.dart';
import 'package:prestige_vente_app/ordonnances/o2/preparation_page.dart';
import 'package:prestige_vente_app/services/ocr_service.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';

List<PipelineOrdonnance> pipelinesBanc(ProductPageSearch recherche, {LecteurTexte? lecteur}) => [
      PipelineTexteCatalogue.reference(recherche, lecteur: lecteur),
      ...candidatsO2(recherche, lecteur: lecteur),
    ];

/// Candidats O2 : découpage par lignes numérotées, avec ou sans amélioration de l'image.
/// (La zone des médicaments est un choix manuel : elle n'est pas rejouée au banc, page entière.)
List<PipelineOrdonnance> candidatsO2(ProductPageSearch recherche, {LecteurTexte? lecteur, PreparationImage? preparation}) => [
      PipelineTexteCatalogue(
        id: 'o2',
        libelle: 'O2 lignes numérotées',
        lecteur: lecteur ?? OcrService.readImageFile,
        decoupage: DecoupageOrdonnance.extraire,
        recherche: recherche,
      ),
      PipelineTexteCatalogue(
        id: 'o2_image',
        libelle: 'O2 lignes numérotées + image améliorée',
        lecteur: lecteur ?? OcrService.readImageFile,
        decoupage: DecoupageOrdonnance.extraire,
        recherche: recherche,
        preparation: preparation ?? (chemin) => PreparationPage.preparerFichier(chemin),
      ),
    ];
