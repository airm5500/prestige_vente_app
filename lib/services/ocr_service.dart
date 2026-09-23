// lib/services/ocr_service.dart
// Photo (appareil photo ou galerie) + reconnaissance du texte sur l'appareil (ML Kit, hors ligne).
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

class OcrService {
  OcrService._();

  /// Prend une photo puis renvoie les lignes de texte reconnues, de haut en bas.
  /// `null` si l'opérateur annule la prise de vue.
  static Future<List<String>?> captureAndRead(ImageSource source) async {
    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: 2400,
      maxHeight: 2400,
      imageQuality: 95,
    );
    if (file == null) return null;
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognized = await recognizer.processImage(InputImage.fromFilePath(file.path));
      final lines = <TextLine>[
        for (final block in recognized.blocks) ...block.lines,
      ];
      // Ordre de lecture : de haut en bas puis de gauche à droite.
      lines.sort((a, b) {
        final dy = a.boundingBox.top - b.boundingBox.top;
        if (dy.abs() > a.boundingBox.height / 2) return dy.sign.toInt();
        return (a.boundingBox.left - b.boundingBox.left).sign.toInt();
      });
      return lines.map((l) => l.text).toList();
    } finally {
      recognizer.close();
    }
  }

  /// Message compréhensible pour l'opérateur à partir d'une erreur technique.
  static String friendlyError(Object e) {
    if (e is MissingPluginException ||
        (e is PlatformException && (e.code == 'channel-error' || e.message?.contains('Unable to establish connection') == true))) {
      return 'Module photo non chargé. Fermez complètement l\'application puis relancez-la '
          '(après une mise à jour, un hot restart ne suffit pas : refaire "flutter run" ou réinstaller l\'APK).';
    }
    if (e is PlatformException && (e.code.contains('camera_access_denied') || e.code.contains('photo_access_denied'))) {
      return 'Accès refusé : autorisez l\'appareil photo pour Prestige dans les paramètres Android.';
    }
    return 'Lecture impossible : $e';
  }
}
