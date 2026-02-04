// lib/screens/assurance_sale/widgets/assurance_summary_footer.dart
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/client_assurance.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/api/models/user.dart';
import 'package:prestige_vente_app/providers/assurance_sale_provider.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/services/receipt_service.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';
import 'assurance_payment_dialog.dart';

import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/api/models/payment_method_qr.dart';
import 'package:prestige_vente_app/api/models/assurance_sale_summary.dart';


class AssuranceSummaryFooter extends StatefulWidget {
  const AssuranceSummaryFooter({super.key});

  @override
  State<AssuranceSummaryFooter> createState() => _AssuranceSummaryFooterState();
}

class _AssuranceSummaryFooterState extends State<AssuranceSummaryFooter> {
  // Verrou local pour empêcher les doubles clics sur les boutons principaux
  bool _isActionInProgress = false;

  Future<void> _handlePrintAndReset(
      BuildContext context, {
        required bool isPrevente,
        PaymentMethod? paymentMethod,
        int? montantVerse,
        int? monnaie,
      }) async {
    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final receiptService = ReceiptService();

    if (provider.saleSummary == null || provider.selectedClient == null || provider.selectedAyantDroit == null || auth.user == null || auth.officine == null) {
      provider.startNewAssuranceSale();
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
          paymentMethod: paymentMethod ?? PaymentMethod(id: '0', name: 'COMPTANT'),
          currentUser: currentUserToPrint,
          isTestMode: settings.isTestPrintMode,
          paperWidth: settings.paperWidth,
          ticketCodeType: settings.ticketCodeType,
          numberOfCopies: copies,
          montantVerse: montantVerse,
          monnaie: monnaie,
        );
      }
    }
    provider.startNewAssuranceSale();
  }


  Future<void> _terminerPrevente(BuildContext context) async {
    setState(() => _isActionInProgress = true);

    try {
      final scaffoldMessenger = ScaffoldMessenger.of(context);
      final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);
      final success = await provider.terminerPrevente();

      if (!success) {
        if(provider.currentStep != AssuranceStep.bonAndAyantDroit) {
          scaffoldMessenger.showSnackBar(SnackBar(
            content: Text(provider.errorMessage ?? "La validation a échoué"),
            backgroundColor: AppColors.error,
          ));
        }
        return;
      }

      scaffoldMessenger.showSnackBar(const SnackBar(
        content: Text('Prévente assurance validée !'),
        backgroundColor: AppColors.success,
      ));
      await _handlePrintAndReset(context, isPrevente: true);

    } finally {
      if(mounted) setState(() => _isActionInProgress = false);
    }
  }

  // NOUVEAU DIALOGUE DE CONFIRMATION SÉCURISÉ (Copie de la logique Vente Tab)
  Future<void> _showPaymentConfirmationDialog({
    required BuildContext context,
    required PaymentMethod method,
    required AssuranceSaleSummary summary,
    required User currentUser,
    PaymentMethodQr? qrMethod,
    int? montantRecu,
    int? montantRemis,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirmation de Paiement"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Mode : ${method.name}", style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text("Montant Net : ${Constants.formatNumber(summary.montantNet)} F",
                  style: const TextStyle(fontSize: 18, color: Colors.blue, fontWeight: FontWeight.bold)),

              const Divider(height: 30),

              if (qrMethod != null && qrMethod.qrCode != null) ...[
                const Text("Scanner pour payer :"),
                const SizedBox(height: 10),
                SizedBox(
                  width: 180,
                  height: 180,
                  child: Image.memory(qrMethod.qrCode!, fit: BoxFit.contain),
                ),
              ] else
                const Text("Veuillez confirmer l'encaissement."),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        actions: [
          Row(
            children: [
              // BOUTON RETOUR / MODIFIER (BLEU)
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(ctx).pop(),
                  icon: const Icon(Icons.arrow_back, color: Colors.white, size: 18),
                  label: const Text("RETOUR", style: TextStyle(color: Colors.white, fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // BOUTON VALIDER LA VENTE (VERT) -> C'EST ICI QUE L'API EST APPELÉE
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.of(ctx).pop(); // Ferme le dialogue

                    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);

                    // APPEL API DE CLOTURE
                    final result = await provider.cloturerVente(
                        method,
                        montantRecu: montantRecu,
                        montantRemis: montantRemis
                    );

                    if (!context.mounted) return;

                    // Vérification Caisse
                    final bool caisseHandled = await Constants.checkAndOpenCaisse(context, result);
                    if (caisseHandled) return;

                    if (result['success'] == true) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Vente validée avec succès !'),
                        backgroundColor: AppColors.success,
                      ));
                      // Lancement impression
                      await _handlePrintAndReset(
                          context,
                          isPrevente: false,
                          paymentMethod: method,
                          montantVerse: montantRecu,
                          monnaie: montantRemis
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(provider.errorMessage ?? "La validation a échoué"),
                        backgroundColor: AppColors.error,
                      ));
                    }
                  },
                  icon: const Icon(Icons.check_circle, color: Colors.white, size: 18),
                  label: const Text("VALIDER", style: TextStyle(color: Colors.white, fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _validerVenteAvecPaiement(BuildContext context) async {
    setState(() => _isActionInProgress = true);

    try {
      // 1. Choix du mode
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => const AssurancePaymentDialog(),
      );

      if (result == null) return;

      final paymentMethod = result['method'] as PaymentMethod?;
      final montantVerse = result['verse'] as int?;
      final monnaie = result['monnaie'] as int?;

      if (paymentMethod == null) return;

      final saleProvider = Provider.of<SaleProvider>(context, listen: false);
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);

      if (provider.saleSummary == null || auth.user == null) return;

      // 2. Recherche du QR Code
      PaymentMethodQr? qrMethod;
      try {
        qrMethod = saleProvider.paymentMethodsWithQr.firstWhere((m) => m.id == paymentMethod.id);
      } catch (e) {
        qrMethod = null;
      }

      // 3. OUVERTURE DU DIALOGUE DE CONFIRMATION (Au lieu d'appeler l'API tout de suite)
      await _showPaymentConfirmationDialog(
          context: context,
          method: paymentMethod,
          summary: provider.saleSummary!,
          currentUser: auth.user!,
          qrMethod: qrMethod,
          montantRecu: montantVerse,
          montantRemis: monnaie
      );

    } finally {
      if(mounted) setState(() => _isActionInProgress = false);
    }
  }

  Future<void> _validerVenteSansPaiement(BuildContext context) async {
    setState(() => _isActionInProgress = true);

    try {
      final scaffoldMessenger = ScaffoldMessenger.of(context);
      final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);

      final result = await provider.cloturerVente(null);

      if (!context.mounted) return;

      final bool caisseHandled = await Constants.checkAndOpenCaisse(context, result);
      if (caisseHandled) return;

      if (result['success'] == true) {
        scaffoldMessenger.showSnackBar(const SnackBar(
          content: Text('Vente validée avec succès !'),
          backgroundColor: AppColors.success,
        ));
        await _handlePrintAndReset(context, isPrevente: false, paymentMethod: null);

      } else {
        final currentStep = provider.currentStep;
        final errorMsg = provider.errorMessage;

        if (currentStep == AssuranceStep.bonAndAyantDroit) {
          scaffoldMessenger.showSnackBar(SnackBar(content: Text(errorMsg ?? "Erreur de N° de Bon"), backgroundColor: AppColors.error));
        } else {
          scaffoldMessenger.showSnackBar(SnackBar(content: Text(errorMsg ?? "La validation a échoué"), backgroundColor: AppColors.error));
        }
      }
    } finally {
      if(mounted) setState(() => _isActionInProgress = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AssuranceSaleProvider>(context);
    final summary = provider.saleSummary;
    final client = provider.selectedClient;

    // CONDITION DE VALIDATION RENFORCÉE
    final bool canValidate = summary != null && !provider.isLoading && client != null && !_isActionInProgress;

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
                  onPressed: provider.isLoading || provider.cartItems.isEmpty || _isActionInProgress
                      ? null
                      : (provider.activeTiersPayants.isEmpty ? null : () => provider.calculateNet()),
                ),
              ),

            if (summary != null && client != null)
              Column(
                children: [
                  _buildSummaryRow('Total Brut:', summary.montant),
                  _buildSummaryRow('Part Tiers Payant:', summary.montantTp, Colors.red),

                  ...summary.tierspayants.map((tp) {
                    final tpClientInfo = client.tiersPayants.firstWhere(
                            (c) => c.compteTp == tp.compteTp,
                        orElse: () => ClientTiersPayant(lgTIERSPAYANTID: '', tpFullName: 'N/A', taux: 0, numSecurity: '', compteTp: '', order: 0, principal: false)
                    );
                    return Padding(
                      padding: const EdgeInsets.only(left: 16.0),
                      child: _buildSummaryRow('∙ ${tpClientInfo.tpFullName} N°Bon: ${tp.numBon} (${tp.taux}%)', tp.tpnet),
                    );
                  }),
                  _buildSummaryRow('Part Client (Net):', summary.montantNet, AppColors.primary, 20),
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
                    child: _isActionInProgress
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Prévente'),
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
                    child: _isActionInProgress
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Vente'),
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
                    child: _isActionInProgress
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Valider Vente (Part Client 0)'),
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