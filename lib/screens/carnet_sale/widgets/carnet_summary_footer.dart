// lib/screens/carnet_sale/widgets/carnet_summary_footer.dart
// 09/11/2025 19:00
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/client_assurance.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
//import 'package:prestige_vente_app/api/models/user.dart';
import 'package:prestige_vente_app/providers/carnet_sale_provider.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/services/receipt_service.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

//import 'package:prestige_vente_app/api/models/assurance_sale_summary.dart';
//import 'package:prestige_vente_app/providers/caisse_provider.dart'; // Pour la vérif caisse

class CarnetSummaryFooter extends StatelessWidget {
  const CarnetSummaryFooter({super.key});

  // Note : La logique d'impression est réutilisée de l'assurance
  // car le ticket est identique (juste le titre change)
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

    // On utilise le même setting que l'assurance pour le nb de copies
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
          // Le paiement est par défaut "ESPECES" même si 0
          paymentMethod: PaymentMethod(id: '1', name: 'CARNET'),
          currentUser: currentUserToPrint,
          isTestMode: settings.isTestPrintMode,
          paperWidth: settings.paperWidth,
          ticketCodeType: settings.ticketCodeType,
          numberOfCopies: copies,
        );
      }
    }
    provider.startNewCarnetSale();
  }


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

  // MODIFICATION : Plus de dialogue de paiement.
  // Cette fonction gère la "Vente" (part client 0 ou > 0)
  Future<void> _validerVenteCarnet(BuildContext context) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final provider = Provider.of<CarnetSaleProvider>(context, listen: false);

    // 1. Appelle la clôture (le provider gère le paiement par défaut)
    final result = await provider.cloturerVenteCarnet();

    if (!context.mounted) return;

    // 2. Vérifie l'erreur "Caisse fermée"
    final bool caisseHandled = await Constants.checkAndOpenCaisse(context, result);
    if (caisseHandled) {
      return; // L'utilisateur doit réessayer
    }

    // 3. Si c'est un succès
    if (result['success'] == true) {
      scaffoldMessenger.showSnackBar(const SnackBar(
        content: Text('Vente Carnet validée avec succès !'),
        backgroundColor: AppColors.success,
      ));
      // Pas de dialogue QR, on passe à l'impression
      await _handlePrintAndReset(context, isPrevente: false);

    } else {
      // 4. Si c'est une autre erreur (ex: N° Bon utilisé)
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
                    // MODIFICATION : Appelle la validation directe
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