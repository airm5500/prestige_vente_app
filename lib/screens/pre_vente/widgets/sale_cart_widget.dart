// lib/screens/pre_vente/widgets/sale_cart_widget.dart
// 28/09/2025 02:00
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

class SaleCartWidget extends StatelessWidget {
  const SaleCartWidget({super.key});

  // Affiche une boîte de dialogue pour modifier la quantité et le prix
  void _showEditDialog(BuildContext context, SaleItemDetail item) {
    final saleProvider = Provider.of<SaleProvider>(context, listen: false);
    final qteController = TextEditingController(text: item.intQUANTITY.toString());
    final priceController = TextEditingController(text: item.intPRICEUNITAIR.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Modifier ${item.strNAME}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qteController,
              decoration: const InputDecoration(labelText: 'Quantité'),
              keyboardType: TextInputType.number,
            ),
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
              saleProvider.updateCartItem(item, newQte, newPrice);
              Navigator.of(ctx).pop();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Le Consumer écoute les changements du SaleProvider
    return Consumer<SaleProvider>(
      builder: (context, saleProvider, child) {
        if (saleProvider.cartItems.isEmpty) {
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

        // Affiche la liste des articles dans le panier
        return ListView.builder(
          itemCount: saleProvider.cartItems.length,
          itemBuilder: (context, index) {
            final item = saleProvider.cartItems[index];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: ListTile(
                title: Text(item.strNAME, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('CIP: ${item.intCIP}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Affiche Quantité x Prix Unitaire = Total Ligne
                    Text(
                      '${item.intQUANTITY} x ${Constants.formatNumber(item.intPRICEUNITAIR)} = ${Constants.formatNumber(item.intPRICE)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(width: 10),
                    // Bouton pour modifier
                    IconButton(
                      icon: const Icon(Icons.edit, color: AppColors.secondary),
                      onPressed: () => _showEditDialog(context, item),
                    ),
                    // Bouton pour supprimer
                    IconButton(
                      icon: const Icon(Icons.delete, color: AppColors.error),
                      onPressed: () {
                        saleProvider.removeProductFromCart(item.lgPREENREGISTREMENTDETAILID);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}