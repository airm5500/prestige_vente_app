// lib/screens/pre_vente/tabs/vente_tab.dart
// 11/11/2025 10:00 (Version Complete: Stock, Caisse, Focus, Auto-Open)
import 'dart:async';
//import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/api/models/user.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/screens/pre_vente/widgets/sale_cart_widget.dart';
import 'package:prestige_vente_app/services/receipt_service.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';
//import 'package:qr_flutter/qr_flutter.dart';
import 'package:prestige_vente_app/api/models/payment_method_qr.dart';

//import 'package:prestige_vente_app/providers/caisse_provider.dart';
import 'package:prestige_vente_app/widgets/cash_payment_dialog.dart';


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

  // Logique d'ouverture automatique (Scan)
  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final provider = Provider.of<SaleProvider>(context, listen: false);
      final query = _searchController.text;

      if (query.isEmpty) return;

      // 1. Lance la recherche
      await provider.searchProducts(query);

      // 2. Si un seul résultat, ouvre le dialogue
      if (mounted && provider.searchResults.length == 1) {
        final product = provider.searchResults.first;
        _showQuantityDialog(product);
      }
    });
  }

  void _showQuantityDialog(ProductSearchResult product) {
    final qteController = TextEditingController(text: '1');

    // Pré-sélection de la quantité pour saisie rapide
    qteController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: qteController.text.length,
    );

    void _addProduct(int quantity) {
      final provider = Provider.of<SaleProvider>(context, listen: false);
      provider.addProductToCart(product, quantity, isPrevente: widget.isPrevente);
      // Nettoyage immédiat de la liste
      provider.clearSearchResults();
      _searchController.clear();
      _searchFocusNode.requestFocus();
    }

    void submitQuantity() {
      final quantity = int.tryParse(qteController.text) ?? 0;
      Navigator.of(context).pop();
      if (quantity > 0) {
        // Vérification du stock
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

  Future<void> _showPrintDialog({
    required bool isPrevente, PaymentMethod? paymentMethod, required User currentUser,
    int? montantVerse,
    int? monnaie,
  }) async {
    final BuildContext mainContext = context;

    final settingsProvider = Provider.of<SettingsProvider>(mainContext, listen: false);
    final saleProvider = Provider.of<SaleProvider>(mainContext, listen: false);
    final authProvider = Provider.of<AuthProvider>(mainContext, listen: false);
    final receiptService = ReceiptService();

    final summaryToPrint = saleProvider.saleSummary;
    final itemsToPrint = List<SaleItemDetail>.from(saleProvider.cartItems);
    final int numberOfTickets = isPrevente ? 1 : settingsProvider.numberOfTickets;
    final String ticketCodeType = settingsProvider.ticketCodeType;
    final int paperWidth = settingsProvider.paperWidth;
    final bool isTestMode = settingsProvider.isTestPrintMode;

    final bool? printFirstTicket = await showDialog<bool>(
      context: mainContext,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(isPrevente ? 'Prévente terminée' : 'Vente terminée'),
        content: const Text('Voulez-vous imprimer le ticket ?'),
        actions: [
          TextButton(
            child: const Text('Non'),
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          ElevatedButton(
            child: const Text('Oui'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    Future<void> _printLogic() async {
      if (isPrevente) {
        await receiptService.printPreventeTicket(
          context: mainContext, officine: authProvider.officine!,
          saleSummary: summaryToPrint, currentUser: currentUser,
          isTestMode: isTestMode, paperWidth: paperWidth,
          ticketCodeType: ticketCodeType,
        );
      } else {
        await receiptService.printSaleTicket(
          context: mainContext, officine: authProvider.officine!,
          saleSummary: summaryToPrint, items: itemsToPrint,
          paymentMethod: paymentMethod!, currentUser: currentUser,
          isTestMode: isTestMode, paperWidth: paperWidth,
          showQrCode: settingsProvider.showQrCodeOnSaleTicket,
          ticketCodeType: ticketCodeType,
          montantVerse: montantVerse,
          monnaie: monnaie,
        );
      }
    }

    if (printFirstTicket == true) {
      await _printLogic();

      for (int i = 1; i < numberOfTickets; i++) {
        if (!mainContext.mounted) break;
        final bool? rePrint = await showDialog<bool>(
          context: mainContext,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Réimpression'),
            content: Text('Voulez-vous réimprimer le ticket ? (${i + 1}/$numberOfTickets)'),
            actions: [
              TextButton(
                child: const Text('Non'),
                onPressed: () => Navigator.of(ctx).pop(false),
              ),
              ElevatedButton(
                child: const Text('Oui'),
                onPressed: () => Navigator.of(ctx).pop(true),
              ),
            ],
          ),
        );
        if (rePrint == true) {
          await _printLogic();
        } else {
          break;
        }
      }
    }

    saleProvider.startNewSale();
  }


  Future<void> _showQrCodeDialog(PaymentMethodQr method, SaleSummary summary, User currentUser) async {
    final BuildContext mainContext = context;

    await showDialog(
      context: mainContext,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: Text("Paiement via ${method.name}"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Veuillez scanner le QR code pour payer ${Constants.formatNumber(summary.montantNet)}."),
              const SizedBox(height: 20),
              SizedBox(
                width: 250,
                height: 250,
                child: method.qrCode != null
                    ? Image.memory(method.qrCode!)
                    : const Center(child: Text("QR Code non disponible")),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              child: const Text("OK"),
              onPressed: () {
                Navigator.of(ctx).pop();
                _showPrintDialog(
                    isPrevente: false,
                    paymentMethod: PaymentMethod(id: method.id, name: method.name),
                    currentUser: currentUser
                );
              },
            )
          ],
        );
      },
    );
  }

  Future<void> _showCashPaymentDialog(PaymentMethod method, User currentUser) async {
    final BuildContext mainContext = context;
    final scaffoldMessenger = ScaffoldMessenger.of(mainContext);
    final saleProvider = Provider.of<SaleProvider>(mainContext, listen: false);

    final result = await showDialog<Map<String, int>>(
      context: mainContext,
      builder: (ctx) => CashPaymentDialog(
        montantNet: saleProvider.saleSummary.montantNet,
      ),
    );

    if (result != null) {
      final int montantVerse = result['verse']!;
      final int monnaie = result['monnaie']!;

      final apiResult = await saleProvider.cloturerVente(
        method,
        currentUser,
        montantRecu: montantVerse,
        montantRemis: monnaie,
      );

      if (!mainContext.mounted) return;

      final bool caisseHandled = await Constants.checkAndOpenCaisse(mainContext, apiResult);
      if (caisseHandled) {
        return;
      }

      if (apiResult['success'] == true) {
        scaffoldMessenger.showSnackBar(const SnackBar(
          content: Text('Vente validée avec succès !'),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 2),
        ));

        _showPrintDialog(
          isPrevente: false,
          paymentMethod: method,
          currentUser: currentUser,
          montantVerse: montantVerse,
          monnaie: monnaie,
        );

      } else {
        scaffoldMessenger.showSnackBar(SnackBar(
          content: Text(saleProvider.errorMessage ?? "La validation a échoué"),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 2),
        ));
      }
    }
  }

  void _showPaymentDialog() async {
    final BuildContext mainContext = context;
    final scaffoldMessenger = ScaffoldMessenger.of(mainContext);
    final saleProvider = Provider.of<SaleProvider>(mainContext, listen: false);
    final authProvider = Provider.of<AuthProvider>(mainContext, listen: false);
    final settingsProvider = Provider.of<SettingsProvider>(mainContext, listen: false);

    final currentUser = authProvider.user;
    if (currentUser == null) {
      Constants.showSnackBar(mainContext, "Erreur: Utilisateur non trouvé", isError: true);
      return;
    }

    final allPaymentMethods = await saleProvider.apiService.getPaymentMethods();
    if (!mainContext.mounted) return;

    final allowedIds = settingsProvider.enabledPaymentMethodIds;
    final filteredMethods = allPaymentMethods
        .where((method) => allowedIds.contains(method.id))
        .toList();

    if (filteredMethods.isEmpty) {
      Constants.showSnackBar(mainContext, "Aucun mode de règlement n'est activé. Vérifiez les paramètres.", isError: true);
      return;
    }

    showDialog(
        context: mainContext,
        builder: (ctx) => AlertDialog(
          title: const Text('Choisir un mode de règlement'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: filteredMethods.length,
              itemBuilder: (context, index) {
                final method = filteredMethods[index];
                return ListTile(
                  title: Text(method.name),
                  onTap: () async {
                    Navigator.of(ctx).pop();

                    if (method.id == '1') {
                      _showCashPaymentDialog(method, currentUser);
                    } else {
                      final result = await saleProvider.cloturerVente(method, currentUser);
                      if (!mainContext.mounted) return;

                      final bool caisseHandled = await Constants.checkAndOpenCaisse(mainContext, result);
                      if (caisseHandled) { return; }

                      if (result['success'] == true) {
                        scaffoldMessenger.showSnackBar(const SnackBar(
                          content: Text('Vente validée avec succès !'),
                          backgroundColor: AppColors.success,
                          duration: Duration(seconds: 2),
                        ));

                        final paymentQrMethods = saleProvider.paymentMethodsWithQr;
                        PaymentMethodQr? qrMethod;
                        try {
                          qrMethod = paymentQrMethods.firstWhere((m) => m.id == method.id);
                        } catch (e) {
                          qrMethod = null;
                        }

                        if (qrMethod != null && qrMethod.qrCode != null) {
                          await _showQrCodeDialog(qrMethod, saleProvider.saleSummary, currentUser);
                        } else {
                          _showPrintDialog(isPrevente: false, paymentMethod: method, currentUser: currentUser);
                        }

                      } else {
                        scaffoldMessenger.showSnackBar(SnackBar(
                          content: Text(saleProvider.errorMessage ?? "La validation a échoué"),
                          backgroundColor: AppColors.error,
                          duration: const Duration(seconds: 2),
                        ));
                      }
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
    final bool isTabletLandscape = MediaQuery.of(context).size.width > 800;
    return isTabletLandscape ? _buildTabletLayout() : _buildMobileLayout();
  }

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
              _buildSummaryFooter(),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          flex: 6,
          child: Container(
            color: Colors.black.withOpacity(0.03),
            child: const SaleCartWidget(),
          ),
        ),
      ],
    );
  }

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
              _searchFocusNode.requestFocus();
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
        final bool isTabletLandscape = MediaQuery.of(context).size.width > 800;

        return Stack(
          children: [
            if (!isTabletLandscape)
              const SaleCartWidget(),

            if (saleProvider.searchResults.isNotEmpty)
              Container(
                color: Theme.of(context).scaffoldBackgroundColor.withAlpha(242),
                child: Scrollbar(
                  child: ListView.builder(
                    itemCount: saleProvider.searchResults.length,
                    itemBuilder: (context, index) {
                      final product = saleProvider.searchResults[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: ListTile(
                          title: Text(product.strNAME, style: const TextStyle(fontWeight: FontWeight.bold)),
                          // STYLE HARMONISÉ
                          subtitle: RichText(
                            text: TextSpan(
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
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
                    Text(
                      'Net à Payer: ${Constants.formatNumber(summary.montantNet)}',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.primary),
                    ),
                  ],
                ),
                saleProvider.isLoading
                    ? const CircularProgressIndicator()
                    : SizedBox(
                  width: 56,
                  height: 56,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: EdgeInsets.zero,
                      backgroundColor: widget.isPrevente ? Colors.orange : AppColors.success,
                    ),
                    child: Icon(widget.isPrevente ? Icons.save : Icons.check_circle, color: Colors.white),
                    onPressed: saleProvider.cartItems.isEmpty ? null : () async {
                      if (widget.isPrevente) {
                        final authProvider = Provider.of<AuthProvider>(context, listen: false);
                        final currentUser = authProvider.user;
                        if(currentUser != null) {
                          final success = await saleProvider.terminerPrevente();
                          if (mounted && success) {
                            _showPrintDialog(isPrevente: true, currentUser: currentUser);
                          }
                        }
                      } else {
                        _showPaymentDialog();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}