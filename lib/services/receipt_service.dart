// lib/services/receipt_service.dart
// 28/09/2025 03:04
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/api/models/officine.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:sunmi_printer_plus/enums.dart';
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';
import 'package:sunmi_printer_plus/sunmi_style.dart';

class ReceiptService {
  Future<bool> _initializePrinter(BuildContext context) async {
    try {
      final bool? isConnected = await SunmiPrinter.bindingPrinter();
      if (isConnected != true) {
        Constants.showSnackBar(context, "Imprimante non connectée.", isError: true);
        return false;
      }
      await SunmiPrinter.initPrinter();
      return true;
    } catch (e) {
      Constants.showSnackBar(context, 'Erreur imprimante Sunmi: $e', isError: true);
      return false;
    }
  }

  Future<void> printSaleTicket({
    required BuildContext context,
    required Officine officine,
    required SaleSummary saleSummary,
    required List<SaleItemDetail> items,
    required PaymentMethod paymentMethod,
  }) async {
    if (!await _initializePrinter(context)) return;

    try {
      await SunmiPrinter.startTransactionPrint(true);

      // --- Fonctions utilitaires de formatage (inspirées de votre code) ---
      const int cols = 32;
      String line([String ch = '-']) => List.filled(cols, ch).join();
      String fit(String s, int len) {
        final t = s.replaceAll("\n", " ");
        if (t.runes.length <= len) return t.padRight(len);
        return String.fromCharCodes(t.runes.take(len));
      }
      String r(int v, int len) => Constants.formatNumber(v).padLeft(len);

      // --- Entête ---
      await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER);
      await SunmiPrinter.printText(officine.nomComplet.toUpperCase(), style: SunmiStyle(bold: true, fontSize: SunmiFontSize.MD));
      await SunmiPrinter.printText(officine.fullName);

      await SunmiPrinter.setAlignment(SunmiPrintAlign.LEFT);
      await SunmiPrinter.printText(line());
      await SunmiPrinter.printText("Date: ${DateFormat("dd/MM/yyyy HH:mm").format(DateTime.now())}");
      await SunmiPrinter.printText("Ticket: ${saleSummary.reference}");
      await SunmiPrinter.printText(line());

      // --- Corps (Articles) ---
      await SunmiPrinter.printText(
        fit('Article', 16) + fit('Qte', 4) + fit('P.U', 6) + fit('Total', 6),
        style: SunmiStyle(bold: true),
      );
      await SunmiPrinter.printText(line('.'));

      for (final item in items) {
        // Imprime le nom du produit sur sa propre ligne pour éviter les coupures
        await SunmiPrinter.printText(item.strNAME);
        // Imprime les détails financiers sur la ligne suivante, alignés à droite
        final String priceDetails = fit('', 16) +
            item.intQUANTITY.toString().padLeft(4) +
            r(item.intPRICEUNITAIR, 6) +
            r(item.intPRICE, 6);
        await SunmiPrinter.printText(priceDetails);
      }
      await SunmiPrinter.printText(line());

      // --- Pied de page (Totaux) ---
      await SunmiPrinter.setAlignment(SunmiPrintAlign.RIGHT);
      await SunmiPrinter.printText('Total: ${Constants.formatNumber(saleSummary.montant)}');
      await SunmiPrinter.printText('Remise: ${Constants.formatNumber(saleSummary.remise)}');
      await SunmiPrinter.printText(
        'NET A PAYER: ${Constants.formatNumber(saleSummary.montantNet)}',
        style: SunmiStyle(bold: true, fontSize: SunmiFontSize.MD),
      );
      await SunmiPrinter.printText('Mode: ${paymentMethod.name.toUpperCase()}');
      await SunmiPrinter.printText(line());

      // --- QR Code ---
      await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER);
      await SunmiPrinter.printQRCode(saleSummary.reference);
      await SunmiPrinter.printText(saleSummary.reference);

      await SunmiPrinter.lineWrap(3);
      await SunmiPrinter.cut();
      await SunmiPrinter.exitTransactionPrint(true);

    } catch (e) {
      Constants.showSnackBar(context, 'Erreur d\'impression: $e', isError: true);
    }
  }

  Future<void> printPreventeTicket({
    required BuildContext context,
    required Officine officine,
    required SaleSummary saleSummary,
  }) async {
    if (!await _initializePrinter(context)) return;

    try {
      await SunmiPrinter.startTransactionPrint(true);

      String line([String ch = '-']) => List.filled(32, ch).join();

      // --- Entête ---
      await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER);
      await SunmiPrinter.printText(officine.nomComplet.toUpperCase(), style: SunmiStyle(bold: true, fontSize: SunmiFontSize.LG));
      await SunmiPrinter.printText(officine.fullName);
      await SunmiPrinter.printText(line());
      await SunmiPrinter.printText('TICKET DE PRE-VENTE', style: SunmiStyle(bold: true));
      await SunmiPrinter.printText(line());

      // --- Total ---
      await SunmiPrinter.printText('NET A PAYER', style: SunmiStyle(fontSize: SunmiFontSize.MD));
      await SunmiPrinter.printText(
        Constants.formatNumber(saleSummary.montantNet),
        style: SunmiStyle(bold: true, fontSize: SunmiFontSize.XL),
      );
      await SunmiPrinter.printText(line());

      // --- QR Code et Date (sur des lignes séparées pour plus de fiabilité) ---
      await SunmiPrinter.setAlignment(SunmiPrintAlign.LEFT);
      await SunmiPrinter.printQRCode(saleSummary.reference, size: 5);
      await SunmiPrinter.printText(saleSummary.reference);

      await SunmiPrinter.setAlignment(SunmiPrintAlign.RIGHT);
      await SunmiPrinter.printText(DateFormat("dd/MM/yyyy HH:mm").format(DateTime.now()));

      await SunmiPrinter.lineWrap(3);
      await SunmiPrinter.cut();
      await SunmiPrinter.exitTransactionPrint(true);
    } catch(e) {
      Constants.showSnackBar(context, 'Erreur d\'impression: $e', isError: true);
    }
  }
}