// lib/screens/pre_vente/tabs/vente_tab.dart
// 28/09/2025 16:00
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/screens/pre_vente/widgets/sale_cart_widget.dart';
import 'package:prestige_vente_app/services/receipt_service.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

class VenteTab extends StatefulWidget {
  final bool isPrevente;
  const VenteTab({super.key, required this.isPrevente});

  @override
  State<VenteTab> createState() => _VenteTabState();
}

class _VenteTabState extends State<VenteTab> {
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
      Provider.of<SaleProvider>(context, listen: false)
          .searchProducts(_searchController.text);
    });
  }

  void _showQuantityDialog(ProductSearchResult product) {
    final qteController = TextEditingController(text: '1');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(product.strNAME),
        content: TextField(
          controller: qteController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Quantité'),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
            child: const Text('Annuler'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          ElevatedButton(
            child: const Text('Ajouter'),
            onPressed: () {
              final quantity = int.tryParse(qteController.text) ?? 0;
              Navigator.of(ctx).pop();
              if (quantity > 0) {
                _checkStockAndAddProduct(product, quantity);
              }
            },
          ),
        ],
      ),
    );
  }

  void _checkStockAndAddProduct(ProductSearchResult product, int quantity) {
    void _addProduct() {
      Provider.of<SaleProvider>(context, listen: false)
          .addProductToCart(product, quantity, isPrevente: widget.isPrevente);
      _searchController.clear();
      _searchFocusNode.requestFocus();
    }

    if (quantity > product.intNUMBERAVAILABLE) {
      showDialog(
        context: context,
        builder: (confirmCtx) => AlertDialog(
          title: const Text('Stock insuffisant'),
          content: Text(
              'Le stock disponible est de ${product.intNUMBERAVAILABLE}. Voulez-vous continuer quand même ?'),
          actions: [
            TextButton(
              child: const Text('Non'),
              onPressed: () {
                Navigator.of(confirmCtx).pop();
                _searchFocusNode.requestFocus();
              },
            ),
            ElevatedButton(
              child: const Text('Oui'),
              onPressed: () {
                Navigator.of(confirmCtx).pop();
                _addProduct();
              },
            ),
          ],
        ),
      );
    } else {
      _addProduct();
    }
  }

  void _showPrintDialog({required bool isPrevente, PaymentMethod? paymentMethod}) {
    final saleProvider = Provider.of<SaleProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final receiptService = ReceiptService();
    final summaryToPrint = saleProvider.saleSummary;
    final itemsToPrint = List<SaleItemDetail>.from(saleProvider.cartItems);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(isPrevente ? 'Prévente terminée' : 'Vente terminée'),
        content: const Text('Voulez-vous imprimer le ticket ?'),
        actions: [
          TextButton(
            child: const Text('Non'),
            onPressed: () { Navigator.of(ctx).pop(); saleProvider.startNewSale(); },
          ),
          ElevatedButton(
            child: const Text('Oui'),
            onPressed: () {
              if (isPrevente) {
                receiptService.printPreventeTicket(context: context, officine: authProvider.officine!, saleSummary: summaryToPrint);
              } else {
                receiptService.printSaleTicket(context: context, officine: authProvider.officine!, saleSummary: summaryToPrint, items: itemsToPrint, paymentMethod: paymentMethod!);
              }
              Navigator.of(ctx).pop();
              saleProvider.startNewSale();
            },
          ),
        ],
      ),
    );
  }

  void _showPaymentDialog() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final saleProvider = Provider.of<SaleProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.user;

    if (currentUser == null) {
      Constants.showSnackBar(context, "Erreur: Utilisateur non trouvé", isError: true);
      return;
    }
    final paymentMethods = await saleProvider.apiService.getPaymentMethods();
    if (!mounted) return;
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Choisir un mode de règlement'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: paymentMethods.length,
              itemBuilder: (context, index) {
                final method = paymentMethods[index];
                return ListTile(
                  title: Text(method.name),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    final success = await saleProvider.cloturerVente(method, currentUser);
                    if (success) {
                      scaffoldMessenger.showSnackBar(const SnackBar(content: Text('Vente validée avec succès !'), backgroundColor: AppColors.success));
                      _showPrintDialog(isPrevente: false, paymentMethod: method);
                    } else {
                      scaffoldMessenger.showSnackBar(SnackBar(content: Text(saleProvider.errorMessage ?? "La validation a échoué"), backgroundColor: AppColors.error));
                    }
                  },
                );
              },
            ),
          ),
        ));
  }

  @override
  Widget build(BuildContext context) {
    // CORRECTION : On détecte la largeur de l'écran pour choisir la bonne mise en page.
    // Un breakpoint à 800 est un bon début pour les tablettes en mode paysage.
    final bool isTabletLandscape = MediaQuery.of(context).size.width > 800;

    return isTabletLandscape ? _buildTabletLayout() : _buildMobileLayout();
  }

  // --- Mise en page pour Mobile (ou tablette en portrait) ---
  Widget _buildMobileLayout() {
    return Column(
      children: [
        _buildSearchArea(),
        const Divider(height: 1),
        Expanded(child: _buildCartAndResultsOverlay()),
        _buildSummaryFooter(),
      ],
    );
  }

  // --- Mise en page pour Tablette en Paysage ---
  Widget _buildTabletLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Colonne de gauche (Recherche et Résumé)
        Expanded(
          flex: 4, // Prend 40% de l'espace
          child: Column(
            children: [
              _buildSearchArea(),
              const Divider(height: 1),
              Expanded(child: _buildCartAndResultsOverlay()), // Le panier est ici pour la superposition des résultats
              _buildSummaryFooter(),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        // Colonne de droite (Panier seul)
        Expanded(
          flex: 6, // Prend 60% de l'espace
          child: Container(
            color: Colors.black.withOpacity(0.03), // Léger fond pour délimiter
            child: const SaleCartWidget(),
          ),
        ),
      ],
    );
  }

  // --- Widgets partagés ---

  Widget _buildSearchArea() {
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
              Provider.of<SaleProvider>(context, listen: false).searchProducts('');
            },
          )
              : null,
        ),
      ),
    );
  }

  Widget _buildCartAndResultsOverlay() {
    return Consumer<SaleProvider>(
      builder: (context, saleProvider, child) {
        // En mode tablette, le panier est à droite, donc on n'affiche que les résultats ici
        final bool isTabletLandscape = MediaQuery.of(context).size.width > 800;

        return Stack(
          children: [
            // En mode mobile, on affiche le panier en fond. En mode tablette, cet espace est vide.
            if (!isTabletLandscape)
              const SaleCartWidget(),

            if (saleProvider.searchResults.isNotEmpty)
              Container(
                color: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.95),
                child: Scrollbar(
                  child: ListView.builder(
                    itemCount: saleProvider.searchResults.length,
                    itemBuilder: (context, index) {
                      final product = saleProvider.searchResults[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: ListTile(
                          title: Text(product.strNAME, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('CIP: ${product.intCIP} | Stock: ${product.intNUMBERAVAILABLE} | Prix: ${Constants.formatNumber(product.intPRICE)}'),
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

  Widget _buildSummaryFooter() {
    return Consumer<SaleProvider>(
      builder: (context, saleProvider, child) {
        final summary = saleProvider.saleSummary;
        return Card(
          elevation: 4,
          margin: const EdgeInsets.all(0),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total: ${Constants.formatNumber(summary.montant)}', style: const TextStyle(fontSize: 16)),
                    Text('Remise: ${Constants.formatNumber(summary.remise)}', style: const TextStyle(fontSize: 16)),
                    Text(
                      'Net à Payer: ${Constants.formatNumber(summary.montantNet)}',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.primary),
                    ),
                  ],
                ),
                saleProvider.isLoading
                    ? const CircularProgressIndicator()
                    : ElevatedButton.icon(
                  icon: Icon(widget.isPrevente ? Icons.save : Icons.check_circle),
                  label: Text(widget.isPrevente ? 'Terminer PREvente' : 'Valider Vente'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.isPrevente ? Colors.orange : AppColors.success,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                  ),
                  onPressed: saleProvider.cartItems.isEmpty ? null : () async {
                    if (widget.isPrevente) {
                      final success = await saleProvider.terminerPrevente();
                      if (mounted && success) {
                        _showPrintDialog(isPrevente: true);
                      }
                    } else {
                      _showPaymentDialog();
                    }
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