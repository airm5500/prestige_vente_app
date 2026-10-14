// ERGONOMIE — Configuration de l'interface d'origine (lib/screens/auth/settings_screen.dart), 4.0.3 (F1).
//
// Avant 4.0.3, la ligne « Type de code ticket » (libellé + choix « QR Code / Code-barres » côte à côte, sans
// retour à la ligne possible) débordait d'environ 132 px même sur tablette (largeur de l'écran bornée à 500 dp).
// Correction de mise en page seulement : le choix passe sous le libellé quand les deux ne tiennent pas sur une
// ligne ; mêmes valeurs ('QR_CODE' / 'BARCODE'), même enregistrement.
//
// Application ENTIÈRE (MyApp, interface d'origine, appareil non configuré → Configuration, comme sur le terrain),
// faux serveur Prestige en mémoire, aux tailles Sunmi V2s / V3 (Compact automatique : 400 dp vus par
// l'interface), téléphone 360×640 dp (Compact automatique), téléphone 360×800 dp (taille normale) et tablette,
// texte ×1,0 et ×1,3 :
//   - aucun débordement ni exception de rendu, sur toute la hauteur de l'écran ;
//   - libellé et deux choix de « Type de code ticket » entièrement dans l'écran ;
//   - les deux choix fonctionnent toujours (valeur enregistrée inchangée).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/screens/auth/settings_screen.dart';
import 'package:provider/provider.dart';

import 'outils/app_e2e.dart';
import 'outils/ergonomie.dart';

/// Lance l'interface d'origine sur un appareil non configuré : la Configuration s'ouvre d'elle-même.
Future<AppE2E> _configuration(WidgetTester t, TailleEcran taille, double echelle) async {
  taille.appliquer(t);
  t.platformDispatcher.textScaleFactorTestValue = echelle;
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  final app = AppE2E();
  await app.preparer(interfaceNouvelle: false, prefs: const {'local_ip': '', 'remote_ip': ''});
  await app.lancer(t);
  expect(await app.attendreQue(t, find.byType(SettingsScreen)), isTrue, reason: 'Configuration d\'origine');
  await app.attendre(t);
  return app;
}

void main() {
  for (final taille in TailleEcran.toutes) {
    for (final echelle in const [1.0, 1.3]) {
      testWidgets('Configuration d\'origine — $taille, texte ×$echelle : aucun débordement, « Type de code ticket » visible',
          (t) async {
        final app = await _configuration(t, taille, echelle);
        final facteur = facteurEcran(t);
        final contexte = '$taille, texte ×$echelle${facteur == 1.0 ? '' : ', interface ×$facteur'}';
        expect(t.takeException(), isNull, reason: '$contexte : erreur de rendu (débordement)');

        // Toute la hauteur de l'écran parcourue : aucun débordement plus bas.
        final zone = find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Scrollable)).first;
        final pos = t.state<ScrollableState>(zone).position;
        while (pos.pixels < pos.maxScrollExtent) {
          pos.jumpTo((pos.pixels + 300).clamp(0, pos.maxScrollExtent));
          await t.pump();
          expect(t.takeException(), isNull, reason: '$contexte : erreur de rendu en faisant défiler');
        }

        // Libellé et deux choix entièrement dans la largeur de l'interface.
        final libelle = find.text('Type de code ticket');
        await app.defilerJusqua(t, libelle, zone: zone);
        final largeur = MediaQuery.sizeOf(HorsLigne.navigatorKey.currentContext!).width;
        for (final f in [libelle, find.text('QR Code'), find.text('Code-barres')]) {
          final r = t.getRect(f);
          expect(r.left, greaterThanOrEqualTo(0), reason: '$contexte : $f coupé à gauche ($r)');
          expect(r.right, lessThanOrEqualTo(largeur + 0.5), reason: '$contexte : $f coupé à droite ($r, largeur $largeur)');
        }
        // Côte à côte (aspect d'origine) ou choix SOUS le libellé, jamais par-dessus.
        final rl = t.getRect(libelle), rc = t.getRect(find.text('QR Code'));
        expect(rc.top >= rl.bottom - 0.5 || (rc.top < rl.bottom && rc.bottom > rl.top), isTrue, reason: '$contexte : $rl / $rc');
        if (echelle == 1.0) {
          // Texte normal : le choix garde sa taille (au plus 5 % de réduction sous la police de test, dont les
          // lettres carrées sont bien plus larges que celles du terminal ; aucune sur tablette).
          final boutons = find.ancestor(of: find.text('QR Code'), matching: find.byType(ToggleButtons));
          final echelleChoix = t.getRect(boutons).width / (t.getSize(boutons).width * facteur);
          expect(echelleChoix, greaterThanOrEqualTo(taille == TailleEcran.tablette ? 0.999 : 0.95), reason: '$contexte : choix réduit');
        }
        expect(t.takeException(), isNull, reason: contexte);
        await app.fermer(t);
      });
    }
  }

  testWidgets('« Type de code ticket » : mêmes choix et mêmes valeurs (QR_CODE / BARCODE)', (t) async {
    final app = await _configuration(t, TailleEcran.sunmiV2s, 1.3);
    final settings = Provider.of<SettingsProvider>(t.element(find.byType(SettingsScreen)), listen: false);
    final zone = find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Scrollable)).first;
    await app.defilerJusqua(t, find.text('Code-barres'), zone: zone);
    final avant = settings.ticketCodeType;
    await t.tap(find.text('Code-barres'));
    await t.pump();
    expect(settings.ticketCodeType, 'BARCODE');
    await t.tap(find.text('QR Code'));
    await t.pump();
    expect(settings.ticketCodeType, 'QR_CODE');
    final boutons = t.widget<ToggleButtons>(find.ancestor(of: find.text('QR Code'), matching: find.byType(ToggleButtons)));
    expect(boutons.isSelected, [true, false]);
    expect(avant, anyOf('QR_CODE', 'BARCODE'));
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });
}
