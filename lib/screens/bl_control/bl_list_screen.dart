// lib/screens/bl_control/bl_list_screen.dart
// 19/10/2025 00:50
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/api/models/bon_livraison.dart';
import 'package:prestige_vente_app/providers/bl_control_provider.dart';
import 'package:prestige_vente_app/screens/bl_control/bl_detail_screen.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

class BlListScreen extends StatefulWidget {
  // MODIFICATION : Accepte un filtre initial
  final String? initialFilter;

  const BlListScreen({super.key, this.initialFilter});

  @override
  State<BlListScreen> createState() => _BlListScreenState();
}

class _BlListScreenState extends State<BlListScreen> {
  final _searchController = TextEditingController();
  final _dtStartController = TextEditingController();
  final _dtEndController = TextEditingController();

  String? _dtStart;
  String? _dtEnd;

  // MODIFICATION : État pour les ToggleButtons (0: À Traiter, 1: Terminés, 2: Tous)
  List<bool> _isSelected = [true, false, false];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _setDate(now, _dtStartController, (val) => _dtStart = val);
    _setDate(now, _dtEndController, (val) => _dtEnd = val);

    // Applique le filtre initial si fourni
    if (widget.initialFilter == 'A_TRAITER') {
      _isSelected = [true, false, false]; // "À Traiter"
    }

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
          // MODIFICATION : Zone de filtres réorganisée et réduite
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: 'Rechercher par N° de BL...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () { _searchController.clear(); _fetchData(); },
                    ),
                    isDense: true, // Réduit la hauteur
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _fetchData(),
                ),
                const SizedBox(height: 8),
                Row(
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
                const SizedBox(height: 8),
                ToggleButtons(
                  isSelected: _isSelected,
                  onPressed: (index) {
                    setState(() {
                      for (int i = 0; i < _isSelected.length; i++) {
                        _isSelected[i] = i == index;
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  constraints: BoxConstraints.expand(width: (MediaQuery.of(context).size.width / 3.5), height: 36),
                  children: const [
                    Text('À Traiter'),
                    Text('Terminés'),
                    Text('Tous'),
                  ],
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

                // MODIFICATION : Logique de filtrage locale
                List<BonLivraison> filteredList = provider.bonsLivraison;
                if (_isSelected[0]) { // À Traiter
                  filteredList = provider.bonsLivraison.where((bl) => bl.statutTraitement != 'TERMINE').toList();
                } else if (_isSelected[1]) { // Terminés
                  filteredList = provider.bonsLivraison.where((bl) => bl.statutTraitement == 'TERMINE').toList();
                }
                // Si _isSelected[2] (Tous), on n'applique pas de filtre

                if (filteredList.isEmpty) {
                  return const Center(child: Text('Aucun bon de livraison trouvé.'));
                }

                return RefreshIndicator(
                  onRefresh: () async => _fetchData(),
                  child: ListView.builder(
                    itemCount: filteredList.length,
                    itemBuilder: (context, index) {
                      final bl = filteredList[index];
                      final isCompleted = bl.statutTraitement == "TERMINE";
                      final isInProgress = bl.statutTraitement == "EN_COURS";

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
                      } else { // A_FAIRE
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