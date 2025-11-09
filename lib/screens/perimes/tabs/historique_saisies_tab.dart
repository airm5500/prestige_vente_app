// lib/screens/perimes/tabs/historique_saisies_tab.dart
// 09/11/2025 17:30
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/providers/perime_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

class HistoriqueSaisiesTab extends StatefulWidget {
  const HistoriqueSaisiesTab({super.key});

  @override
  State<HistoriqueSaisiesTab> createState() => _HistoriqueSaisiesTabState();
}

class _HistoriqueSaisiesTabState extends State<HistoriqueSaisiesTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<PerimeProvider>(context, listen: false).loadSaisieHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PerimeProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading && provider.saisieHistoryList.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (provider.saisieHistoryList.isEmpty) {
          return const Center(child: Text('Aucun historique de saisie.'));
        }

        return RefreshIndicator(
          onRefresh: () => provider.loadSaisieHistory(),
          child: ListView.builder(
            itemCount: provider.saisieHistoryList.length,
            itemBuilder: (context, index) {
              final item = provider.saisieHistoryList[index];
              return Card(
                child: ListTile(
                  title: Text('${item.strNAME} (Qté: ${item.intQUANTITY})', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    'CIP: ${item.intCIP} | Lot: ${item.ticketNum} | Péremption: ${item.dtCREATED}\nOpération: ${item.dateOperation}',
                  ),
                  isThreeLine: true,
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Stock: ${item.stockInitial} -> ${item.stockFinal}', style: const TextStyle(fontSize: 12)),
                      Text(Constants.formatNumber(item.intPRICE), style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}