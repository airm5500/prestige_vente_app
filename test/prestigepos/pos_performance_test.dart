// PrestigePOS — performance (application entière, faux serveur en mémoire) :
//  - démarrage jusqu'à la borne prête : temps simulé, temps réel de calcul, nombre de requêtes ;
//  - vitrine de 500 produits : pages de 50 chargées au fil du défilement, cartes construites à la demande
//    (jamais les 500 à la fois), défilement complet en temps réel borné ;
//  - recherche tapée vite (une lettre toutes les 80 ms) : UNE seule requête, pour le texte final.
// Les mesures sont aussi écrites dans la sortie du test (« MESURE … ») pour le résumé de la CI.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/borne/borne_widgets.dart';

import 'outils/pos_e2e.dart';
import 'pos_e2e_test.dart' show attendreBorne, tablettePortrait;

// ignore: avoid_print
void mesure(String m) => print('MESURE $m');

void main() {
  testWidgets('démarrage jusqu\'à la borne prête', (t) async {
    tablettePortrait(t);
    final app = PosE2E();
    await app.preparer(configure: true);
    final chrono = Stopwatch()..start();
    await app.lancer(t);
    var simule = Duration.zero;
    while (find.byKey(const ValueKey('borne-recherche')).evaluate().isEmpty && simule < const Duration(seconds: 20)) {
      await t.pump(const Duration(milliseconds: 50));
      simule += const Duration(milliseconds: 50);
    }
    chrono.stop();
    expect(find.byKey(const ValueKey('borne-recherche')), findsOneWidget);
    final requetes = app.serveur.recues.length;
    mesure('démarrage : ${simule.inMilliseconds} ms simulées, ${chrono.elapsedMilliseconds} ms de calcul, $requetes requêtes');
    expect(simule, lessThan(const Duration(seconds: 2)), reason: 'borne prête en moins de 2 s (serveur immédiat)');
    expect(chrono.elapsed, lessThan(const Duration(seconds: 10)), reason: 'calcul du démarrage (machine de CI)');
    expect(requetes, lessThanOrEqualTo(8), reason: 'licence, connexion, officine… : démarrage sobre');
    expect(app.recherches, isEmpty, reason: 'aucune recherche avant que le client tape');
    await app.fermer(t);
  });

  testWidgets('vitrine de 500 produits : pages de 50 à la demande, cartes construites à la demande', (t) async {
    tablettePortrait(t);
    final app = PosE2E(catalogue: [
      for (var i = 0; i < 500; i++) produit('P$i', 'DOLITEST ${i.toString().padLeft(3, '0')} CP B/${8 + i % 20}', '9${i.toString().padLeft(6, '0')}', 1000 + i, 5 + i % 30),
    ]);
    await app.preparer(configure: true);
    await app.lancer(t);
    await attendreBorne(t, app);
    await app.chercher(t, 'dolitest');
    FocusManager.instance.primaryFocus?.unfocus();
    await app.attendre(t, const Duration(milliseconds: 500));
    expect(app.recherches.length, 1, reason: 'première page seulement');
    final construites = find.byType(BorneCarteProduit).evaluate().length;
    expect(construites, lessThan(60), reason: 'cartes visibles seulement ($construites construites)');

    final chrono = Stopwatch()..start();
    var maxConstruites = construites;
    final zone = find.byType(Scrollable).last;
    for (var i = 0; i < 400 && find.byKey(const ValueKey('borne-produit-P499')).evaluate().isEmpty; i++) {
      await t.drag(zone, const Offset(0, -1500));
      await t.pump(const Duration(milliseconds: 50));
      await t.pump(const Duration(milliseconds: 50));
      final n = find.byType(BorneCarteProduit).evaluate().length;
      if (n > maxConstruites) maxConstruites = n;
    }
    chrono.stop();
    expect(find.byKey(const ValueKey('borne-produit-P499')), findsOneWidget, reason: 'dernier produit atteint');
    mesure('vitrine 500 produits : ${chrono.elapsedMilliseconds} ms de défilement, ${app.recherches.length} pages, '
        'au plus $maxConstruites cartes construites');
    expect(app.recherches.length, 10, reason: '500 produits = 10 pages de 50, chacune demandée une fois');
    expect(maxConstruites, lessThan(80), reason: 'jamais les 500 cartes à la fois');
    expect(chrono.elapsed, lessThan(const Duration(seconds: 60)), reason: 'défilement complet');
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  testWidgets('recherche tapée vite : une seule requête, pour le texte final', (t) async {
    tablettePortrait(t);
    final app = PosE2E();
    await app.preparer(configure: true);
    await app.lancer(t);
    await attendreBorne(t, app);
    const mot = 'doliprane';
    for (var i = 1; i <= mot.length; i++) {
      await t.enterText(find.byKey(const ValueKey('borne-recherche')), mot.substring(0, i));
      await t.pump(const Duration(milliseconds: 80));
    }
    await app.attendre(t, const Duration(seconds: 1));
    mesure('recherche « $mot » tapée en ${mot.length * 80} ms : ${app.recherches.length} requête(s) ${app.recherches}');
    expect(app.recherches.length, 1);
    expect(app.recherches.single, contains('DOLIPRANE'));
    // Effacer puis retaper 2 lettres : rien n'est envoyé sous 3 caractères.
    await t.enterText(find.byKey(const ValueKey('borne-recherche')), 'do');
    await app.attendre(t, const Duration(seconds: 1));
    expect(app.recherches.length, 1);
    await app.fermer(t);
  });
}
