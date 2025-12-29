// lib/screens/reception_control/reception_list_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/api/models/reception_model.dart';
import 'package:prestige_vente_app/providers/reception_provider.dart';
import 'package:prestige_vente_app/screens/reception_control/reception_detail_screen.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

class ReceptionListScreen extends StatefulWidget {
  const ReceptionListScreen({super.key});

  @override
  State<ReceptionListScreen> createState() => _ReceptionListScreenState();
}

class _ReceptionListScreenState extends State<ReceptionListScreen> {
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchData();
    });
  }

  Future<void> _fetchData() async {
    final startStr = DateFormat('yyyy-MM-dd').format(_startDate);
    final endStr = DateFormat('yyyy-MM-dd').format(_endDate);
    await Provider.of<ReceptionProvider>(context, listen: false)
        .fetchReceptionBons(dtStart: startStr, dtEnd: endStr, query: _searchController.text);
  }

  Future<void> _selectDate(BuildContext context, bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        if (isStart) _startDate = picked; else _endDate = picked;
      });
      _fetchData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Contrôle Réception"),
          bottom: const TabBar(
            tabs: [
              Tab(text: "À FAIRE / EN COURS"),
              Tab(text: "TERMINÉS"),
            ],
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
          ),
        ),
        body: Column(
          children: [
            // Filtres Dates et Recherche
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today),
                          label: Text(DateFormat('dd/MM/yyyy').format(_startDate)),
                          onPressed: () => _selectDate(context, true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(Icons.arrow_forward, color: Colors.grey),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today),
                          label: Text(DateFormat('dd/MM/yyyy').format(_endDate)),
                          onPressed: () => _selectDate(context, false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: "Rechercher un bon...",
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: _fetchData,
                      ),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _fetchData(),
                  ),
                ],
              ),
            ),

            Expanded(
              child: Consumer<ReceptionProvider>(
                builder: (context, provider, child) {
                  if (provider.isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  return TabBarView(
                    children: [
                      // Onglet À FAIRE
                      RefreshIndicator(
                        onRefresh: _fetchData,
                        child: _buildBonList(provider.bonsAFaire),
                      ),
                      // Onglet TERMINÉS
                      RefreshIndicator(
                        onRefresh: _fetchData,
                        child: _buildBonList(provider.bonsTermines),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBonList(List<ReceptionBon> bons) {
    if (bons.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 50),
          Center(child: Text("Aucun bon trouvé pour cette période."))
        ],
      );
    }
    return ListView.builder(
      itemCount: bons.length,
      itemBuilder: (context, index) {
        final bon = bons[index];
        final isTermine = bon.statutTraitement == "TERMINE";
        final isEnCours = bon.statutTraitement == "EN_COURS";

        // Couleur de la carte
        Color? cardColor;
        if (isTermine) {
          cardColor = Colors.green.shade50;
        } else if (isEnCours) {
          cardColor = Colors.orange.shade50;
        } else {
          cardColor = Colors.white;
        }

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          elevation: 2,
          color: cardColor,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isTermine ? Colors.green.shade100 : (isEnCours ? Colors.orange.shade100 : Colors.grey.shade200),
              child: Icon(
                isTermine ? Icons.check : (isEnCours ? Icons.sync : Icons.inventory_2_outlined),
                color: isTermine ? Colors.green : (isEnCours ? Colors.deepOrange : Colors.grey),
              ),
            ),
            title: Text(bon.ref, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(bon.grossiste),
                Text("Livraison: ${bon.dateLivraison}", style: const TextStyle(fontSize: 12)),
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text("${bon.nbreLignes} lignes"),
                Text(Constants.formatNumber(bon.montantHt), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
              ],
            ),
            onTap: () {
              Provider.of<ReceptionProvider>(context, listen: false).selectBon(bon);

              // Modification ici : on actualise la liste au retour
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReceptionDetailScreen()),
              ).then((_) {
                _fetchData(); // Rafraichit la liste au retour
              });
            },
          ),
        );
      },
    );
  }
}