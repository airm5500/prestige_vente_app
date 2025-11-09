// lib/screens/carnet_sale/carnet_sale_screen.dart
// 09/11/2025 19:00
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/providers/carnet_sale_provider.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'widgets/step_1_client.dart';
import 'widgets/step_2_bon_ayantdroit.dart';
import 'widgets/step_3_products.dart';

class CarnetSaleScreen extends StatefulWidget {
  const CarnetSaleScreen({super.key});

  @override
  State<CarnetSaleScreen> createState() => _CarnetSaleScreenState();
}

class _CarnetSaleScreenState extends State<CarnetSaleScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<CarnetSaleProvider>(context, listen: false)
          .startNewCarnetSale();
    });
  }

  Widget _buildCurrentStep(CarnetSaleProvider provider) {
    switch (provider.currentStep) {
      case CarnetStep.clientSearch:
        return const Step1ClientWidget();
      case CarnetStep.bonAndAyantDroit:
        return const Step2BonAyantDroitWidget();
      case CarnetStep.productSearch:
        return const Step3ProductsWidget();
    }
  }

  Future<void> _showExitConfirmationDialog(CarnetSaleProvider provider) async {
    final bool? didConfirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Abandonner la saisie ?'),
        content: const Text('Si vous quittez, toutes les données de la vente en cours seront perdues.'),
        actions: [
          TextButton(
            child: const Text('Non'),
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          ElevatedButton(
            child: const Text('Oui, abandonner'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (didConfirm == true && context.mounted) {
      provider.startNewCarnetSale();
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<CarnetSaleProvider>(context);
    final bool canPopDirectly = provider.selectedClient == null;

    return PopScope(
      canPop: canPopDirectly,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        _showExitConfirmationDialog(provider);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Vente Carnet'),
        ),
        body: Column(
          children: [
            if (provider.isLoading) const LinearProgressIndicator(),
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
            Expanded(
              child: _buildCurrentStep(provider),
            ),
          ],
        ),
      ),
    );
  }
}