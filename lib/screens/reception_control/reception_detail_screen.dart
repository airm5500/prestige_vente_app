// lib/screens/reception_control/reception_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:prestige_vente_app/api/models/reception_model.dart';
import 'package:prestige_vente_app/providers/reception_provider.dart';
import 'package:prestige_vente_app/screens/reception_control/reception_report_screen.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

class ReceptionDetailScreen extends StatefulWidget {
  const ReceptionDetailScreen({super.key});

  @override
  State<ReceptionDetailScreen> createState() => _ReceptionDetailScreenState();
}

class _ReceptionDetailScreenState extends State<ReceptionDetailScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  final Map<String, TextEditingController> _itemControllers = {};
  final Map<String, FocusNode> _itemFocusNodes = {};

  List<ReceptionItem> _filteredItems = [];

  // FILTRES
  String _selectedEmplacement = "__GROUP_ALL__"; // Par défaut : Groupé
  String _selectedStatus = "TOUS";

  static const String _groupAllKey = "__GROUP_ALL__";
  static const String _allKey = "__ALL__";
  static const String _noLocKey = "__NO_LOC__";

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<ReceptionProvider>(context, listen: false);
    final bon = provider.selectedBon;
    if (bon != null) {
      _filteredItems = List.from(bon.details);
      _initializeControllers(provider);
      _applyFilters();
    }
    _searchController.addListener(_applyFilters);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_searchFocusNode);
    });
  }

  void _initializeControllers(ReceptionProvider provider) {
    final quantities = provider.currentCheckedQuantities;
    if (provider.selectedBon == null) return;

    for (var item in provider.selectedBon!.details) {
      if (!_itemControllers.containsKey(item.id)) {
        final val = quantities[item.id] ?? 0;
        final ctrl = TextEditingController(text: val > 0 ? val.toString() : '');
        final focus = FocusNode();

        focus.addListener(() {
          if (focus.hasFocus) {
            ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
          }
        });

        _itemControllers[item.id] = ctrl;
        _itemFocusNodes[item.id] = focus;
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _itemControllers.forEach((_, c) => c.dispose());
    _itemFocusNodes.forEach((_, f) => f.dispose());
    super.dispose();
  }

  void _applyFilters() {
    final provider = Provider.of<ReceptionProvider>(context, listen: false);
    if (provider.selectedBon == null) return;

    final query = _searchController.text.toLowerCase().trim();
    List<ReceptionItem> items = List.from(provider.selectedBon!.details);

    if (query.isNotEmpty) {
      items = items.where((item) {
        return item.nomProduit.toLowerCase().contains(query) ||
            item.cip.contains(query) ||
            item.ean.contains(query);
      }).toList();
    }

    bool isGroupedMode = _selectedEmplacement == _groupAllKey;
    if (!isGroupedMode && _selectedEmplacement != _allKey) {
      if (_selectedEmplacement == _noLocKey) {
        items = items.where((item) => item.emplacement.isEmpty).toList();
      } else {
        items = items.where((item) => item.emplacement == _selectedEmplacement).toList();
      }
    }

    if (_selectedStatus != "TOUS") {
      items = items.where((item) {
        final currentQty = provider.currentCheckedQuantities[item.id] ?? 0;
        final bool isTraite = currentQty > 0 || provider.currentCheckedQuantities.containsKey(item.id);

        switch (_selectedStatus) {
          case "A_TRAITER": return !isTraite;
          case "TRAITE": return isTraite;
          case "ECART": return isTraite && (currentQty != item.qteRecue);
          default: return true;
        }
      }).toList();
    }

    if (isGroupedMode) {
      final groupedItems = groupBy(items, (ReceptionItem item) => item.emplacement.isEmpty ? "Sans Emplacement" : item.emplacement);
      final sortedKeys = groupedItems.keys.toList()..sort();
      List<ReceptionItem> sortedList = [];
      for (var key in sortedKeys) {
        var group = groupedItems[key]!;
        group.sort((a, b) => a.nomProduit.compareTo(b.nomProduit));
        sortedList.addAll(group);
      }
      items = sortedList;
    } else {
      items.sort((a, b) => a.nomProduit.compareTo(b.nomProduit));
    }

    setState(() {
      _filteredItems = items;
    });
  }

  // --- NOUVELLE LOGIQUE SCAN ---
  void _onSearchSubmitted(String val) {
    if (_filteredItems.length == 1) {
      _showQuickScanDialog(_filteredItems.first);
    }
  }

  Future<void> _showQuickScanDialog(ReceptionItem item) async {
    final provider = Provider.of<ReceptionProvider>(context, listen: false);

    // Récupération de la quantité actuelle
    final currentQty = provider.currentCheckedQuantities[item.id] ?? 0;
    final String initialValue = currentQty > 0 ? currentQty.toString() : "";

    // Ouverture du Dialog Sécurisé
    final int? result = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _QuantityInputDialog(
        nomProduit: item.nomProduit,
        cip: item.cip,
        initialValue: initialValue,
      ),
    );

    if (result != null) {
      provider.updateQuantity(item.id, result);
      _itemControllers[item.id]?.text = result.toString();

      // Reset pour enchaîner
      _searchController.clear();
      _searchFocusNode.requestFocus();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Quantité mise à jour : ${item.nomProduit}"), duration: const Duration(milliseconds: 500)),
      );
    }
  }

  void _focusNextProduct(int currentIndex) {
    if (currentIndex + 1 < _filteredItems.length) {
      final nextItem = _filteredItems[currentIndex + 1];
      final nextNode = _itemFocusNodes[nextItem.id];
      if (nextNode != null) {
        FocusScope.of(context).requestFocus(nextNode);
      }
    } else {
      FocusScope.of(context).unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ReceptionProvider>(
      builder: (context, provider, child) {
        final bon = provider.selectedBon;
        if (bon == null) return const Scaffold(body: Center(child: Text("Erreur de sélection")));

        // CORRECTION : Suppression des lignes inutiles qui causaient le Warning
        int countTotal = _filteredItems.length;
        int countTraites = _filteredItems.where((i) => provider.currentCheckedQuantities.containsKey(i.id)).length;
        final bool isGroupedMode = _selectedEmplacement == _groupAllKey;

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(bon.ref, style: const TextStyle(fontSize: 16)),
                Text("${bon.grossiste} - $countTraites/$countTotal lignes (Filtre)", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
              ],
            ),
            actions: [
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                icon: const Icon(Icons.assessment),
                label: const Text('Rapport'),
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  Future.delayed(const Duration(milliseconds: 100), () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ReceptionReportScreen()));
                  });
                },
              )
            ],
          ),
          body: Column(
            children: [
              // ZONE DE FILTRES
              Container(
                padding: const EdgeInsets.all(8.0),
                color: Colors.grey.shade50,
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      decoration: InputDecoration(
                        hintText: "Scanner ou rechercher produit...",
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchController.clear(); _searchFocusNode.requestFocus(); })
                            : null,
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      textInputAction: TextInputAction.search,
                      onSubmitted: _onSearchSubmitted,
                    ),
                  ],
                ),
              ),

              if (provider.isLoading) const LinearProgressIndicator(),

              // LISTE ITEMS
              Expanded(
                child: _filteredItems.isEmpty
                    ? const Center(child: Text("Aucun produit trouvé", style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                  itemCount: _filteredItems.length,
                  itemBuilder: (context, index) {
                    final item = _filteredItems[index];

                    // Header de groupe
                    bool showHeader = false;
                    if (isGroupedMode) {
                      if (index == 0) {
                        showHeader = true;
                      } else {
                        final prevItem = _filteredItems[index - 1];
                        String currentLoc = item.emplacement.isEmpty ? "Sans Emplacement" : item.emplacement;
                        String prevLoc = prevItem.emplacement.isEmpty ? "Sans Emplacement" : prevItem.emplacement;
                        if (currentLoc != prevLoc) showHeader = true;
                      }
                    }

                    final checkedQty = provider.currentCheckedQuantities[item.id];
                    final hasBeenChecked = provider.currentCheckedQuantities.containsKey(item.id);
                    final qtyRecueBL = item.qteRecue;
                    final qtySaisie = checkedQty ?? 0;

                    Color? cardColor;
                    Icon leadingIcon;
                    if (hasBeenChecked) {
                      if (qtySaisie == qtyRecueBL) {
                        cardColor = Colors.green.shade50;
                        leadingIcon = const Icon(Icons.check_circle, color: AppColors.success);
                      } else {
                        cardColor = Colors.orange.shade50;
                        leadingIcon = const Icon(Icons.warning_amber_rounded, color: Colors.deepOrange);
                      }
                    } else {
                      cardColor = Colors.white;
                      leadingIcon = const Icon(Icons.radio_button_unchecked, color: Colors.grey);
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showHeader)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            color: Colors.grey.shade200,
                            child: Text(
                              item.emplacement.isEmpty ? "Sans Emplacement" : item.emplacement,
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                            ),
                          ),
                        Card(
                          color: cardColor,
                          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                            leading: leadingIcon,
                            title: Text(item.nomProduit, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            subtitle: RichText(
                              text: TextSpan(
                                  style: const TextStyle(color: Colors.black87, fontSize: 12),
                                  children: [
                                    const TextSpan(text: "CIP: ", style: TextStyle(color: Colors.grey)),
                                    TextSpan(text: "${item.cip}  "),
                                    if (!isGroupedMode) ...[
                                      const TextSpan(text: "Zone: ", style: TextStyle(color: Colors.grey)),
                                      TextSpan(text: item.emplacement.isEmpty ? "-" : item.emplacement, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                                      const TextSpan(text: "\n"),
                                    ] else ...[
                                      const TextSpan(text: "\n"),
                                    ],
                                    const TextSpan(text: "Attendu: "),
                                    TextSpan(text: "$qtyRecueBL", style: const TextStyle(fontWeight: FontWeight.bold)),
                                    if (hasBeenChecked && qtySaisie != qtyRecueBL)
                                      TextSpan(
                                          text: " | Écart: ${qtySaisie - qtyRecueBL > 0 ? '+' : ''}${qtySaisie - qtyRecueBL}",
                                          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)
                                      ),
                                  ]
                              ),
                            ),
                            trailing: SizedBox(
                              width: 70,
                              child: TextField(
                                controller: _itemControllers[item.id],
                                focusNode: _itemFocusNodes[item.id],
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: "Reçu",
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                  isDense: true,
                                ),
                                onChanged: (val) {
                                  final q = int.tryParse(val) ?? 0;
                                  provider.updateQuantity(item.id, q);
                                },
                                onSubmitted: (val) {
                                  final q = int.tryParse(val) ?? 0;
                                  provider.updateQuantity(item.id, q);
                                  _focusNextProduct(index);
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// WIDGET POPUP SÉCURISÉ (Même logique que BL)
// ---------------------------------------------------------------------------
class _QuantityInputDialog extends StatefulWidget {
  final String nomProduit;
  final String cip;
  final String initialValue;

  const _QuantityInputDialog({
    Key? key,
    required this.nomProduit,
    required this.cip,
    required this.initialValue,
  }) : super(key: key);

  @override
  State<_QuantityInputDialog> createState() => _QuantityInputDialogState();
}

class _QuantityInputDialogState extends State<_QuantityInputDialog> {
  late TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _selectAllText();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _selectAllText() {
    if (_controller.text.isNotEmpty) {
      _controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
    }
  }

  void _validate() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      Navigator.of(context).pop(0);
      return;
    }

    final value = int.tryParse(text);

    // SÉCURITÉ ANTI-SCAN & COHÉRENCE
    if (value == null || value < 0 || value > 10000) {
      setState(() {
        _errorText = "Mauvaise valeur (Trop grande)";
      });
      _selectAllText();
      _focusNode.requestFocus();
    } else {
      Navigator.of(context).pop(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.nomProduit, style: const TextStyle(fontSize: 18)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("CIP: ${widget.cip}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 20),
          const Text("Saisir la quantité comptée :"),
          const SizedBox(height: 10),
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              errorText: _errorText,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(vertical: 15),
            ),
            onChanged: (val) {
              if (_errorText != null) setState(() => _errorText = null);
            },
            onSubmitted: (_) => _validate(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Annuler")),
        ElevatedButton(onPressed: _validate, child: const Text("Valider")),
      ],
    );
  }
}