// lib/screens/pre_vente/tabs/prevente_list_tab.dart
// 28/09/2025 02:16
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

class PreventeListTab extends StatefulWidget {
  final TabController tabController;
  const PreventeListTab({super.key, required this.tabController});

  @override
  State<PreventeListTab> createState() => _PreventeListTabState();
}

class _PreventeListTabState extends State<PreventeListTab> {
  late Future<List<PreventeListItem>> _preventesFuture;

  @override
  void initState() {
    super.initState();
    _fetchPreventes();
  }

  void _fetchPreventes() {
    final saleProvider = Provider.of<SaleProvider>(context, listen: false);
    setState(() {
      _preventesFuture = saleProvider.apiService.getPreventes();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PreventeListItem>>(
      future: _preventesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Erreur: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Aucune prévente en cours.'),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Actualiser'),
                  onPressed: _fetchPreventes,
                )
              ],
            ),
          );
        }

        final preventes = snapshot.data!;

        return RefreshIndicator(
          onRefresh: () async => _fetchPreventes(),
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
                    final saleProvider = Provider.of<SaleProvider>(context, listen: false);
                    saleProvider.loadPrevente(prevente.lgPREENREGISTREMENTID);
                    Constants.showSnackBar(context, 'Chargement de la prévente ${prevente.strREF}');
                    widget.tabController.animateTo(1); // Aller à l'onglet VENTE
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