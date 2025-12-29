// lib/screens/bl_control/bl_report_screen.dart
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/bon_livraison_item.dart';
import 'package:prestige_vente_app/providers/bl_control_provider.dart';
import 'package:prestige_vente_app/services/pdf_service.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

class BlReportScreen extends StatefulWidget {
  final List<BonLivraisonItem>? filteredItems;
  final String filterName;

  const BlReportScreen({
    super.key,
    this.filteredItems,
    this.filterName = "Tous"
  });

  @override
  State<BlReportScreen> createState() => _BlReportScreenState();
}

class _BlReportScreenState extends State<BlReportScreen> {
  bool _isGeneratingPdf = false;
  String _currentFilter = 'TOUS'; // Options: TOUS, CONTROLE, NON_CONTROLE

  // Récupère la liste filtrée selon le choix de l'utilisateur (Dropdown)
  List<BonLivraisonItem> _getDisplayList(List<BonLivraisonItem> sourceList, Map<String, int> checkedQuantities) {
    switch (_currentFilter) {
      case 'CONTROLE':
        return sourceList.where((item) => checkedQuantities.containsKey(item.id)).toList();
      case 'NON_CONTROLE':
        return sourceList.where((item) => !checkedQuantities.containsKey(item.id)).toList();
      case 'TOUS':
      default:
        return sourceList;
    }
  }

  Future<void> _handlePrint(BuildContext context) async {
    setState(() {
      _isGeneratingPdf = true;
    });

    try {
      final provider = Provider.of<BlControlProvider>(context, listen: false);
      final bl = provider.selectedBonLivraison;

      // Liste source (venant de l'écran précédent, potentiellement déjà filtrée par emplacement)
      final sourceList = widget.filteredItems ?? provider.items;
      // Application du filtre local (Contrôlé/Non contrôlé)
      final itemsToPrint = _getDisplayList(sourceList, provider.checkedQuantities);

      // Construction du titre du filtre pour le PDF
      String pdfFilterTitle = "${widget.filterName} - ";
      if (_currentFilter == 'TOUS') pdfFilterTitle += "Tout";
      if (_currentFilter == 'CONTROLE') pdfFilterTitle += "Contrôlés";
      if (_currentFilter == 'NON_CONTROLE') pdfFilterTitle += "Non Contrôlés";

      if (bl != null) {
        await PdfService().generateAndPrintBlReport(
            bl: bl,
            items: itemsToPrint,
            checkedQuantities: provider.checkedQuantities,
            filterTitle: pdfFilterTitle
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur lors de la génération du PDF: $e")),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingPdf = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rapport & Supervision'),
        actions: [
          _isGeneratingPdf
              ? const Padding(
            padding: EdgeInsets.all(12.0),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            ),
          )
              : IconButton(
            icon: const Icon(Icons.print),
            tooltip: "Imprimer la liste affichée",
            onPressed: () => _handlePrint(context),
          )
        ],
      ),
      body: Consumer<BlControlProvider>(
        builder: (context, provider, child) {
          final bl = provider.selectedBonLivraison;
          if (bl == null) {
            return const Center(child: Text("Aucun BL sélectionné."));
          }

          // 1. Liste de base (venant du filtre emplacement écran précédent)
          final baseItems = widget.filteredItems ?? provider.items;

          // 2. Liste affichée (après filtre Contrôlé/Pas Contrôlé)
          final displayItems = _getDisplayList(baseItems, provider.checkedQuantities);

          // Stats pour le header (sur la baseItems pour voir l'avancement global de la zone)
          int totalLines = baseItems.length;
          int completedLines = baseItems.where((i) => provider.checkedQuantities.containsKey(i.id)).length;

          return Column(
            children: [
              // Header Résumé
              Container(
                padding: const EdgeInsets.all(12),
                color: Colors.grey.shade100,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text('BL: ${bl.ref}', style: const TextStyle(fontWeight: FontWeight.bold))),
                        Expanded(child: Text('Fournisseur: ${bl.grossiste}', textAlign: TextAlign.end)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Barre de progression globale
                    LinearProgressIndicator(
                      value: totalLines > 0 ? completedLines / totalLines : 0,
                      backgroundColor: Colors.grey.shade300,
                      color: Colors.blue,
                    ),
                    const SizedBox(height: 4),
                    Text("$completedLines / $totalLines produits contrôlés dans cette zone"),
                  ],
                ),
              ),

              // Barre de Filtre
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  children: [
                    const Text("Afficher : ", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButton<String>(
                        value: _currentFilter,
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(value: 'TOUS', child: Text("Tout")),
                          DropdownMenuItem(value: 'CONTROLE', child: Text("Contrôlés uniquement")),
                          DropdownMenuItem(value: 'NON_CONTROLE', child: Text("Non Contrôlés uniquement")),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _currentFilter = val);
                        },
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Liste
              Expanded(
                child: displayItems.isEmpty
                    ? const Center(child: Text("Aucun produit ne correspond aux critères."))
                    : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: displayItems.length,
                  itemBuilder: (context, index) {
                    final item = displayItems[index];
                    final isControlled = provider.checkedQuantities.containsKey(item.id);
                    final checkedQty = provider.checkedQuantities[item.id] ?? 0;
                    final theoretical = item.stockTheorique;
                    final diff = checkedQty - theoretical;

                    // Définition des couleurs
                    Color? cardColor;
                    if (isControlled) {
                      // Vert si contrôlé
                      // Optionnel : Orange si contrôlé AVEC écart, mais vous avez demandé Vert pour contrôlé
                      cardColor = Colors.green.shade50;
                      if (diff != 0) {
                        // On peut nuancer légèrement si écart, ou garder vert.
                        // Gardons vert comme demandé, mais marquons l'écart en rouge texte
                        cardColor = Colors.green.shade100;
                      }
                    } else {
                      cardColor = Colors.white;
                    }

                    return Card(
                      color: cardColor,
                      elevation: 1,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        title: Text(
                          item.nomProduit,
                          style: TextStyle(
                              fontWeight: isControlled ? FontWeight.bold : FontWeight.normal
                          ),
                        ),
                        subtitle: Text('CIP: ${item.cip} | Zone: ${item.zoneGeoName}'),
                        trailing: isControlled
                            ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('Théo: $theoretical', style: const TextStyle(fontSize: 12)),
                            Text('Cpté: $checkedQty', style: const TextStyle(fontWeight: FontWeight.bold)),
                            if (diff != 0)
                              Text(
                                  '${diff > 0 ? '+' : ''}$diff',
                                  style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)
                              )
                          ],
                        )
                            : const Text("Non compté", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}