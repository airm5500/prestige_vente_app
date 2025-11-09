// lib/screens/carnet_sale/widgets/step_3_products.dart
// 09/11/2025 19:15
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/providers/carnet_sale_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';
import 'carnet_cart_widget.dart';
import 'carnet_summary_footer.dart';

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
      Provider.of<CarnetSaleProvider>(context, listen: false)
          .searchProducts(_searchController.text);
    });
  }

  void _showQuantityDialog(ProductSearchResult product) {
    final provider = Provider.of<CarnetSaleProvider>(context, listen: false);
    final qteController = TextEditingController(text: '1');

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
    final isTabletLandscape = MediaQuery.of(context).size.width > 800;
    return isTabletLandscape ? _buildTabletLayout() : _buildMobileLayout();
  }

  Widget _buildMobileLayout() {
    return Column(
      children: [
        _buildSearchArea(),
        const Divider(height: 1),
        Expanded(child: _buildCartAndResultsOverlay()),
        const CarnetSummaryFooter(),
      ],
    );
  }

  Widget _buildTabletLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Column(
            children: [
              _buildSearchArea(),
              const Divider(height: 1),
              Expanded(child: _buildCartAndResultsOverlay()),
              const CarnetSummaryFooter(),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        const Expanded(
          flex: 6,
          child: CarnetCartWidget(),
        ),
      ],
    );
  }

  Widget _buildSearchArea() {
    final provider = Provider.of<CarnetSaleProvider>(context, listen: false);
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              provider.returnToBonStep();
            },
          ),
          Expanded(
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
          ),
        ],
      ),
    );
  }

  Widget _buildCartAndResultsOverlay() {
    return Consumer<CarnetSaleProvider>(
      builder: (context, provider, child) {
        final bool isTabletLandscape =
            MediaQuery.of(context).size.width > 800;

        return Stack(
          children: [
            if (!isTabletLandscape)
              const CarnetCartWidget(),

            // --- Product Search Results Overlay ---
            if (provider.productSearchResults.isNotEmpty)
              Container(
                color: Theme.of(context).scaffoldBackgroundColor.withAlpha(242),
                child: Scrollbar(
                  child: ListView.builder(
                    itemCount: provider.productSearchResults.length,
                    itemBuilder: (context, index) {
                      final product = provider.productSearchResults[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: ListTile(
                          title: Text(product.strNAME,
                              style:
                              const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: RichText(
                            text: TextSpan(
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: Colors.black54),
                              children: [
                                TextSpan(
                                    text: 'CIP: ${product.intCIP} | Stock: '),
                                TextSpan(
                                  text: product.intNUMBERAVAILABLE.toString(),
                                  style: const TextStyle(
                                    color: AppColors.secondary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                TextSpan(text: ' | Prix: '),
                                TextSpan(
                                  text: Constants.formatNumber(product.intPRICE),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                                if (product.strLIBELLEE.isNotEmpty)
                                  TextSpan(
                                    text: ' (${product.strLIBELLEE})',
                                    style: const TextStyle(
                                        fontStyle: FontStyle.italic),
                                  ),
                              ],
                            ),
                          ),
                          onTap: () => _showQuantityDialog(product),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}