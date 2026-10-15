// lib/screens/analysis/article_analysis_screen.dart
// Analyse article (4.1.2) : la LISTE vient de la recherche rapide GET /vente/search (anti-rebond, annulation,
// classement par début de code, comme la recherche de l'accueil) ; le DÉTAIL d'un produit choisi lit GET /info par
// son CIP exact, avec un indicateur, sans bloquer l'écran (ArticleAnalysisProvider).
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/article_analysis_model.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/providers/article_analysis_provider.dart';
import 'package:prestige_vente_app/screens/analysis/article_analysis_widgets.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/product_paging.dart';
import 'package:prestige_vente_app/widgets/responsive.dart';

class ArticleAnalysisScreen extends StatefulWidget {
  /// Présentation imposée (tests) ; sinon celle choisie sur l'appareil (A par défaut).
  final ListPresentation? presentation;
  const ArticleAnalysisScreen({Key? key, this.presentation}) : super(key: key);

  @override
  State<ArticleAnalysisScreen> createState() => _ArticleAnalysisScreenState();
}

class _ArticleAnalysisScreenState extends State<ArticleAnalysisScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  late ListPresentation _style = widget.presentation ?? ListPresentation.dashboard;

  @override
  void initState() {
    super.initState();
    if (widget.presentation == null) {
      PresentationPrefs.load().then((p) {
        if (mounted) setState(() => _style = p);
      });
    }
  }

  void _setStyle(ListPresentation p) {
    setState(() => _style = p);
    if (widget.presentation == null) PresentationPrefs.save(p);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  /// Anti-rebond des frappes : la recherche part [rebond] après la dernière frappe ; chaque recherche
  /// annule la précédente (une seule requête GET /vente/search en vol, ArticleAnalysisProvider). Aucun
  /// GET /info pendant la frappe : seulement pour le produit choisi.
  static const rebond = Duration(milliseconds: 350);

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    final q = query.trim();
    final provider = Provider.of<ArticleAnalysisProvider>(context, listen: false);
    if (q.length < 2) {
      // Moins de 2 caractères : rien n'est envoyé, la recherche en cours est abandonnée.
      if (provider.query.isNotEmpty || provider.isLoading) provider.clear();
      return;
    }
    _debounce = Timer(rebond, () {
      if (!mounted) return;
      // Même texte déjà affiché (ex. espace ajouté puis retiré) : pas de nouvelle requête.
      if (q == provider.query && provider.error == null && !provider.isLoading) return;
      provider.searchArticles(q);
    });
  }

  void _showDetailDialog(ProductSearchResult produit) {
    final provider = Provider.of<ArticleAnalysisProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (context) => _ArticleDetailDialog(produit: produit, provider: provider),
    );
  }

  // ---------------------------------------------------------------------------
  // Affichage : A · Tableau de bord, B · Liste groupée, C · Parcours guidé
  // ---------------------------------------------------------------------------
  void _clear() {
    _debounce?.cancel();
    _searchCtrl.clear();
    Provider.of<ArticleAnalysisProvider>(context, listen: false).clear();
  }

  Widget _searchField({Color fill = Colors.white}) => TextField(
        controller: _searchCtrl,
        autofocus: true,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: "Rechercher un Article (Nom, CIP)",
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(icon: const Icon(Icons.clear), tooltip: 'Effacer', onPressed: _clear),
          filled: true,
          fillColor: fill,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      );

  Widget _emptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.analytics_outlined, size: 60, color: Colors.grey.shade400),
            const SizedBox(height: 10),
            const Text("Saisissez le nom ou le code CIP du produit", textAlign: TextAlign.center),
          ]),
        ),
      );

  /// Message centré (aucun résultat, erreur) avec action facultative.
  Widget _message(Key key, IconData icon, Color color, String texte, {String? detail, VoidCallback? action}) => Center(
        key: key,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 52, color: color),
            const SizedBox(height: 10),
            Text(texte, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, color: Pal.ink, fontSize: 15)),
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(detail, textAlign: TextAlign.center, style: const TextStyle(color: Pal.muted, fontSize: 13)),
            ],
            if (action != null) ...[
              const SizedBox(height: 14),
              ElevatedButton.icon(style: navyButton, onPressed: action, icon: const Icon(Icons.refresh), label: const Text('Réessayer')),
            ],
          ]),
        ),
      );

  /// Résultats (même source de données pour les trois présentations) : jamais « rien » — chargement,
  /// résultats, aucun produit, ou erreur précise avec Réessayer.
  Widget _results(Widget Function(List<ProductSearchResult> items, Widget? fin) builder) => Consumer<ArticleAnalysisProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return Center(
              key: const ValueKey('analyse-chargement'),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text('Recherche de « ${provider.query} »…', style: const TextStyle(color: Pal.muted)),
              ]),
            );
          }
          if (provider.error != null) {
            return _message(const ValueKey('analyse-erreur'), Icons.cloud_off, const Color(0xFFB45309), 'Analyse non chargée',
                detail: provider.error, action: provider.reessayer);
          }
          if (provider.aucunResultat) {
            return _message(const ValueKey('analyse-aucun'), Icons.search_off, Pal.muted,
                provider.notFound ?? 'Aucun produit dont le nom ou le CIP commence par « ${provider.query} »',
                detail: 'Vérifiez l\'orthographe ou saisissez le début du nom.');
          }
          if (provider.results.isEmpty) return _emptyState();
          // « Charger la suite » / erreur de la suite (liste texte par pages, comme la recherche de l'accueil).
          final s = provider.productSearch;
          final fin = ProductPagingFooter.visibleFor(s) ? ProductPagingFooter(s, onLoadMore: provider.loadMoreProducts) : null;
          return builder(provider.results, fin);
        },
      );

  Color _stockColor(int stock) => stock <= 0 ? const Color(0xFFB91C1C) : Pal.ink;

  Widget _metric(String value, String label, {Color fg = Pal.ink}) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: Pal.page, borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: fg)),
            Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF4A5A70))),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) => switch (_style) {
        ListPresentation.dashboard => _buildDashboard(),
        ListPresentation.compact => _buildCompact(),
        ListPresentation.guided => _buildGuided(),
      };

  /// « CIP: 3595583 · FAMILLE » (famille du produit si connue).
  String _cip(ProductSearchResult p) => "CIP: ${p.intCIP}${p.strLIBELLEE.trim().isNotEmpty ? ' · ${p.strLIBELLEE.trim()}' : ''}";

  String _prix(ProductSearchResult p) => '${Constants.formatNumber(p.intPRICE)} F';

  /// Liste séparée, avec la ligne « Charger la suite » en fin si besoin.
  Widget _liste(List<ProductSearchResult> items, Widget? fin, Widget Function(int i, ProductSearchResult p) carte,
          {EdgeInsets padding = const EdgeInsets.fromLTRB(16, 14, 16, 24)}) =>
      ListView.separated(
        padding: padding,
        itemCount: items.length + (fin == null ? 0 : 1),
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => i < items.length ? carte(i, items[i]) : fin!,
      );

  // --- A ---
  Widget _buildDashboard() => Scaffold(
        backgroundColor: Pal.page,
        body: Column(children: [
          NavyHeader(
            title: 'Analyse article',
            subtitle: 'Ventes, stock et prix d\'un produit',
            actions: [PresentationMenuButton(value: _style, onChanged: _setStyle)],
            children: [_searchField()],
          ),
          Expanded(
            child: ContentWidth(
              child: _results((items, fin) => _liste(items, fin, (_, p) => _cardA(p))),
            ),
          ),
        ]),
      );

  Widget _cardA(ProductSearchResult item) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showDetailDialog(item),
        child: SoftCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(item.strNAME, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Pal.ink))),
              const Icon(Icons.chevron_right, color: Pal.muted),
            ]),
            const SizedBox(height: 2),
            Text(_cip(item), style: const TextStyle(fontSize: 13, color: Pal.muted)),
            const SizedBox(height: 12),
            Row(children: [
              _metric("${item.intNUMBERAVAILABLE}", 'Stock', fg: _stockColor(item.intNUMBERAVAILABLE)),
              const SizedBox(width: 8),
              _metric(_prix(item), 'Prix de vente'),
            ]),
          ]),
        ),
      );

  // --- B ---
  Widget _buildCompact() => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: Pal.navy,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: const Text("Analyse Article", style: TextStyle(fontWeight: FontWeight.bold, color: Pal.navy)),
          actions: [PresentationMenuButton(value: _style, onChanged: _setStyle, color: Pal.navy)],
          bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider(height: 1, color: Pal.line)),
        ),
        body: Column(children: [
          Expanded(
            child: ContentWidth(
              child: Column(children: [
                Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: _searchField(fill: Pal.page)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                  child: Row(children: const [
                    Expanded(child: Text('PRODUIT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: Color(0xFF4A5A70)))),
                    SizedBox(width: 56, child: Text('STOCK', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: Color(0xFF4A5A70)))),
                    SizedBox(width: 72, child: Text('PRIX', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: Color(0xFF4A5A70)))),
                  ]),
                ),
                const Divider(height: 1, color: Pal.line),
                Expanded(
                  child: _results((items, fin) => ListView.builder(
                        itemCount: items.length + (fin == null ? 0 : 1),
                        itemBuilder: (_, i) {
                          if (i >= items.length) return fin!;
                          final item = items[i];
                          return InkWell(
                            onTap: () => _showDetailDialog(item),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEF1F5)))),
                              child: Row(children: [
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(item.strNAME, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Pal.ink)),
                                    Text(_cip(item), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Pal.muted)),
                                  ]),
                                ),
                                SizedBox(
                                  width: 56,
                                  child: Text("${item.intNUMBERAVAILABLE}",
                                      textAlign: TextAlign.right,
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _stockColor(item.intNUMBERAVAILABLE))),
                                ),
                                SizedBox(
                                  width: 72,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerRight,
                                    child: Text(_prix(item), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Pal.ink)),
                                  ),
                                ),
                              ]),
                            ),
                          );
                        },
                      )),
                ),
              ]),
            ),
          ),
        ]),
      );

  // --- C ---
  Widget _buildGuided() => Scaffold(
        backgroundColor: const Color(0xFFEEF2F7),
        body: Column(children: [
          Consumer<ArticleAnalysisProvider>(
            builder: (context, provider, _) => NavyHeader(
              title: 'Analyse article',
              rounded: false,
              actions: [PresentationMenuButton(value: _style, onChanged: _setStyle)],
              children: [
                StepsBar(active: provider.results.isEmpty ? 0 : 1, steps: [
                  (title: 'Rechercher', detail: 'nom ou CIP', onTap: null),
                  (title: 'Choisir', detail: provider.results.isEmpty ? 'le produit' : '${provider.results.length} résultat(s)', onTap: null),
                  (title: 'Analyser', detail: 'ventes, stock', onTap: null),
                ]),
              ],
            ),
          ),
          Expanded(
            child: ContentWidth(
              child: Column(children: [
                Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 8), child: _searchField()),
                Expanded(
                  child: _results((items, fin) => _liste(items, fin, padding: const EdgeInsets.fromLTRB(16, 6, 16, 24), (i, item) {
                        if (i == 0) {
                          return InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _showDetailDialog(item),
                            child: SoftCard(
                              band: Pal.navy,
                              padding: const EdgeInsets.all(16),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                Text(item.strNAME, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Pal.ink)),
                                Text(_cip(item), style: const TextStyle(fontSize: 13, color: Pal.muted)),
                                const SizedBox(height: 12),
                                Row(children: [
                                  _metric("${item.intNUMBERAVAILABLE}", 'Stock', fg: _stockColor(item.intNUMBERAVAILABLE)),
                                  const SizedBox(width: 8),
                                  _metric(_prix(item), 'Prix de vente'),
                                ]),
                                const SizedBox(height: 12),
                                SizedBox(
                                  height: 48,
                                  child: ElevatedButton.icon(
                                    style: amberButton,
                                    icon: const Icon(Icons.show_chart),
                                    label: const Text('Voir l\'analyse complète'),
                                    onPressed: () => _showDetailDialog(item),
                                  ),
                                ),
                              ]),
                            ),
                          );
                        }
                        return SoftCard(
                          child: Row(children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(item.strNAME, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Pal.ink)),
                                Text("Stock ${item.intNUMBERAVAILABLE} · ${_prix(item)}", style: const TextStyle(fontSize: 13, color: Pal.muted)),
                              ]),
                            ),
                            IconButton.filled(
                              tooltip: 'Analyser ${item.strNAME}',
                              style: IconButton.styleFrom(backgroundColor: Pal.navy, foregroundColor: Colors.white, minimumSize: const Size(44, 44)),
                              icon: const Icon(Icons.show_chart),
                              onPressed: () => _showDetailDialog(item),
                            ),
                          ]),
                        );
                      })),
                ),
              ]),
            ),
          ),
        ]),
      );
}

/// « Détails de l'Article » d'un produit CHOISI : nom, CIP, stock et prix de la liste tout de suite, puis
/// l'analyse (GET /info?search=<CIP exact>) avec un indicateur ; erreur précise + Réessayer ; requête abandonnée
/// si la fenêtre est fermée avant la réponse.
class _ArticleDetailDialog extends StatefulWidget {
  final ProductSearchResult produit;
  final ArticleAnalysisProvider provider;
  const _ArticleDetailDialog({required this.produit, required this.provider});

  @override
  State<_ArticleDetailDialog> createState() => _ArticleDetailDialogState();
}

class _ArticleDetailDialogState extends State<_ArticleDetailDialog> {
  ArticleAnalysis? _article;
  bool _chargement = true;
  String? _erreur;
  int _seq = 0;

  ProductSearchResult get _p => widget.produit;

  @override
  void initState() {
    super.initState();
    final connu = widget.provider.detailConnu(_p);
    if (connu != null) {
      _article = connu.article;
      _chargement = false;
    } else {
      _charger();
    }
  }

  @override
  void dispose() {
    if (_chargement) widget.provider.lacherDetail(_p);
    super.dispose();
  }

  Future<void> _charger() async {
    final seq = ++_seq;
    if (mounted && (!_chargement || _erreur != null)) {
      setState(() {
        _chargement = true;
        _erreur = null;
      });
    }
    ArticleAnalysis? a;
    String? erreur;
    try {
      a = await widget.provider.chargerDetail(_p);
    } catch (e) {
      erreur = ApiService.messageErreurInfo(e);
    }
    if (!mounted || seq != _seq) return;
    setState(() {
      _article = a;
      _erreur = erreur;
      _chargement = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = _article;
    final stock = a?.stock ?? _p.intNUMBERAVAILABLE;
    // Informations et graphique bicolore partagés avec la fiche produit (article_analysis_widgets.dart).
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Titre avec bouton fermer
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(child: Text("Détails de l'Article", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.primary))),
                  IconButton(icon: const Icon(Icons.close), tooltip: 'Fermer', onPressed: () => Navigator.pop(context))
                ],
              ),
              const Divider(),

              // Header: CIP & Libellé
              Center(
                child: Column(
                  children: [
                    Text("Code CIP: ${_p.intCIP}", style: const TextStyle(color: Color(0xFF5B6B82))),
                    const SizedBox(height: 5),
                    Text(a != null && a.libelle.isNotEmpty ? a.libelle : _p.strNAME,
                        textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              if (_chargement)
                _attente(stock)
              else if (_erreur != null)
                _erreurBloc(stock)
              else if (a == null)
                _sansAnalyse(stock)
              else ...[
                // Bloc Infos Central
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Column(
                      key: const ValueKey('analyse-detail'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [for (final (label, value) in articleInfos(a)) _infoRow(label, value)],
                    ),
                    Positioned(right: 0, top: 0, child: _pastilleStock(a.stock)),
                  ],
                ),

                // Stock rayon / réserve (« — » si non géré en réserve), seuils, total, alerte.
                const Divider(),
                Column(
                  key: const ValueKey('analyse-stock-reserve'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (label, value) in stockReserveInfos(a.stock, a.reserve)) _infoRow(label, value),
                    PastilleReappro(reserve: a.reserve, rayon: a.stock),
                  ],
                ),

                const SizedBox(height: 20),

                // Légende, « Évolution des ventes mensuelles: » et graphique bicolore
                ArticleVentesChart(article: a),
              ],

              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: () => Navigator.pop(context), child: const Text("Fermer")),
              )
            ],
          ),
        ),
      ),
    );
  }

  /// Stock et prix de la liste, en attendant l'analyse.
  Widget _resume(int stock) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _infoRow('Stock', '$stock'),
        _infoRow('Prix de vente', '${_p.intPRICE} FCFA'),
      ]);

  Widget _attente(int stock) => Column(key: const ValueKey('analyse-detail-chargement'), crossAxisAlignment: CrossAxisAlignment.start, children: [
        _resume(stock),
        const SizedBox(height: 8),
        const Row(children: [
          SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
          SizedBox(width: 12),
          Expanded(child: Text('Chargement de l\'analyse (ventes, grossiste, emplacement)…', style: TextStyle(color: Color(0xFF5B6B82)))),
        ]),
      ]);

  Widget _erreurBloc(int stock) => Column(key: const ValueKey('analyse-detail-erreur'), crossAxisAlignment: CrossAxisAlignment.start, children: [
        _resume(stock),
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.cloud_off, color: Color(0xFFB45309)),
          const SizedBox(width: 10),
          Expanded(child: Text(_erreur ?? '', style: const TextStyle(color: Pal.ink))),
        ]),
        Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _charger, child: const Text('Réessayer'))),
      ]);

  Widget _sansAnalyse(int stock) => Column(key: const ValueKey('analyse-detail-vide'), crossAxisAlignment: CrossAxisAlignment.start, children: [
        _resume(stock),
        const SizedBox(height: 8),
        const Text("Pas d'analyse sur le serveur pour ce produit (emplacement, grossiste ou ventes non renseignés).",
            style: TextStyle(color: Color(0xFF5B6B82), fontSize: 13)),
      ]);

  Widget _pastilleStock(int stock) => Container(
        padding: const EdgeInsets.all(15),
        decoration: const BoxDecoration(
            color: AppColors.primary, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(2, 2))]),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("Stock", style: TextStyle(color: Colors.white, fontSize: 10)),
            Text("$stock", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
      );

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        ],
      ),
    );
  }
}
