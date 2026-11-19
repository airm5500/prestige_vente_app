// lib/parametres/largeur_ticket_reglage.dart
// 4.14.0 — « Largeur du ticket » (Réglages › Impression) : terminal à imprimante intégrée → largeur de l'imprimante,
// imposée (58 mm sur les terminaux Sunmi V2s) ; appareil sans imprimante intégrée (tablette) → 58 ou 80 mm, gardé
// sur l'appareil, appliqué au ticket suivant sans redémarrer. « Page de test » : la largeur choisie de bord à bord.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/parametres/parametres_widgets.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/services/largeur_ticket.dart';
import 'package:prestige_vente_app/services/receipt_service.dart';
import 'package:provider/provider.dart';

class ChoixLargeurTicket extends StatelessWidget {
  const ChoixLargeurTicket({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>();
    return FutureBuilder<int?>(
      future: LargeurTicket.integree(),
      initialData: LargeurTicket.integreeConnue,
      builder: (context, snap) {
        final imposee = snap.data;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (imposee != null)
            SettingCard(
              key: const ValueKey('largeur-ticket-imposee'),
              child: Text('$imposee mm, imposé par l\'imprimante intégrée du terminal.',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            )
          else
            Segmented<int>(
              key: const ValueKey('largeur-ticket-choix'),
              options: const [(58, '58 mm'), (80, '80 mm')],
              value: LargeurTicket.valide(s.paperWidth),
              onChanged: s.setPaperWidth,
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('largeur-ticket-page-test'),
              style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: () => ReceiptService().printPageTestLargeur(
                context: context,
                paperWidth: s.paperWidth,
                isTestMode: s.isTestPrintMode,
              ),
              icon: const Icon(Icons.straighten),
              label: const Text('Page de test de la largeur'),
            ),
          ),
        ]);
      },
    );
  }
}
