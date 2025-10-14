// lib/services/receipt_service.dart
// 14/10/2025 00:05
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/api/models/officine.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/api/models/user.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:sunmi_printer_plus/enums.dart';
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';
import 'package:sunmi_printer_plus/sunmi_style.dart';
import 'package:qr_flutter/qr_flutter.dart';

class ReceiptService {
  Future<void> printSaleTicket({
    required BuildContext context, required Officine officine, required SaleSummary saleSummary, required List<SaleItemDetail> items,
    required PaymentMethod paymentMethod, required User currentUser, required bool isTestMode, required int paperWidth,
    required bool showQrCode,
  }) async {
    if (isTestMode) {
      final ticketWidget = _buildSaleTicketWidget(context, officine, saleSummary, items, paymentMethod, currentUser, paperWidth, showQrCode);
      await _showTestTicketDialog(context, ticketWidget, paperWidth);
    } else {
      await _printSaleTicketSunmi(context, officine, saleSummary, items, paymentMethod, currentUser, paperWidth, showQrCode);
    }
  }

  Future<void> printPreventeTicket({
    required BuildContext context, required Officine officine, required SaleSummary saleSummary,
    required User currentUser, required bool isTestMode, required int paperWidth,
  }) async {
    if (isTestMode) {
      final ticketWidget = _buildPreventeTicketWidget(context, officine, saleSummary, currentUser, paperWidth);
      await _showTestTicketDialog(context, ticketWidget, paperWidth);
    } else {
      await _printPreventeTicketSunmi(context, officine, saleSummary, currentUser, paperWidth);
    }
  }

  Future<bool> _initializePrinter(BuildContext context) async { try { final bool? isConnected = await SunmiPrinter.bindingPrinter(); if (isConnected != true) { Constants.showSnackBar(context, "Imprimante non connectée.", isError: true); return false; } await SunmiPrinter.initPrinter(); return true; } catch (e) { Constants.showSnackBar(context, 'Erreur imprimante Sunmi: $e', isError: true); return false; } }

  Future<void> _printSaleTicketSunmi(BuildContext context, Officine officine, SaleSummary saleSummary, List<SaleItemDetail> items, PaymentMethod paymentMethod, User currentUser, int paperWidth, bool showQrCode) async {
    if (!await _initializePrinter(context)) return;
    try {
      await SunmiPrinter.startTransactionPrint(true);
      final int cols = paperWidth == 58 ? 32 : 48;
      final int articleWidth = paperWidth == 58 ? 14 : 26;
      final int financialWidth = paperWidth == 58 ? 8 : 10;
      String line([String ch = '-']) => List.filled(cols, ch).join();
      String fit(String s, int len) { final t = s.replaceAll("\n", " "); if (t.runes.length <= len) return t.padRight(len); return String.fromCharCodes(t.runes.take(len)); }
      String r(int v, int len) => Constants.formatNumber(v).padLeft(len);

      await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER);
      await SunmiPrinter.printText(officine.nomComplet.toUpperCase(), style: SunmiStyle(bold: true, fontSize: SunmiFontSize.MD));
      await SunmiPrinter.printText(officine.fullName);
      await SunmiPrinter.setAlignment(SunmiPrintAlign.LEFT);
      await SunmiPrinter.printText(line());
      await SunmiPrinter.printText(fit('Article', articleWidth) + fit('Qte*P.U', financialWidth) + fit('Total', financialWidth), style: SunmiStyle(bold: true));
      await SunmiPrinter.printText(line('.'));
      for (final item in items) {
        // MODIFICATION : Le nom du produit est tronqué s'il est trop long
        await SunmiPrinter.printText(fit(item.strNAME, cols));
        final String priceDetails = fit('', articleWidth) + '${item.intQUANTITY}*${Constants.formatNumber(item.intPRICEUNITAIR)}'.padRight(financialWidth) + r(item.intPRICE, financialWidth);
        await SunmiPrinter.printText(priceDetails);
      }
      await SunmiPrinter.printText(line());
      await SunmiPrinter.setAlignment(SunmiPrintAlign.RIGHT);
      await SunmiPrinter.printText('Total: ${Constants.formatNumber(saleSummary.montant)}');
      await SunmiPrinter.printText('NET A PAYER: ${Constants.formatNumber(saleSummary.montantNet)}', style: SunmiStyle(bold: true, fontSize: SunmiFontSize.MD));
      await SunmiPrinter.printText('Mode: ${paymentMethod.name.toUpperCase()}');
      await SunmiPrinter.printText(line());

      await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER);
      await SunmiPrinter.printText(DateFormat("dd/MM/yyyy HH:mm").format(DateTime.now()));
      await SunmiPrinter.printText("Vendeur: ${currentUser.fullName}");
      await SunmiPrinter.lineWrap(1);

      // MODIFICATION : Logique d'affichage du QR Code et de la référence
      if (showQrCode) {
        await SunmiPrinter.printQRCode(saleSummary.reference);
      }
      // La référence est toujours affichée, bien centrée
      await SunmiPrinter.printText(saleSummary.reference);
      // On ajoute 2 lignes de saut après la référence
      await SunmiPrinter.lineWrap(2);

      await SunmiPrinter.lineWrap(3);
      await SunmiPrinter.cut();
      await SunmiPrinter.exitTransactionPrint(true);
    } catch (e) {
      Constants.showSnackBar(context, 'Erreur d\'impression: $e', isError: true);
    }
  }

  Future<void> _printPreventeTicketSunmi(BuildContext context, Officine officine, SaleSummary saleSummary, User currentUser, int paperWidth) async {
    if (!await _initializePrinter(context)) return;
    try {
      await SunmiPrinter.startTransactionPrint(true);
      final int cols = paperWidth == 58 ? 32 : 48;
      String line([String ch = '-']) => List.filled(cols, ch).join();
      SunmiStyle defaultStyle = SunmiStyle(fontSize: SunmiFontSize.MD);
      await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER);
      await SunmiPrinter.printText(officine.nomComplet.toUpperCase(), style: SunmiStyle(bold: true, fontSize: SunmiFontSize.MD));
      await SunmiPrinter.printText(officine.fullName, style: defaultStyle);
      await SunmiPrinter.printText(line());
      await SunmiPrinter.printText('PRE-VENTE -- ${DateFormat("dd/MM/yyyy HH:mm:ss").format(DateTime.now())}', style: SunmiStyle(bold: true, fontSize: SunmiFontSize.MD));
      await SunmiPrinter.printText(line());
      await SunmiPrinter.lineWrap(1);
      await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER);
      await SunmiPrinter.printText('NET A PAYER: ${Constants.formatNumber(saleSummary.montantNet)}', style: SunmiStyle(bold: true, fontSize: SunmiFontSize.MD));
      await SunmiPrinter.lineWrap(1);
      await SunmiPrinter.printQRCode(saleSummary.reference, size: 8);
      await SunmiPrinter.printText(saleSummary.reference, style: defaultStyle);
      await SunmiPrinter.lineWrap(1);
      await SunmiPrinter.printText("Vendeur: ${currentUser.fullName}", style: defaultStyle);
      await SunmiPrinter.lineWrap(3);
      await SunmiPrinter.cut();
      await SunmiPrinter.exitTransactionPrint(true);
    } catch(e) {
      Constants.showSnackBar(context, 'Erreur d\'impression: $e', isError: true);
    }
  }

  Future<void> _showTestTicketDialog(BuildContext context, Widget ticketContent, int paperWidth) async { await showDialog( context: context, builder: (ctx) => AlertDialog( title: const Text("Aperçu du Ticket"), content: Container( width: paperWidth == 58 ? 300 : 420, child: ticketContent, ), actions: [ TextButton( child: const Text("Fermer"), onPressed: () => Navigator.of(ctx).pop(), ) ], ), ); }

  Widget _buildSaleTicketWidget(BuildContext context, Officine officine, SaleSummary saleSummary, List<SaleItemDetail> items, PaymentMethod paymentMethod, User currentUser, int paperWidth, bool showQrCode) {
    const textStyle = TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.black);
    const boldStyle = TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black);
    final int cols = paperWidth == 58 ? 32 : 48;
    String line([String ch = '-']) => List.filled(cols, ch).join();
    String fit(String s, int len) { final t = s.replaceAll("\n", " "); if (t.runes.length <= len) return t.padRight(len); return String.fromCharCodes(t.runes.take(len)); }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Text(officine.nomComplet.toUpperCase(), style: boldStyle.copyWith(fontSize: 14))),
          Center(child: Text(officine.fullName, style: textStyle)),
          Text(line(), style: textStyle),
          Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ Text("Article", style: boldStyle), Text("Qte*P.U   Total", style: boldStyle), ], ),
          Text(line('.'), style: textStyle),
          ...items.map((item) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(fit(item.strNAME, cols), style: textStyle),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${item.intQUANTITY}*${Constants.formatNumber(item.intPRICEUNITAIR)} = ${Constants.formatNumber(item.intPRICE)}',
                  style: textStyle,
                ),
              ),
            ],
          )),
          Text(line(), style: textStyle),
          Align(alignment: Alignment.centerRight, child: Text('Total: ${Constants.formatNumber(saleSummary.montant)}', style: textStyle)),
          Align(alignment: Alignment.centerRight, child: Text('NET A PAYER: ${Constants.formatNumber(saleSummary.montantNet)}', style: boldStyle)),
          Align(alignment: Alignment.centerRight, child: Text('Mode: ${paymentMethod.name.toUpperCase()}', style: textStyle)),
          Text(line(), style: textStyle),
          Center(child: Text(DateFormat("dd/MM/yyyy HH:mm").format(DateTime.now()), style: textStyle)),
          Center(child: Text("Vendeur: ${currentUser.fullName}", style: textStyle)),
          const SizedBox(height: 8),

          if (showQrCode)
            Center(
              child: QrImageView( data: saleSummary.reference, version: QrVersions.auto, size: 120.0, ),
            ),
          Center(child: Text(saleSummary.reference, style: textStyle)),
          const SizedBox(height: 16), // Simule les 2 lignes de saut
        ],
      ),
    );
  }

  Widget _buildPreventeTicketWidget(BuildContext context, Officine officine, SaleSummary saleSummary, User currentUser, int paperWidth) {
    const textStyle = TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.black);
    const boldStyle = TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black);
    final int cols = paperWidth == 58 ? 32 : 48;
    String line([String ch = '-']) => List.filled(cols, ch).join();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(officine.nomComplet.toUpperCase(), style: boldStyle.copyWith(fontSize: 14)),
          Text(officine.fullName, style: textStyle),
          Text(line(), style: textStyle),
          Text('PRE-VENTE -- ${DateFormat("dd/MM/yyyy HH:mm:ss").format(DateTime.now())}', style: boldStyle),
          Text(line(), style: textStyle),
          const SizedBox(height: 16),
          Center(
            child: Text(
                'NET A PAYER: ${Constants.formatNumber(saleSummary.montantNet)}',
                style: boldStyle.copyWith(fontSize: 14)
            ),
          ),
          const SizedBox(height: 16),
          Center(child: QrImageView(data: saleSummary.reference, version: QrVersions.auto, size: 120.0)),
          Center(child: Text(saleSummary.reference, style: textStyle)),
          const SizedBox(height: 8),
          Center(child: Text("Vendeur: ${currentUser.fullName}", style: textStyle)),
        ],
      ),
    );
  }
}