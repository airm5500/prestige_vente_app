// lib/screens/carnet_sale/widgets/carnet_cart_widget.dart
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/providers/carnet_sale_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

class CarnetCartWidget extends StatelessWidget {
  const CarnetCartWidget({super.key});

  void _showEditDialog(BuildContext context, SaleItemDetail item) {
    final provider = Provider.of<CarnetSaleProvider>(context, listen: false);
    final qteController = TextEditingController(text: item.intQUANTITY.toString());

    // MODIF : J'ai activé ce contrôleur qui était commenté ou manquant
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
              autofocus: true,
            ),
            const SizedBox(height: 10),
            // MODIF : Ajout du champ prix
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
              final int qte = int.tryParse(qteController.text) ?? item.intQUANTITY;
              // MODIF : Récupération du prix
              final int price = int.tryParse(priceController.text) ?? item.intPRICEUNITAIR;

              if (qte > 0) {
                // MODIF : Envoi du nouveau prix au provider
                provider.updateCartItem(item, qte, price);
              }
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
            child: Text(
              'Le panier est vide',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(8.0),
          itemCount: provider.cartItems.length,
          separatorBuilder: (ctx, i) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final item = provider.cartItems[index];
            return Card(
              elevation: 2,
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: RichText(
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            text: TextSpan(
                              style: const TextStyle(color: Colors.black87, fontSize: 13),
                              children: [
                                TextSpan(
                                  text: item.strNAME,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                TextSpan(
                                  text: ' (${item.intCIP})',
                                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${item.intQUANTITY} x ${Constants.formatNumber(item.intPRICEUNITAIR)} = ${Constants.formatNumber(item.intPRICE)} F',
                          style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600
                          ),
                        ),
                        Row(
                          children: [
                            SizedBox(
                              width: 30,
                              height: 30,
                              child: IconButton(
                                icon: const Icon(Icons.edit, size: 18),
                                color: Colors.blue,
                                padding: EdgeInsets.zero,
                                onPressed: () => _showEditDialog(context, item),
                                tooltip: "Modifier",
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 30,
                              height: 30,
                              child: IconButton(
                                icon: const Icon(Icons.delete, size: 18),
                                color: Colors.red,
                                padding: EdgeInsets.zero,
                                onPressed: () => provider.removeProductFromCart(item.lgPREENREGISTREMENTDETAILID),
                                tooltip: "Supprimer",
                              ),
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