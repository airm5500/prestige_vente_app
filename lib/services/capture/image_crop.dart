// lib/services/capture/image_crop.dart
// Recadrage de la photo sur le cadre, avant la lecture du texte (calcul hors de l'interface).
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;
import 'package:prestige_vente_app/services/capture/capture_geometry.dart';

class ImageCrop {
  ImageCrop._();

  /// Recadre la photo [path] sur la zone vue dans [frame] (aperçu "cover" dans [view]).
  /// Écrit un nouveau JPEG et renvoie son chemin.
  static Future<String> cropToFrame({required String path, required Size view, required Rect frame}) {
    final vw = view.width, vh = view.height;
    final fl = frame.left, ft = frame.top, fr = frame.right, fb = frame.bottom;
    return Isolate.run(() {
      final bytes = File(path).readAsBytesSync();
      final cropped = cropBytes(bytes, view: Size(vw, vh), frame: Rect.fromLTRB(fl, ft, fr, fb));
      final out = '${path.replaceAll(RegExp(r'\.(jpe?g|png)$', caseSensitive: false), '')}_cadre.jpg';
      File(out).writeAsBytesSync(cropped);
      return out;
    });
  }

  /// Recadrage pur (testable) : décode, redresse selon l'EXIF, découpe, encode en JPEG.
  static Uint8List cropBytes(List<int> bytes, {required Size view, required Rect frame}) {
    final decoded = img.decodeImage(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));
    if (decoded == null) throw const FormatException('Photo illisible');
    final upright = img.bakeOrientation(decoded);
    final r = CaptureGeometry.frameInImage(
      image: Size(upright.width.toDouble(), upright.height.toDouble()),
      view: view,
      frame: frame,
    );
    if (r.isEmpty) throw const FormatException('Cadre hors de la photo');
    final crop = img.copyCrop(
      upright,
      x: r.left.round(),
      y: r.top.round(),
      width: r.width.round(),
      height: r.height.round(),
    );
    return img.encodeJpg(crop, quality: 95);
  }
}
