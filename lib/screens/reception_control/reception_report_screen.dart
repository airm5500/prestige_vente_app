// lib/screens/reception_control/reception_report_screen.dart
import 'package:flutter/material.dart';
//import 'package:collection/collection.dart'; // Nécessaire pour le tri/groupement
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/api/models/reception_model.dart';
import 'package:prestige_vente_app/providers/reception_provider.dart';
import 'package:prestige_vente_app/services/pdf_service.dart';
//import 'package:prestige_vente_app/utils/constants.dart';

class ReceptionReportScreen extends StatefulWidget {
  const ReceptionReportScreen({super.key});

  @override
  State<ReceptionReportScreen> createState() => _ReceptionReportScreenState();
}

class _ReceptionReportScreenState extends State<ReceptionReportScreen> {
  String _selectedEmplacementFilter = "__GROUP_ALL__"; // Par défaut : Groupé
  String _selectedStatusFilter = "TOUS";
  bool _isGeneratingPdf = false;

  static const String _groupAllKey = "__GROUP_ALL__";
  static const String _noLocationKey = "__NO_LOC__";

  // Récupère la liste finale à afficher/imprimer selon les filtres
  List<ReceptionItem> _getFilteredItems(List<ReceptionItem> allItems, Map<String, int> checkedQuantities) {
    List<ReceptionItem> filtered = List.from(allItems);

    // 1. Filtre par Emplacement
    bool isGroupedMode = _selectedEmplacementFilter == _groupAllKey;

    if (!isGroupedMode) {
      if (_selectedEmplacementFilter == _noLocationKey) {
        filtered = filtered.where((i) => i.emplacement.isEmpty).toList();
      } else {
        filtered = filtered.where((i) => i.emplacement == _selectedEmplacementFilter).toList();
      }
    }

    // 2. Filtre par Statut
    if (_selectedStatusFilter != "TOUS") {
      filtered = filtered.where((item) {
        final int currentQty = checkedQuantities[item.id] ?? 0;
        final bool isControlled = currentQty > 0;
        final int ecart = currentQty - item.qteRecue;

        switch (_selectedStatusFilter) {
          case "CONTROLE":
            return isControlled;
          case "NON_CONTROLE":
            return !isControlled;
          case "ECART":
            return isControlled && ecart != 0;
          default:
            return true;
        }
      }).toList();
    }

    // 3. Tri pour l'affichage
    if (isGroupedMode) {
      // Tri par Emplacement puis par Nom pour le mode groupé
      filtered.sort((a, b) {
        int cmp = a.emplacement.compareTo(b.emplacement);
        if (cmp != 0) return cmp;
        return a.nomProduit.compareTo(b.nomProduit);
      });
    } else {
      // Tri par Nom simple
      filtered.sort((a, b) => a.nomProduit.compareTo(b.nomProduit));
    }

    return filtered;
  }

  Future<void> _handlePrint(BuildContext context) async {
    setState(() => _isGeneratingPdf = true);
    try {
      final provider = Provider.of<ReceptionProvider>(context, listen: false);
      final bon = provider.selectedBon;
      if (bon == null) return;

      final currentQuantities = provider.currentCheckedQuantities;
      final filteredSource = _getFilteredItems(bon.details, currentQuantities);

      // Préparation des items avec les quantités à jour pour le PDF
      final List<ReceptionItem> itemsToPrint = filteredSource.map((item) {
        final realQty = currentQuantities[item.id] ?? 0;
        return ReceptionItem(
          id: item.id,
          produitId: item.produitId,
          nomProduit: item.nomProduit,
          cip: item.cip,
          ean: item.ean,
          qteCommandee: item.qteCommandee,
          qteRecue: item.qteRecue,
          quantiteControle: realQty,
          prixAchat: item.prixAchat,
          prixVente: item.prixVente,
          emplacement: item.emplacement,
        );
      }).toList();

      String pdfFilterTitle = "";
      if (_selectedEmplacementFilter == _groupAllKey) {
        pdfFilterTitle = "Tous (Groupés)";
      } else if (_selectedEmplacementFilter == _noLocationKey) {
        pdfFilterTitle = "Sans Emplacement";
      } else {
        pdfFilterTitle = "Emplacement $_selectedEmplacementFilter";
      }

      if (_selectedStatusFilter != "TOUS") {
        pdfFilterTitle += " - $_selectedStatusFilter";
      }

      await PdfService().generateAndPrintReceptionReport(
        bon: bon,
        items: itemsToPrint,
        filterTitle: pdfFilterTitle,
      );

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur PDF: $e")));
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ReceptionProvider>(
      builder: (context, provider, child) {
        final bon = provider.selectedBon;
        if (bon == null) return const Scaffold(body: Center(child: Text("Aucun bon sélectionné")));

        // Liste des emplacements pour le Dropdown
        final Set<String> locations = bon.details.map((e) => e.emplacement).toSet();
        final List<String> sortedLocations = locations.where((e) => e.isNotEmpty).toList()..sort();
        final bool hasNoLocationItems = locations.contains('');

        final displayItems = _getFilteredItems(bon.details, provider.currentCheckedQuantities);
        final bool isGroupedMode = _selectedEmplacementFilter == _groupAllKey;

        final int totalLines = bon.details.length;
        final int controlledLines = provider.currentCheckedQuantities.values.where((q) => q > 0).length;

        return Scaffold(
          appBar: AppBar(
            title: const Text("Rapport & Supervision"),
            actions: [
              _isGeneratingPdf
                  ? const Padding(
                padding: EdgeInsets.all(12.0),
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
              )
                  : IconButton(
                icon: const Icon(Icons.print),
                tooltip: "Imprimer PDF",
                onPressed: () => _handlePrint(context),
              ),
            ],
          ),
          body: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(12),
                color: Colors.grey.shade100,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text('BL: ${bon.ref}', style: const TextStyle(fontWeight: FontWeight.bold))),
                        Expanded(child: Text(bon.grossiste, textAlign: TextAlign.end)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: totalLines > 0 ? controlledLines / totalLines : 0,
                      backgroundColor: Colors.grey.shade300,
                      color: Colors.blue,
                    ),
                    const SizedBox(height: 4),
                    Text("$controlledLines / $totalLines produits contrôlés (Global)"),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Filtres
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<String>(
                        value: _selectedEmplacementFilter,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Emplacement', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0)),
                        items: [
                          const DropdownMenuItem(value: _groupAllKey, child: Text("Tous (Groupés)", style: TextStyle(fontWeight: FontWeight.bold))),
                          if (hasNoLocationItems)
                            const DropdownMenuItem(value: _noLocationKey, child: Text("Sans Emplacement", style: TextStyle(fontStyle: FontStyle.italic))),
                          ...sortedLocations.map((loc) => DropdownMenuItem(value: loc, child: Text(loc))),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedEmplacementFilter = val);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        value: _selectedStatusFilter,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Statut', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0)),
                        items: const [
                          DropdownMenuItem(value: "TOUS", child: Text("Tous")),
                          DropdownMenuItem(value: "CONTROLE", child: Text("Contrôlés")),
                          DropdownMenuItem(value: "NON_CONTROLE", child: Text("Non Contrôlés")),
                          DropdownMenuItem(value: "ECART", child: Text("Écarts Only")),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedStatusFilter = val);
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // Liste
              Expanded(
                child: displayItems.isEmpty
                    ? const Center(child: Text("Aucun produit ne correspond aux critères."))
                    : ListView.builder(
                  itemCount: displayItems.length,
                  itemBuilder: (context, index) {
                    final item = displayItems[index];
                    final int checkedQty = provider.currentCheckedQuantities[item.id] ?? 0;

                    final bool isControlled = checkedQty > 0;
                    final int ecart = checkedQty - item.qteRecue;

                    // Gestion de l'entête de groupe (Si mode groupé activé)
                    bool showHeader = false;
                    if (isGroupedMode) {
                      if (index == 0) {
                        showHeader = true;
                      } else {
                        final prevItem = displayItems[index - 1];
                        String currentLoc = item.emplacement.isEmpty ? "Sans Emplacement" : item.emplacement;
                        String prevLoc = prevItem.emplacement.isEmpty ? "Sans Emplacement" : prevItem.emplacement;
                        if (currentLoc != prevLoc) showHeader = true;
                      }
                    }

                    Color cardColor = Colors.white;
                    if (isControlled) {
                      cardColor = (ecart == 0) ? Colors.green.shade50 : Colors.orange.shade50;
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showHeader)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            color: Colors.grey.shade200,
                            child: Text(
                              item.emplacement.isEmpty ? "Sans Emplacement" : item.emplacement,
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                            ),
                          ),
                        Card(
                          color: cardColor,
                          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          child: ListTile(
                            dense: true,
                            title: Text(item.nomProduit, style: TextStyle(fontWeight: isControlled ? FontWeight.bold : FontWeight.normal)),
                            subtitle: Text("CIP: ${item.cip} | Zone: ${item.emplacement.isEmpty ? '-' : item.emplacement}"),
                            trailing: SizedBox(
                              width: 100,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text("Reçu: ${item.qteRecue}", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                      Text("Cpté: ${isControlled ? checkedQty : '-'}", style: const TextStyle(fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                  if (ecart != 0 && isControlled)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 8.0),
                                      child: Text(
                                        "${ecart > 0 ? '+' : ''}$ecart",
                                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}