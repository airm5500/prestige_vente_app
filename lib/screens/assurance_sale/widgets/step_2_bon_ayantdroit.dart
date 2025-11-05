// lib/screens/assurance_sale/widgets/step_2_bon_ayantdroit.dart
// 05/11/2025 01:30 (Corrigé)
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

class Step2BonAyantDroitWidget extends StatefulWidget {
  const Step2BonAyantDroitWidget({super.key});

  @override
  State<Step2BonAyantDroitWidget> createState() =>
      _Step2BonAyantDroitWidgetState();
}

class _Step2BonAyantDroitWidgetState extends State<Step2BonAyantDroitWidget> {
  late Map<String, TextEditingController> _bonControllers;
  FocusNode? _firstBonFocusNode;

  @override
  void initState() {
    super.initState();
    _bonControllers = {};
    final provider =
    Provider.of<AssuranceSaleProvider>(context, listen: false);

    _updateControllers(provider);

    // MODIFICATION (Point 2.5) - Met le focus sur le premier champ de bon
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if(mounted) {
        FocusScope.of(context).requestFocus(_firstBonFocusNode);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Met à jour les controllers si la liste des TP actifs change
    final provider = Provider.of<AssuranceSaleProvider>(context, listen: true);
    _updateControllers(provider);
  }

  void _updateControllers(AssuranceSaleProvider provider) {
    if (provider.selectedClient != null) {
      final activeComptesTp = provider.activeTiersPayants.map((tp) => tp.compteTp).toSet();

      _bonControllers.removeWhere((key, controller) {
        if (!activeComptesTp.contains(key)) {
          controller.dispose();
          return true;
        }
        return false;
      });

      _firstBonFocusNode = null;

      for (var tp in provider.activeTiersPayants) {
        if (!_bonControllers.containsKey(tp.compteTp)) {
          _bonControllers[tp.compteTp] =
              TextEditingController(text: provider.bonNumbers[tp.compteTp] ?? "");
        }
        // Assigne le focus node au premier champ actif
        if (_firstBonFocusNode == null) {
          _firstBonFocusNode = FocusNode();
        }
      }
    }
  }


  @override
  void dispose() {
    _bonControllers.forEach((_, controller) => controller.dispose());
    _firstBonFocusNode?.dispose(); // (Point 2.5)
    super.dispose();
  }

  // MODIFICATION (Point 9) - Confirmation avant de quitter
  Future<void> _confirmReturnToClientSearch(BuildContext context) async {
    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);

    // On vérifie si un bon est saisi OU si le panier n'est pas vide
    bool hasData = provider.cartItems.isNotEmpty || provider.bonNumbers.values.any((bon) => bon.isNotEmpty);

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

  // MODIFICATION (Point 4) - Dialogue pour modifier le taux
  void _showEditTauxDialog(ActiveTiersPayant activeTp) {
    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);
    final tauxController = TextEditingController(text: activeTp.taux.toString());

    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Modifier Taux: ${activeTp.tpFullName}'),
          content: TextFormField(
            controller: tauxController,
            decoration: const InputDecoration(labelText: 'Nouveau Taux %'),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            autofocus: true,
          ),
          actions: [
            TextButton(
              child: const Text('Annuler'),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
            ElevatedButton(
              child: const Text('Valider'),
              onPressed: () {
                final int? newTaux = int.tryParse(tauxController.text);
                if (newTaux != null && newTaux >= 0 && newTaux <= 100) {
                  provider.updateTiersPayantTaux(activeTp.compteTp, newTaux);
                  Navigator.of(ctx).pop();
                } else {
                  Constants.showSnackBar(context, "Taux invalide (0-100)", isError: true);
                }
              },
            )
          ],
        )
    );
  }


  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AssuranceSaleProvider>(context);
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final client = provider.selectedClient;

    if (client == null) {
      return const Center(
          child: Text("Aucun client sélectionné. Veuillez recommencer."));
    }

    // MODIFICATION (Point 5)
    final bool canAddTiersPayant = client.tiersPayants.length < settings.maxTiersPayants;

    // (Correction Erreur Point 4) - S'assure que la valeur sélectionnée est valide
    AyantDroit? validSelectedAyantDroit = provider.selectedAyantDroit;
    if (validSelectedAyantDroit != null && !provider.ayantDroitList.contains(validSelectedAyantDroit)) {
      validSelectedAyantDroit = null;
    }
    if (validSelectedAyantDroit == null && provider.ayantDroitList.isNotEmpty) {
      validSelectedAyantDroit = provider.ayantDroitList.first;
      provider.selectAyantDroit(validSelectedAyantDroit);
    }


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
                onPressed: () => _confirmReturnToClientSearch(context), // (Point 9)
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
                // (Correction Erreur Point 4)
                child: DropdownButtonFormField<AyantDroit>(
                  value: validSelectedAyantDroit,
                  decoration: const InputDecoration(
                    labelText: 'Ayant Droit',
                    border: OutlineInputBorder(),
                  ),
                  items: provider.ayantDroitList.map((AyantDroit ad) {
                    return DropdownMenuItem<AyantDroit>(
                      value: ad,
                      child: Text(
                          '${ad.fullName} (${ad.strNUMEROSECURITESOCIAL})'),
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

          // MODIFICATION (Point 4) - Liste dynamique avec Checkbox
          ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: client.tiersPayants.length,
              itemBuilder: (context, index) {
                final tp = client.tiersPayants[index];
                final activeTp = provider.activeTiersPayants.firstWhere(
                        (atp) => atp.originalData.compteTp == tp.compteTp,
                    orElse: () => ActiveTiersPayant(originalData: tp, taux: tp.taux) // Crée un factice
                );
                final bool isActive = provider.activeTiersPayants.indexWhere((atp) => atp.originalData.compteTp == tp.compteTp) != -1;

                return Card(
                  color: isActive ? Colors.white : Colors.grey[200],
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    children: [
                      CheckboxListTile(
                        title: Text('${tp.tpFullName} (${isActive ? activeTp.taux : tp.taux}%)', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Matricule: ${tp.numSecurity}'),
                        value: isActive,
                        onChanged: (bool? value) {
                          provider.toggleTiersPayant(tp, value ?? false);
                        },
                        // (Point 4) - Bouton Modifier Taux
                        secondary: isActive ? IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blueAccent),
                          tooltip: 'Modifier le taux pour cette vente',
                          onPressed: () => _showEditTauxDialog(activeTp),
                        ) : null,
                      ),
                      if (isActive)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: TextFormField(
                            focusNode: index == 0 ? _firstBonFocusNode : null, // (Point 2.5)
                            controller: _bonControllers[tp.compteTp],
                            decoration: InputDecoration(
                              labelText: 'N° Bon pour ${tp.tpFullName}',
                              border: const OutlineInputBorder(),
                            ),
                            onChanged: (value) {
                              provider.updateBonNumber(tp.compteTp, value);
                            },
                            textInputAction: TextInputAction.next,
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
            onPressed: canAddTiersPayant ? _showAddTiersPayantDialog : null, // (Point 5)
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
              provider.validateBonsAndProceed();
            },
            child: const Text('Continuer vers la saisie des produits'),
          ),
        ],
      ),
    );
  }
}