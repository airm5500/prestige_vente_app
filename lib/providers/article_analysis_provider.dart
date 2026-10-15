// lib/providers/article_analysis_provider.dart
// Analyse article en deux temps (4.1.2, retours du pharmacien : « doli » / « ibex » tournaient puis « Délai dépassé ») :
// 1. LISTE : recherche RAPIDE GET /vente/search (même recherche que l'accueil : anti-rebond à l'écran, une seule
//    requête en vol — la frappe suivante ANNULE la précédente —, code exact avec variantes, liste texte par pages,
//    classement par début de code lib/services/classement_code.dart). Aucun GET /info pendant la frappe : sur le
//    serveur, GET /info?search= calcule les ventes de 6 mois et les dernières ventes / achats / inventaires de TOUS
//    les produits qui commencent par la saisie (docs/serveur/DEMANDE_PERFORMANCE_INFO.md).
// 2. DÉTAIL : quand un produit est CHOISI, GET /info?search=<son CIP exact> (une seule ligne retenue : même
//    identifiant, sinon même CIP — jamais celle d'un autre produit), délai ApiService.delaiInfo (30 s), cache court
//    partagé avec la fiche produit (FicheInfoCache), requête abandonnée si le détail est fermé avant la réponse.
// Jamais « rien » : chargement, résultats, « aucun produit » ou erreur précise avec Réessayer.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prestige_vente_app/accueil/fiche_produit_screen.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/article_analysis_model.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/services/product_finder.dart';

class ArticleAnalysisProvider with ChangeNotifier, PagedProductSearchHost {
  ApiService _apiService;

  /// Cache des détails (GET /info d'un produit) ; par défaut celui de la fiche produit.
  final FicheInfoCache _cache;

  ArticleAnalysisProvider(this._apiService, {FicheInfoCache? cache}) : _cache = cache ?? FicheInfoCache.instance;

  void updateApiService(ApiService api) => _apiService = api;

  /// Recherche rapide (GET /vente/search), saisie numérique classée par début de code.
  late final PagedProductSearch _search = PagedProductSearch(() => _apiService, classerCodes: true);

  @override
  PagedProductSearch get productSearch => _search;

  /// Produits trouvés (liste rapide : nom, CIP, stock, prix).
  List<ProductSearchResult> get results => _search.items;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// Panne de la dernière recherche (cause précise) ; null si le serveur a répondu.
  String? get error => _search.error;

  /// Texte de la dernière recherche envoyée ('' : aucune).
  String _query = '';
  String get query => _query;

  /// Code introuvable (« Code X introuvable (essayé aussi Y) »).
  String? get notFound => _search.notFound;

  /// Le serveur a répondu sans aucun produit pour [query].
  bool get aucunResultat => !_isLoading && error == null && _query.isNotEmpty && results.isEmpty;

  /// Diagnostic (tests) : recherches envoyées / annulées car remplacées.
  int requetes = 0;
  int get annulees => _search.annulees;

  void clear() {
    _search.clear();
    _query = '';
    _isLoading = false;
    notifyListeners();
  }

  /// Relance la dernière recherche (bouton Réessayer).
  Future<void> reessayer() => searchArticles(_query);

  Future<void> searchArticles(String query) async {
    final q = query.trim();
    // Règle métier : on lance la recherche si au moins 2 caractères
    if (q.length < 2) {
      clear();
      return;
    }
    _query = q;
    _isLoading = true;
    notifyListeners();
    requetes++;
    final courante = await _search.run(q);
    if (!courante) return; // une recherche plus récente (ou l'effacement) a pris la main
    _isLoading = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Détail d'un produit choisi : GET /info?search=<CIP exact>
  // ---------------------------------------------------------------------------

  String _cle(ProductSearchResult p) => cleFiche(_apiService, p);

  /// Analyse du produit [p] (ventes, grossiste, emplacement, réserve) : null si le serveur n'a pas de ligne pour
  /// lui. Erreur précise (ApiLoadException, délai) transmise à l'écran.
  Future<ArticleAnalysis?> chargerDetail(ProductSearchResult p) {
    if (p.intCIP.trim().isEmpty) return Future.value(null);
    final delai = delaiMaxFiche();
    return _cache.charger(_cle(p), chargeurFiche(_apiService, p)).timeout(delai, onTimeout: () {
      lacherDetail(p);
      throw ApiLoadException('Délai dépassé : pas de réponse du serveur en ${delai.inSeconds} s (GET /info). Réessayez.');
    });
  }

  /// Détail encore en mémoire (réouverture sans attente), sinon null.
  ({ArticleAnalysis? article})? detailConnu(ProductSearchResult p) => _cache.connu(_cle(p));

  /// Le détail de [p] n'est plus affiché : la requête est abandonnée si personne d'autre ne l'attend.
  void lacherDetail(ProductSearchResult p) => _cache.lacher(_cle(p));

  @override
  void dispose() {
    _search.clear();
    super.dispose();
  }
}
