// lib/screens/bl_control/bl_list_screen.dart
// 18/10/2025 16:12
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/providers/bl_control_provider.dart';
import 'package:prestige_vente_app/screens/bl_control/bl_detail_screen.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

class BlListScreen extends StatefulWidget {
  const BlListScreen({super.key});

  @override
  State<BlListScreen> createState() => _BlListScreenState();
}

class _BlListScreenState extends State<BlListScreen> {
  final _searchController = TextEditingController();
  final _dtStartController = TextEditingController();
  final _dtEndController = TextEditingController();

  String? _dtStart; // Format YYYY-MM-DD
  String? _dtEnd;   // Format YYYY-MM-DD

  @override
  void initState() {
    super.initState();
    // On met les dates du jour par défaut
    final now = DateTime.now();
    _setDate(now, _dtStartController, (val) => _dtStart = val);
    _setDate(now, _dtEndController, (val) => _dtEnd = val);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchData();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _dtStartController.dispose();
    _dtEndController.dispose();
    super.dispose();
  }

  void _fetchData() {
    Provider.of<BlControlProvider>(context, listen: false).fetchBonsLivraison(
      query: _searchController.text,
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
    return Scaffold(
      appBar: AppBar(title: const Text('Bons de Livraison')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Rechercher par N° de BL...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _fetchData();
                  },
                ),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _fetchData(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _dtStartController,
                    readOnly: true,
                    decoration: const InputDecoration(labelText: 'Date Début', suffixIcon: Icon(Icons.calendar_today)),
                    onTap: () => _selectDate(context, _dtStartController, (val) => _dtStart = val),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _dtEndController,
                    readOnly: true,
                    decoration: const InputDecoration(labelText: 'Date Fin', suffixIcon: Icon(Icons.calendar_today)),
                    onTap: () => _selectDate(context, _dtEndController, (val) => _dtEnd = val),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _fetchData,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Consumer<BlControlProvider>(
              builder: (context, provider, child) {
                if (provider.isLoading && provider.bonsLivraison.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (provider.bonsLivraison.isEmpty) {
                  return const Center(child: Text('Aucun bon de livraison trouvé.'));
                }
                return RefreshIndicator(
                  onRefresh: () async => _fetchData(),
                  child: ListView.builder(
                    itemCount: provider.bonsLivraison.length,
                    itemBuilder: (context, index) {
                      final bl = provider.bonsLivraison[index];
                      final isCompleted = provider.isBlCompleted(bl.id);
                      final isInProgress = provider.isBlInProgress(bl.id);

                      Color? cardColor;
                      IconData iconData;
                      Color iconColor;

                      if (isCompleted) {
                        cardColor = Colors.green.shade50;
                        iconData = Icons.check_circle;
                        iconColor = AppColors.success;
                      } else if (isInProgress) {
                        cardColor = Colors.orange.shade50;
                        iconData = Icons.pending_actions;
                        iconColor = Colors.orange;
                      } else {
                        cardColor = null;
                        iconData = Icons.receipt_long;
                        iconColor = AppColors.primary;
                      }

                      return Card(
                        color: cardColor,
                        child: ListTile(
                          leading: Icon(iconData, color: iconColor),
                          title: Text('${bl.ref} - ${bl.grossiste}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${bl.date} - ${bl.nbreLignes} lignes'),
                          trailing: Text(
                            Constants.formatNumber(bl.montantTotal),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.secondary),
                          ),
                          onTap: () async {
                            await provider.selectBonLivraison(bl);
                            if (mounted) {
                              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BlDetailScreen()));
                              if (mounted) {
                                _fetchData();
                              }
                            }
                          },
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}