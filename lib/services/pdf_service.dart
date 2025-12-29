// lib/services/pdf_service.dart
import 'package:collection/collection.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// Imports des modèles
import 'package:prestige_vente_app/api/models/bon_livraison.dart';
import 'package:prestige_vente_app/api/models/bon_livraison_item.dart';
import 'package:prestige_vente_app/api/models/reception_model.dart';

class PdfService {
  final NumberFormat _currencyFormat = NumberFormat.currency(locale: 'fr_FR', symbol: 'FCFA', decimalDigits: 0);

  // ===========================================================================
  // 1. RAPPORT DE POINTAGE BL
  // ===========================================================================

  Future<void> generateAndPrintBlReport({
    required BonLivraison bl,
    required List<BonLivraisonItem> items,
    required Map<String, int> checkedQuantities,
    String filterTitle = "Tous",
  }) async {
    final doc = pw.Document();

    final bool isGroupedMode = filterTitle.contains("Tous (Groupés)");
    final bool isSpecificLocation = filterTitle.contains("Emplacement");
    final bool hideLocationColumn = isGroupedMode || isSpecificLocation;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          List<pw.Widget> content = [
            _buildBlHeader(bl, filterTitle),
            pw.SizedBox(height: 15),
          ];

          if (isGroupedMode) {
            final groupedItems = groupBy(items, (BonLivraisonItem item) => item.zoneGeoName);
            final sortedKeys = groupedItems.keys.toList()..sort();

            for (var location in sortedKeys) {
              final groupItems = groupedItems[location] ?? [];
              groupItems.sort((a, b) => a.nomProduit.compareTo(b.nomProduit));

              content.add(
                pw.Container(
                  width: double.infinity,
                  color: PdfColors.grey200,
                  padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  margin: const pw.EdgeInsets.only(top: 10, bottom: 4),
                  child: pw.Text(
                    "Emplacement : $location",
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                  ),
                ),
              );

              content.add(_buildBlTable(groupItems, checkedQuantities, hideLocationColumn: true));
            }

          } else {
            content.add(_buildBlTable(items, checkedQuantities, hideLocationColumn: hideLocationColumn));
          }

          content.add(pw.SizedBox(height: 15));
          content.add(_buildFooter(items.length));

          return content;
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Rapport_BL_${bl.ref}.pdf',
    );
  }

  // ===========================================================================
  // 2. RAPPORT DE RÉCEPTION
  // ===========================================================================

  Future<void> generateAndPrintReceptionReport({
    required ReceptionBon bon,
    required List<ReceptionItem> items,
    String filterTitle = "Tous",
  }) async {
    final doc = pw.Document();

    final bool isGroupedMode = filterTitle.contains("Tous (Groupés)");
    final bool isSpecificLocation = filterTitle.contains("Emplacement");
    final bool hideLocationColumn = isGroupedMode || isSpecificLocation;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          List<pw.Widget> content = [
            _buildReceptionHeader(bon, filterTitle),
            pw.SizedBox(height: 15),
          ];

          if (isGroupedMode) {
            final groupedItems = groupBy(items, (ReceptionItem item) => item.emplacement.isEmpty ? "Sans Emplacement" : item.emplacement);
            final sortedKeys = groupedItems.keys.toList()..sort();

            for (var location in sortedKeys) {
              final groupItems = groupedItems[location] ?? [];
              groupItems.sort((a, b) => a.nomProduit.compareTo(b.nomProduit));

              content.add(
                pw.Container(
                  width: double.infinity,
                  color: PdfColors.grey200,
                  padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  margin: const pw.EdgeInsets.only(top: 10, bottom: 4),
                  child: pw.Text(
                    "Emplacement : $location",
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                  ),
                ),
              );

              content.add(_buildReceptionTable(groupItems, hideLocationColumn: true));
            }
          } else {
            content.add(_buildReceptionTable(items, hideLocationColumn: hideLocationColumn));
          }

          content.add(pw.SizedBox(height: 15));
          content.add(_buildFooter(items.length));

          return content;
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Rapport_Reception_${bon.ref}.pdf',
    );
  }

  // ===========================================================================
  // HELPER WIDGETS
  // ===========================================================================

  pw.Widget _buildBlHeader(BonLivraison bl, String filterTitle) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text("RAPPORT DE POINTAGE", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Text(DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()), style: pw.TextStyle(fontSize: 10)),
          ],
        ),
        pw.SizedBox(height: 5),
        pw.Text("BL Réf: ${bl.ref}", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.Text("Fournisseur: ${bl.grossiste}", style: pw.TextStyle(fontSize: 10)),
        pw.Text("Filtre: $filterTitle", style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic, color: PdfColors.blue700)),
      ],
    );
  }

  pw.Widget _buildBlTable(List<BonLivraisonItem> items, Map<String, int> checkedQuantities, {required bool hideLocationColumn}) {
    final List<String> headers = ['CIP', 'Désignation'];
    if (!hideLocationColumn) headers.add('Zone');
    headers.addAll(['PA', 'Théo.', 'Cpté', 'Ecart']);

    final Map<int, pw.TableColumnWidth> columnWidths = {
      0: const pw.FixedColumnWidth(50),
      1: const pw.FlexColumnWidth(3),
    };

    int colIndex = 2;
    if (!hideLocationColumn) {
      columnWidths[colIndex] = const pw.FlexColumnWidth(1);
      colIndex++;
    }

    columnWidths[colIndex] = const pw.FixedColumnWidth(40);
    columnWidths[colIndex + 1] = const pw.FixedColumnWidth(30);
    columnWidths[colIndex + 2] = const pw.FixedColumnWidth(30);
    columnWidths[colIndex + 3] = const pw.FixedColumnWidth(30);

    return pw.TableHelper.fromTextArray(
      headers: headers,
      columnWidths: columnWidths,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9),
      headerDecoration: pw.BoxDecoration(color: PdfColors.blue700),
      rowDecoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5))),
      cellAlignment: pw.Alignment.centerLeft,
      cellAlignments: {
        colIndex: pw.Alignment.centerRight,
        colIndex + 1: pw.Alignment.center,
        colIndex + 2: pw.Alignment.center,
        colIndex + 3: pw.Alignment.center,
      },
      cellPadding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      data: items.map((item) {
        final checkedQty = checkedQuantities[item.id] ?? 0;
        final theoretical = item.stockTheorique;
        final ecart = checkedQty - theoretical;

        final bool isControlled = checkedQuantities.containsKey(item.id);
        final bool hasEcart = ecart != 0;

        // Suppression de const pour éviter l'erreur
        final pw.TextStyle baseStyle = isControlled
            ? pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)
            : pw.TextStyle(fontSize: 8);

        pw.Widget cell(String text, {pw.TextStyle? specificStyle}) {
          return pw.Text(text, style: specificStyle ?? baseStyle);
        }

        final List<pw.Widget> row = [
          cell(item.cip),
          cell(item.nomProduit),
        ];

        if (!hideLocationColumn) {
          row.add(cell(item.zoneGeoName));
        }

        row.addAll([
          cell(_currencyFormat.format(item.prixAchat).replaceAll('FCFA', '')),
          cell(theoretical.toString()),
          cell(isControlled ? checkedQty.toString() : "-"),
          hasEcart && isControlled
              ? pw.Text(ecart > 0 ? "+$ecart" : "$ecart", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.red, fontSize: 8))
              : cell(isControlled ? (ecart > 0 ? "+$ecart" : "$ecart") : "-"),
        ]);

        return row;
      }).toList(),
    );
  }

  pw.Widget _buildReceptionHeader(ReceptionBon bon, String filterTitle) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text("RAPPORT DE RÉCEPTION", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Text(DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()), style: pw.TextStyle(fontSize: 10)),
          ],
        ),
        pw.SizedBox(height: 5),
        pw.Text("BL Réf: ${bon.ref}", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.Text("Fournisseur: ${bon.grossiste}", style: pw.TextStyle(fontSize: 10)),
        pw.Text("Filtre: $filterTitle", style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic, color: PdfColors.blue700)),
      ],
    );
  }

  pw.Widget _buildReceptionTable(List<ReceptionItem> items, {required bool hideLocationColumn}) {
    final List<String> headers = ['CIP', 'Désignation'];
    if (!hideLocationColumn) headers.add('Zone');
    headers.addAll(['Qte BL', 'Reçu', 'Ecart']);

    final Map<int, pw.TableColumnWidth> columnWidths = {
      0: const pw.FixedColumnWidth(50),
      1: const pw.FlexColumnWidth(3),
    };

    int colIndex = 2;
    if (!hideLocationColumn) {
      columnWidths[colIndex] = const pw.FlexColumnWidth(1);
      colIndex++;
    }

    columnWidths[colIndex] = const pw.FixedColumnWidth(40);
    columnWidths[colIndex + 1] = const pw.FixedColumnWidth(40);
    columnWidths[colIndex + 2] = const pw.FixedColumnWidth(40);

    return pw.TableHelper.fromTextArray(
      headers: headers,
      columnWidths: columnWidths,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9),
      headerDecoration: pw.BoxDecoration(color: PdfColors.blue700),
      rowDecoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5))),
      cellAlignment: pw.Alignment.centerLeft,
      cellAlignments: {
        colIndex: pw.Alignment.center,
        colIndex + 1: pw.Alignment.center,
        colIndex + 2: pw.Alignment.center,
      },
      cellPadding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      data: items.map((item) {
        final checkedQty = item.quantiteControle;
        final blQty = item.qteRecue;
        final ecart = checkedQty - blQty;

        final bool isControlled = checkedQty > 0;
        final bool hasEcart = ecart != 0;

        // Suppression de const
        final pw.TextStyle baseStyle = isControlled
            ? pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)
            : pw.TextStyle(fontSize: 8);

        pw.Widget cell(String text, {pw.TextStyle? specificStyle}) {
          return pw.Text(text, style: specificStyle ?? baseStyle);
        }

        final List<pw.Widget> row = [
          cell(item.cip),
          cell(item.nomProduit),
        ];

        if (!hideLocationColumn) {
          row.add(cell(item.emplacement.isEmpty ? '-' : item.emplacement));
        }

        row.addAll([
          cell(blQty.toString()),
          cell(isControlled ? checkedQty.toString() : "-"),

          hasEcart && isControlled
              ? pw.Text(ecart > 0 ? "+$ecart" : "$ecart", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.red, fontSize: 8))
              : cell(isControlled ? (ecart > 0 ? "+$ecart" : "$ecart") : "-"),
        ]);

        return row;
      }).toList(),
    );
  }

  pw.Widget _buildFooter(int totalLines) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [
        pw.Text("Total lignes: $totalLines", style: pw.TextStyle(color: PdfColors.grey700, fontSize: 9)),
      ],
    );
  }
}