// lib/screens/perimes/tabs/historique_saisies_tab.dart
// 09/11/2025 18:45 (Ajout filtres date Pémimés)
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/providers/perime_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

class HistoriqueSaisiesTab extends StatefulWidget {
  const HistoriqueSaisiesTab({super.key});

  @override
  State<HistoriqueSaisiesTab> createState() => _HistoriqueSaisiesTabState();
}

class _HistoriqueSaisiesTabState extends State<HistoriqueSaisiesTab> {
  // MODIFICATION : Ajout des filtres
  final _dtStartController = TextEditingController();
  final _dtEndController = TextEditingController();
  String? _dtStart;
  String? _dtEnd;

  @override
  void initState() {
    super.initState();
    // Par défaut, charge les données du jour
    final now = DateTime.now();
    _setDate(now, _dtStartController, (val) => _dtStart = val);
    _setDate(now, _dtEndController, (val) => _dtEnd = val);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchData();
    });
  }

  @override
  void dispose() {
    _dtStartController.dispose();
    _dtEndController.dispose();
    super.dispose();
  }

  void _fetchData() {
    Provider.of<PerimeProvider>(context, listen: false).loadSaisieHistory(
      dtStart: _dtStart,
      dtEnd: _dtEnd,
    );
  }

  Future<void> _selectDate(BuildContext context, TextEditingController controller, Function(String) onDateSelected) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2101),
    );
    if (picked != null) {
      _setDate(picked, controller, onDateSelected);
    }
  }

  void _setDate(DateTime date, TextEditingController controller, Function(String) onDateSelected) {
    setState(() {
      controller.text = DateFormat('dd/MM/yyyy').format(date);
      onDateSelected(DateFormat('yyyy-MM-dd').format(date));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // MODIFICATION : Ajout de la barre de filtres
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _dtStartController,
                  readOnly: true,
                  decoration: const InputDecoration(labelText: 'Date Début', suffixIcon: Icon(Icons.calendar_today), isDense: true),
                  onTap: () => _selectDate(context, _dtStartController, (val) => _dtStart = val),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _dtEndController,
                  readOnly: true,
                  decoration: const InputDecoration(labelText: 'Date Fin', suffixIcon: Icon(Icons.calendar_today), isDense: true),
                  onTap: () => _selectDate(context, _dtEndController, (val) => _dtEnd = val),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: _fetchData,
                style: IconButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              ),
            ],
          ),
        ),
        // FIN MODIFICATION

        Expanded(
          child: Consumer<PerimeProvider>(
            builder: (context, provider, child) {
              if (provider.isLoading && provider.saisieHistoryList.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }

              if (provider.saisieHistoryList.isEmpty) {
                return const Center(child: Text('Aucun historique de saisie pour cette période.'));
              }

              return RefreshIndicator(
                onRefresh: () async => _fetchData(),
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
          ),
        ),
      ],
    );
  }
}