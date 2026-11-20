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
//   (et prix d'achat, emplacement) tout de suite, graphe dès que GET /info répond ;
// - 5.1.0 (retour du 20/11, Analyse article lente) : le lot n'est utilisé au clic que s'il est DÉJÀ arrivé ; sinon le
//   CIP exact est demandé tout de suite (avant : le détail attendait tout le lot, jusqu'à 30 produits) ; lot limité
//   aux listes de 5 produits au plus ; un détail fermé avant la réponse ANNULE sa requête ;
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
      testWidgets('${style.label} : ordre et nombre des requêtes ; identité, stock, prix immédiats ; graphe à la réponse du CIP (lot lent non attendu)',
          (t) async {
        // 5.1.0 : lot de la saisie lent (12 s), CIP exact 2 s.
        final app = await lancerAnalyse(t, style: style, info: const Duration(seconds: 2), infoLot: const Duration(seconds: 12));
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
        expect(_recherchesInfo(app, infoAvant), ['doli', '3595583'], reason: 'lot en route non attendu : CIP exact tout de suite');

        final graphe = await _jusqua(t, find.byKey(const ValueKey('analyse-detail')));
        mesurer('Analyse article : graphe après le clic (lot de 12 s en route, CIP 2 s)', graphe.inMilliseconds,
            seuil: 2300, unite: 'ms', detail: 'avant 5.1.0 : le détail attendait la fin du lot (11 s ici)');
        expect(graphe, lessThan(const Duration(seconds: 3)), reason: 'réponse du CIP, sans attendre le lot');
        expect(find.text('RAYON F-DOLI'), findsOneWidget, reason: 'la ligne du produit choisi (pas 3595583D)');
        expect(find.byKey(const ValueKey('analyse-stock-reserve')), findsOneWidget);

        // Lot arrivé ensuite : 2ᵉ produit de la même liste complet dès la 1ʳᵉ image, aucune requête.
        await t.tap(find.text('Fermer'));
        await app.attendre(t, const Duration(seconds: 10));
        if (style != ListPresentation.guided) {
          await t.tap(find.text(analyseDoliD).hitTestable().first);
          await t.pump();
          await t.pump(const Duration(milliseconds: 50));
          expect(find.text('RAYON DETAIL'), findsOneWidget, reason: '2ᵉ produit servi par le lot arrivé, sans attente');
          expect(find.byKey(const ValueKey('analyse-detail-chargement')), findsNothing);
          expect(_recherchesInfo(app, infoAvant), ['doli', '3595583']);
          await t.tap(find.text('Fermer'));
          await app.attendre(t, const Duration(milliseconds: 500));
        }
        expect(t.takeException(), isNull);
        await app.fermer(t);
      });
    }

    testWidgets('clic immédiat (lot à peine parti) : CIP exact tout de suite, graphe à sa réponse ; saisie prolongée : rien de plus',
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
      expect(_recherchesInfo(app, infoAvant), ['doli', '3595583']);
      await t.tap(find.text('Fermer'));
      await app.attendre(t, const Duration(milliseconds: 500));
      // « doliprane » prolonge « doli » (lot arrivé) : aucune nouvelle lecture GET /info.
      await t.enterText(find.byType(TextField).first, 'doliprane');
      await app.attendre(t, const Duration(seconds: 1));
      expect(_recherchesInfo(app, infoAvant), ['doli', '3595583']);
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });

    testWidgets('détail fermé avant la réponse : sa requête est annulée ; rouvert : nouvelle requête du CIP, détail à sa réponse',
        (t) async {
      final app = await lancerAnalyse(t, info: const Duration(seconds: 6));
      await app.ouvrirMenu(t, ListPresentation.dashboard, 'analyse_article');
      final infoAvant = app.serveur.recuesSur('/info').length;
      final abandonsAvant = FicheInfoCache.instance.abandons;
      await frappeAnalyse(t, 'ibex');
      await _jusqua(t, find.text(analyseIbex));
      await t.tap(find.text(analyseIbex).hitTestable().first);
      await app.attendre(t, const Duration(seconds: 2));
      expect(find.byKey(const ValueKey('analyse-detail-chargement')), findsOneWidget);
      await t.tap(find.text('Fermer'));
      await app.attendre(t, const Duration(milliseconds: 500));
      expect(FicheInfoCache.instance.abandons, abandonsAvant + 1, reason: 'requête du détail annulée à la fermeture');
      await t.tap(find.text(analyseIbex).hitTestable().first);
      final graphe = await _jusqua(t, find.text('RAYON IBEX'));
      expect(graphe, lessThan(const Duration(seconds: 7)));
      expect(_recherchesInfo(app, infoAvant), ['ibex', '8049052', '8049052']);
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });

    testWidgets('liste de plus de 5 produits (5.1.0 ; 30 avant) : pas de lot, GET /info par le CIP exact au clic', (t) async {
      final app = await lancerAnalyse(t);
      app.serveur.routes['GET /vente/search'] = (r) {
        final l = [for (var i = 0; i < produitsMaxLot + 1; i++) produitAnalyse('L$i', 'DOLI LOT $i', '77${i.toString().padLeft(5, '0')}', 100, 1)];
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
    testWidgets('recherche de l\'accueil : fiche immédiate, analyse à la réponse du CIP (lot lent non attendu), images lentes sans effet', (t) async {
      final app = await lancerAnalyse(t, info: const Duration(seconds: 2), infoLot: const Duration(seconds: 12), images: const Duration(seconds: 20));
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
      mesurer('Fiche produit (accueil) : analyse après l\'ouverture (lot de 12 s en route, CIP 2 s, images 20 s)',
          analyse.inMilliseconds,
          seuil: 2300, unite: 'ms', detail: 'ni le lot ni les images lentes ne retardent GET /info du CIP');
      expect(analyse, lessThan(const Duration(seconds: 3)));
      expect(_recherchesInfo(app, infoAvant), ['ibex', '8049052'], reason: 'CIP exact demandé à l\'ouverture');
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

    test('5.1.0 : produit couvert par le lot EN ROUTE : CIP exact tout de suite (lot non attendu) ; lot arrivé : servi sans requête', () async {
      final c = FicheInfoCache();
      final lot = Completer<List<ArticleAnalysis>>();
      var lots = 0;
      c.chargerSaisie(src, 'doli', (_) {
        lots++;
        return lot.future;
      });
      var cip = 0;
      final a = await c.charger(cle(doli), (_) async {
        cip++;
        return _a(infoAnalyseSearch('3595583').last);
      }, produit: doli);
      expect(a!.emplacement, 'RAYON F-DOLI');
      expect((lots, cip, c.servisParLot), (1, 1, 0), reason: 'réponse du CIP sans attendre le lot (jamais arrivé ici)');
      lot.complete([for (final j in infoAnalyseSearch('doli')) _a(j)]);
      await Future<void>.delayed(Duration.zero);
      // Un autre produit couvert, après l'arrivée du lot : immédiat, sans requête.
      expect(c.connuPour(cle(doliD), doliD)!.article!.emplacement, 'RAYON DETAIL');
      expect(c.requetes, 1);
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

    test('5.1.0 : un détail n\'attend plus le lot : nouvelle saisie → lot abandonné ; 2 caractères : aucun lot', () async {
      final c = FicheInfoCache();
      final lot = Completer<List<ArticleAnalysis>>();
      CancelToken? jeton;
      c.chargerSaisie(src, 'doli', (j) {
        jeton = j;
        return lot.future;
      });
      final f = c.charger(cle(doli), (_) async => _a(infoAnalyseSearch('3595583').last), produit: doli);
      c.lacherSaisie(src);
      expect(jeton!.isCancelled, isTrue, reason: 'aucun détail ne dépend du lot');
      expect((await f)!.codeCip, '3595583');
      c.chargerSaisie(src, 'do', (_) async => throw StateError('jamais'));
      expect(c.lots, 1);
    });

    test('lot en échec (délai) : sans effet sur le détail (CIP exact demandé au clic)', () async {
      final c = FicheInfoCache();
      c.chargerSaisie(src, 'doli', (_) async => throw Exception('Délai dépassé : pas de réponse du serveur en 30 s (GET /info).'));
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

    test('5.1.0 : écran fermé : la requête est annulée (rien en cache), réouverture → nouvelle requête ; délai dépassé : oubliée, Réessayer en relance une', () async {
      final c = FicheInfoCache();
      final rep = Completer<ArticleAnalysis?>();
      CancelToken? jeton;
      final f = c.charger(cle(ibex), (j) {
        jeton = j;
        return rep.future;
      });
      c.lacher(cle(ibex));
      expect(jeton!.isCancelled, isTrue);
      expect(c.enCours(cle(ibex)), isFalse);
      expect(c.abandons, 1);
      rep.complete(_a(infoAnalyseSearch('8049052').single));
      await f;
      expect(c.connu(cle(ibex)), isNull, reason: 'réponse d\'une requête annulée jamais gardée');
      expect(await c.charger(cle(ibex), (_) async => _a(infoAnalyseSearch('8049052').single)), isNotNull);
      expect(c.requetes, 2);

      // Deux écrans sur la même requête : annulée seulement quand le dernier se ferme.
      final lente = Completer<ArticleAnalysis?>();
      CancelToken? j3;
      c.charger(cle(doliD), (j) {
        j3 = j;
        return lente.future;
      }).ignore();
      c.charger(cle(doliD), (_) async => null).ignore();
      c.lacher(cle(doliD));
      expect(j3!.isCancelled, isFalse);
      c.lacher(cle(doliD));
      expect(j3!.isCancelled, isTrue);

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
