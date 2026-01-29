// lib/screens/depot_sale/depot_sale_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
//import 'package:intl/intl.dart'; // Pour le formatage, ou utilisez ma fonction helper ci-dessous
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

  List<DepotModel> _availableDepots = [];
  bool _isLoadingDepots = false;
  bool _isSearching = false;

  Timer? _debounce;

  // --- HELPER FORMATAGE MONNAIE (Séparateur milliers) ---
  String _formatCurrency(int amount) {
    // Si vous avez le package intl, utilisez NumberFormat
    // Sinon, voici une regex simple pour ajouter les espaces
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
        _searchFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _depotFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
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
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (value.trim().isNotEmpty) {
        _performSearch(value.trim());
      }
    });
  }

  Future<void> _performSearch(String query) async {
    final provider = Provider.of<DepotSaleProvider>(context, listen: false);

    if (provider.selectedDepot == null) {
      _showError("Veuillez d'abord sélectionner un Dépôt / Client");
      return;
    }

    setState(() => _isSearching = true);
    final api = Provider.of<ApiService>(context, listen: false);

    try {
      final results = await api.searchProducts(query);
      if (!mounted) return;

      if (results.length == 1) {
        if (query.length > 5 && (query == results.first.intCIP || query == results.first.lgFAMILLEID)) {
          _checkStockAndAdd(results.first);
        } else {
          _showSelectionDialog(results);
        }
      } else if (results.isNotEmpty) {
        _showSelectionDialog(results);
      }
    } catch (e) {
      _showError("Erreur : $e");
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _checkStockAndAdd(ProductSearchResult product) async {
    if (product.intNUMBERAVAILABLE <= 0) {
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

      if (force != true) {
        _searchController.clear();
        _searchFocusNode.requestFocus();
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
      _searchFocusNode.requestFocus();
    }
  }

  void _showSelectionDialog(List<ProductSearchResult> products) {
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
      _searchController.clear();
      _searchFocusNode.requestFocus();
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.red));
  }

  void _editLine(SaleLine item) {
    final qtyController = TextEditingController(text: item.intQUANTITY.toString());
    final priceController = TextEditingController(text: item.intPRICEUNITAIR.toString());

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
    ).then((_) => _searchFocusNode.requestFocus());
  }

  Future<void> _validateSale() async {
    final provider = Provider.of<DepotSaleProvider>(context, listen: false);
    if (provider.cartItems.isEmpty) return;

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

    if (confirm == true) {
      final success = await provider.closeSale();
      if (success && mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Vente clôturée avec succès"), backgroundColor: Colors.green));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DepotSaleProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          appBar: AppBar(title: const Text("Nouvelle Vente Dépôt")),

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
                        _searchFocusNode.requestFocus();
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
                            // MODIFICATION 1: Affichage de la REF stockée dans le Provider
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

              // ZONE 2 : RECHERCHE
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                color: Colors.white,
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    hintText: "Saisir nom ou scanner",
                    prefixIcon: _isSearching
                        ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.search),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () { _searchController.clear(); _searchFocusNode.requestFocus(); },
                    ),
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.blue.shade50.withOpacity(0.3),
                  ),
                ),
              ),

              const Divider(height: 1),

              // ZONE 3 : LISTE PRODUITS (Avec séparateurs milliers)
              Expanded(
                child: provider.isLoading && !_isSearching
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
                      title: Text(item.strNAME, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text("${_formatCurrency(item.intPRICEUNITAIR)} F x ${item.intQUANTITY}"),
                      trailing: Text(
                        "${_formatCurrency(item.intPRICE)} F",
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                      ),
                      onTap: () => _editLine(item),
                    );
                  },
                ),
              ),

              // ZONE 4 : FOOTER (Refonte complète)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, -2))]
                ),
                child: SafeArea(
                  child: Row(
                    children: [
                      // BOUTON CLOTURER (40% de l'espace)
                      Expanded(
                        flex: 4,
                        child: ElevatedButton.icon(
                          onPressed: provider.cartItems.isEmpty ? null : _validateSale,
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text("CLÔTURER"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 18), // Plus haut
                            elevation: 2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 15),

                      // ZONE TOTAL AGRANDIE (60% de l'espace)
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
                              // MODIFICATION : Texte plus grand et formaté
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  "${_formatCurrency(provider.totalAmount)} F",
                                  style: const TextStyle(
                                      fontSize: 28, // Beaucoup plus gros
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
    );
  }
}