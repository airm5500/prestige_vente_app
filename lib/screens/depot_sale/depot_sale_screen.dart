// lib/screens/depot_sale/depot_sale_screen.dart
// Saisie d'une vente dépôt : présentations A, B, C ; panier, total et « CLÔTURER » fixés en bas.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/depot_model.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/providers/depot_sale_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/sync_status.dart';

/// Bornes de saisie de la vente dépôt.
class DepotSaleLimits {
  DepotSaleLimits._();
  static const int maxAddQty = 9999; // règle existante : 4 chiffres au plus à l'ajout
  static const int maxQty = 99999;
  static const int maxPrice = 999999999;
  static const int maxSearchLength = 50;
}

// Caractères de contrôle refusés dans les champs texte.
final _noControlChars = FilteringTextInputFormatter.deny(RegExp(r'[\x00-\x1F\x7F]'));

class DepotSaleScreen extends StatefulWidget {
  /// Présentation reçue de la liste ; sinon celle de l'appareil (A par défaut).
  final ListPresentation? presentation;

  const DepotSaleScreen({super.key, this.presentation});

  @override
  State<DepotSaleScreen> createState() => _DepotSaleScreenState();
}

class _DepotSaleScreenState extends State<DepotSaleScreen> with PresentationAware {
  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _depotFocusNode = FocusNode();
  final FocusNode _keyboardFocusNode = FocusNode();

  List<DepotModel> _availableDepots = [];
  bool _isLoadingDepots = false;
  String? _depotsError;
  bool _isProcessing = false;
  bool _closing = false;
  bool _leaving = false;

  String _scanBuffer = "";
  Timer? _debounce;
  bool _isPopupOpen = false;

  // --- VARIABLES INTELLIGENCE SCAN ---
  String? _lastScannedCIP;
  int _scanRepeatCount = 0;

  @override
  void initState() {
    super.initState();
    loadPresentation();
    _loadDepots();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
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
        // Caractères imprimables seulement, longueur bornée.
        final c = event.character!.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');
        if (_scanBuffer.length + c.length <= DepotSaleLimits.maxSearchLength) _scanBuffer += c;
      }
    }
  }

  Future<void> _loadDepots() async {
    setState(() {
      _isLoadingDepots = true;
      _depotsError = null;
    });
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
      if (mounted) {
        setState(() {
          _isLoadingDepots = false;
          _depotsError = e is ApiLoadException ? e.message : "Impossible de charger les dépôts : $e";
        });
      }
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
    query = query.trim();
    if (_isProcessing || _isPopupOpen || query.isEmpty || _closing) return;

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

      // Échec réseau/serveur : ne pas l'annoncer comme « produit introuvable ».
      if (provider.searchError != null) {
        _showError("Recherche impossible : ${provider.searchError}");
        return;
      }

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
      if (mounted) _showError("Erreur : $e");
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
        if (!_isPopupOpen) _requestSearchFocus();
      }
    }
  }

  // --- DIALOG INTELLIGENT ---
  void _showSmartBulkDialog(ProductSearchResult product, DepotSaleProvider provider) async {
    setState(() => _isPopupOpen = true);

    final qty = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => QuantityDialog(product: product, isSmartMode: true),
    );

    if (!mounted) return;
    setState(() => _isPopupOpen = false);

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

    if (!mounted) return;
    setState(() => _isPopupOpen = false);

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

    if (!mounted) return;
    setState(() => _isPopupOpen = false);

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
    // Garde-fou : quantité entière bornée.
    if (qty < 1 || qty > DepotSaleLimits.maxQty) {
      _showError("Quantité invalide ($qty).");
      return;
    }
    final provider = Provider.of<DepotSaleProvider>(context, listen: false);
    final success = await provider.addToCart(product, qty: qty);

    if (mounted) {
      if (success) {
        final stale = provider.cartError != null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(stale
                ? "${product.strNAME} ajouté (+ $qty), mais le panier n'a pas pu être actualisé."
                : "${product.strNAME} ajouté (+ $qty)"),
            duration: Duration(milliseconds: stale ? 3000 : 500),
            backgroundColor: stale ? Colors.orange.shade800 : Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _searchController.clear();
      } else {
        _showError(provider.errorMessage.isNotEmpty ? provider.errorMessage : "Erreur ajout : produit non ajouté.");
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
        icon: const Icon(Icons.inventory_2_outlined, color: Colors.red),
        title: const Text("Stock Insuffisant"),
        content: Text("${product.strNAME}\n\nStock disponible : ${product.intNUMBERAVAILABLE}.\nForcer l'ajout de $qty ?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Non")),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Oui, Forcer")),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _isPopupOpen = false);
    if (confirm == true) {
      _addProductToCart(product, qty: qty);
    } else {
      _requestSearchFocus();
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.red.shade700));
  }

  bool _busy(DepotSaleProvider p) => p.isLoading || _closing;

  Future<void> _confirmDeleteItem(SaleLine item) async {
    final provider = Provider.of<DepotSaleProvider>(context, listen: false);
    if (_busy(provider)) return;
    setState(() => _isPopupOpen = true);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Supprimer ?"),
        content: Text("Retirer ${item.strNAME} de la vente ?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Non")),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Oui")),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _isPopupOpen = false);
    if (ok == true) {
      final done = await provider.removeItem(item.lgPREENREGISTREMENTDETAILID);
      if (!mounted) return;
      if (!done) _showError(provider.errorMessage.isNotEmpty ? provider.errorMessage : "Ligne non supprimée.");
    }
    _requestSearchFocus();
  }

  void _showEditDialog(SaleLine item) async {
    final provider = Provider.of<DepotSaleProvider>(context, listen: false);
    if (_busy(provider)) return;
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
    if (provider.cartItems.isEmpty || _closing || provider.isLoading) return;
    if (provider.cartError != null) {
      _showError("Actualisez d'abord le panier (bouton « Réessayer ») avant de clôturer.");
      return;
    }

    setState(() => _isPopupOpen = true);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Clôturer Vente Dépôt"),
        content: Text(
          "Client : ${provider.selectedDepot?.fullName ?? '—'}\n"
          "${provider.cartItems.length} produit(s)\n"
          "Total: ${Constants.formatNumber(provider.totalAmount)} FCFA\n\n"
          "Confirmer la clôture ? Elle est définitive.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Non")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Oui")),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _isPopupOpen = false);

    if (confirm == true) {
      setState(() => _closing = true);
      final success = await provider.closeSale();
      if (!mounted) return;
      setState(() => _closing = false);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Vente clôturée avec succès"), backgroundColor: Colors.green));
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) _depotFocusNode.requestFocus();
        });
      } else {
        _showError(provider.errorMessage.isNotEmpty ? provider.errorMessage : "Vente NON clôturée. Réessayez.");
      }
    } else {
      _requestSearchFocus();
    }
  }

  // --- Sortie de l'écran ---
  Future<void> _onBack(DepotSaleProvider provider) async {
    if (_leaving) return;
    if (_busy(provider)) {
      _showError("Opération en cours, patientez avant de quitter.");
      return;
    }
    _leaving = true;
    try {
      final hasSale = provider.currentSaleId != null;
      // Panier connu vide (et bien relu) : proposer de supprimer la vente vide (comportement existant).
      if (hasSale && provider.cartItems.isEmpty && provider.cartError == null) {
        final bool? shouldDelete = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Vente vide"),
            content: const Text("Cette vente est vide.\nVoulez-vous la supprimer ?"),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Non, garder")),
              ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text("Oui, Supprimer")),
            ],
          ),
        );
        if (shouldDelete == null) return; // fermé sans choix : on reste
        if (shouldDelete == true) {
          final ok = await provider.deleteCurrentSale();
          if (!ok && mounted) _showError("La vente vide n'a pas pu être supprimée sur le serveur.");
        } else {
          provider.resetSale();
        }
        if (mounted) Navigator.pop(context);
        return;
      }
      // Panier non vide : confirmer l'abandon de la saisie (la vente reste en cours).
      if (hasSale) {
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Quitter la vente ?"),
            content: const Text("La vente n'est pas clôturée. Elle reste en cours et pourra être reprise depuis la liste."),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Rester")),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Quitter")),
            ],
          ),
        );
        if (leave != true || !mounted) return;
      }
      if (mounted) Navigator.pop(context);
    } finally {
      _leaving = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Affichage
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Consumer<DepotSaleProvider>(
        builder: (context, provider, child) {
          final bool isScanMode = provider.isQuickScanMode;
          final guided = style == ListPresentation.guided;
          final units = provider.cartItems.fold<int>(0, (s, e) => s + e.intQUANTITY);
          final step = provider.selectedDepot == null ? 0 : (provider.cartItems.isEmpty ? 1 : 2);

          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, result) {
              if (didPop) return;
              _onBack(provider);
            },
            child: PresentationScaffold(
              style: style,
              title: provider.currentSaleId == null ? "Nouvelle Vente Dépôt" : "Vente Dépôt",
              subtitle: provider.currentSaleRef != null ? "REF: ${provider.currentSaleRef}" : null,
              actions: (col) => [
                IconButton(
                  tooltip: isScanMode ? "Scan rapide actif" : "Activer le scan rapide",
                  icon: Icon(isScanMode ? Icons.bolt : Icons.flash_off, color: isScanMode ? Colors.greenAccent.shade400 : col),
                  onPressed: () {
                    provider.toggleQuickScanMode();
                    _requestSearchFocus();
                  },
                ),
              ],
              steps: StepsBar(active: step, steps: const [
                (title: 'Dépôt', detail: 'client', onTap: null),
                (title: 'Panier', detail: 'produits', onTap: null),
                (title: 'Clôture', detail: 'sur Prestige', onTap: null),
              ]),
              header: [
                _depotBlock(provider, onNavy: true),
                _searchField(provider, onNavy: true),
                if (style == ListPresentation.dashboard)
                  Row(children: [
                    Expanded(child: KpiTile('${provider.cartItems.length}', 'produit(s)')),
                    const SizedBox(width: 8),
                    Expanded(child: KpiTile('$units', 'unité(s)')),
                  ]),
              ],
              compactHeader: [
                _depotBlock(provider, onNavy: false),
                _searchField(provider, onNavy: false),
              ],
              body: Column(children: [
                if (_depotsError != null && provider.currentSaleId == null)
                  LoadErrorBanner(message: _depotsError!, onRetry: _loadDepots),
                if (provider.cartError != null)
                  LoadErrorBanner(message: provider.cartError!, onRetry: provider.isLoading ? null : provider.refreshCart),
                if (provider.isLoading || _closing) const LinearProgressIndicator(minHeight: 2),
                Expanded(child: _cart(provider)),
              ]),
              bottomNavigationBar: _bottomBar(provider, guided),
            ),
          );
        },
      ),
    );
  }

  Widget _depotBlock(DepotSaleProvider provider, {required bool onNavy}) {
    if (provider.currentSaleId == null) {
      if (_isLoadingDepots) return const LinearProgressIndicator();
      return DropdownButtonFormField<DepotModel>(
        value: _availableDepots.contains(provider.selectedDepot) ? provider.selectedDepot : null,
        focusNode: _depotFocusNode,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: "Sélectionner le Dépôt / Client",
          filled: true,
          fillColor: onNavy ? Colors.white : Pal.page,
          isDense: true,
          prefixIcon: const Icon(Icons.store),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
        hint: Text(_availableDepots.isEmpty && _depotsError == null ? "Aucun dépôt disponible" : "Choisir…"),
        items: _availableDepots
            .map((depot) => DropdownMenuItem(
                  value: depot,
                  child: Text("${depot.fullName} (${depot.descriptionTypeDepot})", maxLines: 1, overflow: TextOverflow.ellipsis),
                ))
            .toList(),
        onChanged: _busy(provider)
            ? null
            : (val) {
                if (val != null) {
                  provider.selectDepot(val);
                  Future.delayed(const Duration(milliseconds: 100), () => _requestSearchFocus());
                }
              },
      );
    }
    final name = provider.selectedDepot?.fullName ?? '—';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: onNavy ? Colors.white.withValues(alpha: 0.12) : Pal.page,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Icon(Icons.store, color: onNavy ? Colors.white : Pal.navy),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Client: $name",
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.bold, color: onNavy ? Colors.white : Pal.ink)),
            Text("REF: ${provider.currentSaleRef ?? '...'}",
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: onNavy ? Pal.headerMuted : Pal.muted)),
          ]),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: onNavy ? Colors.white : const Color(0xFFE3ECF7), borderRadius: BorderRadius.circular(20)),
          child: Text("${provider.cartItems.length} Produit(s)", style: const TextStyle(color: Pal.navy, fontWeight: FontWeight.bold, fontSize: 12)),
        ),
      ]),
    );
  }

  Widget _searchField(DepotSaleProvider provider, {required bool onNavy}) {
    final isScanMode = provider.isQuickScanMode;
    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      onChanged: _onSearchChanged,
      maxLength: DepotSaleLimits.maxSearchLength,
      inputFormatters: [_noControlChars],
      enabled: !_closing,
      decoration: InputDecoration(
        counterText: '',
        hintText: isScanMode ? "SCAN RAPIDE ACTIF" : "Saisir nom ou scanner",
        isDense: true,
        prefixIcon: _isProcessing
            ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
            : Icon(isScanMode ? Icons.bolt : Icons.search, color: isScanMode ? Colors.green : null),
        suffixIcon: IconButton(
          tooltip: 'Effacer',
          icon: const Icon(Icons.clear),
          onPressed: () {
            _searchController.clear();
            provider.clearSearchResults();
            _requestSearchFocus();
          },
        ),
        filled: true,
        fillColor: isScanMode ? const Color(0xFFE8F7EC) : (onNavy ? Colors.white : Pal.page),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: isScanMode ? const BorderSide(color: Colors.green, width: 2.5) : BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isScanMode ? Colors.green : Pal.amber, width: 2.5),
        ),
      ),
      onSubmitted: (val) => _performSearch(val, autoAddIfUnique: isScanMode),
    );
  }

  Widget _cart(DepotSaleProvider provider) {
    if (provider.cartItems.isEmpty) {
      if (provider.isLoading) return const Center(child: CircularProgressIndicator());
      return ListView(padding: const EdgeInsets.all(32), children: [
        const Icon(Icons.shopping_cart_outlined, size: 56, color: Colors.grey),
        const SizedBox(height: 10),
        Text(
          provider.selectedDepot == null
              ? "Choisissez d'abord le dépôt / client, puis scannez ou saisissez un produit."
              : "Panier vide. Scannez ou saisissez un produit.",
          textAlign: TextAlign.center,
          style: const TextStyle(color: Pal.muted, fontSize: 15),
        ),
      ]);
    }
    final items = provider.cartItems;
    if (style == ListPresentation.compact) {
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 12),
        itemCount: items.length,
        itemBuilder: (_, i) => _rowB(items[i], provider),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _card(items[i], provider, guided: style == ListPresentation.guided),
    );
  }

  String _lineDetail(SaleLine item) => "${Constants.formatNumber(item.intPRICEUNITAIR)} F x ${item.intQUANTITY}";

  Widget _lineTotal(SaleLine item, {double size = 15}) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Text("${Constants.formatNumber(item.intPRICE)} F", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: size)),
      );

  List<Widget> _lineActions(SaleLine item, DepotSaleProvider provider) => [
        IconButton(
          icon: const Icon(Icons.edit, color: Colors.orange),
          onPressed: _busy(provider) ? null : () => _showEditDialog(item),
          tooltip: "Modifier",
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: _busy(provider) ? null : () => _confirmDeleteItem(item),
          tooltip: "Supprimer",
        ),
      ];

  // A et C : cartes.
  Widget _card(SaleLine item, DepotSaleProvider provider, {required bool guided}) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _busy(provider) ? null : () => _showEditDialog(item),
        child: SoftCard(
          band: guided ? Pal.blue : null,
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 6),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.strNAME.isEmpty ? '—' : item.strNAME,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, color: Pal.ink, fontSize: 15)),
                const SizedBox(height: 4),
                Text(_lineDetail(item), style: const TextStyle(color: Pal.muted, fontSize: 13)),
                Align(alignment: Alignment.centerLeft, child: _lineTotal(item, size: 16)),
              ]),
            ),
            ..._lineActions(item, provider),
          ]),
        ),
      );

  // B : lignes compactes.
  Widget _rowB(SaleLine item, DepotSaleProvider provider) => InkWell(
        onTap: _busy(provider) ? null : () => _showEditDialog(item),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 6, 0, 6),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEF1F5)))),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.strNAME.isEmpty ? '—' : item.strNAME,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, color: Pal.ink)),
                Text(_lineDetail(item), style: const TextStyle(fontSize: 13, color: Pal.muted)),
              ]),
            ),
            ConstrainedBox(constraints: const BoxConstraints(maxWidth: 96), child: _lineTotal(item)),
            ..._lineActions(item, provider),
          ]),
        ),
      );

  Widget _bottomBar(DepotSaleProvider provider, bool guided) {
    final canClose = provider.cartItems.isNotEmpty && !_busy(provider) && provider.cartError == null;
    return Container(
      decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, -2))]),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(children: [
            Expanded(
              flex: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                decoration: BoxDecoration(color: Pal.page, borderRadius: BorderRadius.circular(12), border: Border.all(color: Pal.line)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                  const Text("TOTAL NET", style: TextStyle(fontSize: 12, color: Pal.muted, fontWeight: FontWeight.w600)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text("${Constants.formatNumber(provider.totalAmount)} F",
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Pal.ink)),
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 5,
              child: SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  style: guided
                      ? amberButton
                      : ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                  onPressed: canClose ? _validateSale : null,
                  icon: _closing
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check_circle_outline),
                  label: const FittedBox(fit: BoxFit.scaleDown, child: Text("CLÔTURER")),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// =========================================================
// QUANTITY DIALOG (contrôle de saisie : entier 1..9999)
// =========================================================
class QuantityDialog extends StatefulWidget {
  final ProductSearchResult product;
  final bool isSmartMode;
  const QuantityDialog({super.key, required this.product, this.isSmartMode = false});

  @override
  State<QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<QuantityDialog> {
  final _formKey = GlobalKey<FormState>();
  final _qteController = TextEditingController(text: "1");
  final _qtyFocusNode = FocusNode();
  bool _confirming = false;

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

  static String? validateQty(String? val) {
    final v = (val ?? '').trim();
    if (v.isEmpty) return "Requis";
    final n = int.tryParse(v);
    if (n == null) return "Invalide";
    if (n <= 0) return "Min 1";
    if (n > DepotSaleLimits.maxAddQty) return "Trop grand ! (max ${DepotSaleLimits.maxAddQty})";
    return null;
  }

  void _submit() async {
    if (_confirming) return;
    if (!_formKey.currentState!.validate()) {
      _qtyFocusNode.requestFocus();
      _qteController.selection = TextSelection(baseOffset: 0, extentOffset: _qteController.text.length);
      return;
    }
    final qty = int.tryParse(_qteController.text.trim());
    if (qty == null) return;
    if (qty > 50) {
      _confirming = true;
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
      _confirming = false;
      if (!mounted) return;
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
    final p = widget.product;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.isSmartMode)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
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
          Text(p.strNAME, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Pal.ink)),
          const SizedBox(height: 6),
          Wrap(spacing: 12, runSpacing: 2, children: [
            Text("CIP: ${p.intCIP}", style: const TextStyle(fontSize: 12, color: Pal.muted)),
            Text("Stock: ${p.intNUMBERAVAILABLE}",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: p.intNUMBERAVAILABLE <= 0 ? Colors.red : Pal.ink)),
            Text("Prix: ${Constants.formatNumber(p.intPRICE)} F", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Pal.ink)),
          ]),
        ],
      ),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _qteController,
          focusNode: _qtyFocusNode,
          decoration: InputDecoration(
            labelText: widget.isSmartMode ? 'Quantité Restante' : 'Quantité',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
          validator: validateQty,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        ElevatedButton(style: navyButton, onPressed: _submit, child: const Text('Ajouter')),
      ],
    );
  }
}

// =========================================================
// EDIT LINE DIALOG : quantité 1..99999, prix 0..999 999 999 ; attend la réponse du serveur.
// =========================================================
class EditLineDialog extends StatefulWidget {
  final SaleLine item;
  const EditLineDialog({super.key, required this.item});

  @override
  State<EditLineDialog> createState() => _EditLineDialogState();
}

class _EditLineDialogState extends State<EditLineDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _qteController;
  late TextEditingController _priceController;
  final FocusNode _qteFocusNode = FocusNode();
  final FocusNode _priceFocusNode = FocusNode();
  bool _busy = false;
  String? _error;

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

  static String? validateQty(String? val) {
    final n = int.tryParse((val ?? '').trim());
    if ((val ?? '').trim().isEmpty) return "Quantité requise";
    if (n == null) return "Quantité invalide";
    if (n < 1) return "Minimum 1";
    if (n > DepotSaleLimits.maxQty) return "Maximum ${DepotSaleLimits.maxQty}";
    return null;
  }

  static String? validatePrice(String? val) {
    final n = int.tryParse((val ?? '').trim());
    if ((val ?? '').trim().isEmpty) return "Prix requis";
    if (n == null) return "Prix invalide";
    if (n < 0) return "Prix négatif interdit";
    if (n > DepotSaleLimits.maxPrice) return "Prix trop élevé";
    return null;
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!_formKey.currentState!.validate()) return;
    final qty = int.tryParse(_qteController.text.trim());
    final price = int.tryParse(_priceController.text.trim());
    if (qty == null || price == null || qty <= 0) return;

    if (price == 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text("Prix à 0"),
          content: const Text("Le prix unitaire est à 0 F. Confirmer ?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("Non")),
            ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text("Oui")),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final provider = Provider.of<DepotSaleProvider>(context, listen: false);
    final success = await provider.updateItem(widget.item, qty, price);
    if (!mounted) return;
    if (success) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _busy = false;
        _error = provider.errorMessage.isNotEmpty ? provider.errorMessage : "Ligne non modifiée. Réessayez.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.item.strNAME, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Pal.ink)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
            child: const Text("MODIFICATION LIGNE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange)),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _qteController,
                focusNode: _qteFocusNode,
                enabled: !_busy,
                decoration: InputDecoration(labelText: "Quantité", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
                validator: validateQty,
                onFieldSubmitted: (_) => _priceFocusNode.requestFocus(),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _priceController,
                focusNode: _priceFocusNode,
                enabled: !_busy,
                decoration: InputDecoration(labelText: "Prix Unitaire", suffixText: 'F', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
                validator: validatePrice,
                onFieldSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text("Annuler")),
        ElevatedButton(
          style: navyButton,
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text("Valider"),
        ),
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