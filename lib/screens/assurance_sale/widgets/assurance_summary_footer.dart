// lib/screens/assurance_sale/widgets/assurance_summary_footer.dart
// 02/11/2025 15:45
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/providers/assurance_sale_provider.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/services/receipt_service.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';
import 'assurance_payment_dialog.dart';

class AssuranceSummaryFooter extends StatelessWidget {
  const AssuranceSummaryFooter({super.key});

  // Action pour "Terminer Prévente"
  Future<void> _terminerPrevente(BuildContext context) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);

    final success = await provider.terminerPrevente();
    if (!success) {
      scaffoldMessenger.showSnackBar(SnackBar(
        content: Text(provider.errorMessage ?? "La validation a échoué"),
        backgroundColor: AppColors.error,
      ));
      return;
    }

    scaffoldMessenger.showSnackBar(const SnackBar(
      content: Text('Prévente assurance validée !'),
      backgroundColor: AppColors.success,
    ));

    // --- Logique d'impression ---
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final receiptService = ReceiptService();

    final summaryToPrint = provider.saleSummary!;
    final clientToPrint = provider.selectedClient!;
    final ayantDroitToPrint = provider.selectedAyantDroit!;

    final bool? printTicket = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Prévente Assurance terminée'),
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
      await receiptService.printAssurancePreventeTicket(
        context: context,
        officine: auth.officine!,
        saleSummary: summaryToPrint,
        client: clientToPrint,
        ayantDroit: ayantDroitToPrint,
        currentUser: auth.user!,
        isTestMode: settings.isTestPrintMode,
        paperWidth: settings.paperWidth,
        ticketCodeType: settings.ticketCodeType,
      );
    }

    // Réinitialise l'écran
    provider.startNewAssuranceSale();
  }

  // Action pour "Valider Vente"
  void _validerVente(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => const AssurancePaymentDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AssuranceSaleProvider>(context);
    final summary = provider.saleSummary;
    final bool canValidate = summary != null && !provider.isLoading;

    return Card(
      elevation: 4,
      margin: const EdgeInsets.all(0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            // Ligne 1: Bouton de calcul
            if (summary == null)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.calculate),
                  label: const Text('Calculer le Net à Payer'),
                  onPressed: provider.isLoading || provider.cartItems.isEmpty
                      ? null
                      : () => provider.calculateNet(),
                ),
              ),

            // Ligne 2: Affichage des montants
            if (summary != null)
              Column(
                children: [
                  _buildSummaryRow('Total Brut:', summary.montant),
                  _buildSummaryRow(
                      'Part Tiers Payant:', summary.montantTp, Colors.red),
                  // Affichage par TP
                  ...summary.tierspayants.map((tp) => Padding(
                    padding: const EdgeInsets.only(left: 16.0),
                    child: _buildSummaryRow(
                        '∙ Bon ${tp.numBon} (${tp.taux}%)', tp.tpnet),
                  )),
                  _buildSummaryRow(
                      'Part Client (Net):', summary.montantNet, AppColors.primary, 20),
                ],
              ),

            const SizedBox(height: 12),

            // Ligne 3: Boutons de validation
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange.shade700,
                      side: BorderSide(color: Colors.orange.shade700),
                    ),
                    onPressed: canValidate
                        ? () => _terminerPrevente(context)
                        : null,
                    child: const Text('Prévente'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                    ),
                    onPressed: canValidate && summary.montantNet > 0
                        ? () => _validerVente(context)
                        : null,
                    child: const Text('Vente'),
                  ),
                ),
              ],
            ),
            // Si la part client est 0, on peut valider en Vente sans paiement
            if (summary != null && summary.montantNet == 0)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                  ),
                  onPressed: canValidate
                      ? () => _validerVente(context) // Le dialogue gèrera le paiement à 0
                      : null,
                  child: const Text('Valider Vente (Part Client 0)'),
                ),
              ),

          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, int value, [Color? color, double? fontSize]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: fontSize ?? 16,
                  color: color ?? Colors.black87)),
          Text(
            Constants.formatNumber(value),
            style: TextStyle(
                fontSize: fontSize ?? 16,
                fontWeight: FontWeight.bold,
                color: color ?? AppColors.primary),
          ),
        ],
      ),
    );
  }
}