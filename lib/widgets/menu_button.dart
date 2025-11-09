// lib/widgets/menu_button.dart
// 18/10/2025 20:00
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/utils/constants.dart';

class MenuButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  // MODIFICATION : La couleur s'applique maintenant à l'icône, pas au fond
  final Color color;

  const MenuButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = AppColors.primary, // Couleur par défaut si non fournie
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      // Le fond est maintenant blanc (ou la couleur par défaut du CardTheme)
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // L'icône prend la couleur
            Icon(icon, size: 48, color: color),
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}