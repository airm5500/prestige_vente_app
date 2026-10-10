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
import 'package:prestige_vente_app/widgets/presentation_style.dart';

// Imports PDF & Printing
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ProformaListScreen extends StatefulWidget {
  /// Présentation imposée (tests) ; sinon celle choisie sur l'appareil (A par défaut).
  final ListPresentation? presentation;
  const ProformaListScreen({Key? key, this.presentation}) : super(key: key);

  @override
  State<ProformaListScreen> createState() => _ProformaListScreenState();
}

class _ProformaListScreenState extends State<ProformaListScreen> {
  List<ProformaListItem> _proformas = [];
  bool _isLoading = true;
  final String _today = DateFormat('yyyy-MM-dd').format(DateTime.now());

  late ListPresentation _style = widget.presentation ?? ListPresentation.dashboard;

  @override
  void initState() {
    super.initState();
    if (widget.presentation == null) {
      PresentationPrefs.load().then((p) {
        if (mounted) setState(() => _style = p);
      });
    }
    _loadProformas();
  }

  void _setStyle(ListPresentation p) {
    setState(() => _style = p);
    if (widget.presentation == null) PresentationPrefs.save(p);
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

  // ---------------------------------------------------------------------------
  // Affichage : A · Tableau de bord, B · Liste groupée, C · Parcours guidé
  // ---------------------------------------------------------------------------
  bool _isOpen(ProformaListItem item) => item.strSTATUT == 'is_Process' || item.strSTATUT == 'devis';
  int get _total => _proformas.fold(0, (s, p) => s + p.intPRICE);

  StatusBadge _statusBadge(ProformaListItem item) => _isOpen(item)
      ? StatusBadge(item.strSTATUT, fg: const Color(0xFF0B6B45), bg: const Color(0xFFDCF5E7))
      : StatusBadge(item.strSTATUT, fg: const Color(0xFF3D4B60), bg: const Color(0xFFE6EBF2));

  Widget get _fab => FloatingActionButton.extended(
        onPressed: () => _openProforma(null),
        label: const Text("Nouveau Devis"),
        icon: const Icon(Icons.add),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      );

  /// Liste ou état vide / chargement (même comportement pour les trois présentations).
  Widget _list(Widget Function() builder) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_proformas.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadProformas,
        child: ListView(children: const [
          Padding(padding: EdgeInsets.all(32), child: Text("Aucun devis trouvé pour aujourd'hui", textAlign: TextAlign.center)),
        ]),
      );
    }
    return RefreshIndicator(onRefresh: _loadProformas, child: builder());
  }

  @override
  Widget build(BuildContext context) => switch (_style) {
        ListPresentation.dashboard => _buildDashboard(),
        ListPresentation.compact => _buildCompact(),
        ListPresentation.guided => _buildGuided(),
      };

  // --- A ---
  Widget _buildDashboard() => Scaffold(
        backgroundColor: Pal.page,
        floatingActionButton: _fab,
        body: Column(children: [
          NavyHeader(
            title: 'Proformas / Devis',
            subtitle: "Devis du jour · ${DateFormat('dd/MM/yyyy').format(DateTime.now())}",
            actions: [
              PresentationMenuButton(value: _style, onChanged: _setStyle),
              IconButton(icon: const Icon(Icons.refresh, color: Colors.white), tooltip: 'Actualiser', onPressed: _loadProformas),
            ],
            children: [
              Row(children: [
                Expanded(child: KpiTile('${_proformas.length}', 'devis du jour')),
                const SizedBox(width: 8),
                Expanded(child: KpiTile('${_proformas.where(_isOpen).length}', 'en cours')),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: KpiTile('${_formatCurrency(_total)} F', 'montant total', highlight: true)),
              ]),
            ],
          ),
          Expanded(
            child: _list(() => ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
                  itemCount: _proformas.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _cardA(_proformas[i]),
                )),
          ),
        ]),
      );

  Widget _cardA(ProformaListItem item) => SoftCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            GrossisteAvatar(item.strClientFullName),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.strClientFullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Pal.ink)),
                Text("Réf: ${item.strREF} - ${item.heure}", style: const TextStyle(fontSize: 13, color: Pal.muted)),
                if (item.userFullName.isNotEmpty)
                  Text("Vendeur: ${item.userFullName}", style: const TextStyle(fontSize: 12, color: Pal.muted)),
              ]),
            ),
            _statusBadge(item),
          ]),
          const SizedBox(height: 10),
          Text("${_formatCurrency(item.intPRICE)} F", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Pal.navy)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 44,
                child: OutlinedButton.icon(
                  style: outlineButton,
                  icon: const Icon(Icons.print, size: 18),
                  label: const Text('Imprimer A4'),
                  onPressed: () => _handlePrint(item),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(height: 44, child: ElevatedButton(style: navyButton, onPressed: () => _openProforma(item), child: const Text('Ouvrir'))),
            ),
          ]),
        ]),
      );

  // --- B ---
  Widget _buildCompact() => Scaffold(
        backgroundColor: Colors.white,
        floatingActionButton: _fab,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: Pal.navy,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: const Text("Liste Proformas / Devis", style: TextStyle(fontWeight: FontWeight.bold, color: Pal.navy)),
          actions: [
            PresentationMenuButton(value: _style, onChanged: _setStyle, color: Pal.navy),
            IconButton(icon: const Icon(Icons.refresh, color: Pal.navy), tooltip: 'Actualiser', onPressed: _loadProformas),
          ],
          bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider(height: 1, color: Pal.line)),
        ),
        body: Column(children: [
          Expanded(
            child: _list(() => ListView.builder(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: _proformas.length,
                  itemBuilder: (_, i) {
                    final item = _proformas[i];
                    return InkWell(
                      onTap: () => _openProforma(item),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
                        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEF1F5)))),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(item.strClientFullName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Pal.ink)),
                              Text.rich(TextSpan(style: const TextStyle(fontSize: 13, color: Pal.muted), children: [
                                TextSpan(text: "${item.strREF} · ${item.heure}${item.userFullName.isNotEmpty ? ' · ${item.userFullName}' : ''} · "),
                                TextSpan(
                                  text: item.strSTATUT,
                                  style: TextStyle(fontWeight: FontWeight.w600, color: _isOpen(item) ? const Color(0xFF0B6B45) : Pal.muted),
                                ),
                              ])),
                            ]),
                          ),
                          Text("${_formatCurrency(item.intPRICE)} F", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Pal.navy)),
                          IconButton(
                            icon: const Icon(Icons.print, color: Colors.blueGrey),
                            tooltip: "Imprimer A4",
                            onPressed: () => _handlePrint(item),
                          ),
                        ]),
                      ),
                    );
                  },
                )),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(color: Color(0xFFF8FAFC), border: Border(top: BorderSide(color: Pal.line))),
            child: SafeArea(
              top: false,
              child: Row(children: [
                Expanded(child: Text("${_proformas.length} devis aujourd'hui", style: const TextStyle(fontSize: 13, color: Color(0xFF4A5A70)))),
                Text("Total ${_formatCurrency(_total)} F", style: const TextStyle(fontWeight: FontWeight.w600, color: Pal.ink)),
              ]),
            ),
          ),
        ]),
      );

  // --- C ---
  Widget _buildGuided() => Scaffold(
        backgroundColor: const Color(0xFFEEF2F7),
        body: Column(children: [
          NavyHeader(
            title: 'Proformas / Devis',
            rounded: false,
            actions: [
              PresentationMenuButton(value: _style, onChanged: _setStyle),
              IconButton(icon: const Icon(Icons.refresh, color: Colors.white), tooltip: 'Actualiser', onPressed: _loadProformas),
            ],
            children: const [
              StepsBar(active: 0, steps: [
                (title: 'Devis', detail: 'nouveau ou existant', onTap: null),
                (title: 'Produits', detail: 'quantités, remises', onTap: null),
                (title: 'Imprimer', detail: 'proforma A4', onTap: null),
              ]),
            ],
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
              SoftCard(
                band: Pal.amber,
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text('Nouveau devis', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Pal.ink)),
                  const Text('Choisissez le client, ajoutez les produits, puis imprimez la proforma.',
                      style: TextStyle(fontSize: 13, color: Pal.muted)),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      style: amberButton,
                      icon: const Icon(Icons.add),
                      label: const Text("Nouveau Devis"),
                      onPressed: () => _openProforma(null),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              Text("DEVIS DU JOUR · ${_proformas.length} · ${_formatCurrency(_total)} F",
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: Color(0xFF4A5A70))),
              const SizedBox(height: 8),
              if (_isLoading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
              if (!_isLoading && _proformas.isEmpty)
                const Padding(padding: EdgeInsets.all(24), child: Text("Aucun devis trouvé pour aujourd'hui", textAlign: TextAlign.center)),
              if (!_isLoading)
                for (final item in _proformas) ...[
                  SoftCard(
                    child: Row(children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => _openProforma(item),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(item.strClientFullName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Pal.ink)),
                            Text("${item.strREF} · ${item.heure} · ${_formatCurrency(item.intPRICE)} F", style: const TextStyle(fontSize: 13, color: Pal.muted)),
                          ]),
                        ),
                      ),
                      IconButton(icon: const Icon(Icons.print, color: Colors.blueGrey), tooltip: "Imprimer A4", onPressed: () => _handlePrint(item)),
                      IconButton.filled(
                        tooltip: 'Ouvrir ${item.strREF}',
                        style: IconButton.styleFrom(backgroundColor: Pal.navy, foregroundColor: Colors.white, minimumSize: const Size(44, 44)),
                        icon: const Icon(Icons.arrow_forward),
                        onPressed: () => _openProforma(item),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 10),
                ],
            ]),
          ),
        ]),
      );
}