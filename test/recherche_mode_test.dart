// Recherche « Commence par » / « Contient » : texte envoyé au serveur (produits, clients, tiers payants),
// codes scannés inchangés dans les deux modes, réglage mémorisé, puce de bascule, 360 px.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/accueil/recherche_globale_screen.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/client_assurance.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/tiers_payant_assurance.dart';
import 'package:prestige_vente_app/parametres/parametres_logic.dart';
import 'package:prestige_vente_app/parametres/rubriques_pages.dart';
import 'package:prestige_vente_app/services/product_finder.dart';
import 'package:prestige_vente_app/services/search_mode.dart';
import 'package:prestige_vente_app/ventes/assurance/assurance_controller.dart';
import 'package:prestige_vente_app/ventes/carnet/carnet_controller.dart';
import 'package:prestige_vente_app/ventes/common/vente_product_search.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProductSearchResult _p(String id, String name, String cip) =>
    ProductSearchResult(lgFAMILLEID: id, strNAME: name, intCIP: cip, intPRICE: 1000, intNUMBERAVAILABLE: 5, strLIBELLEE: '', intPAF: 800);

final _catalog = [
  _p('d1', 'DOLIPRANE 1000MG CP B/8', '3400935955838'),
  _p('d2', 'DOLIPRANE 500MG CP B/16', '3400935955839'),
  _p('e1', 'EFFERALGAN 1000MG CP B/8', '3595548'),
  _p('p1', 'PARACETAMOL DOLI 1000', '3595549'),
];

/// Faux serveur : LIKE 'texte%' avec les jokers % et _ (comme le vrai serveur).
List<ProductSearchResult> _like(String query) {
  final re = RegExp('^${RegExp.escape(query.toUpperCase()).replaceAll('%', '.*').replaceAll('_', '.')}');
  return _catalog.where((p) => re.hasMatch(p.strNAME) || re.hasMatch(p.intCIP)).toList();
}

class _Api extends ApiService {
  _Api() : super(baseUrl: 'http://localhost');
  final sent = <String>[];

  @override
  Future<ProductPage> searchProductsPageOrFail(String query, int start, int limit) async {
    sent.add(query);
    final all = _like(query);
    return ProductPage(all.skip(start).take(limit).toList(), all.length);
  }
}

/// Faux VenteGateway : seules les recherches servent ici.
class _Gw implements VenteGateway {
  final sent = <String>[];

  @override
  Future<VenteResult<ProductPage>> searchProductsPage(String query, int start, int limit) async {
    sent.add('produit:$query');
    final all = _like(query);
    return VenteOk(ProductPage(all.skip(start).take(limit).toList(), all.length));
  }

  @override
  Future<VenteResult<List<ClientAssurance>>> searchClients(String query, {required String typeClientId}) async {
    sent.add('client:$query');
    return const VenteOk([]);
  }

  @override
  Future<VenteResult<List<TiersPayantAssurance>>> searchTiersPayants(String query, {required bool carnet}) async {
    sent.add('tp${carnet ? '-carnet' : ''}:$query');
    return const VenteOk([]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SearchModePrefs.mode.value = SearchMode.commencePar;
  });
  tearDown(() => SearchModePrefs.mode.value = SearchMode.commencePar);

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(720, 1400); // 360 x 700
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  group('serverQuery', () {
    test('« Commence par » : texte inchangé sans joker', () {
      expect(serverQuery('DOLIPRANE 1000', SearchMode.commencePar), 'DOLIPRANE 1000');
      expect(serverQuery('  doli  ', SearchMode.commencePar), 'doli');
      expect(serverQuery('', SearchMode.commencePar), '');
    });

    test('« Commence par » : jokers tapés neutralisés (coupé au 1ᵉʳ joker)', () {
      expect(serverQuery('BETADINE 10%', SearchMode.commencePar), 'BETADINE 10');
      expect(serverQuery('DOLI%1000', SearchMode.commencePar), 'DOLI');
      expect(serverQuery('%1000MG', SearchMode.commencePar), '1000MG');
      expect(serverQuery('A_B', SearchMode.commencePar), 'A');
      expect(serverQuery('%%_', SearchMode.commencePar), '');
      expect(serverQuery('doli % 1000', SearchMode.commencePar), 'doli');
    });

    test('« Contient » : % devant et entre les mots, jokers tapés = espaces', () {
      expect(serverQuery('doli 1000', SearchMode.contient), '%doli%1000');
      expect(serverQuery('  1000MG ', SearchMode.contient), '%1000MG');
      expect(serverQuery('doli   1000  cp', SearchMode.contient), '%doli%1000%cp');
      expect(serverQuery('BETADINE 10%', SearchMode.contient), '%BETADINE%10');
      expect(serverQuery('A_B', SearchMode.contient), '%A%B');
      expect(serverQuery('%%', SearchMode.contient), '');
      expect(serverQuery('', SearchMode.contient), '');
    });

    test('« Contient » à partir de 3 caractères, sinon « commence par »', () {
      expect(modeFor('do', SearchMode.contient), SearchMode.commencePar);
      expect(modeFor('dol', SearchMode.contient), SearchMode.contient);
      expect(modeFor('dol', SearchMode.commencePar), SearchMode.commencePar);
    });
  });

  group('réglage', () {
    test('défaut « Commence par », bascule mémorisée (clé recherche_mode_v1)', () async {
      expect(await SearchModePrefs.load(), SearchMode.commencePar);
      await SearchModePrefs.toggle();
      expect(SearchModePrefs.current, SearchMode.contient);
      expect((await SharedPreferences.getInstance()).getString('recherche_mode_v1'), 'contient');
      SearchModePrefs.mode.value = SearchMode.commencePar;
      expect(await SearchModePrefs.load(), SearchMode.contient);
    });

    test('résumé de la rubrique Apparence', () {
      expect(ParametresSummary.apparence(ListPresentation.guided), 'Présentation C · organiser l\'accueil');
      expect(ParametresSummary.apparence(ListPresentation.guided, search: SearchMode.contient),
          'Présentation C · organiser l\'accueil · recherche « contient »');
      expect(rubriqueMatches(Rubrique.apparence, '', 'contient'), isTrue);
    });

    testWidgets('Apparence : choix « Contient » enregistré, explication, 360 px', (tester) async {
      phone(tester);
      await tester.pumpWidget(MaterialApp(home: ApparencePage(initial: ListPresentation.dashboard, openOrganiser: (_) async {})));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const Key('recherche_mode')), 120, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(find.textContaining('« 1000 » ne le trouve pas'), findsOneWidget);
      await tester.tap(find.descendant(of: find.byKey(const Key('recherche_mode')), matching: find.text('Contient')));
      await tester.pumpAndSettle();
      expect(SearchModePrefs.current, SearchMode.contient);
      expect((await SharedPreferences.getInstance()).getString(SearchModePrefs.key), 'contient');
      expect(find.textContaining('« doli 1000 » trouve « DOLIPRANE 1000MG »'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('produits', () {
    test('ProductPager : texte selon le mode, sans mode = texte brut (ordonnance)', () async {
      final sent = <String>[];
      Future<VenteResult<ProductPage>> search(String q, int s, int l) async {
        sent.add(q);
        final all = _like(q);
        return VenteOk(ProductPage(all, all.length));
      }

      final a = ProductPager(search, 'doli 1000', mode: SearchMode.contient);
      await a.loadMore();
      expect(a.items.map((p) => p.lgFAMILLEID), ['d1', 'p1']);
      final b = ProductPager(search, 'doli 1000', mode: SearchMode.commencePar);
      await b.loadMore();
      expect(b.items, isEmpty);
      SearchModePrefs.mode.value = SearchMode.contient;
      final raw = ProductPager(search, 'BETADINE 10%');
      await raw.loadMore();
      final jokers = ProductPager(search, '%%%', mode: SearchMode.contient);
      expect(await jokers.loadMore(), isTrue);
      expect(sent, ['%doli%1000', 'doli 1000', 'BETADINE 10%']);
    });

    test('menus (PagedProductSearch) : texte selon le mode, codes inchangés', () async {
      final api = _Api();
      final s = PagedProductSearch(() => api);
      await s.run('doli 1000');
      expect(s.items, isEmpty);
      SearchModePrefs.mode.value = SearchMode.contient;
      await s.run('doli 1000');
      expect(s.items.map((p) => p.lgFAMILLEID), ['d1', 'p1']);
      await s.run('do'); // < 3 caractères : « commence par »
      await s.run('3595548');
      expect(s.items.single.lgFAMILLEID, 'e1');
      await s.run('3400935955838', asCode: true);
      expect(s.items.single.lgFAMILLEID, 'd1');
      expect(api.sent, ['doli 1000', '%doli%1000', 'do', '3595548', '3400935955838']);
    });

    test('codes : ProductLookup identique dans les deux modes', () async {
      final calls = <SearchMode, List<String>>{};
      for (final m in SearchMode.values) {
        SearchModePrefs.mode.value = m;
        final gw = _Gw();
        final r = await ProductLookup.byCode('3400935955838', gw.searchProductsPage);
        expect(r.valueOrNull?.exact?.lgFAMILLEID, 'd1');
        calls[m] = gw.sent;
      }
      expect(calls[SearchMode.contient], calls[SearchMode.commencePar]);
      expect(calls[SearchMode.contient]!.first, 'produit:3400935955838');
    });
  });

  group('clients et tiers payants', () {
    test('assurance : client et TP selon le mode', () async {
      final gw = _Gw();
      final c = AssuranceController(gateway: gw, userId: 'U1');
      await c.searchClients('kouassi awa');
      await c.searchTiersPayants('mugef');
      SearchModePrefs.mode.value = SearchMode.contient;
      await c.searchClients('kouassi awa');
      await c.searchTiersPayants('mugef ci');
      await c.searchClients('ko'); // < 3 caractères : « commence par »
      await c.searchClients('%%%'); // que des jokers : rien n'est envoyé
      expect(gw.sent, ['client:kouassi awa', 'tp:mugef', 'client:%kouassi%awa', 'tp:%mugef%ci', 'client:ko']);
      c.dispose();
    });

    test('carnet : client et carnet selon le mode', () async {
      final gw = _Gw();
      final c = CarnetController(gateway: gw, userId: 'U1');
      await c.searchClients('yao');
      await c.searchCarnets('carnet');
      SearchModePrefs.mode.value = SearchMode.contient;
      await c.searchClients('yao k');
      await c.searchCarnets('net 2');
      await c.searchClients('ya_'); // jokers neutralisés
      expect(gw.sent, ['client:yao', 'tp-carnet:carnet', 'client:%yao%k', 'tp-carnet:%net%2', 'client:%ya']);
      c.dispose();
    });
  });

  group('puce de bascule', () {
    Future<_Gw> pumpVente(WidgetTester tester, {bool onDark = false}) async {
      phone(tester);
      final gw = _Gw();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: Pal.navy,
          body: Column(children: [
            VenteProductSearch(
              search: (q) async => const VenteOk([]),
              pageSearch: gw.searchProductsPage,
              addProduct: (p, q) async => true,
              debounce: const Duration(milliseconds: 10),
              onDark: onDark,
            ),
          ]),
        ),
      ));
      await tester.pumpAndSettle();
      return gw;
    }

    for (final dark in [false, true]) {
      testWidgets('ventes${dark ? ' (en-tête bleu)' : ''} : bascule, relance, aide adaptée, codes inchangés, 360 px', (tester) async {
        final gw = await pumpVente(tester, onDark: dark);
        final chip = find.byKey(const ValueKey('recherche-mode'));
        expect(find.descendant(of: chip, matching: find.text('Début')), findsOneWidget);
        expect(find.byTooltip('Recherche : commence par le texte tapé. Toucher pour « Contient ».'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'zz 9');
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();
        expect(find.text('Aucun produit dont le nom ou le code commence par « zz 9 ».'), findsOneWidget);

        await tester.tap(chip);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();
        expect(SearchModePrefs.current, SearchMode.contient);
        expect((await SharedPreferences.getInstance()).getString(SearchModePrefs.key), 'contient');
        expect(find.descendant(of: chip, matching: find.text('Contient')), findsOneWidget);
        expect(find.text('Aucun produit dont le nom ou le code contient « zz 9 ».'), findsOneWidget);

        // Code tapé : recherche exacte, sans joker.
        await tester.enterText(find.byType(TextField), '3595548');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        expect(gw.sent, ['produit:zz 9', 'produit:%zz%9', 'produit:3595548']);
        expect(find.textContaining('EFFERALGAN'), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('recherche globale : bascule et relance la recherche produit, 360 px', (tester) async {
      phone(tester);
      final api = _Api();
      await tester.pumpWidget(MaterialApp(home: RechercheGlobaleScreen(menus: const [], onOpenMenu: (_) {}, api: () => api)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'doli 1000');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('Aucun produit trouvé.'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('recherche-mode')));
      await tester.pumpAndSettle();
      expect(SearchModePrefs.current, SearchMode.contient);
      expect(find.text('DOLIPRANE 1000MG CP B/8'), findsOneWidget);
      expect(find.text('PARACETAMOL DOLI 1000'), findsOneWidget);
      expect(api.sent, ['doli 1000', '%doli%1000']);
      expect(tester.takeException(), isNull);
    });
  });
}
