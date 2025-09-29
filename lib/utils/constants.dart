// lib/utils/constants.dart
// 29/09/2025 02:10
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
        // MODIFICATION : Durée d'affichage réduite à 2 secondes
        duration: const Duration(seconds: 1),
      ),
    );
  }

  static String formatNumber(num value) {
    final formatter = NumberFormat("#,##0", "fr_FR");
    return formatter.format(value);
  }
}