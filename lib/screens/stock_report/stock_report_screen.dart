// lib/screens/stock_report/stock_report_screen.dart
// 12/11/2025 15:30 (Focus Recherche après Emplacement)
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/api/models/stock_report_models.dart';
import 'package:prestige_vente_app/api/models/rayon.dart';
import 'package:prestige_vente_app/providers/stock_report_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

class StockReportScreen extends StatefulWidget {
  const StockReportScreen({super.key});

  @override
  State<StockReportScreen> createState() => _StockReportScreenState();
}

class _StockReportScreenState extends State<StockReportScreen> {
  final _searchController = TextEditingController();
  final _stockValueController = TextEditingController();

  final _searchFocusNode = FocusNode();
  final _stockValueFocusNode = FocusNode();

  Timer? _debounce;

  Rayon? _selectedRayon;
  StockFilterType? _selectedFilterType;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<StockReportProvider>(context, listen: false);
      provider.loadFiltersData();
      provider.clearFilters();

      if(mounted) FocusScope.of(context).requestFocus(_searchFocusNode);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _stockValueController.dispose();
    _searchFocusNode.dispose();
    _stockValueFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      Provider.of<StockReportProvider>(context, listen: false).setQuery(value);
    });
  }

  void _onStockValueChanged(String value) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      Provider.of<StockReportProvider>(context, listen: false).setStockValue(value);
    });
  }

  void _onClearFilters() {
    _searchController.clear();
    _stockValueController.clear();

    setState(() {
      _selectedRayon = null;
      _selectedFilterType = null;
    });

    Provider.of<StockReportProvider>(context, listen: false).clearFilters();

    _searchFocusNode.requestFocus();
  }

  void _showDetailDialog(StockReportItem item) {
    final provider = Provider.of<StockReportProvider>(context, listen: false);
    final grossisteName = provider.getGrossisteName(item.grossisteId);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item.libelle),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow("Code (CIP):", item.code),
              _detailRow("Code EAN:", item.codeEan),
              _detailRow("Emplacement:", item.rayonLibelle),
              const Divider(),
              _detailRow("Stock:", item.stock.toString(), isBold: true, color: AppColors.primary),
              _detailRow("Prix Vente:", Constants.formatNumber(item.prixVente)),
              _detailRow("Prix Achat:", Constants.formatNumber(item.prixAchat)),
              _detailRow("TVA:", item.tva),
              const Divider(),
              _detailRow("Grossiste:", grossisteName),
              _detailRow("Date Entrée:", item.dateEntree),
              _detailRow("Dernière Vente:", item.lastDateVente),
              _detailRow("Date Inventaire:", item.dateInventaire),
              const Divider(),
              _detailRow("Seuil Réappro:", item.seuiRappro.toString()),
              _detailRow("Qté à Réappro:", item.qteReappro.toString()),
            ],
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Fermer'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54)),
          Flexible(
            child: Text(
              value.isEmpty ? '-' : value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                color: color ?? Colors.black87,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('État de Stock'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cleaning_services),
            tooltip: 'Vider les filtres',
            onPressed: _onClearFilters,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFiltersArea(),
          const Divider(height: 1),
          Expanded(
            child: Consumer<StockReportProvider>(
              builder: (context, provider, child) {
                if (provider.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (provider.reportItems.isEmpty) {
                  if (provider.searchQuery.isEmpty && provider.selectedRayonId.isEmpty && provider.selectedStockFilter == null) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.filter_alt, size: 60, color: Colors.grey),
                          SizedBox(height: 16),
                          Text("Saisissez des critères pour rechercher", style: TextStyle(color: Colors.grey, fontSize: 16)),
                        ],
                      ),
                    );
                  }
                  return const Center(child: Text("Aucun article trouvé."));
                }

                return ListView.builder(
                  itemCount: provider.reportItems.length,
                  itemBuilder: (context, index) {
                    final item = provider.reportItems[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: ListTile(
                        title: Text(item.libelle, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('CIP: ${item.code} | Empl: ${item.rayonLibelle}'),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                                'Stock: ${item.stock}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.secondary)
                            ),
                            Text('${Constants.formatNumber(item.prixVente)} F'),
                          ],
                        ),
                        onTap: () => _showDetailDialog(item),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersArea() {
    return Consumer<StockReportProvider>(
      builder: (context, provider, child) {
        return Card(
          elevation: 2,
          margin: const EdgeInsets.all(8.0),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                // Ligne 1 : Recherche Texte
                TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  decoration: InputDecoration(
                    labelText: 'Rechercher (Nom, CIP, Scan)',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          provider.setQuery('');
                          _searchFocusNode.requestFocus();
                        }
                    )
                        : null,
                    isDense: true,
                  ),
                  onChanged: _onSearchChanged,
                ),
                const SizedBox(height: 12),

                // Ligne 2 : Filtres Stock
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<StockFilterType>(
                        value: _selectedFilterType,
                        decoration: const InputDecoration(labelText: 'Filtre Stock', isDense: true, border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: null, child: Text('Aucun')),
                          DropdownMenuItem(value: StockFilterType.EQUAL, child: Text('Égal à (=)')),
                          DropdownMenuItem(value: StockFilterType.GREATER, child: Text('Supérieur à (> )')),
                          DropdownMenuItem(value: StockFilterType.LESS, child: Text('Inférieur à (< )')),
                          DropdownMenuItem(value: StockFilterType.GREATER_EQUAL, child: Text('Sup. ou Égal (>=)')),
                          DropdownMenuItem(value: StockFilterType.LESS_EQUAL, child: Text('Inf. ou Égal (<=)')),
                        ],
                        onChanged: (val) {
                          setState(() => _selectedFilterType = val);
                          if (val == null) {
                            _stockValueController.clear();
                            provider.setStockValue('');
                            provider.setStockFilter(null);
                          } else {
                            provider.setStockFilter(val);
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if(mounted) FocusScope.of(context).requestFocus(_stockValueFocusNode);
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 1,
                      child: TextFormField(
                        controller: _stockValueController,
                        focusNode: _stockValueFocusNode,
                        decoration: const InputDecoration(labelText: 'Valeur', isDense: true, border: OutlineInputBorder()),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        enabled: _selectedFilterType != null,
                        onChanged: _onStockValueChanged,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Ligne 3 : Emplacement
                DropdownButtonFormField<String>(
                  value: _selectedRayon?.id,
                  decoration: const InputDecoration(labelText: 'Emplacement', isDense: true, border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem<String>(value: null, child: Text('Tous les emplacements')),
                    ...provider.rayons.map((r) => DropdownMenuItem(value: r.id, child: Text(r.libelle, overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (val) {
                    setState(() {
                      if (val == null) {
                        _selectedRayon = null;
                      } else {
                        _selectedRayon = provider.rayons.firstWhere((r) => r.id == val);
                      }
                    });
                    provider.setRayon(val ?? '');

                    // MODIFICATION : Focus retour à la recherche
                    _searchFocusNode.requestFocus();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}