// lib/screens/depot_sale/depot_sale_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/depot_model.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/providers/depot_sale_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/api/models/product.dart';

class DepotSaleScreen extends StatefulWidget {
  const DepotSaleScreen({Key? key}) : super(key: key);

  @override
  State<DepotSaleScreen> createState() => _DepotSaleScreenState();
}

class _DepotSaleScreenState extends State<DepotSaleScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _depotFocusNode = FocusNode();
  final FocusNode _keyboardFocusNode = FocusNode(); // Pour le scanner global

  List<DepotModel> _availableDepots = [];
  bool _isLoadingDepots = false;

  // VERROU DE SÉCURITÉ ANTI-DOUBLON & ETAT DE RECHERCHE UI
  bool _isProcessing = false;

  String _scanBuffer = "";
  Timer? _debounce;
  bool _isPopupOpen = false;

  // --- HELPER FORMATAGE MONNAIE ---
  String _formatCurrency(int amount) {
    return amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]} ');
  }

  @override
  void initState() {
    super.initState();
    _loadDepots();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Provider.of<DepotSaleProvider>(context, listen: false).selectedDepot == null) {
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

  // GESTION DU SCANNER (Mode Clavier Externe)
  void _handleKeyEvent(KeyEvent event) {
    final provider = Provider.of<DepotSaleProvider>(context, listen: false);
    if (!provider.isQuickScanMode) return;
    if (_isPopupOpen) return;

    // PROTECTION CAS 2: Si le champ a le focus, on ignore le scan global pour éviter double validation
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

  Future<void> _loadDepots() async {
    setState(() => _isLoadingDepots = true);
    final api = Provider.of<ApiService>(context, listen: false);
    final list = await api.fetchDepots();
    if (mounted) {
      setState(() {
        _availableDepots = list;
        _isLoadingDepots = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    // En mode Scan Rapide, on peut désactiver le debounce automatique si souhaité
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (value.trim().isNotEmpty) {
        _performSearch(value.trim());
      }
    });
  }

  Future<void> _performSearch(String query) async {
    // VERROU DE SÉCURITÉ
    if (_isProcessing) return;
    if (query.isEmpty) return;

    final provider = Provider.of<DepotSaleProvider>(context, listen: false);

    if (provider.selectedDepot == null) {
      _showError("Veuillez d'abord sélectionner un Dépôt / Client");
      _searchController.clear();
      return;
    }

    // _isProcessing sert aussi d'indicateur de chargement UI (remplace _isSearching)
    setState(() => _isProcessing = true);
    final api = Provider.of<ApiService>(context, listen: false);

    try {
      final results = await api.searchProducts(query);
      if (!mounted) return;

      if (results.length == 1) {
        // CAS: 1 seul résultat trouvé
        final product = results.first;

        // Nettoyage immédiat pour éviter doublons pendant traitement
        _searchController.clear();

        if (provider.isQuickScanMode) {
          // Mode Scan Rapide : Ajout direct
          await _checkStockAndAdd(product);
        } else {
          // Mode Normal : Logique existante (match exact ou dialogue)
          if (query.length > 5 && (query == product.intCIP || query == product.lgFAMILLEID)) {
            await _checkStockAndAdd(product);
          } else {
            _showSelectionDialog(results);
          }
        }
      } else if (results.isNotEmpty) {
        _showSelectionDialog(results);
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

  Future<void> _checkStockAndAdd(ProductSearchResult product) async {
    if (product.intNUMBERAVAILABLE <= 0) {
      setState(() => _isPopupOpen = true);
      final bool? force = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Stock Insuffisant", style: TextStyle(color: Colors.red)),
          content: Text("Le produit ${product.strNAME} est en rupture (Stock: ${product.intNUMBERAVAILABLE}).\nVoulez-vous forcer le stock ?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Non")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("OUI, FORCER", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      setState(() => _isPopupOpen = false);

      if (force != true) {
        _searchController.clear();
        _requestSearchFocus();
        return;
      }
    }
    await _addProductToCart(product);
  }

  Future<void> _addProductToCart(ProductSearchResult product, {int qty = 1}) async {
    final provider = Provider.of<DepotSaleProvider>(context, listen: false);
    final success = await provider.addProduct(product, qty);

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("${product.strNAME} ajouté"),
            duration: const Duration(milliseconds: 500),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _searchController.clear();
      } else {
        _showError(provider.errorMessage.isNotEmpty ? provider.errorMessage : "Erreur ajout");
      }
      // On redonne le focus seulement si on n'est pas déjà en train de traiter autre chose
      if(!_isProcessing) _requestSearchFocus();
    }
  }

  void _showSelectionDialog(List<ProductSearchResult> products) {
    setState(() => _isPopupOpen = true);
    showDialog(
      context: context,
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
                subtitle: Text(
                  "Stock: ${p.intNUMBERAVAILABLE} | Prix: ${_formatCurrency(p.intPRICE)} F",
                  style: TextStyle(color: isRupture ? Colors.red : Colors.grey[700], fontWeight: isRupture ? FontWeight.bold : FontWeight.normal),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _checkStockAndAdd(p);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Fermer"))
        ],
      ),
    ).then((_) {
      setState(() => _isPopupOpen = false);
      _searchController.clear();
      _requestSearchFocus();
    });
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

  void _editLine(SaleLine item) {
    final qtyController = TextEditingController(text: item.intQUANTITY.toString());
    final priceController = TextEditingController(text: item.intPRICEUNITAIR.toString());

    setState(() => _isPopupOpen = true);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item.strNAME),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: qtyController, decoration: const InputDecoration(labelText: "Quantité"), keyboardType: TextInputType.number, autofocus: true),
            TextField(controller: priceController, decoration: const InputDecoration(labelText: "Prix Unitaire"), keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await Provider.of<DepotSaleProvider>(context, listen: false).removeItem(item.lgPREENREGISTREMENTDETAILID);
            },
            child: const Text("Supprimer", style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () async {
              final qty = int.tryParse(qtyController.text) ?? item.intQUANTITY;
              final price = int.tryParse(priceController.text) ?? item.intPRICEUNITAIR;
              Navigator.pop(ctx);
              await Provider.of<DepotSaleProvider>(context, listen: false).updateItem(item, qty, price);
            },
            child: const Text("Valider"),
          )
        ],
      ),
    ).then((_) {
      setState(() => _isPopupOpen = false);
      _requestSearchFocus();
    });
  }

  Future<void> _validateSale() async {
    final provider = Provider.of<DepotSaleProvider>(context, listen: false);
    if (provider.cartItems.isEmpty) return;

    setState(() => _isPopupOpen = true);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Clôturer Vente Dépôt"),
        content: Text("Total: ${_formatCurrency(provider.totalAmount)} FCFA\nConfirmer la clôture ?"),
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
        // Reset focus
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

          return Scaffold(
            appBar: AppBar(
              title: const Text("Nouvelle Vente Dépôt"),
              actions: [
                // BOUTON TOGGLE SCAN RAPIDE
                IconButton(
                  tooltip: isScanMode ? "Désactiver Scan Rapide" : "Activer Scan Rapide",
                  icon: Icon(
                      isScanMode ? Icons.bolt : Icons.flash_off,
                      color: isScanMode ? Colors.greenAccent : null
                  ),
                  onPressed: () {
                    provider.toggleQuickScanMode();
                    _requestSearchFocus();
                  },
                )
              ],
            ),

            body: Column(
              children: [
                // ZONE 1 : SELECTION DEPOT + INFOS VENTE
                Container(
                  padding: const EdgeInsets.all(10),
                  color: Colors.white,
                  child: provider.currentSaleId == null
                      ? _isLoadingDepots
                      ? const LinearProgressIndicator()
                      : DropdownButtonFormField<DepotModel>(
                    value: provider.selectedDepot,
                    focusNode: _depotFocusNode,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: "Sélectionner le Dépôt / Client",
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.store),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10),
                    ),
                    items: _availableDepots.map((depot) {
                      return DropdownMenuItem(
                        value: depot,
                        child: Text("${depot.fullName} (${depot.descriptionTypeDepot})", overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        provider.selectDepot(val);
                        Future.delayed(const Duration(milliseconds: 100), () {
                          _requestSearchFocus();
                        });
                      }
                    },
                  )
                      : Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.grey.shade100, border: Border.all(color: Colors.grey.shade300)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Client: ${provider.selectedDepot?.fullName}", style: const TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text(
                                "REF: ${provider.currentSaleRef ?? '...'}",
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: Colors.blue.shade100, borderRadius: BorderRadius.circular(20)),
                          child: Text(
                            "${provider.cartItems.length} Produit(s)",
                            style: TextStyle(color: Colors.blue.shade800, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ZONE 2 : RECHERCHE (Avec Style Scan Rapide)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  color: Colors.white,
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: isScanMode ? "SCAN RAPIDE ACTIF" : "Saisir nom ou scanner",
                      // CORRECTION ICI : Utilisation de _isProcessing au lieu de _isSearching
                      prefixIcon: _isProcessing
                          ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(isScanMode ? Icons.bolt : Icons.search, color: isScanMode ? Colors.green : null),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () { _searchController.clear(); _requestSearchFocus(); },
                      ),
                      border: const OutlineInputBorder(),

                      // COULEUR DE BORDURE VERTE SI SCAN ACTIF
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: isScanMode ? Colors.green : Colors.grey, width: isScanMode ? 2.5 : 1.0),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: isScanMode ? Colors.green : Theme.of(context).primaryColor, width: isScanMode ? 2.5 : 2.0),
                      ),

                      filled: true,
                      fillColor: isScanMode ? Colors.green.withValues(alpha: 0.1) : Colors.blue.shade50.withValues(alpha: 0.3),
                    ),
                    onSubmitted: (val) {
                      // Validation manuelle
                      _performSearch(val);
                      _requestSearchFocus();
                    },
                  ),
                ),

                const Divider(height: 1),

                // ZONE 3 : LISTE PRODUITS (Compacte + Delete Button)
                Expanded(
                  // CORRECTION ICI AUSSI
                  child: provider.isLoading && !_isProcessing
                      ? const Center(child: CircularProgressIndicator())
                      : provider.cartItems.isEmpty
                      ? const Center(child: Text("Panier vide. Scannez ou saisissez un produit."))
                      : ListView.separated(
                    itemCount: provider.cartItems.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = provider.cartItems[index];
                      return ListTile(
                        dense: true,
                        visualDensity: const VisualDensity(vertical: -2), // Compact
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),

                        title: Text(
                          item.strNAME,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),

                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 2.0),
                          child: Text("${_formatCurrency(item.intPRICEUNITAIR)} F x ${item.intQUANTITY}"),
                        ),

                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "${_formatCurrency(item.intPRICE)} F",
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                            ),
                            const SizedBox(width: 8),
                            // BOUTON SUPPRIMER DIRECT SUR LA LIGNE
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              tooltip: "Supprimer",
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => _confirmDeleteItem(item),
                            ),
                          ],
                        ),

                        onTap: () => _editLine(item),
                      );
                    },
                  ),
                ),

                // ZONE 4 : FOOTER
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, -2))]
                  ),
                  child: SafeArea(
                    child: Row(
                      children: [
                        // BOUTON CLOTURER
                        Expanded(
                          flex: 4,
                          child: ElevatedButton.icon(
                            onPressed: provider.cartItems.isEmpty ? null : _validateSale,
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text("CLÔTURER"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              elevation: 2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 15),

                        // ZONE TOTAL
                        Expanded(
                          flex: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text("TOTAL NET", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    "${_formatCurrency(provider.totalAmount)} F",
                                    style: const TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.black,
                                        letterSpacing: 0.5
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      ],
                    ),
                  ),
                )
              ],
            ),
          );
        },
      ),
    );
  }
}