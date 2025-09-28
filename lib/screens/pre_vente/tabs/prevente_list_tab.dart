// lib/screens/pre_vente/tabs/prevente_list_tab.dart
// 28/09/2025 19:25
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

class PreventeListTab extends StatelessWidget {
  final TabController tabController;
  const PreventeListTab({super.key, required this.tabController});

  @override
  Widget build(BuildContext context) {
    return Consumer<SaleProvider>(
      builder: (context, saleProvider, child) {
        if (saleProvider.isLoadingPreventes) {
          return const Center(child: CircularProgressIndicator());
        }

        if (saleProvider.preventes.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Aucune prévente en cours.'),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Actualiser'),
                  onPressed: () => saleProvider.fetchPreventes(),
                )
              ],
            ),
          );
        }

        final preventes = saleProvider.preventes;

        return RefreshIndicator(
          onRefresh: () => saleProvider.fetchPreventes(),
          child: ListView.builder(
            itemCount: preventes.length,
            itemBuilder: (context, index) {
              final prevente = preventes[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.receipt_long, color: AppColors.primary),
                  title: Text('Ref: ${prevente.strREF}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${prevente.dtUPDATED} ${prevente.heure} - Vendeur: ${prevente.userFullName}'),
                  trailing: Text(
                    Constants.formatNumber(prevente.intPRICE),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.secondary),
                  ),
                  onTap: () {
                    saleProvider.loadPrevente(prevente.lgPREENREGISTREMENTID);
                    Constants.showSnackBar(context, 'Chargement de la prévente ${prevente.strREF}');
                    tabController.animateTo(1); // Aller à l'onglet VENTE
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }
}