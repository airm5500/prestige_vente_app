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
// 5.4.0 : contraste « Renforcé » (par défaut) : seuil 160 et traits verticaux d'un point doublés (voir
// [Ticket1Bit.renforcer]) ; « Normal » : rendu d'avant (seuil 128).
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

/// 5.4.0 — « Contraste d'impression » (Réglages › Impression) : rendu des tickets dessinés par le serveur.
enum ContrasteImpression {
  /// Seuil 128, rien d'autre : rendu de la 4.15.1 à la 5.3.0.
  normal,

  /// Seuil 160 et traits verticaux d'un seul point doublés (voir [Ticket1Bit.renforcer]). Par défaut.
  renforce,
}

class Ticket1Bit {
  Ticket1Bit._();

  /// Luminance (0-255) en dessous de laquelle un point est imprimé.
  static const int seuil = 128;

  /// 5.4.0 : seuil du contraste renforcé (le bord lissé des lettres fines compte davantage).
  static const int seuilRenforce = 160;

  /// 5.4.0 : une colonne noire d'au moins ce nombre de points (barre du code-barres, cadre) n'est jamais épaissie,
  /// ni ses voisines : les barres et les espaces du code-barres gardent leur largeur exacte (lecture du code).
  static const int hauteurProtegee = 32;

  /// Convertit un PNG (niveaux de gris, couleur, avec ou sans transparence) en 1 bit. null : PNG illisible, ou plus
  /// large que [largeurMax] points (jamais réduit : une image réduite ne serait plus celle du serveur).
  static Raster1Bit? depuisPng(Uint8List png,
      {int? largeurMax, int seuilNoir = seuil, ContrasteImpression contraste = ContrasteImpression.normal}) {
    final img.Image? i;
    try {
      i = img.decodePng(png);
    } catch (_) {
      return null;
    }
    if (i == null || i.width <= 0 || i.height <= 0) return null;
    if (largeurMax != null && i.width > largeurMax) return null;
    return depuisImage(i, seuilNoir: seuilNoir, contraste: contraste);
  }

  static Raster1Bit depuisImage(img.Image i, {int seuilNoir = seuil, ContrasteImpression contraste = ContrasteImpression.normal}) {
    final w = i.width, h = i.height;
    final n = (w + 7) >> 3;
    final renforce = contraste == ContrasteImpression.renforce;
    final s = renforce && seuilNoir == seuil ? seuilRenforce : seuilNoir;
    final gris = i.hasPalette ? i.palette!.numChannels <= 2 : i.numChannels <= 2;
    // Points noirs (1 octet par point) : au seuil, puis renforcés au besoin.
    final noir = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      final base = y * w;
      for (var x = 0; x < w; x++) {
        final p = i.getPixel(x, y);
        // luminance 0..1 (un canal : le gris lui-même ; getLuminance lirait vert et bleu à 0 et noircirait tout),
        // transparence posée sur du blanc
        final l = gris ? p.rNormalized.toDouble() : (0.299 * p.rNormalized + 0.587 * p.gNormalized + 0.114 * p.bNormalized);
        final a = i.hasAlpha ? p.aNormalized.toDouble() : 1.0;
        final v = (l * a + (1 - a)) * 255;
        if (v < s) noir[base + x] = 1;
      }
    }
    final points = renforce ? renforcer(noir, w, h) : noir;
    final out = Uint8List(n * h);
    for (var y = 0; y < h; y++) {
      final base = y * n, ligne = y * w;
      for (var x = 0; x < w; x++) {
        if (points[ligne + x] != 0) out[base + (x >> 3)] |= 0x80 >> (x & 7);
      }
    }
    return Raster1Bit(w, h, out);
  }

  /// 5.4.0 — retour du pharmacien (SUNMI V3) : sur le ticket du serveur, les textes en police normale (« Matricule
  /// assuré », « Bénéficiaire », « Bon N° », « Part du client », organismes, « 1 ligne · 1 article », « Total »)
  /// sortaient FINS et pâles, comme tramés, alors que les gras passaient bien. Le serveur les dessine en NOIR
  /// (RenduTicket : Color.BLACK, police « Arial Narrow » de 8 points en 58 mm, lissée), mais à 203 dpi un trait vertical
  /// de cette police fait 1,5 point environ : au seuil 128, les trois quarts des traits verticaux de ces textes ne
  /// gardent qu'UN point de large (mesuré sur un ticket fictif dessiné par le code du serveur), et une colonne d'un
  /// seul point chauffe mal sur la tête thermique (trait gris, pointillé).
  ///
  /// Renforcement (sans redimensionner : l'image reste à la largeur exacte de la tête) : tout trait horizontal d'un
  /// seul point noir (vertical fin) est doublé d'un point à DROITE, seulement si le point suivant est blanc (deux
  /// lettres ne se touchent jamais : un point blanc reste entre elles). Les colonnes noires d'au moins
  /// [hauteurProtegee] points (barres du code-barres, bords du cadre) et leurs voisines ne sont jamais touchées : le
  /// code-barres garde ses largeurs (vérifié décodable). Les traits horizontaux ne sont pas épaissis (les petites
  /// boucles des lettres « e », « a » resteraient ouvertes).
  static Uint8List renforcer(Uint8List noir, int w, int h) {
    // Hauteur de la colonne noire qui passe par chaque point.
    final protege = Uint8List(w * h);
    for (var x = 0; x < w; x++) {
      var y = 0;
      while (y < h) {
        if (noir[y * w + x] == 0) {
          y++;
          continue;
        }
        var y1 = y;
        while (y1 < h && noir[y1 * w + x] != 0) {
          y1++;
        }
        if (y1 - y >= hauteurProtegee) {
          for (var k = y; k < y1; k++) {
            protege[k * w + x] = 1;
          }
        }
        y = y1;
      }
    }
    final out = Uint8List.fromList(noir);
    for (var y = 0; y < h; y++) {
      final l = y * w;
      for (var x = 0; x < w - 1; x++) {
        final i = l + x;
        if (noir[i] == 0 || protege[i] != 0) continue;
        if (x > 0 && noir[i - 1] != 0) continue; // trait d'au moins deux points : inchangé
        if (noir[i + 1] != 0) continue;
        if (x + 2 < w && (noir[i + 2] != 0 || protege[i + 2] != 0)) continue; // garder un blanc avant le trait suivant
        out[i + 1] = 1;
      }
    }
    return out;
  }
}
