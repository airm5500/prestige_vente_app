// Nouvel accueil : présentations A / B / C à 360 px, tâches, pastille serveur, recherche / scan
// global, favoris, menus masqués, protection par code, organiser l'accueil, contrôle de licence.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestige_vente_app/accueil/accueil_menus.dart';
import 'package:prestige_vente_app/accueil/accueil_screen.dart';
import 'package:prestige_vente_app/accueil/fiche_produit_screen.dart';
import 'package:prestige_vente_app/accueil/organiser_accueil_screen.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/bon_livraison.dart';
import 'package:prestige_vente_app/api/models/licence_model.dart';
import 'package:prestige_vente_app/api/models/officine.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/product_info.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/bl_control_provider.dart';
import 'package:prestige_vente_app/providers/licence_provider.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/screens/auth/licence_registration_screen.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(baseUrl: 'http://localhost');
  bool blFail = false;
  int searches = 0;

  @override
  Future<Officine?> fetchOfficineInfo() async => Officine(fullName: 'KONAN KOU', nomComplet: 'PHARMACIE LES PALMIERS');

  @override
  Future<List<PreventeListItem>> getPreventes() async => [
        for (var i = 0; i < 3; i++)
          PreventeListItem(
              lgPREENREGISTREMENTID: 'p$i', heure: '09:1$i:00', dtUPDATED: '10/10/2026', intPRICE: 1000, strREF: 'PV-$i', userFullName: 'Koffi', lgTYPEVENTEID: '1'),
      ];

  @override
  Future<List<BonLivraison>> getBonsLivraison({String query = '', String? dtStart, String? dtEnd}) async {
    if (blFail) throw const ApiLoadException('Serveur injoignable');
    return [
      BonLivraison(id: 'b1', ref: 'BL1', grossiste: 'LABOREX', date: '', nbreLignes: 3, montantTotal: 0, statutTraitement: 'EN_COURS', strStatut: ''),
      BonLivraison(id: 'b2', ref: 'BL2', grossiste: 'COPHARMED', date: '', nbreLignes: 3, montantTotal: 0, statutTraitement: 'A_FAIRE', strStatut: ''),
      BonLivraison(id: 'b3', ref: 'BL3', grossiste: 'DPCI', date: '', nbreLignes: 3, montantTotal: 0, statutTraitement: 'TERMINE', strStatut: ''),
    ];
  }

  @override
  Future<ProductPage> searchProductsPageOrFail(String query, int start, int limit) async {
    searches++;
    final p = ProductSearchResult(
        lgFAMILLEID: 'f1', strNAME: 'STOCKOVIT CP B/30', intCIP: '3400120', intPRICE: 4500, intNUMBERAVAILABLE: 12, strLIBELLEE: '', intPAF: 0);
    if (query == '3400120' || query.toLowerCase().contains('stock')) return ProductPage([p], 1);
    return const ProductPage([], 0);
  }

  @override
  Future<ProductInfo?> getProductInfo(String codeCip) async => ProductInfo(
      codeCip: codeCip, emplacement: 'RAYON B2', grossiste: 'LABOREX', libelle: 'STOCKOVIT CP B/30', moyenne: 0, prixAchat: 3000, prixVente: 4500, produitId: 'f1', stock: 12);
}

class _FakeLicence extends LicenceProvider {
  _FakeLicence(super.api, {this.block = false, this.days = 21});
  final bool block;
  final int days;
  int checks = 0;

  @override
  LicenceStatus get status => LicenceStatus.valid;
  @override
  LicenceModel? get licence => LicenceModel(id: '1', dateStart: '', dateEnd: '', typeLicence: '');
  @override
  int get remainingDays => days;
  @override
  Future<bool> mustBlockAccess() async {
    checks++;
    return block;
  }

  @override
  void checkReminders(BuildContext context) {}
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(720, 1400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  Future<(_FakeApi, _FakeLicence, SettingsProvider)> pump(
    WidgetTester tester, {
    ListPresentation style = ListPresentation.dashboard,
    bool serveur = true,
    bool block = false,
    int days = 21,
    _FakeApi? api,
    Future<String?> Function(BuildContext)? scanner,
    Future<bool> Function(BuildContext)? askPin,
    List<String> hidden = const [],
  }) async {
    final a = api ?? _FakeApi();
    final licence = _FakeLicence(a, block: block, days: days);
    final settings = SettingsProvider();
    await settings.saveMenuConfig(const [], hidden);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        Provider<ApiService>.value(value: a),
        ChangeNotifierProvider<LicenceProvider>.value(value: licence),
        ChangeNotifierProvider(create: (_) => AuthProvider(a)),
        ChangeNotifierProvider(create: (_) => SaleProvider(a)),
        ChangeNotifierProvider(create: (_) => BlControlProvider(a)),
      ],
      child: MaterialApp(
        home: AccueilScreen(
          presentation: style,
          serverCheck: () async => serveur,
          scanner: scanner,
          askPin: askPin,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return (a, licence, settings);
  }

  Future<void> scrollTo(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
  }

  for (final style in ListPresentation.values) {
    testWidgets('Accueil ${style.label} : 360 px sans débordement, barre du bas, pastille serveur', (tester) async {
      phone(tester);
      await pump(tester, style: style);
      expect(tester.takeException(), isNull);
      for (final l in ['Accueil', 'Scanner', 'Tâches', 'Réglages']) {
        expect(find.text(l), findsWidgets);
      }
      expect(find.textContaining(RegExp('Serveur connecté|En ligne')), findsOneWidget);
      expect(find.text('Licence : 21 jour(s)'), findsOneWidget);
      if (style == ListPresentation.guided) {
        expect(find.text('Vendre'), findsOneWidget);
        expect(find.text('3 prévente(s) en attente'), findsOneWidget);
        await scrollTo(tester, find.text('Voir tous les menus'));
        await tester.tap(find.text('Voir tous les menus'));
        await tester.pumpAndSettle();
        await scrollTo(tester, find.text('Pointage'));
      } else {
        expect(find.textContaining('prévente(s) à encaisser'), findsWidgets);
        await scrollTo(tester, find.text('Pointage'));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('A : tâches, favoris par défaut, familles, cadenas, menus masqués exclus', (tester) async {
    phone(tester);
    await pump(tester, hidden: const ['depot']);
    expect(find.text('À FAIRE MAINTENANT'), findsOneWidget);
    expect(find.text('prévente(s) à encaisser'), findsOneWidget); // 3 en grand à gauche
    expect(find.text('BL à pointer'), findsOneWidget); // 2 non terminés
    expect(find.text('FAVORIS'), findsOneWidget);
    for (final f in ['VENTES', 'CAISSE', 'RÉCEPTION & FOURNISSEURS', 'STOCK', 'PRODUITS', 'ÉQUIPE']) {
      await scrollTo(tester, find.text(f));
    }
    expect(find.text('Dépôt'), findsNothing);
    expect(find.byIcon(Icons.lock), findsWidgets); // Ajustement
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Hors ligne : pastille rouge, Réessayer, préventes « non vérifiées » (pas 0)', (tester) async {
    phone(tester);
    final api = _FakeApi()..blFail = true;
    await pump(tester, serveur: false, api: api);
    expect(find.text('Hors ligne'), findsOneWidget);
    expect(find.text('Réessayer'), findsWidgets);
    expect(find.textContaining('serveur injoignable'), findsOneWidget);
    expect(find.textContaining('BL non chargés'), findsOneWidget);
    expect(find.text('Tout est à jour ✓'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Licence > 30 jours : non affichée', (tester) async {
    phone(tester);
    await pump(tester, days: 200);
    expect(find.textContaining('Licence'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Onglet Tâches : cartes et retour à l\'accueil', (tester) async {
    phone(tester);
    await pump(tester);
    await tester.tap(find.text('Tâches').last);
    await tester.pumpAndSettle();
    expect(find.text('3 prévente(s) à encaisser'), findsOneWidget);
    expect(find.text('Encaisser'), findsOneWidget);
    expect(find.text('2 BL à pointer'), findsOneWidget);
    expect(find.textContaining('Actualisé à'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Accueil').last);
    await tester.pumpAndSettle();
    expect(find.text('À FAIRE MAINTENANT'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Recherche : « stock » propose des menus et des produits', (tester) async {
    phone(tester);
    await pump(tester);
    await tester.tap(find.text('Rechercher un menu ou un produit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'stock');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('MENUS'), findsOneWidget);
    expect(find.text('État de Stock'), findsOneWidget);
    expect(find.text('Ajustement Stock'), findsOneWidget);
    expect(find.text('PRODUITS'), findsOneWidget);
    expect(find.text('STOCKOVIT CP B/30'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('STOCKOVIT CP B/30'));
    await tester.pumpAndSettle();
    expect(find.byType(FicheProduitScreen), findsOneWidget);
    expect(find.text('RAYON B2'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Scanner (barre du bas) : un code connu ouvre la fiche produit', (tester) async {
    phone(tester);
    await pump(tester, scanner: (_) async => '3400120');
    await tester.tap(find.text('Scanner').last);
    await tester.pumpAndSettle();
    expect(find.byType(FicheProduitScreen), findsOneWidget);
    expect(find.text('STOCKOVIT CP B/30'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Ajustement : code administrateur exigé (refus = menu non ouvert)', (tester) async {
    phone(tester);
    var asked = 0;
    await pump(tester, askPin: (_) async {
      asked++;
      return false;
    });
    await scrollTo(tester, find.text('Ajustement'));
    await tester.tap(find.text('Ajustement'));
    await tester.pumpAndSettle();
    expect(asked, 1);
    expect(find.text('Ajustement'), findsOneWidget); // toujours sur l'accueil
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Retour au premier plan : licence expirée → écran de licence (comme l\'original)', (tester) async {
    phone(tester);
    final (_, licence, _) = await pump(tester, block: true);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(licence.checks, greaterThan(0));
    expect(find.byType(LicenceRegistrationScreen), findsOneWidget);
    expect(find.byType(AccueilScreen), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Licence valide au retour : l\'accueil reste affiché', (tester) async {
    phone(tester);
    final (_, licence, _) = await pump(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(licence.checks, 1);
    expect(find.byType(AccueilScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Déconnexion de secours (⋮) avec confirmation', (tester) async {
    phone(tester);
    await pump(tester);
    await tester.tap(find.byTooltip('Plus d\'actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Se déconnecter'));
    await tester.pumpAndSettle();
    expect(find.text('Se déconnecter ?'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(find.byType(AccueilScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  group('Organiser l\'accueil', () {
    Future<SettingsProvider> pumpOrg(WidgetTester tester, {bool pin = true, List<String> order = const [], List<String> hidden = const []}) async {
      final settings = SettingsProvider();
      await settings.saveMenuConfig(order, hidden);
      await tester.pumpWidget(ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => OrganiserAccueilScreen(askPin: (_) async => pin))),
                  child: const Text('ouvrir'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      return settings;
    }

    testWidgets('code refusé : écran refermé, rien de visible', (tester) async {
      phone(tester);
      await pumpOrg(tester, pin: false);
      expect(find.byType(OrganiserAccueilScreen), findsNothing);
      expect(find.text('ouvrir'), findsOneWidget);
    });

    testWidgets('reprend l\'organisation actuelle ; favoris 4 max ; masquer ; enregistrer', (tester) async {
      phone(tester);
      final settings = await pumpOrg(tester, order: const ['carnet', 'prevente'], hidden: const ['depot']);
      expect(tester.takeException(), isNull);
      expect(find.text('FAVORIS (4/4)'), findsOneWidget);
      expect(find.text('Vente Dépôt (masqué)'), findsOneWidget);
      // 5e favori refusé
      await tester.tap(find.byTooltip('Mettre en favori').first);
      await tester.pump();
      expect(find.text('4 favoris au maximum : retirez d\'abord une étoile.'), findsOneWidget);
      // retirer Pré-vente des favoris, puis afficher Dépôt
      await tester.tap(find.byTooltip('Retirer des favoris').first);
      await tester.pumpAndSettle();
      expect(find.text('FAVORIS (3/4)'), findsOneWidget);
      await tester.tap(find.byTooltip('Afficher').first);
      await tester.pumpAndSettle();
      expect(find.text('Vente Dépôt'), findsOneWidget);
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(find.byType(OrganiserAccueilScreen), findsNothing);
      expect(settings.hiddenMenuIds, isEmpty);
      // ordre enregistré : carnet avant prevente dans Ventes (organisation reprise), 22 menus
      expect(settings.menuOrder.length, accueilMenus.length);
      expect(settings.menuOrder.indexOf('carnet'), lessThan(settings.menuOrder.indexOf('prevente')));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(AccueilFavoris.key), ['assurance', 'search', 'reception_bl']);
      expect(prefs.getStringList('menuOrder'), settings.menuOrder);
    });

    testWidgets('Par défaut puis Enregistrer : ordre et favoris par défaut', (tester) async {
      phone(tester);
      final settings = await pumpOrg(tester, order: const ['carnet', 'prevente'], hidden: const ['depot', 'search']);
      await tester.tap(find.text('Par défaut'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(settings.hiddenMenuIds, isEmpty);
      expect(settings.menuOrder, accueilMenus.map((m) => m.id).toList());
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(AccueilFavoris.key), AccueilFavoris.parDefaut);
    });
  });

  group('Catalogue des menus', () {
    test('22 menus, mêmes identifiants que l\'accueil d\'origine, familles complètes', () {
      expect(accueilMenus.length, 22);
      expect(accueilMenuById.length, 22);
      const origine = [
        'prevente', 'assurance', 'carnet', 'caisse', 'perimes', 'evaluation', 'search', 'update_perim', 'delivery', 'bl_control', 'reception',
        'update_ean', 'update_emplacement', 'stock', 'depot', 'proforma', 'analyse_article', 'ajustement', 'ordonnance', 'reception_bl',
        'retour_frs', 'empreinte',
      ];
      expect(accueilMenuById.keys.toSet(), origine.toSet());
      expect(accueilMenus.where((m) => m.protege).map((m) => m.id), ['ajustement']);
    });

    test('ordre enregistré puis menus manquants ; recherche sans accents', () {
      final o = orderedMenus(const ['stock', 'inconnu', 'prevente']);
      expect(o.first.id, 'stock');
      expect(o[1].id, 'prevente');
      expect(o.length, 22);
      expect(chercherMenus('etat', accueilMenus).map((m) => m.id), contains('stock'));
      expect(chercherMenus('PÉREMPTION', accueilMenus).map((m) => m.id), contains('update_perim'));
      expect(chercherMenus('', accueilMenus), isEmpty);
    });

    test('favoris nettoyés : connus, sans doublon, 4 max', () {
      expect(AccueilFavoris.nettoyer(['x', 'carnet', 'carnet', 'stock', 'caisse', 'search', 'depot']), ['carnet', 'stock', 'caisse', 'search']);
    });
  });
}
