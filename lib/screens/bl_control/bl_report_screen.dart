// lib/screens/bl_control/bl_report_screen.dart
// Rapport du pointage d'un BL : contrôlés / écarts, impression de la liste affichée (présentations A, B, C).
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/bon_livraison_item.dart';
import 'package:prestige_vente_app/providers/bl_control_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/services/pdf_service.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';

class BlReportScreen extends StatefulWidget {
  final List<BonLivraisonItem>? filteredItems;
  final String filterName;

  /// Présentation (A, B, C) ; celle de l'appareil si non précisée.
  final ListPresentation? presentation;

  const BlReportScreen({
    super.key,
    this.filteredItems,
    this.filterName = "Tous",
    this.presentation,
  });

  @override
  State<BlReportScreen> createState() => _BlReportScreenState();
}

class _BlReportScreenState extends State<BlReportScreen> with PresentationAware {
  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  bool _isGeneratingPdf = false;
  String _currentFilter = 'TOUS'; // Options: TOUS, CONTROLE, NON_CONTROLE, AVEC_ECART, SANS_ECART

  static const _filters = {
    'TOUS': 'Tout',
    'CONTROLE': 'Contrôlés',
    'NON_CONTROLE': 'Non contrôlés',
    'AVEC_ECART': 'Avec écart',
    'SANS_ECART': 'Sans écart',
  };

  @override
  void initState() {
    super.initState();
    loadPresentation();
  }

  // Récupère la liste filtrée selon le choix de l'utilisateur
  List<BonLivraisonItem> _getDisplayList(List<BonLivraisonItem> sourceList, Map<String, int> checkedQuantities, String comparisonMode,
      [String? filter]) {
    switch (filter ?? _currentFilter) {
      case 'CONTROLE':
        return sourceList.where((item) => checkedQuantities.containsKey(item.id)).toList();
      case 'NON_CONTROLE':
        return sourceList.where((item) => !checkedQuantities.containsKey(item.id)).toList();
      case 'AVEC_ECART':
        return sourceList.where((item) {
          if (!checkedQuantities.containsKey(item.id)) return false;
          final checkedQty = checkedQuantities[item.id] ?? 0;
          final refStock = comparisonMode == 'machine' ? item.stockFinal : item.stockFinalTheorique;
          return checkedQty != refStock;
        }).toList();
      case 'SANS_ECART':
        return sourceList.where((item) {
          if (!checkedQuantities.containsKey(item.id)) return false;
          final checkedQty = checkedQuantities[item.id] ?? 0;
          final refStock = comparisonMode == 'machine' ? item.stockFinal : item.stockFinalTheorique;
          return checkedQty == refStock;
        }).toList();
      case 'TOUS':
      default:
        return sourceList;
    }
  }

  Future<void> _handlePrint(BuildContext context) async {
    if (_isGeneratingPdf) return; // pas de double impression
    setState(() {
      _isGeneratingPdf = true;
    });

    try {
      final provider = Provider.of<BlControlProvider>(context, listen: false);
      final settings = Provider.of<SettingsProvider>(context, listen: false);
      final bl = provider.selectedBonLivraison;

      // Liste source (venant de l'écran précédent, potentiellement déjà filtrée par emplacement)
      final sourceList = widget.filteredItems ?? provider.items;
      // Application du filtre local
      final itemsToPrint = _getDisplayList(sourceList, provider.checkedQuantities, settings.blStockComparisonMode);

      // Construction du titre du filtre pour le PDF
      String pdfFilterTitle = "${widget.filterName} - ";
      if (_currentFilter == 'TOUS') pdfFilterTitle += "Tout";
      if (_currentFilter == 'CONTROLE') pdfFilterTitle += "Contrôlés";
      if (_currentFilter == 'NON_CONTROLE') pdfFilterTitle += "Non Contrôlés";
      if (_currentFilter == 'AVEC_ECART') pdfFilterTitle += "Avec Écarts";
      if (_currentFilter == 'SANS_ECART') pdfFilterTitle += "Sans Écarts";

      if (bl != null) {
        await PdfService().generateAndPrintBlReport(
          bl: bl,
          items: itemsToPrint,
          checkedQuantities: provider.checkedQuantities,
          filterTitle: pdfFilterTitle,
          comparisonMode: settings.blStockComparisonMode, // Nouveau paramètre
        );
      }
    } catch (e) {
      if (mounted) {
        Constants.showSnackBar(this.context, "Erreur lors de la génération du PDF. Vérifiez l'imprimante et réessayez.", isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingPdf = false;
        });
      }
    }
  }

  void _setStyle(ListPresentation p) {
    setState(() => style = p);
    if (widget.presentation == null) PresentationPrefs.save(p);
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final comparisonMode = settings.blStockComparisonMode;

    return Consumer<BlControlProvider>(
      builder: (context, provider, child) {
        final bl = provider.selectedBonLivraison;
        if (bl == null) {
          return PresentationScaffold(
            style: style,
            title: 'Rapport & Supervision',
            actions: (_) => const [],
            body: const Center(child: Text("Aucun BL sélectionné.")),
          );
        }

        // 1. Liste de base (venant du filtre emplacement écran précédent)
        final baseItems = widget.filteredItems ?? provider.items;
        final checkedQuantities = provider.checkedQuantities;

        // 2. Liste affichée (après filtre Contrôlé/Pas Contrôlé/Ecarts)
        final displayItems = _getDisplayList(baseItems, checkedQuantities, comparisonMode);

        // Stats pour l'en-tête
        final counts = {for (final f in _filters.keys) f: _getDisplayList(baseItems, checkedQuantities, comparisonMode, f).length};
        final totalLines = baseItems.length;
        final completedLines = counts['CONTROLE'] ?? 0;
        final ecarts = counts['AVEC_ECART'] ?? 0;
        final compact = style == ListPresentation.compact;
        final progressText = "$completedLines / $totalLines produits contrôlés dans cette zone";

        return PresentationScaffold(
          style: style,
          title: 'Rapport & Supervision',
          subtitle: 'BL ${bl.ref.trim().isEmpty ? '—' : bl.ref} · ${bl.grossiste.trim().isEmpty ? '—' : bl.grossiste}',
          actions: (col) => [PresentationMenuButton(value: style, onChanged: _setStyle, color: col)],
          steps: const StepsBar(active: 2, steps: [
            (title: 'Choisir le BL', detail: 'liste', onTap: null),
            (title: 'Pointer', detail: 'scan, quantités', onTap: null),
            (title: 'Rapport', detail: 'écarts, impression', onTap: null),
          ]),
          header: [
            if (style == ListPresentation.dashboard)
              Row(children: [
                Expanded(child: KpiTile('$completedLines/$totalLines', 'contrôlés')),
                const SizedBox(width: 8),
                Expanded(child: KpiTile('$ecarts', 'avec écart', highlight: true)),
                const SizedBox(width: 8),
                Expanded(child: KpiTile('${counts['NON_CONTROLE'] ?? 0}', 'non comptés')),
              ]),
            _progress(completedLines, totalLines, progressText, dark: true),
          ],
          compactHeader: [
            LightFigures([
              ('$completedLines/$totalLines', 'Contrôlés', Pal.navy),
              ('$ecarts', 'Avec écart', AppColors.error),
              ('${counts['SANS_ECART'] ?? 0}', 'Conformes', Pal.green),
            ]),
            const SizedBox(height: 6),
            _progress(completedLines, totalLines, progressText, dark: false),
          ],
          body: Column(
            children: [
              // Filtres (Afficher : ...)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(spacing: 6, runSpacing: 0, children: [
                    for (final e in _filters.entries)
                      ChoiceChip(
                        label: Text('${e.value} (${counts[e.key] ?? 0})'),
                        selected: _currentFilter == e.key,
                        onSelected: (_) => setState(() => _currentFilter = e.key),
                      ),
                  ]),
                ),
              ),
              if (compact) const Divider(height: 1, color: Pal.line),
              Expanded(
                child: displayItems.isEmpty
                    ? ListView(children: const [
                        Padding(
                          padding: EdgeInsets.all(32),
                          child: Column(children: [
                            Icon(Icons.filter_alt_off_outlined, size: 48, color: Pal.muted),
                            SizedBox(height: 12),
                            Text("Aucun produit ne correspond aux critères.", textAlign: TextAlign.center),
                          ]),
                        ),
                      ])
                    : ListView.separated(
                        padding: compact ? const EdgeInsets.only(bottom: 16) : const EdgeInsets.fromLTRB(12, 6, 12, 16),
                        itemCount: displayItems.length,
                        separatorBuilder: (_, __) => SizedBox(height: compact ? 0 : 8),
                        itemBuilder: (context, index) => _row(displayItems[index], checkedQuantities, comparisonMode),
                      ),
              ),
            ],
          ),
          // Action principale : impression de la liste affichée.
          bottomNavigationBar: Container(
            decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Pal.line))),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: SizedBox(
                  height: 50,
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: style == ListPresentation.guided ? amberButton : navyButton,
                    icon: _isGeneratingPdf
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.print),
                    label: Text('Imprimer la liste affichée (${displayItems.length})'),
                    onPressed: _isGeneratingPdf || displayItems.isEmpty ? null : () => _handlePrint(context),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _progress(int done, int total, String text, {required bool dark}) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: dark ? Colors.white : Pal.muted)),
        ],
      );

  Widget _row(BonLivraisonItem item, Map<String, int> checkedQuantities, String comparisonMode) {
    final isControlled = checkedQuantities.containsKey(item.id);
    final checkedQty = checkedQuantities[item.id] ?? 0;

    // Calcul basé sur le paramètre choisi
    final refStock = comparisonMode == 'machine' ? item.stockFinal : item.stockFinalTheorique;
    final diff = checkedQty - refStock;
    final color = !isControlled ? const Color(0xFF8A99AD) : (diff == 0 ? Pal.green : AppColors.error);

    final trailing = isControlled
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${comparisonMode == 'machine' ? 'Mach.' : 'Théo.'}: $refStock', style: const TextStyle(fontSize: 12, color: Pal.muted)),
              Text('Cpté: $checkedQty', style: const TextStyle(fontWeight: FontWeight.bold, color: Pal.ink)),
              if (diff != 0)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                  decoration: BoxDecoration(color: const Color(0xFFFDE7E7), borderRadius: BorderRadius.circular(999)),
                  child: Text('${diff > 0 ? '+' : ''}$diff', style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
                ),
            ],
          )
        : const Text("Non compté", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic));

    final row = Row(children: [
      Icon(!isControlled ? Icons.radio_button_unchecked : (diff == 0 ? Icons.check_circle : Icons.error), color: color),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            item.nomProduit.trim().isEmpty ? '—' : item.nomProduit,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 15, color: Pal.ink, fontWeight: isControlled ? FontWeight.w600 : FontWeight.normal),
          ),
          Text('CIP: ${item.cip.trim().isEmpty ? '—' : item.cip} | Zone: ${item.zoneGeoName}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Pal.muted)),
        ]),
      ),
      const SizedBox(width: 8),
      trailing,
    ]);

    if (style == ListPresentation.compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isControlled && diff != 0 ? const Color(0xFFFFF7F7) : null,
          border: const Border(bottom: BorderSide(color: Color(0xFFEEF1F5))),
        ),
        child: row,
      );
    }
    return SoftCard(
      band: style == ListPresentation.guided ? color : null,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: row,
    );
  }
}
