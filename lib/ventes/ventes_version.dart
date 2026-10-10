// lib/ventes/ventes_version.dart
// Interrupteur « Ventes : nouvelle / ancienne version » (Réglages).
// L'ancienne version = les écrans d'origine, laissés intacts, pour revenir en arrière
// en boutique sans réinstaller l'application.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/screens/assurance_sale/assurance_sale_screen.dart';
import 'package:prestige_vente_app/screens/carnet_sale/carnet_sale_screen.dart';
import 'package:prestige_vente_app/screens/pre_vente/pre_vente_screen.dart';
import 'package:prestige_vente_app/ventes/assurance/vente_assurance_screen.dart';
import 'package:prestige_vente_app/ventes/carnet/vente_carnet_screen.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VentesVersion {
  VentesVersion._();

  static const _key = 'ventes_nouvelle_version_v1';

  /// Version choisie (nouvelle par défaut). Mise à jour par [setNew].
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

  // --- Ouverture des menus selon la version choisie ---

  /// Pré-vente / vente. [resumeVenteId] : vente à afficher (ex. pré-vente créée depuis une ordonnance).
  static Widget preVente({int initialTabIndex = 0, String? resumeVenteId}) => useNew.value
      ? VenteScreen(initialTabIndex: initialTabIndex, resumeVenteId: resumeVenteId)
      : PreVenteScreen(initialTabIndex: initialTabIndex);

  static Widget assurance() => useNew.value ? const VenteAssuranceScreen() : const AssuranceSaleScreen();

  static Widget carnet() => useNew.value ? const VenteCarnetScreen() : const CarnetSaleScreen();
}

/// Réglage affiché dans l'écran Configuration.
class VentesVersionTile extends StatelessWidget {
  const VentesVersionTile({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: VentesVersion.useNew,
        builder: (context, isNew, _) => SwitchListTile(
          title: const Text('Ventes : nouvelle version'),
          subtitle: Text(isNew
              ? 'Pré-vente, Assurance et Carnet fiabilisés. Désactivez pour revenir à l\'ancienne version.'
              : 'Ancienne version des ventes utilisée (retour arrière).'),
          value: isNew,
          onChanged: (v) => VentesVersion.setNew(v),
        ),
      );
}
