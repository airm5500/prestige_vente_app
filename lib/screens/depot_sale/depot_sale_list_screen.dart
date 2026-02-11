// lib/screens/depot_sale/depot_sale_list_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/providers/depot_sale_provider.dart';
import 'package:prestige_vente_app/screens/depot_sale/depot_sale_screen.dart';
import 'package:intl/intl.dart';

class DepotSaleListScreen extends StatefulWidget {
  const DepotSaleListScreen({super.key});

  @override
  State<DepotSaleListScreen> createState() => _DepotSaleListScreenState();
}

class _DepotSaleListScreenState extends State<DepotSaleListScreen> {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<DepotSaleProvider>(context, listen: false).fetchOngoingSales();
    });
  }

  String _formatCurrency(int amount) {
    return NumberFormat.currency(locale: 'fr_XOF', symbol: 'F', decimalDigits: 0).format(amount);
  }

  void _resumeSale(String saleId) async {
    final provider = Provider.of<DepotSaleProvider>(context, listen: false);
    await provider.loadExistingSale(saleId);

    if (mounted) {
      Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DepotSaleScreen())
      ).then((_) {
        provider.fetchOngoingSales();
      });
    }
  }

  void _createNewSale() {
    final provider = Provider.of<DepotSaleProvider>(context, listen: false);
    provider.resetSale();
    Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DepotSaleScreen())
    ).then((_) {
      provider.fetchOngoingSales();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Ventes Dépôt en cours"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => Provider.of<DepotSaleProvider>(context, listen: false).fetchOngoingSales(),
          )
        ],
      ),

      // --- AJOUT DU BOUTON FLOTTANT (Toujours visible) ---
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createNewSale,
        label: const Text("Nouvelle Vente"),
        icon: const Icon(Icons.add),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),

      body: Consumer<DepotSaleProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.ongoingSales.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.shopping_basket_outlined, size: 60, color: Colors.grey),
                  const SizedBox(height: 10),
                  const Text("Aucune vente en cours", style: TextStyle(color: Colors.grey)),
                  // Le bouton ici est optionnel car le FloatingActionButton est présent,
                  // mais on peut le garder pour l'ergonomie si la liste est vide.
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 80), // Padding bas pour éviter que le FAB cache le dernier élément
            itemCount: provider.ongoingSales.length,
            separatorBuilder: (_, __) => const SizedBox(height: 5), // Petit espace entre les cartes
            itemBuilder: (context, index) {
              final sale = provider.ongoingSales[index];
              return Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: CircleAvatar(
                    backgroundColor: Colors.brown.shade100,
                    child: const Icon(Icons.store, color: Colors.brown),
                  ),
                  title: Text(
                    sale.strREF.isEmpty ? "Sans Référence" : sale.strREF,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text("Client: ${sale.strClientFullName}", style: const TextStyle(fontWeight: FontWeight.w500)),
                      Text(
                        "${sale.dtUPDATED} à ${sale.heure}",
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _formatCurrency(sale.intPRICE),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 16),
                      ),
                      const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey)
                    ],
                  ),
                  onTap: () => _resumeSale(sale.lgPREENREGISTREMENTID),
                ),
              );
            },
          );
        },
      ),
    );
  }
}