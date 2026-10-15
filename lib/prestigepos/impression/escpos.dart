// lib/prestigepos/impression/escpos.dart
// PrestigePOS — générateur ESC/POS minimal, en Dart pur (aucune dépendance native) :
// commandes Epson standard reconnues par les imprimantes thermiques Bluetooth / USB / réseau du marché
// (Epson, Xprinter, Goojprt, Rongta, MUNBYN, HPRT…), papier 58 mm (384 points, 32 caractères en police A)
// ou 80 mm (576 points, 48 caractères).
//
// Choix : un générateur maison plutôt qu'un paquet (esc_pos_utils_plus…) pour
//  - des octets entièrement maîtrisés et vérifiés un par un dans les tests (test/prestigepos/escpos_test.dart) ;
//  - les accents : par défaut translittérés en ASCII (é → e), seul jeu lisible sur TOUTES les imprimantes ;
//    page de code PC858 (ESC t 19) en option pour les imprimantes qui la gèrent ;
//  - aucune dépendance supplémentaire (le QR « image » utilise le paquet `qr`, déjà présent via qr_flutter).
import 'dart:convert';
import 'dart:typed_data';

import 'package:qr/qr.dart';

/// Jeu de caractères envoyé à l'imprimante.
enum JeuCaracteres {
  /// Lettres accentuées remplacées (é → e) : lisible partout (par défaut).
  ascii,

  /// Page de code PC858 (ESC t 19) : accents imprimés si l'imprimante la gère.
  pc858,
}

/// Impression du QR code.
enum ModeQr {
  /// Commande QR native (GS ( k) : nette et rapide (la plupart des imprimantes récentes).
  natif,

  /// QR dessiné en image (GS v 0) : pour les imprimantes sans QR natif.
  image,
}

class EscPos {
  /// Largeur du papier : 58 ou 80 mm.
  final int papier;
  final JeuCaracteres jeu;
  final BytesBuilder _o = BytesBuilder(copy: false);

  EscPos({this.papier = 58, this.jeu = JeuCaracteres.ascii});

  /// Caractères par ligne en police A (12 × 24) : 32 en 58 mm, 48 en 80 mm.
  int get colonnes => papier == 80 ? 48 : 32;

  /// Points imprimables par ligne : 384 en 58 mm, 576 en 80 mm.
  int get points => papier == 80 ? 576 : 384;

  Uint8List get octets => _o.toBytes();

  void _c(List<int> b) => _o.add(b);

  // ---------------------------------------------------------------------------
  // Commandes
  // ---------------------------------------------------------------------------

  /// ESC @ (réinitialisation), puis page de code PC858 si demandée (ESC t 19).
  void initialiser() {
    _c(const [0x1B, 0x40]);
    if (jeu == JeuCaracteres.pc858) _c(const [0x1B, 0x74, 19]);
  }

  /// ESC a n : 0 gauche, 1 centre, 2 droite.
  void aligner(int n) => _c([0x1B, 0x61, n.clamp(0, 2)]);

  /// ESC E n : gras.
  void gras(bool actif) => _c([0x1B, 0x45, actif ? 1 : 0]);

  /// GS ! n : taille des caractères (largeur et hauteur, 1 à 8).
  void taille({int largeur = 1, int hauteur = 1}) => _c([0x1D, 0x21, ((largeur.clamp(1, 8) - 1) << 4) | (hauteur.clamp(1, 8) - 1)]);

  /// Texte suivi d'un saut de ligne.
  void ligne(String texte) {
    _c(encoder(texte, jeu));
    _c(const [0x0A]);
  }

  /// ESC d n : avance de n lignes.
  void avancer(int n) => _c([0x1B, 0x64, n.clamp(0, 255)]);

  /// GS V 66 0 : avance jusqu'au couteau puis coupe partielle (ignoré par les imprimantes sans couteau).
  void couper() => _c(const [0x1D, 0x56, 0x42, 0x00]);

  /// QR code de [donnees] (module de [module] points, correction M).
  void qr(String donnees, {ModeQr mode = ModeQr.natif, int module = 6}) {
    if (mode == ModeQr.image) {
      image(matriceQr(donnees), module: module);
      return;
    }
    final d = utf8.encode(donnees);
    final n = d.length + 3;
    _c([0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00]); // modèle 2
    _c([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, module.clamp(1, 16)]); // taille du module
    _c(const [0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x31]); // correction M
    _c([0x1D, 0x28, 0x6B, n & 0xFF, (n >> 8) & 0xFF, 0x31, 0x50, 0x30, ...d]); // données
    _c(const [0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30]); // impression
  }

  /// Code-barres CODE128 (jeu B) : GS h (hauteur), GS w (largeur), GS H 0 (sans texte), GS k 73.
  void codeBarres(String donnees, {int hauteur = 60, int largeur = 2}) {
    final d = ascii.encode(translitterer(donnees));
    final corps = [0x7B, 0x42, ...d]; // {B
    _c([0x1D, 0x68, hauteur.clamp(1, 255)]);
    _c([0x1D, 0x77, largeur.clamp(2, 6)]);
    _c(const [0x1D, 0x48, 0x00]);
    _c([0x1D, 0x6B, 0x49, corps.length, ...corps]);
  }

  /// Image noir et blanc (matrice [y][x], true = noir), agrandie [module] fois, en GS v 0 (mode raster normal).
  void image(List<List<bool>> m, {int module = 1}) {
    if (m.isEmpty) return;
    final h = m.length * module;
    final w = m.first.length * module;
    final octetsLigne = (w + 7) >> 3;
    _c([0x1D, 0x76, 0x30, 0x00, octetsLigne & 0xFF, (octetsLigne >> 8) & 0xFF, h & 0xFF, (h >> 8) & 0xFF]);
    final ligne = Uint8List(octetsLigne);
    for (var y = 0; y < h; y++) {
      ligne.fillRange(0, octetsLigne, 0);
      final src = m[y ~/ module];
      for (var x = 0; x < w; x++) {
        if (src[x ~/ module]) ligne[x >> 3] |= 0x80 >> (x & 7);
      }
      _c(Uint8List.fromList(ligne));
    }
  }

  // ---------------------------------------------------------------------------
  // Texte
  // ---------------------------------------------------------------------------

  /// Lettres accentuées → lettres simples ; espaces insécables (séparateur des milliers « 1 200 ») → espace ;
  /// tout autre signe hors ASCII imprimable → « ? ».
  static String translitterer(String s) {
    final b = StringBuffer();
    for (final r in s.runes) {
      final c = String.fromCharCode(r);
      if (r == 0x0A || (r >= 0x20 && r < 0x7F)) {
        b.write(c);
      } else {
        b.write(_ascii[c] ?? '?');
      }
    }
    return b.toString();
  }

  /// Octets du texte dans le jeu [jeu].
  static List<int> encoder(String s, JeuCaracteres jeu) {
    if (jeu == JeuCaracteres.ascii) return ascii.encode(translitterer(s));
    final out = <int>[];
    for (final r in s.runes) {
      final c = String.fromCharCode(r);
      if (r == 0x0A || (r >= 0x20 && r < 0x7F)) {
        out.add(r);
      } else if (_pc858.containsKey(c)) {
        out.add(_pc858[c]!);
      } else {
        out.addAll(ascii.encode(_ascii[c] ?? '?'));
      }
    }
    return out;
  }

  static const Map<String, String> _ascii = {
    'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', 'À': 'A', 'Â': 'A', 'Ä': 'A', 'Á': 'A',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'É': 'E', 'È': 'E', 'Ê': 'E', 'Ë': 'E',
    'î': 'i', 'ï': 'i', 'í': 'i', 'Î': 'I', 'Ï': 'I',
    'ô': 'o', 'ö': 'o', 'ó': 'o', 'Ô': 'O', 'Ö': 'O',
    'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u', 'Ù': 'U', 'Û': 'U', 'Ü': 'U',
    'ç': 'c', 'Ç': 'C', 'ñ': 'n', 'Ñ': 'N', 'ÿ': 'y',
    'œ': 'oe', 'Œ': 'OE', 'æ': 'ae', 'Æ': 'AE',
    '°': 'o', '€': 'EUR', '’': "'", '‘': "'", '«': '"', '»': '"', '“': '"', '”': '"',
    '–': '-', '—': '-', '…': '...', '·': '.', '×': 'x',
    ' ': ' ', ' ': ' ', ' ': ' ',
  };

  /// Page de code PC858 (multilingue latin + €).
  static const Map<String, int> _pc858 = {
    'Ç': 0x80, 'ü': 0x81, 'é': 0x82, 'â': 0x83, 'ä': 0x84, 'à': 0x85, 'ç': 0x87, 'ê': 0x88, 'ë': 0x89, 'è': 0x8A,
    'ï': 0x8B, 'î': 0x8C, 'Ä': 0x8E, 'É': 0x90, 'ô': 0x93, 'ö': 0x94, 'û': 0x96, 'ù': 0x97, 'Ö': 0x99, 'Ü': 0x9A,
    'á': 0xA0, 'í': 0xA1, 'ó': 0xA2, 'ú': 0xA3, 'ñ': 0xA4, 'Ñ': 0xA5, '«': 0xAE, '»': 0xAF, 'Á': 0xB5, 'Â': 0xB6,
    'À': 0xB7, '€': 0xD5, 'Ê': 0xD2, 'Ë': 0xD3, 'È': 0xD4, 'Î': 0xD7, 'Ï': 0xD8, 'Ô': 0xE2, 'Û': 0xEA, 'Ù': 0xEB,
    '°': 0xF8, '·': 0xFA,
  };

  /// Matrice du QR code (zone blanche de 4 modules autour), correction M.
  static List<List<bool>> matriceQr(String donnees) {
    final code = QrCode.fromData(data: donnees, errorCorrectLevel: QrErrorCorrectLevel.M);
    final img = QrImage(code);
    const marge = 4;
    final n = img.moduleCount + 2 * marge;
    return [
      for (var y = 0; y < n; y++)
        [
          for (var x = 0; x < n; x++)
            x >= marge && y >= marge && x < n - marge && y < n - marge && img.isDark(y - marge, x - marge)
        ]
    ];
  }
}
