// lib/screens/delivery_control/delivery_list_screen.dart
// 18/10/2025 14:40
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/providers/delivery_control_provider.dart';
import 'package:prestige_vente_app/screens/delivery_control/delivery_detail_screen.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

class DeliveryListScreen extends StatefulWidget {
  const DeliveryListScreen({super.key});

  @override
  State<DeliveryListScreen> createState() => _DeliveryListScreenState();
}

class _DeliveryListScreenState extends State<DeliveryListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<DeliveryControlProvider>(context, listen: false).fetchCommandes();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Liste des Commandes')),
      body: Consumer<DeliveryControlProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.commandes.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (provider.commandes.isEmpty) {
            return const Center(child: Text('Aucune commande en cours.'));
          }

          return RefreshIndicator(
            onRefresh: () => provider.fetchCommandes(),
            child: ListView.builder(
              itemCount: provider.commandes.length,
              itemBuilder: (context, index) {
                final commande = provider.commandes[index];

                final isCompleted = provider.isOrderCompleted(commande.id);
                final isInProgress = provider.isOrderInProgress(commande.id);

                Color? cardColor;
                IconData iconData;
                Color iconColor;

                if (isCompleted) {
                  cardColor = Colors.green.shade50;
                  iconData = Icons.check_circle;
                  iconColor = AppColors.success;
                } else if (isInProgress) {
                  cardColor = Colors.orange.shade50;
                  iconData = Icons.pending_actions;
                  iconColor = Colors.orange;
                } else {
                  cardColor = null;
                  iconData = Icons.receipt_long;
                  iconColor = AppColors.primary;
                }

                return Card(
                  color: cardColor,
                  child: ListTile(
                    leading: Icon(iconData, color: iconColor),
                    title: Text('${commande.ref} - ${commande.grossiste}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${commande.date} - ${commande.nbreProduit} produits'),
                    trailing: Text(
                      Constants.formatNumber(commande.prixAchatTotal),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.secondary),
                    ),
                    onTap: () async {
                      await provider.selectCommande(commande);
                      if (mounted) {
                        // On attend que l'écran de détail soit fermé (quand l'utilisateur appuie sur "retour")
                        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DeliveryDetailScreen()));

                        // MODIFICATION : Une fois de retour, on rafraîchit la liste.
                        if (mounted) {
                          provider.fetchCommandes();
                        }
                      }
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}