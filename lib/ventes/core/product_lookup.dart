// lib/ventes/core/product_lookup.dart
// Recherche produit « professionnelle » :
// - un CODE scanné (CIP, EAN-13, GTIN, DataMatrix) cherche le produit EXACT, avec les variantes
//   (EAN-13 34009… → CIP7, GTIN-14 → EAN-13), quel que soit le nombre de produits qui commencent pareil ;
// - un TEXTE donne une liste par pages : on connaît le total (« 30 sur 252 ») et on charge la suite,
//   au lieu de couper la liste en silence.
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/services/datamatrix_parser.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';

/// Une page de résultats du serveur (`total` = nombre total de produits correspondants).
class ProductPage {
  final List<ProductSearchResult> items;
  final int total;
  const ProductPage(this.items, this.total);
}

typedef ProductPageSearch = Future<VenteResult<ProductPage>> Function(String query, int start, int limit);

/// Résultat d'une recherche par code.
class CodeLookup {
  /// Produit trouvé exactement (null si aucun ou plusieurs possibles).
  final ProductSearchResult? exact;

  /// Produits candidats (à proposer si pas de correspondance exacte).
  final List<ProductSearchResult> candidates;

  /// Codes essayés (pour le message « introuvable »).
  final List<String> tried;
  const CodeLookup({this.exact, this.candidates = const [], this.tried = const []});
}

class ProductLookup {
  ProductLookup._();

  /// Taille d'une page de résultats texte.
  static const int pageSize = 50;

  static final RegExp _digits = RegExp(r'^\d+$');

  /// La saisie ressemble-t-elle à un code scanné (et non à un nom) ?
  static bool looksLikeCode(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return false;
    if (v.contains('\u001d') || v.startsWith(']d2') || v.startsWith('01') && v.length > 16) return true;
    return _digits.hasMatch(v) && v.length >= 7;
  }

  /// Codes à essayer, du plus précis au plus large.
  static List<String> codeCandidates(String raw) {
    final v = raw.replaceAll(RegExp(r'[\x00-\x1C\x1E\x1F\x7F]'), '').trim();
    if (v.isEmpty) return const [];
    final out = <String>[];
    final dm = DataMatrixParser.parse(v);
    if (dm != null && dm.productSearchQueries.isNotEmpty) out.addAll(dm.productSearchQueries);
    final d = v.replaceAll(RegExp(r'\s'), '');
    if (_digits.hasMatch(d)) {
      out.add(d);
      // GTIN-14 commençant par 0 → EAN-13.
      final ean = d.length == 14 && d.startsWith('0') ? d.substring(1) : d;
      if (ean != d) out.add(ean);
      // EAN-13 / CIP13 français 34009 + CIP7 + clé.
      if (ean.length == 13 && ean.startsWith('34009')) out.add(ean.substring(5, 12));
    } else if (out.isEmpty) {
      out.add(d);
    }
    return out.toSet().toList();
  }

  /// Recherche par code : renvoie le produit exact s'il existe, sinon les candidats.
  static Future<VenteResult<CodeLookup>> byCode(String raw, ProductPageSearch search) async {
    final codes = codeCandidates(raw);
    final candidates = <String, ProductSearchResult>{};
    VenteResult<ProductPage>? lastFailure;
    for (final code in codes) {
      final r = await search(code, 0, pageSize);
      if (r is! VenteOk<ProductPage>) {
        lastFailure = r;
        continue;
      }
      final items = r.value.items;
      final exact = items.where((p) => p.intCIP.trim() == code).toList();
      if (exact.length == 1) return VenteOk(CodeLookup(exact: exact.first, tried: codes));
      // Un seul produit pour ce code (correspondance EAN côté serveur) : c'est lui.
      if (items.length == 1 && r.value.total <= 1) return VenteOk(CodeLookup(exact: items.first, tried: codes));
      for (final p in items) {
        candidates[p.lgFAMILLEID] = p;
      }
    }
    if (candidates.isEmpty && lastFailure != null) return lastFailure.map((_) => const CodeLookup());
    return VenteOk(CodeLookup(candidates: candidates.values.toList(), tried: codes));
  }
}

/// Liste de résultats texte chargée par pages.
class ProductPager {
  final ProductPageSearch _search;
  final String query;
  final List<ProductSearchResult> items = [];
  int total = 0;
  bool _loading = false;
  String? error;

  ProductPager(this._search, this.query);

  bool get hasMore => items.length < total;
  bool get loading => _loading;

  /// Charge la page suivante ; renvoie false en cas d'échec (message dans [error]).
  Future<bool> loadMore() async {
    if (_loading || (total > 0 && !hasMore)) return true;
    _loading = true;
    error = null;
    try {
      final r = await _search(query, items.length, ProductLookup.pageSize);
      if (r is VenteOk<ProductPage>) {
        final known = {for (final p in items) p.lgFAMILLEID};
        items.addAll(r.value.items.where((p) => known.add(p.lgFAMILLEID)));
        // Total du serveur ; s'il manque ou si la page est incomplète, on s'arrête là.
        total = r.value.items.length < ProductLookup.pageSize ? items.length : (r.value.total > items.length ? r.value.total : items.length);
        return true;
      }
      error = r.message;
      return false;
    } finally {
      _loading = false;
    }
  }
}
