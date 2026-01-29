// lib/screens/depot_sale/depot_sale_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/depot_model.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/providers/depot_sale_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
// Import du modèle correct
import 'package:prestige_vente_app/api/models/product.dart';

class DepotSaleScreen extends StatefulWidget {
  const DepotSaleScreen({Key? key}) : super(key: key);

  @override
  State<DepotSaleScreen> createState() => _DepotSaleScreenState();
}

class _DepotSaleScreenState extends State<DepotSaleScreen> {
  // Contrôleurs pour la recherche intégrée
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<DepotModel> _availableDepots = [];
  bool _isLoadingDepots = false;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadDepots();
    // Focus automatique sur le champ de recherche au démarrage
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
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

  // --- LOGIQUE DE RECHERCHE ET D'AJOUT ---
  Future<void> _onSearchSubmitted(String value) async {
    final query = value.trim();
    if (query.isEmpty) return;

    final provider = Provider.of<DepotSaleProvider>(context, listen: false);

    // 1. Vérification Dépôt
    if (provider.selectedDepot == null) {
      _showError("Veuillez d'abord sélectionner un Dépôt / Client");
      _searchFocusNode.requestFocus(); // On garde le focus
      return;
    }

    setState(() => _isSearching = true);
    final api = Provider.of<ApiService>(context, listen: false);

    try {
      // 2. Appel API Recherche
      // On utilise la méthode existante qui retourne List<ProductSearchResult>
      final results = await api.searchProducts(query);

      if (!mounted) return;

      if (results.isEmpty) {
        _showError("Aucun produit trouvé pour '$query'");
      } else if (results.length == 1) {
        // CAS PARFAIT : 1 seul résultat (ex: scan code barre exact) -> Ajout Direct
        await _addProductToCart(results.first);
      } else {
        // PLUSIEURS RÉSULTATS : On demande à l'utilisateur de choisir
        _showSelectionDialog(results);
      }
    } catch (e) {
      _showError("Erreur de recherche: $e");
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
        _searchController.clear(); // On vide le champ pour le prochain scan
        _searchFocusNode.requestFocus(); // On remet le focus pour enchaîner
      }
    }
  }

  Future<void> _addProductToCart(ProductSearchResult product, {int qty = 1}) async {
    final provider = Provider.of<DepotSaleProvider>(context, listen: false);
    final success = await provider.addProduct(product, qty);

    if (mounted) {
      if (success) {
        // Petit feedback visuel non bloquant
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("${product.strNAME} ajouté"),
            duration: const Duration(milliseconds: 500),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        _showError(provider.errorMessage.isNotEmpty ? provider.errorMessage : "Erreur ajout");
      }
    }
  }

  // Affiche une liste de choix quand la recherche est ambiguë
  void _showSelectionDialog(List<ProductSearchResult> products) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Plusieurs résultats (${products.length})"),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.separated(
            itemCount: products.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (ctx, index) {
              final p = products[index];
              return ListTile(
                title: Text(p.strNAME, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("Stock: ${p.intNUMBERAVAILABLE} | Prix: ${p.intPRICE}"),
                onTap: () {
                  Navigator.pop(ctx); // Ferme le dialog
                  _addProductToCart(p); // Ajoute le produit choisi
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Annuler"),
          )
        ],
      ),
    ).then((_) {
      // Au retour du dialog, on remet le focus sur la barre de recherche
      _searchFocusNode.requestFocus();
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  // --- MODIFICATION / SUPPRESSION LIGNE ---
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
            TextField(
              controller: qtyController,
              decoration: const InputDecoration(labelText: "Quantité", border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
              autofocus: true,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: priceController,
              decoration: const InputDecoration(labelText: "Prix Unitaire", border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
            ),
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
        content: Text("Total: ${provider.totalAmount} FCFA\nConfirmer la clôture ?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Non")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Oui")),
        ],
      ),
    );

    if (confirm == true) {
      final success = await provider.closeSale();
      if (success && mounted) {
        Navigator.pop(context); // Retour liste
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Vente clôturée avec succès"), backgroundColor: Colors.green));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DepotSaleProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text("Nouvelle Vente Dépôt"),
            actions: [
              if (provider.cartItems.isNotEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: Text(
                      "${provider.totalAmount} FCFA",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                )
            ],
          ),
          body: Column(
            children: [
              // ZONE 1 : SÉLECTION DÉPÔT
              Container(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                color: Colors.white,
                child: provider.currentSaleId == null
                    ? _isLoadingDepots
                    ? const LinearProgressIndicator()
                    : DropdownButtonFormField<DepotModel>(
                  value: provider.selectedDepot,
                  decoration: const InputDecoration(
                    labelText: "Sélectionner le Dépôt / Client",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.store),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  ),
                  items: _availableDepots.map((depot) {
                    return DropdownMenuItem(
                      value: depot,
                      child: Text(
                        "${depot.fullName} (${depot.descriptionTypeDepot})",
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      provider.selectDepot(val);
                      _searchFocusNode.requestFocus();
                    }
                  },
                )
                    : Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock, color: Colors.green),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Client: ${provider.selectedDepot?.fullName ?? 'N/A'}", style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text("Réf Vente: ${provider.currentSaleId ?? '...'}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ZONE 2 : BARRE DE RECHERCHE / SCAN (INTÉGRÉE)
              Container(
                padding: const EdgeInsets.all(10),
                color: Colors.white,
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  decoration: InputDecoration(
                    hintText: "Scanner ou saisir un produit (Entrée pour valider)",
                    prefixIcon: _isSearching
                        ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.qr_code_scanner),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _searchFocusNode.requestFocus();
                      },
                    ),
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.blue.shade50.withOpacity(0.3),
                  ),
                  textInputAction: TextInputAction.go,
                  onSubmitted: _onSearchSubmitted, // Lance la recherche à la touche Entrée (ou fin de scan)
                ),
              ),

              const Divider(height: 1),

              // ZONE 3 : LISTE DU PANIER
              Expanded(
                child: provider.isLoading && !_isSearching
                    ? const Center(child: CircularProgressIndicator())
                    : provider.cartItems.isEmpty
                    ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.shopping_cart_outlined, size: 60, color: Colors.grey.shade300),
                      const SizedBox(height: 10),
                      const Text("Le panier est vide"),
                      const Text("Utilisez la barre ci-dessus pour ajouter des articles", style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                )
                    : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 80), // Espace pour le footer
                  itemCount: provider.cartItems.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = provider.cartItems[index];
                    return ListTile(
                      dense: true,
                      title: Text(item.strNAME, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4)),
                            child: Text("${item.intPRICEUNITAIR} F", style: TextStyle(color: Colors.blue.shade800, fontSize: 12)),
                          ),
                          const SizedBox(width: 5),
                          const Text("x"),
                          const SizedBox(width: 5),
                          Text("${item.intQUANTITY}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        ],
                      ),
                      trailing: Text(
                        "${item.intPRICE} F",
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primary),
                      ),
                      onTap: () => _editLine(item),
                    );
                  },
                ),
              ),

              // ZONE 4 : BOUTON CLOTURER (FOOTER)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, -2))],
                ),
                child: SafeArea(
                  child: ElevatedButton.icon(
                    onPressed: provider.cartItems.isEmpty ? null : _validateSale,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text("CLÔTURER LA VENTE"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                      elevation: 0,
                    ),
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