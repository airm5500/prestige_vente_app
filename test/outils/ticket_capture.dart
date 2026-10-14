// test/outils/ticket_capture.dart
// Capture des tickets (4.1.1) : appels envoyés à l'imprimante Sunmi (canal `sunmi_printer_plus` simulé) et lignes
// de l'aperçu (mode test d'impression). Sert au test de non-régression « par défaut, ticket identique à avant » :
// `test/ticket_prevente_reference.json` a été produit avec ces mêmes scénarios sur le code 4.1.0 (avant le réglage).
// Données fictives uniquement.
import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/models/assurance_sale_summary.dart';
import 'package:prestige_vente_app/api/models/ayant_droit.dart';
import 'package:prestige_vente_app/api/models/client_assurance.dart';
import 'package:prestige_vente_app/api/models/officine.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/api/models/user.dart';
import 'package:prestige_vente_app/borne/borne_service.dart';
import 'package:prestige_vente_app/borne/borne_ticket.dart';
import 'package:prestige_vente_app/services/receipt_service.dart';
import 'package:qr_flutter/qr_flutter.dart';

const canalSunmi = MethodChannel('sunmi_printer_plus');

/// Dates et heures du ticket (DateTime.now()) remplacées pour comparer deux impressions.
String sansDate(String s) => s.replaceAll(RegExp(r'\d{2}/\d{2}/\d{4} \d{2}:\d{2}(:\d{2})?'), '<DATE>');

/// Enregistre chaque appel au canal Sunmi (« méthode arguments »), imprimante présente.
class ImprimanteSimulee {
  final List<String> appels = [];

  /// Textes envoyés par `printText` (une ligne de ticket chacun, sans le retour à la ligne final).
  final List<String> textes = [];

  void installer(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(canalSunmi, (call) async {
      appels.add(sansDate('${call.method} ${call.arguments}'));
      if (call.method == 'PRINT_TEXT') {
        final t = '${(call.arguments as Map)['text']}';
        textes.add(sansDate(t.endsWith('\n') ? t.substring(0, t.length - 1) : t));
      }
      if (call.method == 'BIND_PRINTER_SERVICE' || call.method == 'INIT_PRINTER') return true;
      return null;
    });
  }

  void retirer(WidgetTester tester) => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(canalSunmi, null);

}

// --- Données fictives ---
final officineFictive = Officine(fullName: 'Cocody Riviera 2 - Tel 00 00 00 00', nomComplet: 'Pharmacie Fictive du Test');
final userFictif = User(userId: 'U1', login: 'awa', firstName: 'Awa', lastName: 'Kouassi', officineName: 'TEST');

SaleItemDetail article(String nom, int qte, int pu, {String id = 'L1'}) => SaleItemDetail(
    lgPREENREGISTREMENTDETAILID: id, lgFAMILLEID: 'F$id', strNAME: nom, intCIP: '0000000', intQUANTITY: qte, intPRICEUNITAIR: pu, intPRICE: qte * pu, strREF: '20261014000042');

/// Panier fictif : nom court, nom de la capture de la borne (> 32 caractères), nom très long.
final articlesFictifs = [
  article('EFFERALGAN 500MG', 2, 1200, id: 'L1'),
  article('PARACETAMOL BIOGARAN 1G CPR EFFV B/20', 1, 950, id: 'L2'),
  article('DOLIPRANE 1000MG COMPRIMES PELLICULES BOITE DE 8 SECABLES SANS SUCRE', 3, 1100, id: 'L3'),
];

final resumeFictif = SaleSummary(montant: 6650, montantNet: 6650, reference: '20261014000042', venteId: 'V42');

final tpFictif = ClientTiersPayant(
    lgTIERSPAYANTID: 'TP1', tpFullName: 'MUGEF-CI', taux: 80, numSecurity: 'M-001', compteTp: 'CT1', order: 1, principal: true);
final clientFictif = ClientAssurance(
  lgCLIENTID: 'C1',
  fullName: 'KOUASSI Awa',
  strFIRSTNAME: 'KOUASSI',
  strLASTNAME: 'Awa',
  strNUMEROSECURITESOCIAL: 'M-001',
  tiersPayants: [tpFictif],
  ayantDroits: [],
);
final ayantDroitFictif = AyantDroit(
    lgAYANTSDROITSID: 'A1', lgCLIENTID: 'C1', fullName: 'KOUASSI Awa', strFIRSTNAME: 'KOUASSI', strLASTNAME: 'Awa', strNUMEROSECURITESOCIAL: 'M-001', strSEXE: '');
final resumeAssuranceFictif = AssuranceSaleSummary(
  montant: 6650,
  montantTp: 5320,
  montantNet: 1330,
  tierspayants: [TiersPayantSummary(numBon: 'B1', taux: 80, compteTp: 'CT1', tpnet: 5320)],
  reference: '20261014000043',
  venteId: 'V43',
);

/// Prévente de la borne (articles de la capture).
BornePrevente preventeBorne(List<SaleItemDetail> lignes) =>
    BornePrevente(venteId: 'V9', reference: '20261014000042', total: lignes.fold(0, (s, l) => s + l.intPRICE), lignes: lignes, at: DateTime(2026, 10, 14, 9, 30));

/// Lignes de l'aperçu (mode test d'impression) dans l'ordre : textes, « [QR] », « [CODE-BARRES <données>] ».
List<String> lignesApercu(WidgetTester tester) {
  final out = <String>[];
  void visiter(Element e) {
    final w = e.widget;
    if (w is Text) {
      out.add(sansDate(w.data ?? w.textSpan?.toPlainText() ?? ''));
    } else if (w is QrImageView) {
      out.add('[QR]');
    } else if (w is BarcodeWidget) {
      out.add('[CODE-BARRES ${w.data}]');
    }
    e.visitChildElements(visiter);
  }

  final contenu = find.descendant(of: find.byType(AlertDialog), matching: find.byType(SingleChildScrollView));
  tester.element(contenu).visitChildElements(visiter);
  return out;
}

/// Lignes de la borne : (largeur, discret, payé par) → lignes.
Map<String, List<String>> lignesBorne(List<SaleItemDetail> lignes) => {
      for (final largeur in [58, 80])
        for (final discret in [false, true])
          for (final paye in [null, 'Wave'])
            'borne $largeur discret=$discret paye=$paye':
                BorneTicket(officine: 'Pharmacie Fictive', prevente: preventeBorne(lignes), discret: discret, largeur: largeur, payePar: paye).lignes,
    };

/// Monte une page vide et rend son contexte (ScaffoldMessenger présent pour les messages d'erreur).
Future<BuildContext> contexteTicket(WidgetTester tester) async {
  late BuildContext ctx;
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) {
    ctx = c;
    return const SizedBox();
  }))));
  return ctx;
}

/// Impression Sunmi simulée de [imprimer] : appels au canal.
Future<List<String>> appelsSunmi(WidgetTester tester, Future<void> Function(BuildContext) imprimer) async {
  final ctx = await contexteTicket(tester);
  final p = ImprimanteSimulee()..installer(tester);
  await imprimer(ctx);
  p.retirer(tester);
  return p.appels;
}

/// Aperçu (mode test) de [imprimer] : lignes du dialogue, puis fermeture.
Future<List<String>> apercu(WidgetTester tester, Future<void> Function(BuildContext) imprimer) async {
  final ctx = await contexteTicket(tester);
  final fin = imprimer(ctx);
  await tester.pumpAndSettle();
  final lignes = lignesApercu(tester);
  await tester.tap(find.text('Fermer'));
  await tester.pumpAndSettle();
  await fin;
  return lignes;
}

/// Tous les tickets avec les réglages PAR DÉFAUT (aucun paramètre nouveau) : la référence 4.1.0 de la
/// non-régression. Clé : « type largeur code provisoire » ; valeur : appels Sunmi ou lignes d'aperçu.
Future<Map<String, List<String>>> tousLesTicketsParDefaut(WidgetTester tester) async {
  final r = ReceiptService();
  final out = <String, List<String>>{};
  for (final largeur in [58, 80]) {
    for (final code in ['QR_CODE', 'BARCODE']) {
      for (final prov in [null, 'HL-0007']) {
        for (final test in [false, true]) {
          final mode = test ? 'apercu' : 'sunmi';
          Future<List<String>> run(Future<void> Function(BuildContext) f) => test ? apercu(tester, f) : appelsSunmi(tester, f);
          final k = '$largeur $code prov=$prov $mode';
          out['prevente $k'] = await run((c) => r.printPreventeTicket(
              context: c, officine: officineFictive, saleSummary: resumeFictif, currentUser: userFictif, isTestMode: test, paperWidth: largeur, ticketCodeType: code, provisoire: prov));
          for (final carnet in [false, true]) {
            out['prevente-assurance carnet=$carnet $k'] = await run((c) => r.printAssurancePreventeTicket(
                context: c, officine: officineFictive, saleSummary: resumeAssuranceFictif, items: articlesFictifs, client: clientFictif, ayantDroit: ayantDroitFictif,
                currentUser: userFictif, isTestMode: test, paperWidth: largeur, ticketCodeType: code, carnet: carnet, reference: '20261014000043', provisoire: prov));
          }
          out['vente $k'] = await run((c) => r.printSaleTicket(
              context: c, officine: officineFictive, saleSummary: resumeFictif, items: articlesFictifs, paymentMethod: PaymentMethod(id: '1', name: 'Espèces'),
              currentUser: userFictif, isTestMode: test, paperWidth: largeur, showQrCode: true, ticketCodeType: code, montantVerse: 10000, monnaie: 3350, provisoire: prov));
          if (prov == null) {
            out['vente-assurance $k'] = await run((c) => r.printAssuranceSaleTicket(
                context: c, officine: officineFictive, saleSummary: resumeAssuranceFictif, items: articlesFictifs, client: clientFictif, ayantDroit: ayantDroitFictif,
                paymentMethod: PaymentMethod(id: '1', name: 'Espèces'), currentUser: userFictif, isTestMode: test, paperWidth: largeur, ticketCodeType: code, reference: '20261014000043'));
          }
        }
      }
    }
  }
  // Borne : noms qui tiennent sur la largeur (les noms trop longs sont la correction 4.1.1).
  final courts = [article('EFFERALGAN 500MG', 2, 1200, id: 'L1'), article('DOLIPRANE 500MG CPR B/16', 1, 900, id: 'L2')];
  for (final e in lignesBorne(courts).entries) {
    out[e.key] = e.value;
  }
  return out;
}
