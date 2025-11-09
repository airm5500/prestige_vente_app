// lib/screens/assurance_sale/assurance_sale_screen.dart
// 08/11/2025 23:00 (Améliorations UI)
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/providers/assurance_sale_provider.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'widgets/step_1_client.dart';
import 'widgets/step_2_bon_ayantdroit.dart';
import 'widgets/step_3_products.dart';

class AssuranceSaleScreen extends StatefulWidget {
  const AssuranceSaleScreen({super.key});

  @override
  State<AssuranceSaleScreen> createState() => _AssuranceSaleScreenState();
}

class _AssuranceSaleScreenState extends State<AssuranceSaleScreen> {
  @override
  void initState() {
    super.initState();
    // Initialise une nouvelle vente assurance à chaque fois que l'écran est ouvert
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AssuranceSaleProvider>(context, listen: false)
          .startNewAssuranceSale();
    });
  }

  Widget _buildCurrentStep(AssuranceSaleProvider provider) {
    // Affiche le widget correspondant à l'étape actuelle
    switch (provider.currentStep) {
      case AssuranceStep.clientSearch:
        return const Step1ClientWidget();
      case AssuranceStep.bonAndAyantDroit:
        return const Step2BonAyantDroitWidget();
      case AssuranceStep.productSearch:
        return const Step3ProductsWidget();
    }
  }

  Future<void> _showExitConfirmationDialog(AssuranceSaleProvider provider) async {
    final bool? didConfirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // L'utilisateur doit choisir
      builder: (ctx) => AlertDialog(
        title: const Text('Abandonner la saisie ?'),
        content: const Text('Si vous quittez, toutes les données de la vente en cours seront perdues.'),
        actions: [
          TextButton(
            child: const Text('Non'),
            onPressed: () => Navigator.of(ctx).pop(false), // Reste sur l'écran
          ),
          ElevatedButton(
            child: const Text('Oui, abandonner'),
            onPressed: () => Navigator.of(ctx).pop(true), // Quitte l'écran
          ),
        ],
      ),
    );

    // Si l'utilisateur a cliqué "Oui"
    if (didConfirm == true && mounted) {
      // On nettoie la vente avant de quitter
      provider.startNewAssuranceSale();
      // On force la navigation retour
      Navigator.of(context).pop();
    }
    // Si "Non", ne fait rien
  }

  @override
  Widget build(BuildContext context) {
    // On doit récupérer le provider ici pour déterminer si on peut quitter
    final provider = Provider.of<AssuranceSaleProvider>(context);
    final bool canPopDirectly = provider.selectedClient == null;

    return PopScope(
      // On peut quitter directement SEULEMENT si aucun client n'est sélectionné
      canPop: canPopDirectly,

      onPopInvokedWithResult: (bool didPop, dynamic result) {
        // Si le pop a déjà eu lieu (parce que canPop était true), on ne fait rien
        if (didPop) {
          return;
        }
        // Sinon (canPop était false), on affiche notre dialogue de confirmation
        _showExitConfirmationDialog(provider);
      },

      child: Scaffold(
        appBar: AppBar(
          title: const Text('Vente Assurance'),
          actions: const [
            // MODIFICATION (1a) : Bouton (+) "Nouvelle Vente" supprimé
            /*
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () {
                // Cette action réinitialise juste l'écran, elle ne quitte pas
                provider.startNewAssuranceSale();
              },
              tooltip: 'Nouvelle Vente Assurance',
            )
            */
          ],
          // La flèche "Retour" sera maintenant gérée par le PopScope
        ),
        body: Column(
          children: [
            // Affiche une barre de chargement si le provider travaille
            if (provider.isLoading) const LinearProgressIndicator(),

            // Affiche une erreur si le provider en signale une
            if (provider.errorMessage != null)
              Container(
                width: double.infinity,
                color: AppColors.error,
                padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  provider.errorMessage!,
                  style: const TextStyle(color: Colors.white),
                ),
              ),

            // Affiche le widget de l'étape actuelle
            Expanded(
              child: _buildCurrentStep(provider),
            ),
          ],
        ),
      ),
    );
  }
}