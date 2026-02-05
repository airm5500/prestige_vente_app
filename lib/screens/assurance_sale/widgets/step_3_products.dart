// lib/screens/assurance_sale/widgets/step_3_products.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final _keyboardFocusNode = FocusNode(); // Pour le scanner global
  Timer? _debounce;

  bool _isProcessing = false;
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
    if (mounted && !_isPopupOpen && !_isProcessing) {
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
    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);
    if (!provider.isQuickScanMode) return;
    if (_isPopupOpen) return;

    if (_searchFocusNode.hasFocus) {
      _scanBuffer = "";
      return;
    }

    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        if (_scanBuffer.isNotEmpty) {
          _performSearch(_scanBuffer.trim(), fromScan: true);
          _scanBuffer = "";
        }
      } else if (event.character != null) {
        _scanBuffer += event.character!;
      }
    }
  }

  void _onSearchChanged() {
    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);
    if (provider.isQuickScanMode) return; // Mode Scan : pas de recherche auto

    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 500), () {
      final query = _searchController.text.trim();
      if (query.length >= 3) {
        // Mode Manuel : Recherche Auto -> Popup
        _performSearch(query, fromScan: false);
      }
    });
  }

  Future<void> _performSearch(String query, {required bool fromScan}) async {
    if (_isProcessing) return;
    if (query.isEmpty) return;

    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);
    if (_isPopupOpen && !fromScan) return; // Évite réouverture

    setState(() => _isProcessing = true);

    try {
      await provider.searchProducts(query);

      if (!mounted) return;

      if (provider.productSearchResults.length == 1) {
        final product = provider.productSearchResults.first;

        if (provider.isQuickScanMode) {
          // SCAN : AJOUT DIRECT
          _searchController.clear();
          provider.clearProductSearch();
          await provider.addProductToCart(product, 1);
        } else {
          // MANUEL : POPUP QUANTITÉ
          _showQuantityDialog(product);
        }
      } else if (provider.productSearchResults.isNotEmpty) {
        // MULTIPLES : POPUP SÉLECTION
        _showSelectionDialog(provider.productSearchResults);
      } else {
        if(fromScan) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Produit introuvable"), duration: Duration(milliseconds: 500)));
          _searchController.clear();
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
        if (!_isPopupOpen) _requestSearchFocus();
      }
    }
  }

  void _showSelectionDialog(List<ProductSearchResult> products) {
    setState(() => _isPopupOpen = true);
    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text("Résultats (${products.length})"),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.separated(
            itemCount: products.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (ctx, index) {
              final p = products[index];
              final bool isRupture = p.intNUMBERAVAILABLE <= 0;
              return ListTile(
                title: Text(p.strNAME, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("Stock: ${p.intNUMBERAVAILABLE} | CIP: ${p.intCIP}",
                    style: TextStyle(color: isRupture ? Colors.red : Colors.grey[700])),
                trailing: Text("${Constants.formatNumber(p.intPRICE)} F"),
                onTap: () {
                  Navigator.pop(ctx);
                  _searchController.clear();
                  provider.clearProductSearch();
                  _showQuantityDialog(p);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                provider.clearProductSearch();
                _searchController.clear();
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
    setState(() => _isPopupOpen = true);
    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);
    final qteController = TextEditingController(text: '1');
    qteController.selection = TextSelection(baseOffset: 0, extentOffset: qteController.text.length);

    void submit() {
      final qty = int.tryParse(qteController.text) ?? 0;
      Navigator.of(context).pop();
      if (qty > 0) {
        if (qty > product.intNUMBERAVAILABLE) {
          _showForceStockDialog(product, qty);
        } else {
          provider.addProductToCart(product, qty);
          provider.clearProductSearch();
          _searchController.clear();
        }
      }
    }

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
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => submit(),
        ),
        actions: [
          TextButton(
              child: const Text('Annuler'),
              onPressed: () {
                Navigator.of(ctx).pop();
                provider.clearProductSearch();
                _searchController.clear();
              }
          ),
          ElevatedButton(child: const Text('Ajouter'), onPressed: submit),
        ],
      ),
    ).then((_) {
      if (mounted) {
        setState(() => _isPopupOpen = false);
        _requestSearchFocus();
      }
    });
  }

  void _showForceStockDialog(ProductSearchResult product, int qty) {
    setState(() => _isPopupOpen = true);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stock insuffisant', style: TextStyle(color: Colors.red)),
        content: Text('Stock disponible : ${product.intNUMBERAVAILABLE}.\nForcer l\'ajout de $qty ?'),
        actions: [
          TextButton(child: const Text('Non'), onPressed: () => Navigator.pop(ctx)),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                Navigator.pop(ctx);
                Provider.of<AssuranceSaleProvider>(context, listen: false).addProductToCart(product, qty);
                _searchController.clear();
              },
              child: const Text('OUI', style: TextStyle(color: Colors.white))
          ),
        ],
      ),
    ).then((_) => setState(() => _isPopupOpen = false));
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AssuranceSaleProvider>(context);
    final isTabletLandscape = MediaQuery.of(context).size.width > 800;
    final isActive = provider.isQuickScanMode;

    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Column(
        children: [
          // ZONE 1 : EN-TÊTE COMPACT (Ligne unique)
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
                  tooltip: "Modifier Bon / Ayant Droit",
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

          const AssuranceSummaryFooter(),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(AssuranceSaleProvider provider, bool isActive) {
    return Column(
      children: [
        _buildSearchRow(provider, isActive),
        const Divider(height: 1),
        const Expanded(child: AssuranceCartWidget()),
      ],
    );
  }

  Widget _buildTabletLayout(AssuranceSaleProvider provider, bool isActive) {
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
        const Expanded(
          flex: 6,
          child: AssuranceCartWidget(),
        ),
      ],
    );
  }

  // ZONE RECHERCHE : BOUTON GAUCHE
  Widget _buildSearchRow(AssuranceSaleProvider provider, bool isActive) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          // BOUTON TOGGLE SCAN (GAUCHE)
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

          const SizedBox(width: 8),

          // CHAMP TEXTE
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              textInputAction: TextInputAction.go,
              decoration: InputDecoration(
                hintText: isActive ? 'SCAN RAPIDE ACTIF' : 'Saisir (Auto) ou Scanner',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
              onSubmitted: (val) {
                // Validation Manuelle (si Auto n'a pas déclenché)
                _performSearch(val, fromScan: false);
                _requestSearchFocus();
              },
            ),
          ),

          if (_isProcessing)
            const Padding(
              padding: EdgeInsets.only(left: 8.0),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
        ],
      ),
    );
  }
}