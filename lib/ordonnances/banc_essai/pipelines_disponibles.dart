// lib/ordonnances/banc_essai/pipelines_disponibles.dart
// Pipelines proposés au banc d'essai : la référence (scan actuel) d'abord, puis les candidats
// des étapes O2–O4 (ajoutés ici au fil des étapes).
import 'package:prestige_vente_app/ordonnances/banc_essai/pipeline_ordonnance.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';

List<PipelineOrdonnance> pipelinesBanc(ProductPageSearch recherche) => [
      PipelineTexteCatalogue.reference(recherche),
    ];
