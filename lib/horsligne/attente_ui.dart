// lib/horsligne/attente_ui.dart
// Attentes visibles et anti double-clic : un bouton dont l'action est en cours est DÉSACTIVÉ et
// affiche un indicateur animé (indéterminé uniquement pendant l'attente) ; un second appui est ignoré.
import 'package:flutter/material.dart';

/// Exécute une action à la fois : un appel pendant qu'une autre est en cours est ignoré (null).
class Verrou {
  bool _occupe = false;
  bool get occupe => _occupe;

  Future<T?> executer<T>(Future<T> Function() action) async {
    if (_occupe) return null;
    _occupe = true;
    try {
      return await action();
    } finally {
      _occupe = false;
    }
  }
}

/// Bouton icône d'une action longue (PDF, impression…) : désactivé et animé pendant l'action.
class IconActionOccupee extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final Future<void> Function()? onPressed;
  final Color? color;
  const IconActionOccupee({super.key, required this.icon, required this.tooltip, required this.onPressed, this.color});

  @override
  State<IconActionOccupee> createState() => _IconActionOccupeeState();
}

class _IconActionOccupeeState extends State<IconActionOccupee> {
  bool _occupe = false;

  Future<void> _run() async {
    final f = widget.onPressed;
    if (_occupe || f == null) return;
    setState(() => _occupe = true);
    try {
      await f();
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Animation seulement si l'écran est au premier plan (l'aperçu d'impression ouvert par-dessus
    // garde le bouton désactivé, sans animation inutile).
    final auPremierPlan = ModalRoute.of(context)?.isCurrent ?? true;
    return IconButton(
        tooltip: _occupe ? '${widget.tooltip} (en cours…)' : widget.tooltip,
        color: widget.color,
        onPressed: _occupe || widget.onPressed == null ? null : _run,
        icon: _occupe && auPremierPlan
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: widget.color ?? IconTheme.of(context).color),
              )
            : Icon(widget.icon),
      );
  }
}

/// Barre « chargement » d'un écran : animée pendant l'attente, absente ensuite.
class BarreChargement extends StatelessWidget {
  final bool visible;
  final double? valeur;
  const BarreChargement({super.key, required this.visible, this.valeur});

  @override
  Widget build(BuildContext context) => visible
      ? LinearProgressIndicator(key: const Key('barre_chargement'), value: valeur, minHeight: 3)
      : const SizedBox(height: 3);
}
