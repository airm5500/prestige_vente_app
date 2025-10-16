// lib/screens/delivery_control/delivery_detail_screen.dart
// 16/10/2025 10:30
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/commande_item.dart';
import 'package:prestige_vente_app/providers/delivery_control_provider.dart';
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

    // MODIFICATION : On récupère les quantités déjà saisies
    final checkedQuantities = provider.checkedQuantities;

    for (var item in provider.items) {
      _itemFocusNodes[item.id] = FocusNode();

      // On vérifie s'il y a une valeur sauvegardée pour cet item
      final savedQuantity = checkedQuantities[item.id];

      // On initialise le controller avec la valeur sauvegardée, ou vide sinon.
      _itemControllers[item.id] = TextEditingController(
        text: savedQuantity != null ? savedQuantity.toString() : '',
      );
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

        if (_filteredItems.length == 1) {
          final itemId = _filteredItems.first.id;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            FocusScope.of(context).requestFocus(_itemFocusNodes[itemId]);
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
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

                    return _buildItemTile(context, item, nextItem, provider);
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
        decoration: InputDecoration(
          labelText: 'Rechercher ou Scanner (Nom, CIP)',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () => _searchController.clear(),
          ),
        ),
      ),
    );
  }

  Widget _buildItemTile(BuildContext context, CommandeItem item, CommandeItem? nextItem, DeliveryControlProvider provider) {
    final controller = _itemControllers[item.id]!;
    final focusNode = _itemFocusNodes[item.id]!;
    final isChecked = provider.checkedQuantities.containsKey(item.id);

    return Card(
      color: isChecked ? Colors.green.shade50 : null,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: Icon(
          isChecked ? Icons.check_circle : Icons.radio_button_unchecked,
          color: isChecked ? AppColors.success : Colors.grey,
        ),
        title: Text(item.nomProduit, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('CIP: ${item.cip} | Qté Cmd: ${item.qteCommandee}'),
        trailing: SizedBox(
          width: 80,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
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