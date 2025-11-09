// lib/screens/assurance_sale/widgets/assurance_summary_footer.dart
// 09/11/2025 00:30 (Gestion Erreur N° Bon)
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/client_assurance.dart';
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

  Future<void> _handlePrintAndReset(
      BuildContext context, {
        required bool isPrevente,
        PaymentMethod? paymentMethod,
      }) async {
    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);
    if (provider.isLoading) return;

    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final receiptService = ReceiptService();

    final summaryToPrint = provider.saleSummary!;
    final itemsToPrint = List<SaleItemDetail>.from(provider.cartItems);
    final clientToPrint = provider.selectedClient!;
    final ayantDroitToPrint = provider.selectedAyantDroit!;
    final copies = settings.numberOfTicketsAssurance;

    final bool? printTicket = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(isPrevente ? 'Prévente terminée' : 'Vente terminée'),
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
      if (isPrevente) {
        await receiptService.printAssurancePreventeTicket(
          context: context,
          officine: auth.officine!,
          saleSummary: summaryToPrint,
          items: itemsToPrint,
          client: clientToPrint,
          ayantDroit: ayantDroitToPrint,
          currentUser: auth.user!,
          isTestMode: settings.isTestPrintMode,
          paperWidth: settings.paperWidth,
          ticketCodeType: settings.ticketCodeType,
          numberOfCopies: copies,
        );
      } else {
        await receiptService.printAssuranceSaleTicket(
          context: context,
          officine: auth.officine!,
          saleSummary: summaryToPrint,
          items: itemsToPrint,
          client: clientToPrint,
          ayantDroit: ayantDroitToPrint,
          paymentMethod: paymentMethod ?? PaymentMethod(id: '0', name: 'COMPTANT'),
          currentUser: auth.user!,
          isTestMode: settings.isTestPrintMode,
          paperWidth: settings.paperWidth,
          ticketCodeType: settings.ticketCodeType,
          numberOfCopies: copies,
        );
      }
    }

    provider.startNewAssuranceSale();
  }


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

    await _handlePrintAndReset(context, isPrevente: true);
  }

  Future<void> _validerVenteAvecPaiement(BuildContext context) async {
    // Affiche le dialogue et ATTEND son résultat
    final paymentMethod = await showDialog<PaymentMethod>(
      context: context,
      builder: (ctx) => const AssurancePaymentDialog(),
    );

    // Si l'utilisateur a validé (paymentMethod n'est pas null),
    // on lance l'impression et la réinitialisation.
    if (paymentMethod != null) {
      await _handlePrintAndReset(context, isPrevente: false, paymentMethod: paymentMethod);
    }
  }

  Future<void> _validerVenteSansPaiement(BuildContext context) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);

    final success = await provider.cloturerVente(null); // Envoie null

    if (!success) {
      // MODIFICATION (Gestion Erreur N° Bon)
      // On vérifie si le provider est revenu à l'étape 2
      final currentStep = provider.currentStep;
      final errorMsg = provider.errorMessage;

      if (currentStep == AssuranceStep.bonAndAyantDroit) {
        // L'erreur (ex: N° Bon) s'affichera automatiquement en haut
        // On peut ajouter un SnackBar en plus si on veut
        scaffoldMessenger.showSnackBar(SnackBar(
          content: Text(errorMsg ?? "Erreur de N° de Bon"),
          backgroundColor: AppColors.error,
        ));
      } else {
        // Autre erreur
        scaffoldMessenger.showSnackBar(SnackBar(
          content: Text(errorMsg ?? "La validation a échoué"),
          backgroundColor: AppColors.error,
        ));
      }
      return;
      // FIN MODIFICATION
    }

    scaffoldMessenger.showSnackBar(const SnackBar(
      content: Text('Vente validée avec succès !'),
      backgroundColor: AppColors.success,
    ));

    await _handlePrintAndReset(context, isPrevente: false, paymentMethod: null);
  }


  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AssuranceSaleProvider>(context);
    final summary = provider.saleSummary;
    final client = provider.selectedClient;
    final bool canValidate = summary != null && !provider.isLoading && client != null;

    return Card(
      elevation: 4,
      margin: const EdgeInsets.all(0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            if (summary == null)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.calculate),
                  label: const Text('Calculer le Net à Payer'),
                  onPressed: provider.isLoading || provider.cartItems.isEmpty
                      ? null
                      : (provider.activeTiersPayants.isEmpty ? null : () => provider.calculateNet()),
                ),
              ),

            if (summary != null && client != null)
              Column(
                children: [
                  _buildSummaryRow('Total Brut:', summary.montant),
                  _buildSummaryRow(
                      'Part Tiers Payant:', summary.montantTp, Colors.red),

                  ...summary.tierspayants.map((tp) {
                    final tpClientInfo = client.tiersPayants.firstWhere(
                            (c) => c.compteTp == tp.compteTp,
                        orElse: () => ClientTiersPayant(lgTIERSPAYANTID: '', tpFullName: 'N/A', taux: 0, numSecurity: '', compteTp: '', order: 0, principal: false)
                    );
                    return Padding(
                      padding: const EdgeInsets.only(left: 16.0),
                      child: _buildSummaryRow(
                          '∙ ${tpClientInfo.tpFullName} N°Bon: ${tp.numBon} (${tp.taux}%)', tp.tpnet),
                    );
                  }),
                  _buildSummaryRow(
                      'Part Client (Net):', summary.montantNet, AppColors.primary, 20),
                ],
              ),

            const SizedBox(height: 12),

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
                    onPressed: canValidate && (summary.montantNet > 0)
                        ? () => _validerVenteAvecPaiement(context)
                        : null,
                    child: const Text('Vente'),
                  ),
                ),
              ],
            ),

            if (summary != null && summary.montantNet == 0)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                    ),
                    onPressed: canValidate
                        ? () => _validerVenteSansPaiement(context)
                        : null,
                    child: const Text('Valider Vente (Part Client 0)'),
                  ),
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
          Flexible(
            child: Text(label,
              style: TextStyle(
                  fontSize: fontSize ?? 16,
                  color: color ?? Colors.black87),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
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