// PrestigePOS — choix de paiement selon les capacités du serveur (application entière, faux serveur) :
//  - « Payer en caisse » (espèces → ticket de prévente QR, le client va à la caisse) TOUJOURS proposé ;
//  - mobile money proposé seulement si le module serveur B3 annonce des opérateurs
//    (GET /paiements-mobile/capacites) ET si PrestigePOS l'autorise (réglage de l'assistant, activé par défaut).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/prestigepos/pos_reglages.dart';

import 'outils/pos_e2e.dart';
import 'pos_e2e_test.dart' show attendreBorne, tablettePortrait;

Future<void> versPanier(WidgetTester t, PosE2E app) async {
  await app.chercher(t, 'doli');
  await app.toucher(t, 'borne-ajouter-F1');
  await app.attendre(t, const Duration(milliseconds: 2600));
  await app.toucher(t, 'borne-voir-panier');
}

int appelsCapacites(PosE2E app) => app.serveur.recues.where((r) => r.chemin.endsWith('/paiements-mobile/capacites')).length;

void main() {
  testWidgets('module mobile money annoncé : « Payer en caisse » ET « Payer par mobile money »', (t) async {
    tablettePortrait(t);
    final app = PosE2E();
    app.serveur.routes['GET /paiements-mobile/capacites'] =
        (_) => FauxServeurPrestige.ok({'success': true, 'paiementsMobile': ['orange', 'wave'], 'expirationMin': 10});
    await app.preparer(configure: true);
    await app.lancer(t);
    await attendreBorne(t, app);
    await versPanier(t, app);
    expect(find.byKey(const ValueKey('borne-payer')), findsOneWidget);
    expect(find.byKey(const ValueKey('borne-payer-mobile')), findsOneWidget);
    await app.toucher(t, 'borne-payer-mobile');
    expect(find.byKey(const ValueKey('borne-operateur-orange')), findsOneWidget);
    expect(find.byKey(const ValueKey('borne-operateur-wave')), findsOneWidget);
    expect(appelsCapacites(app), greaterThan(0));
    await app.fermer(t);
  });

  testWidgets('serveur sans module mobile money : « Payer en caisse » seulement', (t) async {
    tablettePortrait(t);
    final app = PosE2E();
    await app.preparer(configure: true);
    await app.lancer(t);
    await attendreBorne(t, app);
    await versPanier(t, app);
    expect(find.byKey(const ValueKey('borne-payer')), findsOneWidget);
    expect(find.byKey(const ValueKey('borne-payer-mobile')), findsNothing);
    expect(appelsCapacites(app), greaterThan(0), reason: 'capacités demandées au serveur (réponse 404)');
    await app.fermer(t);
  });

  testWidgets('module annoncé mais mobile money désactivé dans PrestigePOS : « Payer en caisse » seulement, aucune demande', (t) async {
    tablettePortrait(t);
    final app = PosE2E();
    app.serveur.routes['GET /paiements-mobile/capacites'] = (_) => FauxServeurPrestige.ok({'success': true, 'paiementsMobile': ['orange']});
    await app.preparer(configure: true, prefs: {PosReglages.cleMobileMoney: false});
    await app.lancer(t);
    await attendreBorne(t, app);
    await versPanier(t, app);
    expect(find.byKey(const ValueKey('borne-payer-mobile')), findsNothing);
    expect(appelsCapacites(app), 0);
    await app.fermer(t);
  });

  test('réglage par défaut : mobile money autorisé (proposé si le serveur l\'annonce)', () {
    expect(const PosConfig().mobileMoney, isTrue);
    expect(const PosConfig().configure, isFalse);
  });
}
