// lib/screens/delivery_control/delivery_report_screen.dart
// 16/10/2025 10:45
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/providers/delivery_control_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

class DeliveryReportScreen extends StatelessWidget {
  const DeliveryReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rapport de Contrôle'),
      ),
      body: Consumer<DeliveryControlProvider>(
        builder: (context, provider, child) {
          final commande = provider.selectedCommande;
          if (commande == null) {
            return const Center(child: Text("Aucune commande sélectionnée."));
          }

          final itemsWithDiscrepancy = provider.items.where((item) {
            final checkedQty = provider.checkedQuantities[item.id] ?? 0;
            return item.qteCommandee != checkedQty;
          }).toList();

          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              Text('Commande: ${commande.ref}', style: Theme.of(context).textTheme.headlineSmall),
              Text('Fournisseur: ${commande.grossiste}'),
              const Divider(height: 30),

              if (itemsWithDiscrepancy.isEmpty)
                const Center(
                  child: Column(
                    children: [
                      Icon(Icons.check_circle_outline, color: AppColors.success, size: 60),
                      SizedBox(height: 16),
                      Text("Aucune anomalie détectée.", style: TextStyle(fontSize: 18)),
                      Text("Toutes les quantités reçues correspondent à la commande."),
                    ],
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Anomalies détectées :", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    ...itemsWithDiscrepancy.map((item) {
                      final checkedQty = provider.checkedQuantities[item.id] ?? 0;
                      final difference = checkedQty - item.qteCommandee;
                      return Card(
                        color: Colors.orange.shade50,
                        child: ListTile(
                          title: Text(item.nomProduit),
                          // MODIFICATION : Ajout du CIP et du Prix d'Achat (PA)
                          subtitle: Text('CIP: ${item.cip} | PA: ${Constants.formatNumber(item.prixAchat)}'),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('Commandé: ${item.qteCommandee}'),
                              Text('Reçu: $checkedQty'),
                              Text(
                                'Écart: ${difference > 0 ? '+' : ''}$difference',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.error),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}