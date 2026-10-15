// Retours de la vidéo client (serveur récent : commit 2e4615e « v1/info et v1/checkproduit rapides »,
// audit sécurité 6919e280 + 035346e9 « session renouvelée ») :
// 1. GET /info : lecture tolérante (liste directe ET objet {data: […]}), d'après InfoArticleDTO du serveur
//    récent (champs nuls omis, stockReserve / seuilReserve / seuilMiniRayon) ; 401 « Veuillez vous connecter »,
//    réponse illisible, délai : erreur précise + Réessayer — jamais de squelette ni de roue sans fin ;
//    Analyse article : message clair au lieu de rien.
// 2. Recherche : anti-rebond 350 ms, une seule requête en vol (la précédente est ANNULÉE), 2 caractères minimum.
// 3. Favoris de l'accueil : appui long → Ajouter / Retirer des favoris, 4 au plus (message), clé conservée.
// 4. Charte bleu nuit / ambre : barre du bas de l'accueil, en-tête des Réglages.
// 5. « Ajouter une photo » visible directement pour l'administrateur (absent sinon).
// 6. Entrée « Borne / vente discrète » (groupe Ventes) pour l'administrateur, sans rien activer.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestige_vente_app/accueil/accueil_menus.dart';
import 'package:prestige_vente_app/accueil/accueil_screen.dart';
import 'package:prestige_vente_app/accueil/fiche_produit_screen.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/article_analysis_model.dart';
import 'package:prestige_vente_app/api/models/bon_livraison.dart';
import 'package:prestige_vente_app/api/models/licence_model.dart';
import 'package:prestige_vente_app/api/models/officine.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/product_info.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/api/models/user.dart';
import 'package:prestige_vente_app/borne/borne_config.dart';
import 'package:prestige_vente_app/borne/borne_reglages_page.dart';
import 'package:prestige_vente_app/images/images_reglages.dart';
import 'package:prestige_vente_app/images/photo_produit.dart';
import 'package:prestige_vente_app/images/produit_images.dart';
import 'package:prestige_vente_app/parametres/parametres_screen.dart';
import 'package:prestige_vente_app/parametres/parametres_services.dart';
import 'package:prestige_vente_app/pointage/pointage_repository.dart';
import 'package:prestige_vente_app/providers/article_analysis_provider.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/bl_control_provider.dart';
import 'package:prestige_vente_app/providers/licence_provider.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/screens/analysis/article_analysis_screen.dart';
import 'package:prestige_vente_app/services/product_finder.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------------------------------------
// Réponses construites d'après le serveur récent (InfoArticleRessource / InfoArticleDTO, commit 2e4615e) :
// GET v1/info renvoie une LISTE d'InfoArticleDTO ; le sérialiseur omet les champs nuls (produit sans vente :
// pas de « moyenne », « quantiteMois »…) ; stockReserve / seuilReserve / seuilMiniRayon seulement si le produit
// est géré en réserve (bool_RESERVE). Les nombres sont des Integer / BigDecimal.
// ---------------------------------------------------------------------------------------------------------
final Map<String, dynamic> _doliprane = {
  'classe': 'A',
  'codeCip': '3529422',
  'dateDernierAchat': '29/08/2026',
  'dateDerniereVente': '10/10/2026',
  'emplacement': 'ANTALGIQUES  ET ANTIGRIPPAUX SIROPS',
  'grossiste': 'LABOREX-CI YOP',
  'libelle': 'DOLIPRANE 1000MG CPR EFFV B/8',
  'moyenne': 11.33,
  'moyenneJour': 0.22,
  'prixAchat': 976,
  'prixVente': 1475,
  'produitId': '16819535271235676850',
  'qteDernierAchat': 5,
  'qteDerniereVente': 8,
  'quantiteMois': '10:10,12:9,22:8',
  'quantiteVendue': 34,
  'stock': 18,
  // Produit géré en réserve (bool_RESERVE) : stock réserve et seuils.
  'stockReserve': 40,
  'seuilReserve': 10,
  'seuilMiniRayon': 20,
};
// Produit sans vente sur la période : champs nuls omis par le serveur.
final Map<String, dynamic> _dolipraneSansVente = {
  'codeCip': '3480911',
  'dateDernierAchat': '19/08/2026',
  'emplacement': 'SUPPOSITOIRES',
  'grossiste': 'LABOREX-CI YOP',
  'libelle': 'DOLIPRANE 100MG NN SUPPO B/10',
  'prixAchat': 821,
  'prixVente': 1240,
  'produitId': '168195352348543219',
  'qteDernierAchat': 1,
  'stock': 1,
};

/// Faux serveur branché sur le client Dio partagé du vrai ApiService.
class _Serveur implements HttpClientAdapter {
  final requetes = <String>[];
  final annulees = <String>[];

  /// Corps et statut de GET /info (objet JSON, ou texte brut si [texte]).
  Object? info;
  String? texte;
  int statut = 200;
  String typeContenu = Headers.jsonContentType;

  /// GET /vente/search : statut / texte brut imposés (panne de la recherche rapide d'Analyse article) ; [sansProduit] :
  /// aucun produit.
  int statutRecherche = 200;
  String? texteRecherche;
  bool sansProduit = false;

  /// Réponses retenues jusqu'à [liberer] (ou à l'annulation).
  bool retenir = false;
  bool jamais = false;
  final _attentes = <String, Completer<void>>{};

  void liberer(String requete) => _attentes.remove(requete)?.complete();

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final chemin = options.uri.path.replaceFirst(RegExp(r'^.*/api/v1'), '');
    final r = '$chemin?${Uri.decodeQueryComponent(options.uri.query)}';
    requetes.add(r);
    var annulee = false;
    cancelFuture?.then((_) {
      annulee = true;
      annulees.add(r);
    });
    if (jamais || retenir) {
      final c = Completer<void>();
      _attentes[r] = c;
      await Future.any([c.future, if (cancelFuture != null) cancelFuture]);
    }
    if (annulee) return ResponseBody.fromString('', 499);
    if (chemin == '/info') {
      if (texte != null) return ResponseBody.fromString(texte!, statut, headers: {Headers.contentTypeHeader: [typeContenu]});
      return ResponseBody.fromString(jsonEncode(info), statut, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
    }
    if (chemin == '/vente/search') {
      if (texteRecherche != null) {
        return ResponseBody.fromString(texteRecherche!, statutRecherche, headers: {Headers.contentTypeHeader: ['text/plain']});
      }
      final q = options.uri.queryParameters['query'] ?? '';
      final items = [
        if (!sansProduit && ('doliprane'.startsWith(q.toLowerCase()) || q.toLowerCase().startsWith('dol')))
          {'lgFAMILLEID': 'f1', 'strNAME': 'DOLIPRANE 1000MG', 'intCIP': '3529422', 'intPRICE': 1475, 'intNUMBERAVAILABLE': 18},
      ];
      return ResponseBody.fromString(jsonEncode({'total': items.length, 'data': items}), 200,
          headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
    }
    return ResponseBody.fromString('{}', 404, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

/// Attend (temps réel, 3 s au plus) que [condition] soit vraie (requête arrivée au faux serveur…).
Future<void> _jusqua(bool Function() condition) async {
  for (var i = 0; i < 300 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// ApiService réel (routes et lecture réelles) sur le faux serveur.
(ApiService, _Serveur) _brancher() {
  final api = ApiService(baseUrl: 'http://serveur-test:8080/prestige/api/v1');
  final s = _Serveur();
  final origine = api.dio.httpClientAdapter;
  api.dio.httpClientAdapter = s;
  addTearDown(() => api.dio.httpClientAdapter = origine);
  return (api, s);
}

// --- Faux services pour l'accueil et les réglages ---
class _FakeApi extends ApiService {
  _FakeApi() : super(baseUrl: 'http://localhost');

  @override
  Future<User?> login(String login, String password) async =>
      User(userId: 'u1', login: login, firstName: 'Awa', lastName: 'Kouassi', officineName: 'PHCIE TEST');

  @override
  Future<void> logout() async {}

  @override
  Future<Officine?> fetchOfficineInfo() async => Officine(fullName: 'KONAN KOU', nomComplet: 'PHARMACIE LES PALMIERS');

  @override
  Future<List<PreventeListItem>> getPreventes() async => const [];

  @override
  Future<List<BonLivraison>> getBonsLivraison({String query = '', String? dtStart, String? dtEnd}) async => const [];

  @override
  Future<ProductPage> searchProductsPageOrFail(String query, int start, int limit) async => const ProductPage([], 0);
}

class _FakeLicence extends LicenceProvider {
  _FakeLicence(super.api);
  @override
  LicenceStatus get status => LicenceStatus.valid;
  @override
  LicenceModel? get licence => LicenceModel(id: '1', dateStart: '', dateEnd: '', typeLicence: '');
  @override
  int get remainingDays => 120;
  @override
  Future<bool> mustBlockAccess() async => false;
  @override
  void checkReminders(BuildContext context) {}
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FicheInfoCache.instance.vider();
  });

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(720, 1400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  // =======================================================================================================
  group('1. GET /info : deux formes, 401, illisible, délai — jamais rien, jamais sans fin', () {
    test('forme actuelle (liste directe, champs nuls omis, stock réserve et seuils)', () async {
      final (api, s) = _brancher();
      s.info = [_doliprane, _dolipraneSansVente];
      final l = await api.fetchArticleAnalysisOrFail('dolip');
      expect(s.requetes, ['/info?search=dolip']);
      expect(l.map((a) => a.codeCip), ['3529422', '3480911']);
      expect(l.first.moyenne, 11.33);
      expect(l.first.reserve.stockReserve, 40);
      expect(l.first.reserve.seuilReserve, 10);
      expect(l.first.reserve.seuilMiniRayon, 20);
      expect(l.first.reserve.total(l.first.stock), 58);
      // Produit sans vente (champs omis) : lu sans échec, pas géré en réserve.
      expect(l.last.moyenne, 0);
      expect(l.last.quantiteMoisBrut, '');
      expect(l.last.reserve.geree, isFalse);
    });

    test('forme paginée {data: […], total} et nombres en texte', () async {
      final (api, s) = _brancher();
      s.info = {
        'success': true,
        'total': 1,
        'data': [
          {..._doliprane, 'prixVente': '1475', 'stock': '18', 'moyenne': '11.33', 'stockReserve': '40.0'},
        ],
      };
      final l = await api.fetchArticleAnalysisOrFail('dolip');
      expect(l.single.prixVente, 1475);
      expect(l.single.stock, 18);
      expect(l.single.moyenne, 11.33);
      expect(l.single.reserve.stockReserve, 40);
      // Même lecture tolérante pour la Recherche Article (ProductInfo).
      final info = await api.getProductInfo('3529422');
      expect(info, isNotNull);
      expect(info!.stock, 18);
      expect(info.prixVente, 1475);
      expect(info.reserve.stockReserve, 40);
    });

    test('lignesInfo : liste, {data}, {results}, texte JSON, {total: 0}, illisible', () {
      expect(ApiService.lignesInfo([_doliprane])!.single['codeCip'], '3529422');
      expect(ApiService.lignesInfo({'data': [_doliprane]})!.length, 1);
      expect(ApiService.lignesInfo({'results': [_doliprane]})!.length, 1);
      expect(ApiService.lignesInfo(jsonEncode([_doliprane]))!.length, 1);
      expect(ApiService.lignesInfo({'total': 0}), isEmpty);
      expect(ApiService.lignesInfo(null), isEmpty);
      expect(ApiService.lignesInfo('Veuillez vous connecter'), isNull);
      expect(ApiService.lignesInfo('<html><body>Erreur</body></html>'), isNull);
      expect(ApiService.lignesInfo({'message': 'erreur'}), isNull);
    });

    test('401 texte « Veuillez vous connecter » (cookie ancien) : session expirée, pas une liste vide', () async {
      final (api, s) = _brancher();
      s
        ..statut = 401
        ..texte = 'Veuillez vous connecter'
        ..typeContenu = 'text/plain';
      await expectLater(
        api.fetchArticleAnalysisOrFail('dolip'),
        throwsA(isA<ApiLoadException>().having((e) => e.message, 'message', 'Session expirée — reconnectez-vous (HTTP 401, GET /info).')),
      );
      // Menu Analyse article : l'erreur remonte (l'ancienne version renvoyait [] : écran vide).
      await expectLater(api.fetchArticleAnalysis('dolip'), throwsA(isA<ApiLoadException>()));
    });

    test('200 avec texte de connexion / texte illisible : message précis', () async {
      final (api, s) = _brancher();
      s
        ..texte = 'Veuillez vous connecter'
        ..typeContenu = 'text/plain';
      await expectLater(api.fetchArticleAnalysisOrFail('dolip'),
          throwsA(isA<ApiLoadException>().having((e) => e.message, 'message', contains('Session expirée — reconnectez-vous'))));
      s.texte = 'Internal error <b>NullPointerException</b>';
      await expectLater(api.fetchArticleAnalysisOrFail('dolip'),
          throwsA(isA<ApiLoadException>().having((e) => e.message, 'message', startsWith('Réponse illisible du serveur (GET /info, HTTP 200)'))));
      s
        ..texte = null
        ..statut = 500
        ..info = {};
      await expectLater(api.fetchArticleAnalysisOrFail('dolip'),
          throwsA(isA<ApiLoadException>().having((e) => e.message, 'message', contains('HTTP 500'))));
    });

    test('serveur qui ne répond jamais : « Délai dépassé » au bout de delaiInfo, requête abandonnée', () async {
      final (api, s) = _brancher();
      s.jamais = true;
      final avant = ApiService.delaiInfo;
      ApiService.delaiInfo = const Duration(milliseconds: 300);
      addTearDown(() => ApiService.delaiInfo = avant);
      final debut = DateTime.now();
      await expectLater(api.fetchArticleAnalysisOrFail('dolip'),
          throwsA(isA<ApiLoadException>().having((e) => e.message, 'message', startsWith('Délai dépassé'))));
      expect(DateTime.now().difference(debut), lessThan(const Duration(seconds: 5)));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(s.annulees, ['/info?search=dolip'], reason: 'la requête est abandonnée, pas laissée en vol');
    });

    test('Analyse article (provider) : liste rapide en erreur, aucun résultat, Réessayer — GET /info seulement pour une liste reçue', () async {
      final (api, s) = _brancher();
      final p = ArticleAnalysisProvider(api, cache: FicheInfoCache());
      s
        ..statutRecherche = 500
        ..texteRecherche = '<html>Erreur</html>';
      await p.searchArticles('dolip');
      expect(p.isLoading, isFalse);
      expect(p.error, isNotNull);
      expect(p.results, isEmpty);
      s
        ..statutRecherche = 200
        ..texteRecherche = null
        ..sansProduit = true;
      await p.reessayer();
      expect(p.error, isNull);
      expect(p.aucunResultat, isTrue);
      expect(s.requetes.where((r) => r.startsWith('/info')), isEmpty, reason: 'liste en erreur ou vide : aucun GET /info');
      s
        ..sansProduit = false
        ..info = [_doliprane, _dolipraneSansVente];
      await p.reessayer();
      expect(p.results.single.strNAME, 'DOLIPRANE 1000MG');
      expect(p.aucunResultat, isFalse);
      // 4.3.2 : liste reçue → UN GET /info de la saisie (lot), dont le détail du produit choisi est tiré.
      final d = await p.chargerDetail(p.results.single);
      expect(s.requetes.where((r) => r.startsWith('/info')), ['/info?search=dolip'], reason: 'aucune 2ᵉ requête au clic');
      expect(d!.grossiste, 'LABOREX-CI YOP');
      expect(d.codeCip, '3529422', reason: 'la ligne du produit choisi, pas une autre du lot');
    });

    testWidgets('écran Analyse article : « dolip » en erreur → message + Réessayer (jamais un écran vide)', (tester) async {
      phone(tester);
      final (api, s) = _brancher();
      s
        ..statutRecherche = 401
        ..texteRecherche = 'Veuillez vous connecter';
      final provider = ArticleAnalysisProvider(api, cache: FicheInfoCache());
      await tester.pumpWidget(ChangeNotifierProvider<ArticleAnalysisProvider>.value(
        value: provider,
        child: const MaterialApp(home: ArticleAnalysisScreen(presentation: ListPresentation.dashboard)),
      ));
      await tester.enterText(find.byType(TextField), 'dolip');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('analyse-erreur')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // Le serveur répond de nouveau : Réessayer affiche les produits.
      s
        ..statutRecherche = 200
        ..texteRecherche = null
        ..info = [_doliprane];
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.text('DOLIPRANE 1000MG'), findsOneWidget);
      // Choix du produit : détail GET /info par CIP.
      await tester.tap(find.text('DOLIPRANE 1000MG'));
      await tester.pumpAndSettle();
      expect(find.text('LABOREX-CI YOP'), findsOneWidget);
      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();
      // Aucun produit : message clair (ni roue, ni écran « Saisissez… »).
      s.sansProduit = true;
      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('analyse-aucun')), findsOneWidget);
      expect(find.textContaining('« zzzz »'), findsOneWidget);
      api.dio.httpClientAdapter = s; // (rétabli par addTearDown)
    });

    testWidgets('fiche produit : serveur muet → erreur « Délai dépassé » + Réessayer, plus aucun squelette', (tester) async {
      phone(tester);
      final avant = delaiMaxFiche;
      delaiMaxFiche = () => const Duration(seconds: 3);
      addTearDown(() => delaiMaxFiche = avant);
      final jamais = Completer<List<ArticleAnalysis>>();
      var appels = 0;
      final produit = ProductSearchResult(
          lgFAMILLEID: 'f1', strNAME: 'IBEX 200/235/30MG GEL B/24', intCIP: '8049052', intPRICE: 1435, intNUMBERAVAILABLE: 83, strLIBELLEE: '', intPAF: 0);
      await tester.pumpWidget(MaterialApp(
        home: FicheProduitScreen(
          produit: produit,
          presentation: ListPresentation.dashboard,
          loadAnalyse: (_) {
            appels++;
            return appels == 1 ? jamais.future : Future.value([ArticleAnalysis.fromJson({..._doliprane, 'codeCip': '8049052', 'produitId': 'f1'})]);
          },
        ),
      ));
      await tester.pump();
      expect(find.byKey(const ValueKey('fiche-squelette-Emplacement')), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      expect(find.byKey(const ValueKey('fiche-squelette-Emplacement')), findsNothing);
      expect(find.byKey(const ValueKey('fiche-squelette-ventes')), findsNothing);
      expect(find.byKey(const ValueKey('fiche-squelette-moyenne')), findsNothing);
      expect(find.textContaining('Délai dépassé'), findsOneWidget);
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('fiche-info-Grossiste')), findsOneWidget);
      expect(find.textContaining('Délai dépassé'), findsNothing);
      expect(appels, 2, reason: 'Réessayer envoie une NOUVELLE requête (jamais rattachée à celle restée muette)');
    });

    testWidgets('fiche produit : 401 « Veuillez vous connecter » → « Session expirée — reconnectez-vous »', (tester) async {
      phone(tester);
      final (api, s) = _brancher();
      s
        ..statut = 401
        ..texte = 'Veuillez vous connecter';
      final produit = ProductSearchResult(
          lgFAMILLEID: 'f1', strNAME: 'IBEX', intCIP: '8049052', intPRICE: 1435, intNUMBERAVAILABLE: 83, strLIBELLEE: '', intPAF: 0);
      await tester.pumpWidget(Provider<ApiService>.value(
          value: api, child: MaterialApp(home: FicheProduitScreen(produit: produit, presentation: ListPresentation.dashboard))));
      await tester.pumpAndSettle();
      expect(find.textContaining('Session expirée — reconnectez-vous'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
      expect(find.byKey(const ValueKey('fiche-squelette-Emplacement')), findsNothing);
    });
  });

  // =======================================================================================================
  group('2. Recherche : une seule requête en vol, la précédente annulée, anti-rebond', () {
    test('Analyse article : la frappe suivante ANNULE la requête précédente', () async {
      final (api, s) = _brancher();
      s
        ..retenir = true
        ..info = [_doliprane];
      final p = ArticleAnalysisProvider(api, cache: FicheInfoCache());
      final f1 = p.searchArticles('dol');
      await _jusqua(() => s.requetes.length == 1);
      final f2 = p.searchArticles('doli');
      await _jusqua(() => s.requetes.length == 2 && s.annulees.isNotEmpty);
      expect(s.annulees.single, startsWith('/vente/search?query=dol&'));
      expect(p.annulees, 1);
      s.liberer(s.requetes.last);
      await f1;
      await f2;
      expect(p.query, 'doli');
      expect(p.error, isNull, reason: 'l\'annulation de la recherche remplacée n\'est pas une erreur');
      expect(p.results, hasLength(1));
      // 4.3.2 : liste reçue → lot GET /info de la saisie « doli » (retenu ici par le faux serveur).
      await _jusqua(() => s.requetes.length == 3);
      expect(s.requetes.last, '/info?search=doli');
      // « dolip » prolonge « doli » : couverte par le lot en route, aucun nouveau GET /info.
      final f3 = p.searchArticles('dolip');
      await _jusqua(() => s.requetes.length == 4);
      expect(s.requetes.last, startsWith('/vente/search?query=dolip&'));
      // Moins de 2 caractères : rien n'est envoyé, la recherche en vol ET le lot devenu inutile sont abandonnés.
      await p.searchArticles('d');
      await f3;
      await _jusqua(() => s.annulees.length == 3);
      expect(s.annulees, containsAll(['/info?search=doli']));
      expect(s.annulees.where((r) => r.startsWith('/vente/search?query=dolip&')), hasLength(1));
      expect(s.requetes.where((r) => r.startsWith('/vente/search?query=d&')), isEmpty);
      expect(s.requetes.where((r) => r.startsWith('/info')), ['/info?search=doli'], reason: 'aucun GET /info par lettre');
      expect(p.isLoading, isFalse);
    });

    test('Recherche produit (menus) : la recherche suivante annule la précédente', () async {
      final (api, s) = _brancher();
      s.retenir = true;
      final search = PagedProductSearch(() => api);
      final f1 = search.run('dol');
      await _jusqua(() => s.requetes.length == 1);
      final f2 = search.run('doli');
      await _jusqua(() => s.requetes.length == 2 && s.annulees.isNotEmpty);
      expect(s.annulees.single, startsWith('/vente/search?query=dol&'));
      s.liberer(s.requetes.last);
      expect(await f1, isFalse, reason: 'remplacée : ignorée');
      expect(await f2, isTrue);
      expect(search.error, isNull);
      expect(search.items.single.strNAME, 'DOLIPRANE 1000MG');
      // Effacer annule aussi la recherche en vol.
      final f3 = search.run('dolipr');
      await _jusqua(() => s.requetes.length == 3);
      search.clear();
      expect(await f3, isFalse);
      await _jusqua(() => s.annulees.length == 2);
      expect(s.annulees, hasLength(2));
    });

    testWidgets('Analyse article : frappe rapide « d o l i p » → UNE recherche 350 ms après la dernière frappe, puis UN lot', (tester) async {
      phone(tester);
      final (api, s) = _brancher();
      s.info = [_doliprane];
      await tester.pumpWidget(ChangeNotifierProvider<ArticleAnalysisProvider>(
        create: (_) => ArticleAnalysisProvider(api, cache: FicheInfoCache()),
        child: const MaterialApp(home: ArticleAnalysisScreen(presentation: ListPresentation.compact)),
      ));
      for (final t in ['d', 'do', 'dol', 'doli', 'dolip']) {
        await tester.enterText(find.byType(TextField), t);
        await tester.pump(const Duration(milliseconds: 120));
      }
      expect(s.requetes, isEmpty, reason: 'anti-rebond : rien pendant la frappe');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(s.requetes, hasLength(2));
      expect(s.requetes.first, startsWith('/vente/search?query=dolip&'), reason: 'liste rapide d\'abord');
      expect(s.requetes.last, '/info?search=dolip', reason: '4.3.2 : puis UN lot GET /info de la saisie finale');
      expect(find.text('DOLIPRANE 1000MG'), findsOneWidget);
      // 1 caractère : aucune requête.
      await tester.enterText(find.byType(TextField), 'd');
      await tester.pump(const Duration(milliseconds: 500));
      expect(s.requetes, hasLength(2));
    });
  });

  // =======================================================================================================
  group('3-4-6. Accueil : favoris par appui long, charte, entrée Borne (administrateur)', () {
    Future<AuthProvider> pumpAccueil(WidgetTester tester, {String login = 'caissier', ListPresentation style = ListPresentation.dashboard, List<String>? favoris}) async {
      phone(tester);
      if (favoris != null) SharedPreferences.setMockInitialValues({AccueilFavoris.key: favoris});
      final a = _FakeApi();
      final auth = AuthProvider(a);
      await auth.login(login, 'x');
      final settings = SettingsProvider();
      await settings.saveMenuConfig(const [], const []);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          Provider<ApiService>.value(value: a),
          ChangeNotifierProvider<LicenceProvider>.value(value: _FakeLicence(a)),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => SaleProvider(a)),
          ChangeNotifierProvider(create: (_) => BlControlProvider(a)),
        ],
        child: MaterialApp(home: AccueilScreen(presentation: style, serverCheck: () async => true, askPin: (_) async => true)),
      ));
      await tester.pumpAndSettle();
      return auth;
    }

    Future<List<String>?> favorisEnregistres() async => (await SharedPreferences.getInstance()).getStringList(AccueilFavoris.key);

    testWidgets('appui long sur une tuile → Ajouter aux favoris (clé accueil_favoris_v1), puis Retirer', (tester) async {
      await pumpAccueil(tester, favoris: ['prevente', 'assurance']);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('tuile_stock')), 200, scrollable: find.byType(Scrollable).first);
      await tester.longPress(find.byKey(const ValueKey('tuile_stock')));
      await tester.pumpAndSettle();
      expect(find.text('Ajouter aux favoris'), findsOneWidget);
      expect(find.text('Favoris : 2/4'), findsOneWidget);
      await tester.tap(find.byKey(const Key('favori_basculer')));
      await tester.pumpAndSettle();
      expect(await favorisEnregistres(), ['prevente', 'assurance', 'stock']);
      expect(find.text('« État stock » ajouté aux favoris.'), findsOneWidget);
      // Retour en haut de l'accueil : la tuile est dans les favoris.
      await tester.scrollUntilVisible(find.byKey(const ValueKey('favori_stock')), -200, scrollable: find.byType(Scrollable).first);
      expect(find.byKey(const ValueKey('favori_stock')), findsOneWidget);
      // Appui long sur le favori : Retirer.
      await tester.longPress(find.byKey(const ValueKey('favori_stock')));
      await tester.pumpAndSettle();
      expect(find.text('Retirer des favoris'), findsOneWidget);
      await tester.tap(find.byKey(const Key('favori_basculer')));
      await tester.pumpAndSettle();
      expect(await favorisEnregistres(), ['prevente', 'assurance']);
      expect(find.byKey(const ValueKey('favori_stock')), findsNothing);
    });

    testWidgets('limite de 4 favoris : message, rien d\'ajouté', (tester) async {
      await pumpAccueil(tester); // favoris par défaut : 4
      await tester.scrollUntilVisible(find.byKey(const ValueKey('tuile_stock')), 200, scrollable: find.byType(Scrollable).first);
      await tester.longPress(find.byKey(const ValueKey('tuile_stock')));
      await tester.pumpAndSettle();
      expect(find.text('Déjà 4 favoris (maximum) : retirez-en un d\'abord'), findsOneWidget);
      await tester.tap(find.byKey(const Key('favori_basculer')));
      await tester.pumpAndSettle();
      expect(find.textContaining('4 favoris au maximum'), findsOneWidget);
      expect((await SharedPreferences.getInstance()).getStringList(AccueilFavoris.key), isNull, reason: 'rien enregistré');
      expect(find.byKey(const ValueKey('favori_stock')), findsNothing);
    });

    testWidgets('présentation B : appui long sur une ligne de menu → favoris', (tester) async {
      await pumpAccueil(tester, style: ListPresentation.compact, favoris: const []);
      await tester.longPress(find.text('Vente Carnet'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('favori_basculer')));
      await tester.pumpAndSettle();
      expect(await favorisEnregistres(), ['carnet']);
    });

    testWidgets('aucun favori : aide « appui long » affichée', (tester) async {
      await pumpAccueil(tester, favoris: const []);
      expect(find.byKey(const Key('favoris_aide')), findsOneWidget);
    });

    testWidgets('barre du bas : charte bleu nuit / ambre (plus le lavande Material par défaut)', (tester) async {
      await pumpAccueil(tester);
      final ctx = tester.element(find.byKey(const Key('accueil_barre_bas')));
      final t = NavigationBarTheme.of(ctx);
      expect(t.backgroundColor, Pal.navy);
      expect(t.indicatorColor, Pal.amber);
      final fond = tester.widget<Material>(find.descendant(of: find.byKey(const Key('accueil_barre_bas')), matching: find.byType(Material)).first);
      expect(fond.color, Pal.navy);
      // Libellés lisibles sur le fond bleu nuit.
      final style = t.labelTextStyle!.resolve({WidgetState.selected});
      expect(style!.color, Colors.white);
      // Menu ⋮ et dialogues : fond blanc (pas de teinte lavande).
      expect(Theme.of(ctx).popupMenuTheme.color, Colors.white);
      expect(Theme.of(ctx).dialogTheme.backgroundColor, Colors.white);
    });

    testWidgets('« Borne / vente discrète » : visible pour l\'administrateur (Ventes), absent sinon, rien activé', (tester) async {
      await pumpAccueil(tester, login: 'caissier');
      expect(find.byKey(const ValueKey('tuile_borne_admin')), findsNothing);

      await pumpAccueil(tester, login: 'admin');
      expect(find.byKey(const ValueKey('tuile_borne_admin')), findsOneWidget);
      expect(find.text('Borne'), findsOneWidget);
      final actifAvant = BorneReglages.courant.value.actif;
      await tester.tap(find.byKey(const ValueKey('tuile_borne_admin')));
      await tester.pumpAndSettle();
      expect(find.byType(BornePage), findsOneWidget);
      expect(BorneReglages.courant.value.actif, actifAvant, reason: 'l\'entrée ouvre la configuration sans rien activer');
      expect(actifAvant, isFalse);
      // Pas de favori sur cette entrée réservée.
      expect(accueilMenuById.containsKey(menuBorneAdmin.id), isFalse);
    });

    testWidgets('présentation B : entrée Borne pour l\'administrateur', (tester) async {
      await pumpAccueil(tester, login: 'admin', style: ListPresentation.compact);
      expect(find.text('Borne / vente discrète'), findsOneWidget);
    });
  });

  // =======================================================================================================
  group('4. Réglages : en-tête bleu nuit', () {
    testWidgets('en-tête NavyHeader (plus l\'en-tête blanc), même contenu', (tester) async {
      phone(tester);
      final a = _FakeApi();
      final auth = AuthProvider(a);
      await auth.login('admin', 'x');
      final settings = SettingsProvider();
      await settings.loadSettings();
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          Provider<ApiService>.value(value: a),
          ChangeNotifierProvider<LicenceProvider>.value(value: LicenceProvider(a)),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<SaleProvider>.value(value: SaleProvider(a)),
        ],
        child: MaterialApp(home: ParametresScreen(services: ParametresServices(pointageRepository: MemoryPointageRepository()))),
      ));
      await tester.pumpAndSettle();
      final entete = tester.widget<NavyHeader>(find.byKey(const Key('reglages_entete')));
      expect(entete.title, 'Réglages');
      expect(entete.subtitle, 'Awa Kouassi');
      expect(find.byType(AppBar), findsNothing);
      expect(tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor, Pal.page);
      // Rubriques inchangées (Borne libre-service et Images des produits plus bas dans la liste).
      expect(find.byKey(const Key('rubrique_connexion')), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const Key('rubrique_borne')), 200, scrollable: find.ancestor(of: find.byKey(const Key('rubrique_connexion')), matching: find.byType(Scrollable)).first);
      expect(find.byKey(const Key('rubrique_borne')), findsOneWidget);
      expect(find.text('Désactivée · libre-service client'), findsOneWidget);
    });
  });

  // =======================================================================================================
  group('5. « Ajouter une photo » pour l\'administrateur', () {
    late ImagesConfig avant;
    setUp(() => avant = ImagesReglages.courant.value);
    tearDown(() => ImagesReglages.courant.value = avant);

    Future<void> bouton(WidgetTester tester, {required bool admin, ProduitImages? images}) => tester.pumpWidget(MaterialApp(
          home: Scaffold(body: PhotoProduitBouton(familleId: 'f1', admin: admin, images: images ?? ProduitImages())),
        ));

    testWidgets('administrateur : visible directement (réglage photoTerminal désactivé)', (tester) async {
      ImagesReglages.courant.value = const ImagesConfig(); // photoTerminal false, photoAdmin true (défauts)
      expect(ImagesReglages.courant.value.photoTerminal, isFalse);
      expect(ImagesReglages.courant.value.photoAdmin, isTrue);
      await bouton(tester, admin: true);
      expect(find.byKey(const ValueKey('photo-produit-admin')), findsOneWidget);
      expect(find.text('Ajouter une photo'), findsOneWidget);
    });

    testWidgets('autre compte : absent (comportement inchangé)', (tester) async {
      ImagesReglages.courant.value = const ImagesConfig();
      await bouton(tester, admin: false);
      expect(find.text('Ajouter une photo'), findsNothing);
      expect(find.byKey(const ValueKey('photo-produit')), findsNothing);
    });

    testWidgets('administrateur : masqué par le réglage, ou hors ligne', (tester) async {
      ImagesReglages.courant.value = const ImagesConfig(photoAdmin: false);
      await bouton(tester, admin: true);
      expect(find.text('Ajouter une photo'), findsNothing);
      ImagesReglages.courant.value = const ImagesConfig();
      await bouton(tester, admin: true, images: ProduitImages()..horsLigne = () => true);
      expect(find.text('Ajouter une photo'), findsNothing);
    });

    test('réglage photoAdmin : activé par défaut, aussi pour des réglages enregistrés avant cette version', () {
      expect(ImagesConfig.fromJson({'actif': true, 'photoTerminal': false}).photoAdmin, isTrue);
      expect(ImagesConfig.fromJson(const ImagesConfig(photoAdmin: false).toJson()).photoAdmin, isFalse);
    });

    test('envoi : accepté pour l\'administrateur sans le réglage photoTerminal, refusé sinon', () async {
      ImagesReglages.courant.value = const ImagesConfig();
      final api = _ImagesApi();
      final s = ProduitImages(api: api);
      final r = await s.ajouterPhoto('f1', Uint8List.fromList([1, 2, 3]), admin: true);
      expect(r.isOk, isTrue);
      expect(api.ajouts, 1);
      final r2 = await s.ajouterPhoto('f1', Uint8List.fromList([1, 2, 3]));
      expect(r2.isOk, isFalse);
      expect(r2.message, 'Ajout de photo désactivé (Réglages).');
      expect(api.ajouts, 1);
    });

    test('serveur sans images (404) : message clair au lieu de « pas le droit »', () async {
      ImagesReglages.courant.value = const ImagesConfig();
      final s = ProduitImages(api: _ImagesApi()..sansImages = true);
      final r = await s.ajouterPhoto('f1', Uint8List.fromList([1]), admin: true);
      expect(r.message, 'Ce serveur ne gère pas les images des produits.');
      expect(s.capacite, CapaciteImages.non);
    });

    test('ProductInfo : stock en texte ou décimal lu sans échec', () {
      final i = ProductInfo.fromJson({'stock': '12', 'prixVente': '1 475', 'moyenne': 2});
      expect(i.stock, 12);
      expect(i.moyenne, 2.0);
    });
  });
}

class _ImagesApi implements ProduitImagesApi {
  int ajouts = 0;
  bool sansImages = false;

  @override
  Future<VenteResult<ImagesListe?>> lister(String familleId) async => sansImages ? const VenteOk(null) : const VenteOk(ImagesListe([], modifiable: true));

  @override
  Future<VenteResult<Uint8List>> fichier(String familleId, String imageId, {bool vignette = true}) async => const VenteFailed('non');

  @override
  Future<VenteResult<String>> ajouter(String familleId, Uint8List octets, {String nom = 'photo.jpg', bool principale = true}) async {
    ajouts++;
    return const VenteOk('img1');
  }

}
