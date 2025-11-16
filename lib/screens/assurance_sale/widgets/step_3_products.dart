// lib/screens/assurance_sale/widgets/step_3_products.dart
// 09/11/2025 20:15 (Correction Focus)
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/providers/assurance_sale_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
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
    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);
    final qteController = TextEditingController(text: '1');

    void _addProduct(int quantity) {
      provider.addProductToCart(product, quantity);
      _searchController.clear();
      _searchFocusNode.requestFocus();
    }

    void submitQuantity() {
      final quantity = int.tryParse(qteController.text) ?? 0;
      Navigator.of(context).pop();
      if (quantity <= 0) return;

      if (quantity > product.intNUMBERAVAILABLE) {
        showDialog(
          context: context,
          builder: (confirmCtx) => AlertDialog(
            title: const Text('Stock insuffisant'),
            content: Text('Le stock disponible est de ${product.intNUMBERAVAILABLE}. Voulez-vous continuer quand même ?'),
            actions: [
              TextButton(
                  child: const Text('Non'),
                  onPressed: () {
                    Navigator.of(confirmCtx).pop();
                    _searchFocusNode.requestFocus();
                  }
              ),
              ElevatedButton(
                child: const Text('Oui'),
                onPressed: () {
                  Navigator.of(confirmCtx).pop();
                  _addProduct(quantity);
                },
              ),
            ],
          ),
        );
      } else {
        _addProduct(quantity);
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
    final isTabletLandscape = MediaQuery.of(context).size.width > 800;

    return Column(
      children: [
        Material(
          color: Colors.grey[100],
          child: ListTile(
            leading: const Icon(Icons.person_pin),
            title: Text(provider.selectedClient?.fullName ?? 'Client'),
            subtitle: Text(provider.selectedAyantDroit?.fullName ?? 'Ayant droit'),
            trailing: TextButton.icon(
              icon: const Icon(Icons.edit, size: 18),
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
        const Expanded(
          flex: 6,
          child: AssuranceCartWidget(),
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
              // **LA CORRECTION EST ICI**
              _searchFocusNode.requestFocus();
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
              subtitle: RichText(
                text: TextSpan(
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.black54),
                  children: [
                    TextSpan(text: 'CIP: ${product.intCIP} | Stock: '),
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
                        style: const TextStyle(fontStyle: FontStyle.italic),
                      ),
                  ],
                ),
              ),
              onTap: () => _showQuantityDialog(product),
            ),
          );
        },
      ),
    );
  }
}