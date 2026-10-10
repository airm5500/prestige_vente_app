// lib/ordonnances/o2/lecture_o2.dart
// Étape O2 en production : interrupteurs (Réglages › Ventes, DÉSACTIVÉS par défaut) et lecture d'une
// photo d'ordonnance : capture guidée de la page (ou galerie) → refus des photos floues → zone des
// médicaments → (option) contraste / ombres → ML Kit. Le découpage par lignes numérotées est appliqué
// par l'écran Ordonnance ([DecoupageOrdonnance.extraire]) quand la nouvelle lecture est active.
// À activer seulement si le banc d'essai montre un meilleur score que la référence (anti-régression).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:prestige_vente_app/ordonnances/o2/preparation_page.dart';
import 'package:prestige_vente_app/ordonnances/o2/zone_medicaments_screen.dart';
import 'package:prestige_vente_app/screens/common/guided_capture_screen.dart';
import 'package:prestige_vente_app/services/ocr_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lecture des ordonnances : actuelle (d'origine), O2 (page + lignes numérotées),
/// O3 (O2 + correspondance catalogue améliorée).
enum ModeLecture { actuelle, o2, o3 }

class LectureO2 {
  LectureO2._();

  static const _cleMode = 'ordonnance_lecture_mode_v1';
  static const _cleActif = 'ordonnance_lecture_o2_v1'; // ancien réglage O2 (booléen), repris s'il existe
  static const _cleImage = 'ordonnance_lecture_o2_image_v1';

  /// Lecture choisie. « Actuelle » par défaut.
  static final ValueNotifier<ModeLecture> mode = ValueNotifier<ModeLecture>(ModeLecture.actuelle);

  /// Nouvelle lecture (O2 ou O3) : capture page, zone des médicaments, lignes numérotées.
  static bool get nouvelleLecture => mode.value != ModeLecture.actuelle;

  /// Amélioration de l'image (contraste, ombres) avant la lecture. Désactivée par défaut.
  static final ValueNotifier<bool> ameliorerImage = ValueNotifier<bool>(false);

  static Future<void> charger() async {
    try {
      final p = await SharedPreferences.getInstance();
      final m = ModeLecture.values.asNameMap()[p.getString(_cleMode)];
      mode.value = m ?? ((p.getBool(_cleActif) ?? false) ? ModeLecture.o2 : ModeLecture.actuelle);
      ameliorerImage.value = p.getBool(_cleImage) ?? false;
    } catch (_) {}
  }

  static Future<void> definirMode(ModeLecture m) async {
    mode.value = m;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_cleMode, m.name);
      await p.remove(_cleActif);
    } catch (_) {}
  }

  static Future<void> definirAmeliorerImage(bool v) async {
    ameliorerImage.value = v;
    try {
      await (await SharedPreferences.getInstance()).setBool(_cleImage, v);
    } catch (_) {}
  }

  /// Photo (capture guidée de la page) ou galerie → lignes lues ; null si annulé.
  static Future<List<String>?> lire(BuildContext context, {required bool camera}) async {
    final temporaires = <String>[];
    try {
      while (true) {
        String? chemin;
        if (!context.mounted) return null;
        if (camera) {
          chemin = await GuidedCaptureScreen.openPage(context);
          if (chemin != null) temporaires.add(chemin);
        } else {
          chemin = (await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2400, maxHeight: 2400, imageQuality: 95))?.path;
        }
        if (chemin == null || !context.mounted) return null;

        if (await PreparationPage.fichierFlou(chemin)) {
          if (!context.mounted) return null;
          final choix = await _photoFloue(context);
          if (choix == null || !context.mounted) return null;
          if (choix == false) continue; // reprendre
        }
        if (!context.mounted) return null;
        final zone = await ZoneMedicamentsScreen.ouvrir(context, chemin);
        if (zone == null) return null;
        final entiere = zone == ZoneMedicamentsScreen.pageEntiere;
        var aLire = chemin;
        if (!entiere || ameliorerImage.value) {
          aLire = await PreparationPage.preparerFichier(chemin, zone: entiere ? null : zone, ameliorerImage: ameliorerImage.value);
          temporaires.add(aLire);
        }
        return await OcrService.readImageFile(aLire);
      }
    } finally {
      for (final t in temporaires) {
        try {
          final f = File(t);
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
    }
  }

  /// true : lire quand même ; false : reprendre ; null : annuler.
  static Future<bool?> _photoFloue(BuildContext context) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Photo floue'),
          content: const Text('La photo est floue : la lecture serait mauvaise. Reprenez-la bien à plat, '
              'avec assez de lumière, sans bouger.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Annuler')),
            TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Lire quand même')),
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Reprendre')),
          ],
        ),
      );
}
