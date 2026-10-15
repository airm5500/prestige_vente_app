// 4.1.2 — Retours du pharmacien : « doli » / « ibex » dans Analyse article et la fiche produit tournaient puis
// « Délai dépassé : pas de réponse du serveur en 10 s (GET /info) » ; État de Stock tournait aussi longtemps.
// Causes : la LISTE d'Analyse article venait de GET /info?search=<saisie> (serveur : ventes de 6 mois + dernière
// vente / achat / inventaire de TOUS les produits qui commencent par la saisie) à chaque frappe ; le client partagé
// abandonnait au bout de 10 s (délai de réception de DioClient) alors que l'appli annonçait 30 s.
// Vérifié ici contre l'application ENTIÈRE et un faux serveur LENT (GET /info 12 s, comparaison de stock 15 s) :
// - Analyse article : liste rapide (GET /vente/search) affichée vite, AUCUN GET /info pendant la frappe ; le détail
//   du produit choisi (GET /info par son CIP exact) arrive ensuite avec un indicateur ; au-delà de 30 s : message
//   « … en 30 s » + Réessayer, la liste reste ;
// - fiche produit : affichée tout de suite (nom, stock, prix), le bloc GET /info ensuite, sans bloquer l'écran ;
// - État de Stock : la requête de la frappe précédente est annulée ; un serveur de 15 s n'échoue plus à 10 s,
//   mêmes chiffres (même route GET /fichearticle/comparaison).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/accueil/fiche_produit_screen.dart';
import 'package:prestige_vente_app/accueil/recherche_globale_screen.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/providers/stock_report_provider.dart';
import 'package:prestige_vente_app/screens/analysis/article_analysis_screen.dart';
import 'package:prestige_vente_app/screens/stock_report/stock_report_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';

import 'outils/app_e2e.dart';

const _doli = 'DOLIPRANE 1000MG CP B/8';
const _doliD = 'DOLIPRANE 1000MG CP B/8 DETAIL';
const _ibex = 'IBEX 200/325/30MG GEL B/24';

Map<String, dynamic> _produit(String id, String nom, String cip, int prix, int stock) =>
    {'lgFAMILLEID': id, 'strNAME': nom, 'intCIP': cip, 'intPRICE': prix, 'intNUMBERAVAILABLE': stock, 'strLIBELLEE': 'ANTALGIQUES', 'intPAF': 0};

Map<String, dynamic> _info(String id, String nom, String cip, String emplacement) => {
      'produitId': id,
      'codeCip': cip,
      'libelle': nom,
      'emplacement': emplacement,
      'grossiste': 'LABOREX-CI YOP',
      'moyenne': 11.33,
      'prixAchat': 976,
      'prixVente': 1475,
      'quantiteVendue': 34,
      'stock': 18,
      'quantiteMois': '10:10,12:9',
    };

final _catalogue = [
  _produit('F1', _doli, '3595583', 1475, 18),
  _produit('F2', _doliD, '3595583D', 200, 4),
  _produit('F3', _ibex, '8049052', 1435, 37),
];

/// GET /info?search= « commence par » (CIP ou nom), triée par nom, comme le serveur.
List<Map<String, dynamic>> _infoSearch(String q) => [
      if ('3595583'.startsWith(q) || q.startsWith('3595583') || _doli.startsWith(q.toUpperCase())) ...[
        _info('F2', _doliD, '3595583D', 'RAYON DETAIL'),
        _info('F1', _doli, '3595583', 'RAYON F-DOLI'),
      ],
      if ('8049052'.startsWith(q) || _ibex.startsWith(q.toUpperCase())) _info('F3', _ibex, '8049052', 'RAYON IBEX'),
    ];

AppE2E _app({Duration info = const Duration(seconds: 12)}) {
  final app = AppE2E()..serveur.activerModules();
  app.serveur.routes['GET /vente/search'] = (r) {
    final q = (r.query['query'] ?? '').toUpperCase().replaceAll('%', '');
    final l = [for (final p in _catalogue) if ((p['strNAME'] as String).startsWith(q) || (p['intCIP'] as String).startsWith(q)) p];
    return FauxServeurPrestige.ok({'data': l, 'total': l.length});
  };
  app.serveur.routes['GET /info'] = (r) => FauxServeurPrestige.lent(_infoSearch(r.query['search'] ?? ''), info);
  return app;
}

Future<AppE2E> _lancer(WidgetTester t, {Duration info = const Duration(seconds: 12), ListPresentation style = ListPresentation.dashboard}) async {
  TailleEcran.sunmiV2s.appliquer(t);
  final app = _app(info: info);
  await app.preparer(prefs: {'hiddenMenuIds': <String>[], 'presentation_listes_v1': style.name});
  await app.lancer(t);
  expect(await app.seConnecter(t, login: DonneesFictives.admin, motDePasse: DonneesFictives.motDePasseAdmin), isTrue);
  await app.attendre(t);
  return app;
}

/// Frappe lettre par lettre (100 ms entre deux lettres, comme au clavier).
Future<void> _frappe(WidgetTester t, String texte, {Finder? champ}) async {
  for (var i = 1; i <= texte.length; i++) {
    await t.enterText(champ ?? find.byType(TextField).first, texte.substring(0, i));
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('Analyse article : liste rapide, puis détail du produit choisi', () {
    for (final style in ListPresentation.values) {
      testWidgets('${style.label} : GET /info lent (12 s) → liste en moins d\'1 s, aucun GET /info pendant la frappe, détail ensuite',
          (t) async {
        final app = await _lancer(t, style: style);
        await app.ouvrirMenu(t, style, 'analyse_article');
        expect(find.byType(ArticleAnalysisScreen), findsOneWidget);
        final infoAvant = app.serveur.recuesSur('/info').length;

        await _frappe(t, 'doli');
        await app.attendre(t, const Duration(milliseconds: 900));
        expect(find.text(_doli), findsOneWidget, reason: 'liste rapide affichée sans attendre GET /info');
        expect(find.text(_doliD), findsOneWidget);
        expect(app.serveur.recuesSur('/info').length, infoAvant, reason: 'aucun GET /info pendant la frappe');
        final recherches = app.serveur.recuesSur('/vente/search');
        expect(recherches.last.query['query'], 'doli');
        expect(recherches.where((r) => r.query['query'] == 'd'), isEmpty, reason: '1 lettre : rien n\'est envoyé');

        // Choix du produit : GET /info par SON CIP exact, indicateur pendant l'attente, l'écran reste utilisable.
        await t.tap(find.text(_doli).hitTestable().first);
        await app.attendre(t, const Duration(milliseconds: 500));
        expect(find.text("Détails de l'Article"), findsOneWidget);
        expect(find.byKey(const ValueKey('analyse-detail-chargement')), findsOneWidget, reason: 'indicateur, stock et prix déjà là');
        expect(find.textContaining('Chargement de l\'analyse'), findsOneWidget);
        final infos = app.serveur.recuesSur('/info').skip(infoAvant).toList();
        expect([for (final r in infos) r.query['search']], ['3595583'], reason: 'une seule requête, CIP exact');

        await app.attendre(t, const Duration(seconds: 12));
        expect(find.byKey(const ValueKey('analyse-detail')), findsOneWidget);
        expect(find.text('RAYON F-DOLI'), findsOneWidget, reason: 'ligne du produit choisi (pas le 3595583D renvoyé avant)');
        expect(find.text('LABOREX-CI YOP'), findsOneWidget);
        expect(find.textContaining('Délai dépassé'), findsNothing);
        expect(t.takeException(), isNull);
        await app.fermer(t);
      });
    }

    testWidgets('GET /info au-delà de 30 s : « Délai dépassé … en 30 s » + Réessayer, la liste reste', (t) async {
      final app = await _lancer(t, info: const Duration(seconds: 45));
      await app.ouvrirMenu(t, ListPresentation.dashboard, 'analyse_article');
      await _frappe(t, 'ibex');
      await app.attendre(t, const Duration(seconds: 1));
      await t.tap(find.text(_ibex).hitTestable());
      await app.attendre(t, const Duration(seconds: 12));
      expect(find.byKey(const ValueKey('analyse-detail-chargement')), findsOneWidget, reason: 'à 12 s : on attend encore (plus d\'abandon à 10 s)');
      expect(find.textContaining('Délai dépassé'), findsNothing);
      await app.attendre(t, const Duration(seconds: 25));
      expect(find.byKey(const ValueKey('analyse-detail-erreur')), findsOneWidget);
      expect(find.textContaining('en ${ApiService.delaiInfo.inSeconds} s (GET /info)'), findsOneWidget);
      expect(find.textContaining('10 s'), findsNothing);
      expect(find.text('Réessayer'), findsOneWidget);
      // Fermer : la liste rapide est toujours là.
      await t.tap(find.text('Fermer'));
      await app.attendre(t, const Duration(seconds: 1));
      expect(find.text(_ibex), findsOneWidget);
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });
  });

  group('Fiche produit (recherche de l\'accueil)', () {
    testWidgets('GET /info lent (12 s) : fiche affichée tout de suite (nom, stock, prix), le bloc GET /info ensuite', (t) async {
      final app = await _lancer(t);
      await app.defilerJusqua(t, find.text('Rechercher un menu ou un produit'));
      await t.tap(find.text('Rechercher un menu ou un produit'));
      await app.attendre(t);
      expect(find.byType(RechercheGlobaleScreen), findsOneWidget);
      final infoAvant = app.serveur.recuesSur('/info').length;
      await _frappe(t, 'ibex');
      await app.attendre(t, const Duration(seconds: 1));
      expect(find.text(_ibex), findsWidgets, reason: 'recherche rapide de l\'accueil');
      expect(app.serveur.recuesSur('/info').length, infoAvant, reason: 'aucun GET /info pendant la frappe');
      await t.tap(find.text(_ibex).hitTestable().first);
      await app.attendre(t, const Duration(milliseconds: 600));
      expect(find.byType(FicheProduitScreen), findsOneWidget);
      expect(find.text(_ibex), findsWidgets);
      expect(find.text('37'), findsWidgets, reason: 'stock de la liste, sans attendre');
      expect(find.byKey(const ValueKey('fiche-squelette-Emplacement')), findsOneWidget, reason: 'bloc /info en attente');
      expect([for (final r in app.serveur.recuesSur('/info').skip(infoAvant)) r.query['search']], ['8049052']);
      await app.attendre(t, const Duration(seconds: 12));
      expect(find.byKey(const ValueKey('fiche-squelette-Emplacement')), findsNothing);
      expect(find.byKey(const ValueKey('fiche-info-Grossiste')), findsOneWidget);
      expect(find.textContaining('Délai dépassé'), findsNothing);
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });
  });

  group('État de Stock', () {
    testWidgets('frappe : la requête précédente est annulée ; serveur lent (15 s) : résultats, plus d\'abandon à 10 s', (t) async {
      final app = await _lancer(t);
      app.serveur.routes['GET /fichearticle/comparaison'] = (r) => FauxServeurPrestige.lent({
            'total': 1,
            'data': [
              {'id': 'F1', 'code': '3595583', 'libelle': _doli, 'stock': 18, 'prixVente': 1475, 'prixAchat': 976, 'rayonLibelle': 'RAYON F-DOLI'},
            ],
          }, const Duration(seconds: 15));
      await app.ouvrirMenu(t, ListPresentation.dashboard, 'stock');
      expect(find.byType(StockReportScreen), findsOneWidget);
      final provider = Provider.of<StockReportProvider>(t.element(find.byType(StockReportScreen)), listen: false);
      final champ = find.byKey(const Key('stock_search'));
      await t.enterText(champ, 'dol');
      await app.attendre(t, const Duration(milliseconds: 700));
      expect(app.serveur.recuesSur('/fichearticle/comparaison').last.query['query'], 'dol');
      await t.enterText(champ, 'doli');
      await app.attendre(t, const Duration(milliseconds: 700));
      expect(app.serveur.recuesSur('/fichearticle/comparaison').last.query['query'], 'doli');
      expect(provider.annulees, 1, reason: 'la recherche « dol » est abandonnée, pas attendue');
      await app.attendre(t, const Duration(seconds: 12));
      expect(provider.loadError, isNull, reason: 'à 12 s : on attend encore (plus d\'abandon à 10 s)');
      await app.attendre(t, const Duration(seconds: 4));
      expect(provider.loadError, isNull);
      expect(provider.reportItems.single.libelle, _doli);
      expect(provider.reportItems.single.stock, 18, reason: 'mêmes chiffres (même route)');
      expect(find.text(_doli), findsWidgets);
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });
  });
}
