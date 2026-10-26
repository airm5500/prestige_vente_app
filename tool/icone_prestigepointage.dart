// Génère l'icône de Prestige Pointage (saveur `pointage`) : fond vert sarcelle, horloge blanche, pastille ambre cochée.
//   dart run tool/icone_prestigepointage.dart
// Écrit android/app/src/pointage/res/mipmap-*/launcher_icon{,_round,_foreground}.png.
import 'dart:io';

import 'package:image/image.dart' as img;

final vert = img.ColorRgba8(15, 118, 110, 255);
final blanc = img.ColorRgba8(255, 255, 255, 255);
final ambre = img.ColorRgba8(245, 158, 11, 255);

img.Image dessin(int taille, String fond, double echelle) {
  final s = taille * 4;
  final im = img.Image(width: s, height: s, numChannels: 4);
  img.fill(im, color: img.ColorRgba8(0, 0, 0, 0));
  if (fond == 'rond') img.fillCircle(im, x: s ~/ 2, y: s ~/ 2, radius: s ~/ 2 - 1, color: vert, antialias: true);
  if (fond == 'carre') img.fillRect(im, x1: 0, y1: 0, x2: s - 1, y2: s - 1, radius: s ~/ 5, color: vert);
  final c = s / 2, r = s * 0.30 * echelle, w = (s * 0.06 * echelle).clamp(4, 9999).toDouble();
  // cadran : anneau blanc
  img.fillCircle(im, x: c.round(), y: c.round(), radius: r.round(), color: blanc, antialias: true);
  img.fillCircle(im, x: c.round(), y: c.round(), radius: (r - w).round(), color: fond == '' ? img.ColorRgba8(0, 0, 0, 0) : vert, antialias: true);
  // aiguilles (10 h 10)
  img.drawLine(im, x1: c.round(), y1: c.round(), x2: c.round(), y2: (c - r * 0.62).round(), color: blanc, thickness: w, antialias: false);
  img.drawLine(im, x1: c.round(), y1: c.round(), x2: (c + r * 0.48).round(), y2: (c + r * 0.05).round(), color: blanc, thickness: w, antialias: false);
  img.fillCircle(im, x: c.round(), y: c.round(), radius: w.round(), color: blanc, antialias: true);
  // pastille ambre cochée
  final cx = c + r * 0.78, cy = c + r * 0.78, k = r * 0.42;
  img.fillCircle(im, x: cx.round(), y: cy.round(), radius: k.round(), color: ambre, antialias: true);
  img.drawLine(im, x1: (cx - k * 0.5).round(), y1: cy.round(), x2: (cx - k * 0.1).round(), y2: (cy + k * 0.4).round(), color: blanc, thickness: w * 0.8, antialias: false);
  img.drawLine(im, x1: (cx - k * 0.1).round(), y1: (cy + k * 0.4).round(), x2: (cx + k * 0.55).round(), y2: (cy - k * 0.4).round(), color: blanc, thickness: w * 0.8, antialias: false);
  return img.copyResize(im, width: taille, height: taille, interpolation: img.Interpolation.average);
}

void main() {
  const res = 'android/app/src/pointage/res';
  for (final (dens, t) in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]) {
    final d = Directory('$res/mipmap-$dens')..createSync(recursive: true);
    File('${d.path}/launcher_icon.png').writeAsBytesSync(img.encodePng(dessin(t, 'carre', 1.0)));
    File('${d.path}/launcher_icon_round.png').writeAsBytesSync(img.encodePng(dessin(t, 'rond', 1.0)));
    File('${d.path}/launcher_icon_foreground.png').writeAsBytesSync(img.encodePng(dessin(t * 108 ~/ 48, '', 0.6)));
  }
}
