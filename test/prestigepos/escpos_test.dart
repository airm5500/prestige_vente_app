// PrestigePOS — génération ESC/POS du ticket de la borne, OCTET PAR OCTET, en 58 et 80 mm.
// Références : test/prestigepos/references/ticket_{58,80}_{qr,image,codebarres}.hex (une commande par ligne,
// commentée). Pour les régénérer après un changement VOULU de la mise en page :
//   MAJ_REFERENCES=1 flutter test test/prestigepos/escpos_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/borne/borne_service.dart';
import 'package:prestige_vente_app/borne/borne_ticket.dart';
import 'package:prestige_vente_app/prestigepos/impression/escpos.dart';
import 'package:prestige_vente_app/prestigepos/impression/imprimante_reglages.dart';
import 'package:prestige_vente_app/prestigepos/impression/ticket_escpos.dart';
import 'package:prestige_vente_app/services/ticket_prevente.dart';

final _maj = Platform.environment.containsKey('MAJ_REFERENCES');

SaleItemDetail _l(String nom, int qte, int pu) => SaleItemDetail(
    lgPREENREGISTREMENTDETAILID: '', lgFAMILLEID: nom, strNAME: nom, intCIP: '', intQUANTITY: qte, intPRICEUNITAIR: pu, intPRICE: qte * pu, strREF: '');

/// Ticket type : 3 produits (un nom long sur deux lignes), total 9 900 F, référence de 14 chiffres.
BorneTicket ticketType({int largeur = 58, bool discret = false, String codeType = 'QR_CODE'}) => BorneTicket(
      officine: 'Pharmacie des Palmiers',
      largeur: largeur,
      discret: discret,
      codeType: codeType,
      prevente: BornePrevente(
        venteId: 'V1',
        reference: '20261014000127',
        total: 9900,
        lignes: [
          _l('DOLIPRANE 1000MG CP B/8', 2, 1500),
          _l('VITAMINE C UPSA 1000MG CPR EFFERVESCENT B/20', 1, 2100),
          _l('GEL INTIME SAFORELLE 250ML', 1, 4800),
        ],
        at: DateTime(2026, 10, 14, 10, 42),
      ),
    );

/// Découpe les octets en commandes lisibles (une par ligne) : « 1B 40  ; ESC @ », texte entre guillemets.
String dump(Uint8List o) {
  final out = StringBuffer();
  var i = 0;
  String hex(Iterable<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
  void cmd(int n, String c) {
    out.writeln('${hex(o.sublist(i, i + n))}  ; $c');
    i += n;
  }

  while (i < o.length) {
    final b = o[i];
    if (b == 0x1B && o[i + 1] == 0x40) {
      cmd(2, 'ESC @ initialiser');
    } else if (b == 0x1B && o[i + 1] == 0x74) {
      cmd(3, 'ESC t page de code');
    } else if (b == 0x1B && o[i + 1] == 0x61) {
      cmd(3, 'ESC a alignement ${o[i + 2]}');
    } else if (b == 0x1B && o[i + 1] == 0x45) {
      cmd(3, 'ESC E gras ${o[i + 2]}');
    } else if (b == 0x1B && o[i + 1] == 0x64) {
      cmd(3, 'ESC d avance ${o[i + 2]}');
    } else if (b == 0x1D && o[i + 1] == 0x21) {
      cmd(3, 'GS ! taille');
    } else if (b == 0x1D && o[i + 1] == 0x56) {
      cmd(4, 'GS V coupe');
    } else if (b == 0x1D && o[i + 1] == 0x28 && o[i + 2] == 0x6B) {
      final n = o[i + 3] | (o[i + 4] << 8);
      cmd(5 + n, 'GS ( k QR fonction ${o[i + 6]}');
    } else if (b == 0x1D && (o[i + 1] == 0x68 || o[i + 1] == 0x77 || o[i + 1] == 0x48)) {
      cmd(3, 'GS ${String.fromCharCode(o[i + 1])} code-barres');
    } else if (b == 0x1D && o[i + 1] == 0x6B) {
      cmd(4 + o[i + 3], 'GS k CODE128');
    } else if (b == 0x1D && o[i + 1] == 0x76) {
      final w = o[i + 4] | (o[i + 5] << 8), h = o[i + 6] | (o[i + 7] << 8);
      out.writeln('${hex(o.sublist(i, i + 8))}  ; GS v 0 image $w octets x $h lignes');
      i += 8;
      out.writeln('… ${w * h} octets d\'image, empreinte ${o.sublist(i, i + w * h).fold<int>(0, (s, x) => (s * 31 + x) & 0x7FFFFFFF)}');
      i += w * h;
    } else {
      final fin = o.indexOf(0x0A, i);
      final t = o.sublist(i, fin);
      out.writeln('${hex(t)} 0A  ; "${latin1.decode(t)}"');
      i = fin + 1;
    }
  }
  return out.toString();
}

/// Lignes de texte du ticket (entre les commandes).
List<String> textes(Uint8List o) =>
    [for (final l in dump(o).split('\n')) if (l.contains('; "')) l.substring(l.indexOf('; "') + 3, l.length - 1)];

void verifierReference(String nom, Uint8List o) {
  final f = File('test/prestigepos/references/$nom.hex');
  final d = dump(o);
  if (_maj || !f.existsSync()) {
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(d);
  }
  expect(d, f.readAsStringSync(), reason: '$nom : octets différents de la référence (MAJ_REFERENCES=1 si le changement est voulu)');
}

void main() {
  group('Ticket type ESC/POS', () {
    for (final papier in [58, 80]) {
      final cols = papier == 58 ? 32 : 48;
      final c = ImprimanteConfig(type: TypeImprimante.bluetooth, papier: papier);

      test('$papier mm : octets identiques à la référence', () {
        verifierReference('ticket_${papier}_qr', TicketEscPos.ticket(ticketType(largeur: papier), c));
        verifierReference('ticket_${papier}_image', TicketEscPos.ticket(ticketType(largeur: papier), c.copyWith(qr: ModeQr.image)));
        verifierReference('ticket_${papier}_codebarres', TicketEscPos.ticket(ticketType(largeur: papier, codeType: 'BARCODE'), c));
      });

      test('$papier mm : structure (initialisation, contenu du ticket borne, QR de la référence, coupe)', () {
        final o = TicketEscPos.ticket(ticketType(largeur: papier), c);
        expect(o.sublist(0, 2), [0x1B, 0x40], reason: 'ESC @ en tête');
        expect(o.sublist(o.length - 4), [0x1D, 0x56, 0x42, 0x00], reason: 'coupe partielle en fin');
        final t = textes(o);
        expect(t.first, 'PHARMACIE DES PALMIERS');
        expect(t, containsAllInOrder(['PRE-VENTE BORNE', 'No 0127', 'DOLIPRANE 1000MG CP B/8'.padRight(cols), '20261014000127',
          'Presentez ce ticket a la caisse', '14/10/2026 10:42']));
        expect(t.any((l) => l.startsWith('TOTAL A PAYER: 9 900 F')), isTrue, reason: 'total (espace insécable → espace)');
        // Aucune ligne de texte normal ne dépasse la largeur du papier.
        for (final l in t) {
          expect(l.length, lessThanOrEqualTo(cols), reason: '« $l » > $cols colonnes');
        }
        // QR natif : données = référence, module 6 (58 mm) / 8 (80 mm).
        final qr = [0x1D, 0x28, 0x6B, 17, 0x00, 0x31, 0x50, 0x30, ...ascii.encode('20261014000127')];
        expect(_contient(o, qr), isTrue, reason: 'stockage du QR');
        expect(_contient(o, [0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, papier == 58 ? 6 : 8]), isTrue, reason: 'taille du module');
        expect(_contient(o, [0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30]), isTrue, reason: 'impression du QR');
      });

      test('$papier mm : nom long sur deux lignes, coupé à un espace (comme le ticket Sunmi)', () {
        final t = textes(TicketEscPos.ticket(ticketType(largeur: papier), c));
        final i = t.indexWhere((l) => l.startsWith('VITAMINE C'));
        expect(i, greaterThan(0));
        if (papier == 58) {
          expect(t[i].trimRight(), 'VITAMINE C UPSA 1000MG CPR');
          expect(t[i + 1].trimRight(), 'EFFERVESCENT B/20');
        } else {
          expect(t[i].trimRight(), 'VITAMINE C UPSA 1000MG CPR EFFERVESCENT B/20');
        }
        expect(t.where((l) => l.trim().startsWith('1 x 2 100')).single.length, cols);
      });

      test('$papier mm : ticket discret (sans nom des produits)', () {
        final t = textes(TicketEscPos.ticket(ticketType(largeur: papier, discret: true), c));
        expect(t, contains('4 articles'));
        expect(t.any((l) => l.contains('DOLIPRANE')), isFalse);
      });
    }

    test('sans coupe : pas de GS V ; page PC858 : ESC t 19 et accents imprimés', () {
      final o = TicketEscPos.ticket(ticketType(), const ImprimanteConfig(type: TypeImprimante.reseau, hote: '1.2.3.4', coupe: false, jeu: JeuCaracteres.pc858));
      expect(_contient(o, [0x1D, 0x56]), isFalse);
      expect(o.sublist(0, 5), [0x1B, 0x40, 0x1B, 0x74, 19]);
      expect(_contient(o, [...ascii.encode('Pr'), 0x82, ...ascii.encode('sentez')]), isTrue, reason: 'é = 0x82 en PC858');
      expect(_contient(o, [0x4E, 0xF8, 0x20]), isTrue, reason: '« N° » : ° = 0xF8');
    });

    test('QR en image : GS v 0, 29 modules × 6 points = 174 points (22 octets par ligne)', () {
      final o = TicketEscPos.ticket(ticketType(), const ImprimanteConfig(type: TypeImprimante.usb, qr: ModeQr.image));
      final i = _index(o, [0x1D, 0x76, 0x30, 0x00]);
      expect(i, greaterThan(0));
      expect(o.sublist(i + 4, i + 8), [22, 0, 174, 0]);
      expect(_contient(o, [0x1D, 0x28, 0x6B]), isFalse, reason: 'pas de commande QR native');
    });

    test('code-barres CODE128 jeu B de la référence', () {
      final o = TicketEscPos.ticket(ticketType(codeType: 'BARCODE'), const ImprimanteConfig(type: TypeImprimante.bluetooth));
      expect(_contient(o, [0x1D, 0x6B, 0x49, 16, 0x7B, 0x42, ...ascii.encode('20261014000127')]), isTrue);
    });

    test('ticket d\'essai : largeur et règle de colonnes', () {
      for (final p in [58, 80]) {
        final t = textes(TicketEscPos.essai(ImprimanteConfig(type: TypeImprimante.reseau, papier: p), at: DateTime(2026, 10, 15, 9, 5)));
        final cols = p == 58 ? 32 : 48;
        expect(t, contains('Papier $p mm : $cols caracteres'));
        expect(t.where((l) => l.startsWith('1234567890')).single.length, cols);
        expect(t, contains('15/10/2026 09:05'));
      }
    });
  });

  group('Texte', () {
    test('translittération : accents, espaces insécables, signes inconnus', () {
      expect(EscPos.translitterer('Présentez à la caisse'), 'Presentez a la caisse');
      expect(EscPos.translitterer('1 200 F'), '1 200 F');
      expect(EscPos.translitterer('ŒUF « bio » → 2'), 'OEUF " bio " ? 2');
    });

    test('jeu ASCII : uniquement des octets imprimables', () {
      final o = EscPos.encoder('Crème été çà N°', JeuCaracteres.ascii);
      expect(o.every((b) => b >= 0x20 && b < 0x7F), isTrue);
      expect(ascii.decode(o), 'Creme ete ca No');
    });

    test('découpage des noms (TicketPrevente.nom, partagé avec le ticket Sunmi)', () {
      expect(TicketPrevente.nom('DOLIPRANE 1000MG CP B/8', 32), ['DOLIPRANE 1000MG CP B/8'.padRight(32)]);
      expect(TicketPrevente.nom('VITAMINE C UPSA 1000MG CPR EFFERVESCENT B/20', 32).map((l) => l.trimRight()),
          ['VITAMINE C UPSA 1000MG CPR', 'EFFERVESCENT B/20']);
      final tresLong = TicketPrevente.nom('A' * 40 + ' BBBBBBBBBB CCCCCCCCCC DDDDDDDDDD EEEEEEEEEE', 32);
      expect(tresLong.length, 2);
      expect(tresLong.last.trimRight().endsWith('..'), isTrue, reason: 'nom raccourci signalé');
      expect(tresLong.every((l) => l.length == 32), isTrue);
    });
  });
}

int _index(List<int> o, List<int> motif) {
  for (var i = 0; i + motif.length <= o.length; i++) {
    var ok = true;
    for (var j = 0; j < motif.length && ok; j++) {
      ok = o[i + j] == motif[j];
    }
    if (ok) return i;
  }
  return -1;
}

bool _contient(List<int> o, List<int> motif) => _index(o, motif) >= 0;
