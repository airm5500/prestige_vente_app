// lib/ventes/prevente/prevente_dialogs.dart
// Fenêtres de la Pré-vente / Vente au style des maquettes : « Reprendre la vente ? » et
// « Un panier est en cours » (boutons pleine largeur, libellés explicites).
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

/// Choix devant un panier non terminé.
enum PanierEnCoursChoice {
  /// Enregistrer le panier en prévente (terminerprevente) puis continuer.
  enregistrer,

  /// Garder le panier et y revenir (rien ne change).
  garder,

  /// Continuer sans l'enregistrer (le panier reste sur le serveur, non encaissé).
  abandonner,
}

String panierLabel({required String reference, required int itemCount, required int total}) =>
    '${reference.isEmpty ? 'Vente en cours' : reference} ($itemCount article${itemCount > 1 ? 's' : ''}'
    '${total > 0 ? ', ${Constants.formatNumber(total)} F' : ''})';

/// Cadre commun : titre, texte, boutons empilés pleine largeur (≥ 48 px).
class _ChoiceDialog extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;
  final List<Widget> buttons;
  const _ChoiceDialog({required this.title, required this.message, required this.icon, required this.buttons});

  @override
  Widget build(BuildContext context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(icon, color: Pal.navy),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Pal.ink))),
            ]),
            const SizedBox(height: 10),
            Text(message, style: const TextStyle(fontSize: 14, color: Pal.muted, height: 1.35)),
            const SizedBox(height: 16),
            for (final b in buttons) Padding(padding: const EdgeInsets.only(top: 8), child: SizedBox(height: 48, child: b)),
          ]),
        ),
      );
}

/// « Reprendre la vente ? » (true = REPRENDRE, false = PLUS TARD).
Future<bool> showReprendreVenteDialog(BuildContext context,
    {required String reference, required int itemCount, required int total, DateTime? savedAt}) async {
  final when = savedAt == null ? '' : ' (${DateFormat('dd/MM/yyyy HH:mm').format(savedAt)})';
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ChoiceDialog(
      title: 'Reprendre la vente ?',
      icon: Icons.history,
      message: 'La vente ${panierLabel(reference: reference, itemCount: itemCount, total: total)} '
          'n\'a pas été terminée lors de la dernière utilisation$when.',
      buttons: [
        ElevatedButton(
          key: const ValueKey('vente-reprendre'),
          style: navyButton,
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('REPRENDRE'),
        ),
        OutlinedButton(
          style: outlineButton,
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('PLUS TARD', maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    ),
  );
  return ok == true;
}

/// « Un panier est en cours » avant d'ouvrir autre chose ([action] : « ouvrir PV-000118 », …).
Future<PanierEnCoursChoice> showPanierEnCoursDialog(BuildContext context,
    {required String panier, required String action, required String abandonLabel}) async {
  final r = await showDialog<PanierEnCoursChoice>(
    context: context,
    builder: (ctx) => _ChoiceDialog(
      title: 'Un panier est en cours',
      icon: Icons.shopping_cart_outlined,
      message: '$panier n\'est pas terminée. Que faire avant de $action ?\n\n'
          'Sans l\'enregistrer, elle reste sur le serveur, non encaissée, hors de la liste des préventes.',
      buttons: [
        ElevatedButton(
          key: const ValueKey('panier-enregistrer'),
          style: navyButton,
          onPressed: () => Navigator.pop(ctx, PanierEnCoursChoice.enregistrer),
          child: const FittedBox(fit: BoxFit.scaleDown, child: Text('L\'ENREGISTRER EN PRÉVENTE')),
        ),
        OutlinedButton(
          key: const ValueKey('panier-garder'),
          style: outlineButton,
          onPressed: () => Navigator.pop(ctx, PanierEnCoursChoice.garder),
          child: const FittedBox(fit: BoxFit.scaleDown, child: Text('LA GARDER ET REVENIR')),
        ),
        TextButton(
          key: const ValueKey('panier-abandonner'),
          style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
          onPressed: () => Navigator.pop(ctx, PanierEnCoursChoice.abandonner),
          child: FittedBox(fit: BoxFit.scaleDown, child: Text(abandonLabel)),
        ),
      ],
    ),
  );
  return r ?? PanierEnCoursChoice.garder;
}
