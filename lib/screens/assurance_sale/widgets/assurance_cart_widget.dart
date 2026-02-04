// lib/screens/assurance_sale/widgets/assurance_cart_widget.dart
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/providers/assurance_sale_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

class AssuranceCartWidget extends StatelessWidget {
  const AssuranceCartWidget({super.key});

  void _showEditDialog(BuildContext context, SaleItemDetail item) {
    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);
    final qteController = TextEditingController(text: item.intQUANTITY.toString());
    final priceController = TextEditingController(text: item.intPRICEUNITAIR.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item.strNAME, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qteController,
              decoration: const InputDecoration(labelText: 'Quantité'),
              keyboardType: TextInputType.number,
              autofocus: true,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: priceController,
              decoration: const InputDecoration(labelText: 'Prix Unitaire'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            child: const Text('Annuler'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          ElevatedButton(
            child: const Text('Valider'),
            onPressed: () {
              final newQte = int.tryParse(qteController.text) ?? item.intQUANTITY;
              final newPrice = int.tryParse(priceController.text) ?? item.intPRICEUNITAIR;
              provider.updateCartItem(item, newQte, newPrice);
              Navigator.of(ctx).pop();
            },
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, SaleItemDetail item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Supprimer ?"),
        content: Text("Retirer ${item.strNAME} ?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Non")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              Provider.of<AssuranceSaleProvider>(context, listen: false)
                  .removeProductFromCart(item.lgPREENREGISTREMENTDETAILID);
            },
            child: const Text("Oui", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AssuranceSaleProvider>(
      builder: (context, provider, child) {
        // CORRECTION FLUIDITÉ : On affiche le loader QUE si la liste est vide
        if (provider.cartItems.isEmpty) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shopping_cart_outlined, size: 60, color: Colors.grey),
                SizedBox(height: 10),
                Text('Le panier est vide', style: TextStyle(fontSize: 16, color: Colors.grey)),
              ],
            ),
          );
        }

        return ListView.separated(
          itemCount: provider.cartItems.length,
          separatorBuilder: (_,__) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final item = provider.cartItems[index];

            // UI COMPACTE SUR UNE LIGNE
            return ListTile(
              dense: true,
              visualDensity: const VisualDensity(vertical: -2),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),

              title: Text(
                item.strNAME,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              subtitle: Padding(
                padding: const EdgeInsets.only(top: 2.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${item.intQUANTITY} x ${Constants.formatNumber(item.intPRICEUNITAIR)}',
                      style: TextStyle(color: Colors.grey.shade800, fontSize: 13),
                    ),
                    Text(
                      '${Constants.formatNumber(item.intPRICE)} F',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue),
                    ),
                  ],
                ),
              ),

              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Bouton Modifier
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20, color: AppColors.secondary),
                    onPressed: () => _showEditDialog(context, item),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 12),
                  // Bouton Supprimer
                  IconButton(
                    icon: const Icon(Icons.delete, size: 20, color: AppColors.error),
                    onPressed: () => _confirmDelete(context, item),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              onTap: () => _showEditDialog(context, item),
            );
          },
        );
      },
    );
  }
}