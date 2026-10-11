// lib/accueil/fiche_produit_screen.dart
// Fiche produit ouverte depuis la recherche ou le scan de l'accueil :
// nom, CIP, stock, prix de vente (résultat de recherche) + emplacement et grossiste (GET /info).
// Affichage IMMÉDIAT avec la ligne de résultat ; le complément (GET /info) et l'image arrivent en
// arrière-plan (squelettes de chargement), en parallèle, avec un cache mémoire court (60 s) et
// l'abandon de la requête si l'on quitte la fiche avant la réponse.
// Hors ligne : données de la copie locale du catalogue (lib/horsligne) avec leur date ;
// ce qui exige le serveur affiche « Disponible en ligne uniquement » (jamais une erreur).
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/product_info.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/images/photo_produit.dart';
import 'package:prestige_vente_app/images/produit_image_widget.dart';
import 'package:prestige_vente_app/screens/product_search/product_search_widgets.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/responsive.dart';

/// Chargement du complément d'une fiche (annulable).
typedef ChargeurInfo = Future<ProductInfo?> Function(String cip, CancelToken token);

/// Complément de la fiche (GET /info) chez l'[ApiService] : requête annulable sur le serveur réel ;
/// une sous-classe (faux service des tests) garde son propre [ApiService.getProductInfo].
ChargeurInfo chargeurInfo(ApiService api) =>
    (cip, token) => api.runtimeType == ApiService ? api.getProductInfoAnnulable(cip, token) : api.getProductInfo(cip);

/// Cache mémoire court des compléments de fiche : réouverture sans attente, une seule requête
/// à la fois par produit, requête abandonnée quand plus aucune fiche ne l'attend.
class FicheInfoCache {
  FicheInfoCache({this.duree = const Duration(seconds: 60), DateTime Function()? horloge}) : horloge = horloge ?? DateTime.now;

  /// Cache de l'application.
  static final FicheInfoCache instance = FicheInfoCache();

  final Duration duree;
  final DateTime Function() horloge;
  final Map<String, ({DateTime at, ProductInfo info})> _connus = {};
  final Map<String, _Demande> _enCours = {};

  /// Requêtes réellement envoyées (diagnostic, tests).
  int requetes = 0;

  /// Requêtes abandonnées (fiche quittée avant la réponse).
  int abandons = 0;

  /// Complément encore frais (null sinon).
  ProductInfo? connu(String cle) {
    final e = _connus[cle];
    if (e == null) return null;
    if (horloge().difference(e.at) > duree) {
      _connus.remove(cle);
      return null;
    }
    return e.info;
  }

  /// Complément de [cle] : frais en cache, sinon la requête en cours, sinon une nouvelle requête.
  /// [attendre] faux (préchargement) : la requête ne compte pas d'écran en attente.
  Future<ProductInfo?> charger(String cle, String cip, ChargeurInfo chargeur, {bool attendre = true}) {
    final c = connu(cle);
    if (c != null) return Future.value(c);
    final d = _enCours[cle];
    if (d != null) {
      if (attendre) d.abonnes++;
      return d.future;
    }
    final token = CancelToken();
    requetes++;
    late final _Demande demande;
    final f = Future<ProductInfo?>.sync(() => chargeur(cip, token)).then<ProductInfo?>((info) {
      if (info != null && !token.isCancelled) _connus[cle] = (at: horloge(), info: info);
      return info;
    }, onError: (_) => null).whenComplete(() {
      if (identical(_enCours[cle], demande)) _enCours.remove(cle);
    });
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
  final Future<ProductInfo?> future;
  int abonnes;
  _Demande(this.token, this.future, this.abonnes);
}

/// Clé du cache : une source (service : serveur et session) et un CIP.
String cleFiche(Object source, String cip) => '${identityHashCode(source)}|$cip';

/// Préchargement du complément dès la sélection du produit (pendant l'ouverture de la fiche).
void prechargerFiche(ApiService api, ProductSearchResult p, {FicheInfoCache? cache}) {
  final cip = p.intCIP.trim();
  if (cip.isEmpty || HorsLigne.instance.offline) return;
  (cache ?? FicheInfoCache.instance).charger(cleFiche(api, cip), cip, chargeurInfo(api), attendre: false);
}

class FicheProduitScreen extends StatefulWidget {
  final ProductSearchResult produit;

  /// Chargement du complément (tests) ; sinon ApiService.getProductInfo.
  final Future<ProductInfo?> Function(String cip)? loadInfo;

  /// Cache des compléments (tests) ; par défaut celui de l'application, ou un cache propre à
  /// la fiche si [loadInfo] est fourni.
  final FicheInfoCache? cache;
  const FicheProduitScreen({super.key, required this.produit, this.loadInfo, this.cache});

  @override
  State<FicheProduitScreen> createState() => _FicheProduitScreenState();
}

class _FicheProduitScreenState extends State<FicheProduitScreen> {
  ProductInfo? _info;
  bool _loading = true;
  bool _failed = false;

  /// Hors ligne : produit relu dans la copie locale (null : celui reçu).
  ProductSearchResult? _local;
  late final HorsLigne _hl = HorsLigne.instance;
  late bool _offline = _hl.offline;

  late final FicheInfoCache _cache = widget.cache ?? (widget.loadInfo != null ? FicheInfoCache() : FicheInfoCache.instance);

  /// Clé du complément attendu (null : aucun).
  String? _attendu;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _hl.monitor.addListener(_onMonitor);
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
      _info = null;
      _loading = false;
      _failed = false;
    });
  }

  Future<void> _load() async {
    _lacher();
    final seq = ++_seq;
    if (_offline) {
      setState(() {
        _loading = true;
        _failed = false;
      });
      return _loadLocal();
    }
    final cip = widget.produit.intCIP.trim();
    final Object source = widget.loadInfo ?? Provider.of<ApiService>(context, listen: false);
    final cle = cleFiche(source, cip);
    // Déjà connu (réouverture, préchargement terminé) : affiché tout de suite, sans requête.
    final connu = cip.isEmpty ? null : _cache.connu(cle);
    if (connu != null || cip.isEmpty) {
      setState(() {
        _info = connu;
        _local = null;
        _loading = false;
        _failed = connu == null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _failed = false;
    });
    final ChargeurInfo chargeur = widget.loadInfo != null ? (c, _) => widget.loadInfo!(c) : chargeurInfo(source as ApiService);
    _attendu = cle;
    final info = await _cache.charger(cle, cip, chargeur);
    if (!mounted || _offline || seq != _seq) return;
    _attendu = null;
    setState(() {
      _info = info;
      _local = null;
      _loading = false;
      _failed = info == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = _offline ? (_local ?? widget.produit) : widget.produit;
    final info = _offline ? null : _info;
    final stock = info?.stock ?? p.intNUMBERAVAILABLE;
    final stockColor = stock <= 0 ? const Color(0xFFB91C1C) : Pal.green;
    return Scaffold(
      backgroundColor: Pal.page,
      body: Column(children: [
        const NavyHeader(title: 'Fiche produit', subtitle: 'Stock, prix et emplacement'),
        Expanded(
          child: ContentWidth(
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
              if (_offline) ...[_noteHorsLigne(), const SizedBox(height: 12)],
              // B2 : image du produit (serveur, cache disque ; rien si le produit n'en a pas).
              Center(
                child: ProduitImage(
                  familleId: p.lgFAMILLEID,
                  taille: 180,
                  rayon: BorderRadius.circular(16),
                  placeholder: const SizedBox.shrink(),
                  prioritaire: true,
                ),
              ),
              SoftCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(orDash(info?.libelle.isNotEmpty == true ? info!.libelle : p.strNAME),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Pal.ink)),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: _figure('$stock', 'En stock', stockColor)),
                    const SizedBox(width: 8),
                    Expanded(child: _figure('${Constants.formatNumber(p.intPRICE)} F', 'Prix de vente', Pal.ink)),
                  ]),
                  const SizedBox(height: 12),
                  DetailLine('Code CIP', orDash(p.intCIP), bold: true),
                  if (p.strLIBELLEE.trim().isNotEmpty) DetailLine('Famille', orDash(p.strLIBELLEE)),
                  if (_loading) ...[
                    // Squelettes : la fiche reste lisible, le complément arrive en arrière-plan.
                    _squelette('Emplacement'),
                    _squelette('Grossiste'),
                  ] else if (_offline) ...[
                    const DetailLine('Emplacement', 'Disponible en ligne uniquement'),
                    const DetailLine('Grossiste', 'Disponible en ligne uniquement'),
                  ] else if (info != null) ...[
                    DetailLine('Emplacement', orDash(info.emplacement)),
                    DetailLine('Grossiste', orDash(info.grossiste)),
                  ],
                ]),
              ),
              if (_failed && !_loading && !_offline) ...[
                const SizedBox(height: 12),
                SoftCard(
                  child: Row(children: [
                    const Icon(Icons.cloud_off, color: Color(0xFFB45309)),
                    const SizedBox(width: 10),
                    const Expanded(child: Text('Emplacement et grossiste non disponibles (serveur ou fiche introuvable).', style: TextStyle(color: Pal.muted))),
                    TextButton(onPressed: _load, child: const Text('Réessayer')),
                  ]),
                ),
              ],
              // B2 : « Photo du produit » (réglage administrateur désactivé par défaut, droit du serveur).
              Padding(padding: const EdgeInsets.only(top: 12), child: Align(alignment: Alignment.centerLeft, child: PhotoProduitBouton(familleId: p.lgFAMILLEID))),
            ]),
          ),
        ),
      ]),
    );
  }

  /// Ligne en attente du complément (libellé + barre grise).
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

  Widget _figure(String value, String label, Color color) => Container(
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
