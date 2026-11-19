// lib/services/receipt_service.dart
// CORRECTION : SÉPARATION NETTE ENTRE VENTE (DÉTAILLÉE) ET PRÉVENTE (MINIMALISTE)
// 4.1.1 : produits sur le ticket de prévente selon le réglage « Afficher les produits sur le ticket de prévente »
// (Réglages › Impression ; désactivé par défaut = ticket minimaliste d'origine). Tickets de vente inchangés.
// 4.14.0 : tickets de VENTE (comptant, assurance, carnet) mis en page comme le serveur (lib/services/ticket_texte.dart :
// prix jamais coupés, traits à la largeur exacte, remise) ; largeur de l'imprimante intégrée imposée
// (lib/services/largeur_ticket.dart) ; ticket dessiné par le serveur quand il sait le faire
// (lib/services/impression_ticket.dart), gabarit local sinon.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/api/models/officine.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/api/models/user.dart';
import 'package:prestige_vente_app/services/impression_ticket.dart';
import 'package:prestige_vente_app/services/largeur_ticket.dart';
import 'package:prestige_vente_app/services/ticket_prevente.dart';
import 'package:prestige_vente_app/services/ticket_serveur.dart';
import 'package:prestige_vente_app/services/ticket_texte.dart';
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
    final papier = await LargeurTicket.pourImpression(paperWidth);
    if (!context.mounted) return;
    if (provisoire == null &&
        await ImpressionTicket.parServeur(context, type: TypeTicketServeur.vno, venteId: saleSummary.venteId, largeur: papier, apercu: isTestMode)) {
      return;
    }
    if (!context.mounted) return;
    final ticket = ticketVenteComptant(
      papier: papier, officine: officine, saleSummary: saleSummary, items: items, paymentMethod: paymentMethod, currentUser: currentUser,
      showQrCode: showQrCode, montantVerse: montantVerse, monnaie: monnaie, reglements: reglements, provisoire: provisoire,
    );
    if (isTestMode) {
      await _showTestTicketDialog(context, apercuTicketTexte(ticket, ticketCodeType), papier);
    } else {
      await _imprimerTicketTexteSunmi(context, ticket, ticketCodeType);
    }
  }

  /// 4.14.0 — Ticket de vente comptant, mise en page du serveur (aperçu, impression, tests).
  static TicketTexte ticketVenteComptant({
    required int papier, required Officine officine, required SaleSummary saleSummary, required List<SaleItemDetail> items,
    required PaymentMethod paymentMethod, required User currentUser, bool showQrCode = false,
    int? montantVerse, int? monnaie, List<TicketReglement>? reglements, String? provisoire, DateTime? date,
  }) {
    final m = MiseEnPageTicket(papier);
    final r = TicketVenteTexte.reglement(m: m, mode: paymentMethod.name, montantVerse: montantVerse, monnaie: monnaie, reglements: reglements);
    return TicketVenteTexte.vente(
      papierMm: papier,
      officine: officine.nomComplet,
      pharmacien: officine.fullName,
      titre: 'VENTE COMPTANT',
      provisoire: provisoire == null ? null : provisoireTitre(provisoire),
      provisoireNote: provisoireNote,
      vendeur: currentUser.fullName,
      articles: [for (final i in items) (designation: i.strNAME, quantite: i.intQUANTITY, prixUnitaire: i.intPRICEUNITAIR, montant: i.intPRICE)],
      total: saleSummary.montant,
      remise: _remiseDe(saleSummary.montant, saleSummary.montantNet, saleSummary.remise),
      net: saleSummary.montantNet,
      reglement: r.lignes,
      monnaie: r.monnaie,
      date: date ?? DateTime.now(),
      reference: saleSummary.reference,
      code: showQrCode && provisoire == null,
    );
  }

  /// Remise imprimée : celle du serveur, sinon l'écart brut − net d'une vente comptant (arrondi à 5 F compris).
  static int _remiseDe(int brut, int net, int remise) => remise > 0 ? remise : (brut > net ? brut - net : 0);

  /// 4.14.0 — Ticket de vente assurance / carnet, mise en page du serveur (aperçu, impression, tests).
  static TicketTexte ticketVenteAssurance({
    required int papier, required Officine officine, required AssuranceSaleSummary saleSummary, required List<SaleItemDetail> items,
    required ClientAssurance client, required AyantDroit ayantDroit, required PaymentMethod? paymentMethod, required User currentUser,
    required String reference, required String title, bool showQrCode = true,
    int? montantVerse, int? monnaie, List<TicketReglement>? reglements, DateTime? date,
  }) {
    final m = MiseEnPageTicket(papier);
    final carnet = title.toUpperCase().contains('CARNET');
    // Nom du client : sur sa propre ligne (un nom n'est jamais une valeur poussée à droite).
    final lignesClient = <PaireTicket>[
      (libelle: 'Client : ${client.fullName}', valeur: ''),
      if (ayantDroit.strNUMEROSECURITESOCIAL.trim().isNotEmpty) (libelle: 'Matricule assuré', valeur: ayantDroit.strNUMEROSECURITESOCIAL.trim()),
      if (ayantDroit.fullName.trim().isNotEmpty) (libelle: 'Bénéficiaire : ${ayantDroit.fullName}', valeur: ''),
      for (final bon in {for (final tp in saleSummary.tierspayants) if (tp.numBon.trim().isNotEmpty) tp.numBon.trim()}) (libelle: 'Bon N°', valeur: bon),
      (libelle: 'Part du client', valeur: m.montantF(saleSummary.montantNet)),
      for (final tp in saleSummary.tierspayants)
        (
          libelle: '${client.tiersPayants.where((c) => c.compteTp == tp.compteTp).firstOrNull?.tpFullName ?? 'Organisme'} [${tp.taux}%]',
          valeur: m.montantF(tp.tpnet),
        ),
    ];
    final r = TicketVenteTexte.reglement(m: m, mode: paymentMethod?.name ?? '', montantVerse: montantVerse, monnaie: monnaie, reglements: reglements);
    return TicketVenteTexte.vente(
      papierMm: papier,
      officine: officine.nomComplet,
      pharmacien: officine.fullName,
      titre: title,
      vendeur: currentUser.fullName,
      clients: lignesClient,
      articles: [for (final i in items) (designation: i.strNAME, quantite: i.intQUANTITY, prixUnitaire: i.intPRICEUNITAIR, montant: i.intPRICE)],
      total: saleSummary.montant,
      remise: saleSummary.remise > 0 ? saleSummary.remise : 0,
      // Comme le serveur : « Pris sur le carnet » / « Vente à terme » quand la part du client est nulle (sinon les
      // parts sont dans le bloc du client).
      aTerme: saleSummary.montantNet == 0 ? (libelle: carnet ? 'Pris sur le carnet' : 'Vente à terme', montant: saleSummary.montantTp) : null,
      net: saleSummary.montantNet,
      reglement: r.lignes,
      monnaie: r.monnaie,
      date: date ?? DateTime.now(),
      reference: reference,
      code: showQrCode && reference.isNotEmpty,
    );
  }

  // --- PRÉVENTE COMPTANT ---
  Future<void> printPreventeTicket({
    required BuildContext context, required Officine officine, required SaleSummary saleSummary, required User currentUser, required bool isTestMode, required int paperWidth, required String ticketCodeType,
    // Optionnel (hors ligne) : numéro provisoire « HL-0007 » ; null = comportement d'origine.
    String? provisoire,
    // 4.1.1 : réglage « Afficher les produits sur le ticket de prévente » (désactivé : ticket d'origine, sans
    // produits) et lignes du panier ; sans lignes, le ticket reste celui d'origine.
    List<SaleItemDetail> items = const [],
    bool afficherProduits = false,
  }) async {
    final produits = afficherProduits ? TicketPrevente.imprimables(items) : const <SaleItemDetail>[];
    // 4.14.0 : largeur de l'imprimante intégrée imposée ; ticket de prévente du serveur (QR dans l'image) s'il existe.
    paperWidth = await LargeurTicket.pourImpression(paperWidth);
    if (!context.mounted) return;
    if (provisoire == null &&
        await ImpressionTicket.parServeur(context, type: TypeTicketServeur.prevente, venteId: saleSummary.venteId, largeur: paperWidth, apercu: isTestMode)) {
      return;
    }
    if (!context.mounted) return;
    if (isTestMode) {
      final ticketWidget = _buildPreventeTicketWidget(context, officine, saleSummary, currentUser, paperWidth, ticketCodeType, provisoire: provisoire, produits: produits);
      await _showTestTicketDialog(context, ticketWidget, paperWidth);
    } else {
      await _printPreventeTicketSunmi(context, officine, saleSummary, currentUser, paperWidth, ticketCodeType, provisoire: provisoire, produits: produits);
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
    ImpressionTicket.debutCopies();
    for (int i = 0; i < numberOfCopies; i++) {
      if (i > 0 && ImpressionTicket.copiesParServeur) break;
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

      // 4.14.0 : ticket du serveur s'il sait le dessiner (il décide alors du nombre d'exemplaires).
      final papier = await LargeurTicket.pourImpression(paperWidth);
      if (!context.mounted) return;
      if (i == 0 &&
          await ImpressionTicket.parServeur(context, type: TypeTicketServeur.vo, venteId: saleSummary.venteId, largeur: papier, apercu: isTestMode)) {
        return;
      }
      if (!context.mounted) return;
      final ticket = ticketVenteAssurance(
        papier: papier, officine: officine, saleSummary: saleSummary, items: items, client: client, ayantDroit: ayantDroit,
        paymentMethod: paymentMethod, currentUser: currentUser, reference: ref, title: title, showQrCode: showQrCode,
        montantVerse: montantVerse, monnaie: monnaie, reglements: reglements,
      );
      if (isTestMode) {
        await _showTestTicketDialog(context, apercuTicketTexte(ticket, ticketCodeType), papier);
      } else {
        await _imprimerTicketTexteSunmi(context, ticket, ticketCodeType);
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
    // 4.1.1 : réglage « Afficher les produits sur le ticket de prévente » (désactivé : ticket d'origine, sans produits).
    bool afficherProduits = false,
  }) async {
    final ref = reference ?? (items.isNotEmpty ? items.first.strREF : '');
    final title = _assuranceTitle(saleSummary, carnet, prevente: true);
    final produits = afficherProduits ? TicketPrevente.imprimables(items) : const <SaleItemDetail>[];
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
      // 4.14.0 : largeur de l'imprimante intégrée imposée ; ticket de prévente du serveur s'il existe.
      paperWidth = await LargeurTicket.pourImpression(paperWidth);
      if (!context.mounted) return;
      if (provisoire == null &&
          await ImpressionTicket.parServeur(context, type: TypeTicketServeur.prevente, venteId: saleSummary.venteId, largeur: paperWidth, apercu: isTestMode)) {
        return;
      }
      if (!context.mounted) return;
      if (isTestMode) {
        // APPEL DU WIDGET MINIMALISTE
        final ticketWidget = _buildAssurancePreventeTicketWidget(context, officine, saleSummary, items, client, ayantDroit, currentUser, paperWidth, ticketCodeType, reference: ref, title: title, provisoire: provisoire, produits: produits);
        await _showTestTicketDialog(context, ticketWidget, paperWidth);
      } else {
        // APPEL DE L'IMPRESSION MINIMALISTE
        await _printAssurancePreventeTicketSunmi(context, officine, saleSummary, items, client, ayantDroit, currentUser, paperWidth, ticketCodeType, reference: ref, title: title, provisoire: provisoire, produits: produits);
      }
    }
  }

  // --- RAPPORT TEXTE (ventes hors ligne : fin de journée, anomalies) ---
  Future<void> printTextReport({
    required BuildContext context, Officine? officine, required String title, required List<String> lines,
    required bool isTestMode, required int paperWidth,
  }) async {
    paperWidth = await LargeurTicket.pourImpression(paperWidth);
    if (!context.mounted) return;
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

  // --- 4.14.0 : PAGE DE TEST DE LA LARGEUR (Réglages › Impression) ---
  /// Lignes de la page de test : traits et règle de la largeur exacte (32 / 48 caractères), de bord à bord.
  static TicketTexte pageTestLargeur(int papier) {
    final c = TicketTexte.colonnesPour(papier);
    final regle = ('1234567890' * 5).substring(0, c);
    return TicketTexte(colonnes: c, lignes: [
      LigneTicket('=' * c, gras: true),
      const LigneTicket('PAGE DE TEST', gras: true, centre: true),
      ...MiseEnPageTicket.couper('Papier $papier mm : $c caractères', c).map((l) => LigneTicket(l, centre: true)),
      LigneTicket(regle),
      LigneTicket('<${'-' * (c - 2)}>'),
      ...MiseEnPageTicket.paire('1 x 1 500', '1 500', c).map((l) => LigneTicket(l)),
      ...MiseEnPageTicket.couper('Chaque ligne doit tenir sur une seule ligne, sans retour.', c).map((l) => LigneTicket(l)),
      LigneTicket('=' * c, gras: true),
    ]);
  }

  Future<void> printPageTestLargeur({required BuildContext context, required int paperWidth, required bool isTestMode}) async {
    final papier = await LargeurTicket.pourImpression(paperWidth);
    if (!context.mounted) return;
    final t = pageTestLargeur(papier);
    if (isTestMode) {
      await _showTestTicketDialog(context, apercuTicketTexte(t, 'QR_CODE'), papier);
    } else {
      await _imprimerTicketTexteSunmi(context, t, 'QR_CODE');
    }
  }

  // --- BORNE LIBRE-SERVICE (B1) : numéro en grand, produits, total, code de la référence ---
  /// Imprime sur l'imprimante intégrée Sunmi, sans dialogue (la borne affiche le ticket à l'écran si false).
  Future<bool> printBorneTicket({
    required String officine, required String numero, required String reference,
    required List<String> lignes, required List<String> pied, required String codeType,
    String titre = 'PRE-VENTE BORNE',
  }) async {
    try {
      final bool? ok = await SunmiPrinter.bindingPrinter();
      if (ok != true) return false;
      await SunmiPrinter.initPrinter();
      await SunmiPrinter.startTransactionPrint(true);
      await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER);
      await SunmiPrinter.printText(officine.toUpperCase(), style: SunmiStyle(bold: true, fontSize: SunmiFontSize.MD));
      await SunmiPrinter.printText(titre, style: SunmiStyle(bold: true));
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

  /// Lignes produits d'une prévente (4.1.1) : noms sur deux lignes si besoin, quantité × prix et total de la
  /// ligne, séparateur, nombre d'articles. Imprimées alignées à gauche ; [recentrer] : centrage rétabli après.
  Future<void> _printProduitsPreventeSunmi(List<SaleItemDetail> produits, int cols, String separateur, {bool recentrer = false}) async {
    await SunmiPrinter.setAlignment(SunmiPrintAlign.LEFT);
    for (final l in TicketPrevente.produits(produits, cols)) { await SunmiPrinter.printText(l); }
    await SunmiPrinter.printText(separateur);
    await SunmiPrinter.printText(TicketPrevente.articles(TicketPrevente.nombreArticles(produits)));
    if (recentrer) await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER);
  }

  // --- SUNMI PRÉVENTE COMPTANT ---
  Future<void> _printPreventeTicketSunmi(BuildContext context, Officine officine, SaleSummary saleSummary, User currentUser, int paperWidth, String ticketCodeType, {String? provisoire, List<SaleItemDetail> produits = const []}) async {
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
      if (produits.isNotEmpty) await _printProduitsPreventeSunmi(produits, cols, line(), recentrer: true);
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

  // --- SUNMI PRÉVENTE ASSURANCE (RESTE MINIMALISTE) ---
  Future<void> _printAssurancePreventeTicketSunmi(BuildContext context, Officine officine, AssuranceSaleSummary saleSummary, List<SaleItemDetail> items, ClientAssurance client, AyantDroit ayantDroit, User currentUser, int paperWidth, String ticketCodeType, {required String reference, required String title, String? provisoire, List<SaleItemDetail> produits = const []}) async {
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

      // Articles seulement si le réglage « Afficher les produits sur le ticket de prévente » est activé (4.1.1).
      if (produits.isNotEmpty) {
        await SunmiPrinter.printText(line());
        await _printProduitsPreventeSunmi(produits, cols, line());
      }

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

  Widget _buildPreventeTicketWidget(BuildContext context, Officine officine, SaleSummary saleSummary, User currentUser, int paperWidth, String ticketCodeType, {String? provisoire, List<SaleItemDetail> produits = const []}) {
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
        if (produits.isNotEmpty) _produitsPreventeApercu(produits, cols, line(), textStyle),
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

  /// Aperçu des lignes produits d'une prévente : mêmes lignes que l'impression Sunmi (4.1.1).
  Widget _produitsPreventeApercu(List<SaleItemDetail> produits, int cols, String separateur, TextStyle style) => Align(
        key: const ValueKey('ticket-prevente-produits'),
        alignment: Alignment.centerLeft,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final l in TicketPrevente.produits(produits, cols)) Text(l, style: style),
          Text(separateur, style: style),
          Text(TicketPrevente.articles(TicketPrevente.nombreArticles(produits)), style: style),
        ]),
      );

  // --- WIDGET PRÉVENTE ASSURANCE (MINIMALISTE) ---
  Widget _buildAssurancePreventeTicketWidget(BuildContext context, Officine officine, AssuranceSaleSummary saleSummary, List<SaleItemDetail> items, ClientAssurance client, AyantDroit ayantDroit, User currentUser, int paperWidth, String ticketCodeType, {required String reference, required String title, String? provisoire, List<SaleItemDetail> produits = const []}) {
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

        // Articles seulement si le réglage « Afficher les produits sur le ticket de prévente » est activé (4.1.1).
        if (produits.isNotEmpty) ...[
          Text(line(), style: textStyle),
          _produitsPreventeApercu(produits, cols, line(), textStyle),
        ],

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

  // --- 4.14.0 : TICKET DE VENTE COMPOSÉ (ticket_texte.dart) ---

  /// Impression Sunmi d'un ticket composé : chaque ligne avec SA taille de police, posée explicitement (24 points :
  /// 32 / 48 caractères ; grand : 36 points), alignée à gauche (le centrage est dans le texte). Rien ne dépend de la
  /// police par défaut de l'imprimante.
  Future<void> _imprimerTicketTexteSunmi(BuildContext context, TicketTexte ticket, String ticketCodeType) async {
    if (!await _initializePrinter(context)) return;
    try {
      await SunmiPrinter.startTransactionPrint(true);
      for (final l in ticket.lignes) {
        if (l.code) {
          await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER);
          if (ticketCodeType == 'QR_CODE') { await SunmiPrinter.printQRCode(ticket.codeDonnees); }
          else { await SunmiPrinter.printBarCode(ticket.codeDonnees, barcodeType: SunmiBarcodeType.CODE128, height: 60, width: 2); }
          continue;
        }
        await SunmiPrinter.printText(l.imprimee(l.grand ? ticket.colonnesGrand : ticket.colonnes),
            style: SunmiStyle(align: SunmiPrintAlign.LEFT, fontSize: l.grand ? SunmiFontSize.LG : SunmiFontSize.MD, bold: l.gras));
      }
      await SunmiPrinter.lineWrap(4);
      await SunmiPrinter.cut();
      await SunmiPrinter.exitTransactionPrint(true);
    } catch (e) { if (context.mounted) Constants.showSnackBar(context, 'Erreur d\'impression: $e', isError: true); }
  }

  /// Aperçu d'un ticket composé (mode test d'impression, captures) : les mêmes lignes, police à chasse fixe.
  static Widget apercuTicketTexte(TicketTexte ticket, String ticketCodeType) {
    const textStyle = TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.black, height: 1.25);
    return Column(
      key: const ValueKey('ticket-texte-apercu'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final l in ticket.lignes)
          if (l.code)
            Center(
              child: ticketCodeType == 'QR_CODE'
                  ? QrImageView(data: ticket.codeDonnees, version: QrVersions.auto, size: 120.0)
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: BarcodeWidget(barcode: Barcode.code128(), data: ticket.codeDonnees, drawText: false, height: 50),
                    ),
            )
          else if (l.centre)
            Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(l.texte, softWrap: false,
                    style: textStyle.copyWith(fontWeight: l.gras ? FontWeight.bold : FontWeight.normal, fontSize: l.grand ? 18 : 12)),
              ),
            )
          else
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                l.texte.padRight(l.grand ? ticket.colonnesGrand : ticket.colonnes),
                softWrap: false,
                style: textStyle.copyWith(fontWeight: l.gras ? FontWeight.bold : FontWeight.normal, fontSize: l.grand ? 18 : 12),
              ),
            ),
        const SizedBox(height: 16),
      ],
    );
  }
}
