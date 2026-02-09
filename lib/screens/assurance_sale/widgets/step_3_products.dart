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

// AJOUT DE L'IMPORT NÉCESSAIRE
import 'package:prestige_vente_app/providers/sale_provider.dart';

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

  bool _isProcessing = false;
  String _scanBuffer = "";
  bool _isPopupOpen = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);

    // CORRECTION : PRÉ-CHARGEMENT DES QR CODES
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestSearchFocus();

      // On lance le chargement silencieux des QR Codes ici.
      // Comme ça, quand l'utilisateur cliquera sur "Vente" en bas, les images seront déjà prêtes.
      // (Cela utilise le cache du SaleProvider, donc si déjà chargé en vente comptant, c'est instantané)
      Provider.of<SaleProvider>(context, listen: false).fetchPaymentMethodsWithQr();
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
          _performSearch(_scanBuffer.trim(), isScan: true);
          _scanBuffer = "";
        }
      } else if (event.character != null) {
        _scanBuffer += event.character!;
      }
    }
  }

  void _onSearchChanged() {
    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);

    // 1. PROTECTION CRITIQUE : Si champ vide, on arrête tout (Casse la boucle tablette)
    if (_searchController.text.isEmpty) {
      provider.clearProductSearch();
      return;
    }

    // 2. Si un popup est ouvert, on ne cherche pas
    if (_isPopupOpen) return;

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      // Double sécurité
      if (_isPopupOpen) return;

      final text = _searchController.text.trim();
      if (text.isNotEmpty) {
        _performSearch(text, isScan: false);
      } else {
        provider.clearProductSearch();
      }
    });
  }

  Future<void> _performSearch(String query, {required bool isScan}) async {
    _debounce?.cancel();
    if (_isPopupOpen) return;
    if (query.isEmpty) return;

    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);

    // On indique visuellement qu'on cherche (optionnel si vous avez un loader)
    // setState(() => _isProcessing = true);

    try {
      await provider.searchProducts(query);
      if (!mounted) return;
      if (_isPopupOpen) return; // Si un popup s'est ouvert entre temps

      final results = provider.productSearchResults;

      if (results.length == 1) {
        final product = results.first;
        // On vide le champ pour éviter les conflits
        _searchController.clear();
        provider.clearProductSearch();

        // LOGIQUE SCAN RAPIDE (Bouton éclair)
        if (provider.isQuickScanMode) {
          // --- CORRECTION : VÉRIFICATION STOCK MÊME EN RAPIDE ---
          if (product.intNUMBERAVAILABLE < 1) {
            _showForceStockDialog(product, 1);
          } else {
            provider.addProductToCart(product, 1);
          }
        } else {
          // Mode manuel -> Popup quantité
          _showQuantityDialog(product);
        }
      } else if (results.isNotEmpty) {
        _showSelectionDialog(results);
      }
    } finally {
      if (mounted) {
        // setState(() => _isProcessing = false);
        if (!_isPopupOpen) _requestSearchFocus();
      }
    }
  }

// DANS lib/screens/assurance_sale/widgets/step_3_products.dart

  // 1. POPUP RESULTATS RECHERCHE (Style optimisé)
  void _showSelectionDialog(List<ProductSearchResult> results) {
    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);
    final dialogResults = List<ProductSearchResult>.from(results);
    provider.clearProductSearch(); // Nettoyage arrière-plan

    setState(() => _isPopupOpen = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text("Résultats (${dialogResults.length})", style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.separated(
            itemCount: dialogResults.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final p = dialogResults[index];
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(p.strNAME, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: RichText(text: TextSpan(style: const TextStyle(fontSize: 11, color: Colors.grey), children: [
                  const TextSpan(text: "CIP: "), TextSpan(text: "${p.intCIP} ", style: const TextStyle(color: Colors.black54)),
                  const TextSpan(text: "| Stock: "), TextSpan(text: "${p.intNUMBERAVAILABLE} ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                  const TextSpan(text: "| Prix: "), TextSpan(text: "${Constants.formatNumber(p.intPRICE)} F", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                ])),
                onTap: () {
                  // Vider et fermer proprement
                  _searchController.clear();
                  Navigator.pop(ctx);
                  _showQuantityDialog(p);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () {
                // --- PROTECTION BOUCLE ---
                _searchController.clear();
                Navigator.pop(ctx);
              },
              child: const Text("Fermer")
          )
        ],
      ),
    ).then((_) {
      if (mounted) {
        setState(() => _isPopupOpen = false);
        // --- DELAI FOCUS (Tablette) ---
        Future.delayed(const Duration(milliseconds: 350), () {
          if (mounted && !_isPopupOpen) _requestSearchFocus();
        });
      }
    });
  }

  // 2. POPUP QUANTITÉ (Sécurisé + Auto-Select + Style)
  void _showQuantityDialog(ProductSearchResult product) {
    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);
    final formKey = GlobalKey<FormState>();
    final qteController = TextEditingController(text: "1");

    // 1. AMÉLIORATION : Auto-sélection à l'ouverture (Saisie directe)
    qteController.selection = TextSelection(baseOffset: 0, extentOffset: qteController.text.length);

    // Variable pour gérer l'ouverture du dialog sans bloquer l'UI
    setState(() => _isPopupOpen = true);


    void submit() async {
      // 1. SÉCURITÉ : Si Code barre scanné (Erreur Validateur)
      if (!formKey.currentState!.validate()) {
        // CORRECTION : On utilise un petit délai pour forcer la sélection
        // APRES que l'interface a fini d'afficher l'erreur rouge.
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted && qteController.text.isNotEmpty) {
            qteController.selection = TextSelection(
                baseOffset: 0,
                extentOffset: qteController.text.length
            );
          }
        });
        return;
      }

      final qty = int.parse(qteController.text);

      // 2. SÉCURITÉ : Alerte Quantité Suspecte (> 50)
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
          // CORRECTION ICI AUSSI : Délai pour garantir la sélection au retour du dialog
          Future.delayed(const Duration(milliseconds: 50), () {
            if (mounted) {
              qteController.selection = TextSelection(
                  baseOffset: 0,
                  extentOffset: qteController.text.length
              );
            }
          });
          return;
        }
      }

      // Tout est bon
      Navigator.pop(context);

      if (qty > 0) {
        if (qty > product.intNUMBERAVAILABLE) {
          _showForceStockDialog(product, qty);
        } else {
          provider.addProductToCart(product, qty);
          _searchController.clear();
          provider.clearProductSearch();
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
              const TextSpan(text: "| Prix: "), TextSpan(text: "${Constants.formatNumber(product.intPRICE)} F", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
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
              // Blocage anti code-barres (ex: CIP > 4 ou 5 chiffres)
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
                provider.clearProductSearch();
              },
              child: const Text("Annuler")
          ),
          ElevatedButton(onPressed: submit, child: const Text("Valider")),
        ],
      ),
    ).then((_) {
      if (mounted) {
        setState(() => _isPopupOpen = false);
        // Petit délai pour éviter le bug du clavier sur tablette
        Future.delayed(const Duration(milliseconds: 350), () {
          if (mounted && !_isPopupOpen) _requestSearchFocus();
        });
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

  Widget _buildSearchRow(AssuranceSaleProvider provider, bool isActive) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
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
                _performSearch(val, isScan: false);
                _requestSearchFocus();
              },
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