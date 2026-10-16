// lib/widgets/bouton_deconnexion.dart
// 4.4.0 — Bouton de déconnexion identique à celui de l'en-tête de Prestige web (Header.js « hdr-logout ») : rond
// ROUGE #E74C3C, icône « power off » blanche (Font Awesome fa-power-off ↔ Icons.power_settings_new), ombre rouge.
// Rond visible de 36 px, zone tactile de 48 × 48 dp.
import 'package:flutter/material.dart';

/// Rouge de Prestige web (#e74c3c).
const Color rougeDeconnexion = Color(0xFFE74C3C);

class BoutonDeconnexion extends StatelessWidget {
  final VoidCallback? onPressed;
  final String tooltip;
  final double taille;
  const BoutonDeconnexion({super.key, required this.onPressed, this.tooltip = 'Se déconnecter', this.taille = 36});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          label: tooltip,
          child: InkResponse(
            onTap: onPressed,
            radius: 26,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Center(child: PastilleDeconnexion(taille: taille)),
            ),
          ),
        ),
      );
}

/// Rond rouge + icône blanche (aussi utilisé dans les menus).
class PastilleDeconnexion extends StatelessWidget {
  final double taille;
  const PastilleDeconnexion({super.key, this.taille = 36});

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('pastille_deconnexion'),
        width: taille,
        height: taille,
        decoration: BoxDecoration(
          color: rougeDeconnexion,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: rougeDeconnexion.withValues(alpha: 0.45), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Icon(Icons.power_settings_new, color: Colors.white, size: taille * 0.5),
      );
}
