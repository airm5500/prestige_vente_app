// lib/screens/carnet_sale/widgets/carnet_summary_footer.dart
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/client_assurance.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/providers/carnet_sale_provider.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/services/receipt_service.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

class CarnetSummaryFooter extends StatelessWidget {
  const CarnetSummaryFooter({super.key});

  Future<void> _handlePrintAndReset(
      BuildContext context, {
        required bool isPrevente,
      }) async {
    final provider = Provider.of<CarnetSaleProvider>(context, listen: false);
    if (provider.isLoading) return;

    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final receiptService = ReceiptService();

    if (provider.saleSummary == null || provider.selectedClient == null || provider.selectedAyantDroit == null || auth.user == null || auth.officine == null) {
      provider.startNewCarnetSale();
      return;
    }

    final summaryToPrint = provider.saleSummary!;
    final itemsToPrint = List<SaleItemDetail>.from(provider.cartItems);
    final clientToPrint = provider.selectedClient!;
    final ayantDroitToPrint = provider.selectedAyantDroit!;
    final currentUserToPrint = auth.user!;
    final officineToPrint = auth.officine!;

    final copies = settings.numberOfTicketsAssurance;

    final bool? printTicket = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(isPrevente ? 'Prévente terminée' : 'Vente Carnet terminée'),
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
          officine: officineToPrint,
          saleSummary: summaryToPrint,
          items: itemsToPrint,
          client: clientToPrint,
          ayantDroit: ayantDroitToPrint,
          currentUser: currentUserToPrint,
          isTestMode: settings.isTestPrintMode,
          paperWidth: settings.paperWidth,
          ticketCodeType: settings.ticketCodeType,
          numberOfCopies: copies,
        );
      } else {
        await receiptService.printAssuranceSaleTicket(
          context: context,
          officine: officineToPrint,
          saleSummary: summaryToPrint,
          items: itemsToPrint,
          client: clientToPrint,
          ayantDroit: ayantDroitToPrint,
          paymentMethod: PaymentMethod(id: '1', name: 'CARNET'),
          currentUser: currentUserToPrint,
          isTestMode: settings.isTestPrintMode,
          paperWidth: settings.paperWidth,
          ticketCodeType: settings.ticketCodeType,
          numberOfCopies: copies,
          // CORRECTION ICI : ON PASSE LE PARAMÈTRE
          showQrCode: settings.showQrCodeOnSaleTicket,
        );
      }
    }
    provider.startNewCarnetSale();
  }

  // ... (Le reste des méthodes _terminerPrevente, _validerVenteCarnet, build... restent inchangées)
  // Je remets le reste pour être complet :

  Future<void> _terminerPrevente(BuildContext context) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final provider = Provider.of<CarnetSaleProvider>(context, listen: false);

    final success = await provider.terminerPrevente();

    if (!success) {
      if(provider.currentStep != CarnetStep.bonAndAyantDroit) {
        scaffoldMessenger.showSnackBar(SnackBar(
          content: Text(provider.errorMessage ?? "La validation a échoué"),
          backgroundColor: AppColors.error,
        ));
      }
      return;
    }

    scaffoldMessenger.showSnackBar(const SnackBar(
      content: Text('Prévente carnet validée !'),
      backgroundColor: AppColors.success,
    ));

    await _handlePrintAndReset(context, isPrevente: true);
  }

  Future<void> _validerVenteCarnet(BuildContext context) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final provider = Provider.of<CarnetSaleProvider>(context, listen: false);

    final result = await provider.cloturerVenteCarnet();

    if (!context.mounted) return;

    final bool caisseHandled = await Constants.checkAndOpenCaisse(context, result);
    if (caisseHandled) {
      return;
    }

    if (result['success'] == true) {
      scaffoldMessenger.showSnackBar(const SnackBar(
        content: Text('Vente Carnet validée avec succès !'),
        backgroundColor: AppColors.success,
      ));
      await _handlePrintAndReset(context, isPrevente: false);

    } else {
      final currentStep = provider.currentStep;
      final errorMsg = provider.errorMessage;

      if (currentStep == CarnetStep.bonAndAyantDroit) {
        scaffoldMessenger.showSnackBar(SnackBar(
          content: Text(errorMsg ?? "Erreur de N° de Bon"),
          backgroundColor: AppColors.error,
        ));
      } else {
        scaffoldMessenger.showSnackBar(SnackBar(
          content: Text(errorMsg ?? "La validation a échoué"),
          backgroundColor: AppColors.error,
        ));
      }
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<CarnetSaleProvider>(context);
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
                      'Part Carnet:', summary.montantTp, Colors.red),

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
                    onPressed: canValidate
                        ? () => _validerVenteCarnet(context)
                        : null,
                    child: const Text('Vente'),
                  ),
                ),
              ],
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