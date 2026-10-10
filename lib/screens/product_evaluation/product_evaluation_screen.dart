// lib/screens/product_evaluation/product_evaluation_screen.dart
// 09/11/2025 21:00 (Standardisation de la recherche)
// Refonte : présentations A/B/C, recherche contrôlée (nettoyée, bornée, sans double requête).
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/product_stats.dart';
import 'package:prestige_vente_app/providers/product_stats_provider.dart';
import 'package:prestige_vente_app/screens/product_search/product_search_widgets.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';

class ProductEvaluationScreen extends StatefulWidget {
  /// Présentation imposée (tests) ; sinon celle choisie sur l'appareil (A par défaut).
  final ListPresentation? presentation;
  const ProductEvaluationScreen({super.key, this.presentation});

  @override
  State<ProductEvaluationScreen> createState() => _ProductEvaluationScreenState();
}

/// Mois dans l'ordre des données serveur (clés sans accents) et leur libellé court.
const _monthKeys = ['janvier', 'fevrier', 'mars', 'avril', 'mai', 'juin', 'juillet', 'aout', 'septembre', 'octobre', 'novembre', 'decembre'];
const _monthShort = ['Janv.', 'Févr.', 'Mars', 'Avr.', 'Mai', 'Juin', 'Juil.', 'Août', 'Sept.', 'Oct.', 'Nov.', 'Déc.'];

class _ProductEvaluationScreenState extends State<ProductEvaluationScreen> with PresentationAware {
  final _searchController = TextEditingController();
  Timer? _debounce;
  final _searchFocusNode = FocusNode();

  /// Dernier texte vu (ignore les simples déplacements du curseur).
  String _lastText = '';

  /// Dernière recherche envoyée au serveur (évite la double requête).
  String _lastSent = '';

  /// Produit touché (pour signaler l'absence de statistiques).
  ProductSearchResult? _picked;

  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  @override
  void initState() {
    super.initState();
    loadPresentation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Provider.of<ProductStatsProvider>(context, listen: false).clear();
      FocusScope.of(context).requestFocus(_searchFocusNode);
    });
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    _searchFocusNode.dispose();
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

  /// Longueur minimale : 3 chiffres pour un CIP, 2 caractères pour un nom (règle du fournisseur de données).
  int _minFor(String q) => int.tryParse(q) != null ? 3 : SearchQuery.minLength;

  void _runSearch() {
    if (!mounted) return;
    final provider = Provider.of<ProductStatsProvider>(context, listen: false);
    final q = SearchQuery.clean(_searchController.text);
    if (q.isEmpty || SearchQuery.tooShort(q, min: _minFor(q))) {
      // Aucune requête serveur : le fournisseur vide seulement la liste.
      _lastSent = '';
      provider.searchProducts(q);
      setState(() {});
      return;
    }
    if (q == _lastSent && (provider.isLoading || provider.searchResults.isNotEmpty)) return;
    _lastSent = q;
    _picked = null;
    provider.searchProducts(q);
  }

  void _clear(ProductStatsProvider provider) {
    _debounce?.cancel();
    _lastText = '';
    _searchController.clear();
    _lastSent = '';
    _picked = null;
    provider.clear();
    _searchFocusNode.requestFocus(); // Garde le focus
  }

  void _select(ProductStatsProvider provider, ProductSearchResult product) {
    if (provider.isLoading) return; // pas de double sélection
    setState(() => _picked = product);
    provider.selectProduct(product);
    _debounce?.cancel();
    _lastText = '';
    _lastSent = '';
    _searchController.clear();
    _searchFocusNode.unfocus();
  }

  // ---------------------------------------------------------------------------
  // Affichage : A · Tableau de bord, B · Liste groupée, C · Parcours guidé
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Consumer<ProductStatsProvider>(
      builder: (context, provider, child) {
        final sales = provider.selectedProductSales;
        final guided = style == ListPresentation.guided;
        final total = sales == null ? 0 : sales.monthlySales.values.fold<int>(0, (a, b) => a + b);
        final months = DateTime.now().month;
        final average = months == 0 ? 0.0 : total / months;
        Widget field(bool dark) => ProductSearchField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              hint: 'Rechercher par CIP ou Nom',
              dark: dark,
              onClear: () => _clear(provider),
              onSubmitted: (_) => _submitSearch(),
            );
        return PresentationScaffold(
          style: style,
          title: 'Évaluation Vente',
          subtitle: style == ListPresentation.dashboard ? 'Ventes mensuelles d\'un article' : null,
          actions: (c) => [PresentationMenuButton(value: style, onChanged: _setStyle, color: c)],
          steps: StepsBar(
            active: sales != null ? 2 : (provider.searchResults.isNotEmpty ? 1 : 0),
            steps: [
              (title: 'Rechercher', detail: 'nom ou CIP', onTap: null),
              (
                title: 'Choisir',
                detail: provider.searchResults.isEmpty ? 'l\'article' : '${provider.searchResults.length} résultat(s)',
                onTap: null
              ),
              (title: 'Évaluer', detail: 'ventes par mois', onTap: null),
            ],
          ),
          header: [
            field(true),
            if (sales != null)
              Row(children: [
                Expanded(child: HeaderFigure(Constants.formatNumber(total), 'Ventes ${DateTime.now().year}', highlight: guided)),
                const SizedBox(width: 8),
                Expanded(child: HeaderFigure(average.toStringAsFixed(1), 'Moyenne / mois')),
              ]),
          ],
          compactHeader: [
            field(false),
            if (sales != null)
              LightFigures([
                (Constants.formatNumber(total), 'Ventes ${DateTime.now().year}', Pal.navy),
                (average.toStringAsFixed(1), 'Moyenne / mois', Pal.green),
              ]),
          ],
          body: Column(children: [
            if (provider.isLoading) const LinearProgressIndicator(minHeight: 2),
            Expanded(child: sales == null ? _buildSearchResults(provider) : _buildProductDetailsLayout(provider, sales)),
          ]),
          bottomNavigationBar: sales != null
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

  Widget _buildSearchResults(ProductStatsProvider provider) {
    final q = SearchQuery.clean(_searchController.text);
    if (provider.isLoading && provider.searchResults.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_picked != null && q.isEmpty) {
      return InfoState(
        icon: Icons.bar_chart,
        text: 'Aucune vente enregistrée cette année pour « ${orDash(_picked!.strNAME)} ».',
        actionLabel: 'Nouvelle recherche',
        onAction: () => _clear(provider),
      );
    }
    if (q.isEmpty) {
      return const InfoState(icon: Icons.bar_chart, text: 'Saisissez le nom ou le code CIP de l\'article à évaluer');
    }
    if (SearchQuery.tooShort(q, min: _minFor(q))) {
      return InfoState(icon: Icons.keyboard, text: 'Saisissez au moins ${_minFor(q)} ${_minFor(q) == 3 ? 'chiffres' : 'caractères'}');
    }
    if (provider.searchResults.isEmpty) {
      if (q != _lastSent) return const SizedBox.shrink(); // recherche en attente
      if (provider.searchError != null) {
        // Panne (réseau, serveur) : jamais « aucun produit ».
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
      return InfoState(
          icon: Icons.search_off, text: provider.searchNotFound ?? 'Aucun produit trouvé.', actionLabel: 'Effacer', onAction: () => _clear(provider));
    }
    return ProductResultsList(
      results: provider.searchResults,
      style: style,
      onTap: (p) => _select(provider, p),
      paging: provider.productSearch,
      onLoadMore: provider.loadMoreProducts,
    );
  }

  Widget _section(Widget child, {Color? band}) {
    if (style == ListPresentation.compact) {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Pal.line))),
        child: child,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SoftCard(band: style == ListPresentation.guided ? band : null, child: child),
    );
  }

  Widget _buildProductDetailsLayout(ProductStatsProvider provider, ProductAnnualSale sales) {
    final bool isTabletLandscape = MediaQuery.of(context).size.width > 800;

    final details = _section(_buildDetailsColumn(provider, sales), band: Pal.navy);
    final consumption = _section(_buildConsumptionColumn(sales), band: Pal.blue);
    final comparison = _section(_buildComparisonSection(provider), band: Pal.green);
    final pad = style == ListPresentation.compact ? const EdgeInsets.only(bottom: 24) : const EdgeInsets.fromLTRB(16, 14, 16, 24);

    return ListView(
      padding: pad,
      children: isTabletLandscape
          ? [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: details),
                  const SizedBox(width: 16),
                  Expanded(child: consumption),
                ],
              ),
              comparison,
            ]
          : [details, consumption, comparison],
    );
  }

  Widget _title(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Pal.ink)),
      );

  Widget _buildDetailsColumn(ProductStatsProvider provider, ProductAnnualSale product) {
    final info = provider.selectedProductInfo; // Infos (pour le reste)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title('Article'),
        DetailLine('CIP', orDash(product.codeCip), bold: true),
        DetailLine('Désignation', orDash(product.libelle), bold: true),
        DetailLine('Prix Achat', Constants.formatNumber(info?.prixAchat ?? 0)),
        DetailLine('Prix Vente', Constants.formatNumber(info?.prixVente ?? 0)),
        DetailLine('Emplacement', orDash(info?.emplacement)),
        DetailLine('Grossiste', orDash(info?.grossiste)),
      ],
    );
  }

  Widget _buildConsumptionColumn(ProductAnnualSale product) {
    final current = DateTime.now().month - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title('Consommations (Année en cours)'),
        LayoutBuilder(builder: (context, c) {
          const gap = 8.0;
          final w = ((c.maxWidth - gap * 3) / 4).floorToDouble();
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (var i = 0; i < _monthKeys.length; i++)
                Container(
                  width: w,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  decoration: BoxDecoration(
                    color: i == current ? const Color(0xFFE3ECF7) : Pal.page,
                    borderRadius: BorderRadius.circular(10),
                    border: i == current ? Border.all(color: Pal.navy) : null,
                  ),
                  child: Column(children: [
                    Text(_monthShort[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Pal.muted)),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('${product.monthlySales[_monthKeys[i]] ?? 0}',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Pal.ink)),
                    ),
                  ]),
                ),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildComparisonSection(ProductStatsProvider provider) {
    if (provider.showComparisonChart) {
      return _buildComparisonChart(provider);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _title('Comparaison sur 3 ans'),
      const Text('Compare les ventes mensuelles de cette année avec les deux années précédentes.',
          style: TextStyle(fontSize: 13, color: Pal.muted)),
      const SizedBox(height: 12),
      SizedBox(
        height: 48,
        child: provider.isComparisonLoading
            ? const Center(child: CircularProgressIndicator())
            : OutlinedButton.icon(
                style: outlineButton,
                icon: const Icon(Icons.analytics),
                label: const Text('Comparer sur 3 ans'),
                onPressed: () => provider.loadComparisonData(),
              ),
      ),
    ]);
  }

  Widget _buildComparisonChart(ProductStatsProvider provider) {
    final colors = [Colors.blue, Colors.red, Colors.green];
    final currentYear = DateTime.now().year;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title('Comparaison des Ventes Mensuelles'),
        const SizedBox(height: 8),
        SizedBox(
          height: 260,
          child: LineChart(
            LineChartData(
              gridData: const FlGridData(show: true),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (value, meta) {
                  const months = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
                  final i = value.toInt();
                  return Text(i >= 0 && i < months.length ? months[i] : '');
                }, interval: 1, reservedSize: 30)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: true, border: Border.all(color: const Color(0xff37434d), width: 1)),
              lineBarsData: List.generate(provider.comparisonData.length, (index) {
                final saleData = provider.comparisonData[index];
                return LineChartBarData(
                  spots: List.generate(12, (monthIndex) {
                    return FlSpot(monthIndex.toDouble(), saleData.monthlySales[_monthKeys[monthIndex]]?.toDouble() ?? 0.0);
                  }),
                  isCurved: true,
                  color: colors[index % colors.length],
                  barWidth: 3,
                  isStrokeCapRound: true,
                  belowBarData: BarAreaData(show: false),
                );
              }),
              lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          final year = currentYear - spot.barIndex;
                          return LineTooltipItem(
                            '${spot.y.toInt()} ventes\n($year)',
                            TextStyle(color: spot.bar.color, fontWeight: FontWeight.bold),
                          );
                        }).toList();
                      }
                  )
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 16,
          runSpacing: 6,
          children: [
            for (var i = 0; i < provider.comparisonData.length; i++)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 12, height: 12, decoration: BoxDecoration(color: colors[i % colors.length], borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 6),
                Text('${currentYear - i}'),
              ]),
          ],
        ),
      ],
    );
  }
}
