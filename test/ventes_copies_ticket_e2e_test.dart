// 4.10.3 — e2e, application entière (faux serveur Prestige en mémoire, données fictives) : retour du pharmacien « avec
// 2 tickets ou plus, les copies sortent à la suite, je ne peux pas couper le premier ». Nouvelle interface, vente
// comptant (espèces ; même boucle pour tous les modes : différé, mobile money, plusieurs modes) :
//  - N = 1 : une copie, aucune pause ;
//  - N = 2 / 3 : copie 1 tout de suite, puis « Ticket suivant (i/N) — Coupez le ticket, puis imprimez le suivant. »
//    avant CHAQUE copie suivante (jamais avant la première), Imprimer par défaut ;
//  - « Arrêter » : copies restantes annulées ; vente toujours encaissée une seule fois ;
//  - aperçu du mode test (une fenêtre « Aperçu du Ticket » par copie) ET imprimante Sunmi (canal simulé) ;
//  - encaissement provisoire hors ligne : même pause.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart' show CatalogueCategorie;
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import 'outils/app_e2e.dart';
import 'outils/parcours_vente.dart';
import 'outils/ticket_capture.dart';

final _pause = find.byKey(const ValueKey('ticket-suivant'));
final _imprimer = find.byKey(const ValueKey('ticket-suivant-imprimer'));
final _arreter = find.byKey(const ValueKey('ticket-suivant-arreter'));
final _apercu = find.text('Aperçu du Ticket');

Future<(AppE2E, CatalogueFictif)> _vente(WidgetTester t, {required int copies, bool modeTest = true}) async {
  TailleEcran.sunmiV2s.appliquer(t);
  final app = AppE2E();
  final c = CatalogueFictif(app.serveur, nombre: 10);
  await app.preparer(prefs: {...prefsVente, 'is_test_print_mode': modeTest, 'number_of_tickets': copies});
  await app.lancer(t);
  expect(await app.seConnecter(t), isTrue);
  await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
  expect(await ajouterAuPanier(t, app, nomCourt(3)), isTrue);
  await app.attendre(t, const Duration(seconds: 2));
  return (app, c);
}

/// Espèces « Exact », impression laissée cochée (copies du réglage), VALIDER.
Future<void> _encaisser(WidgetTester t, AppE2E app, {Finder? bouton}) async {
  await t.tap(bouton ?? find.byKey(const ValueKey('vente-encaisser')));
  expect(await app.attendreQue(t, find.text('Exact')), isTrue, reason: 'page d\'encaissement ouverte');
  await t.tap(find.text('Exact'));
  await t.pump();
  final valider = find.byKey(const ValueKey('encaissement-valider'));
  await t.ensureVisible(valider);
  await t.pump();
  await t.tap(valider);
}

/// Ferme l'aperçu de la copie en cours (mode test).
Future<void> _fermerApercu(WidgetTester t, AppE2E app) async {
  expect(await app.attendreQue(t, _apercu), isTrue, reason: 'aperçu de la copie');
  expect(_pause, findsNothing, reason: 'jamais de pause pendant une copie');
  await t.tap(find.text('Fermer'));
  await app.attendre(t, const Duration(milliseconds: 500));
}

String _titrePause(WidgetTester t) =>
    t.widget<Text>(find.descendant(of: _pause, matching: find.textContaining('Ticket suivant'))).data!;

void main() {
  for (final n in [1, 2, 3]) {
    testWidgets('comptant, mode test, $n copie(s) : copie 1 sans pause, puis « Ticket suivant (i/$n) » avant chaque suivante', (t) async {
      final (app, c) = await _vente(t, copies: n);
      await _encaisser(t, app);
      await _fermerApercu(t, app);
      for (var i = 2; i <= n; i++) {
        expect(await app.attendreQue(t, _pause), isTrue, reason: 'pause avant la copie $i');
        expect(_titrePause(t), 'Ticket suivant ($i/$n)');
        expect(find.text('Coupez le ticket, puis imprimez le suivant.'), findsOneWidget);
        expect(_apercu, findsNothing, reason: 'copie $i pas encore imprimée');
        // Imprimer : bouton par défaut (focus).
        expect(Focus.of(t.element(find.descendant(of: _imprimer, matching: find.text('Imprimer')))).hasFocus, isTrue);
        await t.tap(_imprimer);
        await app.attendre(t, const Duration(milliseconds: 300));
        await _fermerApercu(t, app);
      }
      await app.attendre(t);
      expect(_pause, findsNothing, reason: 'aucune pause après la dernière copie');
      expect(_apercu, findsNothing);
      expect(c.clotures, 1, reason: 'une seule clôture');
      expect(find.byKey(const ValueKey('vente-recherche')), findsOneWidget, reason: 'nouvelle vente');
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });
  }

  for (final (n, arret) in [(2, 2), (3, 2), (3, 3)]) {
    testWidgets('comptant, $n copies, « Arrêter » à la pause $arret/$n : copies restantes annulées', (t) async {
      final (app, c) = await _vente(t, copies: n);
      await _encaisser(t, app);
      var apercus = 0;
      await _fermerApercu(t, app);
      apercus++;
      for (var i = 2; i < arret; i++) {
        expect(await app.attendreQue(t, _pause), isTrue);
        await t.tap(_imprimer);
        await app.attendre(t, const Duration(milliseconds: 300));
        await _fermerApercu(t, app);
        apercus++;
      }
      expect(await app.attendreQue(t, _pause), isTrue);
      expect(_titrePause(t), 'Ticket suivant ($arret/$n)');
      await t.tap(_arreter);
      await app.attendre(t);
      expect(_apercu, findsNothing, reason: 'rien imprimé après « Arrêter »');
      expect(_pause, findsNothing, reason: 'une seule pause par copie suivante, aucune après « Arrêter »');
      expect(apercus, arret - 1);
      expect(c.clotures, 1);
      expect(find.byKey(const ValueKey('vente-recherche')), findsOneWidget);
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });
  }

  testWidgets('comptant, imprimante Sunmi (canal simulé), 3 copies : 1 ticket, pause, 1 ticket, pause, 1 ticket', (t) async {
    final imp = ImprimanteSimulee()..installer(t);
    addTearDown(() => imp.retirer(t));
    final (app, _) = await _vente(t, copies: 3, modeTest: false);
    int tickets() => imp.appels.where((a) => a.startsWith('BIND_PRINTER_SERVICE')).length;
    await _encaisser(t, app);
    expect(await app.attendreQue(t, _pause), isTrue);
    expect(tickets(), 1, reason: 'copie 1 imprimée, la 2 attend la pause');
    expect(_titrePause(t), 'Ticket suivant (2/3)');
    await t.tap(_imprimer);
    await app.attendre(t, const Duration(milliseconds: 300));
    expect(await app.attendreQue(t, find.text('Ticket suivant (3/3)')), isTrue);
    expect(tickets(), 2);
    await t.tap(_imprimer);
    await app.attendre(t);
    expect(tickets(), 3);
    expect(_pause, findsNothing);
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  testWidgets('comptant, Sunmi, 1 copie : aucune pause', (t) async {
    final imp = ImprimanteSimulee()..installer(t);
    addTearDown(() => imp.retirer(t));
    final (app, _) = await _vente(t, copies: 1, modeTest: false);
    await _encaisser(t, app);
    await app.attendre(t, const Duration(seconds: 2));
    expect(imp.appels.where((a) => a.startsWith('BIND_PRINTER_SERVICE')), hasLength(1));
    expect(_pause, findsNothing);
    await app.fermer(t);
  });

  testWidgets('encaissement provisoire hors ligne, 2 copies : même pause « Ticket suivant (2/2) »', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final app = AppE2E();
    await app.preparer(prefs: {'hiddenMenuIds': <String>[], 'is_test_print_mode': true, 'number_of_tickets': 2});
    await app.lancer(t);
    expect(await app.seConnecter(t), isTrue);
    await app.attendre(t, const Duration(seconds: 3));
    await app.horsLigne.store.replace(CatalogueCategorie.produits, [DonneesFictives.produitRecherche()], DateTime.now());
    await app.horsLigne.sync.refreshStats();
    await app.serveur.couper();
    expect(await app.attendreQue(t, find.text('Continuer hors ligne'), max: const Duration(minutes: 3)), isTrue);
    await t.tap(find.text('Continuer hors ligne'));
    await app.attendre(t);
    await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
    await t.enterText(find.byKey(const ValueKey('vente-recherche')), 'para');
    await app.attendre(t);
    expect(await app.attendreQue(t, champQuantite), isTrue);
    await t.enterText(champQuantite, '1');
    await t.tap(find.text('Ajouter'));
    await app.attendre(t);
    await _encaisser(t, app, bouton: find.byKey(const ValueKey('vente-hl-especes')));
    expect(await app.attendreQue(t, _apercu), isTrue);
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.textContaining('PROVISOIRE')), findsWidgets,
        reason: 'ticket provisoire');
    await _fermerApercu(t, app);
    expect(await app.attendreQue(t, _pause), isTrue);
    expect(_titrePause(t), 'Ticket suivant (2/2)');
    await t.tap(_imprimer);
    await app.attendre(t, const Duration(milliseconds: 300));
    await _fermerApercu(t, app);
    await app.attendre(t);
    expect(_pause, findsNothing);
    expect(app.serveur.ventes, isEmpty, reason: 'rien envoyé hors ligne');
    await app.serveur.retablir();
    await app.fermer(t);
  });
}
