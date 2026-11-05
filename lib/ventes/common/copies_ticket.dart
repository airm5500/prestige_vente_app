// lib/ventes/common/copies_ticket.dart
// 4.10.3 — retour du pharmacien : avec 2 exemplaires ou plus, la nouvelle interface des ventes imprimait les tickets
// à la suite, sans laisser le temps de couper le premier. L'ancienne interface (ReceiptService, confirmEachCopy=true)
// demandait « Réimpression — Voulez-vous réimprimer le ticket ? (2/2) » avant chaque copie suivante ; cette pause a
// disparu le 10/10 (67922ef, « un seul dialogue d'impression avec le nombre de copies » : la pause a été supprimée en
// même temps que la question répétée) et la boucle du comptant (804693a) n'en a jamais eu.
// Règle commune à toutes les ventes de la nouvelle interface (comptant / différé, assurance, carnet, tickets
// provisoires hors ligne, aperçu du mode test) : copie 1 imprimée tout de suite ; avant CHAQUE copie suivante, un
// dialogue « Ticket suivant (i/N) — Coupez le ticket, puis imprimez le suivant. » [Arrêter] [Imprimer] (Imprimer par
// défaut) ; Arrêter (ou le retour Android) annule les copies restantes ; rien quand N = 1.
import 'package:flutter/material.dart';

/// Dialogue de pause avant la copie [numero] (2..[total]). true = imprimer ; false = arrêter.
Future<bool> confirmerTicketSuivant(BuildContext context, int numero, int total) async {
  final r = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      key: const ValueKey('ticket-suivant'),
      title: Text('Ticket suivant ($numero/$total)'),
      content: const Text('Coupez le ticket, puis imprimez le suivant.'),
      actions: [
        TextButton(
          key: const ValueKey('ticket-suivant-arreter'),
          style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Arrêter'),
        ),
        ElevatedButton(
          key: const ValueKey('ticket-suivant-imprimer'),
          autofocus: true,
          style: ElevatedButton.styleFrom(minimumSize: const Size(96, 48)),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Imprimer'),
        ),
      ],
    ),
  );
  return r == true;
}

/// Imprime [copies] exemplaires avec [imprimer] (une copie par appel), avec la pause avant chaque copie suivante.
/// Renvoie le nombre de copies imprimées.
Future<int> imprimerCopiesAvecPause(BuildContext context, int copies, Future<void> Function() imprimer) async {
  var faites = 0;
  for (var i = 0; i < copies; i++) {
    if (!context.mounted) break;
    if (i > 0 && !await confirmerTicketSuivant(context, i + 1, copies)) break;
    if (!context.mounted) break;
    await imprimer();
    faites++;
  }
  return faites;
}
