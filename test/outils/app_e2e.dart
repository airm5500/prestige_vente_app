// Banc e2e : l'application ENTIÈRE (MyApp, vrais providers, vrais écrans, vrai client Dio) montée par
// `flutter test` sur Linux, sans émulateur, reliée au faux serveur Prestige EN MÉMOIRE.
// Reprend l'initialisation de lib/main.dart sauf ce qui exige le téléphone (SQLite, dossier de l'appli,
// capture globale des erreurs) : stockages en mémoire, mêmes réglages lus depuis les préférences.
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestige_vente_app/accueil/accueil_menus.dart';
import 'package:prestige_vente_app/accueil/accueil_screen.dart';
import 'package:prestige_vente_app/connexion/connexion_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/api/session_expiree.dart';
import 'package:prestige_vente_app/borne/borne_config.dart';
import 'package:prestige_vente_app/connexion/connexion_commun.dart';
import 'package:prestige_vente_app/connexion/connexion_reglages.dart';
import 'package:prestige_vente_app/connexion/pin_personnel.dart';
import 'package:prestige_vente_app/droits/droits_modules.dart';
import 'package:prestige_vente_app/droits/droits_vente.dart';
import 'package:prestige_vente_app/api/utilisateur_session.dart';
import 'package:prestige_vente_app/horsligne/catalogue_sync.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart';
import 'package:prestige_vente_app/horsligne/server_monitor.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_horsligne.dart';
import 'package:prestige_vente_app/horsligne/vente_hors_ligne.dart';
import 'package:prestige_vente_app/horsligne/ventes_sync.dart';
import 'package:prestige_vente_app/images/images_reglages.dart';
import 'package:prestige_vente_app/interface_version.dart';
import 'package:prestige_vente_app/main.dart';
import 'package:prestige_vente_app/paiements/paiements_mobile.dart';
import 'package:prestige_vente_app/rh/pointage_rh.dart';
import 'package:prestige_vente_app/services/identifiants_securises.dart';
import 'package:prestige_vente_app/services/search_mode.dart';
import 'package:prestige_vente_app/ui/taille_ecran.dart' as ecran;
import 'package:prestige_vente_app/ventes/ventes_version.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'faux_serveur_prestige.dart';

export 'faux_serveur_prestige.dart';

/// Taille d'écran (pixels physiques, densité).
class TailleEcran {
  final String nom;
  final Size pixels;
  final double densite;
  const TailleEcran(this.nom, this.pixels, this.densite);

  Size get dp => pixels / densite;

  static const sunmiV2s = TailleEcran('Sunmi V2s 720×1440', Size(720, 1440), 2.0);
  static const sunmiV3 = TailleEcran('Sunmi V3 1080×1920', Size(1080, 1920), 2.625);
  static const telephone = TailleEcran('Téléphone 360×640 dp', Size(720, 1280), 2.0);
  static const tablette = TailleEcran('Tablette 1920×1200', Size(1920, 1200), 1.5);

  /// Téléphone courant 1080×2400, densité 3 (Samsung) : 360 × 800 dp, taille NORMALE en Automatique (4.0.1).
  /// Depuis le Compact automatique des petits écrans (V2s, V3, 360×640 dp : 400 dp de large vus par
  /// l'interface), c'est la configuration de la matrice qui garde 360 dp de large à la taille normale.
  static const telephone360x800 = TailleEcran('Téléphone 1080×2400 (360×800 dp)', Size(1080, 2400), 3.0);

  static const toutes = [sunmiV2s, sunmiV3, telephone, telephone360x800, tablette];

  void appliquer(WidgetTester t) {
    t.view.physicalSize = pixels;
    t.view.devicePixelRatio = densite;
    addTearDown(t.view.reset);
  }

  @override
  String toString() => nom;
}

class AppE2E {
  final FauxServeurPrestige serveur;
  late HorsLigne horsLigne;
  AppE2E({FauxServeurPrestige? serveur}) : serveur = serveur ?? FauxServeurPrestige();

  /// Préférences de l'appareil : serveur configuré sur le faux serveur ; « Rester connecté » si [resterConnecte].
  Future<void> preparer({
    bool resterConnecte = false,
    String login = DonneesFictives.login,
    String motDePasse = DonneesFictives.motDePasse,
    Map<String, Object> prefs = const {},
    bool interfaceNouvelle = true,
  }) async {
    SharedPreferences.setMockInitialValues({
      'local_ip': FauxServeurPrestige.hoteMemoire,
      'port': FauxServeurPrestige.portMemoire,
      'app_name': 'prestige',
      'interface_nouvelle_version_v1': interfaceNouvelle,
      if (resterConnecte) ...{'stay_connected': true, 'saved_login': login},
      ...prefs,
    });
    FlutterSecureStorage.setMockInitialValues(resterConnecte ? {IdentifiantsSecurises.cleSure: motDePasse} : {});
    IdentifiantsSecurises.instance = IdentifiantsSecurises();
    PinPersonnel.instance = PinPersonnel(iterations: 1000);

    // Même ordre que lib/main.dart (sans SQLite ni dossier de l'appli).
    await initializeDateFormatting('fr_FR', null);
    await VentesVersion.load();
    await InterfaceVersion.load();
    // Taille de l'écran (4.0.1) : réglage lu comme main() ; Automatique → Compact sur un petit écran.
    await ecran.TailleEcranReglage.charger();
    await SearchModePrefs.load();
    await BorneReglages.charger();
    await ConnexionReglages.charger();
    await ImagesReglages.charger();
    await PaiementsMobileReglages.charger();
    JournalTerminal.instance = JournalTerminal();

    final store = MemoryLocalStore();
    horsLigne = HorsLigne(monitor: ServerMonitor(), store: store, sync: CatalogueSync(store: store, occupee: () => false), ventes: FileVentesHL(store: MemoryVentesHLStore()));
    final hlAvant = HorsLigne.instance;
    HorsLigne.instance = horsLigne;
    StockHorsLigne.instance = null;
    PointageRh.instance = null;
    SessionExpiree.instance = SessionExpiree();
    DroitsModules.instance.oublier();
    // 4.5.1 : droits de vente et compte de la session en mémoire, remis à zéro pour chaque test.
    DroitsVente.instance.oublier();
    DroitsVente.instance.oublierControles();
    UtilisateurSession.id = null;
    SessionChangee.instance = SessionChangee();
    ConnexionServices.instance = const ConnexionServices();
    await DioClient.cookieJar.deleteAll();
    serveur.installerEnMemoire();
    addTearDown(() async {
      ecran.TailleEcranReglage.reinitialiser();
      serveur.desinstaller();
      HorsLigne.instance = hlAvant;
      StockHorsLigne.instance = null;
      PointageRh.instance = null;
      DroitsModules.instance.oublier();
      DroitsVente.instance.oublier();
      UtilisateurSession.id = null;
      await DioClient.cookieJar.deleteAll();
    });
  }

  /// Monte l'application entière (comme runApp(const MyApp())).
  Future<void> lancer(WidgetTester t) async {
    // Application au premier plan (la surveillance du serveur ne travaille qu'au premier plan).
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpWidget(const MyApp());
    await t.pump();
  }

  /// Laisse passer [duree] de temps simulé, image par image (pas de pumpAndSettle : animations infinies).
  Future<void> attendre(WidgetTester t, [Duration duree = const Duration(seconds: 2)]) async {
    const pas = Duration(milliseconds: 100);
    var ecoule = Duration.zero;
    while (ecoule < duree) {
      await t.pump(pas);
      ecoule += pas;
    }
  }

  /// Attend que [f] trouve quelque chose (au plus [max] de temps simulé).
  Future<bool> attendreQue(WidgetTester t, Finder f, {Duration max = const Duration(seconds: 15)}) async {
    const pas = Duration(milliseconds: 100);
    var ecoule = Duration.zero;
    while (ecoule < max) {
      if (f.evaluate().isNotEmpty) return true;
      await t.pump(pas);
      ecoule += pas;
    }
    return f.evaluate().isNotEmpty;
  }

  /// Démonte l'application et laisse finir les minuteries (réessais, surveillance).
  Future<void> fermer(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 31));
  }

  // ---------------------------------------------------------------------------
  // Gestes de l'utilisateur
  // ---------------------------------------------------------------------------

  /// Écran de connexion (nouvelle interface) : identifiant, mot de passe, « Rester connecté » au besoin, puis
  /// attente de l'accueil (false si l'accueil ne s'ouvre pas).
  Future<bool> seConnecter(WidgetTester t,
      {String login = DonneesFictives.login, String motDePasse = DonneesFictives.motDePasse, bool resterConnecte = false}) async {
    if (!await attendreQue(t, find.byType(ConnexionScreen))) return false;
    await t.enterText(find.byKey(const Key('connexion_login')), login);
    await t.enterText(find.byKey(const Key('connexion_mdp')), motDePasse);
    if (resterConnecte) {
      await t.ensureVisible(find.byKey(const Key('rester_connecte')));
      await t.tap(find.byKey(const Key('rester_connecte')));
    }
    await t.ensureVisible(find.byKey(const Key('se_connecter')));
    await t.tap(find.byKey(const Key('se_connecter')));
    final ok = await attendreQue(t, find.byType(AccueilScreen));
    if (ok) await attendre(t, const Duration(seconds: 1));
    return ok;
  }

  /// Fait défiler la première zone défilante de l'écran jusqu'à ce que [f] soit construit, puis le rend visible.
  Future<void> defilerJusqua(WidgetTester t, Finder f, {Finder? zone}) async {
    final z = zone ?? find.byType(Scrollable).first;
    final pos = t.state<ScrollableState>(z).position;
    if (f.evaluate().isEmpty) {
      pos.jumpTo(pos.minScrollExtent);
      await t.pump();
      while (f.evaluate().isEmpty && pos.pixels < pos.maxScrollExtent) {
        pos.jumpTo((pos.pixels + 250).clamp(pos.minScrollExtent, pos.maxScrollExtent));
        await t.pump();
      }
    }
    expect(f, findsWidgets, reason: 'élément introuvable après défilement : $f');
    await t.ensureVisible(f.first);
    await t.pump();
  }

  /// Ouvre le menu [id] de l'accueil dans la présentation [style] (tuile en A, ligne en B, liste « Voir tous les
  /// menus » en C) ; le code administrateur est demandé pour les menus protégés (non utilisés ici).
  Future<void> ouvrirMenu(WidgetTester t, ListPresentation style, String id) async {
    final m = [...accueilMenus, ...menusSousDroits].firstWhere((m) => m.id == id);
    if (style == ListPresentation.guided) await _listeComplete(t);
    final f = style == ListPresentation.dashboard ? find.byKey(ValueKey('tuile_$id')) : find.text(m.label);
    await defilerJusqua(t, f);
    await t.tap(f.first);
    await attendre(t, const Duration(seconds: 1));
  }

  /// Présentation C : liste de tous les menus dépliée (« Voir tous les menus »), une seule fois.
  Future<void> _listeComplete(WidgetTester t) async {
    await defilerJusqua(t, find.textContaining(RegExp('^(Voir tous les menus|Masquer la liste des menus)\$')));
    if (find.text('Voir tous les menus').evaluate().isNotEmpty) {
      await t.tap(find.text('Voir tous les menus'));
      await t.pump();
    }
  }

  /// Le menu [id] figure-t-il sur l'accueil ? (toute la page parcourue)
  Future<bool> menuPresent(WidgetTester t, ListPresentation style, String id) async {
    final m = [...accueilMenus, ...menusSousDroits].firstWhere((m) => m.id == id);
    if (style == ListPresentation.guided) await _listeComplete(t);
    final f = style == ListPresentation.dashboard ? find.byKey(ValueKey('tuile_$id')) : find.text(m.label);
    final pos = t.state<ScrollableState>(find.byType(Scrollable).first).position;
    pos.jumpTo(pos.minScrollExtent);
    await t.pump();
    while (f.evaluate().isEmpty && pos.pixels < pos.maxScrollExtent) {
      pos.jumpTo((pos.pixels + 250).clamp(pos.minScrollExtent, pos.maxScrollExtent));
      await t.pump();
    }
    final present = f.evaluate().isNotEmpty;
    pos.jumpTo(pos.minScrollExtent);
    await t.pump();
    return present;
  }

  /// Bouton « retour » d'Android (comme l'appui sur la touche du terminal).
  Future<void> retour(WidgetTester t) async {
    await t.binding.handlePopRoute();
    await attendre(t, const Duration(seconds: 1));
  }
}
