// lib/ventes/assurance/assurance_print.dart
// Impression des tickets assurance (nouvelle version) : UN seul dialogue avec le nombre de copies
// (au lieu d'une confirmation par copie), titre « ASSURANCE » même à 100 %, vraie référence.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/assurance_sale_summary.dart';
import 'package:prestige_vente_app/api/models/ayant_droit.dart';
import 'package:prestige_vente_app/api/models/client_assurance.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/services/receipt_service.dart';
import 'package:prestige_vente_app/ventes/common/vente_messages.dart';
import 'package:provider/provider.dart';

const int _maxCopies = 9;

/// « Imprimer le ticket ? » avec le nombre de copies. Renvoie le nombre de copies (0 = ne pas imprimer).
Future<int> showPrintCopiesDialog(BuildContext context, {required String title, String? message, required int initialCopies}) async {
  final n = await showDialog<int>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CopiesDialog(title: title, message: message, initial: initialCopies.clamp(1, _maxCopies)),
  );
  return n ?? 0;
}

class _CopiesDialog extends StatefulWidget {
  final String title;
  final String? message;
  final int initial;
  const _CopiesDialog({required this.title, this.message, required this.initial});

  @override
  State<_CopiesDialog> createState() => _CopiesDialogState();
}

class _CopiesDialogState extends State<_CopiesDialog> {
  late int _n = widget.initial;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (widget.message != null) ...[Text(widget.message!), const SizedBox(height: 12)],
          const Text('Imprimer le ticket :'),
          const SizedBox(height: 6),
          Row(children: [
            IconButton.outlined(
              tooltip: 'Moins de copies',
              onPressed: _n > 1 ? () => setState(() => _n--) : null,
              icon: const Icon(Icons.remove),
            ),
            Expanded(
              child: Text(
                '$_n copie${_n > 1 ? 's' : ''}',
                key: const ValueKey('assurance-copies'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton.outlined(
              tooltip: 'Plus de copies',
              onPressed: _n < _maxCopies ? () => setState(() => _n++) : null,
              icon: const Icon(Icons.add),
            ),
          ]),
        ]),
        actions: [
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(64, 44)),
            onPressed: () => Navigator.of(context).pop(0),
            child: const Text('Ne pas imprimer'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(minimumSize: const Size(88, 44)),
            onPressed: () => Navigator.of(context).pop(_n),
            icon: const Icon(Icons.print, size: 18),
            label: const Text('Imprimer'),
          ),
        ],
      );
}

/// Imprime [copies] tickets (prévente minimaliste ou vente détaillée) sans redemander à chaque copie.
Future<void> printAssuranceTicket(
  BuildContext context, {
  required bool prevente,
  required int copies,
  required AssuranceSaleSummary summary,
  required List<SaleItemDetail> items,
  required ClientAssurance client,
  required AyantDroit ayantDroit,
  required String reference,
  PaymentMethod? method,
  int? montantVerse,
  int? monnaie,
}) async {
  if (copies < 1) return;
  final auth = Provider.of<AuthProvider>(context, listen: false);
  final settings = Provider.of<SettingsProvider>(context, listen: false);
  final officine = auth.officine, user = auth.user;
  if (officine == null || user == null) {
    showVenteSnack(context, 'Données officine ou utilisateur manquantes : ticket non imprimé.', error: true);
    return;
  }
  if (prevente) {
    await ReceiptService().printAssurancePreventeTicket(
      context: context,
      officine: officine,
      saleSummary: summary,
      items: items,
      client: client,
      ayantDroit: ayantDroit,
      currentUser: user,
      isTestMode: settings.isTestPrintMode,
      paperWidth: settings.paperWidth,
      ticketCodeType: settings.ticketCodeType,
      numberOfCopies: copies,
      reference: reference,
      carnet: false,
      confirmEachCopy: false,
    );
  } else {
    await ReceiptService().printAssuranceSaleTicket(
      context: context,
      officine: officine,
      saleSummary: summary,
      items: items,
      client: client,
      ayantDroit: ayantDroit,
      paymentMethod: method ?? PaymentMethod(id: '0', name: 'COMPTANT'),
      currentUser: user,
      isTestMode: settings.isTestPrintMode,
      paperWidth: settings.paperWidth,
      numberOfCopies: copies,
      showQrCode: settings.showQrCodeOnSaleTicket,
      ticketCodeType: settings.ticketCodeType,
      montantVerse: montantVerse,
      monnaie: monnaie,
      reference: reference,
      carnet: false,
      confirmEachCopy: false,
    );
  }
}
