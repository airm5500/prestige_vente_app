// PrestigePOS 1.17.0 — Prestige Mobile V3 5.4.0 fusionnée : « Contraste d'impression » sur les chemins propres à
// PrestigePOS (données FICTIVES) :
//  - imprimantes externes : le ticket dessiné par le serveur passe par la même conversion que Prestige Mobile
//    (renforcé par défaut : seuil 160, traits verticaux d'un point doublés ; QR inchangé) ;
//  - ticket ESC/POS composé par la borne : lignes produits et total en gras si renforcé ; « Normal » = octets 1.16.0 ;
//  - page Imprimante : interrupteur « Contraste renforcé », gardé sur l'appareil.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/prestigepos/impression/imprimante_page.dart';
import 'package:prestige_vente_app/prestigepos/impression/imprimante_reglages.dart';
import 'package:prestige_vente_app/prestigepos/impression/ticket_escpos.dart';
import 'package:prestige_vente_app/services/contraste_impression.dart';
import 'package:prestige_vente_app/services/ticket_1bit.dart';
import 'package:prestige_vente_app/services/ticket_serveur.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'escpos_test.dart' show ticketType, textes, verifierReference;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ReglageContraste.reinitialiser();
  });
  tearDown(ReglageContraste.reinitialiser);

  for (final papier in [58, 80]) {
    final c = ImprimanteConfig(type: TypeImprimante.bluetooth, papier: papier);

    test('$papier mm : ticket ESC/POS de la borne, contraste renforcé (par défaut) : octets de référence, lignes en gras', () {
      expect(ReglageContraste.courant.value, ContrasteImpression.renforce);
      final r = TicketEscPos.ticket(ticketType(largeur: papier), c);
      verifierReference('ticket_${papier}_qr_renforce', r);
      ReglageContraste.reinitialiser(ContrasteImpression.normal);
      final n = TicketEscPos.ticket(ticketType(largeur: papier), c);
      expect(textes(r), textes(n), reason: 'mêmes lignes, même largeur');
      final gras = [0x1B, 0x45, 0x01];
      int compte(List<int> o) {
        var k = 0;
        for (var i = 0; i + 2 < o.length; i++) {
          if (o[i] == gras[0] && o[i + 1] == gras[1] && o[i + 2] == gras[2]) k++;
        }
        return k;
      }

      expect(compte(r), compte(n) + 1, reason: 'un passage en gras de plus, pour les lignes produits et le total');
    });

    test('$papier mm : image du serveur pour imprimante externe : renforcée par défaut, normale = 1.16.0', () {
      final points = papier == 58 ? 384 : 576;
      final png = File('test/references/tickets/image_serveur_fictive_assurance_${papier == 58 ? 58 : 80}.png').readAsBytesSync();
      final renforce = TicketEscPos.matricePng(png, points)!;
      expect(renforce, Ticket1Bit.depuisPng(png, largeurMax: points, contraste: ContrasteImpression.renforce)!.matrice());
      ReglageContraste.reinitialiser(ContrasteImpression.normal);
      final normal = TicketEscPos.matricePng(png, points)!;
      expect(normal, Ticket1Bit.depuisPng(png, largeurMax: points)!.matrice(), reason: 'normal : seuil 128 comme la 1.16.0');
      int noirs(List<List<bool>> m) => m.fold(0, (a, l) => a + l.where((p) => p).length);
      expect(noirs(renforce), greaterThan(noirs(normal)));
      final o = TicketEscPos.images([TicketImage(modele: 'VENTE_ASSURANCE', png: png, largeurPoints: points, hauteurPoints: normal.length)], c);
      expect(o, isNotNull);
    });
  }

  testWidgets('page Imprimante : « Contraste renforcé » activé par défaut, désactivé et gardé', (t) async {
    t.view.physicalSize = const Size(720, 1440);
    t.view.devicePixelRatio = 2.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ImprimanteReglagesVue()))));
    await t.pumpAndSettle();
    final inter = find.byKey(const ValueKey('imp-contraste'));
    await t.ensureVisible(inter);
    await t.pumpAndSettle();
    expect(t.widget<SwitchListTile>(inter).value, isTrue);
    await t.tap(inter);
    await t.pumpAndSettle();
    expect(ReglageContraste.courant.value, ContrasteImpression.normal);
    expect((await SharedPreferences.getInstance()).getString(ReglageContraste.cle), 'normal');
    expect(t.widget<SwitchListTile>(inter).value, isFalse);
    expect(t.takeException(), isNull);
  });
}
