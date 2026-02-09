// lib/screens/proforma/proforma_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/proforma_models.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/providers/proforma_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';

class ProformaScreen extends StatefulWidget {
  const ProformaScreen({Key? key}) : super(key: key);

  @override
  State<ProformaScreen> createState() => _ProformaScreenState();
}

class _ProformaScreenState extends State<ProformaScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _keyboardFocusNode = FocusNode();

  List<TypeDevis> _typesDevis = [];
  List<RemiseModel> _availableRemises = [];

  bool _isPopupOpen = false;
  bool _isProcessing = false;

  String _scanBuffer = "";
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _initData();
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestSearchFocus());
  }

  void _requestSearchFocus() {
    if (mounted && !_isPopupOpen && !_isProcessing) {
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

  Future<void> _initData() async {
    final api = Provider.of<ApiService>(context, listen: false);
    final types = await api.fetchTypeDevis();
    final remises = await api.fetchRemises();

    if (mounted) {
      setState(() {
        _typesDevis = types;
        _availableRemises = remises;
      });
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    final provider = Provider.of<ProformaProvider>(context, listen: false);
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

  Future<void> _showClientSearchDialog() async {
    final provider = Provider.of<ProformaProvider>(context, listen: false);
    if (provider.selectedTypeDevis == null) {
      _showError("Sélectionnez d'abord un Type de Devis");
      return;
    }

    setState(() => _isPopupOpen = true);
    ClientModel? selected = await showDialog<ClientModel>(
      context: context,
      builder: (ctx) => _ClientSearchDialog(),
    );
    setState(() => _isPopupOpen = false);

    if (selected != null) {
      provider.setClient(selected);
      _requestSearchFocus();
    }
  }

  void _onSearchChanged(String value) {
    final provider = Provider.of<ProformaProvider>(context, listen: false);
    if (provider.isQuickScanMode) return;

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (value.trim().isNotEmpty) _performSearch(value.trim(), isScan: false);
    });
  }

  Future<void> _performSearch(String query, {required bool isScan}) async {
    if (_isProcessing) return;
    if (query.isEmpty) return;

    final provider = Provider.of<ProformaProvider>(context, listen: false);
    if (provider.selectedClient == null) {
      _showError("Veuillez sélectionner un Client");
      _searchController.clear();
      return;
    }

    setState(() => _isProcessing = true);

    try {
      await provider.searchProducts(query);

      if (!mounted) return;
      final results = provider.searchResults;

      if (results.length == 1) {
        _searchController.clear();
        provider.clearSearchResults();
        await _checkStockAndAdd(results.first, autoAdd: provider.isQuickScanMode);
      } else if (results.isNotEmpty) {
        await _showSelectionDialog(results);
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
        if (!_isPopupOpen) _requestSearchFocus();
      }
    }
  }

  Future<void> _checkStockAndAdd(ProductSearchResult product, {bool autoAdd = false}) async {
    // Note: Proforma permet souvent de forcer le stock, mais on garde l'alerte
    if (product.intNUMBERAVAILABLE <= 0) {
      setState(() => _isPopupOpen = true);
      final bool? force = await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Stock Insuffisant", style: TextStyle(color: Colors.red)),
          content: Text("${product.strNAME} est en rupture.\nForcer ?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Non")),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Oui")),
          ],
        ),
      );
      setState(() => _isPopupOpen = false);
      if (force != true) {
        _searchController.clear();
        return;
      }
    }

    if (autoAdd) {
      await _addProduct(product, 1);
    } else {
      await _showQuantityDialog(product);
    }
  }

  Future<void> _addProduct(ProductSearchResult product, int qty) async {
    final provider = Provider.of<ProformaProvider>(context, listen: false);
    final success = await provider.addProduct(product, qty);
    if (mounted && success) {
      _searchController.clear();
      provider.clearSearchResults();
    }
  }

  // --- NOUVEAU : DIALOGUE QUANTITÉ SÉCURISÉ ---
  Future<void> _showQuantityDialog(ProductSearchResult product) async {
    setState(() => _isPopupOpen = true);
    final formKey = GlobalKey<FormState>();
    final qteController = TextEditingController(text: '1');

    // Auto-sélection
    qteController.selection = TextSelection(baseOffset: 0, extentOffset: qteController.text.length);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(product.strNAME, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 4),
            Text("Stock: ${product.intNUMBERAVAILABLE} | Prix: ${Constants.formatNumber(product.intPRICE)}",
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: qteController,
            autofocus: true,
            decoration: const InputDecoration(
                labelText: 'Quantité',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10)
            ),
            keyboardType: TextInputType.number,
            validator: (val) {
              if (val == null || val.isEmpty) return "Requis";
              if (int.tryParse(val) == null) return "Invalide";
              if (int.parse(val) <= 0) return "Min 1";
              // BLOCAGE ANTI-CODE BARRES
              if (val.length > 4) return "Trop grand !";
              return null;
            },
            onFieldSubmitted: (val) async {
              // LOGIQUE VALIDATION
              if (!formKey.currentState!.validate()) {
                // Re-sélection après délai pour contrer le scanner
                Future.delayed(const Duration(milliseconds: 50), () {
                  if (mounted && qteController.text.isNotEmpty) {
                    qteController.selection = TextSelection(baseOffset: 0, extentOffset: qteController.text.length);
                  }
                });
                return;
              }

              final qty = int.parse(val);

              // ALERTE QUANTITÉ SUSPECTE
              if (qty > 50) {
                final bool? confirm = await showDialog<bool>(
                  context: ctx,
                  builder: (alertCtx) => AlertDialog(
                    title: const Text("⚠️ Quantité élevée"),
                    content: Text("Ajouter $qty unités ?"),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(alertCtx, false), child: const Text("Corriger")),
                      ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(alertCtx, true), child: const Text("Confirmer"))
                    ],
                  ),
                );
                if (confirm != true) {
                  qteController.selection = TextSelection(baseOffset: 0, extentOffset: qteController.text.length);
                  return;
                }
              }

              Navigator.pop(ctx);
              _addProduct(product, qty);
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          ElevatedButton(onPressed: () async {
            if (!formKey.currentState!.validate()) return;
            final qty = int.parse(qteController.text);

            if (qty > 50) {
              final bool? confirm = await showDialog<bool>(
                context: ctx,
                builder: (alertCtx) => AlertDialog(
                  title: const Text("⚠️ Quantité élevée"),
                  content: Text("Ajouter $qty unités ?"),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(alertCtx, false), child: const Text("Corriger")),
                    ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(alertCtx, true), child: const Text("Confirmer"))
                  ],
                ),
              );
              if (confirm != true) {
                qteController.selection = TextSelection(baseOffset: 0, extentOffset: qteController.text.length);
                return;
              }
            }

            Navigator.pop(ctx);
            _addProduct(product, qty);
          }, child: const Text('Ajouter')),
        ],
      ),
    );

    if (mounted) setState(() => _isPopupOpen = false);
  }

  Future<void> _showSelectionDialog(List<ProductSearchResult> products) async {
    final provider = Provider.of<ProformaProvider>(context, listen: false);
    setState(() => _isPopupOpen = true);

    await showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text("Résultats (${products.length})"),
      content: SizedBox(width: double.maxFinite, height: 300, child: ListView.separated(
        itemCount: products.length, separatorBuilder: (_,__) => const Divider(),
        itemBuilder: (ctx, index) {
          final p = products[index];
          return ListTile(
            title: Text(p.strNAME), subtitle: Text("Stock: ${p.intNUMBERAVAILABLE} | ${Constants.formatNumber(p.intPRICE)} F"),
            onTap: () {
              provider.clearSearchResults();
              Navigator.pop(ctx);
              _checkStockAndAdd(p);
            },
          );
        },
      )),
    ));

    if(mounted) {
      setState(() => _isPopupOpen = false);
      _searchController.clear();
    }
  }

  void _showRemiseDialog() {
    if (_availableRemises.isEmpty) {
      _initData();
      return;
    }
    setState(() => _isPopupOpen = true);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Sélectionner une Remise"),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _availableRemises.length,
            separatorBuilder: (_,__) => const Divider(),
            itemBuilder: (ctx, index) {
              final r = _availableRemises[index];
              return ListTile(
                title: Text(r.strNAME, style: const TextStyle(fontWeight: FontWeight.bold)),
                trailing: Text("${r.dblTAUX}%", style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                onTap: () {
                  Navigator.pop(ctx);
                  Provider.of<ProformaProvider>(context, listen: false).applyRemise(r);
                },
              );
            },
          ),
        ),
      ),
    ).then((_) {
      setState(() => _isPopupOpen = false);
      _requestSearchFocus();
    });
  }

  void _showError(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: Colors.red));

  void _editLine(SaleLine item) {
    final qC = TextEditingController(text: item.intQUANTITY.toString());
    final pC = TextEditingController(text: item.intPRICEUNITAIR.toString());
    setState(() => _isPopupOpen = true);
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text(item.strNAME),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: qC, decoration: const InputDecoration(labelText: "Qté"), keyboardType: TextInputType.number, autofocus: true),
        TextField(controller: pC, decoration: const InputDecoration(labelText: "PU"), keyboardType: TextInputType.number),
      ]),
      actions: [
        TextButton(onPressed: () { Navigator.pop(ctx); Provider.of<ProformaProvider>(context, listen: false).removeItem(item.lgPREENREGISTREMENTDETAILID); }, child: const Text("Supprimer", style: TextStyle(color: Colors.red))),
        ElevatedButton(onPressed: () { Navigator.pop(ctx); Provider.of<ProformaProvider>(context, listen: false).updateItem(item, int.tryParse(qC.text)??1, int.tryParse(pC.text)??item.intPRICEUNITAIR); }, child: const Text("Valider")),
      ],
    )).then((_) {
      setState(() => _isPopupOpen = false);
      _requestSearchFocus();
    });
  }

  void _confirmDeleteItem(SaleLine item) {
    setState(() => _isPopupOpen = true);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Supprimer ?", style: TextStyle(color: Colors.red)),
        content: Text("Voulez-vous retirer ${item.strNAME} de la liste ?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Non")
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              Provider.of<ProformaProvider>(context, listen: false).removeItem(item.lgPREENREGISTREMENTDETAILID);
            },
            child: const Text("Oui"),
          ),
        ],
      ),
    ).then((_) {
      setState(() => _isPopupOpen = false);
      _requestSearchFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Consumer<ProformaProvider>(
        builder: (context, provider, child) {

          // --- NOUVEAU : GESTION RETOUR ARRIERE (Nettoyage proforma vide) ---
          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, result) async {
              if (didPop) return;

              // Si on a une proforma initialisée (ID existe) MAIS vide (0 produit)
              if (provider.currentSaleId != null && provider.cartItems.isEmpty) {
                final bool? confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text("Proforma vide"),
                    content: const Text("Cette proforma est vide.\nVoulez-vous la supprimer ?"),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Non, garder", style: TextStyle(color: Colors.grey))),
                      ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text("Oui, Supprimer", style: TextStyle(color: Colors.white))),
                    ],
                  ),
                );

                if (confirm == true) {
                  await provider.deleteCurrentProforma();
                } else if (confirm == false) {
                  provider.resetSale(); // On réinitialise juste l'écran
                }

                if (confirm != null && context.mounted) {
                  Navigator.pop(context);
                }
              } else {
                // Cas normal
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: Scaffold(
              appBar: AppBar(
                title: const Text("Nouvelle Proforma"),
                actions: [
                  IconButton(
                    icon: Icon(provider.isQuickScanMode ? Icons.bolt : Icons.settings,
                        color: provider.isQuickScanMode ? Colors.greenAccent : null),
                    onPressed: () => provider.toggleQuickScanMode(),
                  ),
                ],
              ),
              body: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10), color: Colors.white,
                    child: provider.currentSaleId == null
                        ? Row(
                      children: [
                        Expanded(flex: 4, child: DropdownButtonFormField<TypeDevis>(
                          value: provider.selectedTypeDevis,
                          decoration: const InputDecoration(labelText: "Type", border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10)),
                          items: _typesDevis.map((t) => DropdownMenuItem(value: t, child: Text(t.strNAME, style: const TextStyle(fontSize: 13)))).toList(),
                          onChanged: (val) {
                            provider.setTypeDevis(val);
                            if (val != null) Future.delayed(const Duration(milliseconds: 200), () => _showClientSearchDialog());
                          },
                        )),
                        const SizedBox(width: 10),
                        Expanded(flex: 6, child: InkWell(
                          onTap: _showClientSearchDialog,
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: "Client", border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10)),
                            child: Text(provider.selectedClient?.fullName ?? "Sélectionner...", style: TextStyle(color: provider.selectedClient == null ? Colors.grey : Colors.black, overflow: TextOverflow.ellipsis)),
                          ),
                        )),
                      ],
                    )
                        : Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.grey.shade100, border: Border.all(color: Colors.grey.shade300)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text("Client: ${provider.selectedClient?.fullName}", style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text("REF: ${provider.currentSaleRef ?? '...'}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey)),
                          ])),
                          Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.purple.shade100, borderRadius: BorderRadius.circular(20)),
                            child: Text("${provider.cartItems.length} Art.", style: TextStyle(color: Colors.purple.shade800, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  ),

                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), color: Colors.white,
                    child: TextField(
                      controller: _searchController, focusNode: _searchFocusNode, onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        hintText: provider.isQuickScanMode ? "SCAN RAPIDE ACTIF" : "Saisir nom ou scanner",
                        prefixIcon: provider.isQuickScanMode ? const Icon(Icons.bolt, color: Colors.green) : const Icon(Icons.search),
                        suffixIcon: IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchController.clear(); _requestSearchFocus(); }),
                        border: const OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: provider.isQuickScanMode ? Colors.green : Colors.grey, width: provider.isQuickScanMode ? 2.5 : 1.0),
                        ),
                        filled: true, fillColor: Colors.purple.shade50.withValues(alpha: 0.3),
                      ),
                      onSubmitted: (val) => _performSearch(val, isScan: true),
                    ),
                  ),
                  const Divider(height: 1),

                  Expanded(
                    child: Stack(
                      children: [
                        provider.cartItems.isEmpty
                            ? const Center(child: Text("Panier vide"))
                            : ListView.separated(
                          itemCount: provider.cartItems.length, separatorBuilder: (_,__) => const Divider(height: 1),
                          itemBuilder: (ctx, index) {
                            final item = provider.cartItems[index];
                            return ListTile(
                              dense: true,
                              title: Text(
                                item.strNAME,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text("${Constants.formatNumber(item.intPRICEUNITAIR)} x ${item.intQUANTITY}"),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text("${Constants.formatNumber(item.intPRICE)} F",
                                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.purple, fontSize: 14)),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                                    onPressed: () => _confirmDeleteItem(item),
                                    tooltip: "Supprimer",
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ],
                              ),
                              onTap: () => _editLine(item),
                            );
                          },
                        ),
                        if (!provider.isQuickScanMode && !_isPopupOpen && provider.searchResults.isNotEmpty)
                          Container(
                            color: Colors.white.withAlpha(245),
                            child: ListView.separated(
                              itemCount: provider.searchResults.length,
                              separatorBuilder: (_, __) => const Divider(),
                              itemBuilder: (ctx, i) {
                                final p = provider.searchResults[i];
                                return ListTile(
                                  title: Text(p.strNAME, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text("Stock: ${p.intNUMBERAVAILABLE} | ${Constants.formatNumber(p.intPRICE)} F"),
                                  onTap: () => _checkStockAndAdd(p),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),

                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, -2))]),
                    child: SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              TextButton.icon(
                                  onPressed: provider.cartItems.isEmpty ? null : _showRemiseDialog,
                                  icon: const Icon(Icons.local_offer),
                                  label: Text(provider.selectedRemise?.strNAME ?? "Ajouter Remise")
                              ),
                              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                if (provider.montantRemise > 0) Text("Remise: -${Constants.formatNumber(provider.montantRemise)}", style: const TextStyle(color: Colors.red, fontSize: 12)),
                                Text("${Constants.formatNumber(provider.netAPayer)} F", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.black)),
                              ])
                            ],
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: provider.cartItems.isEmpty ? null : () {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Proforma enregistrée"), backgroundColor: Colors.green));
                                provider.resetSale();
                                Navigator.pop(context);
                              },
                              icon: const Icon(Icons.save),
                              label: const Text("ENREGISTRER PROFORMA"),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.purple.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 15)),
                            ),
                          )
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

class _ClientSearchDialog extends StatefulWidget {
  @override
  __ClientSearchDialogState createState() => __ClientSearchDialogState();
}

class __ClientSearchDialogState extends State<_ClientSearchDialog> {
  final TextEditingController _ctrl = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (query.trim().isNotEmpty) _search(query.trim());
    });
  }

  void _search(String q) {
    Provider.of<ProformaProvider>(context, listen: false).searchClients(q);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ProformaProvider>(
      builder: (context, provider, child) {
        return AlertDialog(
          title: const Text("Rechercher Client"),
          content: SizedBox(
            width: double.maxFinite, height: 400,
            child: Column(children: [
              TextField(
                controller: _ctrl,
                decoration: const InputDecoration(hintText: "Nom, Prénom...", prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
                autofocus: true,
                onChanged: _onSearchChanged,
              ),
              const SizedBox(height: 10),
              Expanded(child: provider.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : provider.clientSearchResults.isEmpty
                  ? const Center(child: Text("Saisissez une recherche."))
                  : ListView.separated(
                itemCount: provider.clientSearchResults.length,
                separatorBuilder: (_,__) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final c = provider.clientSearchResults[i];
                  final bool isCarnet = c is ClientCarnetModel;

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isCarnet ? Colors.blue.shade100 : Colors.grey.shade200,
                      child: Icon(
                        isCarnet ? Icons.local_hospital : Icons.person,
                        color: isCarnet ? Colors.blue.shade800 : Colors.grey.shade600,
                      ),
                    ),
                    title: Text(
                      "${c.strFIRSTNAME} ${c.strLASTNAME}",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: c is ClientCarnetModel
                        ? Text("Matricule: ${c.strNUMEROSECURITESOCIAL ?? 'N/A'}", style: TextStyle(color: Colors.blue.shade700))
                        : const Text("Client Standard"),
                    onTap: () => Navigator.pop(context, c),
                  );
                },
              ))
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler"))],
        );
      },
    );
  }
}