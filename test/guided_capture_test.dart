import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:prestige_vente_app/services/capture/capture_geometry.dart';
import 'package:prestige_vente_app/services/capture/frame_quality.dart';
import 'package:prestige_vente_app/services/capture/image_crop.dart';

/// Plan Y synthétique : [pixel] donne la luminance de (x, y).
Uint8List plane(int w, int h, int Function(int x, int y) pixel) {
  final b = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      b[y * w + x] = pixel(x, y).clamp(0, 255);
    }
  }
  return b;
}

FrameQuality measure(Uint8List y, {FrameQuality? previous}) => FrameQuality.measure(
      y: y,
      width: 320,
      height: 240,
      bytesPerRow: 320,
      region: const Rect.fromLTRB(40, 40, 280, 200),
      previous: previous,
    );

// Texte net : traits noirs fins sur fond clair. Texte flou : mêmes traits, transitions douces.
int sharpText(int x, int y, [int shift = 0]) => ((x + shift) % 12 < 2 || (y % 16 < 2 && x % 40 < 30)) ? 30 : 200;
int blurredText(int x, int y) {
  final d = (x % 12) - 6;
  return (200 - 170 * (1 - (d.abs() / 6))).round();
}

void main() {
  group('Géométrie du cadre', () {
    test('cadre centré, dans l\'écran', () {
      const view = Size(400, 800);
      final f = CaptureGeometry.frameInView(view);
      expect(f.center.dx, 200);
      expect(f.width, closeTo(344, 0.1));
      expect((Offset.zero & view).contains(f.topLeft) && (Offset.zero & view).contains(f.bottomRight), isTrue);
    });

    test('aperçu "cover" : le cadre correspond à la bonne zone de la photo', () {
      // Photo 1080 x 1920 affichée sur 400 x 800 : échelle 0,4167, 25 px coupés à gauche et à droite.
      final r = CaptureGeometry.frameInImage(
        image: const Size(1080, 1920),
        view: const Size(400, 800),
        frame: const Rect.fromLTRB(25, 100, 375, 300),
        margin: 0,
      );
      expect(r.left, closeTo(120, 0.5));
      expect(r.right, closeTo(960, 0.5));
      expect(r.top, closeTo(240, 0.5));
      expect(r.bottom, closeTo(720, 0.5));
    });

    test('marge et limites de la photo', () {
      final r = CaptureGeometry.frameInImage(
        image: const Size(1080, 1920),
        view: const Size(400, 800),
        frame: const Rect.fromLTRB(-60, -60, 460, 100),
      );
      expect(r.left, 0); // ne sort pas de la photo
      expect(r.top, 0);
    });

    test('passage à l\'image du capteur (tournée de 90°)', () {
      // Image redressée 1080 x 1920 ; capteur 1920 x 1080.
      final r = CaptureGeometry.uprightToSensor(
        const Rect.fromLTRB(100, 200, 300, 260),
        sensor: const Size(1920, 1080),
        sensorOrientation: 90,
      );
      expect(r, const Rect.fromLTRB(200, 780, 260, 980));
      expect(
        CaptureGeometry.uprightToSensor(const Rect.fromLTRB(1, 2, 3, 4), sensor: const Size(10, 10), sensorOrientation: 0),
        const Rect.fromLTRB(1, 2, 3, 4),
      );
    });
  });

  group('Qualité de l\'image', () {
    test('texte net : contraste et netteté élevés ; flou : netteté faible', () {
      final sharp = measure(plane(320, 240, sharpText));
      final blurred = measure(plane(320, 240, blurredText));
      expect(sharp.contrast, greaterThan(AutoCaptureGate.minContrast));
      expect(sharp.sharpness, greaterThan(blurred.sharpness * 3));
      expect(sharp.brightness, inInclusiveRange(150, 200));
    });

    test('surface unie : pas de texte ; image noire : trop sombre', () {
      final uniform = measure(plane(320, 240, (x, y) => 180));
      expect(uniform.contrast, lessThan(1));
      final dark = measure(plane(320, 240, (x, y) => 20 + (x % 7)));
      expect(dark.brightness, lessThan(AutoCaptureGate.minBrightness));
    });

    test('mouvement entre deux images', () {
      final a = measure(plane(320, 240, sharpText));
      final same = measure(plane(320, 240, sharpText), previous: a);
      expect(same.motion, 0);
      final big = measure(plane(320, 240, (x, y) => y < 120 ? 40 : 220));
      final moved = measure(plane(320, 240, (x, y) => y < 60 ? 40 : 220), previous: big);
      expect(moved.motion, greaterThan(AutoCaptureGate.maxMotion));
      expect(a.motion, isNull);
    });
  });

  group('Capture automatique', () {
    final t0 = DateTime(2026, 10, 10, 9);
    DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

    test('image nette et immobile : photo après la mise au point et le maintien', () {
      final gate = AutoCaptureGate();
      FrameQuality? prev;
      CaptureAdvice? last;
      var capturedAt = -1;
      for (var ms = 0; ms <= 3000 && capturedAt < 0; ms += 120) {
        prev = measure(plane(320, 240, sharpText), previous: prev);
        last = gate.update(prev, at(ms));
        if (last.capture) capturedAt = ms;
      }
      expect(capturedAt, inInclusiveRange(1200 + 700, 2200));
      expect(last!.hint, CaptureHint.ready);
    });

    test('mouvement : pas de photo ; trop sombre : lampe proposée', () {
      final gate = AutoCaptureGate();
      FrameQuality? prev;
      for (var i = 0; i < 25; i++) {
        prev = measure(plane(320, 240, (x, y) => sharpText(x, y, i * 5)), previous: prev);
        final a = gate.update(prev, at(i * 120));
        expect(a.capture, isFalse);
      }

      final dark = AutoCaptureGate();
      CaptureAdvice? a;
      for (var i = 0; i < 16; i++) {
        a = dark.update(measure(plane(320, 240, (x, y) => 20)), at(i * 120));
      }
      expect(a!.hint, CaptureHint.tooDark);
      expect(a.suggestTorch, isTrue);
    });

    test('flou par rapport à la meilleure netteté vue : on attend', () {
      final gate = AutoCaptureGate();
      FrameQuality? prev;
      for (var i = 0; i < 12; i++) {
        prev = measure(plane(320, 240, sharpText), previous: prev);
        gate.update(prev, at(i * 120));
      }
      // L'image devient floue (mise au point perdue) mais reste immobile et lumineuse.
      final soft = measure(plane(320, 240, (x, y) => ((x % 12 < 2) ? 150 : 185)));
      final a = gate.update(FrameQuality(brightness: soft.brightness, contrast: 20, sharpness: soft.sharpness, motion: 0, cells: soft.cells), at(1600));
      expect(a.hint, CaptureHint.blurry);
      expect(a.capture, isFalse);
    });
  });

  test('recadrage : seule la zone du cadre est gardée', () {
    // Photo 1080 x 1920 ; le cadre (écran 400 x 800) couvre x 120..960, y 240..720.
    final photo = img.Image(width: 1080, height: 1920);
    img.fill(photo, color: img.ColorRgb8(255, 255, 255));
    final out = ImageCrop.cropBytes(
      img.encodeJpg(photo),
      view: const Size(400, 800),
      frame: const Rect.fromLTRB(25, 100, 375, 300),
    );
    final cropped = img.decodeJpg(out)!;
    // Marge de 6 % du cadre (350 px écran -> 21 px écran -> ~50 px photo de chaque côté au total).
    expect(cropped.width, inInclusiveRange(840, 900));
    expect(cropped.height, inInclusiveRange(480, 560));
  });
}
