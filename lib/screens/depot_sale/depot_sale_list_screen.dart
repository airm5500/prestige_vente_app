// lib/screens/depot_sale/depot_sale_list_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/depot_model.dart';
import 'package:prestige_vente_app/providers/depot_sale_provider.dart';
import 'package:prestige_vente_app/screens/depot_sale/depot_sale_screen.dart';
import 'package:prestige_vente_app/utils/constants.dart';

class DepotSaleListScreen extends StatefulWidget {
  const DepotSaleListScreen({Key? key}) : super(key: key);

  @override
  State<DepotSaleListScreen> createState() => _DepotSaleListScreenState();
}

class _DepotSaleListScreenState extends State<DepotSaleListScreen> {
  List<DepotSaleListItem> _sales = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSales();
  }

  Future<void> _loadSales() async {
    setState(() => _isLoading = true);
    final api = Provider.of<ApiService>(context, listen: false);
    final list = await api.fetchDepotSales();
    if (mounted) {
      setState(() {
        _sales = list;
        _isLoading = false;
      });
    }
  }

  void _openSale(String? saleId) async {
    // Si saleId est null, c'est une nouvelle vente, sinon on reprend
    final provider = Provider.of<DepotSaleProvider>(context, listen: false);
    provider.resetSale();

    if (saleId != null) {
      await provider.loadExistingSale(saleId);
    }

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DepotSaleScreen()),
    );

    // Au retour, on rafraichit la liste
    _loadSales();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Ventes Dépôts")),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openSale(null),
        label: const Text("Nouveau Dépôt"),
        icon: const Icon(Icons.add),
        backgroundColor: AppColors.primary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _sales.isEmpty
          ? const Center(child: Text("Aucune vente dépôt en cours"))
          : RefreshIndicator(
        onRefresh: _loadSales,
        child: ListView.builder(
          itemCount: _sales.length,
          itemBuilder: (context, index) {
            final sale = _sales[index];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.blue.shade100,
                  child: const Icon(Icons.store, color: Colors.blue),
                ),
                title: Text(sale.strClientFullName, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("Réf: ${sale.strREF} - ${sale.dtUPDATED} à ${sale.heure}"),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text("${sale.intPRICE} FCFA", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primary)),
                    Text(sale.strSTATUT, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
                onTap: () => _openSale(sale.lgPREENREGISTREMENTID),
              ),
            );
          },
        ),
      ),
    );
  }
}