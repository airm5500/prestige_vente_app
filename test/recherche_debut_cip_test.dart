// F3 (4.0.3) — Recherche par DÉBUT DE CIP : le bon produit en première ligne.
//
// Cause reproduite ici avec un faux serveur qui se comporte comme Prestige : GET /vente/search (listes de
// Recherche Article, Évaluation Vente, recherche de l'accueil) et GET /info?search= (Analyse article, détails
// après le choix d'un produit) cherchent « commence par » (« Contient » : '%…') à la fois sur le NOM, le CIP et
// l'EAN fabricant, et renvoient les lignes triées par NOM. Pour « 3595 », le serveur renvoie d'abord
// « 3595 BABY LAIT… » (nom), puis « ADVIL… » (EAN fabricant 3595…), et seulement ensuite les DOLIPRANE dont le CIP
// commence par 3595 ; l'application affichait cet ordre tel quel. Après le choix du produit, la 1re ligne de
// GET /info?search=3595583 était celle de « 3595583D » (autre produit, nom trié avant) : mauvais stock / prix.
//
// Couverture :
//   - unitaires : saisie numérique, CIP13 ↔ CIP7 (clé EAN-13), rangs, classement stable, choix de la ligne ;
//     PagedProductSearch (liste texte, suite chargée, candidats d'un code ≥ 7 chiffres ; autres menus inchangés) ;
//   - e2e (application entière, faux serveur Prestige en mémoire) : Recherche Article et Évaluation Vente en
//     « Début » et « Contient » (liste ET détails du produit choisi), Analyse article, recherche de l'accueil ;
//     un nom n'est jamais réordonné.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/accueil/recherche_globale_screen.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/article_analysis_model.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/product_stats.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/providers/article_analysis_provider.dart';
import 'package:prestige_vente_app/providers/product_search_provider.dart';
import 'package:prestige_vente_app/providers/product_stats_provider.dart';
import 'package:prestige_vente_app/screens/analysis/article_analysis_screen.dart';
import 'package:prestige_vente_app/screens/product_evaluation/product_evaluation_screen.dart';
import 'package:prestige_vente_app/screens/product_search/product_search_screen.dart';
import 'package:prestige_vente_app/services/classement_code.dart';
import 'package:prestige_vente_app/services/product_finder.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';

import 'outils/app_e2e.dart';

// ---------------------------------------------------------------------------
// Catalogue fictif (noms et codes inventés pour le test)
// ---------------------------------------------------------------------------
const _bebe = '3595 BABY LAIT CORPS 400ML'; // nom qui commence par les chiffres tapés
const _advil = 'ADVIL 400MG CP B/14'; // EAN fabricant 3595…
const _doliDecond = 'DOLIPRANE 1000MG CP B/100'; // CIP 3595583D (déconditionné) : trié AVANT le B/8
const _doli = 'DOLIPRANE 1000MG CP B/8'; // CIP 3595583 : le produit cherché
const _doli500 = 'DOLIPRANE 500MG GELULE B/16'; // CIP 3595590
const _efferalgan = 'EFFERALGAN 500MG CP B/16'; // CIP 3133595 : contient 3595 ailleurs
const _zyrtec = 'ZYRTEC 10MG CP B/15'; // CIP13 3400936100012 : rien à voir avec 3595

Map<String, dynamic> _p(String id, String nom, String cip, int stock, {String ean = ''}) => {
      'lgFAMILLEID': id,
      'strNAME': nom,
      'intCIP': cip,
      'intPRICE': 1000 + stock,
      'intNUMBERAVAILABLE': stock,
      'strLIBELLEE': 'FAMILLE TEST',
      'intPAF': 700,
      'codeEanFabriquant': ean,
    };

final _catalogue = [
  _p('F-BEBE', _bebe, '6011120', 4),
  _p('F-ADVIL', _advil, '2786420', 9, ean: '3595123400017'),
  _p('F-DOLI-D', _doliDecond, '3595583D', 99),
  _p('F-DOLI', _doli, '3595583', 3),
  _p('F-DOLI500', _doli500, '3595590', 12),
  _p('F-EFF', _efferalgan, '3133595', 14),
  _p('F-ZYR', _zyrtec, '3400936100012', 6),
];

Map<String, dynamic> _info(Map<String, dynamic> p) => {
      'produitId': p['lgFAMILLEID'],
      'codeCip': p['intCIP'],
      'libelle': p['strNAME'],
      'stock': p['intNUMBERAVAILABLE'],
      'prixVente': p['intPRICE'],
      'prixAchat': 700,
      'emplacement': 'RAYON ${p['lgFAMILLEID']}',
      'grossiste': 'GROSSISTE DEMO',
      'moyenne': 1,
      'quantiteVendue': 10,
      'quantiteMois': '',
    };

/// LIKE du serveur : « Début » = 'texte%', « Contient » = '%mot1%mot2' (insensible à la casse).
bool _like(String champ, String q) {
  final c = champ.toUpperCase();
  final t = q.toUpperCase();
  if (!t.startsWith('%')) return c.startsWith(t);
  var i = 0;
  for (final mot in t.split('%').where((m) => m.isNotEmpty)) {
    final j = c.indexOf(mot, i);
    if (j < 0) return false;
    i = j + mot.length;
  }
  return true;
}

/// GET /vente/search : nom, CIP ou EAN fabricant, triés par NOM.
List<Map<String, dynamic>> _venteSearch(String q) => _catalogue
    .where((p) => _like(p['strNAME'], q) || _like(p['intCIP'], q) || _like(p['codeEanFabriquant'], q))
    .toList()
  ..sort((a, b) => (a['strNAME'] as String).compareTo(b['strNAME'] as String));

/// GET /info?search= : CIP ou nom, « commence par », triés par libellé.
List<Map<String, dynamic>> _infoSearch(String q) => [
      for (final p in _catalogue)
        if (_like(p['strNAME'], q) || _like(p['intCIP'], q)) _info(p)
    ]..sort((a, b) => (a['libelle'] as String).compareTo(b['libelle'] as String));

/// GET /produit/stats/vente-annuelle?search= : même recherche « commence par », une ligne par produit.
List<Map<String, dynamic>> _ventesAnnuelles(String q) => [
      for (final i in _infoSearch(q))
        {'id': i['produitId'], 'libelle': i['libelle'], 'codeCip': i['codeCip'], 'janvier': i['stock'], 'fevrier': 1}
    ];

/// Faux serveur Prestige avec le catalogue ci-dessus.
AppE2E _app() {
  final app = AppE2E()..serveur.activerModules();
  app.serveur.routes['GET /vente/search'] = (r) {
    final l = _venteSearch(r.query['query'] ?? '');
    final start = int.tryParse(r.query['start'] ?? '') ?? 0;
    final limit = int.tryParse(r.query['limit'] ?? '') ?? 50;
    return FauxServeurPrestige.ok({'data': l.skip(start).take(limit).toList(), 'total': l.length});
  };
  app.serveur.routes['GET /info'] = (r) => FauxServeurPrestige.ok(_infoSearch(r.query['search'] ?? ''));
  app.serveur.routes['GET /produit/stats/vente-annuelle'] = (r) => FauxServeurPrestige.ok({'data': _ventesAnnuelles(r.query['search'] ?? '')});
  return app;
}

Future<AppE2E> _lancer(WidgetTester t, {bool contient = false}) async {
  TailleEcran.sunmiV2s.appliquer(t);
  final app = _app();
  await app.preparer(prefs: {
    'hiddenMenuIds': <String>[],
    'presentation_listes_v1': ListPresentation.compact.name,
    if (contient) 'recherche_mode_v1': 'contient',
  });
  await app.lancer(t);
  expect(await app.seConnecter(t, login: DonneesFictives.admin, motDePasse: DonneesFictives.motDePasseAdmin), isTrue);
  await app.attendre(t);
  return app;
}

Future<void> _taper(WidgetTester t, AppE2E app, String texte) async {
  await t.enterText(find.byType(TextField).first, texte);
  await app.attendre(t, const Duration(seconds: 2));
}

/// Noms affichés, de haut en bas.
List<String> _ordreAffiche(WidgetTester t, List<String> noms) {
  final vus = [for (final n in noms) if (find.text(n).hitTestable().evaluate().isNotEmpty) n];
  vus.sort((a, b) => t.getRect(find.text(a).hitTestable().first).top.compareTo(t.getRect(find.text(b).hitTestable().first).top));
  return vus;
}

const _tous = [_bebe, _advil, _doliDecond, _doli, _doli500, _efferalgan, _zyrtec];

ProductSearchResult _r(Map<String, dynamic> j) => ProductSearchResult.fromJson(j);

/// ApiService dont la recherche par pages renvoie [_venteSearch] (pages de [ProductLookup.pageSize]).
class _Api extends ApiService {
  _Api() : super(baseUrl: 'http://localhost');
  final envoyees = <String>[];
  @override
  Future<ProductPage> searchProductsPageOrFail(String query, int start, int limit) async {
    envoyees.add(query);
    final l = _venteSearch(query);
    return ProductPage([for (final j in l.skip(start).take(limit)) _r(j)], l.length);
  }
}

void main() {
  // -------------------------------------------------------------------------
  // Unitaires
  // -------------------------------------------------------------------------
  group('Classement par début de code (unitaires)', () {
    test('saisie numérique : chiffres seuls (espaces ignorés), sinon vide', () {
      expect(saisieNumerique('3595'), '3595');
      expect(saisieNumerique(' 3595 583 '), '3595583');
      expect(saisieNumerique('doli'), '');
      expect(saisieNumerique('3595a'), '');
      expect(saisieNumerique('%3595'), '');
      expect(saisieNumerique(''), '');
    });

    test('CIP13 d\'un CIP7 (34009 + CIP7 + clé EAN-13) et CIP7 d\'un CIP13', () {
      expect(cleEan13('340093595583'), '8');
      expect(codesProduit('3595583'), ['3595583', '3400935955838']);
      expect(codesProduit('3400935955838'), ['3400935955838', '3595583']);
      expect(codesProduit('3595583D'), ['3595583D'], reason: 'code non numérique : tel quel');
      expect(codesProduit('3595583', ['', ' 3595123400017 ']), ['3595583', '3400935955838', '3595123400017']);
      expect(codesProduit(''), isEmpty);
    });

    test('rangs : exact (tout code) < CIP commence par < autre code commence par < reste', () {
      expect(rangCode('3595583', '3595583'), 0);
      expect(rangCode('3400935955838', '3595583'), 0, reason: 'CIP13 complet d\'un CIP7');
      expect(rangCode('3595123400017', '2786420', ['3595123400017']), 0, reason: 'EAN fabricant complet');
      expect(rangCode('3595', '3595583'), 1);
      expect(rangCode('3595', '3595583D'), 1);
      expect(rangCode('34009359', '3595583'), 2, reason: 'début du CIP13 calculé');
      expect(rangCode('3595', '2786420', ['3595123400017']), 2, reason: 'début de l\'EAN fabricant');
      expect(rangCode('3595', '3133595'), 3, reason: 'contient ailleurs');
      expect(rangCode('', '3595583'), 3);
    });

    test('classerParCode : exact puis début de code en tête, reste dans l\'ordre du serveur (stable)', () {
      final serveur = [for (final j in _venteSearch('3595')) _r(j)];
      expect([for (final p in serveur) p.strNAME], [_bebe, _advil, _doliDecond, _doli, _doli500], reason: 'ordre du serveur : par nom');
      final classes = classerParCode(serveur, '3595', (p) => p.intCIP, autres: (p) => [p.codeEanFabriquant]);
      expect([for (final p in classes) p.strNAME], [_doliDecond, _doli, _doli500, _advil, _bebe]);

      // Correspondance exacte d'abord, même si le serveur la renvoie après un CIP plus long.
      final exact = classerParCode(serveur, '3595583', (p) => p.intCIP, autres: (p) => [p.codeEanFabriquant]);
      expect(exact.first.strNAME, _doli);
      expect(exact[1].strNAME, _doliDecond);

      // « Contient » (%3595) : EFFERALGAN (3133595) reste derrière, dans l'ordre du serveur.
      final contient = [for (final j in _venteSearch('%3595')) _r(j)];
      final c = classerParCode(contient, '3595', (p) => p.intCIP, autres: (p) => [p.codeEanFabriquant]);
      expect([for (final p in c) p.strNAME], [_doliDecond, _doli, _doli500, _advil, _bebe, _efferalgan]);

      // Début de CIP13 (préfixe 34009 + CIP7) : le CIP7 correspondant remonte, le reste suit l'ordre du serveur.
      final cip13 = classerParCode(serveur, '340093595583', (p) => p.intCIP);
      expect(cip13.first.strNAME, _doli);
    });

    test('un nom (ou une saisie qui n\'est pas que des chiffres) n\'est jamais réordonné', () {
      final serveur = [for (final j in _venteSearch('DOLI')) _r(j)];
      expect(identical(classerParCode(serveur, 'DOLI', (p) => p.intCIP), serveur), isTrue);
      expect(identical(classerParCode(serveur, '%3595', (p) => p.intCIP), serveur), isTrue);
      expect(classerParCode(<ProductSearchResult>[], '3595', (p) => p.intCIP), isEmpty);
    });

    test('ligneDuCode : même CIP, sinon la mieux classée ; jamais la 1re ligne d\'un autre produit', () {
      final lignes = _infoSearch('3595583');
      expect([for (final l in lignes) l['codeCip']], ['3595583D', '3595583'], reason: 'le serveur renvoie d\'abord l\'autre produit');
      expect(ligneDuCode(lignes, '3595583', (l) => '${l['codeCip']}')!['libelle'], _doli);
      expect(ApiService.ligneInfoDuCip(lignes, '3595583')!['libelle'], _doli);
      expect(ligneDuCode(<Map<String, dynamic>>[], '3595583', (l) => '${l['codeCip']}'), isNull);
      // Aucune ligne au même CIP : la mieux classée (comportement d'avant si une seule ligne).
      expect(ligneDuCode([_info(_catalogue[0])], '3595583', (l) => '${l['codeCip']}')!['libelle'], _bebe);
      final ventes = [for (final j in _ventesAnnuelles('3595583')) ProductAnnualSale.fromJson(j)];
      expect(ligneDuCode(ventes, '3595583', (s) => s.codeCip)!.libelle, _doli);
    });
  });

  group('PagedProductSearch', () {
    test('Recherche Article / Évaluation (classerCodes) : liste texte classée, suite chargée reclassée', () async {
      final api = _Api();
      final s = PagedProductSearch(() => api, classerCodes: true);
      await s.run('3595');
      expect([for (final p in s.items) p.strNAME], [_doliDecond, _doli, _doli500, _advil, _bebe]);
      expect(api.envoyees, ['3595'], reason: 'requête du serveur inchangée');
      await s.run('doli');
      expect([for (final p in s.items) p.strNAME], [_doliDecond, _doli, _doli500], reason: 'nom : ordre du serveur');
    });

    test('code de 7 chiffres ou plus sans produit exact : candidats classés', () async {
      final api = _Api();
      final s = PagedProductSearch(() => api, classerCodes: true);
      await s.run('3595583');
      expect([for (final p in s.items) p.strNAME], [_doli], reason: 'CIP exact : ce produit seul (inchangé)');
      // CIP13 complet du CIP7 3595583 (34009…) : le serveur ne le connaît pas, la recherche essaie le CIP7.
      await s.run('3400935955838');
      expect(s.items.first.strNAME, _doli);
    });

    test('autres menus (sans classerCodes) : ordre du serveur inchangé', () async {
      final s = PagedProductSearch(() => _Api());
      await s.run('3595');
      expect([for (final p in s.items) p.strNAME], [_bebe, _advil, _doliDecond, _doli, _doli500]);
    });

    test('suite chargée (« Charger la suite ») : toute la liste reste classée', () async {
      // Page 1 : 50 produits sans rapport (noms qui commencent par « 3595 »), le bon produit en page 2.
      final api = _ApiPages();
      final s = PagedProductSearch(() => api, classerCodes: true);
      await s.run('3595');
      expect(s.items.first.strNAME, startsWith('3595 '), reason: 'page 1 : aucun CIP ne commence par 3595');
      expect(s.hasMore, isTrue);
      await s.loadMore();
      expect(s.items.first.strNAME, _doli, reason: 'le CIP 3595583 passe en tête dès qu\'il est chargé');
      expect(s.items.length, 51);
    });
  });

  // -------------------------------------------------------------------------
  // E2E : application entière, faux serveur Prestige en mémoire
  // -------------------------------------------------------------------------
  group('Recherche Article (e2e)', () {
    for (final contient in [false, true]) {
      final mode = contient ? 'Contient' : 'Début';
      testWidgets('$mode : « 3595 » → DOLIPRANE (CIP 3595…) en tête ; détails du bon produit', (t) async {
        final app = await _lancer(t, contient: contient);
        await app.ouvrirMenu(t, ListPresentation.compact, 'search');
        expect(find.byType(ProductSearchScreen), findsOneWidget);
        await _taper(t, app, '3595');
        expect(app.serveur.recuesSur('/vente/search').last.query['query'], contient ? '%3595' : '3595', reason: 'mode $mode inchangé');
        final provider = Provider.of<ProductSearchProvider>(t.element(find.byType(ProductSearchScreen)), listen: false);
        final attendu = [_doliDecond, _doli, _doli500, _advil, _bebe, if (contient) _efferalgan];
        expect([for (final p in provider.searchResults) p.strNAME], attendu);
        expect(_ordreAffiche(t, _tous), attendu.take(_ordreAffiche(t, _tous).length).toList(), reason: 'ordre affiché');
        expect(_ordreAffiche(t, _tous).first, _doliDecond);

        // Choix du DOLIPRANE B/8 : GET /info?search=3595583 renvoie d'abord 3595583D ; on affiche bien le B/8.
        await t.tap(find.text(_doli).hitTestable());
        await app.attendre(t, const Duration(seconds: 2));
        expect(app.serveur.recuesSur('/info').last.query['search'], '3595583');
        expect(provider.selectedProductInfo?.codeCip, '3595583');
        expect(find.text(_doli), findsWidgets);
        expect(find.text(_doliDecond), findsNothing);
        expect(find.text('RAYON F-DOLI'), findsOneWidget, reason: 'emplacement du bon produit');
        expect(t.takeException(), isNull);
        await app.fermer(t);
      });
    }

    testWidgets('nom « doli » : ordre du serveur conservé', (t) async {
      final app = await _lancer(t);
      await app.ouvrirMenu(t, ListPresentation.compact, 'search');
      await _taper(t, app, 'doli');
      final provider = Provider.of<ProductSearchProvider>(t.element(find.byType(ProductSearchScreen)), listen: false);
      expect([for (final p in provider.searchResults) p.strNAME], [_doliDecond, _doli, _doli500]);
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });
  });

  group('Évaluation Vente (e2e)', () {
    for (final contient in [false, true]) {
      final mode = contient ? 'Contient' : 'Début';
      testWidgets('$mode : « 3595 » → DOLIPRANE en tête ; ventes et prix du bon produit', (t) async {
        final app = await _lancer(t, contient: contient);
        await app.ouvrirMenu(t, ListPresentation.compact, 'evaluation');
        expect(find.byType(ProductEvaluationScreen), findsOneWidget);
        await _taper(t, app, '3595');
        final provider = Provider.of<ProductStatsProvider>(t.element(find.byType(ProductEvaluationScreen)), listen: false);
        final attendu = [_doliDecond, _doli, _doli500, _advil, _bebe, if (contient) _efferalgan];
        expect([for (final p in provider.searchResults) p.strNAME], attendu);
        expect(_ordreAffiche(t, _tous).first, _doliDecond);

        await t.tap(find.text(_doli).hitTestable());
        await app.attendre(t, const Duration(seconds: 2));
        expect(app.serveur.recuesSur('/produit/stats/vente-annuelle').last.query['search'], '3595583');
        expect(provider.selectedProductSales?.codeCip, '3595583', reason: 'ventes du B/8, pas du 3595583D');
        expect(provider.selectedProductInfo?.codeCip, '3595583', reason: 'prix du B/8');
        expect(find.text(_doli), findsWidgets);
        expect(find.text(_doliDecond), findsNothing);
        expect(t.takeException(), isNull);
        await app.fermer(t);
      });
    }
  });

  group('Même règle ailleurs (e2e)', () {
    testWidgets('Analyse article : « 3595 » → lignes dont le CIP commence par 3595 en tête', (t) async {
      final app = await _lancer(t);
      await app.ouvrirMenu(t, ListPresentation.compact, 'analyse_article');
      await _taper(t, app, '3595');
      final provider = Provider.of<ArticleAnalysisProvider>(t.element(find.byType(ArticleAnalysisScreen)), listen: false);
      expect([for (final ArticleAnalysis a in provider.results) a.libelle], [_doliDecond, _doli, _doli500, _bebe]);
      expect(_ordreAffiche(t, _tous).first, _doliDecond);
      // Un nom : ordre du serveur.
      await _taper(t, app, 'DOLIPRANE 1');
      expect([for (final a in provider.results) a.libelle], [_doliDecond, _doli]);
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });

    testWidgets('recherche de l\'accueil : « 3595 » → DOLIPRANE en tête', (t) async {
      final app = await _lancer(t);
      await app.defilerJusqua(t, find.text('Rechercher un menu ou un produit'));
      await t.tap(find.text('Rechercher un menu ou un produit'));
      await app.attendre(t);
      expect(find.byType(RechercheGlobaleScreen), findsOneWidget);
      await _taper(t, app, '3595');
      expect(_ordreAffiche(t, _tous).first, _doliDecond);
      final ordre = _ordreAffiche(t, _tous);
      expect(ordre.indexOf(_doli), lessThan(ordre.contains(_bebe) ? ordre.indexOf(_bebe) : 99));
      expect(HorsLigne.instance.offline, isFalse);
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });
  });
}

/// Page 1 : 50 produits dont seul le NOM commence par « 3595 » ; page 2 : le DOLIPRANE (CIP 3595583).
class _ApiPages extends ApiService {
  _ApiPages() : super(baseUrl: 'http://localhost');
  @override
  Future<ProductPage> searchProductsPageOrFail(String query, int start, int limit) async {
    final tous = [
      for (var i = 0; i < 50; i++) _r(_p('N$i', '3595 PRODUIT ${i.toString().padLeft(2, '0')}', '60${i.toString().padLeft(5, '0')}', 1)),
      _r(_catalogue[3]),
    ];
    return ProductPage(tous.skip(start).take(limit).toList(), tous.length);
  }
}
