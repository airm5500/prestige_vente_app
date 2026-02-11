// lib/screens/proforma/proforma_list_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

// Imports App
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/proforma_models.dart';
import 'package:prestige_vente_app/providers/proforma_provider.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/screens/proforma/proforma_screen.dart';
import 'package:prestige_vente_app/utils/constants.dart';

// Imports PDF & Printing
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ProformaListScreen extends StatefulWidget {
  const ProformaListScreen({Key? key}) : super(key: key);

  @override
  State<ProformaListScreen> createState() => _ProformaListScreenState();
}

class _ProformaListScreenState extends State<ProformaListScreen> {
  List<ProformaListItem> _proformas = [];
  bool _isLoading = true;
  final String _today = DateFormat('yyyy-MM-dd').format(DateTime.now());

  @override
  void initState() {
    super.initState();
    _loadProformas();
  }

  Future<void> _loadProformas() async {
    setState(() => _isLoading = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final list = await api.fetchProformas(dtStart: _today, dtEnd: _today);
      if (mounted) {
        setState(() {
          _proformas = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openProforma(ProformaListItem? item) async {
    final provider = Provider.of<ProformaProvider>(context, listen: false);
    provider.resetSale();

    if (item != null) {
      await provider.loadExistingProforma(item);
    }

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProformaScreen()),
    );
    _loadProformas();
  }

  // --- FONCTION PRINCIPALE D'IMPRESSION (PILOTE) ---
  Future<void> _handlePrint(ProformaListItem item) async {
    setState(() => _isLoading = true);

    try {
      final provider = Provider.of<ProformaProvider>(context, listen: false);
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      // 1. Charger les détails (produits)
      await provider.loadExistingProforma(item);

      if (!mounted) return;

      // 2. RÉCUPÉRATION CORRIGÉE DES INFOS (Basée sur votre modèle User.dart)
      String nomOfficine = "MA PHARMACIE";

      // On utilise officineName comme défini dans votre modèle User
      if (authProvider.user != null && authProvider.user!.officineName.isNotEmpty) {
        nomOfficine = authProvider.user!.officineName;
      }

      // 3. Générer et Imprimer le PDF A4
      await _generateAndPrintA4(
        item: item,
        items: provider.cartItems,
        totalNet: provider.netAPayer,
        officineName: nomOfficine,
        officineAddress: "", // Adresse vide car pas dispo dans User.dart
        // On utilise firstName comme défini dans votre modèle User
        vendeur: item.userFullName.isNotEmpty
            ? item.userFullName
            : (authProvider.user?.firstName ?? "Caisse"),
      );

      // 4. Nettoyage
      provider.resetSale();

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur d'impression : $e"), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- GÉNÉRATEUR PDF A4 ---
  Future<void> _generateAndPrintA4({
    required ProformaListItem item,
    required List<dynamic> items, // CartItems
    required int totalNet,
    required String officineName,
    required String officineAddress,
    required String vendeur,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.openSansRegular();
    final fontBold = await PdfGoogleFonts.openSansBold();

    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        build: (pw.Context context) {
          return [
            // --- EN-TÊTE ---
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // NOM DE LA PHARMACIE (EN GROS)
                    pw.Text(officineName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 15)),
                    pw.SizedBox(height: 4),
                    if (officineAddress.isNotEmpty)
                      pw.Text(officineAddress, style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text("***"),
                    pw.Text("FACTURE PROFORMA", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 15, color: PdfColors.blue800)),
                    pw.Text("N° ${item.strREF}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                    pw.Text("Date: $dateStr", style: const pw.TextStyle(fontSize: 10)),
                  ],
                )
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Divider(),
            pw.SizedBox(height: 10),

            // --- INFO CLIENT ---
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: pw.BorderRadius.circular(4),
                color: PdfColors.grey100,
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text("CLIENT:", style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                  pw.Text(item.strClientFullName.toUpperCase(), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // --- TABLEAU DES PRODUITS ---
          pw.TableHelper.fromTextArray(
              headers: ['Désignation', 'Qté', 'P.U.', 'Total'],
              data: items.map((line) {
                // Utilisation dynamique (duck typing) pour éviter les imports croisés
                final String name = line.strNAME;
                final int qty = line.intQUANTITY;
                final int price = line.intPRICEUNITAIR;
                final int totalLine = price * qty;

                return [
                  name,
                  qty.toString(),
                  _formatCurrencyPDF(price),
                  _formatCurrencyPDF(totalLine),
                ];
              }).toList(),
              border: null,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blue700),
              rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5))),
              cellAlignment: pw.Alignment.centerLeft,
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.center,
                2: pw.Alignment.centerRight,
                3: pw.Alignment.centerRight,
              },
              cellPadding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 5),
            ),
            pw.SizedBox(height: 20),

            // --- TOTAUX ---
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Container(
                  width: 200,
                  child: pw.Column(
                    children: [
                      pw.Divider(),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text("TOTAL NET A PAYER:", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                          pw.Text("${_formatCurrencyPDF(totalNet)} FCFA", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                        ],
                      ),
                      pw.Divider(),
                    ],
                  ),
                ),
              ],
            ),

            pw.Spacer(),

            // --- PIED DE PAGE ---
            pw.Text(
              "Arrêté la présente facture proforma à la somme de : ${_formatCurrencyPDF(totalNet)} FCFA.",
              style: pw.TextStyle(fontStyle: pw.FontStyle.italic, fontSize: 10),
            ),
            pw.SizedBox(height: 20),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text("Vendeur : $vendeur", style: const pw.TextStyle(fontSize: 10)),
                pw.Text("Signature & Cachet", style: const pw.TextStyle(fontSize: 10)),
              ],
            ),
          ];
        },
      ),
    );

    // Lancer l'impression / Aperçu
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Proforma_${item.strREF}',
    );
  }

  // Helper pour formater les chiffres
  String _formatCurrencyPDF(int amount) {
    return amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]} ');
  }

  String _formatCurrency(int amount) {
    return amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]} ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Liste Proformas / Devis")),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openProforma(null),
        label: const Text("Nouveau Devis"),
        icon: const Icon(Icons.add),
        backgroundColor: AppColors.primary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _proformas.isEmpty
          ? const Center(child: Text("Aucun devis trouvé pour aujourd'hui"))
          : RefreshIndicator(
        onRefresh: _loadProformas,
        child: ListView.builder(
          itemCount: _proformas.length,
          itemBuilder: (context, index) {
            final item = _proformas[index];
            final bool isGreen = item.strSTATUT == 'is_Process' || item.strSTATUT == 'devis';

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                leading: CircleAvatar(
                  backgroundColor: Colors.purple.shade100,
                  child: const Icon(Icons.description, color: Colors.purple),
                ),
                title: Text(item.strClientFullName, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Réf: ${item.strREF} - ${item.heure}"),
                    if (item.userFullName.isNotEmpty)
                      Text("Vendeur: ${item.userFullName}", style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text("${_formatCurrency(item.intPRICE)} F", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primary)),
                        Text(
                          item.strSTATUT,
                          style: TextStyle(
                              fontSize: 12,
                              color: isGreen ? Colors.green : Colors.grey,
                              fontWeight: FontWeight.bold
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    // BOUTON IMPRIMER A4
                    IconButton(
                      icon: const Icon(Icons.print, color: Colors.blueGrey),
                      tooltip: "Imprimer A4",
                      onPressed: () => _handlePrint(item),
                    ),
                  ],
                ),
                onTap: () => _openProforma(item),
              ),
            );
          },
        ),
      ),
    );
  }
}