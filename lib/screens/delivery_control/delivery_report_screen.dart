// lib/screens/delivery_control/delivery_report_screen.dart
// 16/10/2025 10:45
// 10/10/2026 : présentations A/B/C, chiffres clés (manquants, excédents, valeur des écarts).
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/providers/delivery_control_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';

class DeliveryReportScreen extends StatefulWidget {
  /// Présentation reçue de l'écran de contrôle ; sinon celle choisie sur l'appareil.
  final ListPresentation? presentation;
  const DeliveryReportScreen({super.key, this.presentation});

  @override
  State<DeliveryReportScreen> createState() => _DeliveryReportScreenState();
}

class _DeliveryReportScreenState extends State<DeliveryReportScreen> with PresentationAware {
  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  @override
  void initState() {
    super.initState();
    loadPresentation();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DeliveryControlProvider>(
      builder: (context, provider, child) {
        final commande = provider.selectedCommande;
        if (commande == null) {
          return PresentationScaffold(
            style: style,
            title: 'Rapport de Contrôle',
            actions: (_) => const [],
            body: const Center(child: Text("Aucune commande sélectionnée.")),
          );
        }

        final itemsWithDiscrepancy = provider.items.where((item) {
          final checkedQty = provider.checkedQuantities[item.id] ?? 0;
          return item.qteCommandee != checkedQty;
        }).toList();

        var missing = 0, extra = 0, value = 0;
        for (final item in itemsWithDiscrepancy) {
          final diff = (provider.checkedQuantities[item.id] ?? 0) - item.qteCommandee;
          if (diff < 0) missing += -diff;
          if (diff > 0) extra += diff;
          value += diff * item.prixAchat;
        }
        final compact = style == ListPresentation.compact;
        final guided = style == ListPresentation.guided;
        final valueText = '${value > 0 ? '+' : ''}${Constants.formatNumber(value)}';

        return PresentationScaffold(
          style: style,
          title: 'Rapport de Contrôle',
          subtitle: 'Commande: ${commande.ref}',
          actions: (_) => const [],
          steps: const StepsBar(active: 2, steps: [
            (title: 'Commande', detail: 'choisie', onTap: null),
            (title: 'Contrôle', detail: 'terminé', onTap: null),
            (title: 'Rapport', detail: 'écarts', onTap: null),
          ]),
          header: [
            Row(children: [
              Expanded(child: KpiTile('${itemsWithDiscrepancy.length}', 'anomalie(s)', highlight: itemsWithDiscrepancy.isNotEmpty)),
              const SizedBox(width: 6),
              Expanded(child: KpiTile('$missing', 'manquant(s)')),
              const SizedBox(width: 6),
              Expanded(child: KpiTile('$extra', 'excédent(s)')),
            ]),
          ],
          compactHeader: [
            LightFigures([
              ('${itemsWithDiscrepancy.length}', 'Anomalies', itemsWithDiscrepancy.isEmpty ? Pal.green : AppColors.error),
              ('$missing', 'Manquants', Pal.navy),
              ('$extra', 'Excédents', Pal.navy),
            ]),
          ],
          body: ListView(
            padding: EdgeInsets.fromLTRB(compact ? 0 : 12, 12, compact ? 0 : 12, 24),
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Fournisseur: ${commande.grossiste.trim().isEmpty ? '—' : commande.grossiste}',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Pal.ink)),
                  Text('${provider.items.length} produit(s) contrôlé(s) · valeur des écarts (PA) : $valueText',
                      style: const TextStyle(fontSize: 13, color: Pal.muted)),
                ]),
              ),
              const SizedBox(height: 12),
              if (itemsWithDiscrepancy.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(Icons.check_circle_outline, color: AppColors.success, size: 60),
                      SizedBox(height: 16),
                      Text("Aucune anomalie détectée.", textAlign: TextAlign.center, style: TextStyle(fontSize: 18)),
                      Text("Toutes les quantités reçues correspondent à la commande.", textAlign: TextAlign.center),
                    ],
                  ),
                )
              else ...[
                Padding(
                  padding: EdgeInsets.fromLTRB(compact ? 16 : 4, 0, 16, 8),
                  child: const Text("Anomalies détectées :", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Pal.ink)),
                ),
                for (final item in itemsWithDiscrepancy)
                  _line(provider, item.id, item.nomProduit, item.cip, item.prixAchat, item.qteCommandee, compact, guided),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _line(DeliveryControlProvider provider, String id, String name, String cip, int pa, int ordered, bool compact, bool guided) {
    final checkedQty = provider.checkedQuantities[id] ?? 0;
    final difference = checkedQty - ordered;
    final color = difference < 0 ? AppColors.error : Colors.orange.shade800;
    final content = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name.trim().isEmpty ? '—' : name,
              maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Pal.ink)),
          // CIP et Prix d'Achat (PA)
          Text('CIP: ${cip.trim().isEmpty ? '—' : cip} | PA: ${Constants.formatNumber(pa)}', style: const TextStyle(fontSize: 13, color: Pal.muted)),
        ]),
      ),
      const SizedBox(width: 8),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('Commandé: $ordered', style: const TextStyle(fontSize: 13)),
        Text('Reçu: $checkedQty', style: const TextStyle(fontSize: 13)),
        Text('Écart: ${difference > 0 ? '+' : ''}$difference', style: TextStyle(fontWeight: FontWeight.bold, color: color)),
      ]),
    ]);
    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEF1F5)))),
        child: content,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SoftCard(band: guided ? color : null, padding: const EdgeInsets.all(12), child: content),
    );
  }
}
