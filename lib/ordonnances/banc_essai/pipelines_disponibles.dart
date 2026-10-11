// lib/ordonnances/banc_essai/pipelines_disponibles.dart
// Pipelines proposés au banc d'essai : la référence (scan actuel) d'abord, puis les candidats
// des étapes O2–O4 (ajoutés ici au fil des étapes).
import 'package:prestige_vente_app/ordonnances/banc_essai/pipeline_ordonnance.dart';
import 'package:prestige_vente_app/ordonnances/o2/decoupage_ordonnance.dart';
import 'package:prestige_vente_app/ordonnances/o2/preparation_page.dart';
import 'package:prestige_vente_app/ordonnances/o3/catalogue_o3.dart';
import 'package:prestige_vente_app/ordonnances/o3/correspondance_o3.dart';
import 'package:prestige_vente_app/ordonnances/o4/apprentissage_o4.dart';
import 'package:prestige_vente_app/ordonnances/o4/banc_o4.dart';
import 'package:prestige_vente_app/services/prescription_matcher.dart';
import 'package:prestige_vente_app/services/ocr_service.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';

List<PipelineOrdonnance> pipelinesBanc(
  ProductPageSearch recherche, {
  LecteurTexte? lecteur,
  Future<CorrespondanceO3> Function()? correspondanceO3,
  Future<SourceApprentissages> Function()? apprentissages,
}) =>
    [
      PipelineTexteCatalogue.reference(recherche, lecteur: lecteur),
      ...candidatsO2(recherche, lecteur: lecteur),
      candidatO3(recherche, lecteur: lecteur, correspondance: correspondanceO3),
      candidatO3Appris(recherche, lecteur: lecteur, correspondance: correspondanceO3, apprentissages: apprentissages),
      candidatO3Appris(recherche, lecteur: lecteur, correspondance: correspondanceO3, apprentissages: apprentissages, fragments: true),
    ];

/// Candidat O4 : O3 + apprentissages par correction (réels ; ou simulés en deux passages, voir banc_o4.dart).
/// [fragments] (O3b) : + propositions par fragments sûrs, après les correspondances complètes.
PipelineO3Appris candidatO3Appris(
  ProductPageSearch recherche, {
  LecteurTexte? lecteur,
  Future<CorrespondanceO3> Function()? correspondance,
  Future<SourceApprentissages> Function()? apprentissages,
  bool fragments = false,
}) =>
    PipelineO3Appris(
      id: fragments ? 'o3_fragments' : 'o3_appris',
      libelle: fragments ? 'O3 + fragments + apprentissages' : 'O3 + apprentissages',
      fragments: fragments,
      lecteur: lecteur,
      recherche: recherche,
      correspondance: correspondance ?? () => CatalogueO3.creer(recherche),
      apprentissagesReels: apprentissages,
    );

/// Candidat O3 : découpage O2 + correspondance catalogue améliorée (1ʳᵉ proposition au-dessus du seuil).
/// Une ligne avec CIP garde le rapprochement exact d'origine. Le catalogue est chargé une fois par passage.
PipelineOrdonnance candidatO3(
  ProductPageSearch recherche, {
  LecteurTexte? lecteur,
  Future<CorrespondanceO3> Function()? correspondance,
}) {
  Future<CorrespondanceO3>? o3;
  return PipelineTexteCatalogue(
    id: 'o3',
    libelle: 'O3 correspondance catalogue',
    lecteur: lecteur ?? OcrService.readImageFile,
    decoupage: DecoupageOrdonnance.extraire,
    recherche: recherche,
    rapprochement: (ligne) async {
      if (ligne.cip != null) {
        final m = await PrescriptionMatcher.match(ligne, recherche);
        if (m.kind == PrescriptionMatchKind.exactCip) return (produit: m.chosen!.strNAME, panne: null);
      }
      final r = await (await (o3 ??= (correspondance ?? () => CatalogueO3.creer(recherche))())).proposer(ligne);
      return (produit: r.meilleure?.produit.strNAME, panne: r.panne);
    },
  );
}

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
