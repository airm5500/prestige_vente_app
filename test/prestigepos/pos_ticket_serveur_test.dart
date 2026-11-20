// PrestigePOS 1.12.0 — ticket de la borne et Prestige Mobile 4.14.0 (données FICTIVES) :
//  - imprimante externe (Bluetooth, USB, réseau) : ticket de prévente DESSINÉ PAR LE SERVEUR (route image, quand elle
//    existe) envoyé en raster GS v 0 à la largeur de l'imprimante, coupe entre deux tickets ; route absente, image
//    illisible ou trop large, ticket payé ou discret : gabarit de la borne inchangé ;
//  - la borne ne propose jamais de remise ; la caisse a la remise de Prestige Mobile (fusion).
// 1.13.1 (demande 63) : PNG du serveur en NIVEAUX DE GRIS (un canal) converti en 1 bit par la conversion partagée :
// fond blanc gardé (l'ancienne lecture rendait tout noir), mêmes octets que Prestige Mobile.
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/borne/borne_ticket.dart';
import 'package:prestige_vente_app/prestigepos/impression/escpos.dart';
import 'package:prestige_vente_app/prestigepos/impression/imprimante_pos.dart';
import 'package:prestige_vente_app/prestigepos/impression/imprimante_reglages.dart';
import 'package:prestige_vente_app/prestigepos/impression/ticket_escpos.dart';
import 'package:prestige_vente_app/prestigepos/impression/transports.dart';
import 'package:prestige_vente_app/services/ticket_serveur.dart';

import 'package:image/image.dart' as img;
import 'package:prestige_vente_app/services/contraste_impression.dart';
import 'package:prestige_vente_app/services/ticket_1bit.dart';

import '../outils/demande63_fictive.dart';
import '../outils/remises_fictives.dart';
import 'escpos_test.dart' show ticketType;

const _bt = AppareilImprimante(nom: 'MTP-FICTIVE', adresse: '00:11:22:aa:bb:cc', appaire: true, imprimante: true);

class _Transport implements TransportImpression {
  final List<Uint8List> recus = [];
  @override
  Future<void> envoyer(Uint8List octets) async => recus.add(octets);
}

TicketImage _image(int largeur, {int hauteur = 24}) =>
    TicketImage(modele: 'PREVENTE', png: RemisesFictives.pngFictif(largeur, hauteur), largeurPoints: largeur, hauteurPoints: hauteur);

/// Position de la commande GS v 0 et ses dimensions (octets par ligne, hauteur).
List<(int, int)> _rasters(Uint8List o) => [
      for (var i = 0; i + 7 < o.length; i++)
        if (o[i] == 0x1D && o[i + 1] == 0x76 && o[i + 2] == 0x30 && o[i + 3] == 0x00) (o[i + 4] | (o[i + 5] << 8), o[i + 6] | (o[i + 7] << 8)),
    ];

void main() {
  group('Images du serveur en ESC/POS', () {
    test('58 mm : 384 points = 48 octets par ligne ; 80 mm : 576 = 72 ; deux tickets, deux coupes', () {
      final c58 = const ImprimanteConfig(type: TypeImprimante.bluetooth, bluetooth: _bt, papier: 58, coupe: true);
      final o = TicketEscPos.images([_image(384), _image(384, hauteur: 16)], c58)!;
      expect(_rasters(o), [(48, 24), (48, 16)]);
      expect(RegExp(String.fromCharCodes([0x1D, 0x56, 0x42])).allMatches(String.fromCharCodes(o)), hasLength(2));
      final c80 = const ImprimanteConfig(type: TypeImprimante.reseau, hote: '127.0.0.1', papier: 80);
      expect(_rasters(TicketEscPos.images([_image(576)], c80)!), [(72, 24)]);
    });

    test('image plus large que le papier ou illisible : null (gabarit de la borne)', () {
      const c58 = ImprimanteConfig(type: TypeImprimante.bluetooth, bluetooth: _bt, papier: 58);
      expect(TicketEscPos.images([_image(576)], c58), isNull);
      expect(TicketEscPos.images([TicketImage(modele: 'X', png: Uint8List.fromList([1, 2, 3]), largeurPoints: 384, hauteurPoints: 1)], c58), isNull);
      final m = TicketEscPos.matricePng(_image(384, hauteur: 9).png, 384)!;
      expect(m.first.every((p) => p), isTrue, reason: 'ligne noire');
      expect(m, hasLength(9));
      expect(m.first, hasLength(384));
    });
  });

  group('1.13.1 : PNG gris du serveur (demande 63)', () {
    for (final (papier, points) in [(58, 384), (80, 576)]) {
      test('$papier mm : PNG gris à un canal → raster de $points points, fond blanc, mêmes octets que Prestige Mobile', () {
        final png = Demande63Fictive.ticketGris(points, qr: 'REF-FICT-000123');
        final g = img.decodePng(png)!;
        expect(g.numChannels, 1);
        final c = ImprimanteConfig(type: TypeImprimante.reseau, hote: '127.0.0.1', papier: papier);
        final o = TicketEscPos.images([TicketImage(modele: 'PREVENTE', png: png, largeurPoints: points, hauteurPoints: g.height)], c)!;
        expect(_rasters(o), [(points ~/ 8, g.height)]);
        final m = TicketEscPos.matricePng(png, points)!;
        final noirs = m.fold<int>(0, (a, l) => a + l.where((p) => p).length);
        expect(noirs, lessThan(points * g.height ~/ 4), reason: 'fond blanc (pas un rectangle noir)');
        // 1.17.0 : même conversion que Prestige Mobile, au contraste du réglage (renforcé par défaut).
        final r = Ticket1Bit.depuisPng(png, largeurMax: points, contraste: ReglageContraste.courant.value)!;
        expect(noirs, r.pointsNoirs);
        // ancienne lecture (1.12.0) : luminance de la bibliothèque sur un PNG gris → presque tout noir
        final ancien = [for (var y = 0; y < g.height; y++) for (var x = 0; x < g.width; x++) img.getLuminanceNormalized(g.getPixel(x, y)) < 0.5]
            .where((p) => p)
            .length;
        expect(ancien, greaterThan(points * g.height * 9 ~/ 10));
      });
    }
  });

  group('ImprimantePos : ticket du serveur avant le gabarit', () {
    late _Transport transport;
    late ImprimantePos i;
    final demandes = <BorneTicket>[];
    List<TicketImage>? reponse;

    setUp(() {
      transport = _Transport();
      demandes.clear();
      reponse = null;
      i = ImprimantePos(config: () => const ImprimanteConfig(type: TypeImprimante.bluetooth, bluetooth: _bt, papier: 58), sunmi: () async => false, transport: (_) => transport)
        ..imagesServeur = (dio, t) async {
          demandes.add(t);
          return reponse;
        };
    });

    test('route présente : raster envoyé, à la largeur de l\'imprimante (ticket demandé en 58 mm)', () async {
      reponse = [_image(384)];
      expect(await i.imprimer(ticketType(largeur: 80)), isTrue);
      expect(demandes.single.largeur, 58);
      expect(_rasters(transport.recus.single), [(48, 24)]);
    });

    test('route absente : gabarit de la borne, octets identiques à avant', () async {
      expect(await i.imprimer(ticketType()), isTrue);
      expect(transport.recus.single, TicketEscPos.ticket(ticketType(), const ImprimanteConfig(type: TypeImprimante.bluetooth, bluetooth: _bt, papier: 58)));
    });

    test('ticket payé ou discret : jamais l\'image du serveur (ticketBorneServeur)', () async {
      final d = Dio();
      expect(await ticketBorneServeur(d, ticketType(discret: true)), isNull);
      final paye = BorneTicket(officine: 'P', prevente: ticketType().prevente, payePar: 'WAVE');
      expect(await ticketBorneServeur(d, paye), isNull);
    });

    test('le client de la session est donné à l\'imprimante du POS (avecServeur)', () {
      final d = Dio();
      expect(identical(avecServeur(i, d), i), isTrue);
      expect(avecServeur(null, d), isNull);
    });
  });

  test('borne et POS : aucune zone Remise ; la caisse (écran de vente de Prestige Mobile) l\'a', () {
    for (final f in [...Directory('lib/borne').listSync(recursive: true), ...Directory('lib/prestigepos').listSync(recursive: true)].whereType<File>()) {
      expect(f.readAsStringSync(), isNot(contains('RemiseVenteZone')), reason: f.path);
    }
    expect(File('lib/ventes/prevente/vente_screen.dart').readAsStringSync(), contains('RemiseVenteZone(hote: c'));
  });
}
