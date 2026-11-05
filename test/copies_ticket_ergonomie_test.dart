// ERGONOMIE — 4.10.3 : dialogue « Ticket suivant (i/N) » sur Sunmi V2s / V3, téléphone 360 dp et tablette, texte ×1,0
// et ×1,3 : aucun débordement, titre et consigne entiers à l'écran, « Arrêter » et « Imprimer » visibles, cibles
// ≥ 48 dp, « Imprimer » (action par défaut) à droite.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/ventes/common/copies_ticket.dart';

import 'outils/app_e2e.dart' show TailleEcran;

void main() {
  for (final ecran in [TailleEcran.sunmiV2s, TailleEcran.sunmiV3, TailleEcran.telephone, TailleEcran.tablette]) {
    for (final texte in [1.0, 1.3]) {
      testWidgets('${ecran.nom}, texte ×$texte', (t) async {
        ecran.appliquer(t);
        t.platformDispatcher.textScaleFactorTestValue = texte;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        late BuildContext c;
        await t.pumpWidget(MaterialApp(home: Builder(builder: (ctx) {
          c = ctx;
          return const Scaffold();
        })));
        final f = confirmerTicketSuivant(c, 3, 3);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        final taille = t.view.physicalSize / t.view.devicePixelRatio;
        final ecranRect = Offset.zero & taille;
        for (final x in [find.text('Ticket suivant (3/3)'), find.text('Coupez le ticket, puis imprimez le suivant.')]) {
          final r = t.getRect(x);
          expect(ecranRect.contains(r.topLeft) && ecranRect.contains(r.bottomRight - const Offset(0.1, 0.1)), isTrue, reason: '$x');
        }
        final imprimer = t.getRect(find.byKey(const ValueKey('ticket-suivant-imprimer')));
        final arreter = t.getRect(find.byKey(const ValueKey('ticket-suivant-arreter')));
        for (final r in [imprimer, arreter]) {
          expect(r.height, greaterThanOrEqualTo(48));
          expect(r.width, greaterThanOrEqualTo(48));
          expect(r.right, lessThanOrEqualTo(taille.width + 0.5));
          expect(r.bottom, lessThanOrEqualTo(taille.height + 0.5));
        }
        // Côte à côte : Imprimer à droite ; empilés (texte agrandi) : alignés à droite.
        expect(imprimer.right, greaterThanOrEqualTo(arreter.right - 0.5), reason: 'Imprimer à droite (action principale)');
        await t.tap(find.byKey(const ValueKey('ticket-suivant-imprimer')));
        await t.pumpAndSettle();
        expect(await f, isTrue);
      });
    }
  }
}
