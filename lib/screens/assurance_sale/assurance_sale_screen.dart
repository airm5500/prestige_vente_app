// lib/screens/assurance_sale/assurance_sale_screen.dart
// 02/11/2025 15:45
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/providers/assurance_sale_provider.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'widgets/step_1_client.dart';
import 'widgets/step_2_bon_ayantdroit.dart';

// AJOUT : Import pour l'étape 3
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

    // AJOUT : Affiche le widget de l'étape 3
      case AssuranceStep.productSearch:
        return const Step3ProductsWidget();

      default:
        return const Step1ClientWidget();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AssuranceSaleProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Vente Assurance'),
            actions: [
              // Bouton pour tout réinitialiser et commencer une nouvelle vente
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () {
                  provider.startNewAssuranceSale();
                },
                tooltip: 'Nouvelle Vente Assurance',
              )
            ],
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
        );
      },
    );
  }
}