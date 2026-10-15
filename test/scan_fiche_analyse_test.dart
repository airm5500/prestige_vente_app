// Fiche produit de l'accueil (scan, recherche globale) sur le chemin de données du menu ANALYSE ARTICLE :
// - même route (GET /info?search=<CIP>) et même lecture (ArticleAnalysis.fromJson) que
//   ArticleAnalysisProvider.searchArticles, vérifié avec le vrai ApiService sur un faux serveur HTTP ;
// - affichage immédiat (nom, CIP, stock, prix) puis détails de l'analyse (emplacement, grossiste,
//   prix d'achat, moyenne 3 mois, quantité vendue 6 mois, graphique des ventes mensuelles) ;
// - la bonne ligne quand /info en renvoie plusieurs (CIP « commence par ») ;
// - serveur qui répond sans ligne : aucun message d'échec ; vraie erreur : code HTTP / délai + Réessayer ;
// - hors ligne : copie locale, « Disponible en ligne uniquement », aucune requête (inchangé) ;
// - scan → fiche : une seule requête /info (préchargement partagé), détails affichés ; présentations A/B/C.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestige_vente_app/accueil/fiche_produit_screen.dart';
import 'package:prestige_vente_app/accueil/recherche_globale_screen.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/article_analysis_model.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/horsligne/catalogue_sync.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart';
import 'package:prestige_vente_app/horsligne/server_monitor.dart';
import 'package:prestige_vente_app/providers/article_analysis_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Réponses réelles du serveur de test (laborex) : GET /vente/search et GET /info pour IBEX (CIP 8049052).
const _ibexId = '16819536385619978770';
final Map<String, dynamic> _ibexSearch = {
  'lgFAMILLEID': _ibexId,
  'intPRICE': 1435,
  'intNUMBERAVAILABLE': 37,
  'strNAME': 'IBEX 200/325/30MG GEL B/24',
  'intPAF': 930,
  'lgFAMILLEPARENTID': '',
  'boolDECONDITIONNE': 0,
  'intNUMBER': 37,
  'intCIP': '8049052',
  'strLIBELLEE': 'ANTALGIQUES  ET ANTIGRIPPAUX SIROPS',
  'strDESCRIPTION': 'IBEX 200/325/30MG GEL B/24',
};
final Map<String, dynamic> _ibexInfo = {
  'classe': 'A',
  'codeCip': '8049052',
  'dateDernierAchat': '04/10/2026',
  'dateDerniereVente': '05/10/2026',
  'emplacement': 'RAYON ANTALGIQUES',
  'grossiste': 'LABOREX-CI YOP',
  'libelle': 'IBEX 200/325/30MG GEL B/24',
  'moyenne': 28.67,
  'moyenneJour': 0.48,
  'prixAchat': 930,
  'prixVente': 1435,
  'produitId': _ibexId,
  'qteDernierAchat': 25,
  'qteDerniereVente': 1,
  'quantiteMois': '7:10,60:9,26:8',
  'quantiteVendue': 86,
  'stock': 37,
};
final _ibex = ProductSearchResult.fromJson(_ibexSearch);

/// Faux serveur HTTP branché sur le client Dio du vrai ApiService (routes et lecture réelles).
class _Serveur implements HttpClientAdapter {
  final requetes = <String>[];
  Duration delai = Duration.zero;
  int statutInfo = 200;
  bool delaiDepasse = false;
  List<Map<String, dynamic>> info = [_ibexInfo];
  List<Map<String, dynamic>> recherche = [_ibexSearch];

  int get infos => requetes.where((r) => r.startsWith('/info')).length;

  /// Délai de réception de la dernière requête GET /info (4.1.2 : ApiService.delaiInfo, plus les 10 s du client).
  Duration? delaiRecu;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final chemin = options.uri.path.replaceFirst(RegExp(r'^.*/api/v1'), '');
    requetes.add('$chemin?${options.uri.query}');
    if (delai > Duration.zero) await Future<void>.delayed(delai);
    if (chemin == '/info') {
      delaiRecu = options.receiveTimeout;
      if (delaiDepasse) {
        throw DioException(requestOptions: options, type: DioExceptionType.receiveTimeout);
      }
      return _json(info, statutInfo);
    }
    if (chemin == '/vente/search') return _json({'total': recherche.length, 'data': recherche}, 200);
    return _json({}, 404);
  }

  ResponseBody _json(Object body, int statut) => ResponseBody.fromString(jsonEncode(body), statut, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  @override
  void close({bool force = false}) {}
}

/// Surveillance pilotable installée comme instance de l'appli (copie locale en mémoire).
class _Install {
  final store = MemoryLocalStore();
  late final HorsLigne hl;
  _Install() {
    hl = HorsLigne(monitor: ServerMonitor(ping: () async => true, seuil: 1), store: store, sync: CatalogueSync(store: store));
    final previous = HorsLigne.instance;
    HorsLigne.instance = hl;
    addTearDown(() => HorsLigne.instance = previous);
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FicheInfoCache.instance.vider();
  });

  late ApiService api;
  late _Serveur serveur;
  late HttpClientAdapter adapterOrigine;

  void brancher() {
    api = ApiService(baseUrl: 'http://serveur-test:8080/prestige/api/v1');
    serveur = _Serveur();
    adapterOrigine = api.dio.httpClientAdapter;
    api.dio.httpClientAdapter = serveur;
    addTearDown(() => api.dio.httpClientAdapter = adapterOrigine);
  }

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  /// Graphique des ventes (bas de la fiche) amené à l'écran.
  Future<void> voirGraphique(WidgetTester tester) async {
    await tester.scrollUntilVisible(find.byType(LineChart), 200, scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
  }

  Future<void> fiche(WidgetTester tester, {ListPresentation style = ListPresentation.dashboard, ProductSearchResult? produit}) =>
      tester.pumpWidget(Provider<ApiService>.value(
        value: api,
        child: MaterialApp(home: FicheProduitScreen(produit: produit ?? _ibex, presentation: style)),
      ));

  group('Même chemin de données que le menu Analyse article', () {
    test('même requête GET /info?search=<CIP> et même lecture que le détail d\'Analyse article', () async {
      brancher();
      final provider = ArticleAnalysisProvider(api, cache: FicheInfoCache());
      await provider.searchArticles('8049052');
      // 4.1.2 : la liste vient de la recherche rapide (GET /vente/search), le détail de GET /info (CIP exact).
      expect(serveur.requetes.single, startsWith('/vente/search?'));
      final viaAnalyse = (await provider.chargerDetail(provider.results.single))!;
      final viaFiche = articleDuProduit(await api.fetchArticleAnalysisOrFail('8049052'), _ibex)!;
      expect(serveur.requetes.where((r) => r.startsWith('/info')), ['/info?search=8049052', '/info?search=8049052']);
      for (final a in [viaAnalyse, viaFiche]) {
        expect(a.produitId, _ibexId);
        expect(a.emplacement, 'RAYON ANTALGIQUES');
        expect(a.grossiste, 'LABOREX-CI YOP');
        expect(a.prixAchat, 930);
        expect(a.prixVente, 1435);
        expect(a.moyenne, 28.67);
        expect(a.quantiteVendue, 86);
        expect(a.stock, 37);
        expect(a.getChartData().map((p) => (p.month, p.qty)), [(8, 26.0), (9, 60.0), (10, 7.0)]);
      }
    });

    test('lecture tolérante (nombres en texte, stock décimal) : plus d\'échec de lecture', () {
      final a = ArticleAnalysis.fromJson({'codeCip': 8049052, 'stock': 37.0, 'prixVente': '1435', 'moyenne': '28.67', 'libelle': null});
      expect(a.codeCip, '8049052');
      expect(a.stock, 37);
      expect(a.prixVente, 1435);
      expect(a.moyenne, 28.67);
      expect(a.libelle, '');
    });

    test('plusieurs lignes (CIP « commence par ») : celle du produit, pas la première', () {
      final det = ArticleAnalysis.fromJson({..._ibexInfo, 'produitId': 'DET', 'codeCip': '8049052D', 'libelle': 'A IBEX DET', 'emplacement': 'DETAIL'});
      final boite = ArticleAnalysis.fromJson(_ibexInfo);
      expect(articleDuProduit([det, boite], _ibex)!.emplacement, 'RAYON ANTALGIQUES');
      expect(articleDuProduit([det], _ibex), isNull, reason: 'autre produit : pas de détails trompeurs');
    });
  });

  group('Fiche produit', () {
    testWidgets('affichage immédiat des données de base, puis détails de l\'analyse article', (tester) async {
      phone(tester);
      brancher();
      _Install();
      serveur.delai = const Duration(milliseconds: 800);
      await fiche(tester);
      // 1ʳᵉ image : nom, CIP, stock, prix (ligne du résultat) + squelettes, avant toute réponse.
      expect(find.text('IBEX 200/325/30MG GEL B/24'), findsOneWidget);
      expect(find.text('8049052'), findsOneWidget);
      expect(find.text('37'), findsOneWidget);
      expect(find.text('${Constants.formatNumber(1435)} F'), findsOneWidget);
      // 4.3.2 : emplacement (zone) et prix d'achat déjà connus par la recherche rapide : affichés tout de suite.
      expect(find.byKey(const ValueKey('fiche-connu-Emplacement')), findsOneWidget);
      expect(find.byKey(const ValueKey("fiche-connu-Prix d'achat")), findsOneWidget);
      expect(find.byKey(const ValueKey('fiche-squelette-Grossiste')), findsOneWidget);
      expect(find.byKey(const ValueKey('fiche-squelette-ventes')), findsOneWidget);
      expect(find.text('LABOREX-CI YOP'), findsNothing);
      await tester.pump(const Duration(milliseconds: 801));
      await tester.pump();
      // Détails : mêmes informations que « Détails de l'Article ».
      expect(find.byKey(const ValueKey('fiche-squelette-Grossiste')), findsNothing);
      expect(find.text('RAYON ANTALGIQUES'), findsOneWidget);
      expect(find.text('LABOREX-CI YOP'), findsOneWidget);
      expect(find.text('930 FCFA'), findsOneWidget); // prix d'achat
      expect(find.text('28.67'), findsWidgets); // moyenne 3 mois
      expect(find.text('86'), findsOneWidget); // quantité vendue 6 mois
      await voirGraphique(tester);
      expect(find.text('Évolution des ventes mensuelles:'), findsOneWidget);
      expect(find.byType(LineChart), findsOneWidget);
      expect(find.text('Réessayer'), findsNothing);
      expect(serveur.requetes, ['/info?search=8049052']);
      expect(tester.takeException(), isNull);
    });

    for (final style in ListPresentation.values) {
      testWidgets('présentation ${style.label} : détails et graphique, sans débordement', (tester) async {
        phone(tester);
        brancher();
        _Install();
        await fiche(tester, style: style);
        await tester.pumpAndSettle();
        expect(find.text('LABOREX-CI YOP'), findsOneWidget);
        await voirGraphique(tester);
        expect(find.byType(LineChart), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('le serveur répond sans ligne d\'analyse : aucun message d\'échec', (tester) async {
      phone(tester);
      brancher();
      _Install();
      serveur.info = [];
      await fiche(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('fiche-sans-analyse')), findsOneWidget);
      expect(find.byKey(const ValueKey('fiche-erreur')), findsNothing);
      expect(find.textContaining('non disponibles'), findsNothing);
      expect(find.text('Réessayer'), findsNothing);
      expect(find.text('IBEX 200/325/30MG GEL B/24'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('erreur HTTP : code précis + Réessayer, qui recharge', (tester) async {
      phone(tester);
      brancher();
      _Install();
      serveur.statutInfo = 500;
      await fiche(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('fiche-erreur')), findsOneWidget);
      expect(find.textContaining('HTTP 500'), findsOneWidget);
      expect(find.textContaining('GET /info'), findsOneWidget);
      serveur.statutInfo = 200;
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('fiche-erreur')), findsNothing);
      expect(find.text('LABOREX-CI YOP'), findsOneWidget);
      expect(serveur.infos, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('délai dépassé : message avec la durée réelle (30 s, plus 10 s) + Réessayer', (tester) async {
      phone(tester);
      brancher();
      _Install();
      serveur.delaiDepasse = true;
      await fiche(tester);
      await tester.pumpAndSettle();
      // 4.1.2 : GET /info attend ApiService.delaiInfo (30 s) ; le message annonce cette durée (avant : « 10 s »,
      // délai du client partagé, alors que l'appli annonçait 30 s).
      expect(serveur.delaiRecu, ApiService.delaiInfo);
      expect(ApiService.delaiInfo, const Duration(seconds: 30));
      expect(find.textContaining('Délai dépassé'), findsOneWidget);
      expect(find.textContaining('en 30 s'), findsOneWidget);
      expect(find.textContaining('10 s'), findsNothing);
      expect(find.text('Réessayer'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('fiche quittée avant la réponse : aucune erreur ; la réponse remplit le cache (réouverture sans requête)', (tester) async {
      phone(tester);
      brancher();
      _Install();
      final cache = FicheInfoCache();
      final reponse = Completer<List<ArticleAnalysis>>();
      var appels = 0;
      Future<List<ArticleAnalysis>> load(String _) {
        appels++;
        return reponse.future;
      }

      await tester.pumpWidget(MaterialApp(home: FicheProduitScreen(produit: _ibex, loadAnalyse: load, cache: cache)));
      await tester.pumpWidget(const SizedBox());
      expect(cache.abandons, 1);
      // 4.3.2 : la requête continue (le serveur la calcule de toute façon) ; sa réponse sert à la réouverture.
      reponse.complete([ArticleAnalysis.fromJson(_ibexInfo)]);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(MaterialApp(home: FicheProduitScreen(produit: _ibex, loadAnalyse: load, cache: cache)));
      expect(find.text('LABOREX-CI YOP'), findsOneWidget, reason: 'réouverture : analyse affichée dès la 1ʳᵉ image');
      expect(appels, 1);
    });

    testWidgets('hors ligne : copie locale, « Disponible en ligne uniquement », aucune requête (inchangé)', (tester) async {
      phone(tester);
      brancher();
      final inst = _Install();
      await inst.store.replace(CatalogueCategorie.produits, [
        {..._ibexSearch, 'intNUMBERAVAILABLE': 5}
      ], DateTime(2026, 10, 9, 18, 45));
      await inst.hl.sync.refreshStats();
      inst.hl.monitor.goOffline(manuel: false);
      await fiche(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fiche_hors_ligne')), findsOneWidget);
      expect(find.textContaining('09/10 18:45'), findsOneWidget);
      expect(find.text('5'), findsOneWidget); // stock de la copie locale
      expect(find.text('Disponible en ligne uniquement'), findsNWidgets(2));
      expect(find.byKey(const ValueKey('fiche-erreur')), findsNothing);
      expect(find.byType(LineChart), findsNothing);
      expect(serveur.infos, 0);
      expect(tester.takeException(), isNull);
    });
  });

  group('Scan → fiche', () {
    testWidgets('code scanné : fiche ouverte, une seule requête /info (préchargement partagé), détails', (tester) async {
      phone(tester);
      brancher();
      _Install();
      await tester.pumpWidget(Provider<ApiService>.value(
        value: api,
        child: MaterialApp(home: RechercheGlobaleScreen(menus: const [], onOpenMenu: (_) {}, initialCode: '8049052')),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(FicheProduitScreen), findsOneWidget);
      expect(find.text('IBEX 200/325/30MG GEL B/24'), findsOneWidget);
      expect(find.text('RAYON ANTALGIQUES'), findsOneWidget);
      expect(find.text('LABOREX-CI YOP'), findsOneWidget);
      expect(serveur.requetes.where((r) => r.startsWith('/vente/search')), isNotEmpty);
      expect(serveur.infos, 1);
      expect(serveur.requetes.last, '/info?search=8049052');
      expect(tester.takeException(), isNull);
    });

    testWidgets('sélection dans la recherche globale : même fiche, mêmes détails', (tester) async {
      phone(tester);
      brancher();
      _Install();
      await tester.pumpWidget(Provider<ApiService>.value(
        value: api,
        child: MaterialApp(home: RechercheGlobaleScreen(menus: const [], onOpenMenu: (_) {})),
      ));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'ibex');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      await tester.tap(find.text('IBEX 200/325/30MG GEL B/24'));
      await tester.pumpAndSettle();
      expect(find.byType(FicheProduitScreen), findsOneWidget);
      expect(find.text('LABOREX-CI YOP'), findsOneWidget);
      await voirGraphique(tester);
      expect(find.byType(LineChart), findsOneWidget);
      expect(serveur.infos, 1);
      expect(tester.takeException(), isNull);
    });
  });
}
