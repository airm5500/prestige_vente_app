// lib/services/ticket_1bit.dart
// 4.15.1 — Conversion du ticket dessiné par le serveur en NOIR ET BLANC 1 bit (réponse du serveur à la demande 63,
// branche correctif/demande63-1911, bb6b4604).
//
// Le serveur renvoie un PNG en NIVEAUX DE GRIS (BufferedImage TYPE_BYTE_GRAY, fond blanc, texte lissé :
// RenduTicket.imageImprimante), et non un PNG 1 bit comme le disait la demande. Une imprimante thermique n'imprime
// qu'un point noir ou rien : l'application convertit donc chaque image en 1 bit avant de l'envoyer en raster ESC/POS
// `GS v 0` (imprimante intégrée Sunmi et imprimantes externes de PrestigePOS, même conversion).
//
// Choix : SEUIL fixe (luminance < 128 → noir), pas de tramage. Le serveur ne dessine que du texte (lissé), des traits
// et le QR / code-barres (formes pleines, sans lissage) : un seuil garde des bords nets et des modules de QR pleins,
// alors qu'un tramage (Floyd-Steinberg…) sème des points isolés autour des lettres et dans les modules du QR, ce qui
// les rend flous sur le papier (test/demande63_test.dart : QR relu module par module, aucun point isolé). Les gris du
// lissage au bord des lettres tombent d'un côté ou de l'autre du seuil : traits pleins, épaisseur conservée à un point
// près. Transparence éventuelle : posée sur fond blanc.
//
// Aucun contenu de ticket n'est lu ni écrit dans un journal : seuls des points noirs ou blancs sont manipulés.
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Image 1 bit : lignes de `(largeur + 7) ~/ 8` octets, bit de poids fort à gauche, 1 = point noir (format raster
/// de `GS v 0`).
class Raster1Bit {
  final int largeur;
  final int hauteur;
  final Uint8List octets;
  Raster1Bit(this.largeur, this.hauteur, this.octets);

  int get octetsParLigne => (largeur + 7) >> 3;

  bool noir(int x, int y) => (octets[y * octetsParLigne + (x >> 3)] & (0x80 >> (x & 7))) != 0;

  /// Matrice [y][x] (true = noir).
  List<List<bool>> matrice() => [
        for (var y = 0; y < hauteur; y++) [for (var x = 0; x < largeur; x++) noir(x, y)],
      ];

  /// Nombre de points noirs.
  int get pointsNoirs {
    var n = 0;
    for (final o in octets) {
      var v = o;
      while (v != 0) {
        n += v & 1;
        v >>= 1;
      }
    }
    return n;
  }

  /// Commandes `GS v 0` (mode normal), en bandes de [bande] lignes au plus (certaines imprimantes refusent une
  /// image trop haute en une seule commande ; les bandes s'impriment sans espace entre elles).
  Uint8List gsV0({int bande = 256}) {
    final b = BytesBuilder(copy: false);
    final n = octetsParLigne;
    for (var y0 = 0; y0 < hauteur; y0 += bande) {
      final h = (hauteur - y0) < bande ? hauteur - y0 : bande;
      b.add([0x1D, 0x76, 0x30, 0x00, n & 0xFF, (n >> 8) & 0xFF, h & 0xFF, (h >> 8) & 0xFF]);
      b.add(Uint8List.sublistView(octets, y0 * n, (y0 + h) * n));
    }
    return b.takeBytes();
  }

  /// PNG noir et blanc (aperçu, captures).
  Uint8List png() {
    final i = img.Image(width: largeur, height: hauteur, numChannels: 1);
    for (var y = 0; y < hauteur; y++) {
      for (var x = 0; x < largeur; x++) {
        final v = noir(x, y) ? 0 : 255;
        i.setPixelRgb(x, y, v, v, v);
      }
    }
    return Uint8List.fromList(img.encodePng(i));
  }
}

class Ticket1Bit {
  Ticket1Bit._();

  /// Luminance (0-255) en dessous de laquelle un point est imprimé.
  static const int seuil = 128;

  /// Convertit un PNG (niveaux de gris, couleur, avec ou sans transparence) en 1 bit. null : PNG illisible, ou plus
  /// large que [largeurMax] points (jamais réduit : une image réduite ne serait plus celle du serveur).
  static Raster1Bit? depuisPng(Uint8List png, {int? largeurMax, int seuilNoir = seuil}) {
    final img.Image? i;
    try {
      i = img.decodePng(png);
    } catch (_) {
      return null;
    }
    if (i == null || i.width <= 0 || i.height <= 0) return null;
    if (largeurMax != null && i.width > largeurMax) return null;
    return depuisImage(i, seuilNoir: seuilNoir);
  }

  static Raster1Bit depuisImage(img.Image i, {int seuilNoir = seuil}) {
    final w = i.width, h = i.height;
    final n = (w + 7) >> 3;
    final gris = i.hasPalette ? i.palette!.numChannels <= 2 : i.numChannels <= 2;
    final out = Uint8List(n * h);
    for (var y = 0; y < h; y++) {
      final base = y * n;
      for (var x = 0; x < w; x++) {
        final p = i.getPixel(x, y);
        // luminance 0..1 (un canal : le gris lui-même ; getLuminance lirait vert et bleu à 0 et noircirait tout),
        // transparence posée sur du blanc
        final l = gris ? p.rNormalized.toDouble() : (0.299 * p.rNormalized + 0.587 * p.gNormalized + 0.114 * p.bNormalized);
        final a = i.hasAlpha ? p.aNormalized.toDouble() : 1.0;
        final v = (l * a + (1 - a)) * 255;
        if (v < seuilNoir) out[base + (x >> 3)] |= 0x80 >> (x & 7);
      }
    }
    return Raster1Bit(w, h, out);
  }
}
