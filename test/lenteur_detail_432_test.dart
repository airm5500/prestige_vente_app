// 4.3.2 — Lenteur signalée par le pharmacien (vidéo du 15/10) : « Analyse article affichait les données et le graphe
// en un temps record ; depuis l'ajout du stock réserve, tout met du temps à charger » (Analyse article, onglet
// Scanner → fiche produit, recherche de l'accueil → fiche produit).
//
// Cause (docs/NOTE_VERSION_4.3.2.md) : depuis la 4.2.0, la liste vient de GET /vente/search (rapide) et le détail
// lit GET /info APRÈS le clic ; sur le serveur, GET /info agrège 6 mois de ventes de TOUT le catalogue avant de
// filtrer (demande 44) : chaque ouverture attend ce calcul complet. Avant (4.1.x), la liste venait de GET /info lui-même
// et le détail s'ouvrait sans requête. Le stock réserve n'ajoute aucune requête (il arrive dans GET /info).
//
// Correction vérifiée ici (application entière, faux serveur LENT) :
// - mode hybride : liste rapide, puis UN GET /info de la saisie (lot) dès la liste ; clic → identité, stock, prix
//   (et prix d'achat, emplacement) tout de suite, graphe dès que GET /info répond, sans 2ᵉ requête ;
// - un détail fermé avant la réponse ne fait plus perdre la requête (réouverture immédiate) ;
// - aucune lecture secondaire (images) ne retarde la principale ;
// - FicheInfoCache : lot, prolongation de saisie, échec, produit absent du lot, abandon, délai.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/accueil/fiche_produit_screen.dart';
import 'package:prestige_vente_app/accueil/recherche_globale_screen.dart';
import 'package:prestige_vente_app/api/models/article_analysis_model.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/screens/analysis/article_analysis_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import 'outils/analyse_fictive.dart';
import 'outils/app_e2e.dart';
import 'outils/performance.dart';

List<String?> _recherchesInfo(AppE2E app, [int depuis = 0]) => [for (final r in app.serveur.recuesSur('/info').skip(depuis)) r.query['search']];

/// Temps simulé jusqu'à ce que [f] apparaisse (pas de 50 ms), au plus [max].
Future<Duration> _jusqua(WidgetTester t, Finder f, {Duration max = const Duration(seconds: 40)}) async {
  final debut = t.binding.clock.now();
  while (f.evaluate().isEmpty) {
    if (t.binding.clock.now().difference(debut) > max) break;
    await t.pump(const Duration(milliseconds: 50));
  }
  return t.binding.clock.now().difference(debut);
}

ProductSearchResult _p(Map<String, dynamic> j) => ProductSearchResult.fromJson(j);
ArticleAnalysis _a(Map<String, dynamic> j) => ArticleAnalysis.fromJson(j);

void main() {
  // =====================================================================================================
  group('Performance — Analyse article (serveur lent : GET /info 4 s)', () {
    for (final style in ListPresentation.values) {
      testWidgets('${style.label} : ordre et nombre des requêtes ; identité, stock, prix immédiats ; graphe à la réponse du lot',
          (t) async {
        final app = await lancerAnalyse(t, style: style);
        await app.ouvrirMenu(t, style, 'analyse_article');
        expect(find.byType(ArticleAnalysisScreen), findsOneWidget);
        final infoAvant = app.serveur.recuesSur('/info').length;
        final rechercheAvant = app.serveur.recuesSur('/vente/search').length;

        await frappeAnalyse(t, 'doli');
        final liste = await _jusqua(t, find.text(analyseDoliD));
        mesurer('Analyse article : liste après la dernière frappe (serveur lent)', liste.inMilliseconds,
            seuil: 1000, unite: 'ms', detail: 'anti-rebond 350 ms + GET /vente/search');
        // Une recherche (saisie finale), puis UN lot GET /info de la saisie, jamais un par lettre.
        expect([for (final r in app.serveur.recuesSur('/vente/search').skip(rechercheAvant)) r.query['query']], ['doli']);
        expect(_recherchesInfo(app, infoAvant), ['doli']);

        // L'utilisateur lit la liste 1 s puis choisit un produit.
        await app.attendre(t, const Duration(seconds: 1));
        final cible = style == ListPresentation.guided ? find.text("Voir l'analyse complète") : find.text(analyseDoli).hitTestable();
        await t.tap(cible.first);
        await t.pump();
        await t.pump(const Duration(milliseconds: 50));
        // Première image du détail : nom, CIP, stock, prix de vente, prix d'achat, emplacement — avant toute réponse.
        expect(find.text("Détails de l'Article"), findsOneWidget);
        expect(find.text('Code CIP: 3595583'), findsOneWidget);
        expect(find.text('1475 FCFA'), findsOneWidget);
        expect(find.text('976 FCFA'), findsOneWidget);
        expect(find.text('ANTALGIQUES'), findsOneWidget);
        expect(find.byKey(const ValueKey('analyse-detail-chargement')), findsOneWidget);
        expect(_recherchesInfo(app, infoAvant), ['doli'], reason: 'le détail attend le lot : aucune 2ᵉ requête');

        final graphe = await _jusqua(t, find.byKey(const ValueKey('analyse-detail')));
        mesurer('Analyse article : graphe après le clic (lot parti 1 s avant, serveur 4 s)', graphe.inMilliseconds,
            seuil: 3300, unite: 'ms', detail: 'avant 4.3.2 : ≥ 4000 ms (GET /info lancé au clic)');
        expect(graphe, lessThan(lentAnalyse), reason: 'le lot était parti avec la liste : attente plus courte que GET /info');
        expect(find.text('RAYON F-DOLI'), findsOneWidget, reason: 'la ligne du produit choisi (pas 3595583D)');
        expect(find.byKey(const ValueKey('analyse-stock-reserve')), findsOneWidget);
        expect(_recherchesInfo(app, infoAvant), ['doli']);

        // 2ᵉ produit de la même liste : détail complet dès la 1ʳᵉ image, aucune requête.
        await t.tap(find.text('Fermer'));
        await app.attendre(t, const Duration(milliseconds: 500));
        if (style != ListPresentation.guided) {
          await t.tap(find.text(analyseDoliD).hitTestable().first);
          await t.pump();
          await t.pump(const Duration(milliseconds: 50));
          expect(find.text('RAYON DETAIL'), findsOneWidget, reason: '2ᵉ produit servi par le lot, sans attente');
          expect(find.byKey(const ValueKey('analyse-detail-chargement')), findsNothing);
          expect(_recherchesInfo(app, infoAvant), ['doli']);
          await t.tap(find.text('Fermer'));
          await app.attendre(t, const Duration(milliseconds: 500));
        }
        expect(t.takeException(), isNull);
        await app.fermer(t);
      });
    }

    testWidgets('clic immédiat (lot à peine parti) : une seule requête, graphe à la réponse ; saisie prolongée : rien de plus',
        (t) async {
      final app = await lancerAnalyse(t);
      await app.ouvrirMenu(t, ListPresentation.dashboard, 'analyse_article');
      final infoAvant = app.serveur.recuesSur('/info').length;
      await frappeAnalyse(t, 'doli');
      await _jusqua(t, find.text(analyseDoli));
      await t.tap(find.text(analyseDoli).hitTestable().first);
      await t.pump();
      expect(find.text('1475 FCFA'), findsOneWidget);
      final graphe = await _jusqua(t, find.byKey(const ValueKey('analyse-detail')));
      expect(graphe, lessThanOrEqualTo(lentAnalyse + const Duration(milliseconds: 100)));
      expect(_recherchesInfo(app, infoAvant), ['doli']);
      await t.tap(find.text('Fermer'));
      await app.attendre(t, const Duration(milliseconds: 500));
      // « dolip » prolonge « doli » (lot arrivé) : aucune nouvelle lecture GET /info.
      await t.enterText(find.byType(TextField).first, 'doliprane');
      await app.attendre(t, const Duration(seconds: 1));
      expect(_recherchesInfo(app, infoAvant), ['doli']);
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });

    testWidgets('détail fermé avant la réponse puis rouvert : la requête n\'est pas perdue (pas de nouvelle attente complète)',
        (t) async {
      final app = await lancerAnalyse(t, info: const Duration(seconds: 6));
      await app.ouvrirMenu(t, ListPresentation.dashboard, 'analyse_article');
      final infoAvant = app.serveur.recuesSur('/info').length;
      await frappeAnalyse(t, 'ibex');
      await _jusqua(t, find.text(analyseIbex));
      await t.tap(find.text(analyseIbex).hitTestable().first);
      await app.attendre(t, const Duration(seconds: 2));
      expect(find.byKey(const ValueKey('analyse-detail-chargement')), findsOneWidget);
      await t.tap(find.text('Fermer'));
      await app.attendre(t, const Duration(seconds: 2));
      await t.tap(find.text(analyseIbex).hitTestable().first);
      final graphe = await _jusqua(t, find.text('RAYON IBEX'));
      expect(graphe, lessThan(const Duration(seconds: 3)), reason: 'la réponse en route est reprise (avant : nouvelle requête de 6 s)');
      expect(_recherchesInfo(app, infoAvant), ['ibex']);
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });

    testWidgets('liste longue (plus de 30 produits) : pas de lot, GET /info par le CIP exact au clic', (t) async {
      final app = await lancerAnalyse(t);
      app.serveur.routes['GET /vente/search'] = (r) {
        final l = [for (var i = 0; i < 31; i++) produitAnalyse('L$i', 'DOLI LOT $i', '77${i.toString().padLeft(5, '0')}', 100, 1)];
        return FauxServeurPrestige.ok({'data': l, 'total': l.length});
      };
      await app.ouvrirMenu(t, ListPresentation.dashboard, 'analyse_article');
      final infoAvant = app.serveur.recuesSur('/info').length;
      await frappeAnalyse(t, 'doli');
      await app.attendre(t, const Duration(seconds: 1));
      expect(_recherchesInfo(app, infoAvant), isEmpty, reason: 'saisie trop large : aucun lot');
      await t.tap(find.text('DOLI LOT 0').hitTestable().first);
      await app.attendre(t, const Duration(milliseconds: 300));
      expect(_recherchesInfo(app, infoAvant), ['7700000']);
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });
  });

  // =====================================================================================================
  group('Performance — fiche produit', () {
    testWidgets('recherche de l\'accueil : fiche immédiate, analyse à la réponse du lot, images lentes sans effet', (t) async {
      final app = await lancerAnalyse(t, images: const Duration(seconds: 20));
      await app.defilerJusqua(t, find.text('Rechercher un menu ou un produit'));
      await t.tap(find.text('Rechercher un menu ou un produit'));
      await app.attendre(t);
      expect(find.byType(RechercheGlobaleScreen), findsOneWidget);
      final infoAvant = app.serveur.recuesSur('/info').length;
      await frappeAnalyse(t, 'ibex');
      await _jusqua(t, find.text(analyseIbex));
      expect(_recherchesInfo(app, infoAvant), ['ibex'], reason: 'lot de la saisie, après la liste');
      await app.attendre(t, const Duration(seconds: 1));
      await t.tap(find.text(analyseIbex).hitTestable().first);
      await t.pump();
      await t.pump(const Duration(milliseconds: 350)); // transition de page
      expect(find.byType(FicheProduitScreen), findsOneWidget);
      expect(find.text('37'), findsWidgets, reason: 'stock tout de suite');
      expect(find.byKey(const ValueKey('fiche-connu-Emplacement')), findsOneWidget);
      expect(find.byKey(const ValueKey("fiche-connu-Prix d'achat")), findsOneWidget);
      expect(find.byKey(const ValueKey('fiche-squelette-Grossiste')), findsOneWidget);
      final analyse = await _jusqua(t, find.byKey(const ValueKey('fiche-info-Grossiste')));
      mesurer('Fiche produit (accueil) : analyse après l\'ouverture (lot parti 1 s avant, serveur 4 s, images 20 s)',
          analyse.inMilliseconds,
          seuil: 3300, unite: 'ms', detail: 'les images lentes ne retardent pas GET /info');
      expect(analyse, lessThan(const Duration(seconds: 4)));
      expect(_recherchesInfo(app, infoAvant), ['ibex'], reason: 'aucune 2ᵉ requête');
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });

    testWidgets('onglet Scanner (code) : recherche par code PUIS GET /info du CIP, fiche immédiate, aucun lot', (t) async {
      TailleEcran.sunmiV2s.appliquer(t);
      FicheInfoCache.instance.vider();
      addTearDown(FicheInfoCache.instance.vider);
      final app = appAnalyse();
      await app.preparer(prefs: {'hiddenMenuIds': <String>[]});
      await app.lancer(t);
      expect(await app.seConnecter(t, login: DonneesFictives.admin, motDePasse: DonneesFictives.motDePasseAdmin), isTrue);
      await app.attendre(t);
      final debut = app.serveur.recues.length;
      // Douchette (clavier + Entrée) dans la recherche : comme un code lu par l'onglet Scanner.
      await app.defilerJusqua(t, find.text('Rechercher un menu ou un produit'));
      await t.tap(find.text('Rechercher un menu ou un produit'));
      await app.attendre(t);
      await t.enterText(find.byType(TextField).first, '8049052');
      await t.testTextInput.receiveAction(TextInputAction.search);
      await t.pump();
      final fiche = await _jusqua(t, find.byType(FicheProduitScreen));
      expect(fiche, lessThan(const Duration(seconds: 1)), reason: 'fiche ouverte sans attendre GET /info');
      await t.pump(const Duration(milliseconds: 350));
      expect(find.text('37'), findsWidgets);
      final ordre = [
        for (final r in app.serveur.recues.skip(debut))
          if (r.chemin.endsWith('/info') || r.chemin.endsWith('/vente/search')) '${r.chemin.split('/').last}:${r.query['search'] ?? r.query['query']}'
      ];
      expect(ordre.last, 'info:8049052', reason: 'GET /info par le CIP exact, après la recherche par code');
      expect(ordre.where((e) => e.startsWith('info:')), hasLength(1));
      await _jusqua(t, find.byKey(const ValueKey('fiche-info-Grossiste')));
      expect(find.text('RAYON IBEX'), findsOneWidget);
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });
  });

  // =====================================================================================================
  group('Unitaires — FicheInfoCache (lot de la saisie)', () {
    final doli = _p(catalogueAnalyse[0]);
    final doliD = _p(catalogueAnalyse[1]);
    final ibex = _p(catalogueAnalyse[2]);
    const src = 'S';
    String cle(ProductSearchResult p) => '$src|${p.lgFAMILLEID}|${p.intCIP}';

    test('produit couvert par le lot en route : on attend CE lot (aucune requête propre), ligne du bon produit', () async {
      final c = FicheInfoCache();
      final lot = Completer<List<ArticleAnalysis>>();
      var lots = 0;
      c.chargerSaisie(src, 'doli', (_) {
        lots++;
        return lot.future;
      });
      var cip = 0;
      final f = c.charger(cle(doli), (_) async {
        cip++;
        return null;
      }, produit: doli);
      lot.complete([for (final j in infoAnalyseSearch('doli')) _a(j)]);
      final a = await f;
      expect(a!.emplacement, 'RAYON F-DOLI');
      expect(a.reserve.stockReserve, 20);
      expect((lots, cip, c.servisParLot), (1, 0, 1));
      // Un autre produit couvert, après l'arrivée : immédiat, sans requête.
      expect(c.connuPour(cle(doliD), doliD)!.article!.emplacement, 'RAYON DETAIL');
      expect(c.requetes, 0);
    });

    test('produit non couvert (autre nom, autre CIP) : requête par le CIP exact, sans attendre le lot', () async {
      final c = FicheInfoCache();
      c.chargerSaisie(src, 'doli', (_) => Completer<List<ArticleAnalysis>>().future);
      final a = await c.charger(cle(ibex), (_) async => _a(infoAnalyseSearch('8049052').single), produit: ibex);
      expect(a!.emplacement, 'RAYON IBEX');
      expect(c.requetes, 1);
    });

    test('saisie qui prolonge la précédente : aucun nouveau lot ; autre saisie : l\'ancien lot (non attendu) est abandonné',
        () async {
      final c = FicheInfoCache();
      final jetons = <CancelToken>[];
      Future<List<ArticleAnalysis>> lecture(CancelToken j) {
        jetons.add(j);
        return Completer<List<ArticleAnalysis>>().future;
      }

      c.chargerSaisie(src, 'dol', lecture);
      c.chargerSaisie(src, 'doli', lecture);
      c.chargerSaisie(src, 'DOLIP', lecture);
      expect(c.lots, 1, reason: '« doli », « DOLIP » couverts par « dol »');
      c.chargerSaisie(src, 'ibex', lecture);
      expect(c.lots, 2);
      expect(jetons.first.isCancelled, isTrue);
      expect(c.lotsAnnules, 1);
      expect(c.lotEnRoute(src), 'IBEX');
    });

    test('lot attendu par un détail : jamais abandonné par une nouvelle saisie ; 2 caractères : aucun lot', () async {
      final c = FicheInfoCache();
      final lot = Completer<List<ArticleAnalysis>>();
      CancelToken? jeton;
      c.chargerSaisie(src, 'doli', (j) {
        jeton = j;
        return lot.future;
      });
      final f = c.charger(cle(doli), (_) async => null, produit: doli);
      c.lacherSaisie(src);
      expect(jeton!.isCancelled, isFalse);
      lot.complete([for (final j in infoAnalyseSearch('doli')) _a(j)]);
      expect((await f)!.codeCip, '3595583');
      c.chargerSaisie(src, 'do', (_) async => throw StateError('jamais'));
      expect(c.lots, 1);
    });

    test('lot en échec (délai) : même cause pour le détail qui l\'attendait ; Réessayer → CIP exact', () async {
      final c = FicheInfoCache();
      c.chargerSaisie(src, 'doli', (_) async => throw Exception('Délai dépassé : pas de réponse du serveur en 30 s (GET /info).'));
      final f = c.charger(cle(doli), (_) async => null, produit: doli);
      await expectLater(f, throwsA(isA<Exception>().having((e) => '$e', 'message', contains('Délai dépassé'))));
      expect(c.requetes, 0, reason: 'aucune 2ᵉ attente complète enchaînée');
      final a = await c.charger(cle(doli), (_) async => _a(infoAnalyseSearch('3595583').last), produit: doli);
      expect(a!.emplacement, 'RAYON F-DOLI');
      expect(c.requetes, 1);
    });

    test('produit couvert mais absent du lot : requête par son CIP (prudence)', () async {
      final c = FicheInfoCache();
      c.chargerSaisie(src, 'doli', (_) async => [_a(infoAnalyseSearch('3595583D').single)]);
      await Future<void>.delayed(Duration.zero);
      final a = await c.charger(cle(doli), (_) async => _a(infoAnalyseSearch('3595583').last), produit: doli);
      expect(a!.codeCip, '3595583');
      expect(c.requetes, 1);
    });

    test('écran fermé : la requête continue et remplit le cache ; délai dépassé : oubliée, Réessayer en relance une', () async {
      final c = FicheInfoCache();
      final rep = Completer<ArticleAnalysis?>();
      CancelToken? jeton;
      final f = c.charger(cle(ibex), (j) {
        jeton = j;
        return rep.future;
      });
      c.lacher(cle(ibex));
      expect(jeton!.isCancelled, isFalse);
      rep.complete(_a(infoAnalyseSearch('8049052').single));
      await f;
      expect(c.connu(cle(ibex))!.article!.emplacement, 'RAYON IBEX');

      final muette = Completer<ArticleAnalysis?>();
      CancelToken? j2;
      c.charger(cle(doli), (j) {
        j2 = j;
        return muette.future;
      }).ignore();
      c.abandonner(cle(doli));
      expect(j2!.isCancelled, isTrue);
      expect(c.enCours(cle(doli)), isFalse);
      expect(await c.charger(cle(doli), (_) async => _a(infoAnalyseSearch('3595583').last)), isNotNull);
    });

    test('cache mémoire court (2 min), jamais sur disque : réponse périmée oubliée', () async {
      var maintenant = DateTime(2026, 10, 15, 10);
      final c = FicheInfoCache(horloge: () => maintenant);
      await c.charger(cle(ibex), (_) async => _a(infoAnalyseSearch('8049052').single));
      expect(c.connu(cle(ibex)), isNotNull);
      maintenant = maintenant.add(const Duration(minutes: 2, seconds: 1));
      expect(c.connu(cle(ibex)), isNull);
    });
  });
}
