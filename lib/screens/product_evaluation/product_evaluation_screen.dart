// lib/screens/product_evaluation/product_evaluation_screen.dart
// 28/09/2025 16:46
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:prestige_vente_app/api/models/product_stats.dart';
import 'package:prestige_vente_app/providers/product_stats_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

class ProductEvaluationScreen extends StatefulWidget {
  const ProductEvaluationScreen({super.key});

  @override
  State<ProductEvaluationScreen> createState() => _ProductEvaluationScreenState();
}

class _ProductEvaluationScreenState extends State<ProductEvaluationScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ProductStatsProvider>(context, listen: false).clear();
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
      Provider.of<ProductStatsProvider>(context, listen: false)
          .searchProducts(_searchController.text);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Évaluation Vente Article')),
      body: Consumer<ProductStatsProvider>(
        builder: (context, provider, child) {
          return Column(
            children: [
              _buildSearchBar(provider),
              if (provider.isLoading)
                const LinearProgressIndicator(),
              Expanded(
                child: provider.selectedProductSales == null
                    ? _buildSearchResults(provider)
                    : _buildProductDetailsLayout(provider),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchBar(ProductStatsProvider provider) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _onSearchChanged(),
        decoration: InputDecoration(
          labelText: 'Rechercher par CIP ou Nom',
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

  Widget _buildSearchResults(ProductStatsProvider provider) {
    if (provider.searchResults.isEmpty && _searchController.text.length > 1) {
      return const Center(child: Text('Aucun produit trouvé.'));
    }
    return ListView.builder(
      itemCount: provider.searchResults.length,
      itemBuilder: (context, index) {
        final product = provider.searchResults[index];
        return ListTile(
          title: Text(product.libelle),
          subtitle: Text('CIP: ${product.codeCip}'),
          onTap: () {
            provider.selectProduct(product);
            _searchController.clear();
          },
        );
      },
    );
  }

  Widget _buildProductDetailsLayout(ProductStatsProvider provider) {
    final bool isTabletLandscape = MediaQuery.of(context).size.width > 800;

    final details = _buildDetailsColumn(provider);
    final consumption = _buildConsumptionColumn(provider);
    final comparison = _buildComparisonSection(provider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: isTabletLandscape
          ? Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: details),
              const SizedBox(width: 16),
              Expanded(child: consumption),
            ],
          ),
          const SizedBox(height: 16),
          comparison,
        ],
      )
          : Column(
        children: [
          details,
          const Divider(height: 30),
          consumption,
          const SizedBox(height: 30),
          comparison,
        ],
      ),
    );
  }

  Widget _buildDetailsColumn(ProductStatsProvider provider) {
    final product = provider.selectedProductSales!;
    final info = provider.selectedProductInfo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDetailRow('CIP:', product.codeCip, isBold: true),
        _buildDetailRow('Désignation:', product.libelle, isBold: true),
        _buildDetailRow('Prix Achat:', info?.prixAchat ?? 'N/A'),
        _buildDetailRow('Prix Vente:', info?.prixVente ?? 'N/A'),
        _buildDetailRow('Emplacement:', info?.emplacement ?? 'N/A'),
        _buildDetailRow('Grossiste:', info?.grossiste ?? 'N/A'),
      ],
    );
  }

  Widget _buildConsumptionColumn(ProductStatsProvider provider) {
    final product = provider.selectedProductSales!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Consommations (Année en cours):', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8.0,
          runSpacing: 4.0,
          children: product.monthlySales.entries.map((entry) {
            return Chip(
              label: Text('${entry.key}: ${entry.value}', style: TextStyle(fontWeight: FontWeight.bold)),
              backgroundColor: Colors.blue.shade50,
              visualDensity: VisualDensity.compact,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildComparisonSection(ProductStatsProvider provider) {
    if (provider.showComparisonChart) {
      return _buildComparisonChart(provider);
    }
    return provider.isComparisonLoading
        ? const Center(child: CircularProgressIndicator())
        : Center(
      child: ElevatedButton.icon(
        icon: const Icon(Icons.analytics),
        label: const Text('Comparer sur 3 ans'),
        onPressed: () => provider.loadComparisonData(),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
          Flexible(child: Text(value, textAlign: TextAlign.end, style: TextStyle(fontSize: 16, fontWeight: isBold ? FontWeight.bold : FontWeight.normal))),
        ],
      ),
    );
  }

  Widget _buildComparisonChart(ProductStatsProvider provider) {
    final colors = [Colors.blue, Colors.red, Colors.green];
    final currentYear = DateTime.now().year;
    return Column(
      children: [
        const Text('Comparaison des Ventes Mensuelles', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        SizedBox(
          height: 300,
          child: LineChart(
            LineChartData(
              gridData: FlGridData(show: true),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (value, meta) {
                  const months = ['Jan', 'Fev', 'Mar', 'Avr', 'Mai', 'Jui', 'Jui', 'Aou', 'Sep', 'Oct', 'Nov', 'Dec'];
                  return Text(months[value.toInt()]);
                }, interval: 1, reservedSize: 30)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: true, border: Border.all(color: const Color(0xff37434d), width: 1)),
              lineBarsData: List.generate(provider.comparisonData.length, (index) {
                final saleData = provider.comparisonData[index];
                return LineChartBarData(
                  spots: List.generate(12, (monthIndex) {
                    final monthName = DateFormat('MMMM', 'fr_FR').format(DateTime(0, monthIndex + 1)).toLowerCase();
                    return FlSpot(monthIndex.toDouble(), saleData.monthlySales[monthName]?.toDouble() ?? 0.0);
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
      ],
    );
  }
}