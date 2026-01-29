// lib/screens/proforma/proforma_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
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
  // Controleurs
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // Data locale pour sélection
  List<TypeDevis> _typesDevis = [];
  List<RemiseModel> _availableRemises = [];
  bool _isLoadingInit = false;
  bool _isSearching = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
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

  // --- SELECTION CLIENT (Dialog) ---
  Future<void> _showClientSearchDialog() async {
    final provider = Provider.of<ProformaProvider>(context, listen: false);
    if (provider.selectedTypeDevis == null) {
      _showError("Sélectionnez d'abord un Type de Devis");
      return;
    }

    ClientModel? selected = await showDialog<ClientModel>(
      context: context,
      builder: (ctx) => _ClientSearchDialog(),
    );

    if (selected != null) {
      provider.setClient(selected);
      // Focus recherche produit
      Future.delayed(const Duration(milliseconds: 100), () => _searchFocusNode.requestFocus());
    }
  }

  // --- RECHERCHE PRODUIT ---
  void _onSearchChanged(String value) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (value.trim().isNotEmpty) _performSearch(value.trim());
    });
  }

  Future<void> _performSearch(String query) async {
    final provider = Provider.of<ProformaProvider>(context, listen: false);
    if (provider.selectedClient == null) {
      _showError("Veuillez sélectionner un Client");
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
      _showError("Erreur: $e");
    } finally {
      if(mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _checkStockAndAdd(ProductSearchResult product) async {
    if (product.intNUMBERAVAILABLE <= 0) {
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
      if (force != true) {
        _searchController.clear(); _searchFocusNode.requestFocus(); return;
      }
    }
    _addProduct(product);
  }

  Future<void> _addProduct(ProductSearchResult product) async {
    final provider = Provider.of<ProformaProvider>(context, listen: false);
    final success = await provider.addProduct(product, 1);
    if (mounted && success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${product.strNAME} ajouté"), duration: const Duration(milliseconds: 500), backgroundColor: Colors.green));
      _searchController.clear();
    }
    _searchFocusNode.requestFocus();
  }

  // Dans lib/screens/proforma/proforma_screen.dart

  void _showRemiseDialog() {
    if (_availableRemises.isEmpty) {
      // Si ça s'affiche, c'est que le parsing a échoué ou que l'API renvoie vide
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Aucune remise disponible chargée."), backgroundColor: Colors.orange)
      );
      // On tente de recharger pour la prochaine fois
      _initData();
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Sélectionner une Remise"),
        content: SizedBox(
          width: double.maxFinite,
          // Utilisation de shrinkWrap pour éviter les erreurs de taille
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _availableRemises.length,
            separatorBuilder: (_,__) => const Divider(),
            itemBuilder: (ctx, index) {
              final r = _availableRemises[index];
              return ListTile(
                title: Text(r.strNAME, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("Code: ${r.strCODE}"),
                trailing: Text("${r.dblTAUX}%", style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                onTap: () {
                  Navigator.pop(ctx);
                  // Appel de la méthode qui fait le POST vers /vente/remise
                  Provider.of<ProformaProvider>(context, listen: false).applyRemise(r);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler"))
        ],
      ),
    );
  }

  // --- UI HELPERS ---
  String _formatCurrency(int amount) => amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]} ');
  void _showError(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: Colors.red));

  // Dialog selection produit (copie de Depot)
  void _showSelectionDialog(List<ProductSearchResult> products) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text("Résultats (${products.length})"),
      content: SizedBox(width: double.maxFinite, height: 300, child: ListView.separated(
        itemCount: products.length, separatorBuilder: (_,__) => const Divider(),
        itemBuilder: (ctx, index) {
          final p = products[index];
          return ListTile(
            title: Text(p.strNAME), subtitle: Text("Stock: ${p.intNUMBERAVAILABLE} | ${_formatCurrency(p.intPRICE)} F"),
            onTap: () { Navigator.pop(ctx); _checkStockAndAdd(p); },
          );
        },
      )),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Fermer"))],
    )).then((_) { _searchController.clear(); _searchFocusNode.requestFocus(); });
  }

  // Modification Ligne (copie de Depot)
  void _editLine(SaleLine item) {
    final qC = TextEditingController(text: item.intQUANTITY.toString());
    final pC = TextEditingController(text: item.intPRICEUNITAIR.toString());
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
    )).then((_) => _searchFocusNode.requestFocus());
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ProformaProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          appBar: AppBar(title: const Text("Nouvelle Proforma")),
          body: Column(
            children: [
              // ZONE 1 : SELECTION
              Container(
                padding: const EdgeInsets.all(10), color: Colors.white,
                child: provider.currentSaleId == null
                    ? Row(
                  children: [
                    // Choix Type
                    Expanded(flex: 4, child: DropdownButtonFormField<TypeDevis>(
                      value: provider.selectedTypeDevis,
                      decoration: const InputDecoration(labelText: "Type", border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10)),
                      items: _typesDevis.map((t) => DropdownMenuItem(value: t, child: Text(t.strNAME, style: const TextStyle(fontSize: 13)))).toList(),
                      onChanged: (val) {
                        provider.setTypeDevis(val);
                        // CORRECTION 1 : Ouverture auto du dialogue client après un court instant
                        if (val != null) {
                          Future.delayed(const Duration(milliseconds: 200), () {
                            _showClientSearchDialog();
                          });
                        }
                      },
                    )),
                    const SizedBox(width: 10),
                    // Choix Client (Bouton qui ouvre dialog)
                    Expanded(flex: 6, child: InkWell(
                      onTap: _showClientSearchDialog,
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: "Client", border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10)),
                        child: Text(provider.selectedClient?.fullName ?? "Sélectionner...", style: TextStyle(color: provider.selectedClient == null ? Colors.grey : Colors.black, overflow: TextOverflow.ellipsis)),
                      ),
                    )),
                  ],
                )
                    : Container( // Mode Lecture Seule (Vente créée)
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

              // ZONE 2 : RECHERCHE
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), color: Colors.white,
                child: TextField(
                  controller: _searchController, focusNode: _searchFocusNode, onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    hintText: "Saisir nom ou scanner",
                    prefixIcon: _isSearching ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.search),
                    suffixIcon: IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchController.clear(); _searchFocusNode.requestFocus(); }),
                    border: const OutlineInputBorder(), filled: true, fillColor: Colors.purple.shade50.withOpacity(0.3),
                  ),
                ),
              ),
              const Divider(height: 1),

              // ZONE 3 : PANIER
              Expanded(
                child: provider.isLoading && !_isSearching ? const Center(child: CircularProgressIndicator()) : provider.cartItems.isEmpty ? const Center(child: Text("Panier vide"))
                    : ListView.separated(
                  itemCount: provider.cartItems.length, separatorBuilder: (_,__) => const Divider(height: 1),
                  itemBuilder: (ctx, index) {
                    final item = provider.cartItems[index];
                    return ListTile(dense: true, title: Text(item.strNAME, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text("${_formatCurrency(item.intPRICEUNITAIR)} x ${item.intQUANTITY}"),
                      trailing: Text("${_formatCurrency(item.intPRICE)} F", style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                      onTap: () => _editLine(item),
                    );
                  },
                ),
              ),

              // ZONE 4 : FOOTER (Remise + Total + Save)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, -2))]),
                child: SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Ligne Remise & Total
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton.icon(
                              onPressed: provider.cartItems.isEmpty ? null : _showRemiseDialog,
                              icon: const Icon(Icons.local_offer),
                              label: Text(provider.selectedRemise?.strNAME ?? "Ajouter Remise")
                          ),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            if (provider.montantRemise > 0) Text("Remise: -${_formatCurrency(provider.montantRemise)}", style: const TextStyle(color: Colors.red, fontSize: 12)),
                            Text("${_formatCurrency(provider.netAPayer)} F", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.black)),
                          ])
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Bouton Valider (Ici c'est juste "Enregistrer" pour vider l'écran car c'est une proforma)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: provider.cartItems.isEmpty ? null : () {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Proforma enregistrée"), backgroundColor: Colors.green));
                            Navigator.pop(context); // Retour liste
                          },
                          icon: const Icon(Icons.save),
                          label: const Text("ENREGISTRER PROFORMA"),
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 15)),
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

// Widget Dialog Recherche Client Dynamique
class _ClientSearchDialog extends StatefulWidget {
  @override
  __ClientSearchDialogState createState() => __ClientSearchDialogState();
}

class __ClientSearchDialogState extends State<_ClientSearchDialog> {
  final TextEditingController _ctrl = TextEditingController();
  List<ClientModel> _results = [];
  bool _loading = false;
  Timer? _debounce; // Pour la recherche dynamique

  @override
  void dispose() {
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // CORRECTION 2 : Recherche lancée à la frappe (dynamique)
  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    // On attend 500ms après la dernière lettre tapée
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (query.trim().isNotEmpty) {
        _search(query.trim());
      }
    });
  }

  void _search(String q) async {
    setState(() => _loading = true);
    final res = await Provider.of<ApiService>(context, listen: false).searchClients(q);
    if(mounted) setState(() { _results = res; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Rechercher Client"),
      content: SizedBox(
        width: double.maxFinite, height: 400,
        child: Column(children: [
          TextField(
            controller: _ctrl,
            decoration: InputDecoration(
                hintText: "Nom, Prénom...",
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(icon: const Icon(Icons.clear), onPressed: () => _ctrl.clear()),
                border: const OutlineInputBorder()
            ),
            autofocus: true, // Le clavier sortira tout seul
            onChanged: _onSearchChanged, // Déclenche la recherche live
          ),
          const SizedBox(height: 10),
          Expanded(child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _results.isEmpty
              ? const Center(child: Text("Aucun client trouvé ou saisissez une recherche."))
              : ListView.separated(
            itemCount: _results.length, separatorBuilder: (_,__) => const Divider(),
            itemBuilder: (ctx, i) {
              final c = _results[i];
              return ListTile(
                title: Text(c.fullName, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("Matricule: ${c.strLASTNAME}"), // Ou autre info utile
                onTap: () => Navigator.pop(context, c),
              );
            },
          )
          )
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler"))],
    );
  }
}