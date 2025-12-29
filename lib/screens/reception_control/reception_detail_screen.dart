// lib/screens/reception_control/reception_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:collection/collection.dart'; // Import nécessaire pour groupBy
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
  static const String _allKey = "__ALL__"; // Liste plate (sans groupement)
  static const String _noLocKey = "__NO_LOC__";

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<ReceptionProvider>(context, listen: false);
    final bon = provider.selectedBon;
    if (bon != null) {
      _filteredItems = List.from(bon.details);
      _initializeControllers(provider);
      // Appliquer le tri par défaut (Groupé)
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

  // --- LOGIQUE METIER ---

  void _applyFilters() {
    final provider = Provider.of<ReceptionProvider>(context, listen: false);
    if (provider.selectedBon == null) return;

    final query = _searchController.text.toLowerCase().trim();
    List<ReceptionItem> items = List.from(provider.selectedBon!.details);

    // 1. Filtre Texte (Recherche)
    if (query.isNotEmpty) {
      items = items.where((item) {
        return item.nomProduit.toLowerCase().contains(query) ||
            item.cip.contains(query) ||
            item.ean.contains(query);
      }).toList();
    }

    // 2. Filtre Emplacement
    bool isGroupedMode = _selectedEmplacement == _groupAllKey;

    if (!isGroupedMode && _selectedEmplacement != _allKey) {
      // Filtrage par emplacement spécifique
      if (_selectedEmplacement == _noLocKey) {
        items = items.where((item) => item.emplacement.isEmpty).toList();
      } else {
        items = items.where((item) => item.emplacement == _selectedEmplacement).toList();
      }
    }

    // 3. Filtre Statut
    if (_selectedStatus != "TOUS") {
      items = items.where((item) {
        final currentQty = provider.currentCheckedQuantities[item.id] ?? 0;
        final bool isTraite = currentQty > 0 || provider.currentCheckedQuantities.containsKey(item.id);

        switch (_selectedStatus) {
          case "A_TRAITER":
            return !isTraite;
          case "TRAITE":
            return isTraite;
          case "ECART":
            return isTraite && (currentQty != item.qteRecue);
          default:
            return true;
        }
      }).toList();
    }

    // 4. Tri et Groupement
    if (isGroupedMode) {
      // Si mode groupé, on trie d'abord par emplacement, puis par nom
      // Cela permet à la ListView de détecter les changements de groupe facilement
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
      // Tri alpha simple
      items.sort((a, b) => a.nomProduit.compareTo(b.nomProduit));
    }

    setState(() {
      _filteredItems = items;
    });
  }

  void _onSearchSubmitted(String val) {
    if (_filteredItems.length == 1) {
      _showQuickScanDialog(_filteredItems.first);
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

  Future<void> _showQuickScanDialog(ReceptionItem item) async {
    final provider = Provider.of<ReceptionProvider>(context, listen: false);
    final controller = TextEditingController();

    final currentQty = provider.currentCheckedQuantities[item.id] ?? 0;
    if (currentQty > 0) controller.text = currentQty.toString();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.nomProduit, style: const TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("CIP: ${item.cip}", style: const TextStyle(fontWeight: FontWeight.bold)),
            if (item.emplacement.isNotEmpty)
              Text("Emplacement: ${item.emplacement}", style: const TextStyle(color: Colors.blueGrey)),
            const SizedBox(height: 10),
            const Text("Quantité Reçue (Physique) :"),
            const SizedBox(height: 5),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => Navigator.pop(context),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler")),
          ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text("Valider")),
        ],
      ),
    );

    if (controller.text.isNotEmpty) {
      final qty = int.tryParse(controller.text) ?? 0;
      provider.updateQuantity(item.id, qty);
      _itemControllers[item.id]?.text = qty.toString();

      _searchController.clear();
      _searchFocusNode.requestFocus();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Quantité mise à jour : ${item.nomProduit}"), duration: const Duration(milliseconds: 500)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ReceptionProvider>(
      builder: (context, provider, child) {
        final bon = provider.selectedBon;
        if (bon == null) return const Scaffold(body: Center(child: Text("Erreur de sélection")));

        // Liste des emplacements pour le filtre
        final locations = bon.details.map((e) => e.emplacement).toSet().toList();
        locations.sort();
        final bool hasNoLoc = locations.contains('');

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
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        // Filtre Emplacement
                        Expanded(
                          flex: 3,
                          child: Container(
                            height: 40,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(4)),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: locations.contains(_selectedEmplacement) ||
                                    _selectedEmplacement == _groupAllKey ||
                                    _selectedEmplacement == _allKey ||
                                    _selectedEmplacement == _noLocKey
                                    ? _selectedEmplacement : _groupAllKey,
                                isExpanded: true,
                                icon: const Icon(Icons.filter_list, size: 18),
                                items: [
                                  const DropdownMenuItem(value: _groupAllKey, child: Text("Tous (Groupés)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                                  const DropdownMenuItem(value: _allKey, child: Text("Tous (Liste plate)", style: TextStyle(fontSize: 13))),
                                  if (hasNoLoc) const DropdownMenuItem(value: _noLocKey, child: Text("Sans Emplacement", style: TextStyle(fontStyle: FontStyle.italic, fontSize: 13))),
                                  ...locations.where((l) => l.isNotEmpty).map((loc) => DropdownMenuItem(value: loc, child: Text(loc, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis))),
                                ],
                                onChanged: (val) {
                                  if (val != null) setState(() { _selectedEmplacement = val; _applyFilters(); });
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Filtre Statut
                        Expanded(
                          flex: 2,
                          child: Container(
                            height: 40,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(4)),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedStatus,
                                isExpanded: true,
                                items: const [
                                  DropdownMenuItem(value: "TOUS", child: Text("Tous", style: TextStyle(fontSize: 13))),
                                  DropdownMenuItem(value: "A_TRAITER", child: Text("À Traiter", style: TextStyle(fontSize: 13, color: Colors.red))),
                                  DropdownMenuItem(value: "TRAITE", child: Text("Traités", style: TextStyle(fontSize: 13, color: Colors.green))),
                                  DropdownMenuItem(value: "ECART", child: Text("Écarts", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange))),
                                ],
                                onChanged: (val) {
                                  if (val != null) setState(() { _selectedStatus = val; _applyFilters(); });
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
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

                    // Gestion de l'entête de groupe (Si mode groupé activé)
                    bool showHeader = false;
                    if (isGroupedMode) {
                      if (index == 0) {
                        showHeader = true;
                      } else {
                        final prevItem = _filteredItems[index - 1];
                        // Comparer les emplacements (vide vs vide ou nom vs nom)
                        String currentLoc = item.emplacement.isEmpty ? "Sans Emplacement" : item.emplacement;
                        String prevLoc = prevItem.emplacement.isEmpty ? "Sans Emplacement" : prevItem.emplacement;
                        if (currentLoc != prevLoc) {
                          showHeader = true;
                        }
                      }
                    }

                    // Récupération des valeurs
                    final checkedQty = provider.currentCheckedQuantities[item.id];
                    final hasBeenChecked = provider.currentCheckedQuantities.containsKey(item.id);
                    final qtyRecueBL = item.qteRecue;
                    final qtySaisie = checkedQty ?? 0;

                    // Couleurs & Icônes
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
                                    // Si groupé, on affiche moins l'emplacement dans la ligne car il est dans le header
                                    if (!isGroupedMode) ...[
                                      const TextSpan(text: "Zone: ", style: TextStyle(color: Colors.grey)),
                                      TextSpan(text: item.emplacement.isEmpty ? "-" : item.emplacement, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                                      const TextSpan(text: "\n"),
                                    ] else ...[
                                      const TextSpan(text: "\n"), // Saut de ligne simple si groupé
                                    ],
                                    const TextSpan(text: "Attendu BL: "),
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