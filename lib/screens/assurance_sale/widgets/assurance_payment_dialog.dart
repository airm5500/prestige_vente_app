// lib/screens/assurance_sale/widgets/assurance_payment_dialog.dart
// 02/11/2025 15:50 (Corrigé)
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/providers/assurance_sale_provider.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/services/receipt_service.dart';
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
    // Charge les modes de paiement filtrés
    _paymentMethodsFuture =
        Provider.of<AssuranceSaleProvider>(context, listen: false)
            .getFilteredPaymentMethods();
  }

  Future<void> _handlePayment(PaymentMethod method) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);

    final success = await provider.cloturerVente(method);

    if (!success) {
      scaffoldMessenger.showSnackBar(SnackBar(
        content: Text(provider.errorMessage ?? "La validation a échoué"),
        backgroundColor: AppColors.error,
      ));
      return;
    }

    // Si succès, ferme le dialogue de paiement
    navigator.pop();

    scaffoldMessenger.showSnackBar(const SnackBar(
      content: Text('Vente validée avec succès !'),
      backgroundColor: AppColors.success,
    ));

    // --- Logique d'impression ---
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final receiptService = ReceiptService();

    // Capture des données AVANT de réinitialiser
    final summaryToPrint = provider.saleSummary!;
    final itemsToPrint = List<SaleItemDetail>.from(provider.cartItems);
    final clientToPrint = provider.selectedClient!;
    // *** CORRECTION DE L'ERREUR 2 ***
    final ayantDroitToPrint = provider.selectedAyantDroit!;
    // *** FIN CORRECTION ***

    final bool? printTicket = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Vente Assurance terminée'),
        content: const Text('Voulez-vous imprimer le ticket ?'),
        actions: [
          TextButton(
            child: const Text('Non'),
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          ElevatedButton(
            child: const Text('Oui'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (printTicket == true) {
      await receiptService.printAssuranceSaleTicket(
        context: context,
        officine: auth.officine!,
        saleSummary: summaryToPrint,
        items: itemsToPrint,
        client: clientToPrint,
        // *** CORRECTION DE L'ERREUR 3 ***
        ayantDroit: ayantDroitToPrint,
        // *** FIN CORRECTION ***
        paymentMethod: method,
        currentUser: auth.user!,
        isTestMode: settings.isTestPrintMode,
        paperWidth: settings.paperWidth,
        ticketCodeType: settings.ticketCodeType,
      );
    }

    // Réinitialise l'écran de vente
    provider.startNewAssuranceSale();
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