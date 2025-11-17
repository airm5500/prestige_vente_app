// lib/screens/assurance_sale/widgets/assurance_payment_dialog.dart
// 09/11/2025 21:30 (Correction Filtre Règlements)
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/providers/assurance_sale_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

import 'package:prestige_vente_app/providers/caisse_provider.dart';
import 'package:prestige_vente_app/widgets/cash_payment_dialog.dart';

// MODIFICATION : Import des Settings
import 'package:prestige_vente_app/providers/settings_provider.dart';


class AssurancePaymentDialog extends StatefulWidget {
  const AssurancePaymentDialog({super.key});

  @override
  State<AssurancePaymentDialog> createState() => _AssurancePaymentDialogState();
}

class _AssurancePaymentDialogState extends State<AssurancePaymentDialog> {
  late Future<List<PaymentMethod>> _paymentMethodsFuture;

  @override
  void initState() {
    super.initState();
    // MODIFICATION : Appelle la nouvelle fonction de chargement et filtrage
    _paymentMethodsFuture = _loadAndFilterMethods();
  }

  // MODIFICATION : Nouvelle fonction pour charger ET filtrer
  Future<List<PaymentMethod>> _loadAndFilterMethods() async {
    // 1. Récupère les providers
    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);
    final settings = Provider.of<SettingsProvider>(context, listen: false);

    // 2. Récupère TOUS les modes de paiement
    final allMethods = await provider.getFilteredPaymentMethods();

    // 3. Récupère les IDs autorisés dans les paramètres
    final allowedIds = settings.enabledPaymentMethodIds;

    // 4. Retourne la liste filtrée
    return allMethods.where((m) => allowedIds.contains(m.id)).toList();
  }
  // FIN MODIFICATION

  Future<void> _handleCashPayment(PaymentMethod method) async {
    final BuildContext mainContext = context;
    final scaffoldMessenger = ScaffoldMessenger.of(mainContext);
    final navigator = Navigator.of(mainContext);
    final provider = Provider.of<AssuranceSaleProvider>(mainContext, listen: false);

    final result = await showDialog<Map<String, int>>(
      context: mainContext,
      builder: (ctx) => CashPaymentDialog(
        montantNet: provider.saleSummary!.montantNet,
      ),
    );

    if (result != null) {
      final int montantVerse = result['verse']!;
      final int monnaie = result['monnaie']!;

      showDialog(
        context: mainContext,
        barrierDismissible: false,
        builder: (ctx) => const AlertDialog(content: Row(children: [CircularProgressIndicator(), SizedBox(width: 16), Text("Validation...")])),
      );

      final apiResult = await provider.cloturerVente(
        method,
        montantRecu: montantVerse,
        montantRemis: monnaie,
      );

      Navigator.of(mainContext).pop(); // Ferme le spinner
      if (!mainContext.mounted) return;

      final bool caisseHandled = await Constants.checkAndOpenCaisse(mainContext, apiResult);
      if (caisseHandled) {
        navigator.pop();
        return;
      }

      if (apiResult['success'] == true) {
        scaffoldMessenger.showSnackBar(const SnackBar(
          content: Text('Vente validée avec succès !'),
          backgroundColor: AppColors.success,
        ));
        navigator.pop({
          'method': method,
          'verse': montantVerse,
          'monnaie': monnaie
        });
      } else {
        final currentStep = provider.currentStep;
        final errorMsg = provider.errorMessage;
        if (currentStep == AssuranceStep.bonAndAyantDroit) {
          navigator.pop();
        } else {
          scaffoldMessenger.showSnackBar(SnackBar(
            content: Text(errorMsg ?? "La validation a échoué"),
            backgroundColor: AppColors.error,
          ));
        }
      }
    }
  }

  Future<void> _handleOtherPayment(PaymentMethod method) async {
    final BuildContext mainContext = context;
    final scaffoldMessenger = ScaffoldMessenger.of(mainContext);
    final navigator = Navigator.of(mainContext);
    final provider = Provider.of<AssuranceSaleProvider>(mainContext, listen: false);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(content: Row(children: [CircularProgressIndicator(), SizedBox(width: 16), Text("Validation...")])),
    );

    final result = await provider.cloturerVente(method);

    Navigator.of(context).pop();
    if (!mainContext.mounted) return;

    final bool caisseHandled = await Constants.checkAndOpenCaisse(mainContext, result);
    if (caisseHandled) {
      navigator.pop();
      return;
    }

    if (result['success'] == true) {
      scaffoldMessenger.showSnackBar(const SnackBar(
        content: Text('Vente validée avec succès !'),
        backgroundColor: AppColors.success,
      ));
      navigator.pop({'method': method});
    } else {
      final currentStep = provider.currentStep;
      final errorMsg = provider.errorMessage;

      if (currentStep == AssuranceStep.bonAndAyantDroit) {
        navigator.pop();
      } else {
        scaffoldMessenger.showSnackBar(SnackBar(
          content: Text(errorMsg ?? "La validation a échoué"),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Choisir un mode de règlement'),
      content: SizedBox(
        width: double.maxFinite,
        child: FutureBuilder<List<PaymentMethod>>(
          future: _paymentMethodsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return const Center(
                  child: Text("Erreur de chargement des modes."));
            }
            // MODIFICATION : Message si la liste filtrée est vide
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text("Aucun mode de paiement activé.\nVeuillez vérifier les paramètres.", textAlign: TextAlign.center),
                  ));
            }

            final methods = snapshot.data!;
            return ListView.builder(
              shrinkWrap: true,
              itemCount: methods.length,
              itemBuilder: (context, index) {
                final method = methods[index];
                return ListTile(
                  title: Text(method.name),
                  onTap: () {
                    if (method.id == '1') { // "1" est ESPECES
                      _handleCashPayment(method);
                    } else {
                      _handleOtherPayment(method);
                    }
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}