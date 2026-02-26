// lib/screens/bl_control/bl_list_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/api/models/bon_livraison.dart';
import 'package:prestige_vente_app/providers/bl_control_provider.dart';
import 'package:prestige_vente_app/screens/bl_control/bl_detail_screen.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

class BlListScreen extends StatefulWidget {
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

  List<bool> _isSelected = [true, false, false];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _setDate(now, _dtStartController, (val) => _dtStart = val);
    _setDate(now, _dtEndController, (val) => _dtEnd = val);

    if (widget.initialFilter == 'A_TRAITER') {
      _isSelected = [true, false, false];
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchData(); // Chargement initial silencieux
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _dtStartController.dispose();
    _dtEndController.dispose();
    super.dispose();
  }

  // Requête silencieuse (utilisée à l'ouverture ou au pull-to-refresh)
  Future<void> _fetchData() async {
    await Provider.of<BlControlProvider>(context, listen: false).fetchBonsLivraison(
      query: _searchController.text,
      dtStart: _dtStart,
      dtEnd: _dtEnd,
    );
  }

  // --- NOUVEAUTÉ : Recherche avec Popup bloquant ---
  Future<void> _searchWithPopup() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return const Dialog(
          child: Padding(
            padding: EdgeInsets.all(20.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text("Recherche en cours..."),
              ],
            ),
          ),
        );
      },
    );

    try {
      await _fetchData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Erreur réseau"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        Navigator.of(context).pop(); // Ferme le popup une fois la recherche finie
      }
    }
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
                      onPressed: () {
                        _searchController.clear();
                        _searchWithPopup(); // On relance la recherche bloquante
                      },
                    ),
                    isDense: true,
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _searchWithPopup(), // Recherche via la touche "Entrée" du clavier
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
                      onPressed: _searchWithPopup, // Recherche bloquante via le bouton
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

                List<BonLivraison> filteredList = provider.bonsLivraison;
                if (_isSelected[0]) {
                  filteredList = provider.bonsLivraison.where((bl) => bl.statutTraitement != 'TERMINE').toList();
                } else if (_isSelected[1]) {
                  filteredList = provider.bonsLivraison.where((bl) => bl.statutTraitement == 'TERMINE').toList();
                }

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
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (BuildContext dialogContext) {
                                return const Dialog(
                                  child: Padding(
                                    padding: EdgeInsets.all(20.0),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        CircularProgressIndicator(),
                                        SizedBox(width: 20),
                                        Text("Ouverture du BL en cours..."),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );

                            try {
                              await provider.selectBonLivraison(bl);

                              if (context.mounted) {
                                Navigator.of(context).pop();
                              }

                              if (context.mounted) {
                                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BlDetailScreen()));

                                if (context.mounted) {
                                  _fetchData();
                                }
                              }
                            } catch (e) {
                              if (context.mounted) {
                                Navigator.of(context).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("Erreur lors de l'ouverture du BL. Vérifiez le réseau."),
                                    backgroundColor: Colors.red,
                                  ),
                                );
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