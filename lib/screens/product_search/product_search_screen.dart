// lib/screens/product_search/product_search_screen.dart
// 09/11/2025 21:00 (Standardisation de la recherche)
// Refonte : présentations A/B/C, recherche contrôlée (nettoyée, bornée, sans double requête).
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/product_info.dart';
import 'package:prestige_vente_app/providers/product_search_provider.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'product_search_widgets.dart';

class ProductSearchScreen extends StatefulWidget {
  /// Présentation imposée (tests) ; sinon celle choisie sur l'appareil (A par défaut).
  final ListPresentation? presentation;
  const ProductSearchScreen({super.key, this.presentation});

  @override
  State<ProductSearchScreen> createState() => _ProductSearchScreenState();
}

class _ProductSearchScreenState extends State<ProductSearchScreen> with PresentationAware {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  Timer? _debounce;

  /// Dernier texte vu (ignore les simples déplacements du curseur).
  String _lastText = '';

  /// Dernière recherche envoyée au serveur (évite la double requête).
  String _lastSent = '';

  /// Produit touché (pour signaler une fiche introuvable).
  ProductSearchResult? _picked;

  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  @override
  void initState() {
    super.initState();
    loadPresentation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Provider.of<ProductSearchProvider>(context, listen: false).clear();
      FocusScope.of(context).requestFocus(_searchFocusNode);
    });
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose(); _searchFocusNode.dispose(); _debounce?.cancel();
    super.dispose();
  }

  void _setStyle(ListPresentation p) {
    setState(() => style = p);
    if (widget.presentation == null) PresentationPrefs.save(p);
  }

  void _onSearchChanged() {
    if (_searchController.text == _lastText) return;
    _lastText = _searchController.text;
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _runSearch);
  }

  void _submitSearch() {
    _debounce?.cancel();
    _runSearch();
  }

  void _runSearch() {
    if (!mounted) return;
    final provider = Provider.of<ProductSearchProvider>(context, listen: false);
    final q = SearchQuery.clean(_searchController.text);
    if (q.isEmpty) {
      // Comme avant : un champ vide efface la recherche.
      _lastSent = '';
      _picked = null;
      provider.clear();
      return;
    }
    if (SearchQuery.tooShort(q)) {
      setState(() {}); // affiche l'aide « au moins 2 caractères »
      return;
    }
    if (q == _lastSent && (provider.isLoading || provider.searchResults.isNotEmpty)) return;
    _lastSent = q;
    _picked = null;
    provider.search(q);
  }

  void _clear(ProductSearchProvider provider) {
    _debounce?.cancel();
    _lastText = '';
    _searchController.clear();
    _lastSent = '';
    _picked = null;
    provider.clear();
    _searchFocusNode.requestFocus(); // Garde le focus
  }

  void _select(ProductSearchProvider provider, ProductSearchResult product) {
    if (provider.isLoading) return; // pas de double sélection
    _searchFocusNode.unfocus();
    setState(() => _picked = product);
    provider.selectProduct(product);
  }

  // ---------------------------------------------------------------------------
  // Affichage : A · Tableau de bord, B · Liste groupée, C · Parcours guidé
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Consumer<ProductSearchProvider>(
      builder: (context, provider, child) {
        final info = provider.selectedProductInfo;
        final guided = style == ListPresentation.guided;
        Widget field(bool dark) => ProductSearchField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              hint: 'Rechercher par CIP, Nom ou Scan',
              dark: dark,
              onClear: () => _clear(provider),
              onSubmitted: (_) => _submitSearch(),
            );
        return PresentationScaffold(
          style: style,
          title: 'Recherche Article',
          subtitle: style == ListPresentation.dashboard ? 'Stock, prix et ventes d\'un produit' : null,
          actions: (c) => [PresentationMenuButton(value: style, onChanged: _setStyle, color: c)],
          steps: StepsBar(
            active: info != null ? 2 : (provider.searchResults.isNotEmpty ? 1 : 0),
            steps: [
              (title: 'Rechercher', detail: 'nom, CIP, scan', onTap: null),
              (
                title: 'Choisir',
                detail: provider.searchResults.isEmpty ? 'le produit' : '${provider.searchResults.length} résultat(s)',
                onTap: null
              ),
              (title: 'Consulter', detail: 'stock, ventes', onTap: null),
            ],
          ),
          header: [field(true)],
          compactHeader: [field(false)],
          body: Column(children: [
            if (provider.isLoading) const LinearProgressIndicator(minHeight: 2),
            Expanded(child: info != null ? _buildDetailsView(provider, info) : _buildSearchResults(provider)),
          ]),
          bottomNavigationBar: info != null
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton.icon(
                        style: guided ? amberButton : navyButton,
                        icon: const Icon(Icons.search),
                        label: const Text('Nouvelle recherche'),
                        onPressed: () => _clear(provider),
                      ),
                    ),
                  ),
                )
              : null,
        );
      },
    );
  }

  Widget _buildSearchResults(ProductSearchProvider provider) {
    final q = SearchQuery.clean(_searchController.text);
    if (provider.isLoading && provider.searchResults.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_picked != null && !provider.isLoading) {
      return InfoState(
        icon: Icons.inventory_2_outlined,
        text: 'Fiche article introuvable pour « ${orDash(_picked!.strNAME)} ».',
        actionLabel: 'Nouvelle recherche',
        onAction: () => _clear(provider),
      );
    }
    if (q.isEmpty) {
      return const InfoState(icon: Icons.manage_search, text: 'Saisissez le nom, le code CIP ou scannez le produit');
    }
    if (SearchQuery.tooShort(q)) {
      return const InfoState(icon: Icons.keyboard, text: 'Saisissez au moins ${SearchQuery.minLength} caractères');
    }
    if (provider.searchResults.isEmpty) {
      if (q != _lastSent) return const SizedBox.shrink(); // recherche en attente
      if (provider.searchError != null) {
        // Panne (réseau, serveur) : jamais « aucun résultat ».
        return InfoState(
          icon: Icons.cloud_off,
          text: 'Recherche impossible : ${provider.searchError}',
          actionLabel: 'Réessayer',
          onAction: () {
            _lastSent = '';
            _runSearch();
          },
        );
      }
      return InfoState(icon: Icons.search_off, text: provider.searchNotFound ?? 'Aucun résultat', actionLabel: 'Effacer', onAction: () => _clear(provider));
    }
    return ProductResultsList(
      results: provider.searchResults,
      style: style,
      onTap: (p) => _select(provider, p),
      paging: provider.productSearch,
      onLoadMore: provider.loadMoreProducts,
    );
  }

  Widget _metric(String value, String label, {Color fg = Pal.ink}) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: Pal.page, borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: fg)),
            ),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Color(0xFF4A5A70))),
          ]),
        ),
      );

  Widget _buildDetailsView(ProductSearchProvider provider, ProductInfo info) {
    final compact = style == ListPresentation.compact;
    final guided = style == ListPresentation.guided;
    final stockColor = info.stock <= 0 ? const Color(0xFFB91C1C) : Pal.green;
    final lines = [
      DetailLine('Code CIP', orDash(info.codeCip), bold: true, compact: compact),
      DetailLine('Prix Vente', Constants.formatNumber(info.prixVente), compact: compact),
      DetailLine('Prix Achat', Constants.formatNumber(info.prixAchat), compact: compact),
      DetailLine('Stock Actuel', info.stock.toString(), compact: compact),
      DetailLine('Emplacement', orDash(info.emplacement), compact: compact),
      DetailLine('Grossiste', orDash(info.grossiste), compact: compact),
    ];
    final title = Text(orDash(info.libelle), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Pal.ink));

    if (compact) {
      return ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 10), child: title),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: LightFigures([
              ('${info.stock}', 'Stock', stockColor),
              (Constants.formatNumber(info.prixVente), 'Prix vente', Pal.navy),
              (Constants.formatNumber(info.prixAchat), 'Prix achat', Pal.muted),
            ]),
          ),
          const SizedBox(height: 6),
          ...lines,
          if (provider.hasComparisonData)
            Padding(padding: const EdgeInsets.fromLTRB(12, 16, 12, 0), child: _buildComparisonSection(provider)),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        SoftCard(
          band: guided ? Pal.navy : null,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            title,
            const SizedBox(height: 10),
            Row(children: [
              _metric('${info.stock}', 'Stock', fg: stockColor),
              const SizedBox(width: 8),
              _metric('${Constants.formatNumber(info.prixVente)} F', 'Prix vente'),
            ]),
            const SizedBox(height: 8),
            ...lines,
          ]),
        ),
        const SizedBox(height: 14),
        if (provider.hasComparisonData)
          SoftCard(band: guided ? Pal.green : null, child: _buildComparisonSection(provider)),
      ],
    );
  }

  Widget _buildComparisonSection(ProductSearchProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Comparaison Ventes / Commandes', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Pal.ink)),
        Text('Année ${DateTime.now().year}, par mois', style: const TextStyle(fontSize: 13, color: Pal.muted)),
        const SizedBox(height: 16),
        SizedBox(height: 260, child: LineChart(_buildChartData(provider))),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 20,
          runSpacing: 6,
          children: [
            _legendItem(Colors.blue, "Ventes"),
            _legendItem(Colors.green, "Commandes"),
          ],
        ),
      ],
    );
  }

  LineChartData _buildChartData(ProductSearchProvider provider) {
    return LineChartData(
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, interval: 1, getTitlesWidget: (value, meta) {
            const months = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
            if (value.toInt() >= 0 && value.toInt() < months.length) {
              return Text(months[value.toInt()]);
            }
            return const Text('');
          })),
        ),
        borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey.shade300)),
        gridData: const FlGridData(show: true),
        lineBarsData: [
          LineChartBarData(
              spots: provider.comparisonData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.sales.toDouble())).toList(),
              isCurved: true, color: Colors.blue, barWidth: 3),
          LineChartBarData(
              spots: provider.comparisonData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.orders.toDouble())).toList(),
              isCurved: true, color: Colors.green, barWidth: 3)
        ]
    );
  }

  Widget _legendItem(Color color, String text) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 8),
      Text(text),
    ]);
  }
}
