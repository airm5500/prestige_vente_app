// lib/accueil/fiche_produit_screen.dart
// Fiche produit ouverte depuis le scan ou la recherche globale de l'accueil.
// Même chemin de données que le menu ANALYSE ARTICLE (lib/screens/analysis) : GET /info?search=<CIP>
// lu par ArticleAnalysis.fromJson (ApiService.fetchArticleAnalysisOrFail), et mêmes informations que la
// fenêtre « Détails de l'Article » (article_analysis_widgets.dart) : stock, prix de vente / d'achat,
// grossiste, emplacement, moyenne 3 mois, quantité vendue 6 mois, graphique des ventes mensuelles.
// - Affichage IMMÉDIAT avec la ligne du résultat (nom, CIP, stock, prix), puis l'analyse en arrière-plan
//   (squelettes), avec un cache mémoire court (60 s) et l'abandon de la requête si l'on quitte la fiche.
// - Le serveur répond : jamais de message d'échec (s'il n'a pas de ligne d'analyse pour ce produit,
//   la fiche le dit sobrement). Vraie erreur : cause précise (code HTTP, délai, réseau) + Réessayer.
// - Hors ligne : données de la copie locale du catalogue (lib/horsligne) avec leur date ;
//   ce qui exige le serveur affiche « Disponible en ligne uniquement » (jamais une erreur).
// - Présentations A (tableau de bord), B (liste compacte), C (parcours guidé), comme l'analyse article.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/article_analysis_model.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/images/photo_produit.dart';
import 'package:prestige_vente_app/images/produit_image_widget.dart';
import 'package:prestige_vente_app/screens/analysis/article_analysis_widgets.dart';
import 'package:prestige_vente_app/screens/product_search/product_search_widgets.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/responsive.dart';

/// Chargement de l'analyse d'un produit (annulable) : null si le serveur n'a aucune ligne pour lui.
typedef ChargeurFiche = Future<ArticleAnalysis?> Function(CancelToken token);

/// Ligne de l'analyse (GET /info?search=CIP, recherche « commence par » sur le CIP ou le nom) qui
/// correspond au produit : même identifiant, sinon même CIP (jamais la ligne d'un autre produit,
/// ex. « 8423349D » renvoyé avec « 8423349 »).
ArticleAnalysis? articleDuProduit(List<ArticleAnalysis> lignes, ProductSearchResult p) {
  final id = p.lgFAMILLEID.trim();
  final cip = p.intCIP.trim();
  return lignes.where((a) => id.isNotEmpty && a.produitId == id).firstOrNull ??
      lignes.where((a) => cip.isNotEmpty && a.codeCip.trim() == cip).firstOrNull;
}

/// Analyse du produit chez l'[ApiService] : même route et même lecture que le menu Analyse article.
ChargeurFiche chargeurFiche(ApiService api, ProductSearchResult p) =>
    (token) async => articleDuProduit(await api.fetchArticleAnalysisOrFail(p.intCIP.trim(), cancelToken: token), p);

/// Cache mémoire court des analyses de fiche : réouverture sans attente, une seule requête
/// à la fois par produit, requête abandonnée quand plus aucune fiche ne l'attend.
/// Seules les réponses du serveur sont gardées (jamais une erreur).
class FicheInfoCache {
  FicheInfoCache({this.duree = const Duration(seconds: 60), DateTime Function()? horloge}) : horloge = horloge ?? DateTime.now;

  /// Cache de l'application.
  static final FicheInfoCache instance = FicheInfoCache();

  final Duration duree;
  final DateTime Function() horloge;
  final Map<String, ({DateTime at, ArticleAnalysis? article})> _connus = {};
  final Map<String, _Demande> _enCours = {};

  /// Requêtes réellement envoyées (diagnostic, tests).
  int requetes = 0;

  /// Requêtes abandonnées (fiche quittée avant la réponse).
  int abandons = 0;

  /// Réponse encore fraîche (null : rien de frais) ; `article` null : le serveur n'a pas de ligne.
  ({ArticleAnalysis? article})? connu(String cle) {
    final e = _connus[cle];
    if (e == null) return null;
    if (horloge().difference(e.at) > duree) {
      _connus.remove(cle);
      return null;
    }
    return (article: e.article);
  }

  /// Analyse de [cle] : fraîche en cache, sinon la requête en cours, sinon une nouvelle requête.
  /// [attendre] faux (préchargement) : la requête ne compte pas d'écran en attente.
  /// Une erreur (ApiLoadException, délai…) est transmise à l'écran, jamais mise en cache.
  Future<ArticleAnalysis?> charger(String cle, ChargeurFiche chargeur, {bool attendre = true}) {
    final c = connu(cle);
    if (c != null) return Future.value(c.article);
    final d = _enCours[cle];
    if (d != null) {
      if (attendre) d.abonnes++;
      return d.future;
    }
    final token = CancelToken();
    requetes++;
    late final _Demande demande;
    final f = Future<ArticleAnalysis?>.sync(() => chargeur(token)).then<ArticleAnalysis?>((a) {
      if (!token.isCancelled) _connus[cle] = (at: horloge(), article: a);
      return a;
    }).whenComplete(() {
      if (identical(_enCours[cle], demande)) _enCours.remove(cle);
    });
    // Préchargement sans écran, requête abandonnée : l'erreur n'est pas « non traitée ».
    f.ignore();
    demande = _Demande(token, f, attendre ? 1 : 0);
    _enCours[cle] = demande;
    return f;
  }

  /// Un écran n'attend plus [cle] : la requête est abandonnée si personne d'autre ne l'attend.
  void lacher(String cle) {
    final d = _enCours[cle];
    if (d == null) return;
    d.abonnes--;
    if (d.abonnes <= 0) {
      abandons++;
      d.token.cancel('Fiche produit quittée');
      _enCours.remove(cle);
    }
  }

  bool enCours(String cle) => _enCours.containsKey(cle);

  void vider() {
    _connus.clear();
    _enCours.clear();
  }
}

class _Demande {
  final CancelToken token;
  final Future<ArticleAnalysis?> future;
  int abonnes;
  _Demande(this.token, this.future, this.abonnes);
}

/// Clé du cache : une source (service : serveur et session) et un produit (identifiant + CIP).
String cleFiche(Object source, ProductSearchResult p) => '${identityHashCode(source)}|${p.lgFAMILLEID}|${p.intCIP.trim()}';

/// Préchargement de l'analyse dès la sélection du produit (pendant l'ouverture de la fiche).
void prechargerFiche(ApiService api, ProductSearchResult p, {FicheInfoCache? cache}) {
  if (p.intCIP.trim().isEmpty || HorsLigne.instance.offline) return;
  (cache ?? FicheInfoCache.instance).charger(cleFiche(api, p), chargeurFiche(api, p), attendre: false);
}

/// Message affiché pour une vraie erreur (cause précise, jamais « fiche introuvable »).
String messageErreurFiche(Object e) {
  if (e is ApiLoadException) return e.message;
  if (e is DioException) return ApiService.analyseErreurMessage(e);
  return 'Analyse indisponible : $e';
}

class FicheProduitScreen extends StatefulWidget {
  final ProductSearchResult produit;

  /// Lignes de l'analyse pour un CIP (tests) ; sinon ApiService.fetchArticleAnalysisOrFail.
  final Future<List<ArticleAnalysis>> Function(String cip)? loadAnalyse;

  /// Cache des analyses (tests) ; par défaut celui de l'application, ou un cache propre à
  /// la fiche si [loadAnalyse] est fourni.
  final FicheInfoCache? cache;

  /// Présentation imposée (tests) ; sinon celle choisie sur l'appareil (A par défaut).
  final ListPresentation? presentation;
  const FicheProduitScreen({super.key, required this.produit, this.loadAnalyse, this.cache, this.presentation});

  @override
  State<FicheProduitScreen> createState() => _FicheProduitScreenState();
}

class _FicheProduitScreenState extends State<FicheProduitScreen> {
  ArticleAnalysis? _article;
  bool _loading = true;

  /// Vraie erreur (cause précise) ; null si le serveur a répondu.
  String? _erreur;

  /// Hors ligne : produit relu dans la copie locale (null : celui reçu).
  ProductSearchResult? _local;
  late final HorsLigne _hl = HorsLigne.instance;
  late bool _offline = _hl.offline;
  late ListPresentation _style = widget.presentation ?? ListPresentation.dashboard;

  late final FicheInfoCache _cache = widget.cache ?? (widget.loadAnalyse != null ? FicheInfoCache() : FicheInfoCache.instance);

  /// Clé de l'analyse attendue (null : aucune).
  String? _attendu;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _hl.monitor.addListener(_onMonitor);
    if (widget.presentation == null) {
      PresentationPrefs.load().then((p) {
        if (mounted && p != _style) setState(() => _style = p);
      });
    }
    _load();
  }

  @override
  void dispose() {
    _hl.monitor.removeListener(_onMonitor);
    _lacher();
    super.dispose();
  }

  /// Fiche quittée (ou rechargée) avant la réponse : la requête n'est plus attendue.
  void _lacher() {
    final cle = _attendu;
    _attendu = null;
    if (cle != null) _cache.lacher(cle);
  }

  /// Passage hors ligne / retour en ligne : la fiche est rechargée depuis la bonne source.
  void _onMonitor() {
    if (!mounted || _hl.offline == _offline) return;
    _offline = _hl.offline;
    _load();
  }

  /// Copie locale : produit à jour (stock connu, prix) et date du catalogue.
  Future<void> _loadLocal() async {
    ProductSearchResult? local;
    try {
      if (!_hl.sync.statsLoaded) await _hl.sync.refreshStats();
      final p = widget.produit;
      final cip = p.intCIP.trim();
      if (cip.isNotEmpty) {
        final page = await _hl.store.searchProducts(cip, 0, 20);
        local = page.items.where((e) => e.lgFAMILLEID == p.lgFAMILLEID && e.intCIP.trim() == cip).firstOrNull ??
            page.items.where((e) => e.intCIP.trim() == cip).firstOrNull;
      }
    } catch (_) {
      local = null;
    }
    if (!mounted) return;
    setState(() {
      _local = local;
      _article = null;
      _loading = false;
      _erreur = null;
    });
  }

  Future<void> _load() async {
    _lacher();
    final seq = ++_seq;
    if (_offline) {
      setState(() {
        _loading = true;
        _erreur = null;
      });
      return _loadLocal();
    }
    final p = widget.produit;
    final Object source = widget.loadAnalyse ?? Provider.of<ApiService>(context, listen: false);
    final cle = cleFiche(source, p);
    // Déjà connu (réouverture, préchargement terminé) ou sans CIP : affiché tout de suite, sans requête.
    final connu = _cache.connu(cle);
    if (connu != null || p.intCIP.trim().isEmpty) {
      setState(() {
        _article = connu?.article;
        _local = null;
        _loading = false;
        _erreur = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _erreur = null;
    });
    final load = widget.loadAnalyse;
    final ChargeurFiche chargeur =
        load != null ? (_) async => articleDuProduit(await load(p.intCIP.trim()), p) : chargeurFiche(source as ApiService, p);
    _attendu = cle;
    ArticleAnalysis? article;
    String? erreur;
    try {
      article = await _cache.charger(cle, chargeur);
    } catch (e) {
      erreur = messageErreurFiche(e);
    }
    if (!mounted || _offline || seq != _seq) return;
    _attendu = null;
    setState(() {
      _article = article;
      _local = null;
      _loading = false;
      _erreur = erreur;
    });
  }

  // ---------------------------------------------------------------------------
  // Données affichées : la ligne du résultat tout de suite, l'analyse dès qu'elle arrive.
  // ---------------------------------------------------------------------------
  ProductSearchResult get _p => _offline ? (_local ?? widget.produit) : widget.produit;
  ArticleAnalysis? get _a => _offline ? null : _article;
  int get _stock => _a?.stock ?? _p.intNUMBERAVAILABLE;
  int get _prix => _a?.prixVente ?? _p.intPRICE;
  String get _nom => _a != null && _a!.libelle.isNotEmpty ? _a!.libelle : _p.strNAME;

  @override
  Widget build(BuildContext context) => switch (_style) {
        ListPresentation.dashboard => _buildDashboard(),
        ListPresentation.compact => _buildCompact(),
        ListPresentation.guided => _buildGuided(),
      };

  // --- A · Tableau de bord ---
  Widget _buildDashboard() => Scaffold(
        backgroundColor: Pal.page,
        body: Column(children: [
          const NavyHeader(title: 'Fiche produit', subtitle: 'Stock, prix, emplacement et ventes'),
          Expanded(
            child: ContentWidth(
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
                ..._avant(),
                SoftCard(child: _entete()),
                const SizedBox(height: 12),
                SoftCard(child: _details()),
                ..._apres(carte: true),
              ]),
            ),
          ),
        ]),
      );

  // --- B · Liste compacte ---
  Widget _buildCompact() => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: Pal.navy,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: const Text('Fiche produit', style: TextStyle(fontWeight: FontWeight.bold, color: Pal.navy)),
          bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider(height: 1, color: Pal.line)),
        ),
        body: ContentWidth(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
            ..._avant(),
            _entete(),
            const Divider(height: 24, color: Pal.line),
            _details(),
            ..._apres(carte: false),
          ]),
        ),
      );

  // --- C · Parcours guidé ---
  Widget _buildGuided() => Scaffold(
        backgroundColor: const Color(0xFFEEF2F7),
        body: Column(children: [
          NavyHeader(title: 'Fiche produit', rounded: false, children: [
            StepsBar(active: _loading ? 1 : 2, steps: const [
              (title: 'Scanner', detail: 'ou rechercher', onTap: null),
              (title: 'Produit', detail: 'stock, prix', onTap: null),
              (title: 'Analyse', detail: 'ventes, grossiste', onTap: null),
            ]),
          ]),
          Expanded(
            child: ContentWidth(
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
                ..._avant(),
                SoftCard(band: Pal.navy, padding: const EdgeInsets.all(16), child: _entete(grand: true)),
                const SizedBox(height: 12),
                SoftCard(child: _details()),
                ..._apres(carte: true),
              ]),
            ),
          ),
        ]),
      );

  /// Note hors ligne et image du produit (B2 : serveur, cache disque ; rien s'il n'en a pas).
  List<Widget> _avant() => [
        if (_offline) ...[_noteHorsLigne(), const SizedBox(height: 12)],
        Center(
          child: ProduitImage(
            familleId: _p.lgFAMILLEID,
            taille: 180,
            rayon: BorderRadius.circular(16),
            placeholder: const SizedBox.shrink(),
            prioritaire: true,
          ),
        ),
      ];

  /// Erreur précise, ventes mensuelles, bouton photo.
  List<Widget> _apres({required bool carte}) {
    Widget enCarte(Widget w) => carte ? SoftCard(child: w) : w;
    return [
      if (_erreur != null && !_loading && !_offline) ...[
        const SizedBox(height: 12),
        enCarte(_erreurBloc()),
      ],
      if (!_offline && (_loading || _a != null)) ...[
        if (carte) const SizedBox(height: 12) else const Divider(height: 24, color: Pal.line),
        enCarte(_ventes()),
      ],
      // B2 : « Photo du produit » (réglage administrateur désactivé par défaut, droit du serveur).
      Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Align(alignment: Alignment.centerLeft, child: PhotoProduitBouton(familleId: _p.lgFAMILLEID))),
    ];
  }

  /// Nom, Stock / Prix de vente / Moy. 3 mois (comme la carte de l'analyse article).
  Widget _entete({bool grand = false}) {
    final a = _a;
    final stockColor = _stock <= 0 ? const Color(0xFFB91C1C) : Pal.green;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(orDash(_nom), style: TextStyle(fontSize: grand ? 21 : 20, fontWeight: FontWeight.bold, color: Pal.ink)),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _figure('$_stock', 'En stock', stockColor)),
        const SizedBox(width: 8),
        Expanded(child: _figure('${Constants.formatNumber(_prix)} F', 'Prix de vente', Pal.ink)),
        if (!_offline) ...[
          const SizedBox(width: 8),
          Expanded(
            child: _loading
                ? _figure('…', 'Moy. 3 mois', Pal.muted, key: const ValueKey('fiche-squelette-moyenne'))
                : _figure(a == null ? '—' : a.moyenne.toStringAsFixed(2), 'Moy. 3 mois', Pal.ink),
          ),
        ],
      ]),
    ]);
  }

  /// CIP, famille, puis les informations de l'analyse article (mêmes libellés que « Détails de l'Article »).
  Widget _details() {
    final a = _a;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DetailLine('Code CIP', orDash(_p.intCIP), bold: true),
      if (_p.strLIBELLEE.trim().isNotEmpty) DetailLine('Famille', orDash(_p.strLIBELLEE)),
      if (_loading) ...[
        // Squelettes : la fiche reste lisible, l'analyse arrive en arrière-plan.
        _squelette('Emplacement'),
        _squelette('Grossiste'),
        _squelette("Prix d'achat"),
      ] else if (_offline) ...[
        const DetailLine('Emplacement', 'Disponible en ligne uniquement'),
        const DetailLine('Grossiste', 'Disponible en ligne uniquement'),
      ] else if (a != null) ...[
        for (final (label, value) in articleInfos(a))
          if (label != 'Prix de vente') DetailLine(label, value, key: ValueKey('fiche-info-$label')),
        // Stock rayon / réserve (« — » si non géré en réserve), seuils, total, alerte (GET /info).
        for (final (label, value) in stockReserveInfos(a.stock, a.reserve)) DetailLine(label, value, key: ValueKey('fiche-reserve-$label')),
        if (a.reserve.aReapprovisionner(a.stock))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Align(alignment: Alignment.centerRight, child: PastilleReappro(reserve: a.reserve, rayon: a.stock)),
          ),
      ] else if (_erreur == null)
        // Le serveur a répondu sans ligne d'analyse pour ce produit : ce n'est pas une panne.
        const Padding(
          key: ValueKey('fiche-sans-analyse'),
          padding: EdgeInsets.only(top: 8),
          child: Text("Pas d'analyse sur le serveur pour ce produit (emplacement, grossiste ou ventes non renseignés).",
              style: TextStyle(color: Pal.muted, fontSize: 13)),
        ),
    ]);
  }

  /// « Évolution des ventes mensuelles » (graphique de l'analyse article).
  Widget _ventes() {
    final a = _a;
    if (_loading || a == null) {
      return Column(key: const ValueKey('fiche-squelette-ventes'), crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Évolution des ventes mensuelles:', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Container(height: 150, decoration: BoxDecoration(color: const Color(0xFFE3E8EF), borderRadius: BorderRadius.circular(10))),
      ]);
    }
    return ArticleVentesChart(key: const ValueKey('fiche-ventes'), article: a);
  }

  Widget _erreurBloc() => Row(key: const ValueKey('fiche-erreur'), children: [
        const Icon(Icons.cloud_off, color: Color(0xFFB45309)),
        const SizedBox(width: 10),
        Expanded(child: Text(_erreur ?? '', style: const TextStyle(color: Pal.ink))),
        TextButton(onPressed: _load, child: const Text('Réessayer')),
      ]);

  /// Ligne en attente de l'analyse (libellé + barre grise).
  Widget _squelette(String label) => Padding(
        key: ValueKey('fiche-squelette-$label'),
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          SizedBox(width: 110, child: Text(label, style: const TextStyle(color: Pal.muted, fontSize: 14))),
          const SizedBox(width: 8),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: FractionallySizedBox(
                widthFactor: 0.6,
                child: Container(height: 14, decoration: BoxDecoration(color: const Color(0xFFE3E8EF), borderRadius: BorderRadius.circular(7))),
              ),
            ),
          ),
        ]),
      );

  /// « Hors ligne — données du catalogue du JJ/MM HH:MM ».
  Widget _noteHorsLigne() {
    final at = _hl.sync.catalogueAt;
    final texte = at == null
        ? 'Hors ligne — aucun catalogue local sur cet appareil'
        : 'Hors ligne — données du catalogue du ${HorsLigne.formatDate(at)}';
    return Container(
      key: const Key('fiche_hors_ligne'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        const Icon(Icons.cloud_off, size: 18, color: Color(0xFF334155)),
        const SizedBox(width: 8),
        Expanded(
          child: Text('$texte. Stock connu à cette date.',
              style: const TextStyle(fontSize: 13, color: Color(0xFF334155), fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Widget _figure(String value, String label, Color color, {Key? key}) => Container(
        key: key,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: Pal.page, borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          ),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Pal.muted)),
        ]),
      );
}
