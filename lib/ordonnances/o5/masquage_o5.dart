// lib/ordonnances/o5/masquage_o5.dart
// Étape O5 : image envoyée pour la lecture avancée — protection des données (calculs hors interface, pur Dart).
//  - recadrage OBLIGATOIRE sur la zone des médicaments (la page entière est refusée) ;
//  - masquage automatique des bandes du haut et du bas de la page (en-tête, patient, signature, tampon) là où la
//    zone les recouvre ;
//  - masques ajoutés à la main (nom, date de naissance, téléphone…) ;
//  - nouvelle image JPEG SANS métadonnées (EXIF : appareil, date, position), réduite à 1 600 px, qualité 80.
// L'image produite est celle montrée à l'utilisateur avant l'envoi, et la seule envoyée.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:image/image.dart' as img;

abstract final class MasquageO5 {
  /// Bande masquée automatiquement en haut de la page (en-tête, médecin, patient).
  static const double bandeHaut = 0.18;

  /// Bande masquée automatiquement en bas de la page (signature, tampon, adresse).
  static const double bandeBas = 0.12;

  /// Au-delà de cette part de la page, la zone n'est pas un recadrage : refusée.
  static const double partMax = 0.85;

  static const int coteMax = 1600;
  static const int qualite = 80;

  /// Zone utilisée par le banc d'essai (pas de recadrage manuel) : la page sans les bandes haut / bas.
  static const Rect zoneBanc = Rect.fromLTRB(0, bandeHaut, 1, 1 - bandeBas);

  /// La zone est un vrai recadrage (pas la page entière).
  static bool zoneValide(Rect zone) {
    if (zone.width <= 0 || zone.height <= 0) return false;
    return zone.width * zone.height <= partMax + 1e-9;
  }

  /// Masques automatiques, en fractions de la ZONE : parties de la zone dans les bandes haut / bas de la page.
  static List<Rect> masquesAuto(Rect zone) {
    final out = <Rect>[];
    if (zone.top < bandeHaut) {
      final b = math.min(zone.bottom, bandeHaut);
      out.add(Rect.fromLTRB(0, 0, 1, (b - zone.top) / zone.height));
    }
    if (zone.bottom > 1 - bandeBas) {
      final t = math.max(zone.top, 1 - bandeBas);
      out.add(Rect.fromLTRB(0, (t - zone.top) / zone.height, 1, 1));
    }
    return out;
  }

  /// Image à envoyer : recadrée sur [zone] (fractions de la page), masques auto + [masques] (fractions de la zone)
  /// peints en noir, réduite, JPEG sans métadonnées. Lève [ArgumentError] si la zone n'est pas un recadrage.
  static Uint8List preparer(Uint8List source, Rect zone, {List<Rect> masques = const []}) {
    if (!zoneValide(zone)) {
      throw ArgumentError('Recadrez sur la zone des médicaments : la page entière n\'est jamais envoyée.');
    }
    final decoded = img.decodeImage(source);
    if (decoded == null) throw const FormatException('Photo illisible');
    final page = img.bakeOrientation(decoded);
    final l = (zone.left.clamp(0.0, 1.0) * page.width).round();
    final t = (zone.top.clamp(0.0, 1.0) * page.height).round();
    final r = (zone.right.clamp(0.0, 1.0) * page.width).round();
    final b = (zone.bottom.clamp(0.0, 1.0) * page.height).round();
    var z = img.copyCrop(page, x: l, y: t, width: math.max(1, r - l), height: math.max(1, b - t));
    for (final m in [...masquesAuto(zone), ...masques]) {
      final x1 = (m.left.clamp(0.0, 1.0) * z.width).floor(), y1 = (m.top.clamp(0.0, 1.0) * z.height).floor();
      final x2 = (m.right.clamp(0.0, 1.0) * z.width).ceil(), y2 = (m.bottom.clamp(0.0, 1.0) * z.height).ceil();
      if (x2 > x1 && y2 > y1) img.fillRect(z, x1: x1, y1: y1, x2: x2 - 1, y2: y2 - 1, color: img.ColorRgb8(0, 0, 0));
    }
    if (math.max(z.width, z.height) > coteMax) {
      z = z.width >= z.height ? img.copyResize(z, width: coteMax) : img.copyResize(z, height: coteMax);
    }
    // Nouvelle image sans aucune métadonnée (l'EXIF de la photo d'origine n'est jamais recopié).
    final propre = img.Image(width: z.width, height: z.height, numChannels: 3);
    for (final p in z) {
      propre.setPixelRgb(p.x, p.y, p.r, p.g, p.b);
    }
    propre.exif = img.ExifData();
    return img.encodeJpg(propre, quality: qualite);
  }

  /// Le JPEG contient un bloc EXIF (APP1 « Exif »).
  static bool contientExif(Uint8List jpeg) {
    for (var i = 2; i + 10 < jpeg.length && i < 1 << 16;) {
      if (jpeg[i] != 0xFF) return false;
      final marqueur = jpeg[i + 1];
      if (marqueur == 0xDA) return false; // début des données image
      final longueur = (jpeg[i + 2] << 8) | jpeg[i + 3];
      if (marqueur == 0xE1 && String.fromCharCodes(jpeg.sublist(i + 4, i + 8)) == 'Exif') return true;
      i += 2 + longueur;
    }
    return false;
  }
}
