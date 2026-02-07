// lib/screens/pre_vente/tabs/vente_tab.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/api/models/user.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/screens/pre_vente/widgets/sale_cart_widget.dart';
import 'package:prestige_vente_app/services/receipt_service.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/api/models/payment_method_qr.dart';
import 'package:prestige_vente_app/widgets/cash_payment_dialog.dart';

class VenteTab extends StatefulWidget {
  final bool isPrevente;
  const VenteTab({super.key, required this.isPrevente});

  @override
  State<VenteTab> createState() => _VenteTabState();
}

class _VenteTabState extends State<VenteTab> {
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
    _searchController.addListener(_onSearchChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestSearchFocus();
      // Pré-chargement des QR Codes
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
    final sale = Provider.of<SaleProvider>(context, listen: false);
    if (!sale.isQuickScanMode) return;

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
    final sale = Provider.of<SaleProvider>(context, listen: false);
    // En mode scan rapide, pas de recherche auto
    if (sale.isQuickScanMode) return;

    // Si on est déjà en train de traiter ou qu'un popup est ouvert, on ne lance pas de timer
    if (_isPopupOpen || _isProcessing) return;

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      // Double sécurité au moment de l'exécution du timer
      if (_isPopupOpen || _isProcessing) return;

      if (_searchController.text.trim().isNotEmpty) {
        _performSearch(_searchController.text.trim(), isScan: false);
      } else {
        sale.clearSearchResults();
      }
    });
  }

  Future<void> _performSearch(String query, {required bool isScan}) async {
    // 1. CORRECTION MAJEURE : On tue tout timer en attente immédiatement
    _debounce?.cancel();

    // 2. Si une recherche est déjà en cours, on ne fait rien
    if (_isProcessing) return;

    // 3. Si un popup est déjà ouvert (résultats ou quantité), on BLOQUE toute nouvelle recherche
    if (_isPopupOpen) return;

    if (query.isEmpty) return;

    final provider = Provider.of<SaleProvider>(context, listen: false);
    setState(() => _isProcessing = true);

    try {
      await provider.searchProducts(query);

      if (!mounted) return;

      // Si entre temps un popup s'est ouvert (peu probable avec le await mais possible), on arrête
      if (_isPopupOpen) return;

      final results = provider.searchResults;

      if (results.length == 1) {
        final product = results.first;
        _searchController.clear();
        provider.clearSearchResults();

        if (provider.isQuickScanMode) {
          await provider.addProductToCart(product, 1, isPrevente: widget.isPrevente);
        } else {
          // Mode manuel : On ouvre le popup quantité
          _showQuantityDialog(product);
        }
      } else if (results.isNotEmpty) {
        // Plusieurs résultats : On ouvre le popup de sélection
        _showSelectionDialog(results);
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
        // On ne redonne le focus que si aucun popup n'est resté ouvert
        if (!_isPopupOpen) _requestSearchFocus();
      }
    }
  }

  void _showSelectionDialog(List<ProductSearchResult> products) {
    final provider = Provider.of<SaleProvider>(context, listen: false);
    setState(() => _isPopupOpen = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text("Résultats (${products.length})"),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: products.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (ctx, index) {
              final p = products[index];
              return ListTile(
                title: Text(p.strNAME, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("CIP: ${p.intCIP} | Stock: ${p.intNUMBERAVAILABLE} | Prix: ${Constants.formatNumber(p.intPRICE)} F"),
                onTap: () {
                  provider.clearSearchResults();
                  Navigator.of(ctx).pop();
                  // Enchaînement vers le popup quantité
                  _showQuantityDialog(p);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () {
                provider.clearSearchResults();
                Navigator.of(ctx).pop();
              },
              child: const Text("Fermer")
          )
        ],
      ),
    ).then((_) {
      if (mounted) {
        // Important : on marque le popup comme fermé AVANT de redonner le focus
        setState(() => _isPopupOpen = false);
        _requestSearchFocus();
      }
    });
  }

  void _showQuantityDialog(ProductSearchResult product) {
    final qteController = TextEditingController(text: '1');
    qteController.selection = TextSelection(baseOffset: 0, extentOffset: qteController.text.length);

    setState(() => _isPopupOpen = true);

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
          onSubmitted: (val) {
            final q = int.tryParse(val) ?? 1;
            Navigator.of(ctx).pop();
            _executeAdd(product, q);
          },
        ),
        actions: [
          TextButton(onPressed: () {
            Provider.of<SaleProvider>(context, listen: false).clearSearchResults();
            Navigator.of(ctx).pop();
          }, child: const Text('Annuler')),
          ElevatedButton(onPressed: () {
            final q = int.tryParse(qteController.text) ?? 1;
            Navigator.of(ctx).pop();
            _executeAdd(product, q);
          }, child: const Text('Ajouter')),
        ],
      ),
    ).then((_) {
      if (mounted) {
        setState(() => _isPopupOpen = false);
        _requestSearchFocus();
      }
    });
  }

  void _executeAdd(ProductSearchResult product, int qty) async {
    final provider = Provider.of<SaleProvider>(context, listen: false);

    // Nettoyage immédiat pour éviter les effets de bord
    provider.clearSearchResults();
    _searchController.clear();

    // Appel API
    await provider.addProductToCart(product, qty, isPrevente: widget.isPrevente);

    if (!_isProcessing && mounted) {
      _requestSearchFocus();
    }
  }

  Future<void> _showPrintDialog({
    required bool isPrevente, PaymentMethod? paymentMethod, required User currentUser,
    int? montantVerse, int? monnaie,
  }) async {
    final BuildContext mainContext = context;
    final settingsProvider = Provider.of<SettingsProvider>(mainContext, listen: false);
    final saleProvider = Provider.of<SaleProvider>(mainContext, listen: false);
    final authProvider = Provider.of<AuthProvider>(mainContext, listen: false);
    final receiptService = ReceiptService();

    final bool? printFirstTicket = await showDialog<bool>(
      context: mainContext, barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(isPrevente ? 'Prévente terminée' : 'Vente terminée'),
        content: const Text('Voulez-vous imprimer le ticket ?'),
        actions: [
          TextButton(child: const Text('Non'), onPressed: () => Navigator.of(ctx).pop(false)),
          ElevatedButton(child: const Text('Oui'), onPressed: () => Navigator.of(ctx).pop(true)),
        ],
      ),
    );

    if (printFirstTicket == true) {
      if (isPrevente) {
        await receiptService.printPreventeTicket(
          context: mainContext, officine: authProvider.officine!,
          saleSummary: saleProvider.saleSummary, currentUser: currentUser,
          isTestMode: settingsProvider.isTestPrintMode, paperWidth: settingsProvider.paperWidth, ticketCodeType: settingsProvider.ticketCodeType,
        );
      } else {
        await receiptService.printSaleTicket(
          context: mainContext, officine: authProvider.officine!,
          saleSummary: saleProvider.saleSummary, items: saleProvider.cartItems,
          paymentMethod: paymentMethod!, currentUser: currentUser,
          isTestMode: settingsProvider.isTestPrintMode, paperWidth: settingsProvider.paperWidth,
          showQrCode: settingsProvider.showQrCodeOnSaleTicket, ticketCodeType: settingsProvider.ticketCodeType,
          montantVerse: montantVerse, monnaie: monnaie,
        );
      }
    }
    saleProvider.startNewSale();
    _requestSearchFocus();
  }

  Future<void> _showPaymentConfirmationDialog({
    required PaymentMethod method,
    required User currentUser,
    PaymentMethodQr? qrMethod,
    int? montantRecu,
    int? montantRemis,
  }) async {
    final saleProvider = Provider.of<SaleProvider>(context, listen: false);
    setState(() => _isPopupOpen = true);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirmation de Paiement"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Mode : ${method.name}", style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text("Montant Net : ${Constants.formatNumber(saleProvider.saleSummary.montantNet)} F",
                  style: const TextStyle(fontSize: 18, color: Colors.blue, fontWeight: FontWeight.bold)),
              const Divider(height: 30),
              if (qrMethod != null && qrMethod.qrCode != null) ...[
                const Text("Scanner pour payer :"),
                const SizedBox(height: 10),
                SizedBox(
                  width: 180,
                  height: 180,
                  child: Image.memory(qrMethod.qrCode!, fit: BoxFit.contain),
                ),
              ] else
                const Text("Veuillez confirmer l'encaissement."),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        actions: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(ctx).pop(),
                  icon: const Icon(Icons.arrow_back, color: Colors.white, size: 18),
                  label: const Text("RETOUR", style: TextStyle(color: Colors.white, fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.of(ctx).pop();

                    final apiResult = await saleProvider.cloturerVente(
                        method,
                        currentUser,
                        montantRecu: montantRecu,
                        montantRemis: montantRemis
                    );

                    if (!mounted) return;
                    if (await Constants.checkAndOpenCaisse(context, apiResult)) return;

                    if (apiResult['success'] == true) {
                      _showPrintDialog(
                          isPrevente: false,
                          paymentMethod: method,
                          currentUser: currentUser,
                          montantVerse: montantRecu,
                          monnaie: montantRemis
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(saleProvider.errorMessage ?? "La validation a échoué"),
                        backgroundColor: Colors.red,
                      ));
                    }
                  },
                  icon: const Icon(Icons.check_circle, color: Colors.white, size: 18),
                  label: const Text("VALIDER", style: TextStyle(color: Colors.white, fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ).then((_) {
      if (mounted) {
        setState(() => _isPopupOpen = false);
        _requestSearchFocus();
      }
    });
  }

  Future<void> _showCashPaymentDialog(PaymentMethod method, User currentUser) async {
    final saleProvider = Provider.of<SaleProvider>(context, listen: false);
    final result = await showDialog<Map<String, int>>(
        context: context,
        builder: (ctx) => CashPaymentDialog(montantNet: saleProvider.saleSummary.montantNet)
    );

    if (result != null) {
      _showPaymentConfirmationDialog(
          method: method,
          currentUser: currentUser,
          montantRecu: result['verse'],
          montantRemis: result['monnaie']
      );
    }
  }

  void _showPaymentDialog() async {
    final saleProvider = Provider.of<SaleProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    final currentUser = authProvider.user;
    if (currentUser == null) return;

    final allMethods = await saleProvider.apiService.getPaymentMethods();
    final allowedIds = settingsProvider.enabledPaymentMethodIds;
    final filteredMethods = allMethods.where((m) => allowedIds.contains(m.id)).toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mode de règlement'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: filteredMethods.length,
            itemBuilder: (context, index) {
              final method = filteredMethods[index];
              return ListTile(
                  title: Text(method.name),
                  onTap: () async {
                    Navigator.of(ctx).pop();

                    if (method.id == '1') {
                      _showCashPaymentDialog(method, currentUser);
                    } else {
                      final paymentQrMethods = saleProvider.paymentMethodsWithQr;
                      PaymentMethodQr? qrM;
                      try { qrM = paymentQrMethods.firstWhere((m) => m.id == method.id); } catch (e) { qrM = null; }

                      _showPaymentConfirmationDialog(
                          method: method,
                          currentUser: currentUser,
                          qrMethod: qrM
                      );
                    }
                  }
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isTabletLandscape = MediaQuery.of(context).size.width > 800;
    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: isTabletLandscape ? _buildTabletLayout() : _buildMobileLayout(),
    );
  }

  Widget _buildMobileLayout() {
    return Column(children: [ _buildSearchArea(), const Divider(height: 1), Expanded(child: _buildCartAndResultsOverlay()), _buildSummaryFooter() ]);
  }

  Widget _buildTabletLayout() {
    return Row(children: [
      Expanded(flex: 4, child: Column(children: [_buildSearchArea(), const Divider(height: 1), Expanded(child: _buildCartAndResultsOverlay()), _buildSummaryFooter()])),
      const VerticalDivider(width: 1),
      const Expanded(flex: 6, child: SaleCartWidget()),
    ]);
  }

  Widget _buildSearchArea() {
    return Consumer<SaleProvider>(builder: (context, sale, child) {
      final bool isActive = sale.isQuickScanMode;
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: isActive ? 'SCAN RAPIDE ACTIF' : 'Rechercher (Nom/CIP)',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  prefixIcon: _isProcessing
                      ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(isActive ? Icons.bolt : Icons.search, color: isActive ? Colors.green : null),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () { _searchController.clear(); _requestSearchFocus(); },
                  ),
                  border: const OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: isActive ? Colors.green : Colors.grey, width: isActive ? 2.5 : 1.0),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: isActive ? Colors.green : Theme.of(context).primaryColor, width: isActive ? 2.5 : 2.0),
                  ),
                  filled: true,
                  fillColor: isActive ? Colors.green.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.05),
                ),
                onSubmitted: (val) => _performSearch(val, isScan: true),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: () {
                sale.toggleQuickScanMode();
                _requestSearchFocus();
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isActive ? Colors.green : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isActive ? Colors.green.shade700 : Colors.grey,
                  ),
                ),
                child: Icon(
                  isActive ? Icons.flash_on : Icons.flash_off,
                  color: isActive ? Colors.white : Colors.grey.shade700,
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildCartAndResultsOverlay() {
    return Consumer<SaleProvider>(builder: (context, saleProvider, child) {
      final bool isTablet = MediaQuery.of(context).size.width > 800;
      return Stack(children: [
        if (!isTablet) const SaleCartWidget(),
        if (!saleProvider.isQuickScanMode && !_isPopupOpen && saleProvider.searchResults.isNotEmpty)
          Container(
            color: Theme.of(context).scaffoldBackgroundColor.withAlpha(242),
            child: ListView.separated(
              itemCount: saleProvider.searchResults.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final product = saleProvider.searchResults[index];
                return ListTile(
                  title: Text(product.strNAME, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("CIP: ${product.intCIP} | Stock: ${product.intNUMBERAVAILABLE} | Prix: ${Constants.formatNumber(product.intPRICE)}"),
                  onTap: () => _showQuantityDialog(product),
                );
              },
            ),
          ),
      ]);
    });
  }

  // lib/screens/pre_vente/tabs/vente_tab.dart

// ... (Imports inchangés)

// ... (Début du fichier inchangé)

  Widget _buildSummaryFooter() {
    return Consumer<SaleProvider>(builder: (context, saleProvider, child) {
      final summary = saleProvider.saleSummary;
      return Card(
        elevation: 4, margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Total: ${Constants.formatNumber(summary.montant)}'),
              Text('Net: ${Constants.formatNumber(summary.montantNet)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.primary)),
            ]),

            // --- MODIFICATION ICI ---
            saleProvider.isLoading ? const CircularProgressIndicator() : ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: widget.isPrevente ? Colors.orange : AppColors.success, shape: const CircleBorder(), padding: const EdgeInsets.all(15)),
              child: Icon(widget.isPrevente ? Icons.save : Icons.check_circle, color: Colors.white),

              // Logique du bouton modifiée
              onPressed: saleProvider.cartItems.isEmpty ? null : () async { // Ajout de async

                if (widget.isPrevente) {
                  // CORRECTION : APPEL API OBLIGATOIRE POUR CHANGER LE STATUT EN "is_Process"
                  // Sans cet appel, la vente reste "Pending" en base de données.
                  final bool success = await saleProvider.terminerPrevente();

                  if (success) {
                    if (!mounted) return;
                    _showPrintDialog(isPrevente: true, currentUser: Provider.of<AuthProvider>(context, listen: false).user!);
                  } else {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text("Erreur lors de l'enregistrement de la prévente"),
                      backgroundColor: Colors.red,
                    ));
                  }
                } else {
                  // Cas Vente Directe (inchangé)
                  _showPaymentDialog();
                }
              },
            ),
          ]),
        ),
      );
    });
  }
}
