// lib/services/product_finder.dart
// Recherche produit des menus hors ventes (Proforma, Dépôt, Ajustement, Péremption, Périmés,
// EAN / Emplacement, Évaluation, Recherche article, Ordonnance) : même logique que les ventes
// (lib/ventes/core/product_lookup.dart) :
// - un CODE (CIP, EAN-13, GTIN, DataMatrix) cherche le produit EXACT avec ses variantes
//   (EAN-13 34009… → CIP7), quel que soit le nombre de produits qui commencent pareil ;
// - un TEXTE donne une liste par pages : « 50 sur 120 », la suite se charge à la demande ;
// - une panne (réseau, session, serveur) n'est jamais annoncée comme « produit introuvable » ;
// - le texte suit le réglage « Commence par » / « Contient » (lib/services/search_mode.dart), jamais un code.
import 'package:flutter/foundation.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/services/search_mode.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';

/// Recherche par pages sur l'[ApiService], au format attendu par [ProductLookup] / [ProductPager].
/// Hors ligne : copie locale du catalogue (lib/horsligne/) ; en ligne : inchangé.
ProductPageSearch apiPageSearch(ApiService api) => offlineAware((query, start, limit) async {
      try {
        return VenteOk(await api.searchProductsPageOrFail(query, start, limit));
      } on ApiLoadException catch (e) {
        return VenteFailed(e.message);
      } catch (e) {
        return VenteFailed('Recherche impossible : $e');
      }
    });

/// « Code X introuvable (essayé aussi Y) ».
String codeIntrouvableMessage(String code, List<String> tried) {
  final c = code.trim();
  final others = tried.where((t) => t != c).toList();
  return 'Code $c introuvable${others.isEmpty ? '' : ' (essayé aussi ${others.join(', ')})'}';
}

/// État d'une recherche produit (code exact ou liste texte par pages), partagé par les menus.
class PagedProductSearch {
  final ApiService Function() _api;

  /// Produits à montrer (ex. masquer les « RV ») ; les autres restent comptés dans le total.
  final bool Function(ProductSearchResult)? visible;

  PagedProductSearch(this._api, {this.visible});

  ProductPager? _pager;
  List<ProductSearchResult> _items = const [];
  int _seq = 0;

  /// Dernière saisie recherchée.
  String query = '';

  /// La dernière recherche était une recherche par code.
  bool byCode = false;

  /// Panne de la recherche (réseau, serveur…) : ≠ « introuvable ».
  String? error;

  /// Code inconnu : « Code X introuvable (essayé aussi Y) ».
  String? notFound;

  /// Chargement de la suite en cours / en échec.
  bool loadingMore = false;
  String? loadMoreError;

  List<ProductSearchResult> get items => _items;

  /// Liste texte chargée par pages (null pour une recherche par code).
  ProductPager? get pager => _pager;

  /// Produits chargés / total du serveur (liste texte).
  int get loaded => _pager?.items.length ?? _items.length;
  int get total => _pager?.total ?? _items.length;
  bool get hasMore => _pager?.hasMore ?? false;

  /// « 50 sur 120 » à afficher (liste texte plus longue qu'une page).
  bool get showCount => _pager != null && (hasMore || total > ProductLookup.pageSize);
  String get countLabel => '$loaded sur $total';

  bool _visible(ProductSearchResult p) => visible?.call(p) ?? true;

  /// Recherche [raw] : code → produit exact (variantes) ; texte → 1ʳᵉ page.
  /// [asCode] force le mode (sinon : [ProductLookup.looksLikeCode]).
  /// Renvoie false si une recherche plus récente (ou [clear]) l'a remplacée.
  Future<bool> run(String raw, {bool? asCode}) async {
    final seq = ++_seq;
    final q = raw.trim();
    _reset();
    query = q;
    if (q.isEmpty) return true;
    final search = apiPageSearch(_api());
    if (asCode ?? ProductLookup.looksLikeCode(q)) {
      byCode = true;
      final r = await ProductLookup.byCode(q, search);
      if (seq != _seq) return false;
      if (r is! VenteOk<CodeLookup>) {
        error = r.message;
        return true;
      }
      final found = r.value;
      _items = (found.exact != null ? [found.exact!] : found.candidates).where(_visible).toList();
      if (_items.isEmpty) notFound = codeIntrouvableMessage(q, found.tried);
      return true;
    }
    final pager = ProductPager(search, q, mode: modeFor(q));
    final ok = await pager.loadMore();
    if (seq != _seq) return false;
    if (!ok) {
      error = pager.error;
      return true;
    }
    _pager = pager;
    _items = pager.items.where(_visible).toList();
    return true;
  }

  /// Recherche par une liste de codes déjà calculés (ex. ceux d'un DataMatrix), du plus précis au plus large :
  /// produit exact dès qu'un code le désigne, sinon les produits trouvés par ces codes.
  Future<bool> runCodes(List<String> codes) async {
    final seq = ++_seq;
    _reset();
    byCode = true;
    query = codes.isEmpty ? '' : codes.first;
    if (codes.isEmpty) return true;
    final search = apiPageSearch(_api());
    final candidates = <String, ProductSearchResult>{};
    String? failure;
    for (final code in codes) {
      final r = await search(code, 0, ProductLookup.pageSize);
      if (seq != _seq) return false;
      if (r is! VenteOk<ProductPage>) {
        failure = r.message;
        continue;
      }
      final found = r.value.items;
      final exact = found.where((p) => p.intCIP.trim() == code).toList();
      if (exact.length == 1 || (found.length == 1 && r.value.total <= 1)) {
        _items = (exact.length == 1 ? exact : found).where(_visible).toList();
        if (_items.isEmpty) notFound = codeIntrouvableMessage(codes.first, codes);
        return true;
      }
      for (final p in found) {
        candidates[p.lgFAMILLEID] = p;
      }
    }
    _items = candidates.values.where(_visible).toList();
    if (_items.isEmpty) {
      if (candidates.isEmpty && failure != null) {
        error = failure;
      } else {
        notFound = codeIntrouvableMessage(codes.first, codes);
      }
    }
    return true;
  }

  /// Charge la page suivante de la liste texte ; false en cas d'échec (message dans [loadMoreError]).
  Future<bool> loadMore() async {
    final pager = _pager;
    if (pager == null || !pager.hasMore || loadingMore) return true;
    final seq = _seq;
    loadingMore = true;
    loadMoreError = null;
    final ok = await pager.loadMore();
    if (seq != _seq) return false;
    loadingMore = false;
    if (!ok) loadMoreError = pager.error ?? 'Chargement de la suite impossible';
    _items = pager.items.where(_visible).toList();
    return ok;
  }

  void _reset() {
    _pager = null;
    _items = const [];
    query = '';
    byCode = false;
    error = null;
    notFound = null;
    loadingMore = false;
    loadMoreError = null;
  }

  /// Efface les résultats (et ignore une recherche encore en cours).
  void clear() {
    _seq++;
    _reset();
  }
}

/// Pour les providers : « Charger la suite » avec rafraîchissement de l'écran.
mixin PagedProductSearchHost on ChangeNotifier {
  PagedProductSearch get productSearch;

  Future<void> loadMoreProducts() async {
    final s = productSearch;
    if (!s.hasMore || s.loadingMore) return;
    final f = s.loadMore();
    notifyListeners(); // affiche le chargement
    await f;
    notifyListeners();
  }
}
