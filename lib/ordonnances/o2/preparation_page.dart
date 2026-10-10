// lib/ordonnances/o2/preparation_page.dart
// Étape O2 : préparation de la photo d'une ordonnance avant la lecture du texte (calculs hors interface) :
// - netteté de la page (refus des photos floues avec un message) ;
// - recadrage sur la « zone des médicaments » choisie par l'utilisateur (sans en-tête, tampon ni nom) ;
// - suppression des ombres et contraste : division par le fond estimé (flou large), puis étirement des niveaux.
// Le redressement de perspective (coins de la page) n'est pas fait : il demande une détection de contours
// fiable ; la capture guidée cadre la page de face à la place.
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:image/image.dart' as img;

class PreparationPage {
  PreparationPage._();

  /// En dessous : photo jugée floue. Mesure = force moyenne des 1 % de bords les plus francs
  /// (|laplacien| sur l'image réduite à 800 px) : indépendante de la quantité de texte sur la page.
  static const double seuilNettete = 25;

  /// Netteté : moyenne du 1 % des plus fortes valeurs de |laplacien| (niveaux de gris, largeur ≤ [largeur]).
  static double nettete(img.Image image, {int largeur = 800}) {
    final g = _gris(image.width > largeur ? img.copyResize(image, width: largeur) : image);
    final w = g.width, h = g.height;
    if (w < 3 || h < 3) return 0;
    final hist = List<int>.filled(1021, 0); // |laplacien| ≤ 4 × 255
    var n = 0;
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final v = 4 * _l(g, x, y) - _l(g, x - 1, y) - _l(g, x + 1, y) - _l(g, x, y - 1) - _l(g, x, y + 1);
        hist[v.abs().round().clamp(0, 1020)]++;
        n++;
      }
    }
    final cible = math.max(1, (n * 0.01).round());
    var pris = 0;
    var somme = 0.0;
    for (var k = 1020; k >= 0 && pris < cible; k--) {
      final c = math.min(hist[k], cible - pris);
      somme += c * k;
      pris += c;
    }
    return somme / pris;
  }

  static bool estFloue(img.Image image) => nettete(image) < seuilNettete;

  static num _l(img.Image g, int x, int y) => g.getPixel(x, y).r;

  static img.Image _gris(img.Image i) => img.grayscale(i.clone());

  /// Recadre sur [zone] exprimée en fractions de l'image (0…1).
  static img.Image recadrer(img.Image image, Rect zone) {
    final l = (zone.left.clamp(0.0, 1.0) * image.width).round();
    final t = (zone.top.clamp(0.0, 1.0) * image.height).round();
    final r = (zone.right.clamp(0.0, 1.0) * image.width).round();
    final b = (zone.bottom.clamp(0.0, 1.0) * image.height).round();
    if (r - l < 8 || b - t < 8) return image;
    return img.copyCrop(image, x: l, y: t, width: r - l, height: b - t);
  }

  /// Supprime les ombres (division par le fond) et étire le contraste. Renvoie une image en niveaux de gris.
  static img.Image ameliorer(img.Image image) {
    final g = _gris(image);
    // Fond : image très réduite puis floutée (les traits disparaissent, l'éclairage reste).
    final petite = img.copyResize(g, width: math.max(8, g.width ~/ 16), height: math.max(8, g.height ~/ 16));
    final fondPetit = img.gaussianBlur(petite, radius: 3);
    final fond = img.copyResize(fondPetit, width: g.width, height: g.height, interpolation: img.Interpolation.linear);
    final out = img.Image(width: g.width, height: g.height);
    final valeurs = Uint8List(g.width * g.height);
    var i = 0;
    for (var y = 0; y < g.height; y++) {
      for (var x = 0; x < g.width; x++) {
        final p = g.getPixel(x, y).r.toDouble();
        final f = math.max(1.0, fond.getPixel(x, y).r.toDouble());
        valeurs[i++] = (p / f * 255).clamp(0, 255).round();
      }
    }
    // Étirement des niveaux entre les centiles 1 % et 99 %.
    final hist = List<int>.filled(256, 0);
    for (final v in valeurs) {
      hist[v]++;
    }
    int centile(double c) {
      final cible = (valeurs.length * c).round();
      var cumul = 0;
      for (var k = 0; k < 256; k++) {
        cumul += hist[k];
        if (cumul >= cible) return k;
      }
      return 255;
    }

    final bas = centile(0.01), haut = math.max(centile(0.99), bas + 1);
    i = 0;
    for (var y = 0; y < g.height; y++) {
      for (var x = 0; x < g.width; x++) {
        final v = ((valeurs[i++] - bas) * 255 / (haut - bas)).clamp(0, 255).round();
        out.setPixelRgb(x, y, v, v, v);
      }
    }
    return out;
  }

  /// Fichier → (zone) → amélioration → nouveau JPEG ; renvoie son chemin. [zone] null : page entière.
  static Future<String> preparerFichier(String chemin, {Rect? zone, bool ameliorerImage = true}) {
    final z = zone == null ? null : [zone.left, zone.top, zone.right, zone.bottom];
    return Isolate.run(() {
      final decoded = img.decodeImage(File(chemin).readAsBytesSync());
      if (decoded == null) throw const FormatException('Photo illisible');
      var image = img.bakeOrientation(decoded);
      if (z != null) image = recadrer(image, Rect.fromLTRB(z[0], z[1], z[2], z[3]));
      if (ameliorerImage) image = ameliorer(image);
      final out = '${chemin.replaceAll(RegExp(r'\.(jpe?g|png|webp)$', caseSensitive: false), '')}_o2_${DateTime.now().microsecondsSinceEpoch}.jpg';
      File(out).writeAsBytesSync(img.encodeJpg(image, quality: 92));
      return out;
    });
  }

  /// Netteté d'un fichier image (hors interface).
  static Future<bool> fichierFlou(String chemin) => Isolate.run(() {
        final decoded = img.decodeImage(File(chemin).readAsBytesSync());
        if (decoded == null) return false;
        return estFloue(img.bakeOrientation(decoded));
      });
}
