// lib/services/prescription_matcher.dart
// Rapprochement d'une ligne d'ordonnance avec le catalogue (stock) : logique du scan d'ordonnance,
// sortie de l'écran pour être partagée, À L'IDENTIQUE, par l'écran Ordonnance et le banc d'essai
// (lib/ordonnances/banc_essai/). Toute amélioration passe par un pipeline candidat mesuré au banc.
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/services/prescription_parser.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';

/// Qualité du rapprochement ligne d'ordonnance -> produit du stock.
enum PrescriptionMatchKind { exactCip, exactName, toVerify, none }

class PrescriptionMatchResult {
  final ProductSearchResult? chosen;
  final PrescriptionMatchKind kind;
  final List<ProductSearchResult> alternatives;

  /// Panne de la recherche (≠ produit introuvable), sinon null.
  final String? failure;

  const PrescriptionMatchResult({this.chosen, this.kind = PrescriptionMatchKind.none, this.alternatives = const [], this.failure});
}

class PrescriptionMatcher {
  PrescriptionMatcher._();

  /// Nombre maximal de produits examinés pour un nom (pages de 50).
  static const int maxNameResults = 200;

  /// 1) CIP lu -> uniquement le produit ayant exactement ce CIP ;
  /// 2) sinon nom identique -> ce produit ;
  /// 3) sinon meilleur candidat, marqué "à vérifier" (les autres restent accessibles via "Changer").
  static Future<PrescriptionMatchResult> match(PrescriptionLine line, ProductPageSearch search) async {
    ProductSearchResult? chosen;
    var match = PrescriptionMatchKind.none;
    var alternatives = <ProductSearchResult>[];
    String? failure; // panne (≠ produit introuvable)

    final cip = line.cip;
    if (cip != null) {
      // Code exact, quel que soit le nombre de produits qui commencent pareil
      // (avec les variantes : EAN-13 34009… → CIP7). Seul un produit portant l'un de ces codes est retenu.
      final r = await ProductLookup.byCode(cip, search);
      final found = r.valueOrNull;
      if (found == null) failure = r.message;
      final exact = found?.exact;
      if (exact != null && found!.tried.contains(exact.intCIP.trim())) {
        chosen = exact;
        match = PrescriptionMatchKind.exactCip;
      }
    }

    if (chosen == null) {
      List<ProductSearchResult> results = [];
      for (final q in PrescriptionParser.searchQueries(line)) {
        // Plusieurs pages (jusqu'à maxNameResults produits) au lieu des 30 premiers seulement.
        // Toujours « commence par », texte envoyé tel quel (pas de réglage « Contient ») : la
        // correspondance (1ʳᵉ requête non vide, score, limite) suppose cette recherche.
        final pager = ProductPager(search, q);
        while (pager.items.length < maxNameResults && (pager.total == 0 || pager.hasMore)) {
          if (!await pager.loadMore()) {
            failure = pager.error;
            break;
          }
          if (pager.total == 0) break;
        }
        results = List.of(pager.items);
        if (results.isNotEmpty) break;
      }
      final wanted = PrescriptionParser.comparableName(line.text);
      final sameName = results.where((p) => PrescriptionParser.comparableName(p.strNAME) == wanted).toList();
      if (sameName.length == 1) {
        chosen = sameName.first;
        match = PrescriptionMatchKind.exactName;
      } else {
        final scored = [for (final p in results) MapEntry(p, PrescriptionParser.score(line, p.strNAME))]
          ..sort((a, b) {
            final byScore = b.value.compareTo(a.value);
            return byScore != 0 ? byScore : b.key.intNUMBERAVAILABLE.compareTo(a.key.intNUMBERAVAILABLE);
          });
        final relevant = scored.where((e) => e.value > 0).map((e) => e.key).toList();
        if (relevant.isNotEmpty) {
          chosen = relevant.first;
          match = PrescriptionMatchKind.toVerify;
          alternatives = relevant.skip(1).take(15).toList();
        }
      }
      if (chosen != null && alternatives.isEmpty) {
        final c = chosen;
        alternatives = results.where((p) => p.lgFAMILLEID != c.lgFAMILLEID).take(15).toList();
      }
    }
    return PrescriptionMatchResult(chosen: chosen, kind: match, alternatives: alternatives, failure: failure);
  }
}
