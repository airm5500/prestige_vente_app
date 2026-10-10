// Connexion au serveur sur le nouvel accueil : point vert clignotant / rouge, bouton
// « Se déconnecter » de l'en-tête, messages globaux de perte / retour de connexion,
// fiche produit et recherche globale hors ligne (copie locale en mémoire).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestige_vente_app/accueil/accueil_screen.dart' show AccueilScreen;
import 'package:prestige_vente_app/accueil/fiche_produit_screen.dart';
import 'package:prestige_vente_app/accueil/point_serveur.dart';
import 'package:prestige_vente_app/accueil/recherche_globale_screen.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/bon_livraison.dart';
import 'package:prestige_vente_app/api/models/licence_model.dart';
import 'package:prestige_vente_app/api/models/officine.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/product_info.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/horsligne/catalogue_sync.dart';
import 'package:prestige_vente_app/horsligne/connexion_toasts.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/horsligne_ui.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart';
import 'package:prestige_vente_app/horsligne/server_monitor.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/bl_control_provider.dart';
import 'package:prestige_vente_app/providers/licence_provider.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/screens/auth/login_screen.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart' show ProductPage;
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _vert = Color(0xFF22C55E);
const _rouge = Color(0xFFEF4444);

class _FakeApi extends ApiService {
  _FakeApi() : super(baseUrl: 'http://localhost');
  int searches = 0;
  int infos = 0;
  int logouts = 0;

  @override
  Future<void> logout() async => logouts++;

  @override
  Future<Officine?> fetchOfficineInfo() async => Officine(fullName: 'KONAN KOU', nomComplet: 'PHARMACIE LES PALMIERS');

  @override
  Future<List<PreventeListItem>> getPreventes() async => const [];

  @override
  Future<List<BonLivraison>> getBonsLivraison({String query = '', String? dtStart, String? dtEnd}) async => const [];

  @override
  Future<ProductPage> searchProductsPageOrFail(String query, int start, int limit) async {
    searches++;
    return const ProductPage([], 0);
  }

  @override
  Future<ProductInfo?> getProductInfo(String codeCip) async {
    infos++;
    return ProductInfo(
        codeCip: codeCip, emplacement: 'RAYON B2', grossiste: 'LABOREX', libelle: 'STOCKOVIT CP B/30', moyenne: 0, prixAchat: 3000, prixVente: 4500, produitId: 'f1', stock: 12);
  }
}

class _FakeLicence extends LicenceProvider {
  _FakeLicence(super.api);

  @override
  LicenceStatus get status => LicenceStatus.valid;
  @override
  LicenceModel? get licence => LicenceModel(id: '1', dateStart: '', dateEnd: '', typeLicence: '');
  @override
  int get remainingDays => 200;
  @override
  Future<bool> mustBlockAccess() async => false;
  @override
  void checkReminders(BuildContext context) {}
}

final _catalogueAt = DateTime(2026, 10, 9, 18, 45);

Map<String, dynamic> _row({int stock = 7}) => {
      'lgFAMILLEID': 'f1',
      'strNAME': 'STOCKOVIT CP B/30',
      'intCIP': '3400120',
      'intPRICE': 4500,
      'intNUMBERAVAILABLE': stock,
      'strLIBELLEE': 'VITAMINES',
      'intPAF': 0,
    };

/// Surveillance pilotable (ping réglable, 1 échec suffit) installée comme instance de l'appli.
class _Install {
  bool serveurRepond = true;
  late final HorsLigne hl;
  final store = MemoryLocalStore();

  _Install() {
    final monitor = ServerMonitor(ping: () async => serveurRepond, seuil: 1);
    hl = HorsLigne(monitor: monitor, store: store, sync: CatalogueSync(store: store));
    final previous = HorsLigne.instance;
    HorsLigne.instance = hl;
    addTearDown(() => HorsLigne.instance = previous);
  }

  ServerMonitor get monitor => hl.monitor;

  Future<void> perte() async {
    serveurRepond = false;
    await monitor.checkNow();
  }

  Future<void> retour() async {
    serveurRepond = true;
    await monitor.checkNow();
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(720, 1400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  Future<_FakeApi> pumpAccueil(WidgetTester tester,
      {ListPresentation style = ListPresentation.dashboard, bool serveur = true, bool settle = true, bool disableAnimations = false}) async {
    final a = _FakeApi();
    final settings = SettingsProvider();
    await settings.saveMenuConfig(const [], const []);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        Provider<ApiService>.value(value: a),
        ChangeNotifierProvider<LicenceProvider>.value(value: _FakeLicence(a)),
        ChangeNotifierProvider(create: (_) => AuthProvider(a)),
        ChangeNotifierProvider(create: (_) => SaleProvider(a)),
        ChangeNotifierProvider(create: (_) => BlControlProvider(a)),
      ],
      child: MaterialApp(
        builder: disableAnimations
            ? (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!)
            : null,
        home: AccueilScreen(presentation: style, serverCheck: () async => serveur),
      ),
    ));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
    return a;
  }

  PointServeur point(WidgetTester tester) => tester.widget<PointServeur>(find.byType(PointServeur).first);
  double opacite(WidgetTester tester) => tester.widget<FadeTransition>(find.byKey(const Key('point_serveur')).first).opacity.value;

  group('Point d\'état du serveur', () {
    tearDown(() => PointServeur.clignotementActif = false);

    testWidgets('Serveur connecté : point vert qui clignote (opacité animée)', (tester) async {
      phone(tester);
      _Install();
      PointServeur.clignotementActif = true;
      await pumpAccueil(tester, settle: false);
      expect(find.text('Serveur connecté'), findsOneWidget);
      expect(point(tester).couleur, _vert);
      expect(point(tester).clignote, isTrue);
      final o1 = opacite(tester);
      await tester.pump(const Duration(milliseconds: 500));
      final o2 = opacite(tester);
      expect(o1, isNot(closeTo(o2, 0.01)));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Moins d\'animations demandé : point vert fixe (pumpAndSettle aboutit)', (tester) async {
      phone(tester);
      _Install();
      PointServeur.clignotementActif = true;
      await pumpAccueil(tester, disableAnimations: true);
      expect(point(tester).couleur, _vert);
      expect(opacite(tester), 1.0);
      await tester.pumpWidget(const SizedBox());
    });

    for (final style in ListPresentation.values) {
      testWidgets('${style.label} : rouge fixe si injoignable ou hors ligne, vert au retour', (tester) async {
        phone(tester);
        final inst = _Install();
        await pumpAccueil(tester, style: style);
        expect(point(tester).couleur, _vert);

        await inst.perte();
        await tester.pumpAndSettle();
        expect(inst.monitor.etat, EtatServeur.injoignable);
        expect(point(tester).couleur, _rouge);
        expect(point(tester).clignote, isFalse);
        expect(find.textContaining('njoignable'), findsWidgets);
        expect(find.text('Réessayer'), findsOneWidget);

        inst.monitor.goOffline(manuel: false);
        await tester.pumpAndSettle();
        expect(point(tester).couleur, _rouge);
        expect(find.text('Hors ligne'), findsOneWidget);

        await inst.retour();
        await tester.pumpAndSettle();
        expect(inst.monitor.etat, EtatServeur.enLigne);
        expect(point(tester).couleur, _vert);
        expect(point(tester).clignote, isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('Vérification de l\'accueil en échec : rouge « Hors ligne »', (tester) async {
      phone(tester);
      _Install();
      await pumpAccueil(tester, serveur: false);
      expect(point(tester).couleur, _rouge);
      expect(point(tester).clignote, isFalse);
      expect(find.text('Hors ligne'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Bouton « Se déconnecter » de l\'en-tête', () {
    for (final style in ListPresentation.values) {
      testWidgets('${style.label} : visible à droite, 360 px sans débordement', (tester) async {
        phone(tester);
        _Install();
        await pumpAccueil(tester, style: style);
        final b = find.byKey(const Key('accueil_deconnexion'));
        expect(b, findsOneWidget);
        expect(find.byTooltip('Se déconnecter'), findsOneWidget);
        expect(tester.getTopRight(b).dx, greaterThan(300));
        expect(tester.getSize(b).height, greaterThanOrEqualTo(44));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('Annuler : on reste sur l\'accueil', (tester) async {
      phone(tester);
      _Install();
      final api = await pumpAccueil(tester);
      await tester.tap(find.byKey(const Key('accueil_deconnexion')));
      await tester.pumpAndSettle();
      expect(find.text('Se déconnecter ?'), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(api.logouts, 0);
      expect(find.byType(AccueilScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Confirmer : même déconnexion que le menu ⋮ (logout + écran de connexion)', (tester) async {
      phone(tester);
      _Install();
      final api = await pumpAccueil(tester);
      await tester.tap(find.byKey(const Key('accueil_deconnexion')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Se déconnecter'));
      await tester.pumpAndSettle();
      expect(api.logouts, 1);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(AccueilScreen), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('L\'entrée « Se déconnecter » du menu ⋮ reste', (tester) async {
      phone(tester);
      _Install();
      await pumpAccueil(tester);
      await tester.tap(find.byTooltip('Plus d\'actions'));
      await tester.pumpAndSettle();
      expect(find.text('Se déconnecter'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Messages de connexion', () {
    Future<void> pumpApp(WidgetTester tester, HorsLigne hl) async {
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => HorsLigneScope(
          horsLigne: hl,
          bindApp: false,
          bandeauRetour: false,
          child: ConnexionToasts(horsLigne: hl, child: child!),
        ),
        home: const Scaffold(body: Center(child: Text('écran'))),
      ));
      await tester.pumpAndSettle();
    }

    SnackBar snack(WidgetTester tester) => tester.widget<SnackBar>(find.byType(SnackBar));

    testWidgets('Rien au démarrage ; perte → rouge, retour → vert, sans doublon du bandeau', (tester) async {
      phone(tester);
      final inst = _Install();
      await pumpApp(tester, inst.hl);
      expect(find.byType(SnackBar), findsNothing);

      await inst.perte();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));
      expect(find.text(ConnexionToasts.perteTexte), findsOneWidget);
      expect(snack(tester).backgroundColor, const Color(0xFFB91C1C));
      expect(find.byKey(const Key('bandeau_injoignable')), findsOneWidget);

      await inst.retour();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));
      await tester.pump(const Duration(milliseconds: 750));
      expect(find.text(ConnexionToasts.retourTexte), findsOneWidget);
      expect(find.text(ConnexionToasts.perteTexte), findsNothing);
      expect(snack(tester).backgroundColor, const Color(0xFF15803D));
      expect(find.byKey(const Key('bandeau_retour')), findsNothing);
      expect(find.text('Serveur de nouveau joignable'), findsNothing);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Hors ligne confirmé puis retour : un seul message de perte, puis « De nouveau en ligne »', (tester) async {
      phone(tester);
      final inst = _Install();
      await pumpApp(tester, inst.hl);
      await inst.perte();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('continuer_hors_ligne')));
      await tester.pump();
      expect(inst.monitor.isOffline, isTrue);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);

      await inst.retour();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));
      expect(find.text(ConnexionToasts.retourTexte), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('Hors ligne choisi par l\'utilisateur : pas de message de perte', (tester) async {
      phone(tester);
      final inst = _Install();
      await pumpApp(tester, inst.hl);
      inst.monitor.goOffline();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));
      expect(find.byType(SnackBar), findsNothing);
      inst.monitor.goOnline();
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('Le bandeau de retour reste disponible par défaut (HorsLigneScope inchangé)', (tester) async {
      phone(tester);
      final inst = _Install();
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => HorsLigneScope(horsLigne: inst.hl, bindApp: false, child: child!),
        home: const Scaffold(body: Text('écran')),
      ));
      await inst.perte();
      await tester.pump();
      await inst.retour();
      await tester.pump();
      expect(find.byKey(const Key('bandeau_retour')), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  });

  group('Fiche produit et recherche hors ligne', () {
    final produitRecu = ProductSearchResult(
        lgFAMILLEID: 'f1', strNAME: 'STOCKOVIT CP B/30', intCIP: '3400120', intPRICE: 4500, intNUMBERAVAILABLE: 12, strLIBELLEE: '', intPAF: 0);

    Future<_Install> horsLigne() async {
      final inst = _Install();
      await inst.store.replace(CatalogueCategorie.produits, [_row()], _catalogueAt);
      await inst.hl.sync.refreshStats();
      inst.monitor.goOffline(manuel: false);
      return inst;
    }

    testWidgets('Fiche hors ligne : copie locale datée, « Disponible en ligne uniquement », pas d\'erreur', (tester) async {
      phone(tester);
      final inst = await horsLigne();
      final api = _FakeApi();
      await tester.pumpWidget(Provider<ApiService>.value(
        value: api,
        child: MaterialApp(home: FicheProduitScreen(produit: produitRecu)),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fiche_hors_ligne')), findsOneWidget);
      expect(find.textContaining('Hors ligne — données du catalogue du 09/10 18:45'), findsOneWidget);
      expect(find.text('STOCKOVIT CP B/30'), findsOneWidget);
      expect(find.text('3400120'), findsOneWidget);
      expect(find.text('7'), findsOneWidget); // stock connu de la copie locale
      expect(find.text('VITAMINES'), findsOneWidget);
      expect(find.text('Disponible en ligne uniquement'), findsNWidgets(2));
      expect(find.textContaining('non disponibles'), findsNothing);
      expect(find.text('Réessayer'), findsNothing);
      expect(api.infos, 0);
      expect(tester.takeException(), isNull);

      // Retour en ligne : la fiche se recharge depuis le serveur.
      inst.monitor.goOnline();
      await tester.pumpAndSettle();
      expect(api.infos, 1);
      expect(find.byKey(const Key('fiche_hors_ligne')), findsNothing);
      expect(find.text('RAYON B2'), findsOneWidget);
      expect(find.text('LABOREX'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Fiche hors ligne sans catalogue local : mention claire, données reçues', (tester) async {
      phone(tester);
      final inst = _Install();
      await inst.hl.sync.refreshStats();
      inst.monitor.goOffline();
      await tester.pumpWidget(MaterialApp(home: FicheProduitScreen(produit: produitRecu, loadInfo: (_) async => throw StateError('pas d\'appel'))));
      await tester.pumpAndSettle();
      expect(find.textContaining('aucun catalogue local'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('Disponible en ligne uniquement'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Recherche globale hors ligne : copie locale, puis fiche hors ligne', (tester) async {
      phone(tester);
      await horsLigne();
      final api = _FakeApi();
      await tester.pumpWidget(Provider<ApiService>.value(
        value: api,
        child: MaterialApp(home: RechercheGlobaleScreen(menus: const [], onOpenMenu: (_) {}, api: () => api)),
      ));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'STOCKO');
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(api.searches, 0);
      expect(find.text('STOCKOVIT CP B/30'), findsOneWidget);
      expect(find.byKey(const Key('note_catalogue_local')), findsOneWidget);
      await tester.tap(find.text('STOCKOVIT CP B/30'));
      await tester.pumpAndSettle();
      expect(find.byType(FicheProduitScreen), findsOneWidget);
      expect(find.textContaining('Hors ligne — données du catalogue du 09/10 18:45'), findsOneWidget);
      expect(api.infos, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Scan hors ligne : le code ouvre la fiche depuis la copie locale', (tester) async {
      phone(tester);
      await horsLigne();
      final api = _FakeApi();
      await tester.pumpWidget(Provider<ApiService>.value(
        value: api,
        child: MaterialApp(home: RechercheGlobaleScreen(menus: const [], onOpenMenu: (_) {}, api: () => api, initialCode: '3400120')),
      ));
      await tester.pumpAndSettle();
      expect(api.searches, 0);
      expect(find.byType(FicheProduitScreen), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
