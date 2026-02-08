// lib/screens/ajustement/ajustement_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/providers/ajustement_provider.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/ajustement.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/services/pdf_ajustement_service.dart';

class AjustementScreen extends StatefulWidget {
  const AjustementScreen({super.key});

  @override
  State<AjustementScreen> createState() => _AjustementScreenState();
}

class _AjustementScreenState extends State<AjustementScreen> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  final _keyboardFocusNode = FocusNode();

  Timer? _debounce;
  bool _isQuickScan = false;
  bool _isProcessing = false;

  String _scanBuffer = "";

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AjustementProvider>(context, listen: false).loadTypesAjustement();
      _requestSearchFocus();
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _focusNode.dispose();
    _keyboardFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _requestSearchFocus() {
    if (mounted && !_isProcessing) {
      FocusScope.of(context).requestFocus(_focusNode);
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    if (_focusNode.hasFocus) {
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
    if (_isProcessing) return;

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted || _isProcessing) return;
      if (_searchController.text.trim().isNotEmpty) {
        _performSearch(_searchController.text.trim(), isScan: false);
      }
    });
  }

  Future<void> _performSearch(String query, {required bool isScan}) async {
    _debounce?.cancel();
    if (_isProcessing) return;
    if (query.isEmpty) return;

    setState(() => _isProcessing = true);
    final provider = Provider.of<AjustementProvider>(context, listen: false);

    try {
      final results = await provider.searchProduct(query);

      if (!mounted) return;

      if (results.length == 1) {
        final product = results.first;
        _searchController.clear();

        if (_isQuickScan) {
          await _executeQuickAdd(product);
        } else {
          _showAddDialog(product);
        }
      } else if (results.isNotEmpty) {
        // AFFICHE LE POPUP SI PLUSIEURS RÉSULTATS
        _showSelectionDialog(results);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Produit introuvable"), duration: Duration(seconds: 1))
        );
      }
    } finally {
      if (mounted) {
        if (Navigator.canPop(context) == false) {
          // Si aucun popup n'est ouvert, on libère le lock
        }
        setState(() => _isProcessing = false);
        if (!_isQuickScan) _requestSearchFocus();
      }
    }
  }

  // --- POPUP RÉSULTATS AVEC POLICE RÉDUITE ---
  void _showSelectionDialog(List<ProductSearchResult> results) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text("Résultats (${results.length})", style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.separated(
            itemCount: results.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final p = results[index];
              return ListTile(
                dense: true, // COMPACT
                contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                title: Text(
                    p.strNAME,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13) // NOM RÉDUIT
                ),
                subtitle: Text(
                    "CIP: ${p.intCIP} | Stock: ${p.intNUMBERAVAILABLE}",
                    style: const TextStyle(fontSize: 11, color: Colors.black54) // CIP/STOCK TRÈS RÉDUIT
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _searchController.clear();
                  if (_isQuickScan) {
                    _executeQuickAdd(p);
                  } else {
                    _showAddDialog(p);
                  }
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _searchController.clear();
              Navigator.pop(ctx);
              _requestSearchFocus();
            },
            child: const Text("Annuler"),
          )
        ],
      ),
    );
  }

  Future<void> _executeQuickAdd(ProductSearchResult product) async {
    final provider = Provider.of<AjustementProvider>(context, listen: false);
    int defaultMotifId = provider.typesAjustement.isNotEmpty ? provider.typesAjustement.first.id : 1;

    final success = await provider.addProduct(
      product: product,
      quantity: 1,
      typeAjustementId: defaultMotifId,
    );

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("${product.strNAME} (+1) ajouté"),
        duration: const Duration(milliseconds: 800),
        backgroundColor: Colors.green,
      ));
    }
  }

  void _showAddDialog(ProductSearchResult product) {
    final provider = Provider.of<AjustementProvider>(context, listen: false);
    final formKey = GlobalKey<FormState>();
    final qteController = TextEditingController();
    int selectedTypeId = provider.typesAjustement.isNotEmpty ? provider.typesAjustement.first.id : 1;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(product.strNAME, style: const TextStyle(fontSize: 16)),
        content: StatefulBuilder(
            builder: (context, setStateDialog) {
              return Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("Stock Actuel : ${product.intNUMBERAVAILABLE}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: qteController,
                      decoration: const InputDecoration(
                          labelText: "Quantité (+/-)",
                          border: OutlineInputBorder(),
                          helperText: "Ex: -2 (Retrait) ou 5 (Ajout)"
                      ),
                      keyboardType: const TextInputType.numberWithOptions(signed: true),
                      autofocus: true,
                      validator: (val) {
                        if (val == null || val.isEmpty) return "Requis";
                        if (int.tryParse(val) == null) return "Entier requis";
                        if (int.parse(val) == 0) return "Non nul";
                        if (val.replaceFirst('-', '').length > 4) return "Trop grand !";
                        return null;
                      },
                      onFieldSubmitted: (_) => _submitDialog(ctx, formKey, provider, product, qteController, selectedTypeId),
                    ),

                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      value: selectedTypeId,
                      decoration: const InputDecoration(labelText: "Motif", border: OutlineInputBorder()),
                      items: provider.typesAjustement.map((t) => DropdownMenuItem(value: t.id, child: Text(t.libelle))).toList(),
                      onChanged: (val) => setStateDialog(() => selectedTypeId = val!),
                    ),
                  ],
                ),
              );
            }
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          ElevatedButton(
              onPressed: () => _submitDialog(ctx, formKey, provider, product, qteController, selectedTypeId),
              child: const Text("Valider")
          ),
        ],
      ),
    ).then((_) {
      if (mounted) {
        _searchController.clear();
        _requestSearchFocus();
      }
    });
  }

  Future<void> _submitDialog(BuildContext ctx, GlobalKey<FormState> key, AjustementProvider provider, ProductSearchResult product, TextEditingController qteCtrl, int motifId) async {
    if (!key.currentState!.validate()) return;
    final qty = int.parse(qteCtrl.text);

    if (qty.abs() > 50) {
      final bool? confirm = await showDialog<bool>(
        context: ctx,
        builder: (alertCtx) => AlertDialog(
          title: const Text("⚠️ Quantité élevée"),
          content: Text("Vous allez ajuster le stock de : ${qty > 0 ? '+' : ''}$qty unités.\nConfirmer ?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(alertCtx, false), child: const Text("Corriger", style: TextStyle(color: Colors.red))),
            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(alertCtx, true), child: const Text("Confirmer", style: TextStyle(color: Colors.white))),
          ],
        ),
      );
      if (confirm != true) return;
    }

    if (mounted && Navigator.canPop(ctx)) {
      Navigator.pop(ctx);
    }
    await provider.addProduct(product: product, quantity: qty, typeAjustementId: motifId);
  }

  void _validateAjustement() async {
    final provider = Provider.of<AjustementProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    // 1. CONFIRMATION DE LA CLÔTURE
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirmer l'ajustement"),
        content: Text("Voulez-vous valider et clôturer cet ajustement de ${provider.items.length} lignes ?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Non")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Oui")),
        ],
      ),
    );

    if (confirm == true) {
      // On sauvegarde la liste pour l'impression AVANT que le provider ne la vide
      final List<AjustementItem> itemsToPrint = List.from(provider.items);
      final String userName = authProvider.user?.fullName ?? "Inconnu";

      // 2. APPEL API (Validation)
      final success = await provider.validateAjustement();

      if (success && mounted) {
        // Feedback visuel immédiat
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Ajustement validé avec succès !"),
            backgroundColor: Colors.green
        ));

        // 3. DEMANDE D'IMPRESSION (Optionnelle)
        final bool? wantToPrint = await showDialog<bool>(
          context: context,
          barrierDismissible: false, // Oblige à choisir Oui ou Non
          builder: (ctx) => AlertDialog(
            title: const Text("Impression"),
            content: const Text("L'opération est terminée.\nVoulez-vous imprimer le ticket d'ajustement ?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false), // Réponse NON
                child: const Text("Non, terminer"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true), // Réponse OUI
                child: const Text("Oui, imprimer"),
              ),
            ],
          ),
        );

        // 4. GÉNÉRATION PDF (Seulement si Oui)
        if (wantToPrint == true) {
          try {
            final pdfService = PdfAjustementService();
            await pdfService.printAjustementTicket(itemsToPrint, userName);
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur impression PDF: $e"), backgroundColor: Colors.red));
          }
        }

        // Si Non : On ne fait rien, le provider a déjà vidé la liste via validateAjustement(), l'écran est donc vide et prêt pour le prochain.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AjustementProvider>(context);

    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        appBar: AppBar(title: const Text("Ajustement de Stock")),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _focusNode,
                      decoration: InputDecoration(
                        labelText: _isQuickScan ? "SCAN RAPIDE ACTIF (+1)" : "Scanner ou Rechercher",
                        prefixIcon: _isProcessing
                            ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2))
                            : Icon(_isQuickScan ? Icons.bolt : Icons.search, color: _isQuickScan ? Colors.green : null),
                        suffixIcon: IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              _requestSearchFocus();
                            }
                        ),
                        border: const OutlineInputBorder(),
                        filled: _isQuickScan,
                        fillColor: _isQuickScan ? Colors.green.withValues(alpha: 0.1) : null,
                      ),
                      onSubmitted: (val) => _performSearch(val, isScan: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () {
                      setState(() => _isQuickScan = !_isQuickScan);
                      _requestSearchFocus();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _isQuickScan ? Colors.green : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: _isQuickScan ? Colors.green.shade700 : Colors.grey),
                      ),
                      child: Icon(Icons.flash_on, color: _isQuickScan ? Colors.white : Colors.grey),
                    ),
                  ),
                ],
              ),
            ),

            const Divider(thickness: 2),

            Expanded(
              child: provider.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : provider.items.isEmpty
                  ? const Center(child: Text("Aucun ajustement en cours", style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                itemCount: provider.items.length,
                itemBuilder: (ctx, index) {
                  final item = provider.items[index];
                  final isPositive = item.intNUMBER > 0;
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isPositive ? Colors.green.shade100 : Colors.red.shade100,
                        child: Text(isPositive ? "+" : "-", style: TextStyle(color: isPositive ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                      ),
                      title: Text(item.strNAME, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Text("${item.intCIP}\nAv: ${item.intNUMBERCURRENTSTOCK} -> Ap: ${item.intNUMBERAFTERSTOCK} | ${item.motifAjustement}"),
                      trailing: Text(
                          "${isPositive ? '+' : ''}${item.intNUMBER}",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isPositive ? Colors.green : Colors.red)
                      ),
                    ),
                  );
                },
              ),
            ),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, -2))]),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check_circle),
                label: const Text("CLÔTURER AJUSTEMENT"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: provider.items.isEmpty ? null : _validateAjustement,
              ),
            ),
          ],
        ),
      ),
    );
  }
}