// lib/screens/carnet_sale/widgets/step_3_products.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/api/models/product.dart';
//import 'package:prestige_vente_app/api/models/product_search_result.dart';
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
  final _keyboardFocusNode = FocusNode();

  Timer? _debounce;
  String _scanBuffer = "";
  bool _isPopupOpen = false;
  bool _isProcessing = false;

  // --- VARIABLES INTELLIGENCE SCAN ---
  String? _lastScannedCIP;
  int _scanRepeatCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestSearchFocus();
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

  // --- 1. GESTION SCAN PHYSIQUE ---
  void _handleKeyEvent(KeyEvent event) {
    final provider = Provider.of<CarnetSaleProvider>(context, listen: false);

    if (!provider.isQuickScanMode) return;
    if (_isPopupOpen) return;

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

  // --- 2. GESTION SAISIE CLAVIER ---
  void _onSearchChanged() {
    final provider = Provider.of<CarnetSaleProvider>(context, listen: false);

    if (provider.isQuickScanMode) return;

    final text = _searchController.text.trim();
    if (text.isEmpty) {
      provider.clearProductSearch();
      // Reset intelligence si on efface manuellement
      _scanRepeatCount = 0;
      _lastScannedCIP = null;
      return;
    }

    if (_isPopupOpen) return;
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      if (_isPopupOpen) return;
      if (text.isNotEmpty && text.length >= 2) {
        _performSearch(text, autoAddIfUnique: false);
      }
    });
  }

  // --- 3. EXÉCUTION DE LA RECHERCHE ---
  Future<void> _performSearch(String query, {required bool autoAddIfUnique}) async {
    _debounce?.cancel();
    if (_isPopupOpen || query.isEmpty) return;

    final provider = Provider.of<CarnetSaleProvider>(context, listen: false);

    try {
      if (mounted) setState(() => _isProcessing = true);

      await provider.searchProducts(query);

      if (!mounted) return;
      if (_isPopupOpen) return;

      final results = provider.productSearchResults;

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
          if (autoAddIfUnique) {
            // --- LOGIQUE INTELLIGENTE "SCAN RÉPÉTÉ" ---
            if (_lastScannedCIP == product.intCIP.toString()) {
              _scanRepeatCount++;
              if (_scanRepeatCount >= 3) {
                _showSmartBulkDialog(product);
                return;
              }
            } else {
              _lastScannedCIP = product.intCIP.toString();
              _scanRepeatCount = 1;
            }
            _checkStockAndAddDirectly(product);
          } else {
            // Reset intelligence si manuel
            _scanRepeatCount = 0;
            _lastScannedCIP = null;
            _searchController.clear();
            provider.clearProductSearch();
            _showQuantityDialog(product);
          }
        } else {
          _openSearchModal(results);
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
        if (!_isPopupOpen) _requestSearchFocus();
      }
    }
  }

  // --- NOUVEAU DIALOG INTELLIGENT ---
  void _showSmartBulkDialog(ProductSearchResult product) async {
    setState(() => _isPopupOpen = true);

    final int? qty = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => QuantityDialog(product: product, isSmartMode: true),
    );

    if (mounted) setState(() => _isPopupOpen = false);

    if (qty != null) {
      // Si l'utilisateur saisit une masse (>1), on reset le compteur.
      if (qty > 1) {
        _scanRepeatCount = 0;
        _lastScannedCIP = null;
      }

      if (qty > product.intNUMBERAVAILABLE) {
        _showForceStockDialog(product, qty);
      } else {
        _executeAdd(product, qty);
      }
    } else {
      // Annulation : on ajoute l'unité scannée mais on garde le compteur élevé pour persistance
      _checkStockAndAddDirectly(product);
    }
  }

  // AJOUT DIRECT
  void _checkStockAndAddDirectly(ProductSearchResult product) {
    _searchController.clear();
    Provider.of<CarnetSaleProvider>(context, listen: false).clearProductSearch();

    if (product.intNUMBERAVAILABLE <= 0) {
      _showForceStockDialog(product, 1);
    } else {
      Provider.of<CarnetSaleProvider>(context, listen: false).addProductToCart(product, 1);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${product.strNAME} ajouté (+1)"), duration: const Duration(milliseconds: 500), backgroundColor: Colors.green),
      );
      if (mounted) _requestSearchFocus();
    }
  }

  // --- 4. MODAL RÉSULTATS ---
  void _openSearchModal(List<ProductSearchResult> results) async {
    final provider = Provider.of<CarnetSaleProvider>(context, listen: false);

    setState(() => _isPopupOpen = true);

    final ProductSearchResult? selectedProduct = await showModalBottomSheet<ProductSearchResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ProductListModal(
        results: results,
        initialQuery: _searchController.text,
        onProductSelected: (product) {
          Navigator.pop(ctx, product);
        },
      ),
    );

    if (mounted) setState(() => _isPopupOpen = false);

    if (selectedProduct != null) {
      provider.clearProductSearch();
      _searchController.clear();
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

    final int? qty = await showDialog<int>(
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

  // --- 6. POPUP STOCK INSUFFISANT ---
  void _showForceStockDialog(ProductSearchResult product, int qty) async {
    setState(() => _isPopupOpen = true);

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stock insuffisant', style: TextStyle(color: Colors.red)),
        content: Text('Stock dispo : ${product.intNUMBERAVAILABLE}.\nForcer l\'ajout de $qty ?'),
        actions: [
          TextButton(
              child: const Text('Non'),
              onPressed: () => Navigator.pop(ctx, false)
          ),
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

  void _executeAdd(ProductSearchResult product, int qty) {
    final provider = Provider.of<CarnetSaleProvider>(context, listen: false);
    provider.addProductToCart(product, qty);
    _searchController.clear();
    provider.clearProductSearch();
    if (mounted) _requestSearchFocus();
  }

  // --- UI PRINCIPALE ---
  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<CarnetSaleProvider>(context);
    final isTabletLandscape = MediaQuery.of(context).size.width > 800;
    final isActive = provider.isQuickScanMode;

    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: Colors.grey[100],
            child: Row(
              children: [
                const Icon(Icons.person, size: 20, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(color: Colors.black87, fontSize: 13),
                      children: [
                        const TextSpan(text: "Client: ", style: TextStyle(fontWeight: FontWeight.bold)),
                        TextSpan(text: "${provider.selectedClient?.fullName}  "),
                        const TextSpan(text: "|  ", style: TextStyle(color: Colors.grey)),
                        const TextSpan(text: "Ayant-Droit: ", style: TextStyle(fontWeight: FontWeight.bold)),
                        TextSpan(text: provider.selectedAyantDroit?.fullName ?? "-"),
                      ],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_note, color: Colors.orange),
                  onPressed: () => provider.returnToBonStep(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                )
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: isTabletLandscape
                ? _buildTabletLayout(provider, isActive)
                : _buildMobileLayout(provider, isActive),
          ),
          const CarnetSummaryFooter(),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(CarnetSaleProvider provider, bool isActive) {
    return Column(
      children: [
        _buildSearchRow(provider, isActive),
        const Divider(height: 1),
        const Expanded(child: CarnetCartWidget()),
      ],
    );
  }

  Widget _buildTabletLayout(CarnetSaleProvider provider, bool isActive) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Column(
            children: [
              _buildSearchRow(provider, isActive),
              const Divider(height: 1),
              const Expanded(child: Center(child: Text("Utilisez la recherche pour ajouter", style: TextStyle(color: Colors.grey)))),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        const Expanded(flex: 6, child: CarnetCartWidget()),
      ],
    );
  }

  Widget _buildSearchRow(CarnetSaleProvider provider, bool isActive) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              textInputAction: TextInputAction.go,
              onChanged: (_) => _onSearchChanged(),
              onSubmitted: (val) {
                if (val.isNotEmpty) {
                  _performSearch(val, autoAddIfUnique: isActive);
                  _requestSearchFocus();
                }
              },
              decoration: InputDecoration(
                hintText: isActive ? 'MODE SCAN ACTIF (Saisir + Entrée)' : 'Recherche (Auto) ou Scanner',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                prefixIcon: _isProcessing
                    ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(isActive ? Icons.bolt : Icons.search, color: isActive ? Colors.green : null),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  onPressed: () {
                    _searchController.clear();
                    provider.clearProductSearch();
                    _requestSearchFocus();
                  },
                )
                    : null,
                border: const OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: isActive ? Colors.green : Colors.grey, width: isActive ? 2.0 : 1.0),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: isActive ? Colors.green : Theme.of(context).primaryColor, width: isActive ? 2.0 : 2.0),
                ),
                filled: true,
                fillColor: isActive ? Colors.green.withValues(alpha: 0.05) : null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () {
              provider.toggleQuickScanMode();
              _requestSearchFocus();
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isActive ? Colors.green : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: isActive ? Colors.green.shade700 : Colors.grey.shade300),
              ),
              child: Icon(
                isActive ? Icons.bolt : Icons.flash_off,
                color: isActive ? Colors.white : Colors.grey.shade600,
                size: 24,
              ),
            ),
          ),
        ],
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
        _qteController.selection = TextSelection(
            baseOffset: 0, extentOffset: _qteController.text.length);
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
      _qteController.selection = TextSelection(
          baseOffset: 0, extentOffset: _qteController.text.length);
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
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text("NON")),
            TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text("OUI, CONFIRMER")),
          ],
        ),
      );
      if (confirm != true) {
        _qtyFocusNode.requestFocus();
        _qteController.selection = TextSelection(
            baseOffset: 0, extentOffset: _qteController.text.length);
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
          Text(
              widget.product.strNAME,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)
          ),
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
          decoration: InputDecoration(
            labelText: widget.isSmartMode ? 'Quantité Restante' : 'Quantité',
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          ),
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