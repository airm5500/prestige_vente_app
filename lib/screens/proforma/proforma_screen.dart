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
  bool _isLoadingInit = false;
  bool _isSearching = false;
  bool _isPopupOpen = false;
  String _scanBuffer = "";
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _initData();
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestSearchFocus());
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

  Future<void> _initData() async {
    setState(() => _isLoadingInit = true);
    final api = Provider.of<ApiService>(context, listen: false);
    final types = await api.fetchTypeDevis();
    final remises = await api.fetchRemises();

    if (mounted) {
      setState(() {
        _typesDevis = types;
        _availableRemises = remises;
        _isLoadingInit = false;
      });
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    final provider = Provider.of<ProformaProvider>(context, listen: false);
    if (!provider.isQuickScanMode) return;

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
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (value.trim().isNotEmpty) _performSearch(value.trim(), isScan: false);
    });
  }

  Future<void> _performSearch(String query, {required bool isScan}) async {
    final provider = Provider.of<ProformaProvider>(context, listen: false);
    if (provider.selectedClient == null) {
      _showError("Veuillez sélectionner un Client");
      return;
    }

    setState(() => _isSearching = true);
    await provider.searchProducts(query);

    if (!mounted) return;
    final results = provider.searchResults;

    if (results.length == 1) {
      // Nettoyage immédiat pour éviter la superposition en arrière-plan
      provider.clearSearchResults();
      _checkStockAndAdd(results.first, autoAdd: provider.isQuickScanMode);
    } else if (results.isNotEmpty) {
      _showSelectionDialog(results);
    }

    setState(() => _isSearching = false);
  }

  Future<void> _checkStockAndAdd(ProductSearchResult product, {bool autoAdd = false}) async {
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
        _searchController.clear(); _requestSearchFocus(); return;
      }
    }

    if (autoAdd) {
      _addProduct(product, 1);
    } else {
      _showQuantityDialog(product);
    }
  }

  Future<void> _addProduct(ProductSearchResult product, int qty) async {
    final provider = Provider.of<ProformaProvider>(context, listen: false);
    final success = await provider.addProduct(product, qty);
    if (mounted && success) {
      _searchController.clear();
      provider.clearSearchResults();
    }
    _requestSearchFocus();
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
          onSubmitted: (val) { Navigator.pop(ctx); _addProduct(product, int.tryParse(val) ?? 1); },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          ElevatedButton(onPressed: () { Navigator.pop(ctx); _addProduct(product, int.tryParse(qteController.text) ?? 1); }, child: const Text('Ajouter')),
        ],
      ),
    ).then((_) {
      setState(() => _isPopupOpen = false);
      _requestSearchFocus();
    });
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

  void _showSelectionDialog(List<ProductSearchResult> products) {
    final provider = Provider.of<ProformaProvider>(context, listen: false);
    setState(() => _isPopupOpen = true);
    showDialog(context: context, builder: (ctx) => AlertDialog(
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
    )).then((_) {
      setState(() => _isPopupOpen = false);
      _searchController.clear();
      _requestSearchFocus();
    });
  }

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

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Consumer<ProformaProvider>(
        builder: (context, provider, child) {
          return Scaffold(
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
                      filled: true, fillColor: Colors.purple.shade50.withOpacity(0.3),
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
                          return ListTile(dense: true, title: Text(item.strNAME, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text("${Constants.formatNumber(item.intPRICEUNITAIR)} x ${item.intQUANTITY}"),
                            trailing: Text("${Constants.formatNumber(item.intPRICE)} F", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)),
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
                  // Vérification du type de client pour adapter l'affichage
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
                    subtitle: isCarnet
                        ? Text("Matricule: ${(c as ClientCarnetModel).strNUMEROSECURITESOCIAL ?? 'N/A'}", style: TextStyle(color: Colors.blue.shade700))
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