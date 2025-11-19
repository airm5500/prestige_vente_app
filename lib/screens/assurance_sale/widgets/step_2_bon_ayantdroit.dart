// lib/screens/assurance_sale/widgets/step_2_bon_ayantdroit.dart
// 10/11/2025 17:00 (Correction Focus après modification)
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/api/models/ayant_droit.dart';
import 'package:prestige_vente_app/api/models/client_assurance.dart';
import 'package:prestige_vente_app/providers/assurance_sale_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';
import 'add_tiers_payant_dialog.dart';
import 'create_ayant_droit_dialog.dart';
//import 'package:prestige_vente_app/api/models/tiers_payant_assurance.dart';

class Step2BonAyantDroitWidget extends StatefulWidget {
  const Step2BonAyantDroitWidget({super.key});

  @override
  State<Step2BonAyantDroitWidget> createState() =>
      _Step2BonAyantDroitWidgetState();
}

class _Step2BonAyantDroitWidgetState extends State<Step2BonAyantDroitWidget> {
  final Map<String, TextEditingController> _bonControllers = {};
  final Map<String, FocusNode> _bonFocusNodes = {};

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);
    _initializeControllers(provider);

    // Focus automatique sur le premier champ ACTIF (le nouveau) au démarrage
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if(mounted) {
        _focusFirstActiveTp(provider);
      }
    });
  }

  // Fonction helper pour mettre le focus sur le premier TP actif
  void _focusFirstActiveTp(AssuranceSaleProvider provider) {
    if (provider.selectedClient != null && provider.activeTiersPayants.isNotEmpty) {
      final activeTp = provider.activeTiersPayants.first;
      final node = _bonFocusNodes[activeTp.compteTp];
      if (node != null) {
        FocusScope.of(context).requestFocus(node);
      }
    }
  }

  void _initializeControllers(AssuranceSaleProvider provider) {
    if (provider.selectedClient == null) return;

    for (var tp in provider.selectedClient!.tiersPayants) {
      if (!_bonControllers.containsKey(tp.compteTp)) {
        _bonControllers[tp.compteTp] = TextEditingController(
            text: provider.bonNumbers[tp.compteTp] ?? ""
        );
      }
      if (!_bonFocusNodes.containsKey(tp.compteTp)) {
        _bonFocusNodes[tp.compteTp] = FocusNode();
      }
    }
  }

  @override
  void dispose() {
    _bonControllers.forEach((_, controller) => controller.dispose());
    _bonFocusNodes.forEach((_, node) => node.dispose());
    super.dispose();
  }

  Future<void> _confirmReturnToClientSearch(BuildContext context) async {
    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);
    bool hasData = provider.cartItems.isNotEmpty || _bonControllers.values.any((c) => c.text.isNotEmpty);

    if (!hasData) {
      provider.returnToClientSearch();
      return;
    }

    final bool? quit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitter la vente ?'),
        content: const Text('Toute votre saisie (bons, panier) sera perdue. Voulez-vous continuer ?'),
        actions: [
          TextButton(
            child: const Text('Non'),
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          ElevatedButton(
            child: const Text('Oui, quitter'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (quit == true) {
      provider.returnToClientSearch();
    }
  }

  void _showCreateAyantDroitDialog() {
    showDialog(
      context: context,
      builder: (ctx) => const CreateAyantDroitDialog(),
    );
  }

  void _showAddTiersPayantDialog() {
    showDialog(
      context: context,
      builder: (ctx) => const AddTiersPayantDialog(),
    );
  }

  // MODIFICATION : Ajout de la logique de re-focus après fermeture
  void _showEditTpDialog(ActiveTiersPayant activeTp) {
    showDialog(
      context: context,
      builder: (ctx) => EditTiersPayantDialog(activeTp: activeTp),
    ).then((_) {
      // Une fois le dialogue fermé (et la modification potentiellement faite)
      // On force le focus sur le nouveau TP (qui est en 1ère position)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);
          _focusFirstActiveTp(provider);
        }
      });
    });
  }

  void _validateAndProceed() {
    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);
    provider.clearError();

    if (provider.activeTiersPayants.isEmpty) {
      Constants.showSnackBar(context, "Veuillez activer au moins un tiers payant pour cette vente.", isError: true);
      return;
    }

    _bonControllers.forEach((compteTp, controller) {
      if (provider.activeTiersPayants.any((atp) => atp.compteTp == compteTp)) {
        provider.updateBonNumber(compteTp, controller.text.trim());
      }
    });

    for (var tp in provider.activeTiersPayants) {
      if (provider.bonNumbers[tp.compteTp]?.isEmpty ?? true) {
        Constants.showSnackBar(context, "Le N° de bon pour ${tp.tpFullName} est requis.", isError: true);

        final focusNode = _bonFocusNodes[tp.compteTp];
        if (focusNode != null) {
          FocusScope.of(context).requestFocus(focusNode);
        }
        return;
      }
    }

    provider.validateBonsAndProceed();
  }


  @override
  Widget build(BuildContext context) {
    return Consumer<AssuranceSaleProvider>(
        builder: (context, provider, child) {

          final settings = Provider.of<SettingsProvider>(context, listen: false);
          final client = provider.selectedClient;

          if (client == null) {
            return const Center(
                child: Text("Aucun client sélectionné. Veuillez recommencer."));
          }

          _initializeControllers(provider);

          final bool canAddTiersPayant = client.tiersPayants.length < settings.maxTiersPayants;
          final bool canToggleTiersPayant = client.tiersPayants.length > 1;

          AyantDroit? validSelectedAyantDroit = provider.selectedAyantDroit;
          if (validSelectedAyantDroit != null && !provider.ayantDroitList.contains(validSelectedAyantDroit)) {
            validSelectedAyantDroit = null;
          }
          if (validSelectedAyantDroit == null && provider.ayantDroitList.isNotEmpty) {
            validSelectedAyantDroit = provider.ayantDroitList.first;

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if(mounted) {
                provider.selectAyantDroit(validSelectedAyantDroit);
              }
            });
          }

          final sortedTiersPayants = List<ClientTiersPayant>.from(client.tiersPayants);
          sortedTiersPayants.sort((a, b) {
            final isActiveA = provider.activeTiersPayants.any((atp) => atp.compteTp == a.compteTp);
            final isActiveB = provider.activeTiersPayants.any((atp) => atp.compteTp == b.compteTp);

            if (isActiveA && !isActiveB) return -1;
            if (!isActiveA && isActiveB) return 1;

            return a.order.compareTo(b.order);
          });


          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  elevation: 2,
                  child: ListTile(
                    leading: const Icon(Icons.person, color: AppColors.primary),
                    title: Text(client.fullName,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Matricule: ${client.strNUMEROSECURITESOCIAL}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Changer de client',
                      onPressed: () => _confirmReturnToClientSearch(context),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Text('1. Sélectionner un Ayant Droit (Patient)',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<AyantDroit>(
                        value: validSelectedAyantDroit,
                        decoration: const InputDecoration(
                          labelText: 'Ayant Droit',
                          border: OutlineInputBorder(),
                        ),
                        isExpanded: true,
                        items: provider.ayantDroitList.map((AyantDroit ad) {
                          return DropdownMenuItem<AyantDroit>(
                            value: ad,
                            child: Text(
                              '${ad.fullName} (${ad.strNUMEROSECURITESOCIAL})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (AyantDroit? newValue) {
                          if (newValue != null) {
                            provider.selectAyantDroit(newValue);
                          }
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, color: AppColors.secondary),
                      tooltip: 'Créer un nouvel ayant droit',
                      onPressed: _showCreateAyantDroitDialog,
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                Text('2. Gérer les Tiers Payants et N° de Bon',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),

                ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: sortedTiersPayants.length,
                    itemBuilder: (context, index) {
                      final tp = sortedTiersPayants[index];

                      final activeTp = provider.activeTiersPayants.firstWhere(
                              (atp) => atp.originalData.compteTp == tp.compteTp,
                          orElse: () => ActiveTiersPayant(originalData: tp, taux: tp.taux)
                      );
                      final bool isActive = provider.activeTiersPayants.indexWhere((atp) => atp.originalData.compteTp == tp.compteTp) != -1;

                      final controller = _bonControllers[tp.compteTp];
                      final focusNode = _bonFocusNodes[tp.compteTp];

                      if (controller == null || focusNode == null) {
                        return Card(child: Text("Erreur: ${tp.tpFullName}"));
                      }

                      return Card(
                        color: isActive ? Colors.white : Colors.grey[200],
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          children: [
                            CheckboxListTile(
                              title: Text('${tp.tpFullName} (${isActive ? activeTp.taux : tp.taux}%)', style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('Matricule: ${tp.numSecurity}'),
                              value: isActive,
                              onChanged: canToggleTiersPayant
                                  ? (bool? value) {
                                provider.toggleTiersPayant(tp, value ?? false);
                              }
                                  : null,

                              secondary: isActive ? IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blueAccent),
                                tooltip: 'Modifier le tiers payant',
                                onPressed: () => _showEditTpDialog(activeTp),
                              ) : null,
                            ),
                            if (isActive)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                child: TextFormField(
                                  focusNode: focusNode,
                                  controller: controller,
                                  autofocus: index == 0,
                                  decoration: InputDecoration(
                                    labelText: 'N° Bon pour ${tp.tpFullName}',
                                    border: const OutlineInputBorder(),
                                  ),
                                  textInputAction: TextInputAction.next,
                                  onFieldSubmitted: (_) => _validateAndProceed(),
                                  onTapOutside: (_) {
                                    provider.updateBonNumber(tp.compteTp, controller.text.trim());
                                  },
                                ),
                              ),
                          ],
                        ),
                      );
                    }
                ),

                TextButton.icon(
                  icon: const Icon(Icons.add_card),
                  label: const Text('Ajouter un Tiers Payant au client'),
                  onPressed: canAddTiersPayant ? _showAddTiersPayantDialog : null,
                ),
                if (!canAddTiersPayant)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text(
                      'Nombre maximum de tiers payants (${settings.maxTiersPayants}) atteint.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),

                const SizedBox(height: 24),

                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () {
                    _validateAndProceed();
                  },
                  child: const Text('Continuer vers la saisie des produits'),
                ),
              ],
            ),
          );
        });
  }
}

class EditTiersPayantDialog extends StatefulWidget {
  final ActiveTiersPayant activeTp;

  const EditTiersPayantDialog({super.key, required this.activeTp});

  @override
  State<EditTiersPayantDialog> createState() => _EditTiersPayantDialogState();
}

class _EditTiersPayantDialogState extends State<EditTiersPayantDialog> {
  final _tauxController = TextEditingController();
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  Timer? _debounce;

  dynamic _selectedNewTp;
  bool _isSearchMode = false;

  @override
  void initState() {
    super.initState();
    _tauxController.text = widget.activeTp.taux.toString();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _tauxController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (_searchController.text.length >= 3) {
        provider.searchTiersPayantAssurance(_searchController.text);
      }
    });
  }

  Future<void> _submit() async {
    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);
    final int? newTaux = int.tryParse(_tauxController.text);

    if (newTaux == null || newTaux < 0 || newTaux > 100) {
      Constants.showSnackBar(context, "Taux invalide (0-100)", isError: true);
      return;
    }

    if (_selectedNewTp != null) {
      final success = await provider.replaceTiersPayant(widget.activeTp, _selectedNewTp, newTaux);
      if (mounted && success) Navigator.of(context).pop();
    } else {
      provider.updateTiersPayantTaux(widget.activeTp.compteTp, newTaux);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AssuranceSaleProvider>(context);

    return AlertDialog(
      title: const Text('Modifier Tiers Payant'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_isSearchMode) ...[
              Text(widget.activeTp.tpFullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              TextButton(
                  onPressed: () {
                    setState(() {
                      _isSearchMode = true;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _searchFocusNode.requestFocus();
                      });
                    });
                  },
                  child: const Text("Changer l'assurance")
              ),
            ] else ...[
              DropdownMenu<dynamic>(
                controller: _searchController,
                focusNode: _searchFocusNode,
                label: const Text('Rechercher nouvelle assurance'),
                expandedInsets: EdgeInsets.zero,
                enableFilter: true,
                enableSearch: true,
                dropdownMenuEntries: provider.tiersPayantSearchResults.map((tp) {
                  return DropdownMenuEntry<dynamic>(
                    value: tp,
                    label: tp.strFULLNAME,
                  );
                }).toList(),
                onSelected: (dynamic selection) {
                  setState(() {
                    _selectedNewTp = selection;
                    _searchController.text = selection?.strFULLNAME ?? "";
                  });
                },
              ),
              if (_selectedNewTp != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text("Nouveau: ${_selectedNewTp.strFULLNAME}", style: const TextStyle(color: AppColors.success)),
                ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _tauxController,
              decoration: const InputDecoration(labelText: 'Taux %'),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          child: const Text('Annuler'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        if (provider.isLoading)
          const CircularProgressIndicator()
        else
          ElevatedButton(
            onPressed: _submit,
            child: const Text('Valider'),
          ),
      ],
    );
  }
}