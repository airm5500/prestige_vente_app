// lib/services/code_photo.dart
// Lecture des codes (DataMatrix, EAN, QR…) sur une PHOTO déjà prise, par ML Kit, sans caméra active (4.4.0).
// Utilisée par « Photo étiquette » : si le DataMatrix de la boîte est dans le cadre, son lot et sa date (GS1)
// sont plus sûrs que la lecture du texte. Aucune donnée conservée : le fichier reste à la charge de l'appelant.
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:prestige_vente_app/screens/common/camera_scan_screen.dart';

class CodePhoto {
  CodePhoto._();

  /// Lecteur réel (ML Kit) ; remplaçable dans les tests.
  static Future<List<String>> Function(String chemin) lecteur = _mlKit;

  static Future<List<String>> _mlKit(String chemin) async {
    final c = MobileScannerController(autoStart: false, formats: CameraScanScreen.formatsProduit);
    try {
      final r = await c.analyzeImage(chemin, formats: CameraScanScreen.formatsProduit);
      return [
        for (final b in r?.barcodes ?? const <Barcode>[])
          if (CameraScanScreen.valueOf(b) case final v? when v.isNotEmpty) v,
      ];
    } finally {
      await c.dispose();
    }
  }

  /// Codes lus sur la photo ; liste vide si aucun ou en cas d'erreur (la lecture du texte reste possible).
  static Future<List<String>> lire(String chemin) async {
    try {
      return await lecteur(chemin);
    } catch (_) {
      return const [];
    }
  }
}
