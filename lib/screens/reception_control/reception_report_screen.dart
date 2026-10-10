// lib/screens/reception_control/reception_report_screen.dart
// Contrôle Réception : rapport et supervision d'un bon (filtres, écarts, impression PDF).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/api/models/reception_model.dart';
import 'package:prestige_vente_app/providers/reception_provider.dart';
import 'package:prestige_vente_app/services/pdf_service.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

/// Impression du rapport (remplaçable pour les tests).
typedef ReceptionReportPrinter = Future<void> Function({
  required ReceptionBon bon,
  required List<ReceptionItem> items,
  required String filterTitle,
});

class ReceptionReportScreen extends StatefulWidget {
  /// Présentation reçue de l'écran de comptage ; celle de l'appareil si non précisée.
  final ListPresentation? presentation;

  /// Impression PDF ; par défaut PdfService.
  final ReceptionReportPrinter? printer;

  const ReceptionReportScreen({super.key, this.presentation, this.printer});

  @override
  State<ReceptionReportScreen> createState() => _ReceptionReportScreenState();
}

class _ReceptionReportScreenState extends State<ReceptionReportScreen> with PresentationAware {
  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  String _selectedEmplacementFilter = "__GROUP_ALL__"; // Par défaut : Groupé
  String _selectedStatusFilter = "TOUS";
  bool _isGeneratingPdf = false;

  static const String _groupAllKey = "__GROUP_ALL__";
  static const String _noLocationKey = "__NO_LOC__";

  @override
  void initState() {
    super.initState();
    loadPresentation();
  }

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

  Future<void> _handlePrint() async {
    if (_isGeneratingPdf) return; // pas de double impression
    setState(() => _isGeneratingPdf = true);
    try {
      final provider = Provider.of<ReceptionProvider>(context, listen: false);
      final bon = provider.selectedBon;
      if (bon == null) return;

      final currentQuantities = provider.currentCheckedQuantities;
      final filteredSource = _getFilteredItems(bon.details, currentQuantities);
      if (filteredSource.isEmpty) {
        _snack('Rien à imprimer avec ces filtres.');
        return;
      }

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

      final printer = widget.printer ?? PdfService().generateAndPrintReceptionReport;
      await printer(bon: bon, items: itemsToPrint, filterTitle: pdfFilterTitle);
    } catch (e) {
      _snack("Impression impossible : vérifiez l'imprimante puis réessayez.", error: true);
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), backgroundColor: error ? Colors.red.shade700 : null));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ReceptionProvider>(
      builder: (context, provider, child) {
        final bon = provider.selectedBon;
        if (bon == null) {
          return Scaffold(
            appBar: AppBar(title: const Text("Rapport & Supervision")),
            body: const Center(child: Text("Aucun bon sélectionné")),
          );
        }

        final q = provider.currentCheckedQuantities;
        final displayItems = _getFilteredItems(bon.details, q);
        final bool isGroupedMode = _selectedEmplacementFilter == _groupAllKey;

        final int totalLines = bon.details.length;
        final int controlledLines = bon.details.where((i) => (q[i.id] ?? 0) > 0).length;
        final int gapLines = bon.details.where((i) => (q[i.id] ?? 0) > 0 && (q[i.id] ?? 0) != i.qteRecue).length;
        final dark = style != ListPresentation.compact;

        return PresentationScaffold(
          style: style,
          title: "Rapport & Supervision",
          subtitle: 'BL ${bon.ref.isEmpty ? '—' : bon.ref}${bon.grossiste.isEmpty ? '' : ' · ${bon.grossiste}'}',
          actions: (col) => [
            _isGeneratingPdf
                ? Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: col, strokeWidth: 2)),
                  )
                : IconButton(icon: Icon(Icons.print, color: col), tooltip: "Imprimer PDF", onPressed: _handlePrint),
          ],
          steps: StepsBar(active: 2, steps: [
            (title: 'Bons', detail: 'liste', onTap: null),
            (title: 'Comptage', detail: '$controlledLines/$totalLines', onTap: () => Navigator.of(context).maybePop()),
            (title: 'Rapport', detail: '$gapLines écart(s)', onTap: null),
          ]),
          header: [
            if (style == ListPresentation.dashboard)
              Row(children: [
                Expanded(child: KpiTile('$controlledLines/$totalLines', 'contrôlés')),
                const SizedBox(width: 8),
                Expanded(child: KpiTile('$gapLines', 'écart(s)', highlight: gapLines > 0)),
                const SizedBox(width: 8),
                Expanded(child: KpiTile('${totalLines - controlledLines}', 'non contrôlés')),
              ]),
            _progress(controlledLines, totalLines, dark: dark),
          ],
          compactHeader: [
            LightFigures([
              ('$controlledLines', 'Contrôlés', Pal.green),
              ('$gapLines', 'Écarts', Colors.red.shade700),
              ('${totalLines - controlledLines}', 'Non contrôlés', Pal.navy),
            ]),
            _progress(controlledLines, totalLines, dark: false),
          ],
          body: Column(children: [
            _filters(bon),
            Expanded(
              child: displayItems.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 32),
                      const Icon(Icons.filter_alt_off, size: 52, color: Pal.muted),
                      const SizedBox(height: 10),
                      const Text("Aucun produit ne correspond aux critères.", textAlign: TextAlign.center, style: TextStyle(color: Pal.ink)),
                      const SizedBox(height: 10),
                      Center(
                        child: OutlinedButton(
                          style: outlineButton,
                          onPressed: () => setState(() {
                            _selectedEmplacementFilter = _groupAllKey;
                            _selectedStatusFilter = 'TOUS';
                          }),
                          child: const Text('Réinitialiser les filtres'),
                        ),
                      ),
                    ])
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(dark ? 12 : 0, 4, dark ? 12 : 0, 16),
                      itemCount: displayItems.length,
                      itemBuilder: (context, index) {
                        final item = displayItems[index];
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
                        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          if (showHeader) _groupHeader(item.emplacement.isEmpty ? "Sans Emplacement" : item.emplacement),
                          _row(item, q[item.id] ?? 0),
                          if (dark) const SizedBox(height: 6),
                        ]);
                      },
                    ),
            ),
          ]),
          // Action principale fixée en bas : impression du rapport filtré.
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  style: style == ListPresentation.guided ? amberButton : navyButton,
                  icon: _isGeneratingPdf
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.print),
                  label: Text(_isGeneratingPdf ? 'Impression…' : 'Imprimer PDF (${displayItems.length})'),
                  onPressed: _isGeneratingPdf || displayItems.isEmpty ? null : _handlePrint,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _progress(int done, int total, {required bool dark}) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: total > 0 ? done / total : 0,
            minHeight: 8,
            backgroundColor: dark ? Colors.white.withValues(alpha: 0.2) : const Color(0xFFE6EBF2),
            color: dark ? Pal.amber : Pal.blue,
          ),
        ),
        const SizedBox(height: 4),
        Text("$done / $total produits contrôlés (Global)", style: TextStyle(fontSize: 12, color: dark ? Colors.white : Pal.ink)),
      ]);

  Widget _filters(ReceptionBon bon) {
    // Liste des emplacements pour le Dropdown
    final Set<String> locations = bon.details.map((e) => e.emplacement).toSet();
    final List<String> sortedLocations = locations.where((e) => e.isNotEmpty).toList()..sort();
    final bool hasNoLocationItems = locations.contains('');
    // Filtre devenu invalide (données rechargées) : retour au mode groupé.
    if (_selectedEmplacementFilter != _groupAllKey &&
        !(_selectedEmplacementFilter == _noLocationKey ? hasNoLocationItems : sortedLocations.contains(_selectedEmplacementFilter))) {
      _selectedEmplacementFilter = _groupAllKey;
    }
    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFC5D0DE))),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(children: [
        Expanded(
          flex: 3,
          child: DropdownButtonFormField<String>(
            value: _selectedEmplacementFilter,
            isExpanded: true,
            decoration: deco('Emplacement'),
            items: [
              const DropdownMenuItem(value: _groupAllKey, child: Text("Tous (Groupés)", overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.bold))),
              if (hasNoLocationItems)
                const DropdownMenuItem(value: _noLocationKey, child: Text("Sans Emplacement", overflow: TextOverflow.ellipsis, style: TextStyle(fontStyle: FontStyle.italic))),
              ...sortedLocations.map((loc) => DropdownMenuItem(value: loc, child: Text(loc, overflow: TextOverflow.ellipsis))),
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
            decoration: deco('Statut'),
            items: const [
              DropdownMenuItem(value: "TOUS", child: Text("Tous")),
              DropdownMenuItem(value: "CONTROLE", child: Text("Contrôlés", overflow: TextOverflow.ellipsis)),
              DropdownMenuItem(value: "NON_CONTROLE", child: Text("Non contrôlés", overflow: TextOverflow.ellipsis)),
              DropdownMenuItem(value: "ECART", child: Text("Écarts", overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (val) {
              if (val != null) setState(() => _selectedStatusFilter = val);
            },
          ),
        ),
      ]),
    );
  }

  Widget _groupHeader(String name) => style == ListPresentation.compact
      ? Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: const Color(0xFFF1F4F8),
          child: Text(name.toUpperCase(),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: Color(0xFF4A5A70))),
        )
      : Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
          child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, color: Pal.navy)),
        );

  Widget _row(ReceptionItem item, int checkedQty) {
    final bool isControlled = checkedQty > 0;
    final int ecart = checkedQty - item.qteRecue;
    final color = !isControlled ? const Color(0xFF6B7A90) : (ecart == 0 ? Pal.green : const Color(0xFFB45309));

    final row = Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.nomProduit.isEmpty ? '—' : item.nomProduit,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: Pal.ink, fontWeight: isControlled ? FontWeight.bold : FontWeight.normal)),
          Text("CIP: ${item.cip.isEmpty ? '—' : item.cip} | Zone: ${item.emplacement.isEmpty ? '-' : item.emplacement}",
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Pal.muted)),
        ]),
      ),
      const SizedBox(width: 8),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text("Reçu: ${item.qteRecue}", style: const TextStyle(fontSize: 11, color: Pal.muted)),
        Text("Cpté: ${isControlled ? checkedQty : '-'}", style: TextStyle(fontWeight: FontWeight.bold, color: color)),
      ]),
      SizedBox(
        width: 48,
        child: ecart != 0 && isControlled
            ? Text("${ecart > 0 ? '+' : ''}$ecart",
                textAlign: TextAlign.end, maxLines: 1, style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold))
            : null,
      ),
    ]);

    return switch (style) {
      ListPresentation.compact => Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isControlled ? (ecart == 0 ? const Color(0xFFF2FBF5) : const Color(0xFFFFF8EC)) : null,
            border: const Border(bottom: BorderSide(color: Color(0xFFEEF1F5))),
          ),
          child: row,
        ),
      ListPresentation.guided => SoftCard(band: color, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: row),
      ListPresentation.dashboard => SoftCard(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: row),
    };
  }
}
