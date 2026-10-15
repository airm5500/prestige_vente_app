// PERFORMANCE — LONGUES LISTES et PANIER : temps de chaque image (horloge réelle) pendant le défilement,
// contre le faux serveur Prestige (données fictives) :
//  - Recherche Article : 500 produits chargés par pages de 50 en descendant (application entière) ;
//  - Préventes à encaisser : 200 préventes (application entière, menu Pré-vente) ;
//  - Réserve : suggestion de 300 lignes (écran de traitement, client de la Réserve sur le faux serveur) ;
//  - Journal du terminal : 1 000 actions du jour ;
//  - Vente : 50 lignes ajoutées au panier une à une (temps par ligne, pire image, requêtes par ligne).
// Chaque liste est parcourue deux fois : le premier passage (à froid : code compilé, polices, premières
// constructions) a un seuil large, le second (images « courantes ») les seuils de défilement.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestige_vente_app/horsligne/catalogue_sync.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_screen.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart';
import 'package:prestige_vente_app/horsligne/server_monitor.dart';
import 'package:prestige_vente_app/horsligne/vente_hors_ligne.dart';
import 'package:prestige_vente_app/horsligne/ventes_sync.dart';
import 'package:prestige_vente_app/reserve/reserve_api.dart';
import 'package:prestige_vente_app/reserve/reserve_traitement_screen.dart';
import 'package:prestige_vente_app/screens/product_search/product_search_screen.dart';
import 'package:prestige_vente_app/serveur/client_prestige.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import '../outils/app_e2e.dart';
import '../outils/parcours_vente.dart';
import '../outils/performance.dart';

/// Parcourt deux fois la liste principale : mesures « à froid » puis « courantes ».
Future<void> mesurerDefilement(WidgetTester t, String nom, {Future<void> Function()? apresPas, double pas = 120}) async {
  final liste = plusGrandeListe(t);
  final froid = ChronoImages();
  await defilerJusquEnBas(t, liste, froid, apresPas: apresPas, pas: pas);
  await remonter(t, plusGrandeListe(t));
  final courant = ChronoImages();
  await defilerJusquEnBas(t, plusGrandeListe(t), courant, pas: pas);
  mesurer('$nom — pire image, 1er passage (à froid)', froid.max, seuil: Seuils.imageFroideMs, unite: 'ms', detail: froid.resume);
  mesurer('$nom — pire image, 2e passage', courant.max, seuil: Seuils.imageDefilementMs, unite: 'ms', detail: courant.resume);
  mesurer('$nom — 90 % des images, 2e passage', courant.p90, seuil: Seuils.imageCouranteMs, unite: 'ms');
}

Future<AppE2E> lancerConnecte(WidgetTester t, {int produits = 60, int preventes = 0, void Function(CatalogueFictif c)? avant}) async {
  TailleEcran.sunmiV2s.appliquer(t);
  final app = AppE2E();
  final c = CatalogueFictif(app.serveur, nombre: produits, preventes: preventes);
  avant?.call(c);
  await app.preparer(prefs: prefsVente);
  await app.lancer(t);
  expect(await app.seConnecter(t), isTrue);
  await app.attendre(t, const Duration(seconds: 3));
  return app;
}

/// Pompe par pas de 100 ms (chronométrés) jusqu'à ce que [ok] soit vrai (au plus [max]).
Future<bool> attendreChrono(WidgetTester t, ChronoImages chrono, bool Function() ok, {Duration max = const Duration(seconds: 10)}) async {
  var ecoule = Duration.zero;
  while (!ok() && ecoule < max) {
    await chrono.pump(t, const Duration(milliseconds: 100));
    ecoule += const Duration(milliseconds: 100);
  }
  return ok();
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  testWidgets('Recherche Article : 500 produits (10 pages de 50) chargés en descendant', (t) async {
    final app = await lancerConnecte(t, produits: 500);
    await app.ouvrirMenu(t, ListPresentation.dashboard, 'search');
    expect(find.byType(ProductSearchScreen), findsOneWidget);
    final sw = Stopwatch()..start();
    final rs = await compterRequetes(app.serveur, () async {
      await t.enterText(find.byType(TextField).first, 'PRODUIT');
      expect(await app.attendreQue(t, find.text('PRODUIT 0001 CPR B/20')), isTrue);
      mesurer('Recherche Article — 1re page affichée (frappe → liste)', sw.elapsedMicroseconds / 1000, seuil: Seuils.ouvertureListeMs, unite: 'ms');
      await mesurerDefilement(t, 'Recherche Article (500 produits)', apresPas: () => t.pump(const Duration(milliseconds: 20)));
    });
    expect(find.text('PRODUIT 0500 CPR B/20'), findsOneWidget, reason: 'dernier produit atteint');
    final pages = rs.where((r) => r.chemin.endsWith('/vente/search')).toList();
    mesurer('Recherche Article (500 produits) — requêtes', pages.length, seuil: 10, unite: 'requêtes', detail: detailRequetes(rs));
    expect([for (final r in pages) r.query['start']], [for (var i = 0; i < 10; i++) '${i * 50}'], reason: 'chaque page une seule fois, dans l\'ordre');
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  testWidgets('Préventes à encaisser : 200 préventes', (t) async {
    final app = await lancerConnecte(t, preventes: 200);
    await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
    final sw = Stopwatch()..start();
    final rs = await compterRequetes(app.serveur, () async {
      await t.tap(find.text('Préventes à encaisser').first);
      expect(await app.attendreQue(t, find.textContaining('200 préventes')), isTrue);
    });
    mesurer('Préventes à encaisser (200) — ouverture de la liste', sw.elapsedMicroseconds / 1000, seuil: Seuils.ouvertureListeMs, unite: 'ms');
    mesurer('Préventes à encaisser (200) — requêtes à l\'ouverture', rs.length, seuil: 1, unite: 'requêtes', detail: detailRequetes(rs));
    await mesurerDefilement(t, 'Préventes à encaisser (200)');
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  testWidgets('Réserve : suggestion de 300 lignes (traitement)', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final s = FauxServeurPrestige(exigerSession: false)..installerEnMemoire();
    addTearDown(s.desinstaller);
    s.routes['PUT /S1/ouvrir'] = (_) => FauxServeurPrestige.ok({
          'success': true,
          'entete': DonneesFictives.enteteReserve(),
          'lignes': [for (var i = 1; i <= 300; i++) DonneesFictives.ligneReserve('$i', proposee: 1 + i % 9, rayon: i % 5, reserve: 20)],
          'modifiable': true,
        });
    s.routes['PUT /S1/liberer'] = (_) => FauxServeurPrestige.ok({'success': true});
    final sw = Stopwatch()..start();
    await t.pumpWidget(MaterialApp(home: ReserveTraitementScreen(suggestionId: 'S1', api: ReserveApi(ClientPrestige(() => s.base)))));
    final chrono = ChronoImages();
    expect(await attendreChrono(t, chrono, () => find.text('PRODUIT DEMO 1').evaluate().isNotEmpty), isTrue);
    mesurer('Réserve (300 lignes) — ouverture', sw.elapsedMicroseconds / 1000, seuil: Seuils.ouvertureListeMs, unite: 'ms', detail: chrono.resume);
    expect(s.recues.where((r) => r.chemin.endsWith('/ouvrir')), hasLength(1));
    await mesurerDefilement(t, 'Réserve (300 lignes)');
    expect(find.text('PRODUIT DEMO 300'), findsOneWidget, reason: 'dernière ligne atteinte');
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('Journal du terminal : 1 000 actions du jour', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final store = MemoryLocalStore();
    final hl = HorsLigne(monitor: ServerMonitor(), store: store, sync: CatalogueSync(store: store), ventes: FileVentesHL(store: MemoryVentesHLStore()));
    final hlAvant = HorsLigne.instance;
    HorsLigne.instance = hl;
    addTearDown(() => HorsLigne.instance = hlAvant);
    var now = DateTime.now().copyWith(hour: 6, minute: 0, second: 0);
    final j = JournalTerminal(clock: () => now)
      ..terminalId = 'T-TEST01'
      ..terminalNom = 'SUNMI V2'
      ..utilisateur = 'Awa';
    for (var i = 1; i <= 1000; i++) {
      now = now.add(const Duration(seconds: 30));
      await j.noter(
        type: i % 3 == 0 ? TypeJournal.stock : TypeJournal.encaissement,
        action: 'Action $i',
        refServeur: 'PV-${i.toString().padLeft(4, '0')}',
        montant: 1000 + i,
        modes: {'1': 1000 + i},
        produits: [JournalProduit(id: 'p$i', nom: 'PRODUIT ${i.toString().padLeft(4, '0')}', qte: 1 + i % 4)],
      );
    }
    final sw = Stopwatch()..start();
    await t.pumpWidget(MaterialApp(home: JournalTerminalScreen(journal: j)));
    final chrono = ChronoImages();
    expect(await attendreChrono(t, chrono, () => find.text('1000 action(s) · 0 refus · 0 échec(s) réseau').evaluate().isNotEmpty), isTrue);
    mesurer('Journal (1 000 actions) — ouverture', sw.elapsedMicroseconds / 1000, seuil: Seuils.ouvertureListeMs, unite: 'ms', detail: chrono.resume);
    await mesurerDefilement(t, 'Journal du terminal (1 000 actions)', pas: 240);
    expect(t.takeException(), isNull);
  });

  testWidgets('Vente : 50 lignes ajoutées au panier (temps par ligne, pire image, requêtes par ligne)', (t) async {
    final app = await lancerConnecte(t, produits: 60);
    await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
    final chrono = ChronoImages();
    final sw = Stopwatch()..start();
    final toutes = await compterRequetes(app.serveur, () async {
      for (var i = 1; i <= 50; i++) {
        await t.enterText(champRechercheVente, nomCourt(i));
        expect(await attendreChrono(t, chrono, () => champQuantite.evaluate().isNotEmpty), isTrue, reason: 'ligne $i : fenêtre de quantité');
        await t.enterText(champQuantite, '${1 + i % 3}');
        await t.tap(find.text('Ajouter'));
        final nets = i;
        expect(await attendreChrono(t, chrono, () => app.serveur.recuesSur('/vente/net/vno').length >= nets && champQuantite.evaluate().isEmpty), isTrue,
            reason: 'ligne $i enregistrée');
        await chrono.pump(t, const Duration(milliseconds: 100));
      }
    });
    final ms = sw.elapsedMicroseconds / 1000;
    expect(app.serveur.ventes.values.single, hasLength(50), reason: '50 lignes sur le serveur, une seule vente');
    expect(find.textContaining('50 articles'), findsWidgets);
    mesurer('Vente — ajout d\'une ligne (moyenne sur 50)', ms / 50, seuil: Seuils.ajoutLigneMs, unite: 'ms');
    mesurer('Vente — pire image pendant l\'ajout de 50 lignes', chrono.max, seuil: Seuils.imageVenteMs, unite: 'ms', detail: chrono.resume);
    // Par ligne : recherche (1), ajout (1), lignes de la vente (1), net (1). (Hors vente : l'actualisation
    // périodique de l'accueil, toujours ouvert sous la vente, n'est pas comptée.)
    final rs = [for (final r in toutes) if (r.chemin.contains('/vente/')) r];
    mesurer('Vente — requêtes pour 50 lignes', rs.length, seuil: 50 * 4, unite: 'requêtes', detail: detailRequetes(rs));
    await mesurerDefilement(t, 'Panier de 50 lignes');
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });
}
