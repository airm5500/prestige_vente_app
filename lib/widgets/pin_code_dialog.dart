// lib/widgets/pin_code_dialog.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PinCodeDialog {
  // Le code par défaut
  static const String _defaultCode = "1234";

  // Méthode 1 : VÉRIFIER le code (pour accéder à un menu)
  static Future<bool> show(BuildContext context) async {
    final TextEditingController controller = TextEditingController();
    final prefs = await SharedPreferences.getInstance();
    final String correctCode = prefs.getString('admin_pin_code') ?? _defaultCode;

    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Accès Sécurisé"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Code Administrateur requis :"),
            const SizedBox(height: 15),
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, letterSpacing: 5, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(hintText: "****", counterText: "", border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () {
              if (controller.text == correctCode) {
                Navigator.pop(ctx, true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Code incorrect"), backgroundColor: Colors.red));
                controller.clear();
              }
            },
            child: const Text("Valider"),
          ),
        ],
      ),
    ) ?? false;
  }

  // Méthode 2 : CHANGER le code (pour l'admin) - C'est celle qui manquait
  static Future<void> changePin(BuildContext context) async {
    final TextEditingController controller = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Nouveau Code PIN"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Définir le nouveau code (4 chiffres) :"),
            const SizedBox(height: 15),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, letterSpacing: 5, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(hintText: "0000", counterText: "", border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.length == 4) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('admin_pin_code', controller.text);
                if (context.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Code PIN modifié avec succès"), backgroundColor: Colors.green));
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Le code doit faire 4 chiffres"), backgroundColor: Colors.orange));
              }
            },
            child: const Text("Enregistrer"),
          ),
        ],
      ),
    );
  }
}