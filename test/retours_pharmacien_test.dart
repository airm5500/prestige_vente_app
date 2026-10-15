// Retours des essais du pharmacien (nouvelle interface ; interface d'origine inchangée sauf mention) :
// 1. Fenêtres à la charte : plus aucune fenêtre (AlertDialog, SimpleDialog, feuille du bas, SnackBar) au style lavande
//    de Material 3 par défaut — thème global de la nouvelle interface (CharteNouvelleInterface au-dessus du navigateur) ;
//    code administrateur, déconnexion, « Prévente enregistrée », remplacement d'emplacement, photo de contrôle.
// 2. Passage hors ligne (manuel ou « Continuer hors ligne ») seulement avec des données sur le terminal ; sinon refus
//    expliqué + « Télécharger le catalogue » quand le serveur répond ; date / fraîcheur des données dans Réglages.
// 3. Réserve : deux onglets à l'ouverture, « Manuel » à gauche (ouvert) et « Automatique » à droite, mêmes écrans.
// 4. EAN fabricant : confirmation avant d'enregistrer (produit, ancien → nouvel EAN), Entrée / OK de la douchette
//    valide, « Annuler » ne change rien ; clé de contrôle EAN-8 / 12 / 13 / 14 incorrecte : avertissement.
// 5. Icône de la Pré-vente : shopping_cart_checkout (≠ Caisse, ≠ Encaisser).
// 6. Vente carnet / assurance : recherche du client affichée seule dès la 1re image (plus de « flash » des étapes).
// Tailles : Sunmi V2s (Compact automatique), téléphone 360 × 800 dp, tablette ; texte × 1,0 et × 1,3.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/accueil/accueil_menus.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/product_search_result.dart';
import 'package:prestige_vente_app/api/models/rayon.dart';
import 'package:prestige_vente_app/horsligne/catalogue_sync.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/horsligne_ui.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart';
import 'package:prestige_vente_app/horsligne/server_monitor.dart';
import 'package:prestige_vente_app/parametres/hors_ligne_page.dart';
import 'package:prestige_vente_app/providers/product_update_provider.dart';
import 'package:prestige_vente_app/reserve/reserve_api.dart';
import 'package:prestige_vente_app/reserve/reserve_models.dart';
import 'package:prestige_vente_app/reserve/reserve_panier_screen.dart';
import 'package:prestige_vente_app/reserve/reserve_screen.dart';
import 'package:prestige_vente_app/rh/photo_controle.dart';
import 'package:prestige_vente_app/rh/photo_controle_screen.dart';
import 'package:prestige_vente_app/screens/product_update/ean_update_screen.dart';
import 'package:prestige_vente_app/screens/product_update/emplacement_update_screen.dart';
import 'package:prestige_vente_app/serveur/client_prestige.dart';
import 'package:prestige_vente_app/services/identifiants_securises.dart';
import 'package:prestige_vente_app/services/pin_securise.dart';
import 'package:prestige_vente_app/ui/taille_ecran.dart' as ecran;
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/assurance/assurance_frame.dart';
import 'package:prestige_vente_app/ventes/carnet/carnet_frame.dart';
import 'package:prestige_vente_app/widgets/pin_code_dialog.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/responsive.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart' show ProductPage;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'outils/app_e2e.dart';
import 'outils/ergonomie.dart';

/// Tailles demandées : Sunmi V2s (Compact automatique), téléphone 360 × 800 dp, tablette.
const _tailles = [TailleEcran.sunmiV2s, TailleEcran.telephone360x800, TailleEcran.tablette];
const _echelles = [1.0, 1.3];

void _texte(WidgetTester t, double echelle) {
  t.platformDispatcher.textScaleFactorTestValue = echelle;
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Application minimale comme main() : thème de l'appli, taille de l'écran, charte de la nouvelle interface
/// ([nouvelle]) au-dessus du navigateur, largeur des dialogues sur tablette.
Widget _appli(Widget home, {bool nouvelle = true, ValueNotifier<bool>? interrupteur, GlobalKey<NavigatorState>? navigatorKey}) => ecran.RacineTailleEcran(
      child: MaterialApp(
        navigatorKey: navigatorKey,
        theme: AppTheme.lightTheme,
        builder: (context, child) => CharteNouvelleInterface(
          nouvelle: interrupteur ?? ValueNotifier<bool>(nouvelle),
          child: ResponsiveTheme(child: child!),
        ),
        home: home,
      ),
    );

/// Écran avec un bouton qui ouvre la fenêtre [ouvrir].
Widget _bouton(void Function(BuildContext ctx) ouvrir) => Scaffold(
      body: Builder(builder: (ctx) => Center(child: ElevatedButton(onPressed: () => ouvrir(ctx), child: const Text('ouvrir')))),
    );

/// Fenêtre ouverte : rendu sans erreur, à la charte (aucune lavande Material), au moins [n] fenêtre(s).
void _fenetreCharte(WidgetTester t, String contexte, {int n = 1}) {
  expect(t.takeException(), isNull, reason: '$contexte : erreur de rendu (débordement, exception)');
  expect(verifierFenetresCharte(t, contexte: contexte), greaterThanOrEqualTo(n), reason: '$contexte : fenêtre attendue');
}

/// Stockage sûr en mémoire (code administrateur).
class _Coffre implements CoffreIdentifiants {
  final Map<String, String> valeurs = {};
  @override
  Future<String?> lire(String cle) async => valeurs[cle];
  @override
  Future<void> ecrire(String cle, String valeur) async => valeurs[cle] = valeur;
  @override
  Future<void> effacer(String cle) async => valeurs.remove(cle);
}

/// Caméra frontale simulée (jamais ouverte quand on répond « Plus tard »).
class _Camera implements CameraControle {
  int ouvertures = 0;
  @override
  Future<SessionCamera> ouvrir() async {
    ouvertures++;
    throw StateError('caméra non attendue');
  }
}

/// Serveur des écrans EAN / emplacement (produit fictif).
class _ApiProduit extends ApiService {
  _ApiProduit() : super(baseUrl: 'http://localhost');

  String eanActuel = '';
  String emplacementActuel = '';
  final envois = <Map<String, dynamic>>[];

  @override
  Future<ProductPage> searchProductsPageOrFail(String query, int start, int limit) async {
    final all = await searchProducts(query);
    return ProductPage(all.skip(start).take(limit).toList(), all.length);
  }

  @override
  Future<List<ProductSearchResult>> searchProducts(String query) async => [
        ProductSearchResult(
          lgFAMILLEID: 'p1',
          strNAME: 'DOLIPRANE 1000MG CP B/8 BOITE FAMILIALE',
          intCIP: '3595583',
          intPRICE: 1500,
          intNUMBERAVAILABLE: 12,
          strLIBELLEE: emplacementActuel,
          intPAF: 1100,
        ),
      ];

  @override
  Future<ProductDetails?> getProductDetailsForSearch(String codeCip) async =>
      ProductDetails.fromJson({'lg_FAMILLE_ID': 'p1', 'int_CIP': codeCip, 'str_NAME': 'DOLIPRANE', 'codeEanFabriquant': eanActuel});

  @override
  Future<List<Rayon>> getRayons() async => [Rayon(id: 'r1', libelle: 'RAYON A1'), Rayon(id: 'r3', libelle: 'FRIGO')];

  @override
  Future<bool> updateLiteInfo(Map<String, dynamic> data) async {
    envois.add(data);
    return true;
  }
}

/// Copie locale « téléchargée » : produits seulement (les autres catégories vides).
Future<Map<String, dynamic>> _fetchCatalogue(String path, Map<String, dynamic> q) async => path == '/vente/search'
    ? {
        'total': 1,
        'data': [DonneesFictives.produitRecherche()]
      }
    : {'total': 0, 'data': []};

Future<HorsLigne> _horsLigne({bool donnees = false, bool joignable = true, DateTime? maintenant}) async {
  final store = MemoryLocalStore();
  DateTime horloge() => maintenant ?? DateTime(2026, 10, 15, 10, 30);
  final hl =
      HorsLigne(monitor: ServerMonitor(ping: () async => joignable, seuil: 1, clock: horloge), store: store, sync: CatalogueSync(store: store, clock: horloge));
  if (donnees) await store.replace(CatalogueCategorie.produits, [DonneesFictives.produitRecherche()], DateTime(2026, 10, 15, 8, 30));
  await hl.sync.refreshStats();
  final avant = HorsLigne.instance;
  HorsLigne.instance = hl;
  addTearDown(() => HorsLigne.instance = avant);
  return hl;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PresentationPrefs.derniere = null;
    JournalTerminal.instance = JournalTerminal();
  });

  // =======================================================================================================
  group('1. Fenêtres à la charte (plus de lavande Material)', () {
    test('thème de la nouvelle interface : surfaces neutres, bleu nuit, mise en page des boutons gardée', () {
      final base = AppTheme.lightTheme;
      final t = themeNouvelleInterface(base);
      final s = t.colorScheme;
      expect(s.primary, Pal.navy);
      expect(t.dialogTheme.backgroundColor, Colors.white);
      expect(t.dialogTheme.surfaceTintColor, Colors.transparent);
      expect(t.bottomSheetTheme.backgroundColor, Colors.white);
      expect(t.popupMenuTheme.color, Colors.white);
      expect(t.snackBarTheme.backgroundColor, Pal.ink);
      for (final c in [
        s.primary,
        s.primaryContainer,
        s.secondaryContainer,
        s.inversePrimary,
        s.surface,
        s.surfaceContainerLow,
        s.surfaceContainer,
        s.surfaceContainerHigh,
        s.surfaceContainerHighest,
        s.surfaceDim
      ]) {
        expect(couleursLavande.contains(c.toARGB32()), isFalse, reason: 'couleur lavande restée dans le thème : $c');
      }
      // Boutons pleins : bleu nuit, forme et marges de l'application (mise en page inchangée).
      final e = t.elevatedButtonTheme.style!;
      expect(e.backgroundColor!.resolve({}), Pal.navy);
      expect(e.backgroundColor!.resolve({WidgetState.disabled}), isNot(Pal.navy), reason: 'bouton désactivé reconnaissable');
      expect(e.padding!.resolve({}), base.elevatedButtonTheme.style!.padding!.resolve({}));
      expect(e.shape!.resolve({}), base.elevatedButtonTheme.style!.shape!.resolve({}));
      expect(t.textButtonTheme.style!.foregroundColor!.resolve({}), Pal.navy);
    });

    testWidgets('interface d\'origine : thème strictement inchangé ; basculer ne recrée pas le navigateur', (t) async {
      final interrupteur = ValueNotifier<bool>(false);
      final nav = GlobalKey<NavigatorState>();
      ThemeData? vu;
      await t.pumpWidget(_appli(Builder(builder: (ctx) {
        vu = Theme.of(ctx);
        return const Scaffold(body: Text('accueil'));
      }), interrupteur: interrupteur, navigatorKey: nav));
      expect(vu!.colorScheme.primary, AppTheme.lightTheme.colorScheme.primary);
      expect(vu!.dialogTheme.backgroundColor, isNull);
      nav.currentState!.push(MaterialPageRoute(builder: (_) => const Scaffold(body: Text('écran ouvert'))));
      await t.pumpAndSettle();
      final etat = nav.currentState;
      interrupteur.value = true;
      await t.pumpAndSettle();
      expect(nav.currentState, same(etat), reason: 'navigateur conservé');
      expect(find.text('écran ouvert'), findsOneWidget);
      expect(Theme.of(t.element(find.text('écran ouvert'))).dialogTheme.backgroundColor, Colors.white);
    });

    for (final taille in _tailles) {
      for (final echelle in _echelles) {
        final cfg = '$taille, texte ×$echelle';
        testWidgets('fenêtres types (AlertDialog, SimpleDialog, feuille du bas, message) — $cfg', (t) async {
          taille.appliquer(t);
          _texte(t, echelle);
          await t.pumpWidget(_appli(_bouton((ctx) => showDialog<void>(
                context: ctx,
                builder: (c) => AlertDialog(
                  title: const Text('Titre'),
                  content: const Column(mainAxisSize: MainAxisSize.min, children: [Text('Texte'), TextField(), CircularProgressIndicator()]),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
                    ElevatedButton(onPressed: () {}, child: const Text('OK'))
                  ],
                ),
              ))));
          await t.tap(find.text('ouvrir'));
          await t.pump(const Duration(milliseconds: 400));
          _fenetreCharte(t, 'AlertDialog $cfg');
          await t.tap(find.text('Annuler'));
          await t.pumpAndSettle();

          final ctx = t.element(find.text('ouvrir'));
          unawaited(showDialog<void>(
              context: ctx,
              builder: (c) =>
                  SimpleDialog(title: const Text('Choisir'), children: [SimpleDialogOption(onPressed: () => Navigator.pop(c), child: const Text('Option'))])));
          await t.pumpAndSettle();
          _fenetreCharte(t, 'SimpleDialog $cfg');
          await t.tap(find.text('Option'));
          await t.pumpAndSettle();

          unawaited(showModalBottomSheet<void>(
              context: ctx, showDragHandle: true, builder: (c) => ListTile(title: const Text('Feuille'), onTap: () => Navigator.pop(c))));
          await t.pumpAndSettle();
          _fenetreCharte(t, 'BottomSheet $cfg');
          await t.tap(find.text('Feuille'));
          await t.pumpAndSettle();

          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: const Text('Message'), action: SnackBarAction(label: 'Voir', onPressed: () {})));
          await t.pumpAndSettle();
          _fenetreCharte(t, 'SnackBar $cfg');
          expect(t.widget<Material>(find.descendant(of: find.byType(SnackBar), matching: find.byType(Material)).first).color, Pal.ink);
        });

        testWidgets('code administrateur « Accès sécurisé » — $cfg', (t) async {
          taille.appliquer(t);
          _texte(t, echelle);
          final ancien = CodeAdmin.instance;
          CodeAdmin.instance = CodeAdmin(coffre: _Coffre());
          addTearDown(() => CodeAdmin.instance = ancien);
          await t.pumpWidget(_appli(_bouton((ctx) => PinCodeDialog.show(ctx))));
          await t.tap(find.text('ouvrir'));
          await t.pumpAndSettle();
          expect(find.byKey(const Key('pin_admin_saisie')), findsOneWidget);
          _fenetreCharte(t, 'PIN $cfg');
          expect(t.widget<Material>(find.descendant(of: find.widgetWithText(ElevatedButton, 'Valider'), matching: find.byType(Material))).color, Pal.navy);
          await t.tap(find.text('Annuler'));
          await t.pumpAndSettle();
        });

        testWidgets('photo de contrôle du pointage (explication) — $cfg', (t) async {
          taille.appliquer(t);
          _texte(t, echelle);
          final camera = _Camera();
          final photo = PhotoControle(
            camera: camera,
            registre: RegistrePhotosPointage(stockage: StockagePhotosMemoire(), journal: () => JournalTerminal(), retentionJours: () async => 30),
            reglages: () async => const ReglagesPointageTerminal(),
            compresser: (b) async => b,
          );
          MotifSansPhoto? motif;
          await t.pumpWidget(_appli(_bouton((ctx) async => motif = await expliquerEtAutoriserCamera(ctx, photo))));
          await t.tap(find.text('ouvrir'));
          await t.pumpAndSettle();
          expect(find.byKey(const Key('photo_explication')), findsOneWidget);
          _fenetreCharte(t, 'Photo de contrôle $cfg');
          await t.tap(find.text('Plus tard'));
          await t.pumpAndSettle();
          expect(motif, MotifSansPhoto.permissionRefusee);
          expect(camera.ouvertures, 0);
        });

        testWidgets('« Remplacer l\'emplacement ? » — $cfg', (t) async {
          taille.appliquer(t);
          _texte(t, echelle);
          final api = _ApiProduit()..emplacementActuel = 'RAYON A1';
          await t.pumpWidget(ChangeNotifierProvider(
              create: (_) => ProductUpdateProvider(api), child: _appli(const EmplacementUpdateScreen(presentation: ListPresentation.dashboard))));
          await t.pumpAndSettle();
          await t.enterText(find.byType(TextField).first, 'doliprane');
          await t.pump(const Duration(milliseconds: 600));
          await t.pumpAndSettle();
          await t.tap(find.descendant(of: find.byType(DropdownMenu<Rayon>), matching: find.byType(TextField)));
          await t.pumpAndSettle();
          await t.tap(find.text('FRIGO').last);
          await t.pumpAndSettle();
          expect(find.text('Remplacer l\'emplacement ?'), findsOneWidget);
          _fenetreCharte(t, 'Emplacement $cfg');
          await t.tap(find.text('Annuler'));
          await t.pumpAndSettle();
          expect(api.envois, isEmpty);
        });
      }
    }

    // Application entière (MyApp, vrai thème) : déconnexion, code administrateur, « Prévente enregistrée ».
    for (final taille in _tailles) {
      testWidgets('application entière, $taille : « Se déconnecter ? », « Accès sécurisé », « Prévente enregistrée »', (t) async {
        taille.appliquer(t);
        final app = AppE2E();
        await app.preparer(prefs: {'hiddenMenuIds': <String>[]});
        await app.lancer(t);
        expect(await app.seConnecter(t, login: DonneesFictives.admin, motDePasse: DonneesFictives.motDePasseAdmin), isTrue);
        await app.attendre(t);

        await t.tap(find.byKey(const Key('accueil_deconnexion')));
        await app.attendre(t, const Duration(seconds: 1));
        expect(find.text('Se déconnecter ?'), findsOneWidget);
        _fenetreCharte(t, 'Déconnexion $taille');
        await t.tap(find.text('Annuler'));
        await app.attendre(t, const Duration(seconds: 1));

        await app.ouvrirMenu(t, ListPresentation.dashboard, 'ajustement');
        expect(find.byKey(const Key('pin_admin_saisie')), findsOneWidget);
        _fenetreCharte(t, 'Code administrateur $taille');
        await t.tap(find.text('Annuler'));
        await app.attendre(t, const Duration(seconds: 1));

        await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
        await t.enterText(find.byKey(const ValueKey('vente-recherche')), 'para');
        await app.attendre(t);
        final champQte = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField));
        expect(await app.attendreQue(t, champQte), isTrue);
        _fenetreCharte(t, 'Quantité $taille');
        await t.enterText(champQte, '2');
        await t.tap(find.text('Ajouter'));
        await app.attendre(t);
        await t.tap(find.byKey(const ValueKey('vente-enregistrer-prevente')));
        expect(await app.attendreQue(t, find.text('Prévente enregistrée')), isTrue);
        _fenetreCharte(t, 'Prévente enregistrée $taille');
        await t.tap(find.text('Non'));
        await app.attendre(t);
        expect(t.takeException(), isNull);
        await app.fermer(t);
      });
    }
  });

  // =======================================================================================================
  group('2. Passage hors ligne : données obligatoires sur le terminal', () {
    test('sans données : refus, rien ne change ; avec données : passage ; fraîcheur', () async {
      final vide = await _horsLigne();
      expect(vide.donneesDisponibles, isFalse);
      expect(await vide.passerHorsLigne(manuel: true), isFalse);
      expect(vide.offline, isFalse);
      expect(vide.fraicheurLabel(), 'aucune donnée sur ce terminal');
      await vide.monitor.checkNow(); // serveur joignable
      expect(await vide.passerHorsLigne(manuel: false), isFalse);
      expect(vide.monitor.etat, EtatServeur.enLigne);
      expect(HorsLigne.messageSansDonnees,
          'Impossible de passer hors ligne : aucune donnée sur ce terminal. Téléchargez le catalogue quand le serveur est joignable.');

      final pleine = await _horsLigne(donnees: true);
      expect(pleine.donneesDisponibles, isTrue);
      expect(pleine.fraicheurLabel(), 'catalogue du 15/10 08:30 (il y a 2 h)');
      expect(pleine.donneesAnciennes(), isFalse);
      expect(pleine.donneesAnciennes(DateTime(2026, 10, 16, 9)), isTrue);
      expect(await pleine.passerHorsLigne(manuel: true), isTrue);
      expect(pleine.offline, isTrue);
      expect(pleine.monitor.raison, RaisonHorsLigne.manuel);

      expect(HorsLigne.ilYa(DateTime(2026, 1, 1, 10), DateTime(2026, 1, 1, 10, 0, 30)), 'à l\'instant');
      expect(HorsLigne.ilYa(DateTime(2026, 1, 1, 10), DateTime(2026, 1, 1, 10, 5)), 'il y a 5 min');
      expect(HorsLigne.ilYa(DateTime(2026, 1, 1, 10), DateTime(2026, 1, 3, 11)), 'il y a 2 jours');
    });

    for (final taille in _tailles) {
      for (final echelle in _echelles) {
        final cfg = '$taille, texte ×$echelle';
        testWidgets('« Continuer hors ligne » sans données, serveur injoignable : refus expliqué, pas de téléchargement — $cfg', (t) async {
          taille.appliquer(t);
          _texte(t, echelle);
          final hl = await _horsLigne(joignable: false);
          await t.pumpWidget(ecran.RacineTailleEcran(
            child: MaterialApp(
              navigatorKey: HorsLigne.navigatorKey,
              theme: AppTheme.lightTheme,
              builder: (c, child) => CharteNouvelleInterface(
                  nouvelle: ValueNotifier(true), child: HorsLigneScope(horsLigne: hl, bindApp: false, child: ResponsiveTheme(child: child!))),
              home: const Scaffold(body: Text('écran')),
            ),
          ));
          await hl.monitor.checkNow();
          await t.pumpAndSettle();
          await t.tap(find.byKey(const Key('continuer_hors_ligne')));
          await t.pumpAndSettle();
          expect(hl.offline, isFalse, reason: 'aucun passage hors ligne sans données');
          expect(find.byKey(const Key('hors_ligne_impossible')), findsOneWidget);
          expect(find.text(HorsLigne.messageSansDonnees), findsOneWidget);
          expect(find.byKey(const Key('telecharger_catalogue')), findsNothing, reason: 'serveur injoignable : téléchargement impossible');
          expect(find.byKey(const Key('hors_ligne_impossible_attente')), findsOneWidget);
          _fenetreCharte(t, 'Hors ligne impossible $cfg');
          await t.tap(find.byKey(const Key('hors_ligne_impossible_fermer')));
          await t.pumpAndSettle();
          expect(find.byKey(const Key('bandeau_injoignable')), findsOneWidget);
        });

        testWidgets('Réglages › Hors ligne sans données : refus + « Télécharger le catalogue », puis passage ; fraîcheur — $cfg', (t) async {
          taille.appliquer(t);
          _texte(t, echelle);
          final hl = await _horsLigne(maintenant: DateTime.now());
          hl.sync.fetch = _fetchCatalogue;
          await t.pumpWidget(_appli(HorsLignePage(horsLigne: hl), navigatorKey: HorsLigne.navigatorKey));
          await t.pumpAndSettle();
          expect(find.text('Aucune donnée sur ce terminal'), findsOneWidget);
          expect(find.byKey(const Key('fraicheur_donnees_detail')), findsOneWidget);

          await t.tap(find.byType(Switch));
          await t.pumpAndSettle();
          expect(hl.offline, isFalse);
          expect(find.text(HorsLigne.messageSansDonnees), findsOneWidget);
          _fenetreCharte(t, 'Hors ligne impossible (Réglages) $cfg');
          await t.tap(find.byKey(const Key('telecharger_catalogue')));
          await t.pumpAndSettle();
          expect(hl.donneesDisponibles, isTrue);
          expect(find.byKey(const Key('resultat_telechargement_catalogue')), findsOneWidget);
          expect(t.takeException(), isNull);
          await t.pump(const Duration(seconds: 5));
          await t.pumpAndSettle();
          await t.dragUntilVisible(find.byKey(const Key('fraicheur_donnees')), find.byType(ListView), const Offset(0, 300));
          expect(t.widget<Text>(find.byKey(const Key('fraicheur_donnees'))).data, startsWith('Données du terminal : catalogue du '));
          expect(t.widget<Text>(find.byKey(const Key('fraicheur_donnees'))).data, endsWith('(à l\'instant)'));
          expect(find.byKey(const Key('fraicheur_donnees_detail')), findsNothing);

          await t.dragUntilVisible(find.byType(Switch), find.byType(ListView), const Offset(0, -200));
          await t.tap(find.byType(Switch));
          await t.pumpAndSettle();
          expect(hl.offline, isTrue, reason: 'données présentes : passage hors ligne accepté');
          expect(find.byKey(const Key('hors_ligne_impossible')), findsNothing);
          expect(t.takeException(), isNull);
        });
      }
    }

    testWidgets('données de plus de 12 h : fraîcheur signalée', (t) async {
      TailleEcran.sunmiV2s.appliquer(t);
      final hl = await _horsLigne(donnees: true, maintenant: DateTime(2026, 10, 16, 9));
      await t.pumpWidget(_appli(HorsLignePage(horsLigne: hl)));
      await t.pumpAndSettle();
      expect(find.text('Données du terminal : catalogue du 15/10 08:30 (il y a 1 jour)'), findsOneWidget);
      expect(find.textContaining('Données de plus de 12 h'), findsOneWidget);
    });
  });

  // =======================================================================================================
  group('3. Réserve : onglets Manuel / Automatique', () {
    for (final taille in _tailles) {
      for (final echelle in _echelles) {
        final cfg = '$taille, texte ×$echelle';
        testWidgets('« Manuel » à gauche et ouvert, « Automatique » à droite ; mêmes écrans — $cfg', (t) async {
          taille.appliquer(t);
          _texte(t, echelle);
          final s = FauxServeurPrestige()
            ..activerModules()
            ..exigerSession = false;
          s.installerEnMemoire();
          addTearDown(s.desinstaller);
          await t.pumpWidget(_appli(ReserveScreen(api: ReserveApi(ClientPrestige(() => s.base)))));
          for (var i = 0; i < 10; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          expect(t.takeException(), isNull);
          final manuel = find.byKey(const ValueKey('reserve-onglet-manuel'));
          final auto = find.byKey(const ValueKey('reserve-onglet-auto'));
          expect(t.getCenter(manuel).dx, lessThan(t.getCenter(auto).dx));
          expect(t.getSize(manuel).height, greaterThanOrEqualTo(48 * 0.9 - 0.01), reason: 'onglet ≥ 48 dp de l\'interface');
          expect(DefaultTabController.of(t.element(manuel)).index, 0, reason: 'onglet « Manuel » ouvert');
          expect(find.byKey(const ValueKey('reserve-manuel-versReserve')), findsOneWidget);
          expect(find.byKey(const ValueKey('reserve-manuel-versRayon')), findsOneWidget);
          expect(find.byKey(const ValueKey('reserve-auto-versRayon')), findsNothing);

          // Réappro manuel : même écran qu'avant (panier).
          final preparer = find.descendant(of: find.byKey(const ValueKey('reserve-manuel-versRayon')), matching: find.text('Préparer'));
          await t.ensureVisible(preparer);
          await t.pumpAndSettle();
          await t.tap(preparer);
          await t.pumpAndSettle();
          expect(find.byType(ReservePanierScreen), findsOneWidget);
          expect(t.widget<ReservePanierScreen>(find.byType(ReservePanierScreen)).sens, SensReserve.versRayon);
          Navigator.of(t.element(find.byType(ReservePanierScreen))).pop();
          await t.pumpAndSettle();

          await t.tap(auto);
          await t.pumpAndSettle();
          expect(find.byKey(const ValueKey('reserve-auto-versRayon')), findsOneWidget);
          expect(find.byKey(const ValueKey('reserve-auto-versReserve')), findsOneWidget);
          expect(find.byKey(const ValueKey('reserve-manuel-versRayon')), findsNothing);
          final voir = find.descendant(of: find.byKey(const ValueKey('reserve-auto-versReserve')), matching: find.text('Voir les suggestions'));
          await t.ensureVisible(voir);
          await t.pumpAndSettle();
          await t.tap(voir);
          await t.pumpAndSettle();
          final liste = t.widget<ReserveListeScreen>(find.byType(ReserveListeScreen));
          expect(liste.origine, OrigineSuggestion.automatique);
          expect(liste.sens, SensReserve.versReserve);
          expect(t.takeException(), isNull);
        });
      }
    }
  });

  // =======================================================================================================
  group('4. EAN fabricant : confirmation avant d\'enregistrer', () {
    test('format bloquant, clé de contrôle EAN-8 / 12 / 13 / 14 en avertissement', () {
      expect(validateEanFormat(''), 'Veuillez saisir un code');
      expect(validateEanFormat('12AB5678'), contains('chiffres'));
      expect(validateEanFormat('1234567'), contains('Longueur invalide'));
      expect(validateEanFormat('3400930000015'), isNull, reason: 'clé incorrecte : non bloquante');
      expect(cleEanAttendue('3400930000015'), 4);
      expect(cleEanAttendue('12345670'), 0);
      expect(cleEanAttendue('012345678905'), 5);
      expect(cleEanAttendue('01234567890128'), 8);
      expect(cleEanAttendue('1234'), isNull);
      for (final bon in ['3400930000014', '4006381333931', '12345670', '96385074', '012345678905', '01234567890128']) {
        expect(avertissementCleEan(bon), isNull, reason: bon);
      }
      expect(avertissementCleEan('3400930000015'), 'Clé EAN-13 incorrecte : le dernier chiffre devrait être 4. Vérifiez le code.');
      expect(avertissementCleEan('12345671'), contains('Clé EAN-8 incorrecte'));
      expect(avertissementCleEan('012345678906'), contains('Clé UPC-A incorrecte'));
      expect(avertissementCleEan('01234567890129'), contains('Clé GTIN-14 incorrecte'));
      // Clé EAN-13 calculée comme avant.
      expect(cleEanAttendue('400638133393${ean13CheckDigit('400638133393')}'), ean13CheckDigit('400638133393'));
    });

    Future<_ApiProduit> ouvrir(WidgetTester t, {String eanActuel = '4006381333931'}) async {
      final api = _ApiProduit()..eanActuel = eanActuel;
      await t.pumpWidget(
          ChangeNotifierProvider(create: (_) => ProductUpdateProvider(api), child: _appli(const EanUpdateScreen(presentation: ListPresentation.dashboard))));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).first, 'doliprane');
      await t.pump(const Duration(milliseconds: 600));
      await t.pumpAndSettle();
      return api;
    }

    Finder champ() => find.widgetWithText(TextFormField, 'Code EAN Fabricant');

    for (final taille in _tailles) {
      for (final echelle in _echelles) {
        final cfg = '$taille, texte ×$echelle';
        testWidgets('récapitulatif, « Annuler » ne change rien, Entrée (douchette) enregistre — $cfg', (t) async {
          taille.appliquer(t);
          _texte(t, echelle);
          final api = await ouvrir(t);
          await t.enterText(champ(), '3400930000014');
          await t.testTextInput.receiveAction(TextInputAction.done); // Entrée de la douchette dans le champ
          await t.pumpAndSettle();
          expect(find.byKey(const ValueKey('ean-confirmation')), findsOneWidget);
          expect(find.text('Remplacer l\'EAN Fabricant ?'), findsOneWidget);
          expect(t.widget<Text>(find.byKey(const ValueKey('ean-confirmation-produit'))).data, 'DOLIPRANE 1000MG CP B/8 BOITE FAMILIALE');
          expect(t.widget<Text>(find.byKey(const ValueKey('ean-confirmation-ancien'))).data, '4006381333931');
          expect(t.widget<Text>(find.byKey(const ValueKey('ean-confirmation-nouveau'))).data, '3400930000014  (EAN-13)');
          expect(find.byKey(const ValueKey('ean-confirmation-avertissement')), findsNothing);
          _fenetreCharte(t, 'Confirmation EAN $cfg');
          // Cibles ≥ 48 dp (de l'interface) pour les deux boutons.
          for (final k in ['ean-confirmation-annuler', 'ean-confirmation-enregistrer']) {
            expect(t.getSize(find.byKey(ValueKey(k))).height, greaterThanOrEqualTo(48 * 0.9 - 0.01), reason: k);
          }

          await t.tap(find.byKey(const ValueKey('ean-confirmation-annuler')));
          await t.pumpAndSettle();
          expect(api.envois, isEmpty, reason: '« Annuler » ne change rien');
          expect(t.widget<TextFormField>(champ()).controller!.text, '3400930000014', reason: 'saisie gardée');

          await t.tap(find.text('Valider'));
          await t.pumpAndSettle();
          // Bouton par défaut : Entrée / OK de la douchette valide la confirmation.
          expect(Focus.of(t.element(find.text('Enregistrer'))).hasFocus, isTrue);
          await t.sendKeyEvent(LogicalKeyboardKey.enter);
          await t.pumpAndSettle();
          expect(api.envois, [
            {'id': 'p1', 'codeEanFabriquant': '3400930000014'}
          ]);
          expect(find.byKey(const ValueKey('ean-confirmation')), findsNothing);
          expect(t.takeException(), isNull);
          await t.pump(const Duration(seconds: 3));
        });

        testWidgets('clé incorrecte : avertissement, Entrée = « Corriger », « Enregistrer quand même » explicite — $cfg', (t) async {
          taille.appliquer(t);
          _texte(t, echelle);
          final api = await ouvrir(t, eanActuel: '');
          await t.enterText(champ(), '3400930000015');
          await t.tap(find.text('Valider'));
          await t.pumpAndSettle();
          expect(find.text('Enregistrer l\'EAN Fabricant ?'), findsOneWidget);
          expect(t.widget<Text>(find.byKey(const ValueKey('ean-confirmation-ancien'))).data, 'aucun');
          expect(find.textContaining('Clé EAN-13 incorrecte : le dernier chiffre devrait être 4'), findsOneWidget);
          _fenetreCharte(t, 'Confirmation EAN (clé incorrecte) $cfg');
          await t.sendKeyEvent(LogicalKeyboardKey.enter);
          await t.pumpAndSettle();
          expect(api.envois, isEmpty, reason: 'Entrée ramène à la saisie');
          expect(find.byKey(const ValueKey('ean-confirmation')), findsNothing);

          await t.tap(find.text('Valider'));
          await t.pumpAndSettle();
          await t.tap(find.byKey(const ValueKey('ean-confirmation-enregistrer-quand-meme')));
          await t.pumpAndSettle();
          expect(api.envois.single['codeEanFabriquant'], '3400930000015');
          await t.pump(const Duration(seconds: 3));
        });
      }
    }
  });

  // =======================================================================================================
  group('5. Icône de la Pré-vente', () {
    test('shopping_cart_checkout : distincte de la Caisse, de l\'encaissement et des autres menus', () {
      final pv = accueilMenuById['prevente']!;
      expect(pv.icon, Icons.shopping_cart_checkout);
      expect(pv.icon, isNot(accueilMenuById['caisse']!.icon));
      expect(pv.icon, isNot(Icons.point_of_sale), reason: 'icône du bouton « Encaisser » des ventes');
      for (final m in accueilMenus.where((m) => m.id != 'prevente')) {
        expect(m.icon, isNot(pv.icon), reason: 'icône déjà prise par ${m.id}');
      }
    });

    testWidgets('accueil : tuile et favori Pré-vente avec la nouvelle icône', (t) async {
      TailleEcran.sunmiV2s.appliquer(t);
      final app = AppE2E();
      await app.preparer(prefs: {'hiddenMenuIds': <String>[]});
      await app.lancer(t);
      expect(await app.seConnecter(t), isTrue);
      await app.attendre(t);
      // Favoris par défaut : la Pré-vente en premier.
      expect(find.byIcon(Icons.shopping_cart_checkout), findsWidgets);
      await app.defilerJusqua(t, find.byKey(const ValueKey('tuile_prevente')));
      expect(find.descendant(of: find.byKey(const ValueKey('tuile_prevente')), matching: find.byIcon(Icons.shopping_cart_checkout)), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('tuile_prevente')), matching: find.byIcon(Icons.point_of_sale)), findsNothing);
      await app.fermer(t);
    });
  });

  // =======================================================================================================
  group('6. Vente carnet / assurance : recherche du client seule dès la 1re image', () {
    bool etapesVisibles() =>
        find.byType(StepsBar, skipOffstage: false).evaluate().isNotEmpty ||
        find.byType(CarnetStepPills, skipOffstage: false).evaluate().isNotEmpty ||
        find.byType(AssuranceStepsBar, skipOffstage: false).evaluate().isNotEmpty;

    // Trois présentations sur Sunmi V2s ; tailles et échelles de texte en présentation A.
    final configurations = <(ListPresentation, TailleEcran, double)>[
      for (final style in ListPresentation.values) (style, TailleEcran.sunmiV2s, 1.0),
      for (final taille in _tailles)
        for (final echelle in _echelles)
          if (taille != TailleEcran.sunmiV2s || echelle != 1.0) (ListPresentation.dashboard, taille, echelle),
    ];
    for (final (menu, champ) in const [('carnet', 'carnet-client-recherche'), ('assurance', 'assurance-client-recherche')]) {
      {
        for (final (style, taille, echelle) in configurations) {
          {
            testWidgets('$menu — ${style.label} — $taille, texte ×$echelle : aucune étape à aucune image, clavier fermé ou ouvert', (t) async {
              taille.appliquer(t);
              _texte(t, echelle);
              final app = AppE2E();
              await app.preparer(prefs: {'hiddenMenuIds': <String>[], 'presentation_listes_v1': style.name});
              await app.lancer(t);
              expect(await app.seConnecter(t), isTrue);
              await app.attendre(t);
              final tuile = style == ListPresentation.dashboard ? find.byKey(ValueKey('tuile_$menu')) : find.text(accueilMenuById[menu]!.label);
              if (style == ListPresentation.guided) {
                await app.defilerJusqua(t, find.text('Voir tous les menus'));
                await t.tap(find.text('Voir tous les menus'));
                await t.pump();
              }
              await app.defilerJusqua(t, tuile);
              await t.tap(tuile.first);
              // 1re image construite (encore hors scène : préparation de la transition), puis chaque image de
              // l'ouverture (transition, focus, clavier) : jamais d'étapes, la recherche toujours là.
              await t.pump();
              expect(find.byKey(ValueKey(champ), skipOffstage: false), findsOneWidget, reason: 'recherche du client dès la 1re image');
              expect(etapesVisibles(), isFalse, reason: '1re image : aucune étape avant la recherche');
              for (var i = 0; i < 40; i++) {
                await t.pump(const Duration(milliseconds: 16));
                expect(etapesVisibles(), isFalse, reason: 'image ${i + 2} : étapes affichées (flash)');
              }
              // Clavier ouvert (champ focalisé) puis refermé : toujours aucune étape.
              t.view.viewInsets = FakeViewPadding(bottom: t.view.physicalSize.height * 0.4);
              addTearDown(t.view.resetViewInsets);
              await t.pump();
              expect(etapesVisibles(), isFalse);
              t.view.resetViewInsets();
              await t.pump();
              expect(etapesVisibles(), isFalse);
              expect(find.byKey(ValueKey(champ)), findsOneWidget);
              expect(t.takeException(), isNull);
              await app.fermer(t);
            });
          }
        }
      }
    }
  });
}
