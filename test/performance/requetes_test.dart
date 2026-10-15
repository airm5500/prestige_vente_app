// PERFORMANCE — NOMBRE DE REQUÊTES envoyées au faux serveur Prestige pour les parcours clés (application
// entière, nouvelle interface). Chaque parcours a un PLAFOND explicite : une requête de trop (boucle, double
// chargement, recherche sans anti-rebond, encaissement envoyé deux fois, vente hors ligne renvoyée…) fait
// échouer le test. Plafonds = fonctionnement voulu, sans marge (voir test/README.md).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/accueil/fiche_produit_screen.dart';
import 'package:prestige_vente_app/accueil/recherche_globale_screen.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart' show CatalogueCategorie;
import 'package:prestige_vente_app/screens/analysis/article_analysis_screen.dart';
import 'package:prestige_vente_app/screens/product_search/product_search_screen.dart';
import 'package:prestige_vente_app/screens/stock_report/stock_report_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import '../outils/app_e2e.dart';
import '../outils/parcours_vente.dart';
import '../outils/performance.dart';

/// Frappe rapide, lettre par lettre (100 ms entre deux lettres, comme au clavier).
Future<void> frappeRapide(WidgetTester t, Finder champ, String texte) async {
  for (var i = 1; i <= texte.length; i++) {
    await t.enterText(champ, texte.substring(0, i));
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Lignes de GET /info pour le produit fictif n° [i].
List<Map<String, dynamic>> infoFictive(int i) => [
      {
        'codeCip': produitFictif(i)['intCIP'],
        'libelle': produitFictif(i)['strNAME'],
        'produitId': 'F$i',
        'stock': 50,
        'prixVente': 1000 + i,
        'prixAchat': 500,
        'emplacement': 'RAYON FICTIF $i',
        'grossiste': 'GROSSISTE DEMO',
        'moyenne': 3,
      },
    ];

Future<(AppE2E, CatalogueFictif)> lancerConnecte(WidgetTester t) async {
  TailleEcran.sunmiV2s.appliquer(t);
  final app = AppE2E()..serveur.activerModules();
  final c = CatalogueFictif(app.serveur, nombre: 60);
  app.serveur.routes['GET /info'] = (r) {
    final q = r.query['search'] ?? '';
    final i = c.produits.indexWhere((p) => p['intCIP'] == q);
    return FauxServeurPrestige.ok(i < 0 ? const [] : infoFictive(i + 1));
  };
  app.serveur.routes['GET /fichearticle/comparaison'] = (r) => FauxServeurPrestige.ok({
        'total': 1,
        'data': [
          {'id': 'F7', 'code': produitFictif(7)['intCIP'], 'libelle': produitFictif(7)['strNAME'], 'stock': 50, 'prixVente': 1007, 'prixAchat': 500, 'rayonLibelle': 'RAYON'},
        ],
      });
  await app.preparer(prefs: prefsVente);
  await app.lancer(t);
  expect(await app.seConnecter(t, login: DonneesFictives.admin, motDePasse: DonneesFictives.motDePasseAdmin), isTrue);
  await app.attendre(t, const Duration(seconds: 3));
  return (app, c);
}

/// Requêtes de [rs] dont le chemin finit par [suffixe].
List<RequeteRecue> sur(List<RequeteRecue> rs, String suffixe) => [for (final r in rs) if (r.chemin.endsWith(suffixe)) r];

void main() {
  testWidgets('recherche tapée vite (12 lettres) : UNE requête après l\'anti-rebond — Vente, accueil, Recherche Article', (t) async {
    final (app, _) = await lancerConnecte(t);
    // Vente : anti-rebond 500 ms.
    await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
    var rs = await compterRequetes(app.serveur, () async {
      await frappeRapide(t, champRechercheVente, nomCourt(7));
      await app.attendre(t, const Duration(seconds: 1));
    });
    mesurer('Requêtes — Vente : recherche tapée vite', sur(rs, '/vente/search').length, seuil: 1, unite: 'requêtes', detail: detailRequetes(rs));
    expect(sur(rs, '/vente/search').single.query['query'], contains(nomCourt(7)), reason: 'le texte complet est cherché');
    expect(champQuantite, findsOneWidget, reason: 'produit trouvé');
    await t.tap(find.text('Annuler'));
    await app.attendre(t);
    await app.retour(t);

    // Recherche de l'accueil : anti-rebond 350 ms.
    await app.defilerJusqua(t, find.text('Rechercher un menu ou un produit'));
    await t.tap(find.text('Rechercher un menu ou un produit'));
    await app.attendre(t);
    expect(find.byType(RechercheGlobaleScreen), findsOneWidget);
    rs = await compterRequetes(app.serveur, () async {
      await frappeRapide(t, find.byType(TextField).first, nomCourt(7));
      await app.attendre(t, const Duration(seconds: 1));
    });
    mesurer('Requêtes — recherche de l\'accueil tapée vite', sur(rs, '/vente/search').length, seuil: 1, unite: 'requêtes', detail: detailRequetes(rs));
    await app.retour(t);

    // Recherche Article : anti-rebond 350 ms.
    await app.ouvrirMenu(t, ListPresentation.dashboard, 'search');
    expect(find.byType(ProductSearchScreen), findsOneWidget);
    rs = await compterRequetes(app.serveur, () async {
      await frappeRapide(t, find.byType(TextField).first, nomCourt(7));
      await app.attendre(t, const Duration(seconds: 1));
    });
    mesurer('Requêtes — Recherche Article tapée vite', sur(rs, '/vente/search').length, seuil: 1, unite: 'requêtes', detail: detailRequetes(rs));
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  testWidgets('Analyse article : ouverture, frappe (aucun GET /info), choix du produit (un GET /info)', (t) async {
    final (app, c) = await lancerConnecte(t);
    var rs = await compterRequetes(app.serveur, () => app.ouvrirMenu(t, ListPresentation.dashboard, 'analyse_article'));
    expect(find.byType(ArticleAnalysisScreen), findsOneWidget);
    mesurer('Requêtes — ouverture d\'Analyse article', rs.length, seuil: 0, unite: 'requêtes', detail: detailRequetes(rs));
    rs = await compterRequetes(app.serveur, () async {
      await frappeRapide(t, find.byType(TextField).first, nomCourt(7));
      await app.attendre(t, const Duration(seconds: 1));
    });
    mesurer('Requêtes — Analyse article : frappe', rs.length, seuil: 1, unite: 'requêtes', detail: detailRequetes(rs));
    expect(sur(rs, '/info'), isEmpty, reason: 'aucun GET /info pendant la frappe');
    rs = await compterRequetes(app.serveur, () async {
      await t.tap(find.text(produitFictif(7)['strNAME'] as String).hitTestable().first);
      await app.attendre(t, const Duration(seconds: 2));
    });
    expect(find.text('RAYON FICTIF 7'), findsOneWidget);
    mesurer('Requêtes — Analyse article : détail du produit choisi', rs.length, seuil: 1, unite: 'requêtes', detail: detailRequetes(rs));
    expect(sur(rs, '/info').single.query['search'], c.produits[6]['intCIP'], reason: 'CIP exact');
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  testWidgets('fiche produit (recherche de l\'accueil) : un GET /info, réouverture sans requête', (t) async {
    final (app, _) = await lancerConnecte(t);
    await app.defilerJusqua(t, find.text('Rechercher un menu ou un produit'));
    await t.tap(find.text('Rechercher un menu ou un produit'));
    await app.attendre(t);
    await frappeRapide(t, find.byType(TextField).first, nomCourt(7));
    await app.attendre(t, const Duration(seconds: 1));
    final nom = produitFictif(7)['strNAME'] as String;
    var rs = await compterRequetes(app.serveur, () async {
      await t.tap(find.text(nom).hitTestable().first);
      await app.attendre(t, const Duration(seconds: 2));
    });
    expect(find.byType(FicheProduitScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('fiche-info-Grossiste')), findsOneWidget);
    // Analyse du produit (GET /info, 1) + liste de ses images (photo de la fiche, 1).
    mesurer('Requêtes — ouverture de la fiche produit', rs.length, seuil: 2, unite: 'requêtes', detail: detailRequetes(rs));
    expect(sur(rs, '/info'), hasLength(1));
    await app.retour(t);
    rs = await compterRequetes(app.serveur, () async {
      await t.tap(find.text(nom).hitTestable().first);
      await app.attendre(t, const Duration(seconds: 2));
    });
    mesurer('Requêtes — réouverture de la fiche produit (moins de 60 s)', sur(rs, '/info').length, seuil: 0, unite: 'requêtes', detail: detailRequetes(rs));
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  testWidgets('État de Stock : ouverture puis recherche tapée vite', (t) async {
    final (app, _) = await lancerConnecte(t);
    var rs = await compterRequetes(app.serveur, () => app.ouvrirMenu(t, ListPresentation.dashboard, 'stock'));
    expect(find.byType(StockReportScreen), findsOneWidget);
    // Listes des filtres : rayons (1) et grossistes (1).
    mesurer('Requêtes — ouverture d\'État de Stock', rs.length, seuil: 2, unite: 'requêtes', detail: detailRequetes(rs));
    rs = await compterRequetes(app.serveur, () async {
      await frappeRapide(t, find.byKey(const Key('stock_search')), 'PRODUIT 0007');
      await app.attendre(t, const Duration(seconds: 2));
    });
    mesurer('Requêtes — État de Stock : recherche tapée vite', sur(rs, '/fichearticle/comparaison').length, seuil: 1, unite: 'requêtes', detail: detailRequetes(rs));
    expect(find.text(produitFictif(7)['strNAME'] as String), findsWidgets);
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  testWidgets('encaissement d\'une vente comptant (espèces) : une seule clôture', (t) async {
    final (app, c) = await lancerConnecte(t);
    await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
    var rs = await compterRequetes(app.serveur, () async {
      expect(await ajouterAuPanier(t, app, nomCourt(3), qte: '2'), isTrue);
      await app.attendre(t, const Duration(seconds: 2));
    });
    mesurer('Requêtes — ajout d\'une ligne au panier', rs.length, seuil: 4, unite: 'requêtes', detail: detailRequetes(rs));
    rs = await compterRequetes(app.serveur, () async {
      await validerEncaissementEspeces(t, app);
      await app.attendre(t, const Duration(seconds: 3));
    });
    expect(find.text('Le panier est vide'), findsOneWidget, reason: 'vente encaissée, panier vidé');
    // Modes de règlement (1) + QR des modes (1), client de la vente (1), clôture (1), liste des préventes (1).
    mesurer('Requêtes — encaissement d\'une vente', rs.length, seuil: 5, unite: 'requêtes', detail: detailRequetes(rs));
    expect(c.clotures, 1, reason: 'une seule clôture');
    expect(app.serveur.statutVentes['V-1'], 'is_Closed');
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  testWidgets('synchro hors ligne : 3 préventes provisoires envoyées au retour du serveur, chacune une fois', (t) async {
    final (app, _) = await lancerConnecte(t);
    await app.horsLigne.store.replace(CatalogueCategorie.produits, [for (var i = 1; i <= 5; i++) produitFictif(i)], DateTime.now());
    await app.horsLigne.sync.refreshStats();
    await app.serveur.couper();
    expect(await app.attendreQue(t, find.text('Continuer hors ligne'), max: const Duration(minutes: 3)), isTrue);
    await t.tap(find.text('Continuer hors ligne'));
    await app.attendre(t);
    expect(app.horsLigne.offline, isTrue);
    await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
    for (var i = 1; i <= 3; i++) {
      expect(await ajouterAuPanier(t, app, nomCourt(i), qte: '$i'), isTrue, reason: 'produit $i trouvé dans la copie locale');
      await app.attendre(t);
      await t.tap(find.byKey(const ValueKey('vente-hl-prevente')));
      await app.attendre(t);
      expect(find.text('Prévente provisoire enregistrée'), findsOneWidget);
      await t.tap(find.text('Non'));
      await app.attendre(t);
    }
    expect(app.horsLigne.ventes.enAttente, 3);
    await app.retour(t);
    await app.serveur.retablir();
    final rs = await compterRequetes(app.serveur, () async {
      app.horsLigne.monitor.goOnline();
      expect(await app.attendreQue(t, find.byKey(const Key('confirmation_envoi')), max: const Duration(minutes: 2)), isTrue);
      await t.tap(find.byKey(const Key('envoyer_selection')));
      await app.attendre(t, const Duration(seconds: 8));
    });
    expect(app.horsLigne.ventes.enAttente, 0);
    expect(app.serveur.ventes, hasLength(3), reason: 'trois préventes créées, aucune en double');
    final envoi = [for (final r in rs) if (r.chemin.contains('/vente/')) r];
    // Par prévente d'une ligne : produit relu (prix, stock : 1), création (1), lignes (1), net (1), enregistrement de
    // la prévente (1). Hors vente : capacités du serveur (clé client H4) et officine (ticket), non comptées.
    mesurer('Requêtes — envoi de 3 préventes hors ligne', envoi.length, seuil: 3 * 5, unite: 'requêtes', detail: detailRequetes(rs));
    expect(sur(envoi, '/vente/add/vno'), hasLength(3), reason: 'chaque prévente créée une seule fois');
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });
}
