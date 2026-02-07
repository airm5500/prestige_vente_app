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
    // Note: Le prix est souvent fixe en assurance/carnet, mais on laisse la possibilité si besoin
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
            // Décommentez si vous voulez permettre la modif de prix
            /*
            const SizedBox(height: 10),
            TextField(
              controller: priceController,
              decoration: const InputDecoration(labelText: 'Prix Unitaire'),
              keyboardType: TextInputType.number,
            ),
            */
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
              final int price = int.tryParse(priceController.text) ?? item.intPRICEUNITAIR;
              if (qte > 0) {
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
          padding: const EdgeInsets.all(8.0), // Padding général réduit
          itemCount: provider.cartItems.length,
          separatorBuilder: (ctx, i) => const Divider(height: 1), // Séparateur fin
          itemBuilder: (context, index) {
            final item = provider.cartItems[index];
            return Card(
              elevation: 2,
              margin: const EdgeInsets.symmetric(vertical: 4), // Marge verticale réduite
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0), // Padding interne compact
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // LIGNE 1 : NOM PRODUIT + CIP (Compacté)
                    Row(
                      children: [
                        Expanded(
                          child: RichText(
                            maxLines: 1, // Force une seule ligne
                            overflow: TextOverflow.ellipsis, // ... si trop long
                            text: TextSpan(
                              style: const TextStyle(color: Colors.black87, fontSize: 13), // Police réduite
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

                    // ESPACE RÉDUIT (C'est ici qu'on gagne de la place)
                    const SizedBox(height: 2),

                    // LIGNE 2 : PRIX ET ACTIONS
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Partie Gauche : Calcul Prix
                        Text(
                          '${item.intQUANTITY} x ${Constants.formatNumber(item.intPRICEUNITAIR)} = ${Constants.formatNumber(item.intPRICE)} F',
                          style: const TextStyle(
                              fontSize: 13, // Police réduite
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600
                          ),
                        ),

                        // Partie Droite : Boutons Actions
                        Row(
                          children: [
                            SizedBox(
                              width: 30, // Bouton compact
                              height: 30,
                              child: IconButton(
                                icon: const Icon(Icons.edit, size: 18), // Icône réduite
                                color: Colors.blue,
                                padding: EdgeInsets.zero,
                                onPressed: () => _showEditDialog(context, item),
                                tooltip: "Modifier quantité",
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 30, // Bouton compact
                              height: 30,
                              child: IconButton(
                                icon: const Icon(Icons.delete, size: 18), // Icône réduite
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