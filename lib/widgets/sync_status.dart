// lib/widgets/sync_status.dart
// Bandeaux communs : échec de chargement (≠ liste vide) et quantités non enregistrées sur le serveur.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/providers/quantity_sync.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

/// Échec de chargement : message clair et bouton « Réessayer ».
class LoadErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const LoadErrorBanner({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFDECEC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF5C2C2)),
        ),
        child: Row(children: [
          Icon(Icons.cloud_off, color: Colors.red.shade700),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: TextStyle(color: Colors.red.shade900, fontSize: 13))),
          if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Réessayer')),
        ]),
      );
}

/// Écran entier quand rien n'a pu être chargé (au lieu de « aucun résultat »).
class LoadErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const LoadErrorView({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off, size: 56, color: Colors.red.shade400),
            const SizedBox(height: 12),
            const Text('Chargement impossible', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Pal.ink)),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Pal.muted)),
            const SizedBox(height: 16),
            ElevatedButton.icon(style: navyButton, onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Réessayer')),
          ]),
        ),
      );
}

/// Quantités saisies mais pas encore enregistrées sur le serveur.
class UnsyncedBanner extends StatelessWidget {
  final int count;
  final bool retrying;
  final VoidCallback onRetry;
  const UnsyncedBanner({super.key, required this.count, required this.retrying, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF5D08A)),
      ),
      child: Row(children: [
        Icon(Icons.sync_problem, color: Colors.orange.shade900),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            count == 1
                ? '1 quantité non enregistrée sur le serveur.'
                : '$count quantités non enregistrées sur le serveur.',
            style: TextStyle(color: Colors.orange.shade900, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        retrying
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : TextButton(onPressed: onRetry, child: const Text('Réessayer')),
      ]),
    );
  }
}

/// Petite marque sur une ligne dont la quantité n'est pas (encore) enregistrée.
class LineSyncMark extends StatelessWidget {
  final bool unsynced;
  final bool sending;
  const LineSyncMark({super.key, required this.unsynced, required this.sending});

  @override
  Widget build(BuildContext context) {
    if (sending) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (!unsynced) return const SizedBox.shrink();
    return Tooltip(
      message: 'Non enregistrée sur le serveur',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Icon(Icons.sync_problem, size: 18, color: Colors.orange.shade800),
      ),
    );
  }
}

/// Avant de quitter un écran : attend les envois en cours puis, s'il reste des quantités non
/// enregistrées, propose de réessayer, rester ou quitter. Renvoie `true` si l'on peut quitter.
/// Message après un envoi refusé.
void showUnsyncedSnack(BuildContext context) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    backgroundColor: Colors.orange.shade900,
    content: const Text('Quantité non enregistrée sur le serveur (réseau ou serveur indisponible). Touchez « Réessayer ».'),
  ));
}

Future<bool> confirmLeaveWithUnsynced(BuildContext context, QuantitySync sync, Future<int> Function() retry) async {
  await sync.waitForPendingSends();
  if (!context.mounted) return false;
  final count = sync.unsyncedCount;
  if (count == 0) return true;
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Quantités non enregistrées'),
      content: Text(
        count == 1
            ? '1 quantité n\'a pas été enregistrée sur le serveur (réseau ou serveur indisponible). '
                'Elle sera perdue si vous quittez sans réessayer.'
            : '$count quantités n\'ont pas été enregistrées sur le serveur (réseau ou serveur indisponible). '
                'Elles seront perdues si vous quittez sans réessayer.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop('leave'), child: const Text('Quitter quand même')),
        TextButton(onPressed: () => Navigator.of(ctx).pop('stay'), child: const Text('Rester')),
        ElevatedButton(onPressed: () => Navigator.of(ctx).pop('retry'), child: const Text('Réessayer')),
      ],
    ),
  );
  if (choice == 'leave') return true;
  if (choice != 'retry') return false;
  final left = await retry();
  if (left == 0) return true;
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: Colors.red.shade700,
      content: Text('$left quantité(s) toujours non enregistrée(s). Vérifiez le réseau.'),
    ));
  }
  return false;
}
