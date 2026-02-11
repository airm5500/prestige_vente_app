// lib/screens/pre_vente/tabs/vente_tab.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/api/models/product.dart';
//import 'package:prestige_vente_app/api/models/product_search_result.dart';
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
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestSearchFocus();
      Provider.of<SaleProvider>(context, listen: false).fetchPaymentMethodsWithQr();
    });
  }

  void _requestSearchFocus() {
    if (mounted && !_isPopupOpen && !_isProcessing) {
      FocusScope.of(context).requestFocus(_searchFocusNode);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _keyboardFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    final sale = Provider.of<SaleProvider>(context, listen: false);
    if (!sale.isQuickScanMode || _isPopupOpen) return;

    if (_searchFocusNode.hasFocus && _searchController.text.isNotEmpty) {
      _scanBuffer = "";
      return;
    }

    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        if (_scanBuffer.isNotEmpty) {
          _performSearch(_scanBuffer.trim(), autoAddIfUnique: true);
          _scanBuffer = "";
        }
      } else if (event.character != null) {
        _scanBuffer += event.character!;
      }
    }
  }

  void _onSearchChanged(String val) {
    final sale = Provider.of<SaleProvider>(context, listen: false);
    if (sale.isQuickScanMode) return;

    if (val.isEmpty) {
      sale.clearSearchResults();
      return;
    }

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted || _isPopupOpen) return;
      if (val.trim().length >= 2) {
        _performSearch(val.trim(), autoAddIfUnique: false);
      }
    });
  }

  Future<void> _performSearch(String query, {required bool autoAddIfUnique}) async {
    _debounce?.cancel();
    if (_isProcessing || _isPopupOpen || query.isEmpty) return;

    final provider = Provider.of<SaleProvider>(context, listen: false);
    setState(() => _isProcessing = true);

    try {
      await provider.searchProducts(query);
      if (!mounted || _isPopupOpen) return;

      final results = provider.searchResults;

      if (results.isEmpty) {
        if (autoAddIfUnique) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Produit introuvable"), backgroundColor: Colors.orange, duration: Duration(seconds: 1)),
          );
          _searchController.clear();
        }
      } else {
        if (results.length == 1) {
          final product = results.first;
          _searchController.clear();
          provider.clearSearchResults();

          if (autoAddIfUnique) {
            _checkStockAndAddDirectly(product);
          } else {
            _showQuantityDialog(product);
          }
        } else {
          _openEnrichedSearchModal(results);
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
        if (!_isPopupOpen) _requestSearchFocus();
      }
    }
  }

  void _checkStockAndAddDirectly(ProductSearchResult product) {
    if (product.intNUMBERAVAILABLE <= 0) {
      _showForceStockDialog(product, 1);
    } else {
      Provider.of<SaleProvider>(context, listen: false).addProductToCart(product, 1, isPrevente: widget.isPrevente);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${product.strNAME} ajouté (+1)"), duration: const Duration(milliseconds: 500), backgroundColor: Colors.green),
      );
    }
  }

  void _openEnrichedSearchModal(List<ProductSearchResult> initialResults) async {
    setState(() => _isPopupOpen = true);

    final selectedProduct = await showModalBottomSheet<ProductSearchResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ProductListModal(
        results: initialResults,
        initialQuery: _searchController.text,
        onProductSelected: (p) => Navigator.pop(ctx, p),
      ),
    );

    if (mounted) setState(() => _isPopupOpen = false);

    if (selectedProduct != null) {
      _searchController.clear();
      Provider.of<SaleProvider>(context, listen: false).clearSearchResults();
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _showQuantityDialog(selectedProduct);
      });
    } else {
      _requestSearchFocus();
    }
  }

  void _showQuantityDialog(ProductSearchResult product) async {
    setState(() => _isPopupOpen = true);

    final qty = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => QuantityDialog(product: product),
    );

    if (mounted) setState(() => _isPopupOpen = false);

    if (qty != null) {
      if (qty > product.intNUMBERAVAILABLE) {
        _showForceStockDialog(product, qty);
      } else {
        _executeAdd(product, qty);
      }
    } else {
      _requestSearchFocus();
    }
  }

  void _showForceStockDialog(ProductSearchResult product, int qty) async {
    setState(() => _isPopupOpen = true);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stock insuffisant', style: TextStyle(color: Colors.red)),
        content: Text('Stock dispo : ${product.intNUMBERAVAILABLE}.\nForcer l\'ajout de $qty ?'),
        actions: [
          TextButton(child: const Text('Non'), onPressed: () => Navigator.pop(ctx, false)),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('OUI', style: TextStyle(color: Colors.white))
          ),
        ],
      ),
    );
    if (mounted) setState(() => _isPopupOpen = false);
    if (confirm == true) {
      _executeAdd(product, qty);
    } else {
      _requestSearchFocus();
    }
  }

  void _executeAdd(ProductSearchResult product, int qty) async {
    final provider = Provider.of<SaleProvider>(context, listen: false);
    provider.clearSearchResults();
    _searchController.clear();
    await provider.addProductToCart(product, qty, isPrevente: widget.isPrevente);
    if (mounted) _requestSearchFocus();
  }

  // --- LOGIQUE METIER ORIGINALE ---

  Future<void> _showPrintDialog({
    required bool isPrevente, PaymentMethod? paymentMethod, required User currentUser,
    int? montantVerse, int? monnaie,
  }) async {
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    final saleProvider = Provider.of<SaleProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final receiptService = ReceiptService();

    final bool? printFirstTicket = await showDialog<bool>(
      context: context, barrierDismissible: false,
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
          context: context, officine: authProvider.officine!,
          saleSummary: saleProvider.saleSummary, currentUser: currentUser,
          isTestMode: settingsProvider.isTestPrintMode, paperWidth: settingsProvider.paperWidth, ticketCodeType: settingsProvider.ticketCodeType,
        );
      } else {
        await receiptService.printSaleTicket(
          context: context, officine: authProvider.officine!,
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

  Future<void> _showPaymentConfirmationDialog({
    required PaymentMethod method,
    required User currentUser,
    PaymentMethodQr? qrMethod,
    int? montantRecu,
    int? montantRemis,
  }) async {
    final saleProvider = Provider.of<SaleProvider>(context, listen: false);
    setState(() => _isPopupOpen = true);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirmation de Paiement"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Mode : ${method.name}", style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text("Montant Net : ${Constants.formatNumber(saleProvider.saleSummary.montantNet)} F",
                  style: const TextStyle(fontSize: 18, color: Colors.blue, fontWeight: FontWeight.bold)),
              const Divider(height: 30),
              if (qrMethod != null && qrMethod.qrCode != null) ...[
                const Text("Scanner pour payer :"),
                const SizedBox(height: 10),
                SizedBox(width: 180, height: 180, child: Image.memory(qrMethod.qrCode!, fit: BoxFit.contain)),
              ] else
                const Text("Veuillez confirmer l'encaissement."),
            ],
          ),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(ctx).pop(),
                  icon: const Icon(Icons.arrow_back, color: Colors.white, size: 18),
                  label: const Text("RETOUR", style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    final apiResult = await saleProvider.cloturerVente(method, currentUser, montantRecu: montantRecu, montantRemis: montantRemis);
                    if (!mounted) return;
                    if (await Constants.checkAndOpenCaisse(context, apiResult)) return;
                    if (apiResult['success'] == true) {
                      _showPrintDialog(isPrevente: false, paymentMethod: method, currentUser: currentUser, montantVerse: montantRecu, monnaie: montantRemis);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(saleProvider.errorMessage ?? "La validation a échoué"), backgroundColor: Colors.red));
                    }
                  },
                  icon: const Icon(Icons.check_circle, color: Colors.white, size: 18),
                  label: const Text("VALIDER", style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700),
                ),
              ),
            ],
          ),
        ],
      ),
    ).then((_) {
      if (mounted) {
        setState(() => _isPopupOpen = false);
        _requestSearchFocus();
      }
    });
  }

  Future<void> _showCashPaymentDialog(PaymentMethod method, User currentUser) async {
    final saleProvider = Provider.of<SaleProvider>(context, listen: false);
    final result = await showDialog<Map<String, int>>(
        context: context,
        builder: (ctx) => CashPaymentDialog(montantNet: saleProvider.saleSummary.montantNet)
    );
    if (result != null) {
      _showPaymentConfirmationDialog(method: method, currentUser: currentUser, montantRecu: result['verse'], montantRemis: result['monnaie']);
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
                    Navigator.of(ctx).pop();
                    if (method.id == '1') {
                      _showCashPaymentDialog(method, currentUser);
                    } else {
                      final paymentQrMethods = saleProvider.paymentMethodsWithQr;
                      PaymentMethodQr? qrM;
                      try { qrM = paymentQrMethods.firstWhere((m) => m.id == method.id); } catch (e) { qrM = null; }
                      _showPaymentConfirmationDialog(method: method, currentUser: currentUser, qrMethod: qrM);
                    }
                  }
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
    return Column(children: [ _buildSearchArea(), const Divider(height: 1), const Expanded(child: SaleCartWidget()), _buildSummaryFooter() ]);
  }

  Widget _buildTabletLayout() {
    return Row(children: [
      Expanded(flex: 4, child: Column(children: [_buildSearchArea(), const Divider(height: 1), const Expanded(child: Center(child: Text("Recherchez un produit"))), _buildSummaryFooter()])),
      const VerticalDivider(width: 1),
      const Expanded(flex: 6, child: SaleCartWidget()),
    ]);
  }

  Widget _buildSearchArea() {
    return Consumer<SaleProvider>(builder: (context, sale, child) {
      final bool isActive = sale.isQuickScanMode;
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: isActive ? 'SCAN RAPIDE ACTIF' : 'Rechercher (Nom/CIP)',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  prefixIcon: _isProcessing
                      ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(isActive ? Icons.bolt : Icons.search, color: isActive ? Colors.green : null),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () { _searchController.clear(); sale.clearSearchResults(); _requestSearchFocus(); },
                  ),
                  border: const OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: isActive ? Colors.green : Colors.grey, width: isActive ? 2.5 : 1.0),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: isActive ? Colors.green : Theme.of(context).primaryColor, width: isActive ? 2.5 : 2.0),
                  ),
                  filled: true,
                  // CORRECTION : withValues au lieu de withOpacity
                  fillColor: isActive ? Colors.green.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.05),
                ),
                onSubmitted: (val) => _performSearch(val, autoAddIfUnique: isActive),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: () {
                sale.toggleQuickScanMode();
                _requestSearchFocus();
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isActive ? Colors.green : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: isActive ? Colors.green.shade700 : Colors.grey),
                ),
                child: Icon(isActive ? Icons.flash_on : Icons.flash_off, color: isActive ? Colors.white : Colors.grey.shade700),
              ),
            ),
          ],
        ),
      );
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
              Text('Net: ${Constants.formatNumber(summary.montantNet)}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor)),
            ]),
            saleProvider.isLoading ? const CircularProgressIndicator() : ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: widget.isPrevente ? Colors.orange : Colors.green, shape: const CircleBorder(), padding: const EdgeInsets.all(15)),
              child: Icon(widget.isPrevente ? Icons.save : Icons.check_circle, color: Colors.white),
              onPressed: saleProvider.cartItems.isEmpty ? null : () async {
                if (widget.isPrevente) {
                  final bool success = await saleProvider.terminerPrevente();
                  if (success) {
                    if (!mounted) return;
                    _showPrintDialog(isPrevente: true, currentUser: Provider.of<AuthProvider>(context, listen: false).user!);
                  } else {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Erreur lors de l'enregistrement"), backgroundColor: Colors.red));
                  }
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

// =========================================================
// QUANTITY DIALOG (DESIGN COMPACT DEMANDÉ)
// =========================================================
class QuantityDialog extends StatefulWidget {
  final ProductSearchResult product;
  const QuantityDialog({super.key, required this.product});

  @override
  State<QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<QuantityDialog> {
  final _formKey = GlobalKey<FormState>();
  final _qteController = TextEditingController(text: "1");
  final _qtyFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _qtyFocusNode.requestFocus();
        _qteController.selection = TextSelection(baseOffset: 0, extentOffset: _qteController.text.length);
      }
    });
  }

  @override
  void dispose() {
    _qtyFocusNode.unfocus();
    _qtyFocusNode.dispose();
    _qteController.dispose();
    super.dispose();
  }

  void _submit() async {
    if (!_formKey.currentState!.validate()) {
      _qtyFocusNode.requestFocus();
      _qteController.selection = TextSelection(baseOffset: 0, extentOffset: _qteController.text.length);
      return;
    }
    final qty = int.parse(_qteController.text);
    if (qty > 50) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text("Confirmation"),
          content: Text("Ajouter $qty unités ?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("NON")),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("OUI, CONFIRMER")),
          ],
        ),
      );
      if (confirm != true) {
        _qtyFocusNode.requestFocus();
        _qteController.selection = TextSelection(baseOffset: 0, extentOffset: _qteController.text.length);
        return;
      }
    }
    Navigator.pop(context, qty);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.product.strNAME, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 11, color: Colors.grey),
              children: [
                const TextSpan(text: "CIP: "),
                TextSpan(text: "${widget.product.intCIP} ", style: const TextStyle(color: Colors.black54)),
                const TextSpan(text: "| Stock: "),
                TextSpan(text: "${widget.product.intNUMBERAVAILABLE} ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                const TextSpan(text: "| Prix: "),
                TextSpan(text: "${Constants.formatNumber(widget.product.intPRICE)} F", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
              ],
            ),
          ),
        ],
      ),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _qteController,
          focusNode: _qtyFocusNode,
          decoration: const InputDecoration(labelText: 'Quantité', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 10)),
          keyboardType: TextInputType.number,
          validator: (val) {
            if (val == null || val.isEmpty) return "Requis";
            if (int.tryParse(val) == null) return "Invalide";
            if (int.parse(val) <= 0) return "Min 1";
            if (val.length > 4) return "Trop grand !";
            return null;
          },
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        ElevatedButton(onPressed: _submit, child: const Text('Ajouter')),
      ],
    );
  }
}

// =========================================================
// MODAL RÉSULTATS (CLONE DESIGN CARNET)
// =========================================================
class ProductListModal extends StatefulWidget {
  final List<ProductSearchResult> results;
  final String initialQuery;
  final Function(ProductSearchResult) onProductSelected;
  const ProductListModal({super.key, required this.results, required this.initialQuery, required this.onProductSelected});

  @override
  State<ProductListModal> createState() => _ProductListModalState();
}

class _ProductListModalState extends State<ProductListModal> {
  late List<ProductSearchResult> _filteredList;
  final TextEditingController _modalSearchCtrl = TextEditingController();
  final FocusNode _modalFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _filteredList = widget.results;
    _modalSearchCtrl.text = widget.initialQuery;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _modalFocusNode.requestFocus();
        _modalSearchCtrl.selection = TextSelection.fromPosition(
            TextPosition(offset: _modalSearchCtrl.text.length));
      }
    });
  }

  @override
  void dispose() {
    _modalFocusNode.unfocus();
    _modalFocusNode.dispose();
    _modalSearchCtrl.dispose();
    super.dispose();
  }

  void _filterResults(String query) {
    setState(() {
      _filteredList = widget.results
          .where((p) =>
      p.strNAME.toLowerCase().contains(query.toLowerCase()) ||
          p.intCIP.toString().contains(query))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    // RÉCUPÉRATION DE LA HAUTEUR DU CLAVIER
    final double keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      // On s'assure que le modal prend bien la taille nécessaire
      height: MediaQuery.of(context).size.height * 0.85,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0), // Pas de padding bas fixe
      decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      child: Column(
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text("Résultats (${_filteredList.length})",
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 10),
          TextField(
            controller: _modalSearchCtrl,
            focusNode: _modalFocusNode,
            decoration: const InputDecoration(
                hintText: "Filtrer dans la liste...",
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true),
            onChanged: _filterResults,
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              // AJOUT DU PADDING BAS DYNAMIQUE
              // On ajoute la hauteur du clavier + un petit bonus de 20px pour l'esthétique
              padding: EdgeInsets.only(bottom: keyboardHeight + 20),
              itemCount: _filteredList.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, index) {
                final p = _filteredList[index];
                return ListTile(
                  dense: true,
                  title: Text(p.strNAME,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 12, color: Colors.black87),
                      children: [
                        TextSpan(text: "CIP: ${p.intCIP} | "),
                        TextSpan(
                            text: "Stock: ${p.intNUMBERAVAILABLE}",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.withValues(alpha: 1))),
                        const TextSpan(text: " | "),
                        TextSpan(
                            text: "Prix: ${Constants.formatNumber(p.intPRICE)} F",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green.withValues(alpha: 1))),
                      ],
                    ),
                  ),
                  onTap: () => widget.onProductSelected(p),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}