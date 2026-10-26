// lib/prestigepointage/lanceur_pointage.dart
// Prestige Mobile 4.10.0 : bouton « Pointer » (écrans de connexion) et tuile de l'accueil qui ouvrent l'application
// Prestige Pointage (com.dici.prestigepointage, demande 57) installée sur le même terminal — sans se déconnecter ni
// toucher la session de vente. Masqués quand Prestige Pointage n'est pas installée.
// Canal natif « prestige/pointage » (MainActivity) : estInstallee (visibilité du paquet déclarée par <queries> dans
// src/main/AndroidManifest.xml), ouvrir (intention de lancement du paquet). Aucune donnée n'est passée.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LanceurPointage {
  LanceurPointage._();

  static const paquet = 'com.dici.prestigepointage';
  static const _canal = MethodChannel('prestige/pointage');

  /// Prestige Pointage installée (dernière détection) ; faux tant qu'elle n'a pas été détectée.
  static final ValueNotifier<bool> installee = ValueNotifier(false);

  /// Remplaçables pour les tests.
  static Future<bool> Function() detecteur = () async => await _canal.invokeMethod<bool>('estInstallee', {'paquet': paquet}) ?? false;
  static Future<bool> Function() ouvreur = () async => await _canal.invokeMethod<bool>('ouvrir', {'paquet': paquet}) ?? false;

  /// Relit la présence de l'application (lancement, retour au premier plan).
  static Future<bool> detecter() async {
    try {
      installee.value = await detecteur();
    } catch (_) {
      installee.value = false;
    }
    return installee.value;
  }

  /// Ouvre Prestige Pointage ; message si elle n'a pas pu être ouverte (désinstallée entre-temps).
  static Future<bool> ouvrir(BuildContext context) async {
    var ok = false;
    try {
      ok = await ouvreur();
    } catch (_) {}
    if (!ok) {
      await detecter();
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(const SnackBar(content: Text('Prestige Pointage n\'a pas pu être ouverte : est-elle installée sur ce terminal ?')));
      }
    }
    return ok;
  }

  /// Tests : état initial.
  @visibleForTesting
  static void reinitialiser() {
    installee.value = false;
    detecteur = () async => await _canal.invokeMethod<bool>('estInstallee', {'paquet': paquet}) ?? false;
    ouvreur = () async => await _canal.invokeMethod<bool>('ouvrir', {'paquet': paquet}) ?? false;
  }
}

/// Bouton « Pointer » des écrans de connexion : visible seulement si Prestige Pointage est installée.
class BoutonPointer extends StatefulWidget {
  final Color couleur;
  const BoutonPointer({super.key, required this.couleur});

  @override
  State<BoutonPointer> createState() => _BoutonPointerState();
}

class _BoutonPointerState extends State<BoutonPointer> {
  @override
  void initState() {
    super.initState();
    LanceurPointage.detecter();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: LanceurPointage.installee,
        builder: (context, ok, _) => !ok
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: TextButton.icon(
                  key: const Key('bouton_pointer'),
                  style: TextButton.styleFrom(foregroundColor: widget.couleur, minimumSize: const Size(48, 48)),
                  onPressed: () => LanceurPointage.ouvrir(context),
                  icon: const Icon(Icons.badge_outlined),
                  label: const Text('Pointer (Prestige Pointage)', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
      );
}
