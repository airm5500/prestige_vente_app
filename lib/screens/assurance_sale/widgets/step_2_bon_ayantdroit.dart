// lib/screens/assurance_sale/widgets/step_2_bon_ayantdroit.dart
// 02/11/2025 15:40
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/ayant_droit.dart';
import 'package:prestige_vente_app/providers/assurance_sale_provider.dart';
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
  // Map pour lier les controllers aux champs de texte des N° de bon
  late Map<String, TextEditingController> _bonControllers;

  @override
  void initState() {
    super.initState();
    _bonControllers = {};
    final provider =
    Provider.of<AssuranceSaleProvider>(context, listen: false);

    // Initialise les controllers pour chaque tiers payant du client
    if (provider.selectedClient != null) {
      for (var tp in provider.selectedClient!.tiersPayants) {
        _bonControllers[tp.compteTp] =
            TextEditingController(text: provider.bonNumbers[tp.compteTp] ?? "");
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Met à jour les controllers si le client change (ex: ajout d'un nouveau TP)
    final provider =
    Provider.of<AssuranceSaleProvider>(context, listen: true);
    if (provider.selectedClient != null) {
      for (var tp in provider.selectedClient!.tiersPayants) {
        if (!_bonControllers.containsKey(tp.compteTp)) {
          _bonControllers[tp.compteTp] =
              TextEditingController(text: provider.bonNumbers[tp.compteTp] ?? "");
        }
      }
    }
  }


  @override
  void dispose() {
    _bonControllers.forEach((_, controller) => controller.dispose());
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AssuranceSaleProvider>(context);
    final client = provider.selectedClient;

    if (client == null) {
      return const Center(
          child: Text("Aucun client sélectionné. Veuillez recommencer."));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // --- Info Client Sélectionné ---
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
                onPressed: () => provider.returnToClientSearch(),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // --- Section Ayant Droit ---
          Text('1. Sélectionner un Ayant Droit (Patient)',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<AyantDroit>(
                  value: provider.selectedAyantDroit,
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

          // --- Section N° de Bon ---
          Text('2. Saisir le(s) N° de Bon',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ...client.tiersPayants.map((tp) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: TextFormField(
                controller: _bonControllers[tp.compteTp],
                decoration: InputDecoration(
                  labelText: 'N° Bon pour ${tp.tpFullName} (${tp.taux}%)',
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) {
                  provider.updateBonNumber(tp.compteTp, value);
                },
              ),
            );
          }).toList(),

          // Bouton pour ajouter un tiers payant
          TextButton.icon(
            icon: const Icon(Icons.add_card),
            label: const Text('Ajouter un Tiers Payant au client'),
            onPressed: _showAddTiersPayantDialog,
          ),

          const SizedBox(height: 24),

          // --- Bouton de navigation ---
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: () {
              // Le provider vérifie si tous les N° de bon sont saisis
              provider.validateBonsAndProceed();
            },
            child: const Text('Continuer vers la saisie des produits'),
          ),
        ],
      ),
    );
  }
}