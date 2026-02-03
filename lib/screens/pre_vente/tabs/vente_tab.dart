// lib/screens/pre_vente/tabs/vente_tab.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/api/models/user.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/screens/pre_vente/widgets/sale_cart_widget.dart';
import 'package:prestige_vente_app/services/receipt_service.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/api/models/payment_method_qr.dart';
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
  final _keyboardFocusNode = FocusNode();
  Timer? _debounce;
  String _scanBuffer = "";
  bool _isPopupOpen = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestSearchFocus();
    });
  }

  void _requestSearchFocus() {
    if (mounted && !_isPopupOpen) {
      FocusScope.of(context).requestFocus(_searchFocusNode);
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _keyboardFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    final sale = Provider.of<SaleProvider>(context, listen: false);
    if (!sale.isQuickScanMode) return;

    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        if (_scanBuffer.isNotEmpty) {
          _performSearch(_scanBuffer.trim(), isScan: true);
          _scanBuffer = "";
        }
      } else if (event.character != null) {
        _scanBuffer += event.character!;
      }
    }
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (_searchController.text.trim().isNotEmpty) {
        _performSearch(_searchController.text.trim(), isScan: false);
      } else {
        Provider.of<SaleProvider>(context, listen: false).clearSearchResults();
      }
    });
  }

  Future<void> _performSearch(String query, {required bool isScan}) async {
    final provider = Provider.of<SaleProvider>(context, listen: false);
    await provider.searchProducts(query);

    if (!mounted) return;

    final results = provider.searchResults;

    if (results.length == 1) {
      final product = results.first;
      if (provider.isQuickScanMode) {
        provider.clearSearchResults();
        _searchController.clear();
        await provider.addProductToCart(product, 1, isPrevente: widget.isPrevente);
        _requestSearchFocus();
      } else {
        _showQuantityDialog(product);
      }
    } else if (results.isNotEmpty) {
      _showSelectionDialog(results);
    }
  }

  void _showSelectionDialog(List<ProductSearchResult> products) {
    final provider = Provider.of<SaleProvider>(context, listen: false);
    setState(() => _isPopupOpen = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text("Résultats (${products.length})"),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: products.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (ctx, index) {
              final p = products[index];
              return ListTile(
                title: Text(p.strNAME, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("CIP: ${p.intCIP} | Stock: ${p.intNUMBERAVAILABLE} | Prix: ${Constants.formatNumber(p.intPRICE)} F"),
                onTap: () {
                  provider.clearSearchResults();
                  Navigator.of(ctx).pop(); // Fermeture immédiate
                  _showQuantityDialog(p);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () {
                provider.clearSearchResults();
                Navigator.of(ctx).pop();
              },
              child: const Text("Fermer")
          )
        ],
      ),
    ).then((_) {
      if (mounted) {
        setState(() => _isPopupOpen = false);
        _requestSearchFocus();
      }
    });
  }

  void _showQuantityDialog(ProductSearchResult product) {
    final qteController = TextEditingController(text: '1');
    qteController.selection = TextSelection(baseOffset: 0, extentOffset: qteController.text.length);

    setState(() => _isPopupOpen = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(product.strNAME),
        content: TextField(
          controller: qteController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Quantité'),
          keyboardType: TextInputType.number,
          onSubmitted: (val) {
            final q = int.tryParse(val) ?? 1;
            Navigator.of(ctx).pop(); // Ferme avant d'ajouter
            _executeAdd(product, q);
          },
        ),
        actions: [
          TextButton(onPressed: () {
            Provider.of<SaleProvider>(context, listen: false).clearSearchResults();
            Navigator.of(ctx).pop();
          }, child: const Text('Annuler')),
          ElevatedButton(onPressed: () {
            final q = int.tryParse(qteController.text) ?? 1;
            Navigator.of(ctx).pop(); // Ferme avant d'ajouter
            _executeAdd(product, q);
          }, child: const Text('Ajouter')),
        ],
      ),
    ).then((_) {
      if (mounted) {
        setState(() => _isPopupOpen = false);
        _requestSearchFocus();
      }
    });
  }

  void _executeAdd(ProductSearchResult product, int qty) async {
    final provider = Provider.of<SaleProvider>(context, listen: false);
    provider.clearSearchResults();
    _searchController.clear();
    await provider.addProductToCart(product, qty, isPrevente: widget.isPrevente);
    _requestSearchFocus();
  }

  // --- MÉTHODES D'IMPRESSION ET PAIEMENT ---

  Future<void> _showPrintDialog({
    required bool isPrevente, PaymentMethod? paymentMethod, required User currentUser,
    int? montantVerse, int? monnaie,
  }) async {
    final BuildContext mainContext = context;
    final settingsProvider = Provider.of<SettingsProvider>(mainContext, listen: false);
    final saleProvider = Provider.of<SaleProvider>(mainContext, listen: false);
    final authProvider = Provider.of<AuthProvider>(mainContext, listen: false);
    final receiptService = ReceiptService();

    final bool? printFirstTicket = await showDialog<bool>(
      context: mainContext, barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(isPrevente ? 'Prévente terminée' : 'Vente terminée'),
        content: const Text('Voulez-vous imprimer le ticket ?'),
        actions: [
          TextButton(child: const Text('Non'), onPressed: () => Navigator.of(ctx).pop(false)),
          ElevatedButton(child: const Text('Oui'), onPressed: () => Navigator.of(ctx).pop(true)),
        ],
      ),
    );

    if (printFirstTicket == true) {
      if (isPrevente) {
        await receiptService.printPreventeTicket(
          context: mainContext, officine: authProvider.officine!,
          saleSummary: saleProvider.saleSummary, currentUser: currentUser,
          isTestMode: settingsProvider.isTestPrintMode, paperWidth: settingsProvider.paperWidth, ticketCodeType: settingsProvider.ticketCodeType,
        );
      } else {
        await receiptService.printSaleTicket(
          context: mainContext, officine: authProvider.officine!,
          saleSummary: saleProvider.saleSummary, items: saleProvider.cartItems,
          paymentMethod: paymentMethod!, currentUser: currentUser,
          isTestMode: settingsProvider.isTestPrintMode, paperWidth: settingsProvider.paperWidth,
          showQrCode: settingsProvider.showQrCodeOnSaleTicket, ticketCodeType: settingsProvider.ticketCodeType,
          montantVerse: montantVerse, monnaie: monnaie,
        );
      }
    }
    saleProvider.startNewSale();
    _requestSearchFocus();
  }

  // RÉINTÉGRÉ ET SÉCURISÉ : Dialogue QR
  Future<void> _showQrCodeDialog(PaymentMethodQr method, SaleSummary summary, User currentUser) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text("Paiement via ${method.name}"),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text("Veuillez scanner le QR code pour payer ${Constants.formatNumber(summary.montantNet)}."),
          const SizedBox(height: 20),
          SizedBox(
            width: 250,
            height: 250,
            child: method.qrCode != null
                ? Image.memory(method.qrCode!)
                : const Center(child: Text("QR Code non disponible")),
          ),
        ]),
        actions: [
          ElevatedButton(
              child: const Text("OK"),
              onPressed: () {
                Navigator.of(ctx).pop();
                _showPrintDialog(isPrevente: false, paymentMethod: PaymentMethod(id: method.id, name: method.name), currentUser: currentUser);
              }
          )
        ],
      ),
    );
  }

  Future<void> _showCashPaymentDialog(PaymentMethod method, User currentUser) async {
    final saleProvider = Provider.of<SaleProvider>(context, listen: false);
    final result = await showDialog<Map<String, int>>(context: context, builder: (ctx) => CashPaymentDialog(montantNet: saleProvider.saleSummary.montantNet));
    if (result != null) {
      final apiResult = await saleProvider.cloturerVente(method, currentUser, montantRecu: result['verse'], montantRemis: result['monnaie']);
      if (!mounted) return;
      if (await Constants.checkAndOpenCaisse(context, apiResult)) return;
      if (apiResult['success'] == true) {
        _showPrintDialog(isPrevente: false, paymentMethod: method, currentUser: currentUser, montantVerse: result['verse'], monnaie: result['monnaie']);
      }
    }
  }

  void _showPaymentDialog() async {
    final saleProvider = Provider.of<SaleProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    final currentUser = authProvider.user;
    if (currentUser == null) return;

    final allMethods = await saleProvider.apiService.getPaymentMethods();
    final allowedIds = settingsProvider.enabledPaymentMethodIds;
    final filteredMethods = allMethods.where((m) => allowedIds.contains(m.id)).toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mode de règlement'),
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
                  Navigator.of(ctx).pop(); // Ferme la sélection

                  if (method.id == '1') {
                    _showCashPaymentDialog(method, currentUser);
                  } else {
                    final res = await saleProvider.cloturerVente(method, currentUser);
                    if (!mounted) return;
                    if (await Constants.checkAndOpenCaisse(context, res)) return;

                    if (res['success'] == true) {
                      // Charger les méthodes QR si pas encore fait
                      await saleProvider.fetchPaymentMethodsWithQr();
                      final paymentQrMethods = saleProvider.paymentMethodsWithQr;

                      PaymentMethodQr? qrMethod;
                      try {
                        qrMethod = paymentQrMethods.firstWhere((m) => m.id == method.id);
                      } catch (e) {
                        qrMethod = null;
                      }

                      if (qrMethod != null && qrMethod.qrCode != null) {
                        _showQrCodeDialog(qrMethod, saleProvider.saleSummary, currentUser);
                      } else {
                        _showPrintDialog(isPrevente: false, paymentMethod: method, currentUser: currentUser);
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(saleProvider.errorMessage ?? "Erreur de clôture"),
                        backgroundColor: Colors.red,
                      ));
                    }
                  }
                },
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isTabletLandscape = MediaQuery.of(context).size.width > 800;
    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: isTabletLandscape ? _buildTabletLayout() : _buildMobileLayout(),
    );
  }

  Widget _buildMobileLayout() {
    return Column(children: [ _buildSearchArea(), const Divider(height: 1), Expanded(child: _buildCartAndResultsOverlay()), _buildSummaryFooter() ]);
  }

  Widget _buildTabletLayout() {
    return Row(children: [
      Expanded(flex: 4, child: Column(children: [_buildSearchArea(), const Divider(height: 1), Expanded(child: _buildCartAndResultsOverlay()), _buildSummaryFooter()])),
      const VerticalDivider(width: 1),
      const Expanded(flex: 6, child: SaleCartWidget()),
    ]);
  }

  Widget _buildSearchArea() {
    return Consumer<SaleProvider>(builder: (context, sale, child) {
      final bool isActive = sale.isQuickScanMode;
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          autofocus: true,
          decoration: InputDecoration(
            labelText: isActive ? 'SCAN RAPIDE ACTIF' : 'Rechercher un produit (CIP ou Nom)',
            labelStyle: TextStyle(color: isActive ? Colors.green : null, fontWeight: isActive ? FontWeight.bold : null),
            prefixIcon: Icon(isActive ? Icons.bolt : Icons.search, color: isActive ? Colors.green : null),
            border: const OutlineInputBorder(),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: isActive ? Colors.green : Colors.grey, width: isActive ? 2.5 : 1.0),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: isActive ? Colors.green : Theme.of(context).primaryColor, width: isActive ? 2.5 : 2.0),
            ),
          ),
          onSubmitted: (val) => _performSearch(val, isScan: true),
        ),
      );
    });
  }

  Widget _buildCartAndResultsOverlay() {
    return Consumer<SaleProvider>(builder: (context, saleProvider, child) {
      final bool isTablet = MediaQuery.of(context).size.width > 800;
      return Stack(children: [
        if (!isTablet) const SaleCartWidget(),
        if (!saleProvider.isQuickScanMode && !_isPopupOpen && saleProvider.searchResults.isNotEmpty)
          Container(
            color: Theme.of(context).scaffoldBackgroundColor.withAlpha(242),
            child: ListView.separated(
              itemCount: saleProvider.searchResults.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final product = saleProvider.searchResults[index];
                return ListTile(
                  title: Text(product.strNAME, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("CIP: ${product.intCIP} | Stock: ${product.intNUMBERAVAILABLE} | Prix: ${Constants.formatNumber(product.intPRICE)}"),
                  onTap: () => _showQuantityDialog(product),
                );
              },
            ),
          ),
      ]);
    });
  }

  Widget _buildSummaryFooter() {
    return Consumer<SaleProvider>(builder: (context, saleProvider, child) {
      final summary = saleProvider.saleSummary;
      return Card(
        elevation: 4, margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Total: ${Constants.formatNumber(summary.montant)}'),
              Text('Net: ${Constants.formatNumber(summary.montantNet)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.primary)),
            ]),
            saleProvider.isLoading ? const CircularProgressIndicator() : ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: widget.isPrevente ? Colors.orange : AppColors.success, shape: const CircleBorder(), padding: const EdgeInsets.all(15)),
              child: Icon(widget.isPrevente ? Icons.save : Icons.check_circle, color: Colors.white),
              onPressed: saleProvider.cartItems.isEmpty ? null : () {
                if (widget.isPrevente) {
                  _showPrintDialog(isPrevente: true, currentUser: Provider.of<AuthProvider>(context, listen: false).user!);
                } else {
                  _showPaymentDialog();
                }
              },
            ),
          ]),
        ),
      );
    });
  }
}