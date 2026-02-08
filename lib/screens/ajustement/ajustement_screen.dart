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
import 'package:prestige_vente_app/screens/common/product_search_modal.dart';

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
  bool _isProcessing = false;
  bool _isModalOpen = false; // Verrou anti-doublon

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
    if (mounted && !_isProcessing && !_isModalOpen) {
      FocusScope.of(context).requestFocus(_focusNode);
    }
  }

  // --- GESTION DOUCHETTE / CLAVIER PHYSIQUE ---
  void _handleKeyEvent(KeyEvent event) {
    if (_focusNode.hasFocus) {
      _scanBuffer = "";
      return;
    }

    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        if (_scanBuffer.isNotEmpty) {
          // C'est un scan : on lance la recherche directe (isScan: true)
          _performSearch(_scanBuffer.trim(), isScan: true);
          _scanBuffer = "";
        }
      } else if (event.character != null) {
        _scanBuffer += event.character!;
      }
    }
  }

  // --- DÉTECTION DE SAISIE MANUELLE ---
  void _onSearchChanged() {
    if (_isProcessing || _isModalOpen) return;

    if (_debounce?.isActive ?? false) _debounce!.cancel();

    // MODIFICATION 1 : Délai augmenté à 800ms pour laisser le temps de taper
    _debounce = Timer(const Duration(milliseconds: 800), () {
      if (!mounted || _isProcessing || _isModalOpen) return;

      final text = _searchController.text.trim();

      // MODIFICATION 2 : On ne lance rien si moins de 3 caractères
      // Cela évite l'ouverture du popup juste pour "d" ou "do"
      if (text.length >= 3) {
        _performSearch(text, isScan: false);
      }
    });
  }

  // --- OUVERTURE DU MODAL DE RECHERCHE CONTINUE ---
  void _openSearchModal(String currentQuery) {
    if (_isModalOpen) return;

    setState(() {
      _isModalOpen = true;
      _isProcessing = false;
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      builder: (ctx) => ProductSearchModal(
        initialQuery: currentQuery,
        onProductSelected: (selectedProduct) {
          // Au retour, on vide le champ et on ouvre le DIALOG DE QUANTITÉ
          _searchController.clear();

          Future.delayed(const Duration(milliseconds: 200), () {
            if (mounted) _showAddDialog(selectedProduct);
          });
        },
      ),
    ).then((_) {
      if (mounted) {
        setState(() => _isModalOpen = false);
        _searchController.clear();
        _requestSearchFocus();
      }
    });
  }

  // --- CŒUR DE LA RECHERCHE ---
  Future<void> _performSearch(String query, {required bool isScan}) async {
    _debounce?.cancel();
    if (query.isEmpty) return;
    if (_isModalOpen) return;

    // 1. CAS DU SCANNER PHYSIQUE (Code exact)
    if (isScan) {
      setState(() => _isProcessing = true);
      final provider = Provider.of<AjustementProvider>(context, listen: false);
      try {
        final results = await provider.searchProduct(query);
        if (!mounted) return;

        if (results.length == 1) {
          // Scan exact -> On ouvre direct le Dialog Quantité (Pas d'ajout auto +1)
          _searchController.clear();
          _showAddDialog(results.first);
        } else if (results.isNotEmpty) {
          // Plusieurs résultats (ex: code court) -> On laisse choisir
          _openSearchModal(query);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Produit introuvable")));
        }
      } finally {
        if (mounted) {
          setState(() => _isProcessing = false);
          if (!_isModalOpen) _requestSearchFocus();
        }
      }
      return;
    }

    // 2. CAS DE LA SAISIE MANUELLE
    // On ouvre le modal pour continuer la saisie (si > 3 chars, géré par _onSearchChanged)
    _openSearchModal(query);
  }

  // --- DIALOGUE QUANTITÉ / MOTIF ---
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
                        if (val.replaceFirst('-', '').length > 4) return "Trop grand (Scan erreur ?)";
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

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirmer l'ajustement"),
        content: Text("Clôturer cet ajustement de ${provider.items.length} lignes ?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Non")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Oui")),
        ],
      ),
    );

    if (confirm == true) {
      final List<AjustementItem> itemsToPrint = List.from(provider.items);
      final String userName = authProvider.user?.fullName ?? "Inconnu";

      final success = await provider.validateAjustement();

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ajustement validé !"), backgroundColor: Colors.green));

        final bool? wantToPrint = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text("Impression"),
            content: const Text("Terminé.\nVoulez-vous imprimer le bon ?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Non, terminer"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("Oui, imprimer"),
              ),
            ],
          ),
        );

        if (wantToPrint == true) {
          try {
            final pdfService = PdfAjustementService();
            await pdfService.printAjustementTicket(itemsToPrint, userName);
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur PDF: $e"), backgroundColor: Colors.red));
          }
        }
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
            // ZONE DE RECHERCHE (SIMPLIFIÉE : PLUS DE BOUTON ÉCLAIR)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                controller: _searchController,
                focusNode: _focusNode,
                decoration: InputDecoration(
                  labelText: "Scanner ou Rechercher (min 3 car.)",
                  prefixIcon: _isProcessing
                      ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.search),
                  suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _requestSearchFocus();
                      }
                  ),
                  border: const OutlineInputBorder(),
                ),
                // Pour le clavier virtuel : lance la recherche quand on fait "Entrée"
                onSubmitted: (val) {
                  if (val.isNotEmpty) _performSearch(val, isScan: false);
                },
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
                        backgroundColor: isPositive ? Colors.green.withValues(alpha: 0.2) : Colors.red.withValues(alpha: 0.2),
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