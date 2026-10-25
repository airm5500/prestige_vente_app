// 4.6.2 — e2e, application entière (faux serveur Prestige en mémoire, données fictives) : terminal de pointage et
// badge RH imprimé en QR (PRESTIGE-BADGE|1|numéro|login|secret, serveur util.BadgeQr).
//  - lecture par la douchette (QWERTY sur AZERTY, verrouillage des majuscules) → « Bonjour Awa », pointage reçu par le
//    serveur pour l'employé du numéro ;
//  - sécurité : ni le secret ni le login du QR dans aucune requête (chemin, paramètres, corps, en-têtes), ni à l'écran ;
//  - badge code-barres actuel : inchangé.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/rh/terminal_pointage_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import 'outils/app_e2e.dart';

const _secret = 'SECRETfictifE2E-4567_azqwm';
const _login = 'awa.e2e';

// Douchette en QWERTY sur un appareil AZERTY, verrouillage des majuscules actif (tables de util.BadgeQr).
String _qwertyMaj(String s) {
  const us = '-_|aqzwmAQZWM', fr = '°)*qawz,QAWZ?';
  return s.split('').map((c) => us.contains(c) ? fr[us.indexOf(c)] : c).join();
}

void main() {
  testWidgets('badge QR lu par la douchette : employé reconnu, pointage envoyé, secret et login jamais transmis', (t) async {
    TailleEcran.telephone360x800.appliquer(t);
    final app = AppE2E()..serveur.activerTerminalRh();
    app.serveur.droitsRh[DonneesFictives.admin] = (pointer: true, gerer: false);
    // Photo de contrôle du badge désactivée (pas de caméra sous les tests) : elle est testée à part.
    await app.preparer(prefs: const {'hiddenMenuIds': <String>[], 'rh_photo_badge_v1': false});
    await app.lancer(t);
    expect(await app.seConnecter(t, login: DonneesFictives.admin, motDePasse: DonneesFictives.motDePasseAdmin), isTrue);
    await app.ouvrirMenu(t, ListPresentation.dashboard, 'pointage_rh');
    expect(await app.attendreQue(t, find.byKey(const Key('rh_voie_b'))), isTrue);
    await t.tap(find.byKey(const Key('rh_voie_b')));
    expect(await app.attendreQue(t, find.byType(TerminalPointageScreen)), isTrue);
    await app.attendre(t);

    final champ = find.byKey(const Key('rh_badge_champ'));
    await t.enterText(champ, _qwertyMaj('PRESTIGE-BADGE|1|B001|$_login|$_secret'));
    await t.pump();
    expect(t.widget<TextField>(champ).obscureText, isTrue, reason: 'QR masqué pendant la rafale du lecteur');
    expect(await app.attendreQue(t, find.text('Bonjour Awa')), isTrue);
    expect(find.byWidgetPredicate((w) => w is Text && (w.data ?? '').contains(_secret)), findsNothing);
    await t.tap(find.byKey(const Key('rh_valider')));
    await app.attendre(t);
    expect(app.serveur.pointagesTerminal.single['employeId'], 'E1');

    // Badge code-barres actuel : inchangé.
    await app.attendre(t, const Duration(seconds: 3));
    await t.enterText(champ, 'B002');
    await t.testTextInput.receiveAction(TextInputAction.done);
    expect(await app.attendreQue(t, find.text('Bonjour Ali')), isTrue);
    await t.tap(find.byKey(const Key('rh_valider')));
    await app.attendre(t);
    expect(app.serveur.pointagesTerminal.map((p) => p['employeId']), ['E1', 'E2']);

    for (final r in app.serveur.recues) {
      final tout = '${r.methode} ${r.chemin} ${r.query} ${r.corps} ${r.clientRef} ${r.utilisateur} ${r.autorisation}';
      expect(tout, isNot(contains(_secret)), reason: '$r');
      expect(tout, isNot(contains(_login)), reason: '$r');
      expect(tout, isNot(contains('PRESTIGE-BADGE')), reason: '$r');
    }
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });
}
