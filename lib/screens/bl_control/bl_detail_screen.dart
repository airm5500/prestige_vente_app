// lib/screens/bl_control/bl_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
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
    _initializeControllers(provider);

    _searchController.addListener(_onSearchChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_searchFocusNode);
    });
  }

  void _initializeControllers(BlControlProvider provider) {
    final checkedQuantities = provider.checkedQuantities;
    for (var item in provider.items) {
      if (!_itemControllers.containsKey(item.id)) {
        final savedQuantity = checkedQuantities[item.id];
        final controller = TextEditingController(
          text: savedQuantity != null ? savedQuantity.toString() : '',
        );
        final focusNode = FocusNode();
        focusNode.addListener(() {
          if (focusNode.hasFocus) {
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
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _itemFocusNodes.forEach((_, node) => node.dispose());
    _itemControllers.forEach((_, controller) => controller.dispose());
    super.dispose();
  }

  void _onSearchChanged() {
    _applyFilters();
  }

  // Déclenché par la touche "Entrée" du clavier ou le caractère de fin de scan
  void _onSearchSubmitted(String value) {
    if (_filteredItems.length == 1) {
      // Scan unique trouvé -> Ouverture Pop-up sécurisé
      _showQuickScanDialog(_filteredItems.first);
    }
  }

  void _applyFilters() {
    final provider = Provider.of<BlControlProvider>(context, listen: false);
    final query = _searchController.text.toLowerCase().trim();

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
  }

  Future<void> _showQuickScanDialog(BonLivraisonItem item) async {
    final provider = Provider.of<BlControlProvider>(context, listen: false);

    // Valeur initiale (Quantité déjà saisie ou vide)
    final existingQty = provider.checkedQuantities[item.id];
    final String initialValue = (existingQty != null && existingQty > 0) ? existingQty.toString() : "";

    // Ouverture du Dialog personnalisé
    final int? result = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _QuantityInputDialog(
        item: item,
        initialValue: initialValue,
      ),
    );

    // Si une valeur valide est retournée
    if (result != null) {
      provider.updateCheckedQuantity(item.id, result);

      // Mise à jour du controller de la liste pour synchronisation visuelle
      if (_itemControllers.containsKey(item.id)) {
        _itemControllers[item.id]?.text = result.toString();
      }

      // Reset total : On vide la recherche et on remet le focus pour le prochain scan
      _searchController.clear();
      _searchFocusNode.requestFocus();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Quantité mise à jour : $result pour ${item.nomProduit}"),
          duration: const Duration(milliseconds: 800),
          backgroundColor: Colors.green,
        ),
      );
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

        final bool isGrouped = (_selectedEmplacement == _groupAllKey);

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

        String filterName = "Tous";
        if (_selectedEmplacement != null && _selectedEmplacement != _groupAllKey) {
          filterName = "Emplacement $_selectedEmplacement";
        } else if (_selectedEmplacement == _groupAllKey) {
          filterName = "Tous (Groupés)";
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(bl.ref),
            actions: [
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                icon: const Icon(Icons.assessment),
                label: const Text('Rapport'),
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => BlReportScreen(
                        filteredItems: itemsToDisplay,
                        filterName: filterName,
                      )
                  ));
                },
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
              textInputAction: TextInputAction.search,
              onSubmitted: _onSearchSubmitted,
              decoration: InputDecoration(
                labelText: 'Rechercher (Scan, Nom, CIP)',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      _searchFocusNode.requestFocus();
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
    if (!_itemControllers.containsKey(item.id)) {
      return const SizedBox();
    }

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
                labelText: 'Qté',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8)
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

// ---------------------------------------------------------------------------
// WIDGET POPUP PERSONNALISÉ POUR LA SAISIE RAPIDE
// ---------------------------------------------------------------------------
class _QuantityInputDialog extends StatefulWidget {
  final BonLivraisonItem item;
  final String initialValue;

  const _QuantityInputDialog({
    Key? key,
    required this.item,
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

    // Focus automatique + Sélection totale du texte pour remplacement rapide
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
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    }
  }

  void _validate() {
    final text = _controller.text.trim();

    // Si vide -> 0
    if (text.isEmpty) {
      Navigator.of(context).pop(0);
      return;
    }

    final value = int.tryParse(text);

    // SÉCURITÉ ANTI-SCAN & COHÉRENCE
    // 1. value == null : Ce n'est pas un nombre
    // 2. value < 0 : Pas de stock négatif
    // 3. value > 10000 : C'est surement un code barre (CIP/EAN) scanné par erreur
    //    (Un CIP fait au moins 7 chiffres, donc > 1 000 000)
    if (value == null || value < 0 || value > 10000) {
      setState(() {
        _errorText = "Mauvaise valeur (Trop grande)";
      });
      // On re-sélectionne tout immédiatement pour que l'utilisateur
      // puisse re-saisir ou re-scanner sans toucher au clavier/souris
      _selectAllText();
      _focusNode.requestFocus();
    } else {
      // Tout est bon
      Navigator.of(context).pop(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.item.nomProduit, style: const TextStyle(fontSize: 18)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("CIP: ${widget.item.cip}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
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
              errorText: _errorText, // Affiche l'erreur en rouge si besoin
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(vertical: 15),
            ),
            onChanged: (val) {
              if (_errorText != null) {
                setState(() => _errorText = null);
              }
            },
            onSubmitted: (_) => _validate(),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(), // Annuler renvoie null
            child: const Text("Annuler")
        ),
        ElevatedButton(
          onPressed: _validate,
          child: const Text("Valider"),
        )
      ],
    );
  }
}