// PrestigePOS 1.8.3 — pause « Ticket suivant (i/N) » de Prestige Mobile 4.10.3 (ventes de la caisse) : la borne n'est
// PAS concernée. Application entière contre le faux serveur, réglages « Nombre de tickets » à 3 : un client qui paie
// en caisse reçoit UN ticket de prévente, et l'écran client n'affiche jamais le dialogue de caisse.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'outils/pos_e2e.dart';
import 'pos_e2e_test.dart' show acheter, attendreBorne, tablettePortrait;

void main() {
  testWidgets('borne, réglages à 3 copies : un seul ticket, aucun dialogue « Ticket suivant »', (t) async {
    tablettePortrait(t);
    final app = PosE2E();
    await app.preparer(configure: true, prefs: {'number_of_tickets': 3, 'number_of_tickets_assurance': 3});
    await app.lancer(t);
    await attendreBorne(t, app);
    final avant = app.pont.envois.length;
    await acheter(t, app);
    await app.attendre(t, const Duration(seconds: 2));
    expect(app.pont.envois.length - avant, 1, reason: 'un seul ticket envoyé à l\'imprimante');
    expect(find.byKey(const ValueKey('ticket-suivant')), findsNothing, reason: 'jamais de dialogue de caisse pour le client');
    expect(find.textContaining('Ticket suivant'), findsNothing);
    expect(find.textContaining('Coupez le ticket'), findsNothing);
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });
}
