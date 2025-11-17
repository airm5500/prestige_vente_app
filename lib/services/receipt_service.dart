// lib/services/receipt_service.dart
// 09/11/2025 21:00 (Gestion Montant Versé)
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
import 'package:barcode_widget/barcode_widget.dart';

import 'package:prestige_vente_app/api/models/assurance_sale_summary.dart';
import 'package:prestige_vente_app/api/models/client_assurance.dart';
import 'package:prestige_vente_app/api/models/ayant_droit.dart';

class ReceiptService {

  // MODIFICATION : Ajout de montantVerse et monnaie
  Future<void> printSaleTicket({
    required BuildContext context, required Officine officine, required SaleSummary saleSummary, required List<SaleItemDetail> items,
    required PaymentMethod paymentMethod, required User currentUser, required bool isTestMode, required int paperWidth,
    required bool showQrCode,
    required String ticketCodeType,
    int? montantVerse,
    int? monnaie,
  }) async {
    if (isTestMode) {
      final ticketWidget = _buildSaleTicketWidget(context, officine, saleSummary, items, paymentMethod, currentUser, paperWidth, showQrCode, ticketCodeType, montantVerse: montantVerse, monnaie: monnaie);
      await _showTestTicketDialog(context, ticketWidget, paperWidth);
    } else {
      await _printSaleTicketSunmi(context, officine, saleSummary, items, paymentMethod, currentUser, paperWidth, showQrCode, ticketCodeType, montantVerse: montantVerse, monnaie: monnaie);
    }
  }

  // ... (printPreventeTicket et _initializePrinter restent inchangés) ...
  Future<void> printPreventeTicket({ required BuildContext context, required Officine officine, required SaleSummary saleSummary, required User currentUser, required bool isTestMode, required int paperWidth, required String ticketCodeType, }) async { if (isTestMode) { final ticketWidget = _buildPreventeTicketWidget(context, officine, saleSummary, currentUser, paperWidth, ticketCodeType); await _showTestTicketDialog(context, ticketWidget, paperWidth); } else { await _printPreventeTicketSunmi(context, officine, saleSummary, currentUser, paperWidth, ticketCodeType); } }
  Future<bool> _initializePrinter(BuildContext context) async { try { final bool? isConnected = await SunmiPrinter.bindingPrinter(); if (isConnected != true) { Constants.showSnackBar(context, "Imprimante non connectée.", isError: true); return false; } await SunmiPrinter.initPrinter(); return true; } catch (e) { Constants.showSnackBar(context, 'Erreur imprimante Sunmi: $e', isError: true); return false; } }

  // MODIFICATION : Ajout de montantVerse et monnaie
  Future<void> _printSaleTicketSunmi(BuildContext context, Officine officine, SaleSummary saleSummary, List<SaleItemDetail> items, PaymentMethod paymentMethod, User currentUser, int paperWidth, bool showQrCode, String ticketCodeType, {int? montantVerse, int? monnaie}) async {
    if (!await _initializePrinter(context)) return;
    try {
      await SunmiPrinter.startTransactionPrint(true);
      final int cols = paperWidth == 58 ? 32 : 48;
      final int articleWidth = paperWidth == 58 ? 14 : 26;
      final int financialWidth = paperWidth == 58 ? 8 : 10;
      String line([String ch = '-']) => List.filled(cols, ch).join();
      String fit(String s, int len) { final t = s.replaceAll("\n", " "); if (t.runes.length <= len) return t.padRight(len); return String.fromCharCodes(t.runes.take(len)); }
      String r(int v, int len) => Constants.formatNumber(v).padLeft(len);

      final headerAlign = paperWidth == 58 ? SunmiPrintAlign.LEFT : SunmiPrintAlign.CENTER;
      await SunmiPrinter.setAlignment(headerAlign);

      await SunmiPrinter.printText(officine.nomComplet.toUpperCase(), style: SunmiStyle(bold: true, fontSize: SunmiFontSize.MD));
      await SunmiPrinter.printText(officine.fullName);

      await SunmiPrinter.setAlignment(SunmiPrintAlign.LEFT);
      await SunmiPrinter.printText(line());
      await SunmiPrinter.printText(fit('Article', articleWidth) + fit('Qte*P.U', financialWidth) + fit('Total', financialWidth), style: SunmiStyle(bold: true));
      await SunmiPrinter.printText(line('.'));
      for (final item in items) {
        await SunmiPrinter.printText(fit(item.strNAME, cols));
        final String priceDetails = fit('', articleWidth) + '${item.intQUANTITY}*${Constants.formatNumber(item.intPRICEUNITAIR)}'.padRight(financialWidth) + r(item.intPRICE, financialWidth);
        await SunmiPrinter.printText(priceDetails);
      }
      await SunmiPrinter.printText(line());
      await SunmiPrinter.setAlignment(SunmiPrintAlign.RIGHT);
      await SunmiPrinter.printText('Total: ${Constants.formatNumber(saleSummary.montant)}');
      await SunmiPrinter.printText('NET A PAYER: ${Constants.formatNumber(saleSummary.montantNet)}', style: SunmiStyle(bold: true, fontSize: SunmiFontSize.MD));

      // MODIFICATION : Ajout des lignes Montant Versé / Monnaie
      if (montantVerse != null) {
        await SunmiPrinter.printText('Montant Versé: ${Constants.formatNumber(montantVerse)}');
      }
      if (monnaie != null && monnaie > 0) {
        await SunmiPrinter.printText('Monnaie: ${Constants.formatNumber(monnaie)}', style: SunmiStyle(bold: true));
      }
      // FIN MODIFICATION

      await SunmiPrinter.printText('Mode: ${paymentMethod.name.toUpperCase()}');
      await SunmiPrinter.printText(line());

      await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER);
      await SunmiPrinter.printText(DateFormat("dd/MM/yyyy HH:mm").format(DateTime.now()));
      await SunmiPrinter.printText("Vendeur: ${currentUser.fullName}");
      await SunmiPrinter.lineWrap(1);

      if (showQrCode) {
        if (ticketCodeType == 'QR_CODE') {
          await SunmiPrinter.printQRCode(saleSummary.reference);
        } else {
          await SunmiPrinter.printBarCode(saleSummary.reference,
            barcodeType: SunmiBarcodeType.CODE128,
            height: 60,
            width: 2,
          );
        }
      }

      await SunmiPrinter.printText(saleSummary.reference);
      await SunmiPrinter.lineWrap(2);

      await SunmiPrinter.lineWrap(3);
      await SunmiPrinter.cut();
      await SunmiPrinter.exitTransactionPrint(true);
    } catch (e) {
      Constants.showSnackBar(context, 'Erreur d\'impression: $e', isError: true);
    }
  }

  // ... (_printPreventeTicketSunmi reste inchangé) ...
  Future<void> _printPreventeTicketSunmi(BuildContext context, Officine officine, SaleSummary saleSummary, User currentUser, int paperWidth, String ticketCodeType) async { if (!await _initializePrinter(context)) return; try { await SunmiPrinter.startTransactionPrint(true); final int cols = paperWidth == 58 ? 32 : 48; String line([String ch = '-']) => List.filled(cols, ch).join(); SunmiStyle defaultStyle = SunmiStyle(fontSize: SunmiFontSize.MD); final headerAlign = paperWidth == 58 ? SunmiPrintAlign.LEFT : SunmiPrintAlign.CENTER; await SunmiPrinter.setAlignment(headerAlign); await SunmiPrinter.printText(officine.nomComplet.toUpperCase(), style: SunmiStyle(bold: true, fontSize: SunmiFontSize.MD)); await SunmiPrinter.printText(officine.fullName, style: defaultStyle); await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER); await SunmiPrinter.printText(line()); await SunmiPrinter.printText('PRE-VENTE -- ${DateFormat("dd/MM/yyyy HH:mm:ss").format(DateTime.now())}', style: SunmiStyle(bold: true, fontSize: SunmiFontSize.MD)); await SunmiPrinter.printText(line()); await SunmiPrinter.lineWrap(1); await SunmiPrinter.printText('NET A PAYER: ${Constants.formatNumber(saleSummary.montantNet)}', style: SunmiStyle(bold: true, fontSize: SunmiFontSize.MD)); await SunmiPrinter.lineWrap(1); if (ticketCodeType == 'QR_CODE') { await SunmiPrinter.printQRCode(saleSummary.reference); } else { await SunmiPrinter.printBarCode(saleSummary.reference, barcodeType: SunmiBarcodeType.CODE128, height: 60, width: 2, ); } await SunmiPrinter.printText(saleSummary.reference, style: defaultStyle); await SunmiPrinter.lineWrap(1); await SunmiPrinter.printText("Vendeur: ${currentUser.fullName}", style: defaultStyle); await SunmiPrinter.lineWrap(5); await SunmiPrinter.cut(); await SunmiPrinter.exitTransactionPrint(true); } catch(e) { Constants.showSnackBar(context, 'Erreur d\'impression: $e', isError: true); } }

  // --- LOGIQUE VENTE ASSURANCE / CARNET ---

  // MODIFICATION : Ajout de montantVerse et monnaie
  Future<void> printAssuranceSaleTicket({
    required BuildContext context,
    required Officine officine,
    required AssuranceSaleSummary saleSummary,
    required List<SaleItemDetail> items,
    required ClientAssurance client,
    required AyantDroit ayantDroit,
    required PaymentMethod paymentMethod,
    required User currentUser,
    required bool isTestMode,
    required int paperWidth,
    required String ticketCodeType,
    int numberOfCopies = 1,
    int? montantVerse,
    int? monnaie,
  }) async {
    for (int i = 0; i < numberOfCopies; i++) {
      if (i > 0) {
        final bool? rePrint = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Réimpression'),
            content: Text('Voulez-vous réimprimer le ticket ? (${i + 1}/$numberOfCopies)'),
            actions: [
              TextButton(child: const Text('Non'), onPressed: () => Navigator.of(ctx).pop(false)),
              ElevatedButton(child: const Text('Oui'), onPressed: () => Navigator.of(ctx).pop(true)),
            ],
          ),
        );
        if (rePrint != true) break;
      }

      if (isTestMode) {
        final ticketWidget = _buildAssuranceSaleTicketWidget(context, officine, saleSummary, items, client, ayantDroit, paymentMethod, currentUser, paperWidth, ticketCodeType, montantVerse: montantVerse, monnaie: monnaie);
        await _showTestTicketDialog(context, ticketWidget, paperWidth);
      } else {
        await _printAssuranceSaleTicketSunmi(context, officine, saleSummary, items, client, ayantDroit, paymentMethod, currentUser, paperWidth, ticketCodeType, montantVerse: montantVerse, monnaie: monnaie);
      }
    }
  }

  // ... (printAssurancePreventeTicket reste inchangé, il a déjà le QR Code) ...
  Future<void> printAssurancePreventeTicket({ required BuildContext context, required Officine officine, required AssuranceSaleSummary saleSummary, required List<SaleItemDetail> items, required ClientAssurance client, required AyantDroit ayantDroit, required User currentUser, required bool isTestMode, required int paperWidth, required String ticketCodeType, int numberOfCopies = 1, }) async { for (int i = 0; i < numberOfCopies; i++) { if (i > 0) { final bool? rePrint = await showDialog<bool>( context: context, barrierDismissible: false, builder: (ctx) => AlertDialog( title: const Text('Réimpression'), content: Text('Voulez-vous réimprimer le ticket ? (${i + 1}/$numberOfCopies)'), actions: [ TextButton(child: const Text('Non'), onPressed: () => Navigator.of(ctx).pop(false)), ElevatedButton(child: const Text('Oui'), onPressed: () => Navigator.of(ctx).pop(true)), ], ), ); if (rePrint != true) break; } if (isTestMode) { final ticketWidget = _buildAssurancePreventeTicketWidget(context, officine, saleSummary, items, client, ayantDroit, currentUser, paperWidth, ticketCodeType); await _showTestTicketDialog(context, ticketWidget, paperWidth); } else { await _printAssurancePreventeTicketSunmi(context, officine, saleSummary, items, client, ayantDroit, currentUser, paperWidth, ticketCodeType); } } }

  // MODIFICATION : Ajout de montantVerse et monnaie
  Future<void> _printAssuranceSaleTicketSunmi(BuildContext context, Officine officine, AssuranceSaleSummary saleSummary, List<SaleItemDetail> items, ClientAssurance client, AyantDroit ayantDroit, PaymentMethod paymentMethod, User currentUser, int paperWidth, String ticketCodeType, {int? montantVerse, int? monnaie}) async {
    if (!await _initializePrinter(context)) return;
    try {
      await SunmiPrinter.startTransactionPrint(true);
      final int cols = paperWidth == 58 ? 32 : 48;
      final int articleWidth = paperWidth == 58 ? 14 : 26;
      final int financialWidth = paperWidth == 58 ? 8 : 10;
      String line([String ch = '-']) => List.filled(cols, ch).join();
      String fit(String s, int len) { final t = s.replaceAll("\n", " "); if (t.runes.length <= len) return t.padRight(len); return String.fromCharCodes(t.runes.take(len)); }
      String r(int v, int len) => Constants.formatNumber(v).padLeft(len);

      final headerAlign = paperWidth == 58 ? SunmiPrintAlign.LEFT : SunmiPrintAlign.CENTER;
      await SunmiPrinter.setAlignment(headerAlign);
      await SunmiPrinter.printText(officine.nomComplet.toUpperCase(), style: SunmiStyle(bold: true, fontSize: SunmiFontSize.MD));
      await SunmiPrinter.printText(officine.fullName);

      await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER);
      final title = saleSummary.tierspayants.any((tp) => tp.taux < 100) ? 'VENTE ASSURANCE' : 'VENTE CARNET';
      await SunmiPrinter.printText(title, style: SunmiStyle(bold: true));

      await SunmiPrinter.setAlignment(SunmiPrintAlign.LEFT);
      await SunmiPrinter.printText(line());
      await SunmiPrinter.printText('Client: ${client.fullName}');
      await SunmiPrinter.printText('Patient: ${ayantDroit.fullName}');
      await SunmiPrinter.printText('Matricule: ${ayantDroit.strNUMEROSECURITESOCIAL}');

      await SunmiPrinter.printText(line());
      await SunmiPrinter.printText(fit('Article', articleWidth) + fit('Qte*P.U', financialWidth) + fit('Total', financialWidth), style: SunmiStyle(bold: true));
      await SunmiPrinter.printText(line('.'));

      for (final item in items) {
        await SunmiPrinter.printText(fit(item.strNAME, cols));
        final String priceDetails = fit('', articleWidth) + '${item.intQUANTITY}*${Constants.formatNumber(item.intPRICEUNITAIR)}'.padRight(financialWidth) + r(item.intPRICE, financialWidth);
        await SunmiPrinter.printText(priceDetails);
      }

      await SunmiPrinter.printText(line());
      await SunmiPrinter.setAlignment(SunmiPrintAlign.RIGHT);

      await SunmiPrinter.printText('Total Brut: ${Constants.formatNumber(saleSummary.montant)}');
      await SunmiPrinter.printText('Part Assurance: ${Constants.formatNumber(saleSummary.montantTp)}', style: SunmiStyle(bold: true));

      for(var tp in saleSummary.tierspayants) {
        final tpClientInfo = client.tiersPayants.firstWhere((c) => c.compteTp == tp.compteTp, orElse: () => ClientTiersPayant(lgTIERSPAYANTID: '', tpFullName: 'N/A', taux: 0, numSecurity: '', compteTp: '', order: 0, principal: false));
        await SunmiPrinter.printText('${tpClientInfo.tpFullName} (${tp.taux}%)');
        await SunmiPrinter.printText('  N°Bon ${tp.numBon}: ${Constants.formatNumber(tp.tpnet)}');
      }

      await SunmiPrinter.printText('PART CLIENT: ${Constants.formatNumber(saleSummary.montantNet)}', style: SunmiStyle(bold: true, fontSize: SunmiFontSize.MD));

      // MODIFICATION : Ajout des lignes Montant Versé / Monnaie
      if (montantVerse != null) {
        await SunmiPrinter.printText('Montant Versé: ${Constants.formatNumber(montantVerse)}');
      }
      if (monnaie != null && monnaie > 0) {
        await SunmiPrinter.printText('Monnaie: ${Constants.formatNumber(monnaie)}', style: SunmiStyle(bold: true));
      }
      // FIN MODIFICATION

      if (saleSummary.montantNet > 0) {
        await SunmiPrinter.printText('Mode: ${paymentMethod.name.toUpperCase()}');
      }

      await SunmiPrinter.printText(line());
      await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER);
      await SunmiPrinter.printText(DateFormat("dd/MM/yyyy HH:mm").format(DateTime.now()));
      await SunmiPrinter.printText("Vendeur: ${currentUser.fullName}");

      await SunmiPrinter.lineWrap(5);
      await SunmiPrinter.cut();
      await SunmiPrinter.exitTransactionPrint(true);
    } catch (e) {
      Constants.showSnackBar(context, 'Erreur d\'impression: $e', isError: true);
    }
  }

  Future<void> _printAssurancePreventeTicketSunmi(BuildContext context, Officine officine, AssuranceSaleSummary saleSummary, List<SaleItemDetail> items, ClientAssurance client, AyantDroit ayantDroit, User currentUser, int paperWidth, String ticketCodeType) async {
    if (!await _initializePrinter(context)) return;
    try {
      final String reference = items.isNotEmpty ? items.first.strREF : '';
      await SunmiPrinter.startTransactionPrint(true);
      final int cols = paperWidth == 58 ? 32 : 48;
      final int articleWidth = paperWidth == 58 ? 14 : 26;
      final int financialWidth = paperWidth == 58 ? 8 : 10;
      String line([String ch = '-']) => List.filled(cols, ch).join();
      String fit(String s, int len) { final t = s.replaceAll("\n", " "); if (t.runes.length <= len) return t.padRight(len); return String.fromCharCodes(t.runes.take(len)); }
      String r(int v, int len) => Constants.formatNumber(v).padLeft(len);
      SunmiStyle defaultStyle = SunmiStyle(fontSize: SunmiFontSize.MD);
      final headerAlign = paperWidth == 58 ? SunmiPrintAlign.LEFT : SunmiPrintAlign.CENTER;
      await SunmiPrinter.setAlignment(headerAlign);
      await SunmiPrinter.printText(officine.nomComplet.toUpperCase(), style: SunmiStyle(bold: true, fontSize: SunmiFontSize.MD));
      await SunmiPrinter.printText(officine.fullName, style: defaultStyle);
      await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER);
      await SunmiPrinter.printText(line());
      final title = saleSummary.tierspayants.any((tp) => tp.taux < 100) ? 'PRE-VENTE ASSURANCE' : 'PRE-VENTE CARNET';
      await SunmiPrinter.printText(title, style: SunmiStyle(bold: true, fontSize: SunmiFontSize.MD));
      await SunmiPrinter.printText(DateFormat("dd/MM/yyyy HH:mm:ss").format(DateTime.now()));
      await SunmiPrinter.setAlignment(SunmiPrintAlign.LEFT);
      await SunmiPrinter.printText(line());
      await SunmiPrinter.printText('Client: ${client.fullName}');
      await SunmiPrinter.printText('Patient: ${ayantDroit.fullName}');
      await SunmiPrinter.printText('Matricule: ${ayantDroit.strNUMEROSECURITESOCIAL}');
      await SunmiPrinter.printText(line());
      await SunmiPrinter.printText(fit('Article', articleWidth) + fit('Qte*P.U', financialWidth) + fit('Total', financialWidth), style: SunmiStyle(bold: true));
      await SunmiPrinter.printText(line('.'));
      for (final item in items) {
        await SunmiPrinter.printText(fit(item.strNAME, cols));
        final String priceDetails = fit('', articleWidth) + '${item.intQUANTITY}*${Constants.formatNumber(item.intPRICEUNITAIR)}'.padRight(financialWidth) + r(item.intPRICE, financialWidth);
        await SunmiPrinter.printText(priceDetails);
      }
      await SunmiPrinter.printText(line());
      await SunmiPrinter.setAlignment(SunmiPrintAlign.RIGHT);
      await SunmiPrinter.printText('Total Brut: ${Constants.formatNumber(saleSummary.montant)}');
      await SunmiPrinter.printText('Part Assurance: ${Constants.formatNumber(saleSummary.montantTp)}', style: SunmiStyle(bold: true));
      for(var tp in saleSummary.tierspayants) {
        final tpClientInfo = client.tiersPayants.firstWhere((c) => c.compteTp == tp.compteTp, orElse: () => ClientTiersPayant(lgTIERSPAYANTID: '', tpFullName: 'N/A', taux: 0, numSecurity: '', compteTp: '', order: 0, principal: false));
        await SunmiPrinter.printText('${tpClientInfo.tpFullName} (${tp.taux}%)');
        await SunmiPrinter.printText('  N°Bon ${tp.numBon}: ${Constants.formatNumber(tp.tpnet)}');
      }
      await SunmiPrinter.printText('PART CLIENT: ${Constants.formatNumber(saleSummary.montantNet)}', style: SunmiStyle(bold: true, fontSize: SunmiFontSize.MD));
      await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER);
      await SunmiPrinter.lineWrap(1);
      if (ticketCodeType == 'QR_CODE') {
        await SunmiPrinter.printQRCode(reference);
      } else {
        await SunmiPrinter.printBarCode(reference,
          barcodeType: SunmiBarcodeType.CODE128,
          height: 60,
          width: 2,
        );
      }
      await SunmiPrinter.printText(reference, style: defaultStyle);
      await SunmiPrinter.lineWrap(1);
      await SunmiPrinter.printText("Vendeur: ${currentUser.fullName}", style: defaultStyle);
      await SunmiPrinter.lineWrap(5);
      await SunmiPrinter.cut();
      await SunmiPrinter.exitTransactionPrint(true);
    } catch(e) {
      Constants.showSnackBar(context, 'Erreur d\'impression: $e', isError: true);
    }
  }


  // --- LOGIQUE D'APERÇU (Mode Test) ---

  Future<void> _showTestTicketDialog(BuildContext context, Widget ticketContent, int paperWidth) async { await showDialog( context: context, builder: (ctx) => AlertDialog( title: const Text("Aperçu du Ticket"), content: Container( width: paperWidth == 58 ? 300 : 420, child: SingleChildScrollView(child: ticketContent), ), actions: [ TextButton( child: const Text("Fermer"), onPressed: () => Navigator.of(ctx).pop(), ) ], ), ); }

  // MODIFICATION : Ajout de montantVerse et monnaie
  Widget _buildSaleTicketWidget(BuildContext context, Officine officine, SaleSummary saleSummary, List<SaleItemDetail> items, PaymentMethod paymentMethod, User currentUser, int paperWidth, bool showQrCode, String ticketCodeType, {int? montantVerse, int? monnaie}) {
    const textStyle = TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.black);
    const boldStyle = TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black);
    final int cols = paperWidth == 58 ? 32 : 48;
    String line([String ch = '-']) => List.filled(cols, ch).join();
    String fit(String s, int len) { final t = s.replaceAll("\n", " "); if (t.runes.length <= len) return t.padRight(len); return String.fromCharCodes(t.runes.take(len)); }
    final headerCrossAlign = paperWidth == 58 ? CrossAxisAlignment.start : CrossAxisAlignment.center;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: paperWidth == 58 ? Alignment.centerLeft : Alignment.center,
          child: Column(
            crossAxisAlignment: headerCrossAlign,
            children: [
              Text(officine.nomComplet.toUpperCase(), style: boldStyle.copyWith(fontSize: 14)),
              Text(officine.fullName, style: textStyle),
            ],
          ),
        ),
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

        // MODIFICATION : Ajout des lignes Montant Versé / Monnaie
        if (montantVerse != null)
          Align(alignment: Alignment.centerRight, child: Text('Montant Versé: ${Constants.formatNumber(montantVerse)}', style: textStyle)),
        if (monnaie != null && monnaie > 0)
          Align(alignment: Alignment.centerRight, child: Text('Monnaie: ${Constants.formatNumber(monnaie)}', style: boldStyle)),
        // FIN MODIFICATION

        Align(alignment: Alignment.centerRight, child: Text('Mode: ${paymentMethod.name.toUpperCase()}', style: textStyle)),
        Text(line(), style: textStyle),
        Center(child: Text(DateFormat("dd/MM/yyyy HH:mm").format(DateTime.now()), style: textStyle)),
        Center(child: Text("Vendeur: ${currentUser.fullName}", style: textStyle)),
        const SizedBox(height: 8),
        if (showQrCode)
          Center(
            child: ticketCodeType == 'QR_CODE'
                ? QrImageView( data: saleSummary.reference, version: QrVersions.auto, size: 120.0, )
                : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: BarcodeWidget(
                barcode: Barcode.code128(),
                data: saleSummary.reference,
                style: textStyle.copyWith(fontSize: 0),
                drawText: false,
                height: 50,
              ),
            ),
          ),
        Center(child: Text(saleSummary.reference, style: textStyle)),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildPreventeTicketWidget(BuildContext context, Officine officine, SaleSummary saleSummary, User currentUser, int paperWidth, String ticketCodeType) {
    // ... (Inchangé) ...
    const textStyle = TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.black);
    const boldStyle = TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black);
    final int cols = paperWidth == 58 ? 32 : 48;
    String line([String ch = '-']) => List.filled(cols, ch).join();
    final headerCrossAlign = paperWidth == 58 ? CrossAxisAlignment.start : CrossAxisAlignment.center;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Align(
          alignment: paperWidth == 58 ? Alignment.centerLeft : Alignment.center,
          child: Column(
            crossAxisAlignment: headerCrossAlign,
            children: [
              Text(officine.nomComplet.toUpperCase(), style: boldStyle.copyWith(fontSize: 14)),
              Text(officine.fullName, style: textStyle),
            ],
          ),
        ),
        Text(line(), style: textStyle),
        Text('PRE-VENTE -- ${DateFormat("dd/MM/yyyy HH:mm:ss").format(DateTime.now())}', style: boldStyle),
        Text(line(), style: textStyle),
        const SizedBox(height: 16),
        Text(
            'NET A PAYER: ${Constants.formatNumber(saleSummary.montantNet)}',
            style: boldStyle.copyWith(fontSize: 14)
        ),
        const SizedBox(height: 16),
        Center(
          child: ticketCodeType == 'QR_CODE'
              ? QrImageView(data: saleSummary.reference, version: QrVersions.auto, size: 120.0)
              : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: BarcodeWidget(
              barcode: Barcode.code128(),
              data: saleSummary.reference,
              style: textStyle.copyWith(fontSize: 0),
              drawText: false,
              height: 50,
            ),
          ),
        ),
        Text(saleSummary.reference, style: textStyle),
        const SizedBox(height: 8),
        Text("Vendeur: ${currentUser.fullName}", style: textStyle),
        const SizedBox(height: 16),
      ],
    );
  }

  // MODIFICATION : Ajout de montantVerse et monnaie
  Widget _buildAssuranceSaleTicketWidget(BuildContext context, Officine officine, AssuranceSaleSummary saleSummary, List<SaleItemDetail> items, ClientAssurance client, AyantDroit ayantDroit, PaymentMethod paymentMethod, User currentUser, int paperWidth, String ticketCodeType, {int? montantVerse, int? monnaie}) {
    const textStyle = TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.black);
    const boldStyle = TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black);
    final int cols = paperWidth == 58 ? 32 : 48;
    String line([String ch = '-']) => List.filled(cols, ch).join();
    String fit(String s, int len) { final t = s.replaceAll("\n", " "); if (t.runes.length <= len) return t.padRight(len); return String.fromCharCodes(t.runes.take(len)); }
    final headerCrossAlign = paperWidth == 58 ? CrossAxisAlignment.start : CrossAxisAlignment.center;

    final title = saleSummary.tierspayants.any((tp) => tp.taux < 100) ? 'VENTE ASSURANCE' : 'VENTE CARNET';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: paperWidth == 58 ? Alignment.centerLeft : Alignment.center,
          child: Column(
            crossAxisAlignment: headerCrossAlign,
            children: [
              Text(officine.nomComplet.toUpperCase(), style: boldStyle.copyWith(fontSize: 14)),
              Text(officine.fullName, style: textStyle),
            ],
          ),
        ),
        Center(child: Text(title, style: boldStyle)),
        Text(line(), style: textStyle),
        Text('Client: ${client.fullName}', style: textStyle),
        Text('Patient: ${ayantDroit.fullName}', style: textStyle),
        Text('Matricule: ${ayantDroit.strNUMEROSECURITESOCIAL}', style: textStyle),
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
        Align(alignment: Alignment.centerRight, child: Text('Total Brut: ${Constants.formatNumber(saleSummary.montant)}', style: textStyle)),
        Align(alignment: Alignment.centerRight, child: Text('Part Assurance: ${Constants.formatNumber(saleSummary.montantTp)}', style: boldStyle)),
        ...saleSummary.tierspayants.map((tp) {
          final tpClientInfo = client.tiersPayants.firstWhere((c) => c.compteTp == tp.compteTp, orElse: () => ClientTiersPayant(lgTIERSPAYANTID: '', tpFullName: 'N/A', taux: 0, numSecurity: '', compteTp: '', order: 0, principal: false));
          return Align(
              alignment: Alignment.centerRight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${tpClientInfo.tpFullName} (${tp.taux}%)', style: textStyle),
                  Text('  N°Bon ${tp.numBon}: ${Constants.formatNumber(tp.tpnet)}', style: textStyle),
                ],
              )
          );
        }),
        Align(alignment: Alignment.centerRight, child: Text('PART CLIENT: ${Constants.formatNumber(saleSummary.montantNet)}', style: boldStyle.copyWith(fontSize: 14))),

        // MODIFICATION : Ajout des lignes Montant Versé / Monnaie
        if (montantVerse != null)
          Align(alignment: Alignment.centerRight, child: Text('Montant Versé: ${Constants.formatNumber(montantVerse)}', style: textStyle)),
        if (monnaie != null && monnaie > 0)
          Align(alignment: Alignment.centerRight, child: Text('Monnaie: ${Constants.formatNumber(monnaie)}', style: boldStyle)),
        // FIN MODIFICATION

        if (saleSummary.montantNet > 0)
          Align(alignment: Alignment.centerRight, child: Text('Mode: ${paymentMethod.name.toUpperCase()}', style: textStyle)),

        Text(line(), style: textStyle),
        Center(child: Text(DateFormat("dd/MM/yyyy HH:mm").format(DateTime.now()), style: textStyle)),
        Center(child: Text("Vendeur: ${currentUser.fullName}", style: textStyle)),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildAssurancePreventeTicketWidget(BuildContext context, Officine officine, AssuranceSaleSummary saleSummary, List<SaleItemDetail> items, ClientAssurance client, AyantDroit ayantDroit, User currentUser, int paperWidth, String ticketCodeType) {
    const textStyle = TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.black);
    const boldStyle = TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black);
    final int cols = paperWidth == 58 ? 32 : 48;
    String line([String ch = '-']) => List.filled(cols, ch).join();
    String fit(String s, int len) { final t = s.replaceAll("\n", " "); if (t.runes.length <= len) return t.padRight(len); return String.fromCharCodes(t.runes.take(len)); }
    final headerCrossAlign = paperWidth == 58 ? CrossAxisAlignment.start : CrossAxisAlignment.center;

    final String reference = items.isNotEmpty ? items.first.strREF : '';
    final title = saleSummary.tierspayants.any((tp) => tp.taux < 100) ? 'PRE-VENTE ASSURANCE' : 'PRE-VENTE CARNET';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: paperWidth == 58 ? Alignment.centerLeft : Alignment.center,
          child: Column(
            crossAxisAlignment: headerCrossAlign,
            children: [
              Text(officine.nomComplet.toUpperCase(), style: boldStyle.copyWith(fontSize: 14)),
              Text(officine.fullName, style: textStyle),
            ],
          ),
        ),
        Center(child: Text(title, style: boldStyle)),
        Center(child: Text(DateFormat("dd/MM/yyyy HH:mm:ss").format(DateTime.now()), style: textStyle)),
        Text(line(), style: textStyle),
        Text('Client: ${client.fullName}', style: textStyle),
        Text('Patient: ${ayantDroit.fullName}', style: textStyle),
        Text('Matricule: ${ayantDroit.strNUMEROSECURITESOCIAL}', style: textStyle),
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
        Align(alignment: Alignment.centerRight, child: Text('Total Brut: ${Constants.formatNumber(saleSummary.montant)}', style: textStyle)),
        Align(alignment: Alignment.centerRight, child: Text('Part Assurance: ${Constants.formatNumber(saleSummary.montantTp)}', style: boldStyle)),
        ...saleSummary.tierspayants.map((tp) {
          final tpClientInfo = client.tiersPayants.firstWhere((c) => c.compteTp == tp.compteTp, orElse: () => ClientTiersPayant(lgTIERSPAYANTID: '', tpFullName: 'N/A', taux: 0, numSecurity: '', compteTp: '', order: 0, principal: false));
          return Align(
              alignment: Alignment.centerRight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${tpClientInfo.tpFullName} (${tp.taux}%)', style: textStyle),
                  Text('  N°Bon ${tp.numBon}: ${Constants.formatNumber(tp.tpnet)}', style: textStyle),
                ],
              )
          );
        }),
        Align(alignment: Alignment.centerRight, child: Text('PART CLIENT: ${Constants.formatNumber(saleSummary.montantNet)}', style: boldStyle.copyWith(fontSize: 14))),
        Text(line(), style: textStyle),

        const SizedBox(height: 16),
        Center(
          child: ticketCodeType == 'QR_CODE'
              ? QrImageView(data: reference, version: QrVersions.auto, size: 120.0)
              : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: BarcodeWidget(
              barcode: Barcode.code128(),
              data: reference,
              style: textStyle.copyWith(fontSize: 0),
              drawText: false,
              height: 50,
            ),
          ),
        ),
        Center(child: Text(reference, style: textStyle)),
        const SizedBox(height: 8),

        Center(child: Text("Vendeur: ${currentUser.fullName}", style: textStyle)),
        const SizedBox(height: 16),
      ],
    );
  }
}