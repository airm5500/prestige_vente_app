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

/// Cache mémoire court des analyses de fiche (jamais sur disque) : réouverture sans attente, une seule requête
/// à la fois par produit. 4.3.2 (lenteur signalée par le pharmacien) :
/// - une fiche ou un détail FERMÉ avant la réponse ne fait plus abandonner la requête : le serveur la calcule de
///   toute façon (l'abandon côté téléphone ne l'arrête pas) ; sa réponse remplit le cache et la réouverture du même
///   produit est immédiate (avant : nouvelle requête, nouvelle attente complète) ;
/// - LOT de la saisie ([chargerSaisie]) : GET /info?search=<saisie> lu dès que la liste rapide est affichée ; il
///   couvre tous les produits dont le CIP ou le nom commence par la saisie (même règle que le serveur). Au clic,
///   un produit couvert est pris dans le lot (déjà arrivé : immédiat ; en route : on attend CE lot, jamais une
///   2ᵉ requête en parallèle) ; sinon GET /info par son CIP exact.
/// Seules les réponses du serveur sont gardées (jamais une erreur).
class FicheInfoCache {
  FicheInfoCache({this.duree = const Duration(minutes: 2), DateTime Function()? horloge}) : horloge = horloge ?? DateTime.now;

  /// Cache de l'application.
  static final FicheInfoCache instance = FicheInfoCache();

  final Duration duree;
  final DateTime Function() horloge;
  final Map<String, ({DateTime at, ArticleAnalysis? article})> _connus = {};
  final Map<String, _Demande> _enCours = {};

  /// Lot de la saisie en cours, par source (service : serveur et session).
  final Map<String, _Lot> _lots = {};

  /// Dernier lot arrivé, par source : une saisie qui le prolonge (« dolip » après « doli ») est déjà couverte.
  final Map<String, _Lot> _lotsFaits = {};

  /// Requêtes par produit réellement envoyées (diagnostic, tests).
  int requetes = 0;

  /// Lots (GET /info d'une saisie) réellement envoyés / annulés car devenus inutiles (diagnostic, tests).
  int lots = 0;
  int lotsAnnules = 0;

  /// Détails servis par un lot (sans requête propre au produit).
  int servisParLot = 0;

  /// Écrans fermés avant la réponse (la requête continue et remplit le cache).
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

  /// Comme [connu], en cherchant aussi dans le dernier lot arrivé qui couvre [p] (ouverture sans attente).
  ({ArticleAnalysis? article})? connuPour(String cle, ProductSearchResult p) {
    final c = connu(cle);
    if (c != null) return c;
    final fait = _lotFrais(sourceDeCle(cle));
    if (fait == null || !fait.couvre(p)) return null;
    final a = articleDuProduit(fait.lignes!, p);
    if (a == null) return null;
    _connus[cle] = (at: fait.at!, article: a);
    servisParLot++;
    return (article: a);
  }

  /// Analyse de [cle] : fraîche en cache, sinon la requête en cours, sinon le lot de la saisie qui couvre
  /// [produit], sinon une nouvelle requête. [attendre] faux (préchargement) : aucun écran en attente.
  /// Une erreur (ApiLoadException, délai…) est transmise à l'écran, jamais mise en cache.
  Future<ArticleAnalysis?> charger(String cle, ChargeurFiche chargeur, {bool attendre = true, ProductSearchResult? produit}) {
    final c = connu(cle);
    if (c != null) return Future.value(c.article);
    final d = _enCours[cle];
    if (d != null) {
      if (attendre) d.abonnes++;
      return d.future;
    }
    // Dernier lot arrivé (encore frais) qui couvre ce produit : sa ligne, sans requête (même règle que GET /info
    // par le CIP : même identifiant, sinon même CIP). Produit absent du lot : requête par son CIP (prudence).
    final fait = produit == null ? null : _lotFrais(sourceDeCle(cle));
    final duLot = fait != null && fait.couvre(produit!) ? articleDuProduit(fait.lignes!, produit) : null;
    if (duLot != null) {
      _connus[cle] = (at: fait!.at!, article: duLot);
      servisParLot++;
      return Future.value(duLot);
    }
    final token = CancelToken();
    final lot = produit == null ? null : _lots[sourceDeCle(cle)];
    late final _Demande demande;
    Future<ArticleAnalysis?> envoyer() {
      requetes++;
      return Future<ArticleAnalysis?>.sync(() => chargeur(token)).then<ArticleAnalysis?>((a) {
        if (!token.isCancelled) _connus[cle] = (at: horloge(), article: a);
        return a;
      });
    }

    final Future<ArticleAnalysis?> source;
    if (lot != null && lot.couvre(produit!)) {
      // Le lot en route contient ce produit : on l'attend (aucune 2ᵉ requête) ; s'il échoue ou ne l'a pas,
      // requête par le CIP exact.
      lot.attentes++;
      source = lot.fin.then((_) {
        lot.attentes--;
        final lignes = lot.lignes;
        // Lot en échec (délai, réseau…) : même cause affichée, avec Réessayer (qui lira le CIP exact) ; jamais une
        // 2ᵉ attente complète enchaînée derrière un serveur déjà trop lent. Lot abandonné : CIP exact.
        final erreur = lot.erreur;
        if (erreur != null) throw erreur;
        final a = lignes == null ? null : articleDuProduit(lignes, produit);
        if (a == null) return envoyer(); // lot abandonné, ou produit absent du lot : CIP exact
        _connus[cle] = (at: lot.at ?? horloge(), article: a);
        servisParLot++;
        return a;
      });
    } else {
      source = envoyer();
    }
    final f = source.whenComplete(() {
      if (identical(_enCours[cle], demande)) _enCours.remove(cle);
    });
    // Préchargement sans écran : l'erreur n'est pas « non traitée ».
    f.ignore();
    demande = _Demande(token, f, attendre ? 1 : 0);
    _enCours[cle] = demande;
    return f;
  }

  /// Un écran n'attend plus [cle] (fiche ou détail fermé) : la requête CONTINUE (le serveur la calcule de toute
  /// façon) et sa réponse reste en cache pour une réouverture immédiate. Elle reste bornée par son délai.
  void lacher(String cle) {
    final d = _enCours[cle];
    if (d == null) return;
    if (d.abonnes > 0) d.abonnes--;
    if (d.abonnes <= 0) abandons++;
  }

  /// Délai dépassé pour [cle] : la requête est abandonnée et oubliée, « Réessayer » en enverra une nouvelle
  /// (jamais rattachée à une requête restée sans réponse).
  void abandonner(String cle) {
    final d = _enCours.remove(cle);
    if (d == null) return;
    abandons++;
    d.token.cancel('Délai dépassé');
  }

  bool enCours(String cle) => _enCours.containsKey(cle);

  /// Lot GET /info?search=<[saisie]> pour [source] (3 caractères au moins). Rien n'est envoyé si la saisie est
  /// déjà couverte par le lot en route ou par le dernier lot arrivé (saisie qui le prolonge). Un lot devenu
  /// inutile (autre saisie) est abandonné s'il n'est attendu par aucun détail.
  Future<void> chargerSaisie(String source, String saisie, Future<List<ArticleAnalysis>> Function(CancelToken token) lecture) {
    final s = saisieLot(saisie);
    if (s.length < longueurMiniLot) return Future.value();
    final enRoute = _lots[source];
    if (enRoute != null && s.startsWith(enRoute.saisie)) return enRoute.fin;
    final fait = _lotFrais(source);
    if (fait != null && s.startsWith(fait.saisie)) return Future.value();
    if (enRoute != null) lacherSaisie(source);
    final token = CancelToken();
    lots++;
    final lot = _Lot(s, token);
    _lots[source] = lot;
    lot.fin = Future<List<ArticleAnalysis>>.sync(() => lecture(token)).then<void>((lignes) {
      if (lot.abandonne) return;
      lot
        ..lignes = lignes
        ..at = horloge();
      _lotsFaits[source] = lot;
    }).catchError((Object e) {
      if (!lot.abandonne) lot.erreur = e;
    }).whenComplete(() {
      if (identical(_lots[source], lot)) _lots.remove(source);
    });
    return lot.fin;
  }

  /// Le lot de [source] n'est plus utile (saisie effacée, liste trop longue, écran quitté) : abandonné s'il
  /// n'est attendu par aucun détail.
  void lacherSaisie(String source) {
    final lot = _lots[source];
    if (lot == null || lot.attentes > 0) return;
    _lots.remove(source);
    lotsAnnules++;
    lot.abandonne = true;
    lot.token.cancel('Saisie remplacée');
  }

  /// Dernier lot arrivé pour [source], s'il est encore frais.
  _Lot? _lotFrais(String source) {
    final l = _lotsFaits[source];
    if (l == null || l.at == null) return null;
    if (horloge().difference(l.at!) > duree) {
      _lotsFaits.remove(source);
      return null;
    }
    return l;
  }

  /// Lot en route pour [source] (tests).
  String? lotEnRoute(String source) => _lots[source]?.saisie;

  void vider() {
    _connus.clear();
    _enCours.clear();
    _lots.clear();
    _lotsFaits.clear();
  }
}

/// Longueur minimale d'une saisie pour lire son lot GET /info (2 lettres : trop de produits).
const int longueurMiniLot = 3;

/// Nombre maximal de produits de la liste rapide pour lire le lot de la saisie (au-delà : détail par CIP au clic).
const int produitsMaxLot = 30;

/// Saisie normalisée comme la recherche « commence par » du serveur (casse ignorée).
String saisieLot(String saisie) => saisie.trim().toUpperCase();

class _Lot {
  final String saisie;
  final CancelToken token;
  late final Future<void> fin;

  /// Détails qui attendent ce lot (il n'est alors jamais abandonné).
  int attentes = 0;

  /// Lignes reçues et heure de réception (null : pas encore arrivé, ou en échec).
  List<ArticleAnalysis>? lignes;
  DateTime? at;

  /// Échec de la lecture (transmis aux détails qui l'attendaient).
  Object? erreur;

  /// Abandonné par l'application (saisie remplacée) : sa réponse éventuelle est ignorée.
  bool abandonne = false;
  _Lot(this.saisie, this.token);

  /// Produit renvoyé par GET /info?search=<saisie> : CIP ou nom qui commence par la saisie.
  bool couvre(ProductSearchResult p) =>
      saisie.isNotEmpty && (p.intCIP.trim().toUpperCase().startsWith(saisie) || p.strNAME.trim().toUpperCase().startsWith(saisie));
}

class _Demande {
  final CancelToken token;
  final Future<ArticleAnalysis?> future;
  int abonnes;
  _Demande(this.token, this.future, this.abonnes);
}

/// Source d'une clé du cache (service : serveur et session).
String cleSource(Object source) => '${identityHashCode(source)}';

String sourceDeCle(String cle) {
  final i = cle.indexOf('|');
  return i < 0 ? cle : cle.substring(0, i);
}

/// Clé du cache : une source (service : serveur et session) et un produit (identifiant + CIP).
String cleFiche(Object source, ProductSearchResult p) => '${cleSource(source)}|${p.lgFAMILLEID.trim()}|${p.intCIP.trim()}';

/// Préchargement de l'analyse dès la sélection du produit (pendant l'ouverture de la fiche).
void prechargerFiche(ApiService api, ProductSearchResult p, {FicheInfoCache? cache}) {
  if (p.intCIP.trim().isEmpty || HorsLigne.instance.offline) return;
  (cache ?? FicheInfoCache.instance).charger(cleFiche(api, p), chargeurFiche(api, p), attendre: false, produit: p);
}

/// 4.3.2 — Lot de la saisie, lu dès que la liste rapide est affichée (Analyse article, recherche de l'accueil) :
/// seulement si la liste compte de 1 à [produitsMaxLot] produits (liste complète) et la saisie
/// [longueurMiniLot] caractères au moins ; sinon le lot en route est abandonné (le détail lira le CIP au clic).
void prechargerSaisie(ApiService api, String saisie, {required int produits, required bool suite, FicheInfoCache? cache}) {
  final c = cache ?? FicheInfoCache.instance;
  final source = cleSource(api);
  if (HorsLigne.instance.offline || produits <= 0 || produits > produitsMaxLot || suite || saisieLot(saisie).length < longueurMiniLot) {
    c.lacherSaisie(source);
    return;
  }
  c.chargerSaisie(source, saisie, (token) => api.fetchArticleAnalysisOrFail(saisie.trim(), cancelToken: token));
}

/// Message affiché pour une vraie erreur (cause précise, jamais « fiche introuvable »).
String messageErreurFiche(Object e) => ApiService.messageErreurInfo(e);

/// Attente maximale de l'analyse dans la fiche, quoi qu'il arrive (au-delà : erreur + Réessayer,
/// jamais de squelette sans fin). Remplaçable dans les tests.
Duration Function() delaiMaxFiche = () => ApiService.delaiInfo + const Duration(seconds: 5);

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
    final connu = _cache.connuPour(cle, p);
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
      final delai = delaiMaxFiche();
      article = await _cache.charger(cle, chargeur, produit: p).timeout(delai, onTimeout: () {
        // Requête abandonnée et oubliée : la fiche affiche la cause et Réessayer (nouvelle requête).
        _attendu = null;
        _cache.abandonner(cle);
        throw ApiLoadException('Délai dépassé : pas de réponse du serveur en ${delai.inSeconds} s (GET /info). Réessayez.');
      });
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
      // B2 : « Ajouter une photo » visible directement pour l'administrateur ; « Photo du produit » pour les
      // autres comptes derrière le réglage (désactivé par défaut) et le droit du serveur.
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
        // 4.3.2 : ce que la recherche rapide a déjà donné est affiché tout de suite (emplacement = zone du produit,
        // prix d'achat) ; seul ce qui exige GET /info reste en squelette (grossiste, ventes, réserve).
        if (_p.strLIBELLEE.trim().isNotEmpty)
          DetailLine('Emplacement', _p.strLIBELLEE.trim(), key: const ValueKey('fiche-connu-Emplacement'))
        else
          _squelette('Emplacement'),
        _squelette('Grossiste'),
        if (_p.intPAF > 0)
          DetailLine("Prix d'achat", '${_p.intPAF} FCFA', key: const ValueKey("fiche-connu-Prix d'achat"))
        else
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
