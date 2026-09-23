// lib/services/ocr_service.dart
// Photo (appareil photo / galerie) ou PDF -> reconnaissance du texte sur l'appareil (ML Kit, hors ligne).
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';

class OcrService {
  OcrService._();

  /// Résolution de rendu des PDF : 300 dpi donne un texte net pour la reconnaissance.
  static const double pdfDpi = 300;
  static const int pdfMaxPages = 5;

  /// Prend une photo puis renvoie les lignes de texte reconnues (une par ligne visuelle).
  /// `null` si l'opérateur annule la prise de vue.
  static Future<List<String>?> captureAndRead(ImageSource source) async {
    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: 2400,
      maxHeight: 2400,
      imageQuality: 95,
    );
    if (file == null) return null;
    return readImageFile(file.path);
  }

  /// Choisit un PDF (ordonnance reçue par e-mail / WhatsApp / éditée par Prestige),
  /// le rend en images haute définition puis en lit le texte. `null` si annulé.
  static Future<List<String>?> pickPdfAndRead() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return null;
    final f = picked.files.first;
    final bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
    if (bytes == null) return null;

    final rows = <String>[];
    final tmp = Directory.systemTemp;
    var page = 0;
    await for (final raster in Printing.raster(bytes, dpi: pdfDpi)) {
      if (page >= pdfMaxPages) break;
      final png = await raster.toPng();
      final file = File('${tmp.path}/ordonnance_page_${DateTime.now().microsecondsSinceEpoch}_$page.png');
      await file.writeAsBytes(png, flush: true);
      try {
        rows.addAll(await readImageFile(file.path));
      } finally {
        if (await file.exists()) await file.delete();
      }
      page++;
    }
    return rows;
  }

  static Future<List<String>> readImageFile(String path) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognized = await recognizer.processImage(InputImage.fromFilePath(path));
      return groupIntoRows([
        for (final block in recognized.blocks)
          for (final line in block.lines) (box: line.boundingBox, text: line.text),
      ]);
    } finally {
      recognizer.close();
    }
  }

  /// Regroupe les morceaux de texte situés à la même hauteur en une seule ligne,
  /// de gauche à droite (colonnes séparées par deux espaces). Indispensable pour
  /// les tableaux : « Produit | CIP | Qté | Posologie » restent sur la même ligne.
  static List<String> groupIntoRows(List<({Rect box, String text})> items) {
    final sorted = [...items]..sort((a, b) => a.box.center.dy.compareTo(b.box.center.dy));
    final rows = <List<({Rect box, String text})>>[];
    for (final item in sorted) {
      final h = item.box.height;
      List<({Rect box, String text})>? target;
      for (final row in rows) {
        final ref = row.first.box;
        final tolerance = (h < ref.height ? h : ref.height) * 0.5;
        if ((item.box.center.dy - ref.center.dy).abs() <= tolerance) {
          target = row;
          break;
        }
      }
      if (target == null) {
        rows.add([item]);
      } else {
        target.add(item);
      }
    }
    return [
      for (final row in rows)
        (row..sort((a, b) => a.box.left.compareTo(b.box.left))).map((e) => e.text.trim()).where((t) => t.isNotEmpty).join('  '),
    ].where((r) => r.isNotEmpty).toList();
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
