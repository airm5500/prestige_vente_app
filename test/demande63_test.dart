// UNITAIRES — 4.15.1 : réponse du serveur à la demande 63 (correctif/demande63-1911, bb6b4604), données FICTIVES :
//  - PNG du serveur en NIVEAUX DE GRIS → 1 bit (seuil) : largeurs 384 / 576, raster GS v 0 (octets par ligne, bandes),
//    QR relu module par module, aucun point isolé (un tramage en sème : choix du seuil), texte gardé, transparence ;
//  - P_REMISE_VENTE : présent / absent, serveur ancien / serveur avec la demande 63 (preuve jamais tirée d'une absence) ;
//  - « sans remise » : "0" seulement sur un serveur qui le connaît, null sinon.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:prestige_vente_app/droits/droits_vente.dart';
import 'package:prestige_vente_app/services/ticket_1bit.dart';
import 'package:prestige_vente_app/ventes/common/remise_vente.dart';
import 'package:qr/qr.dart';

import 'outils/demande63_fictive.dart';

/// Points noirs sans aucun voisin noir (ou blancs sans voisin blanc) : « poussière » sur le papier.
int pointsIsoles(bool Function(int x, int y) noir, int x0, int y0, int x1, int y1) {
  var n = 0;
  for (var y = y0 + 1; y < y1 - 1; y++) {
    for (var x = x0 + 1; x < x1 - 1; x++) {
      final v = noir(x, y);
      if (noir(x - 1, y) != v && noir(x + 1, y) != v && noir(x, y - 1) != v && noir(x, y + 1) != v) n++;
    }
  }
  return n;
}

/// Tramage Floyd-Steinberg (comparaison seulement : l'application ne l'utilise pas).
List<List<bool>> tramer(img.Image i) {
  final w = i.width, h = i.height;
  final e = [for (var y = 0; y < h; y++) [for (var x = 0; x < w; x++) img.getLuminanceNormalized(i.getPixel(x, y)) * 255.0]];
  final out = [for (var y = 0; y < h; y++) List.filled(w, false)];
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final v = e[y][x];
      final n = v < 128;
      out[y][x] = n;
      final err = v - (n ? 0 : 255);
      if (x + 1 < w) e[y][x + 1] += err * 7 / 16;
      if (y + 1 < h) {
        if (x > 0) e[y + 1][x - 1] += err * 3 / 16;
        e[y + 1][x] += err * 5 / 16;
        if (x + 1 < w) e[y + 1][x + 1] += err / 16;
      }
    }
  }
  return out;
}

void main() {
  group('Conversion niveaux de gris → 1 bit', () {
    for (final (mm, points) in [(58, 384), (80, 576)]) {
      test('$mm mm : $points points, ${points ~/ 8} octets par ligne, raster GS v 0 en bandes', () {
        final png = Demande63Fictive.ticketGris(points);
        final gris = img.decodePng(png)!;
        expect(gris.numChannels, 1, reason: 'PNG en niveaux de gris, comme le serveur');
        final valeurs = <int>{for (var y = 0; y < gris.height; y++) for (var x = 0; x < gris.width; x++) gris.getPixel(x, y).r.toInt()};
        expect(valeurs.where((v) => v > 0 && v < 255), isNotEmpty, reason: 'texte lissé : des gris intermédiaires');
        final r = Ticket1Bit.depuisPng(png, largeurMax: points)!;
        expect((r.largeur, r.hauteur, r.octetsParLigne), (points, gris.height, points ~/ 8));
        final esc = r.gsV0(bande: 100);
        var i = 0, lignes = 0;
        while (i < esc.length) {
          expect(esc.sublist(i, i + 4), [0x1D, 0x76, 0x30, 0x00]);
          expect(esc[i + 4] | esc[i + 5] << 8, points ~/ 8);
          final hb = esc[i + 6] | esc[i + 7] << 8;
          expect(hb, lessThanOrEqualTo(100));
          lignes += hb;
          i += 8 + hb * (points ~/ 8);
        }
        expect(i, esc.length);
        expect(lignes, r.hauteur);
        final sortie = img.decodePng(r.png())!;
        final couleurs = <int>{for (var y = 0; y < sortie.height; y++) for (var x = 0; x < sortie.width; x++) sortie.getPixel(x, y).r.toInt()};
        expect(couleurs.difference({0, 255}), isEmpty, reason: 'noir ou blanc seulement');
      });
    }

    test('QR à modules de 2,8 points (bords gris) : chaque module relu tel quel, aucun point isolé ; un tramage en sème', () {
      final q = QrImage(QrCode.fromData(data: 'REF-FICT-000123', errorCorrectLevel: QrErrorCorrectLevel.M));
      const x0 = 7.3, y0 = 5.6, module = 2.8;
      final n = q.moduleCount;
      final cote = (n * module + 20).ceil();
      final g = img.Image(width: cote, height: cote, numChannels: 1);
      img.fill(g, color: img.ColorUint8.rgb(255, 255, 255));
      Demande63Fictive.dessinerQr(g, q, x0, y0, module);
      final gris = <int>{for (var y = 0; y < cote; y++) for (var x = 0; x < cote; x++) g.getPixel(x, y).r.toInt()};
      expect(gris.where((v) => v > 0 && v < 255), isNotEmpty, reason: 'bords de modules gris');
      final r = Ticket1Bit.depuisImage(g);
      for (var l = 0; l < n; l++) {
        for (var c = 0; c < n; c++) {
          final p = Demande63Fictive.centreModule(x0, y0, module, l, c);
          expect(r.noir(p.x, p.y), q.isDark(l, c), reason: 'module $l,$c');
        }
      }
      final xa = x0.floor(), ya = y0.floor(), xb = (x0 + n * module).ceil(), yb = (y0 + n * module).ceil();
      expect(pointsIsoles(r.noir, xa, ya, xb, yb), 0, reason: 'seuil : modules pleins, bords nets');
      final t = tramer(g);
      expect(pointsIsoles((x, y) => t[y][x], xa, ya, xb, yb), greaterThan(0), reason: 'tramage : points isolés (QR flou)');
    });

    test('texte lissé : encre gardée (±25 %), aucune ligne de texte perdue', () {
      final png = Demande63Fictive.ticketGris(384);
      final g = img.decodePng(png)!;
      final r = Ticket1Bit.depuisPng(png)!;
      var encre = 0.0;
      for (var y = 0; y < g.height; y++) {
        for (var x = 0; x < g.width; x++) {
          encre += 1 - g.getPixel(x, y).r / 255;
        }
      }
      expect(r.pointsNoirs, inInclusiveRange(encre * 0.75, encre * 1.25));
      // chaque bande de 26 points (une ligne du ticket fictif) garde des points noirs
      for (var b = 0; b < 9; b++) {
        var noirs = 0;
        for (var y = 6 + b * 26; y < 6 + (b + 1) * 26 && y < r.hauteur; y++) {
          for (var x = 0; x < r.largeur; x++) {
            if (r.noir(x, y)) noirs++;
          }
        }
        expect(noirs, greaterThan(0), reason: 'ligne $b');
      }
    });

    test('transparence posée sur du blanc ; couleur ramenée à la luminance ; seuil à 128', () {
      final i = img.Image(width: 16, height: 2, numChannels: 4);
      for (var x = 0; x < 16; x++) {
        i.setPixelRgba(x, 0, 0, 0, 0, 0); // noir transparent → blanc
        i.setPixelRgba(x, 1, x * 16, x * 16, x * 16, 255);
      }
      final r = Ticket1Bit.depuisPng(Uint8List.fromList(img.encodePng(i)))!;
      expect([for (var x = 0; x < 16; x++) r.noir(x, 0)], everyElement(isFalse));
      expect([for (var x = 0; x < 16; x++) r.noir(x, 1)], [for (var x = 0; x < 16; x++) x * 16 < Ticket1Bit.seuil]);
    });

    test('image plus large que le papier ou illisible : refusée (jamais réduite)', () {
      final png = Demande63Fictive.ticketGris(576);
      expect(Ticket1Bit.depuisPng(png, largeurMax: 384), isNull);
      expect(Ticket1Bit.depuisPng(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])), isNull);
    });
  });

  group('P_REMISE_VENTE (demande 63, point 2)', () {
    test('serveur ancien : droit absent de toutes les listes → remise proposée (comme 4.15.0), "0" jamais envoyé', () {
      final d = DroitsVente()..fixer({'P_SM_VENTE'});
      expect(d.controle(droitRemiseVente), isFalse);
      expect(remiseAutorisee(d), isTrue, reason: 'absence non probante');
      expect(sansRemiseParZero(d), isFalse);
      expect(remiseIdEnvoye(null, d), isNull);
      expect(remiseIdEnvoye(RemiseOption.sansRemise, d), isNull);
      d.fixer(null);
      expect(remiseAutorisee(d), isTrue);
    });

    test('serveur avec la demande 63 : droit présent → remise, et le serveur est prouvé pour tous les comptes suivants', () {
      final d = DroitsVente()..fixer({'P_SM_VENTE', droitRemiseVente}, utilisateur: 'compte.a');
      expect(remiseAutorisee(d), isTrue);
      expect(sansRemiseParZero(d), isTrue);
      d.fixer({'P_SM_VENTE'}, utilisateur: 'compte.b');
      expect(remiseAutorisee(d), isFalse, reason: 'droits connus, serveur qui contrôle le droit, droit absent');
      d.oublierControles();
      expect(remiseAutorisee(d), isTrue, reason: 'autre serveur : preuve oubliée');
    });

    test('preuve par la route image (sans 403) : droits connus sans le droit → masquée ; droits inconnus → proposée', () {
      final d = DroitsVente()..fixer({'P_SM_VENTE'});
      d.controleConstate(droitRemiseVente);
      expect(remiseAutorisee(d), isFalse);
      d.fixer(null);
      expect(remiseAutorisee(d), isTrue, reason: 'droits non lus : le serveur reste juge');
    });

    test('403 interdit : masquée pour ce compte, même droits non lus ; oublié au changement de compte', () {
      final d = DroitsVente()..fixer(null, utilisateur: 'compte.a');
      d.refusConstate(droitRemiseVente);
      expect(remiseAutorisee(d), isFalse);
      expect(sansRemiseParZero(d), isTrue);
      d.fixer(null, utilisateur: 'compte.b');
      expect(remiseAutorisee(d), isTrue);
    });
  });

  group('« Sans remise » (demande 63, point 3)', () {
    test('"0" seulement sur un serveur qui le connaît ; null sinon ; remise choisie envoyée telle quelle', () {
      final ancien = DroitsVente()..fixer({'P_SM_VENTE'});
      final nouveau = DroitsVente()..fixer({'P_SM_VENTE', droitRemiseVente});
      const r = RemiseOption(id: 'REM-FICT-10', nom: 'REMISE FICTIVE 10 %');
      expect(remiseIdEnvoye(r, ancien), 'REM-FICT-10');
      expect(remiseIdEnvoye(r, nouveau), 'REM-FICT-10');
      expect(remiseIdEnvoye(null, ancien), isNull);
      expect(remiseIdEnvoye(null, nouveau), '0');
      expect(remiseIdEnvoye(RemiseOption.sansRemise, nouveau), '0');
      expect(remiseIdRetenue('0'), isNull);
      expect(remiseIdRetenue(null), isNull);
      expect(remiseIdRetenue('REM-FICT-10'), 'REM-FICT-10');
    });

    test('« SANS REMISE » de la liste du serveur (id null) jamais pris pour une remise', () {
      expect(RemiseOption.depuisJson({'lgREMISEID': null, 'strNAME': 'SANS REMISE'}), isNull);
      expect(RemiseOption.sansRemise.id, '0');
    });
  });
}
