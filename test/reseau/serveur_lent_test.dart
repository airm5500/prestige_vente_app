// RÉSEAU — serveur LENT MAIS QUI RÉPOND (2 s, 5 s, 8 s ; 25 s pour GET /info), application entière (vrai Dio,
// délais réels de l'application), faux serveur Prestige en mémoire, temps simulé. Sur la vente, l'encaissement,
// la recherche de l'accueil et l'Analyse article :
//  - un indicateur de chargement est visible pendant toute l'attente ;
//  - aucun message d'erreur (« injoignable », « trop de temps », « Délai dépassé »…) n'apparaît AVANT le délai de
//    l'application (10 s pour la vente et la recherche — DioClient —, 30 s pour GET /info — ApiService.delaiInfo) ;
//  - l'écran reste utilisable (retour possible) et une seconde action pendant l'attente n'envoie RIEN en double
//    (encaissement : une seule clôture ; vente : une seule création) ;
//  - la réponse, une fois arrivée, est affichée / prise en compte.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/accueil/accueil_screen.dart';
import 'package:prestige_vente_app/accueil/recherche_globale_screen.dart';
import 'package:prestige_vente_app/screens/analysis/article_analysis_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import '../outils/app_e2e.dart';
import '../outils/parcours_vente.dart';

const delais = [Duration(seconds: 2), Duration(seconds: 5), Duration(seconds: 8)];

final indicateur = find.byWidgetPredicate((w) => w is ProgressIndicator);

/// Textes d'erreur qui ne doivent pas apparaître tant que le serveur répond dans les délais.
Finder erreurs() => find.byWidgetPredicate((w) {
      if (w is! Text) return false;
      final t = (w.data ?? w.textSpan?.toPlainText() ?? '').toLowerCase();
      return t.contains('injoignable') ||
          t.contains('trop de temps') ||
          t.contains('délai dépassé') ||
          t.contains('ne répond pas') ||
          t.contains('erreur') ||
          t.contains('impossible') ||
          t.contains('réessayer');
    });

/// Attend la réponse du serveur lent ([delai]) par pas de 250 ms : [attendu] (indicateur) visible et aucun
/// message d'erreur à chaque pas ; [pendant] est appelé une fois, à mi-attente (seconde action de l'utilisateur).
Future<void> attendreServeurLent(WidgetTester t, Duration delai, String ecran, {Finder? attendu, Future<void> Function()? pendant}) async {
  final fin = delai - const Duration(milliseconds: 250);
  final debut = t.binding.clock.now();
  var ecoule = Duration.zero;
  var milieu = false;
  while (ecoule + const Duration(milliseconds: 250) <= fin) {
    await t.pump(const Duration(milliseconds: 250));
    ecoule = t.binding.clock.now().difference(debut); // temps simulé, action « pendant » comprise
    expect(attendu ?? indicateur, findsWidgets, reason: '$ecran : indicateur de chargement visible à ${ecoule.inMilliseconds} ms');
    expect(erreurs(), findsNothing, reason: '$ecran : aucun message d\'erreur à ${ecoule.inMilliseconds} ms (serveur lent, pas en panne)');
    if (!milieu && ecoule >= delai ~/ 2 && pendant != null) {
      milieu = true;
      await pendant();
    }
  }
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  expect(erreurs(), findsNothing, reason: '$ecran : réponse arrivée, aucun message d\'erreur');
}

/// Route [cle] du faux serveur ralentie de [d] (réponse normale du faux serveur, sinon [corps]).
void ralentir(FauxServeurPrestige s, String cle, Duration d) {
  final scriptee = s.routes[cle];
  s.routes[cle] = (r) async {
    final rep = scriptee != null ? await scriptee(r) : await _parDefaut(s, cle, r);
    return ReponseLocale(rep.corps, statut: rep.statut, entetes: rep.entetes, delai: d);
  };
}

Future<ReponseLocale> _parDefaut(FauxServeurPrestige s, String cle, RequeteRecue r) async {
  final f = s.routes.remove(cle);
  try {
    return await s.repondre(r);
  } finally {
    s.routes[cle] = f!;
  }
}

Future<(AppE2E, CatalogueFictif)> lancerConnecte(WidgetTester t) async {
  TailleEcran.sunmiV2s.appliquer(t);
  final app = AppE2E();
  final c = CatalogueFictif(app.serveur, nombre: 20);
  app.serveur.routes['GET /info'] = (r) => FauxServeurPrestige.ok([
        {
          'codeCip': r.query['search'],
          'libelle': 'PRODUIT 0007 CPR B/20',
          'produitId': 'F7',
          'stock': 50,
          'prixVente': 1007,
          'prixAchat': 500,
          'emplacement': 'RAYON FICTIF 7',
          'grossiste': 'GROSSISTE DEMO',
          'moyenne': 3,
        }
      ]);
  await app.preparer(prefs: prefsVente);
  await app.lancer(t);
  expect(await app.seConnecter(t), isTrue);
  await app.attendre(t, const Duration(seconds: 3));
  return (app, c);
}

void main() {
  for (final d in delais) {
    final s = '${d.inSeconds} s';
    group('serveur lent ($s)', () {
      testWidgets('vente : recherche puis création de la vente lentes — indicateur, aucune erreur, aucune vente en double', (t) async {
        final (app, c) = await lancerConnecte(t);
        await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
        c.delaiRecherche = d;
        await t.enterText(champRechercheVente, nomCourt(3));
        await t.pump(const Duration(milliseconds: 600)); // anti-rebond
        await attendreServeurLent(t, d, 'Vente — recherche');
        expect(champQuantite, findsOneWidget, reason: 'produit trouvé après $s');
        c.delaiRecherche = Duration.zero;

        ralentir(app.serveur, 'POST /vente/add/vno', d);
        await t.enterText(champQuantite, '2');
        await t.tap(find.text('Ajouter'));
        await t.pump();
        await attendreServeurLent(t, d, 'Vente — création de la vente (1er article)', attendu: find.byKey(const ValueKey('vente-etat-envoi')), pendant: () async {
          // Second produit tapé pendant l'attente : la vente n'est pas créée deux fois.
          await t.enterText(champRechercheVente, nomCourt(4));
          await t.pump(const Duration(milliseconds: 600));
          if (champQuantite.evaluate().isNotEmpty) {
            await t.enterText(champQuantite, '1');
            await t.tap(find.text('Ajouter'));
            await t.pump();
          }
        });
        await app.attendre(t, const Duration(seconds: 3));
        expect(app.serveur.ventes, hasLength(1), reason: 'une seule vente créée');
        expect(app.serveur.recuesSur('/vente/add/vno'), hasLength(1));
        expect(find.textContaining('enregistré'), findsWidgets, reason: 'panier enregistré sur le serveur');
        expect(t.takeException(), isNull);
        await app.fermer(t);
      });

      testWidgets('encaissement lent : « VALIDATION… », second toucher sans double clôture, puis vente encaissée', (t) async {
        final (app, c) = await lancerConnecte(t);
        await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
        expect(await ajouterAuPanier(t, app, nomCourt(5), qte: '1'), isTrue);
        await app.attendre(t, const Duration(seconds: 2));
        c.delaiCloture = d;
        await validerEncaissementEspeces(t, app);
        await attendreServeurLent(t, d, 'Encaissement', pendant: () async {
          final valider = find.byKey(const ValueKey('encaissement-valider'));
          if (valider.evaluate().isNotEmpty) await t.tap(valider, warnIfMissed: false);
          await t.pump(const Duration(milliseconds: 10));
          if (valider.evaluate().isNotEmpty) await t.tap(valider, warnIfMissed: false);
        });
        await app.attendre(t, const Duration(seconds: 2));
        expect(c.clotures, 1, reason: 'une seule clôture malgré les touchers pendant l\'attente');
        expect(find.text('Le panier est vide'), findsOneWidget, reason: 'vente encaissée, panier vidé');
        expect(app.serveur.statutVentes.values.single, 'is_Closed');
        expect(t.takeException(), isNull);
        await app.fermer(t);
      });

      testWidgets('recherche de l\'accueil lente : indicateur, aucune erreur, résultats ; retour possible pendant l\'attente', (t) async {
        final (app, c) = await lancerConnecte(t);
        await app.defilerJusqua(t, find.text('Rechercher un menu ou un produit'));
        await t.tap(find.text('Rechercher un menu ou un produit'));
        await app.attendre(t);
        c.delaiRecherche = d;
        await t.enterText(find.byType(TextField).first, 'PRODUIT 001');
        await t.pump(const Duration(milliseconds: 400)); // anti-rebond
        await attendreServeurLent(t, d, 'Recherche de l\'accueil');
        expect(find.text('PRODUIT 0010 CPR B/20'), findsOneWidget);
        expect(app.serveur.recuesSur('/vente/search').where((r) => r.query['query']!.contains('PRODUIT 001')), hasLength(1));

        // Écran utilisable : nouvelle recherche lente quittée par le bouton retour.
        await t.enterText(find.byType(TextField).first, 'PRODUIT 002');
        await t.pump(const Duration(milliseconds: 400));
        await t.pump(d ~/ 2);
        await app.retour(t);
        expect(find.byType(RechercheGlobaleScreen), findsNothing);
        expect(find.byType(AccueilScreen), findsOneWidget);
        await t.pump(d);
        await app.attendre(t);
        expect(erreurs(), findsNothing);
        expect(t.takeException(), isNull);
        await app.fermer(t);
      });
    });
  }

  for (final d in [...delais, const Duration(seconds: 25)]) {
    testWidgets('Analyse article : GET /info lent (${d.inSeconds} s, délai 30 s) — indicateur sans erreur, puis détail ; retour possible', (t) async {
      final (app, _) = await lancerConnecte(t);
      ralentir(app.serveur, 'GET /info', d);
      await app.ouvrirMenu(t, ListPresentation.dashboard, 'analyse_article');
      expect(find.byType(ArticleAnalysisScreen), findsOneWidget);
      await t.enterText(find.byType(TextField).first, nomCourt(7));
      await app.attendre(t, const Duration(seconds: 1));
      await t.tap(find.text('PRODUIT 0007 CPR B/20').hitTestable().first);
      await t.pump();
      await attendreServeurLent(t, d, 'Analyse article', attendu: find.byKey(const ValueKey('analyse-detail-chargement')));
      expect(find.byKey(const ValueKey('analyse-detail')), findsOneWidget);
      expect(find.text('RAYON FICTIF 7'), findsOneWidget);
      expect(app.serveur.recuesSur('/info'), hasLength(1), reason: 'un seul GET /info');

      // Retour pendant une seconde attente : aucune erreur, aucune exception à l'arrivée de la réponse.
      await t.tap(find.text('Fermer'));
      await app.attendre(t, const Duration(seconds: 1));
      await t.tap(find.text('PRODUIT 0007 CPR B/20').hitTestable().first);
      await t.pump(d ~/ 2);
      await app.retour(t);
      await t.pump(d);
      await app.attendre(t);
      expect(erreurs(), findsNothing);
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });
  }
}
