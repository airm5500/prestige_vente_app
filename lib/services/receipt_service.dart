// lib/services/receipt_service.dart
// CORRECTION : SÉPARATION NETTE ENTRE VENTE (DÉTAILLÉE) ET PRÉVENTE (MINIMALISTE)
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

/// Détail d'un mode de règlement sur le ticket (paiement en plusieurs modes) ; [recu]/[rendu] : espèces.
typedef TicketReglement = ({String mode, int montant, int? recu, int? rendu});

/// Lignes du ticket pour un paiement en plusieurs modes (« ESPECES: 5 000 », « reçu 10 000 / rendu 5 000 »).
List<String> ticketReglementLines(List<TicketReglement> reglements) => [
      for (final r in reglements) ...[
        '${r.mode.toUpperCase()}: ${Constants.formatNumber(r.montant)}',
        if (r.recu != null) 'reçu ${Constants.formatNumber(r.recu!)} / rendu ${Constants.formatNumber(r.rendu ?? 0)}',
      ],
    ];

/// Ticket d'une vente saisie hors ligne : « PROVISOIRE — HL-0007 ».
String provisoireTitre(String numero) => 'PROVISOIRE — $numero';
const String provisoireNote = 'Vente hors ligne : envoi au retour du serveur';

class ReceiptService {

  // ==========================================
  // 1. POINTS D'ENTRÉE PUBLICS
  // ==========================================

  // --- VENTE COMPTANT ---
  Future<void> printSaleTicket({
    required BuildContext context, required Officine officine, required SaleSummary saleSummary, required List<SaleItemDetail> items,
    required PaymentMethod paymentMethod, required User currentUser, required bool isTestMode, required int paperWidth,
    required bool showQrCode, required String ticketCodeType,
    int? montantVerse, int? monnaie,
    // Optionnel (nouvelle version) : détail par mode ; null = comportement d'origine.
    List<TicketReglement>? reglements,
    // Optionnel (hors ligne) : numéro provisoire « HL-0007 » ; null = comportement d'origine.
    String? provisoire,
  }) async {
    if (isTestMode) {
      final ticketWidget = _buildSaleTicketWidget(context, officine, saleSummary, items, paymentMethod, currentUser, paperWidth, showQrCode, ticketCodeType, montantVerse: montantVerse, monnaie: monnaie, reglements: reglements, provisoire: provisoire);
      await _showTestTicketDialog(context, ticketWidget, paperWidth);
    } else {
      await _printSaleTicketSunmi(context, officine, saleSummary, items, paymentMethod, currentUser, paperWidth, showQrCode, ticketCodeType, montantVerse: montantVerse, monnaie: monnaie, reglements: reglements, provisoire: provisoire);
    }
  }

  // --- PRÉVENTE COMPTANT ---
  Future<void> printPreventeTicket({
    required BuildContext context, required Officine officine, required SaleSummary saleSummary, required User currentUser, required bool isTestMode, required int paperWidth, required String ticketCodeType,
    // Optionnel (hors ligne) : numéro provisoire « HL-0007 » ; null = comportement d'origine.
    String? provisoire,
  }) async {
    if (isTestMode) {
      final ticketWidget = _buildPreventeTicketWidget(context, officine, saleSummary, currentUser, paperWidth, ticketCodeType, provisoire: provisoire);
      await _showTestTicketDialog(context, ticketWidget, paperWidth);
    } else {
      await _printPreventeTicketSunmi(context, officine, saleSummary, currentUser, paperWidth, ticketCodeType, provisoire: provisoire);
    }
  }

  // --- VENTE ASSURANCE / CARNET (DOIT ÊTRE DÉTAILLÉE) ---
  Future<void> printAssuranceSaleTicket({
    required BuildContext context, required Officine officine, required AssuranceSaleSummary saleSummary, required List<SaleItemDetail> items,
    required ClientAssurance client, required AyantDroit ayantDroit, required PaymentMethod paymentMethod, required User currentUser,
    required bool isTestMode, required int paperWidth, required String ticketCodeType,
    bool showQrCode = true, int numberOfCopies = 1, int? montantVerse, int? monnaie,
    // Optionnels (nouvelle version des ventes) ; par défaut : comportement d'origine.
    String? reference, bool? carnet, bool confirmEachCopy = true, List<TicketReglement>? reglements,
  }) async {
    final ref = reference ?? (items.isNotEmpty ? items.first.strREF : '');
    final title = _assuranceTitle(saleSummary, carnet, prevente: false);
    for (int i = 0; i < numberOfCopies; i++) {
      if (i > 0 && confirmEachCopy) {
        final bool? rePrint = await showDialog<bool>(
          context: context, barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Réimpression'), content: Text('Voulez-vous réimprimer le ticket ? (${i + 1}/$numberOfCopies)'),
            actions: [ TextButton(child: const Text('Non'), onPressed: () => Navigator.of(ctx).pop(false)), ElevatedButton(child: const Text('Oui'), onPressed: () => Navigator.of(ctx).pop(true)) ],
          ),
        );
        if (rePrint != true) break;
      }

      if (isTestMode) {
        // APPEL DU WIDGET DÉTAILLÉ
        final ticketWidget = _buildAssuranceSaleTicketWidget(context, officine, saleSummary, items, client, ayantDroit, paymentMethod, currentUser, paperWidth, ticketCodeType, showQrCode, montantVerse: montantVerse, monnaie: monnaie, reference: ref, title: title, reglements: reglements);
        await _showTestTicketDialog(context, ticketWidget, paperWidth);
      } else {
        // APPEL DE L'IMPRESSION DÉTAILLÉE
        await _printAssuranceSaleTicketSunmi(context, officine, saleSummary, items, client, ayantDroit, paymentMethod, currentUser, paperWidth, ticketCodeType, showQrCode, montantVerse: montantVerse, monnaie: monnaie, reference: ref, title: title, reglements: reglements);
      }
    }
  }

  // --- PRÉVENTE ASSURANCE / CARNET (DOIT ÊTRE MINIMALISTE) ---
  Future<void> printAssurancePreventeTicket({
    required BuildContext context, required Officine officine, required AssuranceSaleSummary saleSummary, required List<SaleItemDetail> items,
    required ClientAssurance client, required AyantDroit ayantDroit, required User currentUser, required bool isTestMode,
    required int paperWidth, required String ticketCodeType, int numberOfCopies = 1,
    // Optionnels (nouvelle version des ventes) ; par défaut : comportement d'origine.
    String? reference, bool? carnet, bool confirmEachCopy = true,
    // Optionnel (hors ligne) : numéro provisoire « HL-0007 » ; null = comportement d'origine.
    String? provisoire,
  }) async {
    final ref = reference ?? (items.isNotEmpty ? items.first.strREF : '');
    final title = _assuranceTitle(saleSummary, carnet, prevente: true);
    for (int i = 0; i < numberOfCopies; i++) {
      if (i > 0 && confirmEachCopy) {
        final bool? rePrint = await showDialog<bool>(
          context: context, barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Réimpression'), content: Text('Voulez-vous réimprimer le ticket ? (${i + 1}/$numberOfCopies)'),
            actions: [ TextButton(child: const Text('Non'), onPressed: () => Navigator.of(ctx).pop(false)), ElevatedButton(child: const Text('Oui'), onPressed: () => Navigator.of(ctx).pop(true)) ],
          ),
        );
        if (rePrint != true) break;
      }
      if (isTestMode) {
        // APPEL DU WIDGET MINIMALISTE
        final ticketWidget = _buildAssurancePreventeTicketWidget(context, officine, saleSummary, items, client, ayantDroit, currentUser, paperWidth, ticketCodeType, reference: ref, title: title, provisoire: provisoire);
        await _showTestTicketDialog(context, ticketWidget, paperWidth);
      } else {
        // APPEL DE L'IMPRESSION MINIMALISTE
        await _printAssurancePreventeTicketSunmi(context, officine, saleSummary, items, client, ayantDroit, currentUser, paperWidth, ticketCodeType, reference: ref, title: title, provisoire: provisoire);
      }
    }
  }

  // --- RAPPORT TEXTE (ventes hors ligne : fin de journée, anomalies) ---
  Future<void> printTextReport({
    required BuildContext context, Officine? officine, required String title, required List<String> lines,
    required bool isTestMode, required int paperWidth,
  }) async {
    final cols = paperWidth == 58 ? 32 : 48;
    final sep = List.filled(cols, '-').join();
    if (isTestMode) {
      const textStyle = TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.black);
      final ticket = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (officine != null) Text(officine.nomComplet.toUpperCase(), style: textStyle.copyWith(fontWeight: FontWeight.bold, fontSize: 14)),
        Text(title, key: const ValueKey('rapport-ticket-titre'), style: textStyle.copyWith(fontWeight: FontWeight.bold)),
        Text(sep, style: textStyle),
        for (final l in lines) Text(l, style: textStyle),
        Text(sep, style: textStyle),
        Text(DateFormat("dd/MM/yyyy HH:mm").format(DateTime.now()), style: textStyle),
      ]);
      await _showTestTicketDialog(context, ticket, paperWidth);
      return;
    }
    if (!await _initializePrinter(context)) return;
    try {
      await SunmiPrinter.startTransactionPrint(true);
      await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER);
      if (officine != null) await SunmiPrinter.printText(officine.nomComplet.toUpperCase(), style: SunmiStyle(bold: true, fontSize: SunmiFontSize.MD));
      await SunmiPrinter.printText(title, style: SunmiStyle(bold: true));
      await SunmiPrinter.setAlignment(SunmiPrintAlign.LEFT);
      await SunmiPrinter.printText(sep);
      for (final l in lines) { await SunmiPrinter.printText(l); }
      await SunmiPrinter.printText(sep);
      await SunmiPrinter.printText(DateFormat("dd/MM/yyyy HH:mm").format(DateTime.now()));
      await SunmiPrinter.lineWrap(4);
      await SunmiPrinter.cut();
      await SunmiPrinter.exitTransactionPrint(true);
    } catch (e) { if (context.mounted) Constants.showSnackBar(context, 'Erreur d\'impression: $e', isError: true); }
  }

  // --- BORNE LIBRE-SERVICE (B1) : numéro en grand, produits, total, code de la référence ---
  /// Imprime sur l'imprimante intégrée Sunmi, sans dialogue (la borne affiche le ticket à l'écran si false).
  Future<bool> printBorneTicket({
    required String officine, required String numero, required String reference,
    required List<String> lignes, required List<String> pied, required String codeType,
  }) async {
    try {
      final bool? ok = await SunmiPrinter.bindingPrinter();
      if (ok != true) return false;
      await SunmiPrinter.initPrinter();
      await SunmiPrinter.startTransactionPrint(true);
      await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER);
      await SunmiPrinter.printText(officine.toUpperCase(), style: SunmiStyle(bold: true, fontSize: SunmiFontSize.MD));
      await SunmiPrinter.printText('PRE-VENTE BORNE', style: SunmiStyle(bold: true));
      await SunmiPrinter.printText('N° $numero', style: SunmiStyle(bold: true, fontSize: SunmiFontSize.XL));
      await SunmiPrinter.setAlignment(SunmiPrintAlign.LEFT);
      for (final l in lignes) { await SunmiPrinter.printText(l); }
      await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER);
      await SunmiPrinter.lineWrap(1);
      if (codeType == 'QR_CODE') { await SunmiPrinter.printQRCode(reference); }
      else { await SunmiPrinter.printBarCode(reference, barcodeType: SunmiBarcodeType.CODE128, height: 60, width: 2); }
      await SunmiPrinter.printText(reference);
      for (final l in pied) { await SunmiPrinter.printText(l, style: SunmiStyle(bold: l == pied.first)); }
      await SunmiPrinter.lineWrap(4);
      await SunmiPrinter.cut();
      await SunmiPrinter.exitTransactionPrint(true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Titre du ticket assurance / carnet. [carnet] null : règle d'origine (tous les TP à 100 % → CARNET).
  static String _assuranceTitle(AssuranceSaleSummary s, bool? carnet, {required bool prevente}) {
    final isCarnet = carnet ?? !s.tierspayants.any((tp) => tp.taux < 100);
    return '${prevente ? 'PRE-VENTE ' : 'VENTE '}${isCarnet ? 'CARNET' : 'ASSURANCE'}';
  }

  // ==========================================
  // 2. LOGIQUE D'IMPRESSION SUNMI (Privé)
  // ==========================================

  Future<bool> _initializePrinter(BuildContext context) async {
    try {
      final bool? isConnected = await SunmiPrinter.bindingPrinter();
      if (isConnected != true) { Constants.showSnackBar(context, "Imprimante non connectée.", isError: true); return false; }
      await SunmiPrinter.initPrinter(); return true;
    } catch (e) { Constants.showSnackBar(context, 'Erreur imprimante Sunmi: $e', isError: true); return false; }
  }

  // --- SUNMI VENTE COMPTANT ---
  Future<void> _printSaleTicketSunmi(BuildContext context, Officine officine, SaleSummary saleSummary, List<SaleItemDetail> items, PaymentMethod paymentMethod, User currentUser, int paperWidth, bool showQrCode, String ticketCodeType, {int? montantVerse, int? monnaie, List<TicketReglement>? reglements, String? provisoire}) async {
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
      if (provisoire != null) {
        await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER);
        await SunmiPrinter.printText(provisoireTitre(provisoire), style: SunmiStyle(bold: true, fontSize: SunmiFontSize.MD));
        await SunmiPrinter.printText(provisoireNote);
      }
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
      if (reglements != null && reglements.isNotEmpty) {
        for (final l in ticketReglementLines(reglements)) { await SunmiPrinter.printText(l); }
      } else {
      if (montantVerse != null) await SunmiPrinter.printText('Montant Versé: ${Constants.formatNumber(montantVerse)}');
      if (monnaie != null && monnaie > 0) await SunmiPrinter.printText('Monnaie: ${Constants.formatNumber(monnaie)}', style: SunmiStyle(bold: true));
      await SunmiPrinter.printText('Mode: ${paymentMethod.name.toUpperCase()}');
      }
      await SunmiPrinter.printText(line());
      await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER);
      await SunmiPrinter.printText(DateFormat("dd/MM/yyyy HH:mm").format(DateTime.now()));
      await SunmiPrinter.printText("Vendeur: ${currentUser.fullName}");
      await SunmiPrinter.lineWrap(1);

      if (showQrCode && provisoire == null) {
        if (ticketCodeType == 'QR_CODE') { await SunmiPrinter.printQRCode(saleSummary.reference); }
        else { await SunmiPrinter.printBarCode(saleSummary.reference, barcodeType: SunmiBarcodeType.CODE128, height: 60, width: 2); }
      }
      await SunmiPrinter.printText(saleSummary.reference);

      await SunmiPrinter.lineWrap(3);
      await SunmiPrinter.cut();
      await SunmiPrinter.exitTransactionPrint(true);
    } catch (e) { Constants.showSnackBar(context, 'Erreur d\'impression: $e', isError: true); }
  }

  // --- SUNMI PRÉVENTE COMPTANT ---
  Future<void> _printPreventeTicketSunmi(BuildContext context, Officine officine, SaleSummary saleSummary, User currentUser, int paperWidth, String ticketCodeType, {String? provisoire}) async {
    if (!await _initializePrinter(context)) return;
    try {
      await SunmiPrinter.startTransactionPrint(true);
      final int cols = paperWidth == 58 ? 32 : 48;
      String line([String ch = '-']) => List.filled(cols, ch).join();
      final headerAlign = paperWidth == 58 ? SunmiPrintAlign.LEFT : SunmiPrintAlign.CENTER;
      await SunmiPrinter.setAlignment(headerAlign);
      await SunmiPrinter.printText(officine.nomComplet.toUpperCase(), style: SunmiStyle(bold: true, fontSize: SunmiFontSize.MD));
      await SunmiPrinter.printText(officine.fullName, style: SunmiStyle(fontSize: SunmiFontSize.MD));
      await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER);
      await SunmiPrinter.printText(line());
      await SunmiPrinter.printText('PRE-VENTE -- ${DateFormat("dd/MM/yyyy HH:mm:ss").format(DateTime.now())}', style: SunmiStyle(bold: true, fontSize: SunmiFontSize.MD));
      if (provisoire != null) {
        await SunmiPrinter.printText(provisoireTitre(provisoire), style: SunmiStyle(bold: true, fontSize: SunmiFontSize.MD));
        await SunmiPrinter.printText(provisoireNote);
      }
      await SunmiPrinter.printText(line());
      await SunmiPrinter.lineWrap(1);
      await SunmiPrinter.printText('NET A PAYER: ${Constants.formatNumber(saleSummary.montantNet)}', style: SunmiStyle(bold: true, fontSize: SunmiFontSize.MD));
      await SunmiPrinter.lineWrap(1);
      if (provisoire == null) {
        if (ticketCodeType == 'QR_CODE') { await SunmiPrinter.printQRCode(saleSummary.reference); }
        else { await SunmiPrinter.printBarCode(saleSummary.reference, barcodeType: SunmiBarcodeType.CODE128, height: 60, width: 2); }
      }
      await SunmiPrinter.printText(saleSummary.reference, style: SunmiStyle(fontSize: SunmiFontSize.MD));
      await SunmiPrinter.lineWrap(1);
      await SunmiPrinter.printText("Vendeur: ${currentUser.fullName}", style: SunmiStyle(fontSize: SunmiFontSize.MD));
      await SunmiPrinter.lineWrap(5);
      await SunmiPrinter.cut();
      await SunmiPrinter.exitTransactionPrint(true);
    } catch(e) { Constants.showSnackBar(context, 'Erreur d\'impression: $e', isError: true); }
  }

  // --- SUNMI VENTE ASSURANCE / CARNET (RETOUR DE LA VERSION DÉTAILLÉE AVEC PRODUITS) ---
  Future<void> _printAssuranceSaleTicketSunmi(BuildContext context, Officine officine, AssuranceSaleSummary saleSummary, List<SaleItemDetail> items, ClientAssurance client, AyantDroit ayantDroit, PaymentMethod paymentMethod, User currentUser, int paperWidth, String ticketCodeType, bool showQrCode, {int? montantVerse, int? monnaie, required String reference, required String title, List<TicketReglement>? reglements}) async {
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
      await SunmiPrinter.printText(title, style: SunmiStyle(bold: true));

      await SunmiPrinter.setAlignment(SunmiPrintAlign.LEFT);
      await SunmiPrinter.printText(line());
      await SunmiPrinter.printText('Client: ${client.fullName}');
      await SunmiPrinter.printText('Patient: ${ayantDroit.fullName}');
      await SunmiPrinter.printText('Matricule: ${ayantDroit.strNUMEROSECURITESOCIAL}');

      // RESTAURATION DES ARTICLES POUR LE TICKET VENTE
      await SunmiPrinter.printText(line());
      await SunmiPrinter.printText(fit('Article', articleWidth) + fit('Qte*P.U', financialWidth) + fit('Total', financialWidth), style: SunmiStyle(bold: true));
      await SunmiPrinter.printText(line('.'));

      for (final item in items) {
        await SunmiPrinter.printText(fit(item.strNAME, cols));
        final String priceDetails = fit('', articleWidth) + '${item.intQUANTITY}*${Constants.formatNumber(item.intPRICEUNITAIR)}'.padRight(financialWidth) + r(item.intPRICE, financialWidth);
        await SunmiPrinter.printText(priceDetails);
      }
      // FIN RESTAURATION

      await SunmiPrinter.printText(line());
      await SunmiPrinter.setAlignment(SunmiPrintAlign.RIGHT);

      await SunmiPrinter.printText('Total Brut: ${Constants.formatNumber(saleSummary.montant)}');
      await SunmiPrinter.printText('Part Assurance: ${Constants.formatNumber(saleSummary.montantTp)}');

      // Détail TP (Facultatif mais utile pour la vente réelle)
      for(var tp in saleSummary.tierspayants) {
        final tpClientInfo = client.tiersPayants.firstWhere((c) => c.compteTp == tp.compteTp, orElse: () => ClientTiersPayant(lgTIERSPAYANTID: '', tpFullName: 'N/A', taux: 0, numSecurity: '', compteTp: '', order: 0, principal: false));
        await SunmiPrinter.printText('${tpClientInfo.tpFullName} (${tp.taux}%)');
        await SunmiPrinter.printText('  N°Bon ${tp.numBon}: ${Constants.formatNumber(tp.tpnet)}');
      }

      await SunmiPrinter.printText('NET A PAYER: ${Constants.formatNumber(saleSummary.montantNet)}', style: SunmiStyle(bold: true, fontSize: SunmiFontSize.MD));

      if (reglements != null && reglements.isNotEmpty) {
        for (final l in ticketReglementLines(reglements)) { await SunmiPrinter.printText(l); }
      } else {
      if (montantVerse != null) await SunmiPrinter.printText('Montant Versé: ${Constants.formatNumber(montantVerse)}');
      if (monnaie != null && monnaie > 0) await SunmiPrinter.printText('Monnaie: ${Constants.formatNumber(monnaie)}', style: SunmiStyle(bold: true));
      }

      await SunmiPrinter.printText(line());
      await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER);
      await SunmiPrinter.printText(DateFormat("dd/MM/yyyy HH:mm").format(DateTime.now()));
      await SunmiPrinter.printText("Vendeur: ${currentUser.fullName}");

      await SunmiPrinter.lineWrap(1);

      if (showQrCode && reference.isNotEmpty) {
        if (ticketCodeType == 'QR_CODE') { await SunmiPrinter.printQRCode(reference); }
        else { await SunmiPrinter.printBarCode(reference, barcodeType: SunmiBarcodeType.CODE128, height: 60, width: 2); }
      }

      if (reference.isNotEmpty) {
        await SunmiPrinter.printText(reference, style: SunmiStyle(fontSize: SunmiFontSize.MD));
      }

      await SunmiPrinter.lineWrap(5);
      await SunmiPrinter.cut();
      await SunmiPrinter.exitTransactionPrint(true);
    } catch (e) { Constants.showSnackBar(context, 'Erreur d\'impression: $e', isError: true); }
  }

  // --- SUNMI PRÉVENTE ASSURANCE (RESTE MINIMALISTE) ---
  Future<void> _printAssurancePreventeTicketSunmi(BuildContext context, Officine officine, AssuranceSaleSummary saleSummary, List<SaleItemDetail> items, ClientAssurance client, AyantDroit ayantDroit, User currentUser, int paperWidth, String ticketCodeType, {required String reference, required String title, String? provisoire}) async {
    if (!await _initializePrinter(context)) return;
    try {
      await SunmiPrinter.startTransactionPrint(true);
      final int cols = paperWidth == 58 ? 32 : 48;
      String line([String ch = '-']) => List.filled(cols, ch).join();
      SunmiStyle defaultStyle = SunmiStyle(fontSize: SunmiFontSize.MD);
      final headerAlign = paperWidth == 58 ? SunmiPrintAlign.LEFT : SunmiPrintAlign.CENTER;

      await SunmiPrinter.setAlignment(headerAlign);
      await SunmiPrinter.printText(officine.nomComplet.toUpperCase(), style: SunmiStyle(bold: true, fontSize: SunmiFontSize.MD));
      await SunmiPrinter.printText(officine.fullName, style: defaultStyle);
      await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER);
      await SunmiPrinter.printText(line());
      await SunmiPrinter.printText(title, style: SunmiStyle(bold: true, fontSize: SunmiFontSize.MD));
      if (provisoire != null) {
        await SunmiPrinter.printText(provisoireTitre(provisoire), style: SunmiStyle(bold: true));
        await SunmiPrinter.printText(provisoireNote);
      }
      await SunmiPrinter.printText(DateFormat("dd/MM/yyyy HH:mm:ss").format(DateTime.now()));
      await SunmiPrinter.setAlignment(SunmiPrintAlign.LEFT);
      await SunmiPrinter.printText(line());
      await SunmiPrinter.printText('Client: ${client.fullName}');
      await SunmiPrinter.printText('Patient: ${ayantDroit.fullName}');
      await SunmiPrinter.printText('Matricule: ${ayantDroit.strNUMEROSECURITESOCIAL}');

      // ICI : PAS D'ARTICLES POUR LA PRÉVENTE (Correct)

      await SunmiPrinter.printText(line());
      await SunmiPrinter.setAlignment(SunmiPrintAlign.RIGHT);
      await SunmiPrinter.printText('Total Brut: ${Constants.formatNumber(saleSummary.montant)}');
      await SunmiPrinter.printText('Part Assurance: ${Constants.formatNumber(saleSummary.montantTp)}');
      await SunmiPrinter.printText('PART CLIENT: ${Constants.formatNumber(saleSummary.montantNet)}', style: SunmiStyle(bold: true, fontSize: SunmiFontSize.MD));
      await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER);
      await SunmiPrinter.lineWrap(1);

      if (provisoire == null) {
        if (ticketCodeType == 'QR_CODE') {
          await SunmiPrinter.printQRCode(reference);
        } else {
          await SunmiPrinter.printBarCode(reference, barcodeType: SunmiBarcodeType.CODE128, height: 60, width: 2);
        }
      }
      await SunmiPrinter.printText(reference, style: defaultStyle);
      await SunmiPrinter.lineWrap(1);
      await SunmiPrinter.printText("Vendeur: ${currentUser.fullName}", style: defaultStyle);
      await SunmiPrinter.lineWrap(5);
      await SunmiPrinter.cut();
      await SunmiPrinter.exitTransactionPrint(true);
    } catch(e) { Constants.showSnackBar(context, 'Erreur d\'impression: $e', isError: true); }
  }

  // ==========================================
  // 3. WIDGETS D'APERÇU (Mode Test)
  // ==========================================

  Future<void> _showTestTicketDialog(BuildContext context, Widget ticketContent, int paperWidth) async { await showDialog( context: context, builder: (ctx) => AlertDialog( title: const Text("Aperçu du Ticket"), content: Container( width: paperWidth == 58 ? 300 : 420, child: SingleChildScrollView(child: ticketContent), ), actions: [ TextButton( child: const Text("Fermer"), onPressed: () => Navigator.of(ctx).pop(), ) ], ), ); }

  Widget _buildSaleTicketWidget(BuildContext context, Officine officine, SaleSummary saleSummary, List<SaleItemDetail> items, PaymentMethod paymentMethod, User currentUser, int paperWidth, bool showQrCode, String ticketCodeType, {int? montantVerse, int? monnaie, List<TicketReglement>? reglements, String? provisoire}) {
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
        if (provisoire != null) ...[
          Center(child: Text(provisoireTitre(provisoire), style: boldStyle)),
          const Center(child: Text(provisoireNote, style: textStyle)),
        ],
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
        if (reglements != null && reglements.isNotEmpty)
          for (final l in ticketReglementLines(reglements)) Align(alignment: Alignment.centerRight, child: Text(l, style: textStyle))
        else ...[
        if (montantVerse != null)
          Align(alignment: Alignment.centerRight, child: Text('Montant Versé: ${Constants.formatNumber(montantVerse)}', style: textStyle)),
        if (monnaie != null && monnaie > 0)
          Align(alignment: Alignment.centerRight, child: Text('Monnaie: ${Constants.formatNumber(monnaie)}', style: boldStyle)),
        Align(alignment: Alignment.centerRight, child: Text('Mode: ${paymentMethod.name.toUpperCase()}', style: textStyle)),
        ],
        Text(line(), style: textStyle),
        Center(child: Text(DateFormat("dd/MM/yyyy HH:mm").format(DateTime.now()), style: textStyle)),
        Center(child: Text("Vendeur: ${currentUser.fullName}", style: textStyle)),
        const SizedBox(height: 8),
        if (showQrCode && provisoire == null)
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

  Widget _buildPreventeTicketWidget(BuildContext context, Officine officine, SaleSummary saleSummary, User currentUser, int paperWidth, String ticketCodeType, {String? provisoire}) {
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
        if (provisoire != null) ...[
          Text(provisoireTitre(provisoire), style: boldStyle),
          const Text(provisoireNote, style: textStyle),
        ],
        Text(line(), style: textStyle),
        const SizedBox(height: 16),
        Text(
            'NET A PAYER: ${Constants.formatNumber(saleSummary.montantNet)}',
            style: boldStyle.copyWith(fontSize: 14)
        ),
        const SizedBox(height: 16),
        if (provisoire == null)
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

  // --- WIDGET PRÉVENTE ASSURANCE (MINIMALISTE) ---
  Widget _buildAssurancePreventeTicketWidget(BuildContext context, Officine officine, AssuranceSaleSummary saleSummary, List<SaleItemDetail> items, ClientAssurance client, AyantDroit ayantDroit, User currentUser, int paperWidth, String ticketCodeType, {required String reference, required String title, String? provisoire}) {
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
        Center(child: Text(title, style: boldStyle)),
        if (provisoire != null) ...[
          Center(child: Text(provisoireTitre(provisoire), style: boldStyle)),
          const Center(child: Text(provisoireNote, style: textStyle)),
        ],
        Center(child: Text(DateFormat("dd/MM/yyyy HH:mm:ss").format(DateTime.now()), style: textStyle)),
        Text(line(), style: textStyle),
        Text('Client: ${client.fullName}', style: textStyle),
        Text('Patient: ${ayantDroit.fullName}', style: textStyle),
        Text('Matricule: ${ayantDroit.strNUMEROSECURITESOCIAL}', style: textStyle),

        // PAS D'ARTICLES

        Text(line(), style: textStyle),
        Align(alignment: Alignment.centerRight, child: Text('Total Brut: ${Constants.formatNumber(saleSummary.montant)}', style: textStyle)),
        Align(alignment: Alignment.centerRight, child: Text('Part Assurance: ${Constants.formatNumber(saleSummary.montantTp)}', style: textStyle)),
        Align(alignment: Alignment.centerRight, child: Text('PART CLIENT: ${Constants.formatNumber(saleSummary.montantNet)}', style: boldStyle.copyWith(fontSize: 14))),
        Text(line(), style: textStyle),

        const SizedBox(height: 16),
        if (provisoire == null)
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

  // --- WIDGET VENTE ASSURANCE (RETOUR VERSION DÉTAILLÉE AVEC PRODUITS) ---
  Widget _buildAssuranceSaleTicketWidget(BuildContext context, Officine officine, AssuranceSaleSummary saleSummary, List<SaleItemDetail> items, ClientAssurance client, AyantDroit ayantDroit, PaymentMethod paymentMethod, User currentUser, int paperWidth, String ticketCodeType, bool showQrCode, {int? montantVerse, int? monnaie, required String reference, required String title, List<TicketReglement>? reglements}) {
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
        Center(child: Text(title, style: boldStyle)),
        Text(line(), style: textStyle),
        Text('Client: ${client.fullName}', style: textStyle),
        Text('Patient: ${ayantDroit.fullName}', style: textStyle),
        Text('Matricule: ${ayantDroit.strNUMEROSECURITESOCIAL}', style: textStyle),

        // RESTAURATION DES ARTICLES ICI
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
        // FIN RESTAURATION

        Text(line(), style: textStyle),
        Align(alignment: Alignment.centerRight, child: Text('Total Brut: ${Constants.formatNumber(saleSummary.montant)}', style: textStyle)),
        Align(alignment: Alignment.centerRight, child: Text('Part Assurance: ${Constants.formatNumber(saleSummary.montantTp)}', style: textStyle)),

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

        Align(alignment: Alignment.centerRight, child: Text('NET A PAYER: ${Constants.formatNumber(saleSummary.montantNet)}', style: boldStyle.copyWith(fontSize: 14))),

        if (reglements != null && reglements.isNotEmpty)
          for (final l in ticketReglementLines(reglements)) Align(alignment: Alignment.centerRight, child: Text(l, style: textStyle))
        else ...[
        if (montantVerse != null)
          Align(alignment: Alignment.centerRight, child: Text('Montant Versé: ${Constants.formatNumber(montantVerse)}', style: textStyle)),
        if (monnaie != null && monnaie > 0)
          Align(alignment: Alignment.centerRight, child: Text('Monnaie: ${Constants.formatNumber(monnaie)}', style: boldStyle)),
        ],

        Text(line(), style: textStyle),
        Center(child: Text(DateFormat("dd/MM/yyyy HH:mm").format(DateTime.now()), style: textStyle)),
        Center(child: Text("Vendeur: ${currentUser.fullName}", style: textStyle)),
        const SizedBox(height: 8),

        if (showQrCode && reference.isNotEmpty)
          Center(
            child: ticketCodeType == 'QR_CODE'
                ? QrImageView( data: reference, version: QrVersions.auto, size: 120.0, )
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

        if (reference.isNotEmpty)
          Center(child: Text(reference, style: textStyle)),

        const SizedBox(height: 16),
      ],
    );
  }
}