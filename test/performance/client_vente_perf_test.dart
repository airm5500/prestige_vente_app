// PERFORMANCE — 4.13.0 : client d'une vente comptant (application entière, faux serveur en mémoire, données FICTIVES) :
//  - requêtes de l'encaissement SANS client : une de MOINS qu'en 4.12.1 (plus de POST v1/vente/update/client avec le
//    nom du mode) ; AUCUNE route client ;
//  - recherche tapée vite (« K », « KO », … « KOFFI ») : UNE requête GET v1/client/lambda ;
//  - choisir un client : UNE requête POST v1/vente/update/client ; aucune relecture de la vente ;
//  - lecture de 50 réponses de 2 000 clients en moins de 1 s ;
//  - page de recherche avec 300 résultats : affichée et parcourue sans image lente.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import '../outils/app_e2e.dart';
import '../outils/clients_vente_fictifs.dart';
import '../outils/faux_serveur_prestige.dart';
import '../outils/parcours_vente.dart';
import '../outils/performance.dart';

Future<(AppE2E, ClientsVenteFictifs)> _vente(WidgetTester t) async {
  TailleEcran.sunmiV2s.appliquer(t);
  final app = AppE2E();
  CatalogueFictif(app.serveur, nombre: 10);
  final cl = ClientsVenteFictifs(app.serveur);
  await app.preparer(prefs: prefsVente);
  await app.lancer(t);
  expect(await app.seConnecter(t), isTrue);
  await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
  expect(await ajouterAuPanier(t, app, nomCourt(3)), isTrue);
  await app.attendre(t, const Duration(seconds: 2));
  return (app, cl);
}

String _route(RequeteRecue r) => '${r.methode} ${r.chemin.replaceFirst(RegExp(r'^.*/api/v1'), '')}';

void main() {
  testWidgets('encaissement SANS client : plus de POST vente/update/client, aucune route client', (t) async {
    final (app, _) = await _vente(t);
    final avant = app.serveur.recues.length;
    await validerEncaissementEspeces(t, app);
    await app.attendre(t, const Duration(seconds: 3));
    final routes = [for (final r in app.serveur.recues.skip(avant)) _route(r)];
    expect(routes.where((r) => r.contains('/client')), isEmpty, reason: '$routes');
    expect(routes.where((r) => r == 'POST /vente/cloturer/vno'), hasLength(1));
    mesurer('Requêtes — encaissement d\'une vente sans client : vente/update/client', routes.where((r) => r.contains('update/client')).length,
        seuil: 0, unite: 'requêtes', detail: 'avant 4.13.0 : 1 (nom du mode de règlement)');
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  testWidgets('recherche tapée vite : UNE requête ; choisir : UNE requête de rattachement', (t) async {
    final (app, cl) = await _vente(t);
    await t.tap(find.byKey(const ValueKey('client-vente-ouvrir')));
    await app.attendre(t, const Duration(milliseconds: 600));
    final avant = app.serveur.recues.length;
    for (final s in ['K', 'KO', 'KOF', 'KOFF', 'KOFFI']) {
      await t.enterText(find.byKey(const ValueKey('client-vente-recherche')), s);
      await t.pump(const Duration(milliseconds: 120));
    }
    expect(await app.attendreQue(t, find.byKey(const ValueKey('client-vente-resultat-CL-FICT-1'))), isTrue);
    final recherche = [for (final r in app.serveur.recues.skip(avant)) _route(r)];
    mesurer('Requêtes — Client : recherche tapée vite', recherche.length, seuil: 1, unite: 'requêtes', detail: recherche.join(', '));
    expect(recherche, ['GET /client/lambda']);
    final avantChoix = app.serveur.recues.length;
    await t.tap(find.byKey(const ValueKey('client-vente-resultat-CL-FICT-1')));
    await app.attendre(t, const Duration(seconds: 1));
    final choix = [for (final r in app.serveur.recues.skip(avantChoix)) _route(r)];
    mesurer('Requêtes — Client : choix d\'un client', choix.length, seuil: 1, unite: 'requêtes', detail: choix.join(', '));
    expect(choix, ['POST /vente/update/client']);
    expect(cl.clientDeVente['V-1'], 'CL-FICT-1');
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  test('lecture : 50 réponses de 2 000 clients en moins de 1 s', () {
    final data = [
      for (var i = 0; i < 2000; i++) {'lgCLIENTID': 'CL-$i', 'strFIRSTNAME': 'NOM-FICTIF-$i', 'strLASTNAME': 'PRENOM', 'strADRESSE': '07000${i.toString().padLeft(5, '0')}'}
    ];
    final sw = Stopwatch()..start();
    var n = 0;
    for (var k = 0; k < 50; k++) {
      for (final e in data) {
        if (ClientVente.depuisJson(e) != null) n++;
      }
    }
    sw.stop();
    expect(n, 100000);
    mesurer('Client : lecture de 100 000 clients (50 × 2 000)', sw.elapsedMilliseconds, seuil: 1000, unite: 'ms');
    expect(sw.elapsedMilliseconds, lessThan(1000));
  });

  testWidgets('page de recherche, 300 résultats : pire image en parcourant la liste', (t) async {
    final (app, cl) = await _vente(t);
    for (var i = 0; i < 300; i++) {
      cl.ajouter('CL-P$i', 'KOFFI-PERF', 'PRENOM ${i.toString().padLeft(3, '0')}', '07${i.toString().padLeft(8, '0')}');
    }
    await t.tap(find.byKey(const ValueKey('client-vente-ouvrir')));
    await app.attendre(t, const Duration(milliseconds: 600));
    await t.enterText(find.byKey(const ValueKey('client-vente-recherche')), 'KOFFI-PERF');
    expect(await app.attendreQue(t, find.text('300 clients')), isTrue);
    final liste = find.descendant(of: find.byKey(const ValueKey('client-vente-page')), matching: find.byType(Scrollable)).first;
    final chrono = ChronoImages();
    await defilerJusquEnBas(t, liste, chrono);
    mesurer('Client : 300 résultats — pire image en parcourant la liste', chrono.max, seuil: Seuils.imageFroideMs, unite: 'ms', detail: chrono.resume);
    expect(chrono.max, lessThan(Seuils.imageFroideMs));
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });
}
