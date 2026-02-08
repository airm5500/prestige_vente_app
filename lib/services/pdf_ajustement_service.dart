//import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:prestige_vente_app/api/models/ajustement.dart';
//import 'package:prestige_vente_app/utils/constants.dart';

class PdfAjustementService {

  /// Génère et lance l'impression/partage du PDF
  Future<void> printAjustementTicket(List<AjustementItem> items, String userName) async {
    final doc = pw.Document();
    final date = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    // Calculs pour le résumé
    final totalItems = items.length;
    final totalAjout = items.where((i) => i.intNUMBER > 0).length;
    final totalRetrait = items.where((i) => i.intNUMBER < 0).length;

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // EN-TÊTE
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("BON D'AJUSTEMENT DE STOCK", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18)),
                  pw.Text("Date: $date", style: const pw.TextStyle(fontSize: 12)),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Text("Opérateur: $userName"),
              pw.Divider(),
              pw.SizedBox(height: 20),

              // RÉSUMÉ
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSummaryBox("Total Lignes", "$totalItems"),
                  _buildSummaryBox("Ajouts", "+$totalAjout"),
                  _buildSummaryBox("Retraits", "-$totalRetrait"),
                ],
              ),
              pw.SizedBox(height: 20),

              // TABLEAU DES PRODUITS
              pw.TableHelper.fromTextArray(
                context: context,
                border: null,
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
                rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300))),
                cellAlignments: {
                  0: pw.Alignment.centerLeft, // Produit
                  1: pw.Alignment.center,     // CIP
                  2: pw.Alignment.center,     // Qté
                  3: pw.Alignment.center,     // Avant
                  4: pw.Alignment.center,     // Après
                  5: pw.Alignment.centerLeft, // Motif
                },
                headers: ['Produit', 'CIP', 'Qté', 'Avant', 'Après', 'Motif'],
                data: items.map((item) {
                  final isPositive = item.intNUMBER > 0;
                  final sign = isPositive ? "+" : "";
                  return [
                    item.strNAME,
                    item.intCIP,
                    "$sign${item.intNUMBER}",
                    "${item.intNUMBERCURRENTSTOCK}",
                    "${item.intNUMBERAFTERSTOCK}",
                    item.motifAjustement,
                  ];
                }).toList(),
              ),

              pw.Spacer(),

              // PIED DE PAGE
              pw.Divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("Prestige Vente App"),
                  pw.Text("Page ${context.pageNumber}/${context.pagesCount}"),
                ],
              ),
            ],
          );
        },
      ),
    );

    // Lancement de l'interface d'impression système (Android/iOS)
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Ajustement_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}',
    );
  }

  pw.Widget _buildSummaryBox(String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        children: [
          pw.Text(label, style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 10)),
          pw.Text(value, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }
}