// lib/utils/constants.dart
// 09/11/2025 03:00 (Gestion Erreur Caisse Fermée)
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/providers/caisse_provider.dart';
import 'package:provider/provider.dart';

class AppColors {
  static const Color primary = Color(0xFF003366);
  static const Color secondary = Color(0xFF4A90E2);
  static const Color background = Color(0xFFF5F5F7);
  static const Color textLight = Colors.white;
  static const Color textDark = Colors.black87;
  static const Color success = Colors.green;
  static const Color error = Colors.red;
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      primaryColor: AppColors.primary,
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textLight,
        elevation: 4.0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.secondary,
          foregroundColor: AppColors.textLight,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.0),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.0),
          borderSide: const BorderSide(color: Colors.grey),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.0),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
        filled: true,
        fillColor: Colors.white,
      ),
      cardTheme: CardThemeData(
        elevation: 2.0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10.0),
        ),
      ),
    );
  }
}

class Constants {
  static void showSnackBar(BuildContext context, String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.secondary,
        duration: const Duration(seconds: 2), // Remis à 2s pour les erreurs
      ),
    );
  }

  static String formatNumber(num value) {
    final formatter = NumberFormat("#,##0", "fr_FR");
    return formatter.format(value);
  }

  // MODIFICATION : Ajout de la fonction de vérification de caisse
  /// Vérifie si une réponse API indique que la caisse est fermée
  /// et propose à l'utilisateur de l'ouvrir.
  ///
  /// Renvoie `true` si l'erreur "caisse fermée" a été détectée et gérée.
  /// Renvoie `false` s'il n'y avait pas d'erreur ou si c'était une autre erreur.
  static Future<bool> checkAndOpenCaisse(BuildContext context, Map<String, dynamic> apiResult) async {

    // 1. Vérifie si l'erreur est la bonne
    if (apiResult['success'] == false && (apiResult['msg'] as String? ?? '').contains("caisse est fermée")) {

      // 2. Propose à l'utilisateur d'ouvrir la caisse
      final bool? openCaisse = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Caisse Fermée'),
          content: const Text("Votre caisse est fermée. Voulez-vous l'ouvrir maintenant (Fond de caisse 0) ?"),
          actions: [
            TextButton(
              child: const Text('Non'),
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
            ElevatedButton(
              child: const Text('Oui, Ouvrir'),
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ],
        ),
      );

      // 3. Si l'utilisateur clique "Oui"
      if (openCaisse == true) {
        final caisseProvider = Provider.of<CaisseProvider>(context, listen: false);
        // Affiche un indicateur de chargement
        showDialog(context: context, barrierDismissible: false, builder: (ctx) => const AlertDialog(content: Row(children: [CircularProgressIndicator(), SizedBox(width: 16), Text("Ouverture...")])));

        final success = await caisseProvider.ouvrirCaisse();

        Navigator.of(context).pop(); // Ferme l'indicateur

        if (success) {
          Constants.showSnackBar(context, "Caisse ouverte. Veuillez valider la vente à nouveau.");
        } else {
          Constants.showSnackBar(context, caisseProvider.errorMessage ?? "Échec de l'ouverture de la caisse.", isError: true);
        }
      }
      return true; // L'erreur a été gérée
    }

    return false; // Pas d'erreur "caisse fermée"
  }
// FIN MODIFICATION
}