// lib/screens/depot_sale/depot_sale_screen.dart
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
//import 'package:prestige_vente_app/api/models/product_search_result.dart'; // IMPORTANT

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

  // --- GESTION CLAVIER / SCANNER ---
  void _handleKeyEvent(KeyEvent event) {
    final provider = Provider.of<DepotSaleProvider>(context, listen: false);
    // Si on n'est pas en scan rapide, on laisse le comportement standard
    if (!provider.isQuickScanMode) return;
    if (_isPopupOpen) return;

    if (_searchFocusNode.hasFocus) {
      _scanBuffer = "";
      return;
    }

    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        if (_scanBuffer.isNotEmpty) {
          // CORRECTION: isScan: true
          _performSearch(_scanBuffer.trim(), isScan: true);
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

  // --- LISTENER CHAMPS DE RECHERCHE ---
  void _onSearchChanged(String value) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (value.trim().isNotEmpty) {
        // CORRECTION: isScan: false (saisie manuelle)
        _performSearch(value.trim(), isScan: false);
      }
    });
  }

  // --- CŒUR DE LA RECHERCHE ---
  Future<void> _performSearch(String query, {required bool isScan}) async {
    if (_isProcessing) return;
    if (_isPopupOpen) return;
    if (query.isEmpty) return;

    final provider = Provider.of<DepotSaleProvider>(context, listen: false);

    if (provider.selectedDepot == null) {
      _showError("Veuillez d'abord sélectionner un Dépôt / Client");
      _searchController.clear();
      return;
    }

    setState(() => _isProcessing = true);

    try {
      // 1. Appel Provider pour chercher
      await provider.searchProducts(query);

      if (!mounted) return;
      if (_isPopupOpen) return;

      final results = provider.searchResults;

      if (results.length == 1) {
        final product = results.first;

        // On vide immédiatement
        _searchController.clear();
        provider.clearSearchResults();

        // 2. LOGIQUE MODE
        if (provider.isQuickScanMode) {
          // --- MODE RAPIDE : AJOUT DIRECT (1) ---
          // Mais on vérifie le stock quand même (Sécurité Stock)
          if (product.intNUMBERAVAILABLE < 1) {
            _showForceStockDialog(product, 1);
          } else {
            // Ajout direct
            await _addProductToCart(product, qty: 1);
          }
        } else {
          // --- MODE MANUEL : POPUP QUANTITÉ ---
          _showQuantityDialog(product);
        }

      } else if (results.isNotEmpty) {
        // Plusieurs résultats
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

  // --- AJOUTER AU PANIER ---
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
      if(!_isProcessing) _requestSearchFocus();
    }
  }

  // --- POPUP SÉLECTION (PLUSIEURS RÉSULTATS) ---
  void _showSelectionDialog(List<ProductSearchResult> results) {
    final provider = Provider.of<DepotSaleProvider>(context, listen: false);
    // On copie la liste pour le dialog
    final dialogResults = List<ProductSearchResult>.from(results);
    provider.clearSearchResults();

    setState(() => _isPopupOpen = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text("Résultats (${dialogResults.length})"),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.separated(
            itemCount: dialogResults.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, index) {
              final p = dialogResults[index];
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(p.strNAME, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                  "Stock: ${p.intNUMBERAVAILABLE} | Prix: ${_formatCurrency(p.intPRICE)} F",
                  style: TextStyle(color: p.intNUMBERAVAILABLE <= 0 ? Colors.red : Colors.grey[700]),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  // En manuel, on ouvre toujours le choix de quantité
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
                _searchController.clear();
              },
              child: const Text("Fermer")
          )
        ],
      ),
    ).then((_) {
      if (mounted) {
        setState(() => _isPopupOpen = false);
        Future.delayed(const Duration(milliseconds: 300), () {
          if(mounted && !_isPopupOpen) _requestSearchFocus();
        });
      }
    });
  }

  // --- POPUP QUANTITÉ SÉCURISÉ ---
  void _showQuantityDialog(ProductSearchResult product) {
    final provider = Provider.of<DepotSaleProvider>(context, listen: false);
    final formKey = GlobalKey<FormState>();
    final qteController = TextEditingController(text: "1");

    // 1. Auto-sélection à l'ouverture
    qteController.selection = TextSelection(baseOffset: 0, extentOffset: qteController.text.length);

    setState(() => _isPopupOpen = true);

    void submit() async {
      // 2. BLOCAGE ANTI-CODE BARRES (Validateur)
      if (!formKey.currentState!.validate()) {
        // Si erreur, on re-sélectionne après un micro-délai (pour contrer le scanner)
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted && qteController.text.isNotEmpty) {
            qteController.selection = TextSelection(baseOffset: 0, extentOffset: qteController.text.length);
          }
        });
        return;
      }

      final qty = int.parse(qteController.text);

      // 3. ALERTE QUANTITÉ SUSPECTE (> 50)
      if (qty > 50) {
        final bool? confirm = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text("⚠️ Quantité élevée"),
            content: Text("Vous allez ajouter $qty unités.\nConfirmer ?"),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text("Corriger", style: TextStyle(color: Colors.red))
              ),
              ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text("Confirmer", style: TextStyle(color: Colors.white))
              ),
            ],
          ),
        );

        if (confirm != true) {
          // Si annulation, on re-sélectionne tout
          Future.delayed(const Duration(milliseconds: 50), () {
            if (mounted) {
              qteController.selection = TextSelection(baseOffset: 0, extentOffset: qteController.text.length);
            }
          });
          return;
        }
      }

      // Tout est bon
      Navigator.pop(context);

      // Vérification Stock et Ajout
      if (qty > 0) {
        if (qty > product.intNUMBERAVAILABLE) {
          _showForceStockDialog(product, qty);
        } else {
          _addProductToCart(product, qty: qty);
        }
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(product.strNAME, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            RichText(text: TextSpan(style: const TextStyle(fontSize: 11, color: Colors.grey), children: [
              const TextSpan(text: "CIP: "), TextSpan(text: "${product.intCIP} ", style: const TextStyle(color: Colors.black54)),
              const TextSpan(text: "| Stock: "), TextSpan(text: "${product.intNUMBERAVAILABLE} ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
              const TextSpan(text: "| Prix: "), TextSpan(text: "${_formatCurrency(product.intPRICE)} F", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
            ])),
          ],
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: qteController,
            autofocus: true,
            decoration: const InputDecoration(
                labelText: "Quantité",
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 10)
            ),
            keyboardType: TextInputType.number,
            validator: (val) {
              if (val == null || val.isEmpty) return "Requis";
              if (int.tryParse(val) == null) return "Invalide";
              if (int.parse(val) <= 0) return "Min 1";
              // BLOCAGE : Si plus de 4 chiffres, on considère que c'est un code barre scanné par erreur
              if (val.length > 4) return "Trop grand !";
              return null;
            },
            onFieldSubmitted: (_) => submit(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _searchController.clear();
                provider.clearSearchResults();
              },
              child: const Text("Annuler")
          ),
          ElevatedButton(onPressed: submit, child: const Text("Valider")),
        ],
      ),
    ).then((_) {
      if (mounted) {
        setState(() => _isPopupOpen = false);
        Future.delayed(const Duration(milliseconds: 350), () {
          if (mounted && !_isPopupOpen) _requestSearchFocus();
        });
      }
    });
  }

  // --- FORCE STOCK DIALOG ---
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

              // GESTION DU RETOUR ARRIÈRE (Nettoyage vente vide)
              if (provider.currentSaleId != null && provider.cartItems.isEmpty) {
                final bool? shouldDelete = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text("Vente vide"),
                    content: const Text("Cette vente est vide.\nVoulez-vous la supprimer ?"),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false), // Non
                        child: const Text("Non, garder", style: TextStyle(color: Colors.grey)),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: () => Navigator.pop(ctx, true), // Oui
                        child: const Text("Oui, Supprimer", style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                );

                if (shouldDelete == null) return;

                if (shouldDelete) {
                  await provider.deleteCurrentSale(); // Supprime via API
                } else {
                  provider.resetSale(); // Garde en base mais reset l'écran
                }

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
                  // ZONE 1 : SELECTION DEPOT
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

                  // ZONE 2 : RECHERCHE
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    color: Colors.white,
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        hintText: isScanMode ? "SCAN RAPIDE ACTIF" : "Saisir nom ou scanner",
                        prefixIcon: _isProcessing
                            ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2))
                            : Icon(isScanMode ? Icons.bolt : Icons.search, color: isScanMode ? Colors.green : null),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () { _searchController.clear(); _requestSearchFocus(); },
                        ),
                        border: const OutlineInputBorder(),
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
                        // --- CORRECTION ICI ---
                        // On ajoute 'isScan: false' car c'est une validation clavier (Entrée)
                        _performSearch(val, isScan: false);
                        _requestSearchFocus();
                      },
                    ),
                  ),

                  const Divider(height: 1),

                  // ZONE 3 : LISTE PRODUITS
                  Expanded(
                    child: provider.cartItems.isEmpty
                        ? (provider.isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : const Center(child: Text("Panier vide. Scannez ou saisissez un produit.")))
                        : Stack(
                      children: [
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
                                child: Text("${_formatCurrency(item.intPRICEUNITAIR)} F x ${item.intQUANTITY}"),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text("${_formatCurrency(item.intPRICE)} F", style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                                  const SizedBox(width: 8),
                                  IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _confirmDeleteItem(item)),
                                ],
                              ),
                              onTap: () => _editLine(item),
                            );
                          },
                        ),
                        if (provider.isLoading)
                          const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 2)),
                      ],
                    ),
                  ),

                  // ZONE 4 : FOOTER
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, -2))]),
                    child: SafeArea(
                      child: Row(
                        children: [
                          Expanded(flex: 4, child: ElevatedButton.icon(onPressed: provider.cartItems.isEmpty ? null : _validateSale, icon: const Icon(Icons.check_circle_outline), label: const Text("CLÔTURER"), style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 18)))),
                          const SizedBox(width: 15),
                          Expanded(flex: 6, child: Container(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15), decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)), child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [const Text("TOTAL NET", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)), FittedBox(fit: BoxFit.scaleDown, child: Text("${_formatCurrency(provider.totalAmount)} F", style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.black)))]))),
                        ],
                      ),
                    ),
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