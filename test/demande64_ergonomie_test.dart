// ERGONOMIE — 4.15.2 : réponse du serveur à la demande 64, données FICTIVES :
//  - borne, caisse de la borne fermée : écran du ticket de prévente avec l'avis « Paiement mobile indisponible… » ;
//    avis, numéro et « TERMINÉ » visibles, aucun débordement, du Sunmi V2s (360 dp) à la tablette, texte ×1.3 ;
//  - comptoir, panier verrouillé : message du serveur (deux phrases) entièrement affiché dans le bandeau, sans
//    débordement, 8 s ; panier toujours lisible derrière (320 dp à la tablette, texte ×1.3) ;
//  - borne sans droit de clôture : « Payer en caisse » seul, bouton ≥ 48 dp.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/borne/borne_screen.dart';
import 'package:prestige_vente_app/droits/droits_vente.dart';
import 'package:prestige_vente_app/ventes/common/vente_messages.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_cart.dart';

import 'demande64_ecrans_test.dart';
import 'outils/demande64_fictive.dart';

const _bornes = [Size(360, 640), Size(360, 760), Size(800, 1280), Size(1280, 800)];
const _comptoirs = [Size(320, 640), Size(360, 720), Size(960, 600)];

void main() {
  setUp(() => DroitsVente.instance.oublier());
  tearDown(() => DroitsVente.instance.oublier());

  for (final s in _bornes) {
    testWidgets('borne ${s.width.toInt()}×${s.height.toInt()} : caisse fermée → ticket de prévente et avis lisibles, aucun débordement', (t) async {
      DroitsVente.instance.fixer({'P_SM_VENTE', DroitsVente.bornePaiementMobileDroit}, utilisateur: 'U-borne.fictive');
      await borne64(t, PmBorne64(), taille: s);
      await avancer64(t, const Duration(seconds: 1));
      final avis = find.byKey(const ValueKey('borne-avis-ticket'));
      expect(avis, findsOneWidget);
      expect(t.widget<Text>(avis).data, BorneScreen.avisMobileIndisponible);
      for (final k in ['borne-avis-ticket', 'borne-numero', 'borne-termine']) {
        final r = t.getRect(find.byKey(ValueKey(k)));
        expect(r.left, greaterThanOrEqualTo(0), reason: k);
        expect(r.right, lessThanOrEqualTo(s.width + 0.1), reason: k);
      }
      final termine = t.getRect(find.byKey(const ValueKey('borne-termine')));
      expect(termine.height, greaterThanOrEqualTo(47.9));
      expect(termine.bottom, lessThanOrEqualTo(s.height + 0.1), reason: '« TERMINÉ » toujours visible');
      expect(t.takeException(), isNull, reason: 'aucun débordement');
      await fin64(t);
    });
  }

  testWidgets('borne sans droit de clôture : « Payer en caisse » seul, ≥ 48 dp, aucun débordement', (t) async {
    DroitsVente.instance.fixer({'P_SM_VENTE'}, utilisateur: 'U-borne.fictive');
    await borne64(t, PmBorne64(), payer: false);
    expect(find.byKey(const ValueKey('borne-payer-mobile')), findsNothing);
    final r = t.getRect(find.byKey(const ValueKey('borne-payer')));
    expect(r.height, greaterThanOrEqualTo(47.9));
    expect(t.takeException(), isNull);
    await fin64(t);
  });

  for (final s in _comptoirs) {
    for (final texte in [1.0, 1.3]) {
      for (final message in [messagePayeWave4125, messageEnCoursOrange4125]) {
        final cas = message == messagePayeWave4125 ? 'payée' : 'en cours';
        testWidgets('comptoir ${s.width.toInt()} dp, texte ×$texte, $cas : message du verrou entier, aucun débordement', (t) async {
          await panier64(t, GwVerrou64(message), taille: s, texte: texte);
          await modifierLigne64(t, '1');
          await t.pump(const Duration(milliseconds: 500));
          final snack = find.byType(SnackBar);
          expect(snack, findsOneWidget);
          expect(t.widget<SnackBar>(snack).duration, dureeMessageVerrou);
          final texteSnack = find.descendant(of: snack, matching: find.text(message));
          expect(texteSnack, findsOneWidget, reason: 'message du serveur tel quel');
          final r = t.getRect(texteSnack);
          expect(r.right, lessThanOrEqualTo(s.width + 0.1));
          expect(r.top, greaterThanOrEqualTo(0));
          expect(find.byType(VenteCart), findsOneWidget);
          expect(t.takeException(), isNull, reason: 'aucun débordement');
        });
      }
    }
  }
}
