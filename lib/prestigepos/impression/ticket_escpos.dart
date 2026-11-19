// lib/prestigepos/impression/ticket_escpos.dart
// PrestigePOS — ticket de la borne en ESC/POS : MÊME contenu et même ordre que le ticket Sunmi de la borne
// (ReceiptService.printBorneTicket) : officine, titre, numéro en grand, lignes produits (ou ticket discret)
// et total (BorneTicket.lignes, mises en page 32 / 48 colonnes), QR (ou code-barres) de la référence,
// référence, « Présentez ce ticket à la caisse », date.
import 'dart:typed_data';

import 'package:prestige_vente_app/borne/borne_ticket.dart';
import 'package:prestige_vente_app/prestigepos/impression/escpos.dart';
import 'package:prestige_vente_app/prestigepos/impression/imprimante_reglages.dart';
import 'package:prestige_vente_app/services/ticket_1bit.dart';
import 'package:prestige_vente_app/services/ticket_serveur.dart';

class TicketEscPos {
  TicketEscPos._();

  /// Taille du module QR : 6 points en 58 mm (≈ 2,5 cm pour une référence de 14 chiffres), 8 en 80 mm.
  static int moduleQr(int papier) => papier == 80 ? 8 : 6;

  /// Octets du ticket [t] pour l'imprimante [c] (le ticket est mis en page pour [c].papier).
  static Uint8List ticket(BorneTicket t, ImprimanteConfig c) {
    final e = EscPos(papier: c.papier, jeu: c.jeu)..initialiser();
    e
      ..aligner(1)
      ..gras(true)
      ..taille(hauteur: 2);
    for (final l in _couper(t.officine.toUpperCase(), e.colonnes)) {
      e.ligne(l);
    }
    e
      ..taille()
      ..ligne(t.titre)
      ..taille(largeur: 2, hauteur: 2)
      ..ligne(c.jeu == JeuCaracteres.pc858 ? 'N° ${t.prevente.numero}' : 'No ${t.prevente.numero}')
      ..taille()
      ..gras(false)
      ..aligner(0);
    for (final l in t.lignes) {
      e.ligne(l);
    }
    e
      ..aligner(1)
      ..avancer(1);
    if (t.codeType == 'QR_CODE') {
      e.qr(t.prevente.reference, mode: c.qr, module: moduleQr(c.papier));
    } else {
      e.codeBarres(t.prevente.reference);
    }
    e.ligne(t.prevente.reference);
    e
      ..gras(true)
      ..ligne(t.invitationTexte)
      ..gras(false)
      ..ligne(t.date)
      ..avancer(4);
    if (c.coupe) e.couper();
    return e.octets;
  }

  /// 1.12.0 : tickets dessinés par le serveur (384 / 576 points) en raster GS v 0, dans l'ordre, une coupe entre deux
  /// tickets si l'imprimante coupe. null : image illisible ou plus large que le papier (gabarit local).
  /// 1.13.1 (demande 63) : le PNG du serveur est en NIVEAUX DE GRIS ; conversion en 1 bit partagée avec Prestige Mobile
  /// (lib/services/ticket_1bit.dart, seuil 128). Avant, un PNG gris à un canal sortait entièrement noir (la luminance
  /// de la bibliothèque `image` y lit vert et bleu à 0).
  static Uint8List? images(List<TicketImage> tickets, ImprimanteConfig c) {
    final e = EscPos(papier: c.papier, jeu: c.jeu)..initialiser();
    for (final t in tickets) {
      final m = matricePng(t.png, e.points);
      if (m == null) return null;
      e
        ..aligner(0)
        ..image(m)
        ..avancer(4);
      if (c.coupe) e.couper();
    }
    return e.octets;
  }

  /// Matrice noir / blanc d'un PNG (gris, couleur ou transparent ; seuil 128), null si illisible ou plus large que
  /// [points].
  static List<List<bool>>? matricePng(Uint8List png, int points) => Ticket1Bit.depuisPng(png, largeurMax: points)?.matrice();

  /// Ticket d'essai (« Test d'impression ») : largeur, accents, QR.
  static Uint8List essai(ImprimanteConfig c, {String officine = '', DateTime? at}) {
    final e = EscPos(papier: c.papier, jeu: c.jeu)..initialiser();
    final d = at ?? DateTime.now();
    String deux(int v) => v.toString().padLeft(2, '0');
    e
      ..aligner(1)
      ..gras(true)
      ..taille(hauteur: 2)
      ..ligne('PRESTIGEPOS')
      ..taille()
      ..ligne('TEST D\'IMPRESSION')
      ..gras(false);
    if (officine.isNotEmpty) e.ligne(officine.toUpperCase());
    e
      ..aligner(0)
      ..ligne(List.filled(e.colonnes, '-').join())
      ..ligne('Papier ${c.papier} mm : ${e.colonnes} caracteres')
      ..ligne('${'1234567890' * (e.colonnes ~/ 10)}${'1234567890'.substring(0, e.colonnes % 10)}')
      ..ligne('Accents : é è ê à ç ù')
      ..ligne(List.filled(e.colonnes, '-').join())
      ..aligner(1)
      ..qr('PRESTIGEPOS-TEST', mode: c.qr, module: moduleQr(c.papier))
      ..ligne('Si ce ticket est lisible,')
      ..ligne('l\'imprimante est prete.')
      ..ligne('${deux(d.day)}/${deux(d.month)}/${d.year} ${deux(d.hour)}:${deux(d.minute)}')
      ..avancer(4);
    if (c.coupe) e.couper();
    return e.octets;
  }

  /// Texte coupé en lignes de [cols] caractères au plus (coupure à un espace si possible).
  static List<String> _couper(String s, int cols) {
    final t = s.trim();
    if (t.length <= cols) return [t];
    final out = <String>[];
    var reste = t;
    while (reste.length > cols) {
      var i = reste.lastIndexOf(' ', cols);
      if (i <= 0) i = cols;
      out.add(reste.substring(0, i).trim());
      reste = reste.substring(i).trim();
    }
    if (reste.isNotEmpty) out.add(reste);
    return out;
  }
}
