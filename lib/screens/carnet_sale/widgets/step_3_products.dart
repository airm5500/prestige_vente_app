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

  @override
  void initState() {
    super.initState();
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
    _searchController.dispose();
    _searchFocusNode.dispose();
    _keyboardFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // --- 1. GESTION SCAN PHYSIQUE (BUFFER DOUCHETTE) ---
  void _handleKeyEvent(KeyEvent event) {
    final provider = Provider.of<CarnetSaleProvider>(context, listen: false);

    // Actif uniquement si le mode Scan Rapide est ON
    if (!provider.isQuickScanMode) return;
    if (_isPopupOpen) return;

    // Si le champ a le focus et n'est pas vide, on laisse le TextField gérer (cas saisie mixte)
    if (_searchFocusNode.hasFocus && _searchController.text.isNotEmpty) {
      _scanBuffer = "";
      return;
    }

    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        if (_scanBuffer.isNotEmpty) {
          // Scan Douchette fini -> Auto Add activé
          _performSearch(_scanBuffer.trim(), autoAddIfUnique: true);
          _scanBuffer = "";
        }
      } else if (event.character != null) {
        _scanBuffer += event.character!;
      }
    }
  }

  // --- 2. GESTION SAISIE CLAVIER (LISTENER) ---
  void _onSearchChanged() {
    final provider = Provider.of<CarnetSaleProvider>(context, listen: false);

    // Si Scan Rapide est ON : Pas de recherche automatique pendant la frappe.
    // On attend que l'utilisateur fasse "Entrée" (géré dans onSubmitted plus bas).
    if (provider.isQuickScanMode) return;

    // Si Scan Rapide est OFF (Mode Normal) : Recherche automatique (Debounce)
    final text = _searchController.text.trim();
    if (text.isEmpty) {
      provider.clearProductSearch();
      return;
    }

    if (_isPopupOpen) return;
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      if (_isPopupOpen) return;
      if (text.isNotEmpty && text.length >= 2) {
        // Mode Normal : On n'ajoute JAMAIS automatiquement, on propose.
        _performSearch(text, autoAddIfUnique: false);
      }
    });
  }

  // --- 3. EXÉCUTION DE LA RECHERCHE (COEUR DU SYSTÈME) ---
  // autoAddIfUnique = TRUE si Mode Scan Rapide (Douchette ou Entrée Clavier)
  // autoAddIfUnique = FALSE si Mode Normal (Saisie Debounce)
  Future<void> _performSearch(String query, {required bool autoAddIfUnique}) async {
    _debounce?.cancel();
    if (_isPopupOpen) return;
    if (query.isEmpty) return;

    final provider = Provider.of<CarnetSaleProvider>(context, listen: false);

    try {
      if (mounted) setState(() => _isProcessing = true);

      await provider.searchProducts(query);

      if (!mounted) return;
      if (_isPopupOpen) return;

      final results = provider.productSearchResults;

      if (results.isEmpty) {
        // Uniquement si on attendait une action immédiate (Scan Rapide)
        if (autoAddIfUnique) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Produit introuvable"), backgroundColor: Colors.orange, duration: Duration(seconds: 1)),
          );
          _searchController.clear();
        }
      } else {
        // CAS A : RÉSULTAT UNIQUE
        if (results.length == 1) {
          final product = results.first;

          if (autoAddIfUnique) {
            // MODE SCAN RAPIDE -> AJOUT DIRECT (Qté 1)
            _searchController.clear();
            provider.clearProductSearch();
            _checkStockAndAddDirectly(product);
          } else {
            // MODE NORMAL -> OUVERTURE POPUP QUANTITÉ
            _searchController.clear();
            provider.clearProductSearch();
            _showQuantityDialog(product);
          }
        }
        // CAS B : RÉSULTATS MULTIPLES
        else {
          // Dans tous les cas (Scan ou Normal), s'il y a plusieurs choix, on ouvre le modal
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

  // AJOUT DIRECT 1 UNITÉ (Avec vérif stock)
  void _checkStockAndAddDirectly(ProductSearchResult product) {
    // Si Stock épuisé -> On force l'utilisateur à confirmer via le dialogue
    if (product.intNUMBERAVAILABLE <= 0) {
      _showForceStockDialog(product, 1);
    } else {
      // Stock OK -> Ajout direct
      Provider.of<CarnetSaleProvider>(context, listen: false).addProductToCart(product, 1);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${product.strNAME} ajouté (+1)"), duration: const Duration(milliseconds: 500), backgroundColor: Colors.green),
      );
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
        initialQuery: _searchController.text, // On transmet le texte saisi
        onProductSelected: (product) {
          Navigator.pop(ctx, product);
        },
      ),
    );

    if (selectedProduct != null) {
      provider.clearProductSearch();
      _searchController.clear();
      // Petit délai UI
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          // Choix manuel depuis la liste -> Toujours demander la quantité
          _showQuantityDialog(selectedProduct);
        }
      });
    } else {
      if (mounted) {
        setState(() => _isPopupOpen = false);
        _requestSearchFocus();
      }
    }
  }

  // --- 5. POPUP QUANTITÉ ---
  void _showQuantityDialog(ProductSearchResult product) {
    final provider = Provider.of<CarnetSaleProvider>(context, listen: false);
    final formKey = GlobalKey<FormState>();
    final qteController = TextEditingController(text: "1");

    qteController.selection = TextSelection(baseOffset: 0, extentOffset: qteController.text.length);

    setState(() => _isPopupOpen = true);

    void submit() async {
      if (!formKey.currentState!.validate()) return;
      final qty = int.parse(qteController.text);

      if (qty > 50) {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text("Quantité élevée"),
            content: Text("Ajouter $qty unités ?"),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("Non")),
              ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text("Oui")),
            ],
          ),
        );
        if (confirm != true) return;
      }

      Navigator.pop(context);

      if (qty > product.intNUMBERAVAILABLE) {
        _showForceStockDialog(product, qty);
      } else {
        provider.addProductToCart(product, qty);
        _searchController.clear();
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(product.strNAME, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Stock: ${product.intNUMBERAVAILABLE} | Prix: ${Constants.formatNumber(product.intPRICE)} F"),
              const SizedBox(height: 10),
              TextFormField(
                controller: qteController,
                autofocus: true,
                decoration: const InputDecoration(labelText: "Quantité", border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
                validator: (val) => (int.tryParse(val ?? "") ?? 0) <= 0 ? "Invalide" : null,
                onFieldSubmitted: (_) => submit(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          ElevatedButton(onPressed: submit, child: const Text("Valider")),
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
        content: Text('Stock dispo : ${product.intNUMBERAVAILABLE}.\nForcer l\'ajout de $qty ?'),
        actions: [
          TextButton(child: const Text('Non'), onPressed: () => Navigator.pop(ctx)),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                Navigator.pop(ctx);
                Provider.of<CarnetSaleProvider>(context, listen: false).addProductToCart(product, qty);
                _searchController.clear();
              },
              child: const Text('OUI', style: TextStyle(color: Colors.white))
          ),
        ],
      ),
    ).then((_) => setState(() => _isPopupOpen = false));
  }

  // --- UI ---
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
          // HEADER CLIENT
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
          // CONTENU
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
              // EN SCAN RAPIDE, On ignore le onChanged (pas de debounce)
              onChanged: (_) => _onSearchChanged(),
              // EN SCAN RAPIDE, La touche Entrée vaut validation Douchette
              onSubmitted: (val) {
                if (val.isNotEmpty) {
                  // Si Scan Rapide est ON, autoAddIfUnique est TRUE
                  // Si Scan Rapide est OFF, autoAddIfUnique est FALSE (sécurité)
                  _performSearch(val, autoAddIfUnique: isActive);
                  _requestSearchFocus();
                }
              },
              decoration: InputDecoration(
                hintText: isActive ? 'MODE SCAN ACTIF (Saisir + Entrée)' : 'Recherche (Auto) ou Scanner',
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

// =========================================================
// MODAL RÉSULTATS (AVEC REPRISE TEXTE & FILTRE)
// =========================================================
class ProductListModal extends StatefulWidget {
  final List<ProductSearchResult> results;
  final String initialQuery;
  final Function(ProductSearchResult) onProductSelected;

  const ProductListModal({
    super.key,
    required this.results,
    required this.initialQuery,
    required this.onProductSelected,
  });

  @override
  State<ProductListModal> createState() => _ProductListModalState();
}

class _ProductListModalState extends State<ProductListModal> {
  late List<ProductSearchResult> _filteredList;
  final TextEditingController _modalSearchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filteredList = widget.results;

    // Reprise du texte et placement curseur
    _modalSearchCtrl.text = widget.initialQuery;
    _modalSearchCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _modalSearchCtrl.text.length)
    );
  }

  @override
  void dispose() {
    _modalSearchCtrl.dispose();
    super.dispose();
  }

  void _filterResults(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredList = widget.results;
      } else {
        _filteredList = widget.results.where((p) {
          final q = query.toLowerCase();
          return p.strNAME.toLowerCase().contains(q) ||
              p.intCIP.toString().contains(q);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Résultats (${widget.results.length})", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              )
            ],
          ),

          const SizedBox(height: 10),

          TextField(
            controller: _modalSearchCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: "Filtrer dans la liste...",
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              isDense: true,
            ),
            onChanged: _filterResults,
          ),

          const SizedBox(height: 10),
          const Divider(height: 1),

          Expanded(
            child: _filteredList.isEmpty
                ? const Center(child: Text("Aucun produit ne correspond au filtre."))
                : ListView.separated(
              itemCount: _filteredList.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, index) {
                final p = _filteredList[index];
                return ListTile(
                  dense: true,
                  title: Text(p.strNAME, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("CIP: ${p.intCIP} | Stock: ${p.intNUMBERAVAILABLE} | Prix: ${Constants.formatNumber(p.intPRICE)} F"),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                  onTap: () {
                    widget.onProductSelected(p);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}