// lib/screens/delivery_control/delivery_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/commande_item.dart';
import 'package:prestige_vente_app/providers/delivery_control_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/screens/delivery_control/delivery_report_screen.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

class DeliveryDetailScreen extends StatefulWidget {
  const DeliveryDetailScreen({super.key});

  @override
  State<DeliveryDetailScreen> createState() => _DeliveryDetailScreenState();
}

class _DeliveryDetailScreenState extends State<DeliveryDetailScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  final Map<String, FocusNode> _itemFocusNodes = {};
  final Map<String, TextEditingController> _itemControllers = {};

  List<CommandeItem> _filteredItems = [];

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<DeliveryControlProvider>(context, listen: false);
    _filteredItems = provider.items;
    final checkedQuantities = provider.checkedQuantities;

    for (var item in provider.items) {
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

    _searchController.addListener(_filterList);
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

  void _filterList() {
    final provider = Provider.of<DeliveryControlProvider>(context, listen: false);
    final query = _searchController.text.toLowerCase();

    setState(() {
      if (query.isEmpty) {
        _filteredItems = provider.items;
      } else {
        _filteredItems = provider.items.where((item) {
          return item.nomProduit.toLowerCase().contains(query) || item.cip.contains(query);
        }).toList();
      }
    });
  }

  // --- NOUVELLE LOGIQUE SCAN ---
  void _onSearchSubmitted(String val) {
    if (_filteredItems.length == 1) {
      _showQuickScanDialog(_filteredItems.first);
    }
  }

  Future<void> _showQuickScanDialog(CommandeItem item) async {
    final provider = Provider.of<DeliveryControlProvider>(context, listen: false);

    // Récupération de la quantité actuelle
    final currentQty = provider.checkedQuantities[item.id] ?? 0;
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
      provider.updateCheckedQuantity(item.id, result);
      _itemControllers[item.id]?.text = result.toString();

      // Reset pour enchaîner
      _searchController.clear();
      _searchFocusNode.requestFocus();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Quantité mise à jour : ${item.nomProduit}"), duration: const Duration(milliseconds: 500)),
      );
    }
  }
  // -----------------------------

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    final bool canEdit = settingsProvider.canEditDeliveryControl;

    return Consumer<DeliveryControlProvider>(
      builder: (context, provider, child) {
        final commande = provider.selectedCommande;
        if (commande == null) {
          return Scaffold(appBar: AppBar(), body: const Center(child: Text("Aucune commande sélectionnée.")));
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(commande.ref),
            actions: [
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                icon: const Icon(Icons.assessment),
                label: const Text('Rapport'),
                onPressed: provider.isCurrentOrderCompleted ? () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DeliveryReportScreen()));
                } : null,
              ),
            ],
          ),
          body: Column(
            children: [
              _buildSearchBar(),
              if (provider.isLoading)
                const LinearProgressIndicator(),
              Expanded(
                child: ListView.builder(
                  itemCount: _filteredItems.length,
                  itemBuilder: (context, index) {
                    final item = _filteredItems[index];
                    final nextItem = (index + 1 < _filteredItems.length) ? _filteredItems[index + 1] : null;

                    final isChecked = provider.checkedQuantities.containsKey(item.id);
                    final bool isEnabled = canEdit || !isChecked;

                    return _buildItemTile(context, item, nextItem, provider, isEnabled);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        textInputAction: TextInputAction.search, // Important pour le déclenchement
        onSubmitted: _onSearchSubmitted,         // Appel de la nouvelle fonction
        decoration: InputDecoration(
          labelText: 'Rechercher ou Scanner (Nom, CIP)',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _searchController.clear();
                _searchFocusNode.requestFocus();
              }
          ),
        ),
      ),
    );
  }

  Widget _buildItemTile(BuildContext context, CommandeItem item, CommandeItem? nextItem, DeliveryControlProvider provider, bool isEnabled) {
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
        subtitle: Text('CIP: ${item.cip} | Qté Cmd: ${item.qteCommandee}'),
        trailing: SizedBox(
          width: 80,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: isEnabled,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Qté reçue',
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

// ---------------------------------------------------------------------------
// WIDGET POPUP SÉCURISÉ (Copie exacte pour Delivery)
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