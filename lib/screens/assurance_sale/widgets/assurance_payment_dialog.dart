// lib/screens/assurance_sale/widgets/assurance_payment_dialog.dart
// 09/11/2025 03:00 (Gestion Erreur Caisse Fermée)
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/providers/assurance_sale_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

// AJOUT : Import pour le CaisseProvider
//import 'package:prestige_vente_app/providers/caisse_provider.dart';


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
    _paymentMethodsFuture =
        Provider.of<AssuranceSaleProvider>(context, listen: false)
            .getFilteredPaymentMethods();
  }

  Future<void> _handlePayment(PaymentMethod method) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);

    // Affiche un indicateur de chargement DANS le dialogue
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(content: Row(children: [CircularProgressIndicator(), SizedBox(width: 16), Text("Validation...")])),
    );

    final result = await provider.cloturerVente(method);

    navigator.pop(); // Ferme le dialogue de chargement
    if (!mounted) return;

    // 1. Vérifie si l'erreur "Caisse fermée" a eu lieu
    final bool caisseHandled = await Constants.checkAndOpenCaisse(context, result);
    if (caisseHandled) {
      navigator.pop(); // Ferme le dialogue de paiement
      return; // Arrête tout, l'utilisateur doit re-valider
    }

    // 2. Si c'est un succès
    if (result['success'] == true) {
      scaffoldMessenger.showSnackBar(const SnackBar(
        content: Text('Vente validée avec succès !'),
        backgroundColor: AppColors.success,
      ));
      navigator.pop(method); // Ferme le dialogue de paiement avec succès

    } else {
      // 3. Si c'est une autre erreur (ex: N° Bon utilisé)
      final currentStep = provider.currentStep;
      final errorMsg = provider.errorMessage; // Le provider a déjà mis à jour l'erreur

      if (currentStep == AssuranceStep.bonAndAyantDroit) {
        // L'erreur était un N° de bon. On ferme ce dialogue
        navigator.pop();
      } else {
        // C'était une autre erreur, on reste sur le dialogue de paiement
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
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Center(
                  child: Text("Aucun mode de paiement mobile configuré."));
            }

            final methods = snapshot.data!;
            return ListView.builder(
              shrinkWrap: true,
              itemCount: methods.length,
              itemBuilder: (context, index) {
                final method = methods[index];
                return ListTile(
                  title: Text(method.name),
                  onTap: () => _handlePayment(method),
                );
              },
            );
          },
        ),
      ),
    );
  }
}