// lib/screens/carnet_sale/widgets/carnet_cart_widget.dart
// 09/11/2025 19:00
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/providers/carnet_sale_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

class CarnetCartWidget extends StatelessWidget {
  const CarnetCartWidget({super.key});

  void _showEditDialog(BuildContext context, SaleItemDetail item) {
    final provider =
    Provider.of<CarnetSaleProvider>(context, listen: false);
    final qteController =
    TextEditingController(text: item.intQUANTITY.toString());
    final priceController =
    TextEditingController(text: item.intPRICEUNITAIR.toString());

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
              autofocus: true,
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
              final newQte =
                  int.tryParse(qteController.text) ?? item.intQUANTITY;
              final newPrice =
                  int.tryParse(priceController.text) ?? item.intPRICEUNITAIR;
              provider.updateCartItem(item, newQte, newPrice);
              Navigator.of(ctx).pop();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CarnetSaleProvider>(
      builder: (context, provider, child) {
        if (provider.cartItems.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shopping_cart_outlined,
                    size: 60, color: Colors.grey),
                SizedBox(height: 10),
                Text('Le panier est vide',
                    style: TextStyle(fontSize: 16, color: Colors.grey)),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: provider.cartItems.length,
          itemBuilder: (context, index) {
            final item = provider.cartItems[index];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Padding(
                padding:
                const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item.strNAME} - CIP: ${item.intCIP}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${item.intQUANTITY} x ${Constants.formatNumber(item.intPRICEUNITAIR)} = ${Constants.formatNumber(item.intPRICE)}',
                          style: const TextStyle(
                              fontSize: 15, color: Colors.black87),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit,
                                  color: AppColors.secondary),
                              onPressed: () => _showEditDialog(context, item),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            const SizedBox(width: 16),
                            IconButton(
                              icon: const Icon(Icons.delete,
                                  color: AppColors.error),
                              onPressed: () {
                                provider.removeProductFromCart(
                                    item.lgPREENREGISTREMENTDETAILID);
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        )
                      ],
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