// PrestigePOS — réglages de l'imprimante (lecture, normalisation, mémorisation Bluetooth), choix de l'imprimante
// au moment du ticket (Sunmi détectée, Bluetooth, USB, réseau, aucune), messages d'échec, transport réseau RÉEL
// (socket TCP vers un serveur local qui joue l'imprimante sur le port 9100).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/borne/borne_ticket.dart';
import 'package:prestige_vente_app/prestigepos/impression/escpos.dart';
import 'package:prestige_vente_app/prestigepos/impression/imprimante_pos.dart';
import 'package:prestige_vente_app/prestigepos/impression/imprimante_reglages.dart';
import 'package:prestige_vente_app/prestigepos/impression/ticket_escpos.dart';
import 'package:prestige_vente_app/prestigepos/impression/transports.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'escpos_test.dart' show ticketType;

const _bt = AppareilImprimante(nom: 'MTP-II', adresse: '00:11:22:aa:bb:cc', appaire: true, imprimante: true);

class _Transport implements TransportImpression {
  final List<Uint8List> recus = [];
  EchecImpression? echec;
  @override
  Future<void> envoyer(Uint8List octets) async {
    if (echec != null) throw echec!;
    recus.add(octets);
  }
}

class _Sunmi implements BorneImprimante {
  final List<BorneTicket> tickets = [];
  bool ok = true;
  @override
  Future<bool> imprimer(BorneTicket ticket) async {
    tickets.add(ticket);
    return ok;
  }
}

/// Imprimante réseau simulée : serveur TCP local qui garde les octets reçus.
class _ImprimanteReseau {
  late ServerSocket s;
  final recus = BytesBuilder();
  final fini = Completer<void>();
  Future<int> demarrer() async {
    s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    s.listen((c) => c.listen(recus.add, onDone: () {
          c.destroy();
          if (!fini.isCompleted) fini.complete();
        }));
    return s.port;
  }
}

void main() {
  group('Réglages de l\'imprimante', () {
    test('par défaut : automatique (Sunmi si présente), 58 mm, QR natif, ASCII, coupe', () {
      const c = ImprimanteConfig();
      expect((c.type, c.papier, c.qr, c.jeu, c.coupe, c.port), (TypeImprimante.automatique, 58, ModeQr.natif, JeuCaracteres.ascii, true, 9100));
      expect(c.complete, isTrue);
    });

    test('lecture / écriture JSON, valeurs absurdes bornées', () {
      final c = ImprimanteConfig.fromJson({
        'type': 'reseau',
        'papier': 70,
        'hote': ' http://192.168.1.80/imprimante ',
        'port': 0,
        'qr': 'image',
        'jeu': 'pc858',
        'coupe': false,
        'bluetooth': {'nom': 'X\u0007', 'adresse': 'pas une adresse'},
        'memorisees': [_bt.toJson(), _bt.toJson(), {'adresse': 'zz'}],
        'usb': {'nom': 'U', 'adresse': '1155'},
      });
      expect(c.type, TypeImprimante.reseau);
      expect(c.papier, 58, reason: 'seuls 58 et 80 mm');
      expect(c.hote, '192.168.1.80');
      expect(c.port, 9100);
      expect((c.qr, c.jeu, c.coupe), (ModeQr.image, JeuCaracteres.pc858, false));
      expect(c.bluetooth, isNull, reason: 'adresse Bluetooth invalide ignorée');
      expect(c.memorisees.map((m) => m.adresse), ['00:11:22:AA:BB:CC'], reason: 'doublons et adresses invalides retirés');
      expect(c.usb, isNull);
      final relu = ImprimanteConfig.fromJson(jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>);
      expect(relu.toJson(), c.toJson());
      expect(ImprimanteConfig.fromJson({'type': 'inconnu'}).type, TypeImprimante.automatique);
    });

    test('« Ajouter » : choisie, mémorisée sans doublon, 8 au plus ; « Oublier »', () {
      var c = const ImprimanteConfig().ajouterBluetooth(_bt);
      expect(c.type, TypeImprimante.bluetooth);
      expect(c.bluetooth!.adresse, '00:11:22:AA:BB:CC');
      c = c.ajouterBluetooth(_bt);
      expect(c.memorisees.length, 1);
      for (var i = 0; i < 10; i++) {
        c = c.ajouterBluetooth(AppareilImprimante(nom: 'P$i', adresse: '00:00:00:00:00:0$i'));
      }
      expect(c.memorisees.length, ImprimanteConfig.maxMemorisees);
      expect(c.bluetooth!.nom, 'P9');
      c = c.oublierBluetooth(c.bluetooth!);
      expect(c.bluetooth, isNull);
      expect(c.complete, isFalse, reason: 'Bluetooth sans appareil choisi');
    });

    test('configuration complète et résumé', () {
      expect(const ImprimanteConfig(type: TypeImprimante.reseau).complete, isFalse);
      expect(const ImprimanteConfig(type: TypeImprimante.reseau, hote: '10.0.0.5').resume, 'Réseau · 10.0.0.5:9100 · 58 mm');
      expect(const ImprimanteConfig(type: TypeImprimante.usb, usb: AppareilImprimante(nom: 'XP-58', adresse: '1155:22339')).complete, isTrue);
      expect(const ImprimanteConfig(type: TypeImprimante.usb, usb: AppareilImprimante(nom: 'XP-58', adresse: '1155:22339')).usb!.usbIds, (1155, 22339));
      expect(const ImprimanteConfig(type: TypeImprimante.bluetooth, bluetooth: _bt, papier: 80).resume, 'Bluetooth · MTP-II · 80 mm');
    });

    test('mémorisation sur l\'appareil (SharedPreferences)', () async {
      SharedPreferences.setMockInitialValues({});
      await ImprimanteReglages.enregistrer(const ImprimanteConfig().ajouterBluetooth(_bt).copyWith(papier: 80));
      ImprimanteReglages.courant.value = const ImprimanteConfig();
      final c = await ImprimanteReglages.charger();
      expect((c.type, c.papier, c.bluetooth?.adresse), (TypeImprimante.bluetooth, 80, '00:11:22:AA:BB:CC'));
      SharedPreferences.setMockInitialValues({ImprimanteReglages.cle: '{pas du json'});
      expect((await ImprimanteReglages.charger()).type, TypeImprimante.automatique, reason: 'réglage illisible : valeurs par défaut');
    });
  });

  group('Imprimante du ticket', () {
    late _Transport transport;
    late _Sunmi sunmi;
    ImprimantePos imprimante(ImprimanteConfig c, {bool sunmiPresente = false}) =>
        ImprimantePos(config: () => c, sunmi: () async => sunmiPresente, imprimanteSunmi: sunmi, transport: (_) => transport);

    setUp(() {
      transport = _Transport();
      sunmi = _Sunmi();
    });

    test('automatique : Sunmi intégrée détectée → imprimante Sunmi (code de la borne)', () async {
      final i = imprimante(const ImprimanteConfig(), sunmiPresente: true);
      expect(await i.imprimer(ticketType()), isTrue);
      expect(sunmi.tickets.length, 1);
      expect(transport.recus, isEmpty);
    });

    test('automatique sans Sunmi : ticket à l\'écran, sans message d\'erreur', () async {
      final i = imprimante(const ImprimanteConfig());
      expect(await i.imprimer(ticketType()), isFalse);
      expect(i.dernierEchec, isNull);
      final s = imprimante(const ImprimanteConfig(type: TypeImprimante.sunmi));
      expect(await s.imprimer(ticketType()), isFalse);
      expect(s.dernierEchec, contains('Sunmi introuvable'));
    });

    test('aucune imprimante : ticket à l\'écran', () async {
      final i = imprimante(const ImprimanteConfig(type: TypeImprimante.aucune));
      expect(await i.imprimer(ticketType()), isFalse);
      expect(i.dernierEchec, isNull);
    });

    for (final papier in [58, 80]) {
      test('Bluetooth $papier mm : octets ESC/POS du ticket mis en page pour le papier', () async {
        final c = ImprimanteConfig(type: TypeImprimante.bluetooth, bluetooth: _bt, papier: papier);
        final i = imprimante(c);
        final t = ticketType(largeur: papier);
        expect(await i.imprimer(t), isTrue);
        expect(transport.recus.single, TicketEscPos.ticket(t, c));
        expect(i.dernierEchec, isNull);
      });
    }

    test('échec : cause en clair (BorneImprimanteDiagnostic), puis succès : message effacé', () async {
      final i = imprimante(const ImprimanteConfig(type: TypeImprimante.bluetooth, bluetooth: _bt));
      transport.echec = EchecImpression('CONNEXION', EchecImpression.messagePour('CONNEXION'));
      expect(await i.imprimer(ticketType()), isFalse);
      expect(i.dernierEchec, contains('allumée'));
      expect(i, isA<BorneImprimanteDiagnostic>());
      transport.echec = null;
      expect(await i.imprimer(ticketType()), isTrue);
      expect(i.dernierEchec, isNull);
    });

    test('imprimante choisie mais incomplète : message', () async {
      final i = ImprimantePos(config: () => const ImprimanteConfig(type: TypeImprimante.reseau), sunmi: () async => false);
      expect(await i.imprimer(ticketType()), isFalse);
      expect(i.dernierEchec, contains('non choisie'));
    });

    test('« Test d\'impression » : ticket d\'essai, message clair', () async {
      final i = imprimante(const ImprimanteConfig(type: TypeImprimante.bluetooth, bluetooth: _bt));
      expect(await i.tester(officine: 'Pharmacie test'), isNull);
      expect(latin1.decode(transport.recus.single), contains('TEST D\'IMPRESSION'));
      transport.echec = EchecImpression('PERMISSION', EchecImpression.messagePour('PERMISSION'));
      expect(await i.tester(), startsWith('Test non imprimé : Autorisation Bluetooth refusée'));
      expect(await imprimante(const ImprimanteConfig()).tester(), contains('Aucune imprimante intégrée Sunmi'));
      expect(await imprimante(const ImprimanteConfig(type: TypeImprimante.aucune)).tester(), contains('affiché à l\'écran'));
    });

    test('transports choisis selon le type', () {
      expect(ImprimantePos.transportPour(const ImprimanteConfig(type: TypeImprimante.bluetooth, bluetooth: _bt)), isA<TransportBluetooth>());
      expect(ImprimantePos.transportPour(const ImprimanteConfig(type: TypeImprimante.usb, usb: AppareilImprimante(nom: '', adresse: '1:2'))),
          isA<TransportUsb>().having((u) => (u.vendorId, u.productId), 'ids', (1, 2)));
      expect(ImprimantePos.transportPour(const ImprimanteConfig(type: TypeImprimante.reseau, hote: '10.0.0.5', port: 9101)),
          isA<TransportReseau>().having((r) => (r.hote, r.port), 'adresse', ('10.0.0.5', 9101)));
      expect(ImprimantePos.transportPour(const ImprimanteConfig()), isNull);
    });

    test('messages d\'erreur du pont Android : tous en clair', () {
      for (final code in ['PERMISSION', 'BT_ABSENT', 'BT_INACTIF', 'LOCALISATION', 'CONNEXION', 'USB_ABSENT', 'USB_REFUS', 'USB_INTERFACE', 'RESEAU', 'INDISPONIBLE', 'AUTRE']) {
        final m = EchecImpression.messagePour(code);
        expect(m.length, greaterThan(20), reason: code);
        expect(m, isNot(contains(code)), reason: 'pas de code technique affiché : $code');
      }
    });
  });

  group('Imprimante réseau (socket TCP réelle, port local)', () {
    test('le ticket arrive octet pour octet', () async {
      final imp = _ImprimanteReseau();
      final port = await imp.demarrer();
      addTearDown(() => imp.s.close());
      final c = ImprimanteConfig(type: TypeImprimante.reseau, hote: '127.0.0.1', port: port, papier: 80);
      final i = ImprimantePos(config: () => c, sunmi: () async => false);
      expect(await i.imprimer(ticketType(largeur: 80)), isTrue);
      await imp.fini.future.timeout(const Duration(seconds: 5));
      expect(imp.recus.takeBytes(), TicketEscPos.ticket(ticketType(largeur: 80), c));
    });

    test('imprimante éteinte (port fermé) : message avec l\'adresse', () async {
      final libre = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = libre.port;
      await libre.close();
      final i = ImprimantePos(config: () => ImprimanteConfig(type: TypeImprimante.reseau, hote: '127.0.0.1', port: port), sunmi: () async => false);
      expect(await i.imprimer(ticketType()), isFalse);
      expect(i.dernierEchec, contains('127.0.0.1:$port'));
      expect(i.dernierEchec, contains('9100'));
    });
  });
}
