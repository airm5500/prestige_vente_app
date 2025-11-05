// lib/screens/assurance_sale/widgets/step_3_products.dart
// 05/11/2025 00:30 (Corrigé)
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/providers/assurance_sale_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/utils/responsive.dart';
import 'package:provider/provider.dart';
import 'assurance_cart_widget.dart';
import 'assurance_summary_footer.dart';

class Step3ProductsWidget extends StatefulWidget {
  const Step3ProductsWidget({super.key});

  @override
  State<Step3ProductsWidget> createState() => _Step3ProductsWidgetState();
}

class _Step3ProductsWidgetState extends State<Step3ProductsWidget> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_searchFocusNode);
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      Provider.of<AssuranceSaleProvider>(context, listen: false)
          .searchProducts(_searchController.text);
    });
  }

  void _showQuantityDialog(ProductSearchResult product) {
    final qteController = TextEditingController(text: '1');
    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);

    void submitQuantity() {
      final quantity = int.tryParse(qteController.text) ?? 0;
      Navigator.of(context).pop();
      if (quantity > 0) {
        provider.addProductToCart(product, quantity);
        _searchController.clear();
        _searchFocusNode.requestFocus();
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(product.strNAME),
        content: TextField(
          controller: qteController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Quantité'),
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => submitQuantity(),
        ),
        actions: [
          TextButton(
            child: const Text('Annuler'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          ElevatedButton(
            child: const Text('Ajouter'),
            onPressed: submitQuantity,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AssuranceSaleProvider>(context);

    final bool isTabletLandscape = Responsive.isTablet(context) || Responsive.isDesktop(context);

    return Column(
      children: [
        // Header pour revenir à l'étape 2
        Material(
          color: Colors.grey[100],
          child: ListTile(
            leading: const Icon(Icons.person_pin),
            title: Text(provider.selectedClient?.fullName ?? 'Client'),
            subtitle: Text(provider.selectedAyantDroit?.fullName ?? 'Ayant droit'),
            trailing: TextButton.icon(
              icon: const Icon(Icons.edit, size: 18),
              // MODIFICATION (Point 8) - Libellé plus clair
              label: const Text('Modif. Bon/Patient'),
              onPressed: () => provider.returnToBonStep(),
            ),
          ),
        ),

        Expanded(
          child: isTabletLandscape
              ? _buildTabletLayout(provider)
              : _buildMobileLayout(provider),
        ),

        const AssuranceSummaryFooter(),
      ],
    );
  }

  Widget _buildMobileLayout(AssuranceSaleProvider provider) {
    return Column(
      children: [
        _buildSearchArea(provider),
        const Divider(height: 1),
        Expanded(
          child: Stack(
            children: [
              const AssuranceCartWidget(),
              if (provider.productSearchResults.isNotEmpty)
                _buildSearchResultsOverlay(provider),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabletLayout(AssuranceSaleProvider provider) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Column(
            children: [
              _buildSearchArea(provider),
              const Divider(height: 1),
              Expanded(
                child: _buildSearchResultsList(provider),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          flex: 6,
          child: Container(
            color: Colors.black.withOpacity(0.03),
            child: const AssuranceCartWidget(),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchArea(AssuranceSaleProvider provider) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        decoration: InputDecoration(
          labelText: 'Rechercher un produit (CIP ou Nom)',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              _searchController.clear();
              provider.clearProductSearch();
            },
          )
              : null,
        ),
      ),
    );
  }

  Widget _buildSearchResultsOverlay(AssuranceSaleProvider provider) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor.withAlpha(242),
      child: _buildSearchResultsList(provider),
    );
  }

  Widget _buildSearchResultsList(AssuranceSaleProvider provider) {
    if (provider.productSearchResults.isEmpty && _searchController.text.isNotEmpty && !provider.isLoading) {
      return const Center(child: Text('Aucun produit trouvé.'));
    }

    return Scrollbar(
      child: ListView.builder(
        itemCount: provider.productSearchResults.length,
        itemBuilder: (context, index) {
          final product = provider.productSearchResults[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: ListTile(
              title: Text(product.strNAME,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                  'CIP: ${product.intCIP} | Stock: ${product.intNUMBERAVAILABLE} | Prix: ${Constants.formatNumber(product.intPRICE)}'),
              onTap: () => _showQuantityDialog(product),
            ),
          );
        },
      ),
    );
  }
}