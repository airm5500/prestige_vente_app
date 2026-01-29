import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/proforma_models.dart';
import 'package:prestige_vente_app/providers/proforma_provider.dart';
import 'package:prestige_vente_app/screens/proforma/proforma_screen.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:intl/intl.dart';

class ProformaListScreen extends StatefulWidget {
  const ProformaListScreen({Key? key}) : super(key: key);

  @override
  State<ProformaListScreen> createState() => _ProformaListScreenState();
}

class _ProformaListScreenState extends State<ProformaListScreen> {
  List<ProformaListItem> _proformas = [];
  bool _isLoading = true;
  final String _today = DateFormat('yyyy-MM-dd').format(DateTime.now());

  @override
  void initState() {
    super.initState();
    _loadProformas();
  }

  Future<void> _loadProformas() async {
    setState(() => _isLoading = true);
    final api = Provider.of<ApiService>(context, listen: false);
    final list = await api.fetchProformas(dtStart: _today, dtEnd: _today);
    if (mounted) {
      setState(() {
        _proformas = list;
        _isLoading = false;
      });
    }
  }

  // --- CORRECTION 1 : La fonction accepte maintenant l'objet entier ---
  void _openProforma(ProformaListItem? item) async {
    final provider = Provider.of<ProformaProvider>(context, listen: false);
    provider.resetSale();

    if (item != null) {
      // On passe l'objet item entier au provider
      await provider.loadExistingProforma(item);
    }

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProformaScreen()),
    );
    _loadProformas();
  }

  String _formatCurrency(int amount) {
    return amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]} ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Liste Proformas / Devis")),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openProforma(null), // Null pour une nouvelle vente
        label: const Text("Nouveau Devis"),
        icon: const Icon(Icons.add),
        backgroundColor: AppColors.primary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _proformas.isEmpty
          ? const Center(child: Text("Aucun devis trouvé pour aujourd'hui"))
          : RefreshIndicator(
        onRefresh: _loadProformas,
        child: ListView.builder(
          itemCount: _proformas.length,
          itemBuilder: (context, index) {
            final item = _proformas[index];
            final bool isGreen = item.strSTATUT == 'is_Process' || item.strSTATUT == 'devis';

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.purple.shade100,
                  child: const Icon(Icons.description, color: Colors.purple),
                ),
                title: Text(item.strClientFullName, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Réf: ${item.strREF} - ${item.heure}"),
                    if (item.userFullName.isNotEmpty)
                      Text("Vendeur: ${item.userFullName}", style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                  ],
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text("${_formatCurrency(item.intPRICE)} F", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primary)),
                    Text(
                      item.strSTATUT,
                      style: TextStyle(
                          fontSize: 12,
                          color: isGreen ? Colors.green : Colors.grey,
                          fontWeight: FontWeight.bold
                      ),
                    ),
                  ],
                ),
                // --- CORRECTION 2 : On passe l'objet 'item', pas l'ID string ---
                onTap: () => _openProforma(item),
              ),
            );
          },
        ),
      ),
    );
  }
}