// lib/widgets/menu_button.dart
// 28/09/2025 17:32
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/utils/constants.dart';

class MenuButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  // MODIFICATION : Ajout d'un paramètre de couleur optionnel
  final Color? color;

  const MenuButton({
    Key? key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color, // Couleur optionnelle
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      // MODIFICATION : Utilise la couleur passée en paramètre, sinon blanc
      color: color ?? Colors.white,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: AppColors.primary),
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