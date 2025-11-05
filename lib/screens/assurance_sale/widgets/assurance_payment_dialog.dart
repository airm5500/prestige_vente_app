// lib/screens/assurance_sale/widgets/assurance_payment_dialog.dart
// 05/11/2025 02:10 (Corrigé)
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/providers/assurance_sale_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

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

  // MODIFICATION (Point 2)
  // Cette méthode gère la validation et ferme le dialogue en retournant un succès/échec
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

    final success = await provider.cloturerVente(method);

    navigator.pop(); // Ferme le dialogue de chargement

    if (!success) {
      scaffoldMessenger.showSnackBar(SnackBar(
        content: Text(provider.errorMessage ?? "La validation a échoué"),
        backgroundColor: AppColors.error,
      ));
      // Ne ferme pas le dialogue de paiement, l'utilisateur peut réessayer
    } else {
      scaffoldMessenger.showSnackBar(const SnackBar(
        content: Text('Vente validée avec succès !'),
        backgroundColor: AppColors.success,
      ));
      // Si succès, ferme le dialogue de choix de paiement
      // et retourne le mode de paiement utilisé
      navigator.pop(method);
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