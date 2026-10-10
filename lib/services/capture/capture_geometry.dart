// lib/services/capture/capture_geometry.dart
// Géométrie de la capture guidée : position du cadre à l'écran et zone correspondante
// dans l'image de la caméra (aperçu affiché en "cover" : l'image remplit l'écran, les bords débordent).
import 'dart:math' as math;
import 'dart:ui';

class CaptureGeometry {
  CaptureGeometry._();

  /// Cadre fixe à l'écran : bande horizontale (étiquette LOT / EXP), centrée, un peu au-dessus du milieu.
  static Rect frameInView(Size view) {
    final width = view.width * 0.86;
    final height = math.min(width * 0.42, view.height * 0.35);
    final centerY = view.height * 0.42;
    return Rect.fromCenter(center: Offset(view.width / 2, centerY), width: width, height: height);
  }

  /// Cadre « page » (ordonnance A5 / A4, portrait 1 : 1,414), centré un peu au-dessus du milieu
  /// pour laisser la place aux consignes et au déclencheur.
  static Rect pageFrameInView(Size view) {
    var height = math.min(view.width * 0.88 * 1.414, view.height * 0.62);
    final width = height / 1.414;
    height = width * 1.414;
    return Rect.fromCenter(center: Offset(view.width / 2, view.height * 0.43), width: width, height: height);
  }

  /// Zone de l'image (redressée) visible dans [frame], l'aperçu remplissant [view] en mode "cover".
  /// [margin] élargit la zone (fraction de la taille du cadre) pour ne pas couper un caractère au bord.
  static Rect frameInImage({required Size image, required Size view, required Rect frame, double margin = 0.06}) {
    final scale = math.max(view.width / image.width, view.height / image.height);
    final shown = Size(image.width * scale, image.height * scale);
    final offset = Offset((view.width - shown.width) / 2, (view.height - shown.height) / 2);
    final grown = frame.inflate(math.max(frame.width, frame.height) * margin / 2);
    final r = Rect.fromLTRB(
      (grown.left - offset.dx) / scale,
      (grown.top - offset.dy) / scale,
      (grown.right - offset.dx) / scale,
      (grown.bottom - offset.dy) / scale,
    );
    return r.intersect(Offset.zero & image);
  }

  /// Convertit une zone de l'image redressée (portrait) vers l'image brute du capteur,
  /// tournée de [sensorOrientation] degrés (0, 90, 180, 270) par rapport à l'écran.
  static Rect uprightToSensor(Rect r, {required Size sensor, required int sensorOrientation}) {
    // Taille de l'image redressée.
    final quarter = (sensorOrientation ~/ 90) % 4;
    final upright = quarter.isOdd ? Size(sensor.height, sensor.width) : sensor;
    switch (quarter) {
      case 1: // capteur tourné de 90° : x capteur = y écran ; y capteur = largeur - x écran
        return Rect.fromLTRB(r.top, upright.width - r.right, r.bottom, upright.width - r.left);
      case 2:
        return Rect.fromLTRB(upright.width - r.right, upright.height - r.bottom, upright.width - r.left, upright.height - r.top);
      case 3:
        return Rect.fromLTRB(upright.height - r.bottom, r.left, upright.height - r.top, r.right);
      default:
        return r;
    }
  }
}
