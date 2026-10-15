// PrestigePOS — réseau (application entière, faux serveur en mémoire, temps simulé) :
//  - serveur lent (2, 5 et 8 s par réponse) : la borne attend (indicateur), puis affiche les résultats ; la prévente
//    est créée UNE fois même si le client appuie plusieurs fois sur « Payer en caisse » ; le serveur lent n'est
//    jamais pris pour un serveur injoignable ;
//  - coupure en cours d'utilisation : « momentanément indisponible », panier vidé (confidentialité) ; reprise
//    automatique au retour du serveur, la vente suivante passe.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/borne/borne_screen.dart';

import 'outils/pos_e2e.dart';
import 'pos_e2e_test.dart' show acheter, attendreBorne, tablettePortrait;

void main() {
  for (final secondes in [2, 5, 8]) {
    testWidgets('serveur lent ($secondes s par réponse) : attente visible, résultats, une seule prévente', (t) async {
      tablettePortrait(t);
      final app = PosE2E();
      await app.preparer(configure: true);
      await app.lancer(t);
      await attendreBorne(t, app);
      app.serveur.latence = Duration(seconds: secondes);

      await app.saisir(t, 'borne-recherche', 'doli');
      await app.attendre(t, const Duration(milliseconds: 600));
      expect(find.byType(CircularProgressIndicator), findsWidgets, reason: 'recherche en cours affichée');
      expect(await app.attendreQue(t, find.byKey(const ValueKey('borne-ajouter-F1')), max: Duration(seconds: secondes + 5)), isTrue);

      await app.toucher(t, 'borne-ajouter-F1');
      await app.attendre(t, const Duration(milliseconds: 2600));
      await app.toucher(t, 'borne-voir-panier');
      final ventesAvant = app.serveur.ventes.length;
      // Trois appuis rapprochés sur « Payer en caisse ».
      for (var i = 0; i < 3; i++) {
        await t.tap(find.byKey(const ValueKey('borne-payer')), warnIfMissed: false);
        await t.pump(const Duration(milliseconds: 300));
      }
      expect(await app.attendreQue(t, find.byKey(const ValueKey('borne-numero')), max: Duration(seconds: secondes * 12 + 10)), isTrue);
      expect(app.serveur.ventes.length, ventesAvant + 1, reason: 'une seule prévente malgré les appuis répétés');
      expect(find.byKey(const ValueKey('borne-indisponible')), findsNothing, reason: 'serveur lent ≠ serveur injoignable');
      expect(app.pont.envois.length, 1);
      await app.fermer(t);
    });
  }

  testWidgets('coupure pendant l\'utilisation puis reprise', (t) async {
    tablettePortrait(t);
    final app = PosE2E();
    await app.preparer(configure: true);
    await app.lancer(t);
    await attendreBorne(t, app);
    await app.chercher(t, 'doli');
    await app.toucher(t, 'borne-ajouter-F1');

    await app.serveur.couper();
    // Le client continue : la recherche échoue, la surveillance constate la coupure.
    await app.chercher(t, 'vitamine');
    expect(await app.attendreQue(t, find.byKey(const ValueKey('borne-indisponible')), max: const Duration(seconds: 100)), isTrue);
    expect(find.text(BorneScreen.indisponibleTitre), findsOneWidget);

    await app.serveur.retablir();
    expect(await app.attendreQue(t, find.byKey(const ValueKey('borne-recherche')), max: const Duration(seconds: 70)), isTrue,
        reason: 'reprise automatique');
    expect(find.byKey(const ValueKey('borne-barre-total')), findsNothing, reason: 'panier vidé pendant la coupure');
    await acheter(t, app);
    expect(app.pont.envois.length, 1);
    await app.fermer(t);
  });
}
