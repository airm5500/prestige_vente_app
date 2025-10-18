// lib/screens/bl_control/bl_report_screen.dart
// 16/10/2025 15:08
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/providers/bl_control_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

class BlReportScreen extends StatelessWidget {
  const BlReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rapport de Pointage'),
      ),
      body: Consumer<BlControlProvider>(
        builder: (context, provider, child) {
          final bl = provider.selectedBonLivraison;
          if (bl == null) {
            return const Center(child: Text("Aucun BL sélectionné."));
          }

          // On crée la liste des items avec des écarts
          final itemsWithDiscrepancy = provider.items.where((item) {
            final checkedQty = provider.checkedQuantities[item.id] ?? 0;
            return item.stockTheorique != checkedQty;
          }).toList();

          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              Text('BL: ${bl.ref}', style: Theme.of(context).textTheme.headlineSmall),
              Text('Fournisseur: ${bl.grossiste}'),
              const Divider(height: 30),

              if (itemsWithDiscrepancy.isEmpty)
                const Center(
                  child: Column(
                    children: [
                      Icon(Icons.check_circle_outline, color: AppColors.success, size: 60),
                      SizedBox(height: 16),
                      Text("Aucune anomalie détectée.", style: TextStyle(fontSize: 18)),
                      Text("Le stock compté correspond au stock théorique."),
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
                      final theoreticalStock = item.stockTheorique;
                      final difference = checkedQty - theoreticalStock;
                      return Card(
                        color: difference == 0 ? Colors.white : Colors.orange.shade50,
                        child: ListTile(
                          title: Text(item.nomProduit),
                          subtitle: Text('CIP: ${item.cip} | PA: ${Constants.formatNumber(item.prixAchat)}'),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('Théorique: $theoreticalStock'),
                              Text('Compté: $checkedQty'),
                              Text(
                                'Écart: ${difference > 0 ? '+' : ''}$difference',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: difference == 0 ? AppColors.success : AppColors.error
                                ),
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