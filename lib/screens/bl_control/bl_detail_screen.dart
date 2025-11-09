// lib/screens/bl_control/bl_detail_screen.dart
// 29/10/2025 22:55
import 'package:flutter/material.dart';
import 'package:collection/collection.dart'; // Import pour le groupage
import 'package:prestige_vente_app/api/models/bon_livraison_item.dart';
import 'package:prestige_vente_app/providers/bl_control_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/screens/bl_control/bl_report_screen.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

class BlDetailScreen extends StatefulWidget {
  const BlDetailScreen({super.key});

  @override
  State<BlDetailScreen> createState() => _BlDetailScreenState();
}

class _BlDetailScreenState extends State<BlDetailScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  final Map<String, FocusNode> _itemFocusNodes = {};
  final Map<String, TextEditingController> _itemControllers = {};

  List<BonLivraisonItem> _filteredItems = [];
  String? _selectedEmplacement;

  static const String _groupAllKey = "__GROUP_ALL__";

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<BlControlProvider>(context, listen: false);
    _filteredItems = provider.items;

    final checkedQuantities = provider.checkedQuantities;

    for (var item in provider.items) {
      final savedQuantity = checkedQuantities[item.id];
      // MODIFICATION : Le controller et le focus node sont créés en premier
      final controller = TextEditingController(
        text: savedQuantity != null ? savedQuantity.toString() : '',
      );
      final focusNode = FocusNode();

      // MODIFICATION : Ajout du listener pour la pré-sélection
      focusNode.addListener(() {
        if (focusNode.hasFocus) {
          // On utilise addPostFrameCallback pour s'assurer que le champ a bien le focus
          WidgetsBinding.instance.addPostFrameCallback((_) {
            controller.selection = TextSelection(
              baseOffset: 0,
              extentOffset: controller.text.length,
            );
          });
        }
      });

      _itemFocusNodes[item.id] = focusNode;
      _itemControllers[item.id] = controller;
    }

    _searchController.addListener(_applyFilters);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_searchFocusNode);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _itemFocusNodes.forEach((_, node) => node.dispose());
    _itemControllers.forEach((_, controller) => controller.dispose());
    super.dispose();
  }

  void _applyFilters() {
    final provider = Provider.of<BlControlProvider>(context, listen: false);
    final query = _searchController.text.toLowerCase();

    List<BonLivraisonItem> tempItems = provider.items;

    if (_selectedEmplacement != null && _selectedEmplacement != _groupAllKey) {
      tempItems = tempItems.where((item) => item.zoneGeoName == _selectedEmplacement).toList();
    }

    if (query.isNotEmpty) {
      tempItems = tempItems.where((item) {
        return item.nomProduit.toLowerCase().contains(query) || item.cip.contains(query);
      }).toList();
    }

    setState(() {
      _filteredItems = tempItems;
    });

    if (query.isNotEmpty && _filteredItems.length == 1) {
      final itemId = _filteredItems.first.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if(mounted) {
          FocusScope.of(context).requestFocus(_itemFocusNodes[itemId]);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    final bool canEdit = settingsProvider.canEditBlControl;

    return Consumer<BlControlProvider>(
      builder: (context, provider, child) {
        final bl = provider.selectedBonLivraison;
        if (bl == null) {
          return Scaffold(appBar: AppBar(), body: const Center(child: Text("Aucun BL sélectionné.")));
        }

        final bool isGrouped = (_selectedEmplacement != null);

        List<BonLivraisonItem> itemsToDisplay;

        if (isGrouped) {
          final groupedItems = groupBy(_filteredItems, (BonLivraisonItem item) => item.zoneGeoName);
          final sortedKeys = groupedItems.keys.toList()..sort();

          final List<BonLivraisonItem> sortedGroupedItems = [];
          for (final key in sortedKeys) {
            final itemsInGroup = groupedItems[key]!;
            itemsInGroup.sort((a, b) => a.nomProduit.compareTo(b.nomProduit));
            sortedGroupedItems.addAll(itemsInGroup);
          }
          itemsToDisplay = sortedGroupedItems;
        } else {
          itemsToDisplay = List.from(_filteredItems);
          itemsToDisplay.sort((a, b) => a.nomProduit.compareTo(b.nomProduit));
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(bl.ref),
            actions: [
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                icon: const Icon(Icons.assessment),
                label: const Text('Rapport'),
                onPressed: provider.isCurrentBlCompleted ? () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BlReportScreen()));
                } : null,
              ),
            ],
          ),
          body: Column(
            children: [
              _buildFilterBar(provider.isLoading, provider.emplacements),
              if (provider.isLoading)
                const LinearProgressIndicator(),
              Expanded(
                child: ListView.builder(
                  itemCount: itemsToDisplay.length,
                  itemBuilder: (context, index) {
                    final item = itemsToDisplay[index];

                    final bool isFirstInGroup = isGrouped && (index == 0 ||
                        itemsToDisplay[index - 1].zoneGeoName != item.zoneGeoName);

                    BonLivraisonItem? nextItem;
                    if (index + 1 < itemsToDisplay.length) {
                      nextItem = itemsToDisplay[index + 1];
                    }

                    final isChecked = provider.checkedQuantities.containsKey(item.id);
                    final bool isEnabled = canEdit || !isChecked;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isFirstInGroup)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Text(
                              item.zoneGeoName,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary),
                            ),
                          ),
                        _buildItemTile(context, item, nextItem, provider, isEnabled),
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

  Widget _buildFilterBar(bool isLoading, List<String> emplacements) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              decoration: InputDecoration(
                labelText: 'Rechercher (Nom, CIP)',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      _applyFilters();
                    }
                ),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: isLoading
                ? InputDecorator(
              decoration: InputDecoration(
                hintText: 'Emplacement',
                border: const OutlineInputBorder(),
                isDense: true,
                fillColor: Colors.grey.shade200,
                filled: true,
              ),
              child: const Text(
                'Chargement...',
                style: TextStyle(color: Colors.black54),
                overflow: TextOverflow.ellipsis,
              ),
            )
                : DropdownButtonFormField<String>(
              value: _selectedEmplacement,
              hint: const Text('Emplacement'),
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('Aucun (Liste plate)', overflow: TextOverflow.ellipsis),
                ),
                const DropdownMenuItem<String>(
                  value: _groupAllKey,
                  child: Text('Tous (Groupés)', overflow: TextOverflow.ellipsis),
                ),
                ...emplacements.map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value, overflow: TextOverflow.ellipsis),
                  );
                }),
              ],
              onChanged: (String? newValue) {
                setState(() {
                  _selectedEmplacement = newValue;
                });
                _applyFilters();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemTile(BuildContext context, BonLivraisonItem item, BonLivraisonItem? nextItem, BlControlProvider provider, bool isEnabled) {
    final controller = _itemControllers[item.id]!;
    final focusNode = _itemFocusNodes[item.id]!;
    final isChecked = provider.checkedQuantities.containsKey(item.id);

    return Card(
      color: isChecked ? (isEnabled ? Colors.green.shade50 : Colors.grey.shade200) : null,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: Icon(
          isChecked ? Icons.check_circle : Icons.radio_button_unchecked,
          color: isEnabled ? (isChecked ? AppColors.success : Colors.grey) : Colors.grey,
        ),
        title: Text(item.nomProduit, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('CIP: ${item.cip} | PV: ${Constants.formatNumber(item.prixVente)}\nEmpl: ${item.zoneGeoName}'),
        isThreeLine: true,
        trailing: SizedBox(
          width: 80,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: isEnabled,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Qté comptée',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) {
              final quantity = int.tryParse(value) ?? 0;
              provider.updateCheckedQuantity(item.id, quantity);
            },
            onSubmitted: (_) {
              if (nextItem != null) {
                FocusScope.of(context).requestFocus(_itemFocusNodes[nextItem.id]);
              } else {
                FocusScope.of(context).requestFocus(_searchFocusNode);
              }
            },
          ),
        ),
      ),
    );
  }
}