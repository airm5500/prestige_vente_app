// lib/screens/product_search/product_search_screen.dart
// 28/09/2025 16:18
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:prestige_vente_app/providers/product_search_provider.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';

class ProductSearchScreen extends StatefulWidget {
  const ProductSearchScreen({super.key});

  @override
  State<ProductSearchScreen> createState() => _ProductSearchScreenState();
}

class _ProductSearchScreenState extends State<ProductSearchScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ProductSearchProvider>(context, listen: false).clear();
    });
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      Provider.of<ProductSearchProvider>(context, listen: false)
          .search(_searchController.text);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recherche Article')),
      body: Consumer<ProductSearchProvider>(
        builder: (context, provider, child) {
          return Column(
            children: [
              _buildSearchBar(provider),
              if (provider.isLoading) const LinearProgressIndicator(),
              Expanded(
                child: provider.selectedProduct != null
                    ? _buildDetailsLayout(provider)
                    : _buildSearchResults(provider),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchBar(ProductSearchProvider provider) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          labelText: 'Rechercher par CIP, Nom ou Scan',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              _searchController.clear();
              provider.clear();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResults(ProductSearchProvider provider) {
    if (provider.searchResults.isEmpty && _searchController.text.isNotEmpty) {
      return const Center(child: Text('Aucun résultat'));
    }
    return ListView.builder(
      itemCount: provider.searchResults.length,
      itemBuilder: (context, index) {
        final product = provider.searchResults[index];
        return Card(
          child: ListTile(
            title: Text(product.strName, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('CIP: ${product.intCip} | Stock: ${product.intNumber} | Prix: ${Constants.formatNumber(product.intPrice)}'),
            onTap: () => provider.selectProduct(product),
          ),
        );
      },
    );
  }

  Widget _buildDetailsLayout(ProductSearchProvider provider) {
    final bool isTabletLandscape = MediaQuery.of(context).size.width > 800;

    final infoCard = _buildProductInfoCard(provider);
    final comparisonCard = provider.hasComparisonData ? _buildComparisonCard(provider) : const SizedBox.shrink();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: isTabletLandscape
          ? Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 5, child: infoCard),
          const SizedBox(width: 16),
          Expanded(flex: 5, child: comparisonCard),
        ],
      )
          : Column(
        children: [
          infoCard,
          const SizedBox(height: 20),
          comparisonCard,
        ],
      ),
    );
  }

  Widget _buildProductInfoCard(ProductSearchProvider provider) {
    final product = provider.selectedProduct!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(product.strName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                _detailRow("Code CIP:", product.intCip),
                _detailRow("Prix Vente:", Constants.formatNumber(product.intPrice)),
                _detailRow("Prix Achat:", Constants.formatNumber(product.intPaf)),
                _detailRow("Stock:", product.intNumber.toString()),
                _detailRow("Emplacement:", product.lgZoneGeoId),
                _detailRow("Date Péremption:", product.dtPeremption),
                _detailRow("Dernière Vente:", product.dtLastVente),
                _detailRow("Dernière Entrée:", product.dtLastEntree),
                _detailRow("État (Cmd/Ent/Sug):",
                    '${product.produitState['enCommande']}/${product.produitState['entree']}/${product.produitState['enSuggestion']}'
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // CORRECTION : La section du graphique a été réécrite pour plus de clarté
  Widget _buildComparisonCard(ProductSearchProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Comparaison Ventes / Commandes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            SizedBox(
              height: 300,
              // On passe directement l'objet LineChartData au constructeur de LineChart
              child: LineChart(_buildChartData(provider)),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _legendItem(Colors.blue, "Ventes"),
                const SizedBox(width: 20),
                _legendItem(Colors.green, "Commandes"),
              ],
            )
          ],
        ),
      ),
    );
  }

  // CORRECTION : Création d'une fonction dédiée pour la configuration du graphique
  LineChartData _buildChartData(ProductSearchProvider provider) {
    return LineChartData(
      // Configuration des titres (axes)
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
        // Configuration des bordures et de la grille
        borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey.shade300)),
        gridData: const FlGridData(show: true),
        // Configuration des lignes (courbes)
        lineBarsData: [
          // Ligne des Ventes
          LineChartBarData(
            spots: provider.comparisonData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.sales.toDouble())).toList(),
            isCurved: true,
            color: Colors.blue,
            barWidth: 3,
          ),
          // Ligne des Commandes
          LineChartBarData(
            spots: provider.comparisonData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.orders.toDouble())).toList(),
            isCurved: true,
            color: Colors.green,
            barWidth: 3,
          )
        ]
    );
  }

  Widget _legendItem(Color color, String text) {
    return Row(children: [
      Container(width: 12, height: 12, color: color),
      const SizedBox(width: 8),
      Text(text),
    ]);
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54)),
          Flexible(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16))),
        ],
      ),
    );
  }
}