// lib/screens/depot_sale/depot_sale_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/api/models/product.dart';
//import 'package:prestige_vente_app/api/models/product_search_result.dart'; // Import nécessaire pour le type
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/depot_model.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/providers/depot_sale_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';

class DepotSaleScreen extends StatefulWidget {
  const DepotSaleScreen({Key? key}) : super(key: key);

  @override
  State<DepotSaleScreen> createState() => _DepotSaleScreenState();
}

class _DepotSaleScreenState extends State<DepotSaleScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _depotFocusNode = FocusNode();
  final FocusNode _keyboardFocusNode = FocusNode();

  List<DepotModel> _availableDepots = [];
  bool _isLoadingDepots = false;
  bool _isProcessing = false;

  String _scanBuffer = "";
  Timer? _debounce;
  bool _isPopupOpen = false;

  // --- VARIABLES INTELLIGENCE SCAN ---
  String? _lastScannedCIP;
  int _scanRepeatCount = 0;

  @override
  void initState() {
    super.initState();
    _loadDepots();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<DepotSaleProvider>(context, listen: false);
      if (provider.selectedDepot == null) {
        _depotFocusNode.requestFocus();
      } else {
        _requestSearchFocus();
      }
    });
  }

  void _requestSearchFocus() {
    if (mounted && !_isPopupOpen && !_isProcessing) {
      _searchFocusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _depotFocusNode.dispose();
    _keyboardFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // --- 1. GESTION SCAN PHYSIQUE ---
  void _handleKeyEvent(KeyEvent event) {
    final provider = Provider.of<DepotSaleProvider>(context, listen: false);
    if (!provider.isQuickScanMode || _isPopupOpen) return;

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

  Future<void> _loadDepots() async {
    setState(() => _isLoadingDepots = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final list = await api.fetchDepots();
      if (mounted) {
        setState(() {
          _availableDepots = list;
          _isLoadingDepots = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingDepots = false);
    }
  }

  // --- 2. GESTION SAISIE CLAVIER ---
  void _onSearchChanged(String value) {
    final provider = Provider.of<DepotSaleProvider>(context, listen: false);
    if (provider.isQuickScanMode) return;

    if (value.isEmpty) {
      provider.clearSearchResults();
      // Reset intelligence si on efface manuellement
      _scanRepeatCount = 0;
      _lastScannedCIP = null;
      return;
    }

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted && value.trim().length >= 2) {
        _performSearch(value.trim(), autoAddIfUnique: false);
      }
    });
  }

  // --- 3. LOGIQUE DE RECHERCHE ---
  Future<void> _performSearch(String query, {required bool autoAddIfUnique}) async {
    if (_isProcessing || _isPopupOpen || query.isEmpty) return;

    final provider = Provider.of<DepotSaleProvider>(context, listen: false);
    if (provider.selectedDepot == null) {
      _showError("Veuillez d'abord sélectionner un Dépôt / Client");
      _searchController.clear();
      return;
    }

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
            // --- LOGIQUE INTELLIGENTE "SCAN RÉPÉTÉ" ---
            if (_lastScannedCIP == product.intCIP.toString()) {
              _scanRepeatCount++;
              if (_scanRepeatCount >= 3) {
                _showSmartBulkDialog(product, provider);
                return;
              }
            } else {
              _lastScannedCIP = product.intCIP.toString();
              _scanRepeatCount = 1;
            }
            _checkStockAndAddDirectly(product);
          } else {
            // Reset intelligence si on passe en manuel
            _scanRepeatCount = 0;
            _lastScannedCIP = null;
            _showQuantityDialog(product);
          }
        } else {
          _showEnrichedSelectionModal(results);
        }
      }
    } catch (e) {
      _showError("Erreur : $e");
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
        if (!_isPopupOpen) _requestSearchFocus();
      }
    }
  }

  // --- NOUVEAU DIALOG INTELLIGENT ---
  void _showSmartBulkDialog(ProductSearchResult product, DepotSaleProvider provider) async {
    setState(() => _isPopupOpen = true);

    final qty = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => QuantityDialog(product: product, isSmartMode: true),
    );

    if (mounted) setState(() => _isPopupOpen = false);

    if (qty != null) {
      // Si une masse est saisie (>1), on reset le compteur rafale
      if (qty > 1) {
        _scanRepeatCount = 0;
        _lastScannedCIP = null;
      }

      if (qty > product.intNUMBERAVAILABLE) {
        _showForceStockDialog(product, qty);
      } else {
        _addProductToCart(product, qty: qty);
      }
    } else {
      // Annulation : on ajoute l'unité scannée mais on garde le compteur à 3 (persistance)
      _checkStockAndAddDirectly(product);
    }
  }

  void _checkStockAndAddDirectly(ProductSearchResult product) {
    if (product.intNUMBERAVAILABLE <= 0) {
      _showForceStockDialog(product, 1);
    } else {
      _addProductToCart(product, qty: 1);
    }
  }

  // --- 4. MODAL RÉSULTATS ---
  void _showEnrichedSelectionModal(List<ProductSearchResult> results) async {
    setState(() => _isPopupOpen = true);

    final selectedProduct = await showModalBottomSheet<ProductSearchResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ProductListModal(
        results: results,
        initialQuery: _searchController.text,
        onProductSelected: (p) => Navigator.pop(ctx, p),
      ),
    );

    if (mounted) setState(() => _isPopupOpen = false);

    if (selectedProduct != null) {
      _searchController.clear();
      Provider.of<DepotSaleProvider>(context, listen: false).clearSearchResults();
      // Reset intelligence sur sélection manuelle
      _scanRepeatCount = 0;
      _lastScannedCIP = null;
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _showQuantityDialog(selectedProduct);
      });
    } else {
      _requestSearchFocus();
    }
  }

  // --- 5. POPUP QUANTITÉ ---
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
        _addProductToCart(product, qty: qty);
      }
    } else {
      _requestSearchFocus();
    }
  }

  Future<void> _addProductToCart(ProductSearchResult product, {int qty = 1}) async {
    final provider = Provider.of<DepotSaleProvider>(context, listen: false);
    final success = await provider.addToCart(product, qty: qty);

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("${product.strNAME} ajouté (+ $qty)"),
            duration: const Duration(milliseconds: 500),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _searchController.clear();
      } else {
        _showError(provider.errorMessage.isNotEmpty ? provider.errorMessage : "Erreur ajout");
      }
      _requestSearchFocus();
    }
  }

  Future<void> _showForceStockDialog(ProductSearchResult product, int qty) async {
    setState(() => _isPopupOpen = true);
    final bool? confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Stock Insuffisant"),
        content: Text("Stock disponible : ${product.intNUMBERAVAILABLE}.\nForcer l'ajout de $qty ?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Non")),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Oui, Forcer", style: TextStyle(color: Colors.white))
          ),
        ],
      ),
    );
    if (mounted) setState(() => _isPopupOpen = false);
    if (confirm == true) {
      _addProductToCart(product, qty: qty);
    } else {
      _requestSearchFocus();
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.red));
  }

  void _confirmDeleteItem(SaleLine item) {
    setState(() => _isPopupOpen = true);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Supprimer ?"),
        content: Text("Retirer ${item.strNAME} de la vente ?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Non")),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                Navigator.pop(ctx);
                Provider.of<DepotSaleProvider>(context, listen: false).removeItem(item.lgPREENREGISTREMENTDETAILID);
              },
              child: const Text("Oui", style: TextStyle(color: Colors.white))
          ),
        ],
      ),
    ).then((_) {
      setState(() => _isPopupOpen = false);
      _requestSearchFocus();
    });
  }

  void _showEditDialog(SaleLine item) async {
    setState(() => _isPopupOpen = true);
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => EditLineDialog(item: item),
    );
    if (mounted) {
      setState(() => _isPopupOpen = false);
      _requestSearchFocus();
    }
  }

  Future<void> _validateSale() async {
    final provider = Provider.of<DepotSaleProvider>(context, listen: false);
    if (provider.cartItems.isEmpty) return;

    setState(() => _isPopupOpen = true);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Clôturer Vente Dépôt"),
        content: Text("Total: ${Constants.formatNumber(provider.totalAmount)} FCFA\nConfirmer la clôture ?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Non")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Oui")),
        ],
      ),
    );
    setState(() => _isPopupOpen = false);

    if (confirm == true) {
      final success = await provider.closeSale();
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Vente clôturée avec succès"), backgroundColor: Colors.green));
        Future.delayed(const Duration(milliseconds: 200), () => _depotFocusNode.requestFocus());
      }
    } else {
      _requestSearchFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Consumer<DepotSaleProvider>(
        builder: (context, provider, child) {
          final bool isScanMode = provider.isQuickScanMode;

          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, result) async {
              if (didPop) return;
              if (provider.currentSaleId != null && provider.cartItems.isEmpty) {
                final bool? shouldDelete = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text("Vente vide"),
                    content: const Text("Cette vente est vide.\nVoulez-vous la supprimer ?"),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Non, garder")),
                      ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text("Oui, Supprimer", style: TextStyle(color: Colors.white))),
                    ],
                  ),
                );
                if (shouldDelete == true) await provider.deleteCurrentSale();
                else provider.resetSale();
                if (context.mounted) Navigator.pop(context);
              } else {
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: Scaffold(
              appBar: AppBar(
                title: const Text("Nouvelle Vente Dépôt"),
                actions: [
                  IconButton(
                    icon: Icon(isScanMode ? Icons.bolt : Icons.flash_off, color: isScanMode ? Colors.greenAccent : null),
                    onPressed: () {
                      provider.toggleQuickScanMode();
                      _requestSearchFocus();
                    },
                  )
                ],
              ),
              body: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    color: Colors.white,
                    child: provider.currentSaleId == null
                        ? _isLoadingDepots ? const LinearProgressIndicator() : DropdownButtonFormField<DepotModel>(
                      value: provider.selectedDepot,
                      focusNode: _depotFocusNode,
                      decoration: const InputDecoration(labelText: "Sélectionner le Dépôt / Client", border: OutlineInputBorder(), prefixIcon: Icon(Icons.store)),
                      items: _availableDepots.map((depot) => DropdownMenuItem(value: depot, child: Text("${depot.fullName} (${depot.descriptionTypeDepot})", overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          provider.selectDepot(val);
                          Future.delayed(const Duration(milliseconds: 100), () => _requestSearchFocus());
                        }
                      },
                    )
                        : Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.grey.shade100, border: Border.all(color: Colors.grey.shade300)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text("Client: ${provider.selectedDepot?.fullName}", style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text("REF: ${provider.currentSaleRef ?? '...'}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey)),
                          ])),
                          Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.blue.shade100, borderRadius: BorderRadius.circular(20)), child: Text("${provider.cartItems.length} Produit(s)", style: TextStyle(color: Colors.blue.shade800, fontWeight: FontWeight.bold))),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    color: Colors.white,
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        hintText: isScanMode ? "SCAN RAPIDE ACTIF" : "Saisir nom ou scanner",
                        prefixIcon: _isProcessing ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2)) : Icon(isScanMode ? Icons.bolt : Icons.search, color: isScanMode ? Colors.green : null),
                        suffixIcon: IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchController.clear(); provider.clearSearchResults(); _requestSearchFocus(); }),
                        border: const OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: isScanMode ? Colors.green : Colors.grey, width: isScanMode ? 2.5 : 1.0)),
                        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: isScanMode ? Colors.green : Theme.of(context).primaryColor, width: isScanMode ? 2.5 : 2.0)),
                        filled: true,
                        fillColor: isScanMode ? Colors.green.withValues(alpha: 0.1) : Colors.blue.shade50.withValues(alpha: 0.3),
                      ),
                      onSubmitted: (val) => _performSearch(val, autoAddIfUnique: isScanMode),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: provider.cartItems.isEmpty
                        ? (provider.isLoading ? const Center(child: CircularProgressIndicator()) : const Center(child: Text("Panier vide. Scannez ou saisissez un produit.")))
                        : Stack(children: [
                      ListView.separated(
                        itemCount: provider.cartItems.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = provider.cartItems[index];
                          return ListTile(
                            dense: true,
                            visualDensity: const VisualDensity(vertical: -2),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                            title: Text(item.strNAME, style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 2.0),
                              child: Text("${Constants.formatNumber(item.intPRICEUNITAIR)} F x ${item.intQUANTITY}"),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text("${Constants.formatNumber(item.intPRICE)} F", style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                                const SizedBox(width: 10),
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.orange, size: 22),
                                  onPressed: () => _showEditDialog(item),
                                  tooltip: "Modifier",
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                                const SizedBox(width: 15),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 22),
                                  onPressed: () => _confirmDeleteItem(item),
                                  tooltip: "Supprimer",
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                            onTap: () => _showEditDialog(item),
                          );
                        },
                      ),
                      if (provider.isLoading) const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 2)),
                    ]),
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, -2))]),
                    child: SafeArea(child: Row(children: [
                      Expanded(flex: 4, child: ElevatedButton.icon(onPressed: provider.cartItems.isEmpty ? null : _validateSale, icon: const Icon(Icons.check_circle_outline), label: const Text("CLÔTURER"), style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 18)))),
                      const SizedBox(width: 15),
                      Expanded(flex: 6, child: Container(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15), decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)), child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [const Text("TOTAL NET", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)), FittedBox(fit: BoxFit.scaleDown, child: Text("${Constants.formatNumber(provider.totalAmount)} F", style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.black)))]))),
                    ])),
                  )
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// =========================================================
// QUANTITY DIALOG (DESIGN COMPACT + INTELLIGENCE)
// =========================================================
class QuantityDialog extends StatefulWidget {
  final ProductSearchResult product;
  final bool isSmartMode; // AJOUTÉ
  const QuantityDialog({super.key, required this.product, this.isSmartMode = false});

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
          // --- BANDEAU INTELLIGENCE ---
          if (widget.isSmartMode)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                children: [
                  Icon(Icons.bolt, color: Colors.orange, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Produit scanné plusieurs fois.\nCombien en reste-t-il ?",
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ),
          Text(widget.product.strNAME, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          RichText(text: TextSpan(style: const TextStyle(fontSize: 11, color: Colors.grey), children: [
            const TextSpan(text: "CIP: "), TextSpan(text: "${widget.product.intCIP} ", style: const TextStyle(color: Colors.black54)),
            const TextSpan(text: "| Stock: "), TextSpan(text: "${widget.product.intNUMBERAVAILABLE} ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
            const TextSpan(text: "| Prix: "), TextSpan(text: "${Constants.formatNumber(widget.product.intPRICE)} F", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
          ])),
        ],
      ),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _qteController,
          focusNode: _qtyFocusNode,
          decoration: InputDecoration(labelText: widget.isSmartMode ? 'Quantité Restante' : 'Quantité', border: const OutlineInputBorder(), contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10)),
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
// EDIT LINE DIALOG (DESIGN HARMONISÉ)
// =========================================================
class EditLineDialog extends StatefulWidget {
  final SaleLine item;
  const EditLineDialog({super.key, required this.item});

  @override
  State<EditLineDialog> createState() => _EditLineDialogState();
}

class _EditLineDialogState extends State<EditLineDialog> {
  late TextEditingController _qteController;
  late TextEditingController _priceController;
  final FocusNode _qteFocusNode = FocusNode();
  final FocusNode _priceFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _qteController = TextEditingController(text: widget.item.intQUANTITY.toString());
    _priceController = TextEditingController(text: widget.item.intPRICEUNITAIR.toString());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _qteFocusNode.requestFocus();
        _qteController.selection = TextSelection(baseOffset: 0, extentOffset: _qteController.text.length);
      }
    });
  }

  @override
  void dispose() {
    _qteController.dispose();
    _priceController.dispose();
    _qteFocusNode.dispose();
    _priceFocusNode.dispose();
    super.dispose();
  }

  void _submit() async {
    final qty = int.tryParse(_qteController.text) ?? widget.item.intQUANTITY;
    final price = int.tryParse(_priceController.text) ?? widget.item.intPRICEUNITAIR;

    if (qty <= 0) return;

    Navigator.pop(context);
    await Provider.of<DepotSaleProvider>(context, listen: false).updateItem(widget.item, qty, price);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.item.strNAME, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
            child: const Text("MODIFICATION LIGNE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange)),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _qteController,
            focusNode: _qteFocusNode,
            decoration: const InputDecoration(labelText: "Quantité", border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 10)),
            keyboardType: TextInputType.number,
            onSubmitted: (_) => _priceFocusNode.requestFocus(),
          ),
          const SizedBox(height: 15),
          TextField(
            controller: _priceController,
            focusNode: _priceFocusNode,
            decoration: const InputDecoration(labelText: "Prix Unitaire", border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 10)),
            keyboardType: TextInputType.number,
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler", style: TextStyle(color: Colors.grey))),
        ElevatedButton(onPressed: _submit, style: ElevatedButton.styleFrom(backgroundColor: Colors.blue), child: const Text("Valider", style: TextStyle(color: Colors.white))),
      ],
    );
  }
}

// =========================================================
// MODAL RÉSULTATS
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
        _modalSearchCtrl.selection = TextSelection.fromPosition(TextPosition(offset: _modalSearchCtrl.text.length));
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
      _filteredList = widget.results.where((p) => p.strNAME.toLowerCase().contains(query.toLowerCase()) || p.intCIP.toString().contains(query)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final double keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      child: Column(
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text("Résultats (${_filteredList.length})", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 10),
          TextField(
            controller: _modalSearchCtrl,
            focusNode: _modalFocusNode,
            decoration: const InputDecoration(hintText: "Filtrer dans la liste...", prefixIcon: Icon(Icons.search), border: OutlineInputBorder(), isDense: true),
            onChanged: _filterResults,
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.only(bottom: keyboardHeight + 20),
              itemCount: _filteredList.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, index) {
                final p = _filteredList[index];
                return ListTile(
                  dense: true,
                  title: Text(p.strNAME, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 12, color: Colors.black87),
                      children: [
                        TextSpan(text: "CIP: ${p.intCIP} | "),
                        TextSpan(text: "Stock: ${p.intNUMBERAVAILABLE}", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.withValues(alpha: 1))),
                        const TextSpan(text: " | "),
                        TextSpan(text: "Prix: ${Constants.formatNumber(p.intPRICE)} F", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.withValues(alpha: 1))),
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