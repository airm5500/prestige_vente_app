// lib/widgets/pin_code_dialog.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PinCodeDialog {
  // Le code par défaut (si rien n'est configuré)
  static const String _defaultCode = "4123";

  static Future<bool> show(BuildContext context) async {
    final TextEditingController controller = TextEditingController();

    // On récupère le code stocké (ou celui par défaut)
    final prefs = await SharedPreferences.getInstance();
    final String correctCode = prefs.getString('admin_pin_code') ?? _defaultCode;

    return await showDialog<bool>(
      context: context,
      barrierDismissible: false, // Oblige à répondre ou annuler
      builder: (ctx) => AlertDialog(
        title: const Text("Accès Sécurisé"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Veuillez entrer le code administrateur pour accéder à ce menu."),
            const SizedBox(height: 15),
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true, // Cache le code (****)
              keyboardType: TextInputType.number,
              maxLength: 4, // Limite à 4 chiffres
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, letterSpacing: 5, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                hintText: "0000",
                counterText: "", // Cache le compteur 0/4
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false), // Annuler = Accès refusé
            child: const Text("Annuler"),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text == correctCode) {
                Navigator.pop(ctx, true); // Code bon = Accès autorisé
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Code incorrect !"), backgroundColor: Colors.red, duration: Duration(milliseconds: 500)),
                );
                controller.clear();
              }
            },
            child: const Text("Valider"),
          ),
        ],
      ),
    ) ?? false;
  }
}