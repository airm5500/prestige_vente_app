// lib/interface_version.dart
// Interrupteur « Nouvel accueil et nouveaux réglages » (retour arrière sans réinstaller) :
// désactivé, l'écran d'accueil et la Configuration d'origine (inchangés) sont utilisés.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/accueil/accueil_screen.dart';
import 'package:prestige_vente_app/parametres/parametres_screen.dart';
import 'package:prestige_vente_app/screens/auth/settings_screen.dart';
import 'package:prestige_vente_app/screens/home/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class InterfaceVersion {
  InterfaceVersion._();

  static const _key = 'interface_nouvelle_version_v1';

  /// Version choisie (nouvelle par défaut).
  static final ValueNotifier<bool> useNew = ValueNotifier<bool>(true);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      useNew.value = prefs.getBool(_key) ?? true;
    } catch (_) {}
  }

  static Future<void> setNew(bool value) async {
    useNew.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, value);
    } catch (_) {}
  }

  static Widget home() => useNew.value ? const AccueilScreen() : const HomeScreen();

  static Widget settings() => useNew.value ? const ParametresScreen() : const SettingsScreen();
}

/// Réglage affiché dans la Configuration (ancienne et nouvelle).
class InterfaceVersionTile extends StatelessWidget {
  const InterfaceVersionTile({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: InterfaceVersion.useNew,
        builder: (context, isNew, _) => SwitchListTile(
          title: const Text('Nouvel accueil et nouveaux réglages'),
          subtitle: Text(isNew
              ? 'Désactivez pour revenir à l\'accueil et à la configuration d\'origine (effet au prochain retour à l\'accueil).'
              : 'Accueil et configuration d\'origine utilisés.'),
          value: isNew,
          onChanged: (v) => InterfaceVersion.setNew(v),
        ),
      );
}
