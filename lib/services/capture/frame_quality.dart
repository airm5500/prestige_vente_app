// lib/services/capture/frame_quality.dart
// Qualité d'une image de l'aperçu (plan de luminance Y) dans la zone du cadre :
// luminosité, contraste (présence de texte), netteté et mouvement. Calculs légers sur un échantillon de points.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

class FrameQuality {
  /// Luminosité moyenne (0 noir ... 255 blanc).
  final double brightness;

  /// Écart-type de la luminosité : faible = surface unie, sans texte.
  final double contrast;

  /// Netteté : moyenne de la valeur absolue du laplacien (bords francs = élevé).
  final double sharpness;

  /// Mouvement par rapport à l'image précédente (0 = immobile), null pour la première image.
  final double? motion;

  /// Moyennes par case, pour mesurer le mouvement à l'image suivante.
  final List<double> cells;

  const FrameQuality({
    required this.brightness,
    required this.contrast,
    required this.sharpness,
    required this.motion,
    required this.cells,
  });

  static const _cellsX = 16, _cellsY = 8;

  /// Mesure la zone [region] (coordonnées du plan Y) ; [previous] sert au calcul du mouvement.
  static FrameQuality measure({
    required Uint8List y,
    required int width,
    required int height,
    required int bytesPerRow,
    required Rect region,
    FrameQuality? previous,
  }) {
    final left = region.left.clamp(1, width - 2).toInt();
    final top = region.top.clamp(1, height - 2).toInt();
    final right = region.right.clamp(left + 2, width - 1).toInt();
    final bottom = region.bottom.clamp(top + 2, height - 1).toInt();
    final w = right - left, h = bottom - top;
    // Environ 160 x 80 points, quelle que soit la résolution.
    final step = math.max(1, math.min(w ~/ 160, h ~/ 80));

    var n = 0;
    var sum = 0.0, sumSq = 0.0, lapSum = 0.0;
    final cellSum = List<double>.filled(_cellsX * _cellsY, 0);
    final cellCount = List<int>.filled(_cellsX * _cellsY, 0);

    for (var py = top; py < bottom; py += step) {
      final row = py * bytesPerRow;
      final cy = ((py - top) * _cellsY ~/ h).clamp(0, _cellsY - 1);
      for (var px = left; px < right; px += step) {
        final v = y[row + px];
        sum += v;
        sumSq += v * v;
        // Laplacien sur les voisins immédiats (pixels adjacents, pas l'échantillon).
        final lap = 4 * v - y[row + px - 1] - y[row + px + 1] - y[row - bytesPerRow + px] - y[row + bytesPerRow + px];
        lapSum += lap.abs();
        final c = cy * _cellsX + ((px - left) * _cellsX ~/ w).clamp(0, _cellsX - 1);
        cellSum[c] += v;
        cellCount[c]++;
        n++;
      }
    }
    final mean = sum / n;
    final variance = math.max(0.0, sumSq / n - mean * mean);
    final cells = [for (var i = 0; i < cellSum.length; i++) cellCount[i] == 0 ? 0.0 : cellSum[i] / cellCount[i]];
    double? motion;
    if (previous != null && previous.cells.length == cells.length) {
      var d = 0.0;
      for (var i = 0; i < cells.length; i++) {
        d += (cells[i] - previous.cells[i]).abs();
      }
      motion = d / cells.length;
    }
    return FrameQuality(
      brightness: mean,
      contrast: math.sqrt(variance),
      sharpness: lapSum / n,
      motion: motion,
      cells: cells,
    );
  }
}

enum CaptureHint { starting, tooDark, tooBright, noText, moving, blurry, ready }

class CaptureAdvice {
  final CaptureHint hint;

  /// Progression vers la capture automatique (0 ... 1).
  final double progress;

  /// true : prendre la photo maintenant.
  final bool capture;

  /// Image sombre depuis un moment : proposer la lampe.
  final bool suggestTorch;

  const CaptureAdvice(this.hint, {this.progress = 0, this.capture = false, this.suggestTorch = false});

  String get message => switch (hint) {
        CaptureHint.starting => 'Mise au point...',
        CaptureHint.tooDark => 'Trop sombre',
        CaptureHint.tooBright => 'Trop de lumière ou reflet : inclinez légèrement',
        CaptureHint.noText => 'Placez LOT et EXP dans le cadre',
        CaptureHint.moving => 'Ne bougez plus',
        CaptureHint.blurry => 'Image floue : éloignez-vous un peu',
        CaptureHint.ready => 'Ne bougez plus, photo...',
      };
}

/// Décide quand prendre la photo : bonne lumière, texte présent, image nette et stable
/// pendant [hold]. La netteté est jugée par rapport à la meilleure valeur récente
/// (les seuils absolus varient trop d'un appareil à l'autre).
class AutoCaptureGate {
  final Duration warmup;
  final Duration hold;
  final Duration darkBeforeTorch;

  static const minBrightness = 55.0, maxBrightness = 232.0;
  static const minContrast = 16.0;
  static const maxMotion = 4.0;
  static const minSharpness = 5.0;

  AutoCaptureGate({
    this.warmup = const Duration(milliseconds: 1200),
    this.hold = const Duration(milliseconds: 700),
    this.darkBeforeTorch = const Duration(milliseconds: 1500),
  });

  DateTime? _start;
  DateTime? _goodSince;
  DateTime? _darkSince;
  double _peakSharpness = 0;

  void reset() {
    _start = null;
    _goodSince = null;
    _darkSince = null;
    _peakSharpness = 0;
  }

  CaptureAdvice update(FrameQuality q, DateTime now) {
    _start ??= now;
    // La meilleure netteté récente baisse doucement (le cadrage change).
    _peakSharpness = math.max(q.sharpness, _peakSharpness * 0.97);

    final dark = q.brightness < minBrightness;
    if (dark) {
      _darkSince ??= now;
    } else {
      _darkSince = null;
    }
    final suggestTorch = _darkSince != null && now.difference(_darkSince!) >= darkBeforeTorch;

    CaptureHint? problem;
    if (dark) {
      problem = CaptureHint.tooDark;
    } else if (q.brightness > maxBrightness) {
      problem = CaptureHint.tooBright;
    } else if (q.contrast < minContrast) {
      problem = CaptureHint.noText;
    } else if (q.motion == null || q.motion! > maxMotion) {
      problem = CaptureHint.moving;
    } else if (q.sharpness < minSharpness || q.sharpness < _peakSharpness * 0.75) {
      problem = CaptureHint.blurry;
    } else if (now.difference(_start!) < warmup) {
      problem = CaptureHint.starting;
    }

    if (problem != null) {
      _goodSince = null;
      return CaptureAdvice(problem, suggestTorch: suggestTorch);
    }
    _goodSince ??= now;
    final held = now.difference(_goodSince!);
    final progress = (held.inMilliseconds / hold.inMilliseconds).clamp(0.0, 1.0);
    return CaptureAdvice(CaptureHint.ready, progress: progress, capture: held >= hold);
  }
}
