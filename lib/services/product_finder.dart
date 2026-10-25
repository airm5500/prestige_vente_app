// lib/services/product_finder.dart
// Recherche produit des menus hors ventes (Proforma, Dépôt, Ajustement, Péremption, Périmés,
// EAN / Emplacement, Évaluation, Recherche article, Ordonnance) : même logique que les ventes
// (lib/ventes/core/product_lookup.dart) :
// - un CODE (CIP, EAN-13, GTIN, DataMatrix) cherche le produit EXACT avec ses variantes
//   (EAN-13 34009… → CIP7), quel que soit le nombre de produits qui commencent pareil ;
// - un TEXTE donne une liste par pages : « 50 sur 120 », la suite se charge à la demande ;
// - une panne (réseau, session, serveur) n'est jamais annoncée comme « produit introuvable » ;
// - le texte suit le réglage « Commence par » / « Contient » (lib/services/search_mode.dart), jamais un code.
import 'package:dio/dio.dart' show CancelToken, DioException, DioExceptionType;
import 'package:flutter/foundation.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/services/classement_code.dart';
import 'package:prestige_vente_app/services/search_mode.dart';
import 'package:prestige_vente_app/ventes/core/gs1_vente.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';

/// Recherche par pages sur l'[ApiService], au format attendu par [ProductLookup] / [ProductPager].
/// Hors ligne : copie locale du catalogue (lib/horsligne/) ; en ligne : inchangé.
/// [jeton] : requêtes abandonnées quand il est annulé (recherche remplacée par la frappe suivante).
ProductPageSearch apiPageSearch(ApiService api, {CancelToken? jeton}) => offlineAware((query, start, limit) async {
      try {
        Future<ProductPage> f() => api.searchProductsPageOrFail(query, start, limit);
        return VenteOk(await (jeton == null ? f() : ApiService.avecJeton(jeton, f)));
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) return const VenteFailed('Recherche remplacée');
        return VenteFailed('Recherche impossible : ${e.message ?? e.type.name}');
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

  /// Saisie en chiffres : produits dont un code (CIP, CIP13 / CIP7, EAN) commence par la saisie en tête, la
  /// correspondance exacte d'abord, le reste dans l'ordre du serveur ([classerParCode], 4.0.3 F3). Activé pour
  /// Recherche Article, Évaluation Vente et la recherche de l'accueil ; les autres menus gardent l'ordre du serveur.
  final bool classerCodes;

  /// 4.9.1 : ventes Dépôt et Proforma : une étiquette GS1 passe par la lecture GS1 de la vente (lib/ventes/core/
  /// gs1_vente.dart) sans `lotScanne` (leurs routes d'ajout ne s'en servent pas). Faux (autres menus) : inchangé.
  final bool gs1Vente;

  /// 4.9.2 : étiquette étendue (DataMatrix+, QR+) refusée sur l'appareil, même lecture GS1 inactive (Proforma, comme
  /// DevisCtr du web). Faux pour le Dépôt : DepotCtr du web ne la refuse pas ; 4.9.3 : au Dépôt, elle ne passe pas
  /// non plus par le verdict du serveur (qui la refuserait), même lecture active : recherche d'avant.
  final bool etendueRefusee;

  PagedProductSearch(this._api, {this.visible, this.classerCodes = false, this.gs1Vente = false, this.etendueRefusee = false});

  /// 4.9.1 : boîte refusée à la lecture de son étiquette GS1 (message ; aucun produit).
  String? refusGs1;

  /// 4.9.1 : lot différent (avertissement au vendeur ; produit trouvé quand même).
  String? avertissementGs1;

  /// 4.9.4 : étiquette étendue au Dépôt : aucun produit, rien à annoncer (comme le web).
  bool etendueIgnoree = false;

  ProductPager? _pager;
  List<ProductSearchResult> _items = const [];
  int _seq = 0;

  /// Requête de la recherche en cours : annulée par la recherche suivante (une seule en vol).
  CancelToken? _jeton;

  /// Diagnostic (tests) : recherches abandonnées car remplacées.
  int annulees = 0;

  /// Annule la recherche en vol et renvoie le jeton de la nouvelle.
  CancelToken _nouveauJeton() {
    _annuler();
    return _jeton = CancelToken();
  }

  void _annuler() {
    final j = _jeton;
    _jeton = null;
    if (j != null && !j.isCancelled) {
      annulees++;
      j.cancel('Recherche remplacée');
    }
  }

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

  /// Produits visibles, classés par début de code si [classerCodes] (saisie numérique seulement).
  List<ProductSearchResult> _montrer(Iterable<ProductSearchResult> l) {
    final v = l.where(_visible).toList();
    return classerCodes ? classerParCode(v, query, (p) => p.intCIP, autres: (p) => [p.codeEanFabriquant]) : v;
  }

  /// Recherche [raw] : code → produit exact (variantes) ; texte → 1ʳᵉ page.
  /// [asCode] force le mode (sinon : [ProductLookup.looksLikeCode]).
  /// Renvoie false si une recherche plus récente (ou [clear]) l'a remplacée.
  Future<bool> run(String raw, {bool? asCode}) async {
    final seq = ++_seq;
    final q = raw.trim();
    _reset();
    query = q;
    if (q.isEmpty) {
      _annuler();
      return true;
    }
    final search = apiPageSearch(_api(), jeton: _nouveauJeton());
    // 4.9.1 : étiquette GS1 (dépôt, proforma) : verdict de la vente ; lecture inactive, serveur ancien, panne,
    // délai → « comme avant », la recherche ci-dessous est exactement celle d'avant.
    var code = q;
    // 4.9.4 : étiquette étendue au Dépôt (etendueRefusee faux) : comme DepotCtr du web, AUCUN produit et rien de
    // particulier (ni refus, ni verdict, ni « introuvable », ni lecture du GTIN), aucune requête. Proforma : refus
    // local (4.9.2).
    final etendue = Gs1Vente.estEtiquetteEtendue(q);
    if (gs1Vente && etendue && !etendueRefusee) {
      _jeton = null;
      byCode = true;
      etendueIgnoree = true;
      return true;
    }
    if (gs1Vente && (etendue ? etendueRefusee : Gs1Vente.ressembleGs1(q))) {
      final v = await Gs1Vente.instance.verdict(q, lotEnvoye: false, etendueLocale: etendueRefusee);
      if (seq != _seq) return false;
      if (v is Gs1Refus) {
        _jeton = null;
        byCode = true;
        refusGs1 = v.message;
        return true;
      }
      if (v is Gs1Accepte) {
        code = v.code;
        avertissementGs1 = v.avertissement;
      }
    }
    if (asCode ?? ProductLookup.looksLikeCode(q)) {
      byCode = true;
      final r = await ProductLookup.byCode(code, search);
      if (seq != _seq) return false;
      _jeton = null; // terminée : plus rien à annuler
      if (r is! VenteOk<CodeLookup>) {
        error = r.message;
        return true;
      }
      final found = r.value;
      _items = _montrer(found.exact != null ? [found.exact!] : found.candidates);
      if (_items.isEmpty) {
        notFound = codeIntrouvableMessage(code, found.tried);
        avertissementGs1 = null;
      }
      return true;
    }
    final pager = ProductPager(search, q, mode: modeFor(q));
    final ok = await pager.loadMore();
    if (seq != _seq) return false;
    _jeton = null; // terminée : plus rien à annuler
    if (!ok) {
      error = pager.error;
      return true;
    }
    _pager = pager;
    _items = _montrer(pager.items);
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
    final search = apiPageSearch(_api(), jeton: _nouveauJeton());
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
    _items = _montrer(pager.items);
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
    refusGs1 = null;
    avertissementGs1 = null;
    etendueIgnoree = false;
  }

  /// Efface les résultats (et ignore une recherche encore en cours).
  void clear() {
    _seq++;
    _annuler();
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
