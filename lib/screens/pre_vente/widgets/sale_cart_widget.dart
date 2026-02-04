// lib/screens/pre_vente/widgets/sale_cart_widget.dart
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

class SaleCartWidget extends StatelessWidget {
  const SaleCartWidget({super.key});

  void _showEditDialog(BuildContext context, SaleItemDetail item, SaleProvider provider) {
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

  Future<void> _confirmDelete(BuildContext context, SaleItemDetail item, SaleProvider provider) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Supprimer ?"),
        content: Text("Retirer ${item.strNAME} du panier ?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Non"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Oui", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      provider.removeProductFromCart(item.lgPREENREGISTREMENTDETAILID);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SaleProvider>(
      builder: (context, saleProvider, child) {
        if (saleProvider.isLoading && saleProvider.cartItems.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

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

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: saleProvider.cartItems.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final SaleItemDetail item = saleProvider.cartItems[index];

            return Container(
              color: Colors.white, // Fond blanc pour être propre
              child: ListTile(
                // OPTIMISATION VISUELLE
                dense: true,
                visualDensity: const VisualDensity(vertical: -2), // Compacte la hauteur
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),

                // NOM SUR UNE SEULE LIGNE (avec ...)
                title: Text(
                  item.strNAME,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),

                // SOUS-TITRE : Quantité x PU et Total
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

                // BOUTONS D'ACTION (MODIFIER + SUPPRIMER)
                trailing: Row(
                  mainAxisSize: MainAxisSize.min, // Prend juste la place nécessaire
                  children: [
                    // Bouton Modifier (Crayon)
                    IconButton(
                      icon: const Icon(Icons.edit, size: 20, color: AppColors.secondary),
                      onPressed: () => _showEditDialog(context, item, saleProvider),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(), // Retire le padding par défaut
                      tooltip: "Modifier",
                    ),
                    const SizedBox(width: 16), // Espacement entre les icônes
                    // Bouton Supprimer (Poubelle)
                    IconButton(
                      icon: const Icon(Icons.delete, size: 20, color: AppColors.error),
                      onPressed: () => _confirmDelete(context, item, saleProvider),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: "Supprimer",
                    ),
                  ],
                ),

                onTap: () => _showEditDialog(context, item, saleProvider),
              ),
            );
          },
        );
      },
    );
  }
}