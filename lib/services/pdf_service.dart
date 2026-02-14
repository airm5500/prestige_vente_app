// lib/services/pdf_service.dart
// VERSION CORRIGÉE : Zéro const, construction impérative stricte.
import 'package:collection/collection.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:prestige_vente_app/api/models/bon_livraison.dart';
import 'package:prestige_vente_app/api/models/bon_livraison_item.dart';
import 'package:prestige_vente_app/api/models/reception_model.dart';
import 'package:prestige_vente_app/api/models/perime_models.dart';

class PdfService {
  final NumberFormat _currencyFormat = NumberFormat.currency(locale: 'fr_FR', symbol: 'FCFA', decimalDigits: 0);

  // ===========================================================================
  // 1. RAPPORT BL
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
        margin: pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          List<pw.Widget> content = [];
          content.add(_buildBlHeader(bl, filterTitle));
          content.add(pw.SizedBox(height: 15));

          if (isGroupedMode) {
            final groupedItems = groupBy(items, (BonLivraisonItem item) => item.zoneGeoName);
            final sortedKeys = groupedItems.keys.toList()..sort();

            for (var location in sortedKeys) {
              final groupItems = groupedItems[location] ?? [];
              groupItems.sort((a, b) => a.nomProduit.compareTo(b.nomProduit));

              content.add(pw.Container(
                width: double.infinity,
                color: PdfColors.grey200,
                padding: pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                margin: pw.EdgeInsets.only(top: 10, bottom: 4),
                child: pw.Text("Emplacement : $location", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
              ));
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

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => doc.save(), name: 'Rapport_BL_${bl.ref}.pdf');
  }

  // ===========================================================================
  // 2. RAPPORT RECEPTION
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
        margin: pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          List<pw.Widget> content = [];
          content.add(_buildReceptionHeader(bon, filterTitle));
          content.add(pw.SizedBox(height: 15));

          if (isGroupedMode) {
            final groupedItems = groupBy(items, (ReceptionItem item) => item.emplacement.isEmpty ? "Sans Emplacement" : item.emplacement);
            final sortedKeys = groupedItems.keys.toList()..sort();

            for (var location in sortedKeys) {
              final groupItems = groupedItems[location] ?? [];
              groupItems.sort((a, b) => a.nomProduit.compareTo(b.nomProduit));

              content.add(pw.Container(
                width: double.infinity,
                color: PdfColors.grey200,
                padding: pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                margin: pw.EdgeInsets.only(top: 10, bottom: 4),
                child: pw.Text("Emplacement : $location", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
              ));
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

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => doc.save(), name: 'Rapport_Reception_${bon.ref}.pdf');
  }

  // ===========================================================================
  // 3. RAPPORT PERIMES
  // ===========================================================================

  Future<void> generateAndPrintPerimesReport(
      List<ProduitPerime> items,
      String filterLabel,
      {required int totalAchat, required int totalVente}
      ) async {
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          return [
            _buildPerimesHeader(filterLabel),
            pw.SizedBox(height: 20),
            _buildPerimesTable(items),
            pw.SizedBox(height: 15),
            pw.Divider(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text("Nombre de lignes : ${items.length}", style: pw.TextStyle(fontSize: 10)),
                    pw.SizedBox(height: 5),
                    pw.Container(
                      padding: pw.EdgeInsets.all(10),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey100,
                        border: pw.Border.all(color: PdfColors.grey400),
                        borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                      ),
                      child: pw.Row(
                        mainAxisSize: pw.MainAxisSize.min,
                        children: [
                          _buildValueBox("Valeur Achat", totalAchat),
                          pw.SizedBox(width: 20),
                          _buildValueBox("Valeur Vente", totalVente),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => doc.save(), name: 'Rapport_Perimes_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf');
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  pw.Widget _buildValueBox(String label, int value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        pw.Text(_currencyFormat.format(value).replaceAll('FCFA', ' F'), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
      ],
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
    final Map<int, pw.TableColumnWidth> columnWidths = {};
    columnWidths[0] = pw.FixedColumnWidth(50);
    columnWidths[1] = pw.FlexColumnWidth(3);

    int colIndex = 2;
    if (!hideLocationColumn) {
      columnWidths[colIndex] = pw.FlexColumnWidth(1);
      colIndex++;
    }
    columnWidths[colIndex] = pw.FixedColumnWidth(40);
    columnWidths[colIndex + 1] = pw.FixedColumnWidth(30);
    columnWidths[colIndex + 2] = pw.FixedColumnWidth(30);
    columnWidths[colIndex + 3] = pw.FixedColumnWidth(30);

    final List<String> headers = ['CIP', 'Désignation'];
    if (!hideLocationColumn) headers.add('Zone');
    headers.addAll(['PA', 'Théo.', 'Cpté', 'Ecart']);

    return pw.TableHelper.fromTextArray(
      headers: headers,
      columnWidths: columnWidths,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 8),
      headerDecoration: pw.BoxDecoration(color: PdfColors.blue700),
      rowDecoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5))),
      cellAlignment: pw.Alignment.centerLeft,
      cellAlignments: {
        colIndex: pw.Alignment.centerRight,
        colIndex + 1: pw.Alignment.center,
        colIndex + 2: pw.Alignment.center,
        colIndex + 3: pw.Alignment.center,
      },
      cellPadding: pw.EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      cellStyle: pw.TextStyle(fontSize: 7),
      data: items.map((item) {
        final checkedQty = checkedQuantities[item.id] ?? 0;
        final theoretical = item.stockFinalTheorique;
        final ecart = checkedQty - theoretical;
        final bool isControlled = checkedQuantities.containsKey(item.id);
        final bool hasEcart = ecart != 0;

        pw.TextStyle baseStyle;
        if (isControlled) {
          baseStyle = pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold);
        } else {
          baseStyle = pw.TextStyle(fontSize: 7);
        }

        pw.Widget cell(String text, {pw.TextStyle? specificStyle}) {
          return pw.Text(text, style: specificStyle ?? baseStyle);
        }

        List<pw.Widget> row = [];
        row.add(cell(item.cip));
        row.add(cell(item.nomProduit));

        if (!hideLocationColumn) {
          row.add(cell(item.zoneGeoName));
        }

        row.add(cell(_currencyFormat.format(item.prixAchat).replaceAll('FCFA', '')));
        row.add(cell(theoretical.toString()));
        row.add(cell(isControlled ? checkedQty.toString() : "-"));

        if (hasEcart && isControlled) {
          row.add(pw.Text(
              ecart > 0 ? "+$ecart" : "$ecart",
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.red, fontSize: 7)
          ));
        } else {
          row.add(cell(isControlled ? (ecart > 0 ? "+$ecart" : "$ecart") : "-"));
        }
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
    final Map<int, pw.TableColumnWidth> columnWidths = {};
    columnWidths[0] = pw.FixedColumnWidth(50);
    columnWidths[1] = pw.FlexColumnWidth(3);

    int colIndex = 2;
    if (!hideLocationColumn) {
      columnWidths[colIndex] = pw.FlexColumnWidth(1);
      colIndex++;
    }
    columnWidths[colIndex] = pw.FixedColumnWidth(40);
    columnWidths[colIndex + 1] = pw.FixedColumnWidth(40);
    columnWidths[colIndex + 2] = pw.FixedColumnWidth(40);

    final List<String> headers = ['CIP', 'Désignation'];
    if (!hideLocationColumn) headers.add('Zone');
    headers.addAll(['Qte BL', 'Reçu', 'Ecart']);

    return pw.TableHelper.fromTextArray(
      headers: headers,
      columnWidths: columnWidths,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 8),
      headerDecoration: pw.BoxDecoration(color: PdfColors.blue700),
      rowDecoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5))),
      cellAlignment: pw.Alignment.centerLeft,
      cellAlignments: {
        colIndex: pw.Alignment.center,
        colIndex + 1: pw.Alignment.center,
        colIndex + 2: pw.Alignment.center,
      },
      cellPadding: pw.EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      cellStyle: pw.TextStyle(fontSize: 7),
      data: items.map((item) {
        final checkedQty = item.quantiteControle;
        final blQty = item.qteRecue;
        final ecart = checkedQty - blQty;
        final bool isControlled = checkedQty > 0;
        final bool hasEcart = ecart != 0;

        pw.TextStyle baseStyle;
        if (isControlled) {
          baseStyle = pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold);
        } else {
          baseStyle = pw.TextStyle(fontSize: 7);
        }

        pw.Widget cell(String text, {pw.TextStyle? specificStyle}) {
          return pw.Text(text, style: specificStyle ?? baseStyle);
        }

        List<pw.Widget> row = [];
        row.add(cell(item.cip));
        row.add(cell(item.nomProduit));

        if (!hideLocationColumn) {
          row.add(cell(item.emplacement.isEmpty ? '-' : item.emplacement));
        }

        row.add(cell(blQty.toString()));
        row.add(cell(isControlled ? checkedQty.toString() : "-"));

        if (hasEcart && isControlled) {
          row.add(pw.Text(
              ecart > 0 ? "+$ecart" : "$ecart",
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.red, fontSize: 7)
          ));
        } else {
          row.add(cell(isControlled ? (ecart > 0 ? "+$ecart" : "$ecart") : "-"));
        }
        return row;
      }).toList(),
    );
  }

  pw.Widget _buildPerimesHeader(String filterLabel) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text("RAPPORT PRODUITS PÉRIMÉS", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Text(DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()), style: pw.TextStyle(fontSize: 10)),
          ],
        ),
        pw.SizedBox(height: 5),
        pw.Text("Filtre appliqué : $filterLabel", style: pw.TextStyle(fontSize: 12, fontStyle: pw.FontStyle.italic, color: PdfColors.blue700)),
        pw.SizedBox(height: 5),
        pw.Container(height: 1, color: PdfColors.grey400),
      ],
    );
  }

  pw.Widget _buildPerimesTable(List<ProduitPerime> items) {
    final Map<int, pw.TableColumnWidth> columnWidths = {};
    columnWidths[0] = pw.FixedColumnWidth(50);
    columnWidths[1] = pw.FlexColumnWidth(3);
    columnWidths[2] = pw.FixedColumnWidth(50);
    columnWidths[3] = pw.FixedColumnWidth(60);
    columnWidths[4] = pw.FixedColumnWidth(30);
    columnWidths[5] = pw.FlexColumnWidth(2);

    return pw.TableHelper.fromTextArray(
      headers: ['CIP', 'Désignation', 'Lot', 'Date Pér.', 'Qté', 'Statut'],
      columnWidths: columnWidths,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 8),
      headerDecoration: pw.BoxDecoration(color: PdfColors.red700),
      rowDecoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5))),
      cellAlignment: pw.Alignment.centerLeft,
      cellAlignments: {
        4: pw.Alignment.center,
      },
      cellPadding: pw.EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      cellStyle: pw.TextStyle(fontSize: 7),
      data: items.map((item) {
        return [
          item.codeCip,
          item.libelle,
          item.numLot,
          item.datePerement,
          item.quantiteLot.toString(),
          item.statut,
        ];
      }).toList(),
    );
  }
}