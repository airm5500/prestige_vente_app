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

  // SÉCURITÉ : Empêche la double soumission (Scan + Entrée)
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

  // --- LOGIQUE SCANNER GLOBAL ---
  void _handleKeyEvent(KeyEvent event) {
    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);
    if (!provider.isQuickScanMode) return;
    if (_isPopupOpen) return;

    // Si le champ a le focus, on ignore le scan global pour éviter les doublons
    if (_searchFocusNode.hasFocus) {
      _scanBuffer = "";
      return;
    }

    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        if (_scanBuffer.isNotEmpty) {
          _performSearch(_scanBuffer.trim());
          _scanBuffer = "";
        }
      } else if (event.character != null) {
        _scanBuffer += event.character!;
      }
    }
  }

  // Saisie manuelle (Déclencheur Debounce)
  void _onSearchChanged() {
    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);

    // En mode Scan Rapide, on désactive le debounce auto pour éviter les conflits
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 300), () {
      final query = _searchController.text.trim();
      if (query.isNotEmpty) {
        // En mode scan rapide, on laisse _performSearch gérer via "onSubmitted"
        // Sinon, on lance la recherche classique pour afficher les suggestions
        if (!provider.isQuickScanMode) {
          provider.searchProducts(query);
        }
      }
    });
  }

  // Action Principale (Validation Entrée / Scan)
  Future<void> _performSearch(String query) async {
    if (_isProcessing) return; // VERROUILLAGE ACTIVÉ
    if (query.isEmpty) return;

    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);
    setState(() => _isProcessing = true);

    try {
      await provider.searchProducts(query);

      if (!mounted) return;

      if (provider.productSearchResults.length == 1) {
        final product = provider.productSearchResults.first;

        // Nettoyage immédiat
        _searchController.clear();
        provider.clearProductSearch();

        if (provider.isQuickScanMode) {
          // Ajout direct (Scan Rapide)
          await provider.addProductToCart(product, 1);
        } else {
          // Ouverture dialogue (Mode Normal)
          _showQuantityDialog(product);
        }
      }
      // Si plusieurs résultats, ils s'affichent via l'UI (ListView)
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
        if (!_isPopupOpen) _requestSearchFocus();
      }
    }
  }

  void _showQuantityDialog(ProductSearchResult product) {
    setState(() => _isPopupOpen = true);
    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);
    final qteController = TextEditingController(text: '1');
    qteController.selection = TextSelection(baseOffset: 0, extentOffset: qteController.text.length);

    void _addProduct(int quantity) {
      provider.addProductToCart(product, quantity);
      provider.clearProductSearch();
      _searchController.clear();
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
            content: Text('Stock: ${product.intNUMBERAVAILABLE}. Continuer ?'),
            actions: [
              TextButton(child: const Text('Non'), onPressed: () => Navigator.of(confirmCtx).pop()),
              ElevatedButton(child: const Text('Oui'), onPressed: () { Navigator.of(confirmCtx).pop(); _addProduct(quantity); }),
            ],
          ),
        );
      } else {
        _addProduct(quantity);
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
          onSubmitted: (_) => submitQuantity(),
        ),
        actions: [
          TextButton(child: const Text('Annuler'), onPressed: () => Navigator.of(ctx).pop()),
          ElevatedButton(child: const Text('Ajouter'), onPressed: submitQuantity),
        ],
      ),
    ).then((_) {
      if (mounted) {
        setState(() => _isPopupOpen = false);
        _requestSearchFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AssuranceSaleProvider>(context);
    final isTabletLandscape = MediaQuery.of(context).size.width > 800;

    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Column(
        children: [
          // En-tête Client
          Material(
            color: Colors.grey[100],
            child: ListTile(
              leading: const Icon(Icons.person_pin),
              title: Text(provider.selectedClient?.fullName ?? 'Client'),
              subtitle: Text(provider.selectedAyantDroit?.fullName ?? 'Ayant droit'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Bouton Modifier Bon
                  TextButton.icon(
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Modif. Bon'),
                    onPressed: () => provider.returnToBonStep(),
                  ),
                  const SizedBox(width: 8),
                  // BOUTON TOGGLE SCAN
                  IconButton(
                    icon: Icon(
                        provider.isQuickScanMode ? Icons.bolt : Icons.flash_off,
                        color: provider.isQuickScanMode ? Colors.green : null
                    ),
                    tooltip: provider.isQuickScanMode ? "Mode Scan Rapide (Actif)" : "Activer Scan Rapide",
                    onPressed: () {
                      provider.toggleQuickScanMode();
                      _requestSearchFocus();
                    },
                  ),
                ],
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
      ),
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
    final isActive = provider.isQuickScanMode;
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        textInputAction: TextInputAction.go,
        decoration: InputDecoration(
          labelText: isActive ? 'SCAN RAPIDE ACTIF' : 'Rechercher un produit (CIP ou Nom)',
          prefixIcon: _isProcessing
              ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(Icons.search, color: isActive ? Colors.green : null),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              _searchController.clear();
              provider.clearProductSearch();
              _requestSearchFocus();
            },
          )
              : null,
          border: const OutlineInputBorder(),

          // DÉCORATION VERTE SI SCAN ACTIF
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: isActive ? Colors.green : Colors.grey, width: isActive ? 2.5 : 1.0),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: isActive ? Colors.green : Theme.of(context).primaryColor, width: isActive ? 2.5 : 2.0),
          ),
          filled: true,
          fillColor: isActive ? Colors.green.withValues(alpha: 0.1) : null,
        ),
        onSubmitted: (val) {
          _performSearch(val);
          _requestSearchFocus();
        },
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
              title: Text(product.strNAME, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("CIP: ${product.intCIP} | Stock: ${product.intNUMBERAVAILABLE}"),
              onTap: () => _showQuantityDialog(product),
            ),
          );
        },
      ),
    );
  }
}