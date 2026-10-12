// Nouveau lancement et nouvelle connexion (proposition A + option C « Qui êtes-vous ? ») :
// étapes réelles, licence expirée, serveur injoignable + réessai 10 s, borne, connexion OK / erreur,
// changer de serveur sous code admin, terminal partagé, 6 derniers utilisateurs sans défilement,
// PIN personnel haché, 3 erreurs → mot de passe, assistance, nom de l'officine mémorisé,
// ancienne interface inchangée.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/licence_lookup.dart';
import 'package:prestige_vente_app/api/models/licence_model.dart';
import 'package:prestige_vente_app/api/models/officine.dart';
import 'package:prestige_vente_app/api/models/user.dart';
import 'package:prestige_vente_app/borne/borne_config.dart';
import 'package:prestige_vente_app/connexion/assistance.dart';
import 'package:prestige_vente_app/connexion/connexion_commun.dart';
import 'package:prestige_vente_app/connexion/connexion_reglages.dart';
import 'package:prestige_vente_app/connexion/connexion_screen.dart';
import 'package:prestige_vente_app/connexion/lancement_screen.dart';
import 'package:prestige_vente_app/connexion/pin_personnel.dart';
import 'package:prestige_vente_app/connexion/qui_etes_vous_screen.dart';
import 'package:prestige_vente_app/connexion/reglages_connexion.dart';
import 'package:prestige_vente_app/interface_version.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/licence_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/screens/auth/login_screen.dart';
import 'package:prestige_vente_app/screens/splash_screen.dart';
import 'package:prestige_vente_app/services/identifiants_securises.dart';
import 'package:prestige_vente_app/services/pin_securise.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _mdp = 'Secret!42';

class _Api extends ApiService {
  _Api() : super(baseUrl: 'http://localhost');

  LicenceLookup Function() licence = () => LicenceLookup.found(LicenceModel(id: '1', dateStart: '2026-01-01', dateEnd: '2099-12-31', typeLicence: 'ANNUELLE'));
  Completer<void>? bloquerLicence;
  int licences = 0;
  final logins = <String>[];
  final comptes = <String, String>{'kone.awa': _mdp, 'yao.serge': 'Autre#7'};

  @override
  Future<LicenceLookup> lookupLicence() async {
    licences++;
    if (bloquerLicence != null) await bloquerLicence!.future;
    return licence();
  }

  @override
  Future<User?> login(String login, String password) async {
    logins.add(login);
    if (comptes[login] != password) return null;
    return User(
        userId: 'u-$login',
        login: login,
        firstName: login == 'kone.awa' ? 'Awa' : 'Serge',
        lastName: login == 'kone.awa' ? 'Koné' : 'Yao',
        officineName: '',
        role: 'Caissière');
  }

  @override
  Future<void> logout() async {}

  @override
  Future<Officine?> fetchOfficineInfo() async => Officine(fullName: 'KONAN KOU', nomComplet: 'PHARMACIE LES PALMIERS');
}

class _Env {
  final api = _Api();
  final settings = SettingsProvider();
  late final licence = LicenceProvider(api);
  late final auth = AuthProvider(api);
  bool serveurRepond = true;
  bool adminOk = true;
  int adminChecks = 0;
  int bornes = 0;
  final sondes = <String>[];

  ConnexionServices get services => ConnexionServices(
        adminCheck: (_) async {
          adminChecks++;
          return adminOk;
        },
        sonde: (s, ip) async {
          sondes.add(ip);
          return serveurRepond;
        },
        chargements: (ctx) => ctx.read<AuthProvider>().loadOfficineInfo(),
        accueil: () => const Scaffold(body: Text('ACCUEIL (test)')),
        configuration: () => const Scaffold(body: Text('CONFIGURATION (test)')),
        ouvrirBorne: (_) => bornes++,
      );

  Widget app(Widget home, {ThemeData? theme}) => MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          Provider<ApiService>.value(value: api),
          ChangeNotifierProvider<LicenceProvider>.value(value: licence),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ],
        child: MaterialApp(theme: theme, home: home),
      );
}

void main() {
  final appels = <Uri>[];
  var composeurDisponible = true;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    ConnexionReglages.courant.value = const ConnexionConfig();
    ConnexionReglages.officine.value = '';
    BorneReglages.courant.value = const BorneConfig();
    PinPersonnel.instance = PinPersonnel(iterations: 1000);
    IdentifiantsSecurises.instance = IdentifiantsSecurises();
    InterfaceVersion.useNew.value = true;
    appels.clear();
    composeurDisponible = true;
    Assistance.lanceur = (u) async {
      appels.add(u);
      return composeurDisponible;
    };
  });

  void ecran(WidgetTester t, {Size taille = const Size(360, 800)}) {
    t.view.physicalSize = taille * 2;
    t.view.devicePixelRatio = 2.0;
    addTearDown(t.view.reset);
  }

  Future<void> laisser(WidgetTester t, [Duration d = const Duration(milliseconds: 50)]) async {
    for (var i = 0; i < 6; i++) {
      await t.pump(d);
    }
  }

  Future<void> fermer(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 11));
  }

  // -------------------------------------------------------------------------
  group('Lancement', () {
    testWidgets('étapes réelles cochées au fur et à mesure, affichage minimal 1,2 s, puis connexion', (t) async {
      ecran(t);
      final env = _Env()..api.bloquerLicence = Completer<void>();
      await t.pumpWidget(env.app(LancementScreen(services: env.services)));
      await laisser(t);
      expect(find.text('Prestige Mobile'), findsOneWidget);
      expect(find.text('Chargement des réglages'), findsOneWidget); // fait
      expect(find.text('Connexion au serveur…'), findsOneWidget); // en cours
      expect(find.text('Serveur local · 192.168.1.50:8080'), findsOneWidget);
      expect(find.text('Vérification de la licence…'), findsOneWidget);
      expect(find.bySemanticsLabel('Chargement des réglages, terminé'), findsOneWidget);
      expect(find.bySemanticsLabel('Connexion au serveur…, en cours'), findsOneWidget);
      expect(find.textContaining('Version 1.2.0'), findsOneWidget);
      expect(env.api.licences, 1);

      env.api.bloquerLicence!.complete();
      await t.pump();
      await t.pump();
      // Tout est prêt avant 1,2 s : l'écran reste affiché jusqu'au minimum (pas d'attente fixe en plus).
      expect(find.byType(LancementScreen), findsOneWidget);
      await t.pump(const Duration(milliseconds: 1300));
      await laisser(t, const Duration(milliseconds: 200)); // fin de la transition
      expect(find.byType(LancementScreen), findsNothing);
      expect(find.byType(ConnexionScreen), findsOneWidget);
      await fermer(t);
    });

    testWidgets('licence expirée : explication datée, saisir la clé, appeler l\'assistance, vérifier à nouveau', (t) async {
      ecran(t);
      final env = _Env()..api.licence = () => LicenceLookup.found(LicenceModel(id: '1', dateStart: '2020-01-01', dateEnd: '2020-09-30', typeLicence: ''));
      await t.pumpWidget(env.app(LancementScreen(services: env.services)));
      await laisser(t);
      expect(find.text('Licence expirée le 30/09/2020'), findsOneWidget);
      expect(find.text('Licence expirée'), findsOneWidget); // étape en alerte
      expect(find.byKey(const Key('saisir_licence')), findsOneWidget);
      await t.tap(find.text('Appeler l\'assistance Prestige'));
      await t.pump();
      expect(appels.single.toString(), 'tel:0708080068');
      await t.tap(find.byKey(const Key('verifier_licence')));
      await laisser(t);
      expect(env.api.licences, 2);
      expect(t.takeException(), isNull);
      await fermer(t);
    });

    testWidgets('serveur injoignable : message, réessai automatique toutes les 10 s, Réessayer, Configuration sous code admin', (t) async {
      ecran(t);
      final env = _Env()..api.licence = () => const LicenceLookup.failure(LicenceIssue.unreachable, 'timeout');
      await t.pumpWidget(env.app(LancementScreen(services: env.services)));
      await laisser(t);
      expect(find.text('Le serveur ne répond pas'), findsOneWidget);
      expect(find.textContaining('La licence n\'est pas en cause'), findsOneWidget);
      expect(find.text('Connexion au serveur impossible'), findsOneWidget);
      expect(find.text('Nouvel essai automatique dans 10 s'), findsOneWidget);
      expect(find.text('Continuer hors ligne'), findsNothing); // décision client
      await t.pump(const Duration(seconds: 3));
      expect(find.text('Nouvel essai automatique dans 7 s'), findsOneWidget);
      expect(env.api.licences, 1);
      await t.pump(const Duration(seconds: 7));
      await laisser(t);
      expect(env.api.licences, 2); // réessai automatique

      await t.tap(find.byKey(const Key('lancement_reessayer')));
      await laisser(t);
      expect(env.api.licences, 3);

      env.adminOk = false;
      await t.tap(find.byKey(const Key('lancement_configuration')));
      await laisser(t);
      expect(env.adminChecks, 1);
      expect(find.text('CONFIGURATION (test)'), findsNothing);
      env.adminOk = true;
      await t.tap(find.byKey(const Key('lancement_configuration')));
      await laisser(t);
      expect(find.text('CONFIGURATION (test)'), findsOneWidget);
      await fermer(t);
    });

    testWidgets('serveur revenu pendant le réessai : on continue normalement', (t) async {
      ecran(t);
      final env = _Env()..api.licence = () => const LicenceLookup.failure(LicenceIssue.unreachable, null);
      await t.pumpWidget(env.app(LancementScreen(services: env.services)));
      await laisser(t);
      env.api.licence = () => LicenceLookup.found(LicenceModel(id: '1', dateStart: '', dateEnd: '2099-12-31', typeLicence: ''));
      await t.pump(const Duration(seconds: 10));
      await t.pump(const Duration(seconds: 2));
      await laisser(t);
      expect(find.byType(ConnexionScreen), findsOneWidget);
      await fermer(t);
    });

    testWidgets('mode borne actif : ouverture directe de la borne (même si le serveur ne répond pas)', (t) async {
      ecran(t);
      BorneReglages.courant.value = const BorneConfig(actif: true, login: 'borne');
      final env = _Env()..api.licence = () => const LicenceLookup.failure(LicenceIssue.unreachable, null);
      await t.pumpWidget(env.app(LancementScreen(services: env.services)));
      await laisser(t);
      expect(find.text('Borne libre-service — ouverture de la borne…'), findsOneWidget);
      expect(find.text('Le serveur ne répond pas'), findsNothing);
      await t.pump(const Duration(milliseconds: 1300));
      expect(env.bornes, 1);
      await fermer(t);
    });

    testWidgets('appareil non configuré : « Première utilisation » puis Configuration (sans code)', (t) async {
      ecran(t);
      SharedPreferences.setMockInitialValues({'local_ip': '', 'remote_ip': ''});
      final env = _Env();
      await t.pumpWidget(env.app(LancementScreen(services: env.services)));
      await laisser(t);
      expect(find.text('Première utilisation'), findsOneWidget);
      expect(env.api.licences, 0);
      await t.tap(find.byKey(const Key('configurer_serveur')));
      await laisser(t);
      expect(env.adminChecks, 0);
      expect(find.text('CONFIGURATION (test)'), findsOneWidget);
      await fermer(t);
    });

    testWidgets('« Rester connecté » : connexion automatique puis accueil ; mot de passe changé → message', (t) async {
      ecran(t);
      SharedPreferences.setMockInitialValues({'stay_connected': true, 'saved_login': 'kone.awa'});
      FlutterSecureStorage.setMockInitialValues({IdentifiantsSecurises.cleSure: _mdp});
      var env = _Env();
      await t.pumpWidget(env.app(LancementScreen(services: env.services)));
      await laisser(t);
      expect(find.text('Connexion automatique'), findsOneWidget);
      await t.pump(const Duration(milliseconds: 1300));
      await laisser(t);
      expect(find.text('ACCUEIL (test)'), findsOneWidget);
      await fermer(t);

      SharedPreferences.setMockInitialValues({'stay_connected': true, 'saved_login': 'kone.awa'});
      FlutterSecureStorage.setMockInitialValues({IdentifiantsSecurises.cleSure: 'ancien'});
      env = _Env();
      await t.pumpWidget(env.app(LancementScreen(services: env.services)));
      await laisser(t);
      await t.pump(const Duration(milliseconds: 1300));
      await laisser(t);
      expect(find.text('Votre mot de passe a changé, saisissez-le à nouveau.'), findsOneWidget);
      await fermer(t);
    });

    testWidgets('terminal partagé : pas de connexion automatique au lancement', (t) async {
      ecran(t);
      SharedPreferences.setMockInitialValues({
        'stay_connected': true,
        'saved_login': 'kone.awa',
        ConnexionReglages.cle: '{"rapide":false,"partage":true}',
      });
      FlutterSecureStorage.setMockInitialValues({IdentifiantsSecurises.cleSure: _mdp});
      final env = _Env();
      await t.pumpWidget(env.app(LancementScreen(services: env.services)));
      await laisser(t);
      await t.pump(const Duration(milliseconds: 1300));
      await laisser(t);
      expect(env.api.logins, isEmpty);
      expect(find.byType(ConnexionScreen), findsOneWidget);
      expect(find.byKey(const Key('rester_connecte')), findsNothing);
      await fermer(t);
    });
  });

  // -------------------------------------------------------------------------
  group('Connexion (proposition A)', () {
    Future<_Env> ouvrir(WidgetTester t, {Size taille = const Size(360, 800), ThemeData? theme}) async {
      ecran(t, taille: taille);
      final env = _Env();
      await env.settings.loadSettings();
      await t.pumpWidget(env.app(ConnexionScreen(services: env.services), theme: theme));
      await laisser(t);
      return env;
    }

    testWidgets('serveur connecté, connexion OK : identifiants mémorisés, utilisateur noté avec son rôle, officine gardée', (t) async {
      final env = await ouvrir(t);
      expect(find.text('Serveur local connecté'), findsOneWidget);
      expect(find.text('192.168.1.50:8080 · prestige'), findsOneWidget);
      expect(find.byType(LogoOfficine), findsOneWidget);
      expect(find.text('Version 1.2.0 · Assistance : 07 08 08 00 68'), findsOneWidget);

      // Contrôles de saisie.
      await t.tap(find.byKey(const Key('se_connecter')));
      await t.pump();
      expect(find.text('Saisissez votre identifiant'), findsOneWidget);
      expect(env.api.logins, isEmpty);

      await t.enterText(find.byKey(const Key('connexion_login')), 'kone.awa');
      await t.enterText(find.byKey(const Key('connexion_mdp')), _mdp);
      await t.tap(find.byKey(const Key('rester_connecte')));
      await t.pump();
      // Anti double appui.
      await t.tap(find.byKey(const Key('se_connecter')));
      await t.tap(find.byKey(const Key('se_connecter')), warnIfMissed: false);
      await t.pump();
      await laisser(t);
      expect(env.api.logins, ['kone.awa']);
      expect(find.text('ACCUEIL (test)'), findsOneWidget);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('stay_connected'), isTrue);
      expect(prefs.getString(IdentifiantsSecurises.cleClaire), isNull); // jamais en clair
      expect(prefs.getString(ConnexionReglages.cleOfficine), 'PHARMACIE LES PALMIERS');
      final u = (await DerniersUtilisateurs.lire()).single;
      expect((u.login, u.nom, u.role), ('kone.awa', 'Awa Koné', 'Caissière'));
      expect(prefs.getString(DerniersUtilisateurs.cle), isNot(contains(_mdp)));

      // Lancement suivant : nom de l'officine (et croix verte) affichés dès le démarrage.
      await fermer(t);
      final env2 = _Env()..api.bloquerLicence = Completer<void>();
      await t.pumpWidget(env2.app(LancementScreen(services: env2.services)));
      await laisser(t);
      expect(find.text('PHARMACIE LES PALMIERS'), findsOneWidget);
      expect(find.byKey(const Key('croix_verte')), findsOneWidget);
      expect(find.byType(LogoOfficine), findsOneWidget);
      env2.api.bloquerLicence!.complete();
      await fermer(t);
    });

    testWidgets('mot de passe faux : message clair (icône + texte), mot de passe vidé, identifiant gardé', (t) async {
      final env = await ouvrir(t);
      await t.enterText(find.byKey(const Key('connexion_login')), 'kone.awa');
      await t.enterText(find.byKey(const Key('connexion_mdp')), 'faux');
      await t.tap(find.byKey(const Key('se_connecter')));
      await laisser(t);
      expect(find.text('Identifiant ou mot de passe incorrect. Vérifiez les majuscules et réessayez.'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(t.widget<TextFormField>(find.byKey(const Key('connexion_mdp'))).controller!.text, '');
      expect(t.widget<TextFormField>(find.byKey(const Key('connexion_login'))).controller!.text, 'kone.awa');
      expect(find.textContaining('DioException'), findsNothing);
      expect(env.auth.user, isNull);
      await fermer(t);
    });

    testWidgets('serveur injoignable : point rouge + texte, réessai automatique 10 s, Réessayer', (t) async {
      ecran(t);
      final env = _Env()..serveurRepond = false;
      await env.settings.loadSettings();
      await t.pumpWidget(env.app(ConnexionScreen(services: env.services)));
      await laisser(t);
      expect(find.text('Serveur injoignable'), findsOneWidget);
      expect(find.text('Nouvel essai dans 10 s'), findsOneWidget);
      expect(find.byKey(const Key('encadre_injoignable')), findsOneWidget);
      expect(find.text('Continuer hors ligne'), findsNothing);
      final avant = env.sondes.length;
      await t.pump(const Duration(seconds: 10));
      await laisser(t);
      expect(env.sondes.length, avant + 1);
      env.serveurRepond = true;
      await t.ensureVisible(find.byKey(const Key('reessayer_serveur')));
      await t.tap(find.byKey(const Key('reessayer_serveur')));
      await laisser(t);
      expect(find.text('Serveur local connecté'), findsOneWidget);
      expect(find.byKey(const Key('encadre_injoignable')), findsNothing);

      // Le serveur tombe pendant la connexion : message « vos identifiants ne sont pas en cause ».
      env.serveurRepond = false;
      env.api.comptes.clear();
      await t.enterText(find.byKey(const Key('connexion_login')), 'kone.awa');
      await t.enterText(find.byKey(const Key('connexion_mdp')), _mdp);
      await t.tap(find.byKey(const Key('se_connecter')));
      await laisser(t);
      expect(find.byKey(const Key('encadre_injoignable')), findsOneWidget);
      expect(find.text('Identifiant ou mot de passe incorrect. Vérifiez les majuscules et réessayez.'), findsNothing);
      await fermer(t);
    });

    testWidgets('changer de serveur : code administrateur exigé, puis choix local / distant', (t) async {
      SharedPreferences.setMockInitialValues({'local_ip': '192.168.1.50', 'remote_ip': '41.207.10.9'});
      final env = await ouvrir(t);
      env.adminOk = false;
      await t.tap(find.byKey(const Key('changer_serveur')));
      await laisser(t);
      expect(env.adminChecks, 1);
      expect(find.text('Changer de serveur'), findsNothing);

      env.adminOk = true;
      await t.tap(find.byKey(const Key('changer_serveur')));
      await laisser(t);
      expect(find.text('Changer de serveur'), findsOneWidget);
      expect(find.text('Serveur local · utilisé'), findsOneWidget);
      expect(find.text('Répond'), findsNWidgets(2));
      await t.tap(find.byKey(const Key('serveur_distant')));
      await laisser(t);
      expect(env.settings.isRemote, isTrue);
      expect(find.text('Serveur distant connecté'), findsOneWidget);
      expect(env.sondes.last, '41.207.10.9');
      await fermer(t);
    });

    testWidgets('terminal partagé : « Rester connecté » masqué et jamais enregistré', (t) async {
      ConnexionReglages.courant.value = const ConnexionConfig(terminalPartage: true);
      final env = await ouvrir(t);
      expect(find.byKey(const Key('rester_connecte')), findsNothing);
      expect(find.text('Rester connecté'), findsNothing);
      expect(find.byKey(const Key('terminal_partage_info')), findsOneWidget);
      await t.enterText(find.byKey(const Key('connexion_login')), 'kone.awa');
      await t.enterText(find.byKey(const Key('connexion_mdp')), _mdp);
      await t.tap(find.byKey(const Key('se_connecter')));
      await laisser(t);
      expect(find.text('ACCUEIL (test)'), findsOneWidget);
      expect((await SharedPreferences.getInstance()).getBool('stay_connected'), isFalse);
      expect(await IdentifiantsSecurises.instance.lire(), isNull);
      expect(env.auth.user, isNotNull);
      await fermer(t);
    });

    testWidgets('tablette paysage : deux colonnes ; thème sombre ; 360 px : sans débordement', (t) async {
      await ouvrir(t, taille: const Size(1280, 800));
      final logo = t.getRect(find.byType(LogoOfficine));
      final champ = t.getRect(find.byKey(const Key('connexion_mdp')));
      expect(logo.right < 640, isTrue);
      expect(champ.left > 640, isTrue);
      expect(champ.width <= 440, isTrue);
      expect(t.takeException(), isNull);
      await fermer(t);

      await ouvrir(t, theme: ThemeData.dark());
      expect(t.takeException(), isNull);
      final texte = t.widget<Text>(find.text('Connexion'));
      expect(texte.style!.color, Teintes.sombre.texte);
      await fermer(t);
    });

    testWidgets('cibles tactiles ≥ 48 px (œil, rester connecté, se connecter, changer)', (t) async {
      await ouvrir(t);
      for (final k in ['voir_mdp', 'rester_connecte', 'se_connecter', 'changer_serveur']) {
        final r = t.getRect(find.byKey(Key(k)));
        expect(r.height >= 48, isTrue, reason: k);
        expect(r.width >= 48, isTrue, reason: k);
      }
      await fermer(t);
    });
  });

  // -------------------------------------------------------------------------
  group('Option C « Qui êtes-vous ? »', () {
    Future<void> noterSept() async {
      final base = DateTime(2026, 10, 12, 8);
      final noms = ['Diallo Fatou', 'Bamba Jean', 'Touré Mariam', 'Yao Serge', 'Koné Awa', 'Kouassi Paul', 'Traoré Ali'];
      final logins = ['diallo.fatou', 'bamba.jean', 'toure.mariam', 'yao.serge', 'kone.awa', 'kouassi.paul', 'traore.ali'];
      for (var i = 0; i < noms.length; i++) {
        await DerniersUtilisateurs.noter(login: logins[i], nom: noms[i], role: i.isEven ? 'Caissière' : 'Vendeur', date: base.add(Duration(minutes: i)));
      }
    }

    testWidgets('les 6 derniers, sans défilement à 360 × 800, avec le rôle ; le 7e plus ancien est retiré', (t) async {
      ecran(t);
      ConnexionReglages.courant.value = const ConnexionConfig(connexionRapide: true);
      await noterSept();
      final env = _Env();
      await env.settings.loadSettings();
      await t.pumpWidget(env.app(const LoginScreen())); // point d'entrée unique (déconnexion, licence…)
      await laisser(t);
      // Le LoginScreen de la nouvelle interface ouvre « Qui êtes-vous ? »… mais ses services sont ceux de l'appli :
      // on vérifie seulement la grille ici.
      expect(find.byType(QuiEtesVousScreen), findsOneWidget);
      expect(find.text('Qui êtes-vous ?'), findsOneWidget);
      final grille = find.byKey(const Key('grille_utilisateurs'));
      expect(find.descendant(of: grille, matching: find.byType(Scrollable)), findsNothing);
      for (final l in ['bamba.jean', 'toure.mariam', 'yao.serge', 'kone.awa', 'kouassi.paul', 'traore.ali']) {
        final tuile = find.byKey(Key('utilisateur_$l'));
        expect(tuile, findsOneWidget, reason: l);
        final r = t.getRect(tuile);
        expect(r.bottom <= 800 && r.top >= 0 && r.right <= 360, isTrue, reason: '$l visible sans défilement');
        expect(r.height >= 48, isTrue);
        expect(find.byKey(Key('role_$l')), findsOneWidget);
      }
      expect(find.byKey(const Key('utilisateur_diallo.fatou')), findsNothing); // 7e : retiré
      expect(t.getRect(find.byKey(const Key('utilisateur_autre'))).bottom <= 800, isTrue);
      expect(find.text('Caissière'), findsWidgets);
      expect(find.text('Vendeur'), findsWidgets);
      expect(t.takeException(), isNull);
      await fermer(t);
    });

    test('PIN de 4 chiffres : haché (PBKDF2 salé), règles anti-PIN faibles, mot de passe gardé par utilisateur', () async {
      final p = PinPersonnel.instance;
      expect(await p.definir('kone.awa', '1234', _mdp), isNotNull);
      expect(await p.definir('kone.awa', '1111', _mdp), isNotNull);
      expect(await p.definir('kone.awa', '1357', _mdp), isNull);
      expect(await p.definir('kone.awa', '13579', _mdp), contains('4 chiffres'));
      expect(await p.definir('kone.awa', '12a4', _mdp), isNotNull);
      expect(await p.definir('kone.awa', '2580', _mdp), isNull);
      expect(await p.definir('yao.serge', '7391', 'Autre#7'), isNull);
      const coffre = FlutterSecureStorage();
      final tout = await coffre.readAll();
      final empreintes = tout.entries.where((e) => e.key.startsWith('pin_perso_v1_')).map((e) => e.value).toList();
      expect(empreintes, hasLength(2));
      for (final e in empreintes) {
        expect(EmpreintePin.estEmpreinte(e), isTrue);
        expect(e.contains('2580') || e.contains('7391'), isFalse);
      }
      expect(empreintes[0] == empreintes[1], isFalse);
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys()) {
        expect('${prefs.get(k)}', isNot(anyOf(contains('2580'), contains(_mdp))));
      }
      expect(await p.verifier('kone.awa', '2580'), (ResultatPin.accepte, _mdp));
      expect(await p.verifier('yao.serge', '7391'), (ResultatPin.accepte, 'Autre#7'));
      expect((await p.verifier('inconnu', '2580')).$1, ResultatPin.absent);
      expect(await p.effacerTout(), 2);
      expect((await p.verifier('kone.awa', '2580')).$1, ResultatPin.absent);
    });

    testWidgets('PIN correct : connexion au serveur avec le mot de passe gardé ; 3 PIN faux → mot de passe exigé', (t) async {
      ecran(t);
      ConnexionReglages.courant.value = const ConnexionConfig(connexionRapide: true);
      await DerniersUtilisateurs.noter(login: 'kone.awa', nom: 'Awa Koné', role: 'Caissière');
      await t.runAsync(() => PinPersonnel.instance.definir('kone.awa', '2580', _mdp));
      final env = _Env();
      await env.settings.loadSettings();
      await t.pumpWidget(env.app(QuiEtesVousScreen(services: env.services)));
      await laisser(t);
      await t.tap(find.byKey(const Key('utilisateur_kone.awa')));
      await laisser(t);
      expect(find.text('kone.awa · Caissière'), findsOneWidget);
      expect(find.byKey(const Key('touche_5')), findsOneWidget);
      expect(t.getRect(find.byKey(const Key('touche_5'))).height, greaterThanOrEqualTo(64));

      Future<void> taper(String code) async {
        for (final c in code.split('')) {
          await t.tap(find.byKey(Key('touche_$c')));
          await t.pump();
        }
        await laisser(t);
      }

      await taper('1357');
      expect(find.text('Code incorrect · 2 essais restants'), findsOneWidget);
      await taper('9999');
      expect(find.text('Code incorrect · 1 essai restant'), findsOneWidget);
      await taper('0000');
      expect(find.text('3 codes incorrects : saisissez votre mot de passe.'), findsOneWidget);
      expect(find.byKey(const Key('utilisateur_mdp')), findsOneWidget);
      expect(find.byKey(const Key('touche_5')), findsNothing);
      expect(env.api.logins, isEmpty); // aucun essai serveur avec un PIN faux
      // Le PIN reste verrouillé même avec le bon code.
      expect((await PinPersonnel.instance.verifier('kone.awa', '2580')).$1, ResultatPin.verrouille);

      // Mot de passe complet : le verrou est levé.
      await t.enterText(find.byKey(const Key('utilisateur_mdp')), _mdp);
      await t.tap(find.byKey(const Key('utilisateur_se_connecter')));
      await laisser(t);
      expect(find.text('ACCUEIL (test)'), findsOneWidget);
      expect(await PinPersonnel.instance.erreurs('kone.awa'), 0);
      await fermer(t);

      // Connexion par PIN : le serveur est appelé avec le mot de passe gardé.
      final env2 = _Env();
      await env2.settings.loadSettings();
      await t.pumpWidget(env2.app(QuiEtesVousScreen(services: env2.services)));
      await laisser(t);
      await t.tap(find.byKey(const Key('utilisateur_kone.awa')));
      await laisser(t);
      await taper('2580');
      expect(env2.api.logins, ['kone.awa']);
      expect(find.text('ACCUEIL (test)'), findsOneWidget);
      await fermer(t);
    });

    testWidgets('mot de passe changé sur le serveur : PIN et mot de passe gardé effacés', (t) async {
      ecran(t);
      ConnexionReglages.courant.value = const ConnexionConfig(connexionRapide: true);
      await DerniersUtilisateurs.noter(login: 'kone.awa', nom: 'Awa Koné', role: 'Caissière');
      await t.runAsync(() => PinPersonnel.instance.definir('kone.awa', '2580', 'ancien'));
      final env = _Env();
      await env.settings.loadSettings();
      await t.pumpWidget(env.app(UtilisateurConnexionScreen(utilisateur: (await t.runAsync(DerniersUtilisateurs.lire))!.first, services: env.services)));
      await laisser(t);
      for (final c in '2580'.split('')) {
        await t.tap(find.byKey(Key('touche_$c')));
        await t.pump();
      }
      await laisser(t);
      expect(find.text('Votre mot de passe a changé : saisissez-le. Le code PIN sera à recréer.'), findsOneWidget);
      expect(await PinPersonnel.instance.actif('kone.awa'), isFalse);
      await fermer(t);
    });

    testWidgets('première connexion par mot de passe : PIN personnel proposé (facultatif) et enregistré', (t) async {
      ecran(t);
      ConnexionReglages.courant.value = const ConnexionConfig(connexionRapide: true);
      final env = _Env();
      await env.settings.loadSettings();
      await t.pumpWidget(env.app(ConnexionScreen(services: env.services)));
      await laisser(t);
      await t.enterText(find.byKey(const Key('connexion_login')), 'kone.awa');
      await t.enterText(find.byKey(const Key('connexion_mdp')), _mdp);
      await t.tap(find.byKey(const Key('se_connecter')));
      await laisser(t);
      expect(find.text('Code PIN personnel'), findsOneWidget);
      await t.enterText(find.byKey(const Key('pin_perso_nouveau')), '1234');
      await t.enterText(find.byKey(const Key('pin_perso_confirmation')), '1234');
      await t.tap(find.byKey(const Key('pin_perso_enregistrer')));
      await laisser(t);
      expect(find.text('Le code par défaut n\'est pas autorisé.'), findsOneWidget);
      await t.enterText(find.byKey(const Key('pin_perso_nouveau')), '2580');
      await t.enterText(find.byKey(const Key('pin_perso_confirmation')), '2580');
      await t.tap(find.byKey(const Key('pin_perso_enregistrer')));
      await laisser(t);
      expect(find.text('ACCUEIL (test)'), findsOneWidget);
      expect(await PinPersonnel.instance.actif('kone.awa'), isTrue);
      await fermer(t);
    });
  });

  // -------------------------------------------------------------------------
  group('Assistance', () {
    test('format et contrôle du numéro', () {
      expect(Assistance.formater('0708080068'), '07 08 08 00 68');
      expect(Assistance.refus('07 08 08 00 68'), isNull);
      expect(Assistance.refus('+225 07 08 08 00 68'), isNull);
      expect(Assistance.refus('abc'), isNotNull);
      expect(Assistance.refus('123'), isNotNull);
      expect(Assistance.refus(''), isNotNull);
    });

    testWidgets('modifiable dans les Paramètres, affiché sur la connexion, bouton Appeler (repli : copie)', (t) async {
      ecran(t);
      final env = _Env();
      await env.settings.loadSettings();
      await t.pumpWidget(env.app(const Scaffold(body: SingleChildScrollView(child: ReglagesEcranConnexion()))));
      await laisser(t);
      expect(t.widget<TextField>(find.byKey(const Key('reglage_assistance'))).controller!.text, '0708080068');
      await t.enterText(find.byKey(const Key('reglage_assistance')), 'abc');
      await t.pump();
      await t.enterText(find.byKey(const Key('reglage_assistance')), '12');
      await t.pump();
      expect(find.text('De 8 à 15 chiffres'), findsOneWidget);
      expect(t.widget<ElevatedButton>(find.byKey(const Key('reglage_assistance_enregistrer'))).onPressed, isNull);
      await t.enterText(find.byKey(const Key('reglage_assistance')), '07 01 02 03 04');
      await t.pump();
      await t.tap(find.byKey(const Key('reglage_assistance_enregistrer')));
      await laisser(t);
      expect(ConnexionReglages.courant.value.assistance, '0701020304');
      expect((await SharedPreferences.getInstance()).getString(ConnexionReglages.cle), contains('0701020304'));
      await fermer(t);

      await t.pumpWidget(env.app(ConnexionScreen(services: env.services)));
      await laisser(t);
      expect(find.text('Version 1.2.0 · Assistance : 07 01 02 03 04'), findsOneWidget);
      await t.ensureVisible(find.byKey(const Key('appeler_assistance')));
      await t.tap(find.byKey(const Key('appeler_assistance')));
      await laisser(t);
      expect(appels.last.toString(), 'tel:0701020304');

      composeurDisponible = false;
      String? copie;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copie = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await t.tap(find.byKey(const Key('appeler_assistance')));
      await laisser(t);
      expect(copie, '0701020304');
      expect(find.textContaining('numéro 07 01 02 03 04 copié'), findsOneWidget);
      await fermer(t);
    });

    testWidgets('réglages admin : terminal partagé active la connexion rapide et efface « Rester connecté »', (t) async {
      ecran(t);
      SharedPreferences.setMockInitialValues({'stay_connected': true, 'saved_login': 'kone.awa'});
      FlutterSecureStorage.setMockInitialValues({IdentifiantsSecurises.cleSure: _mdp});
      final env = _Env();
      await env.settings.loadSettings();
      await t.pumpWidget(env.app(const Scaffold(body: SingleChildScrollView(child: ReglagesEcranConnexion()))));
      await laisser(t);
      expect(ConnexionReglages.courant.value.connexionRapide, isFalse); // désactivée par défaut
      expect(ConnexionReglages.courant.value.terminalPartage, isFalse);
      await t.tap(find.byKey(const Key('reglage_terminal_partage')));
      await laisser(t);
      expect(ConnexionReglages.courant.value.terminalPartage, isTrue);
      expect(ConnexionReglages.courant.value.connexionRapide, isTrue);
      expect(env.settings.stayConnected, isFalse);
      expect(await IdentifiantsSecurises.instance.lire(), isNull);
      await fermer(t);
    });
  });

  // -------------------------------------------------------------------------
  group('Ancienne interface inchangée', () {
    testWidgets('interrupteur désactivé : écran de démarrage d\'origine (2 s d\'attente) et connexion d\'origine', (t) async {
      ecran(t);
      InterfaceVersion.useNew.value = false;
      addTearDown(() => InterfaceVersion.useNew.value = true);
      final env = _Env();
      await t.pumpWidget(env.app(const SplashScreen()));
      expect(find.byType(AncienSplashScreen), findsOneWidget);
      expect(find.byType(LancementScreen), findsNothing);
      expect(find.text('Démarrage...'), findsOneWidget);
      await t.pump(const Duration(milliseconds: 1900));
      expect(env.api.licences, 0); // attente visuelle de 2 s conservée
      await t.pump(const Duration(milliseconds: 200));
      await laisser(t);
      expect(env.api.licences, 1);
      await t.pump(const Duration(seconds: 1));
      expect(find.byType(AncienLoginScreen), findsOneWidget);
      expect(find.byType(ConnexionScreen), findsNothing);
      expect(find.text('Local'), findsOneWidget);
      expect(find.text('Distant'), findsOneWidget);
      expect(find.text('Rester connecté'), findsOneWidget);
      await fermer(t);
    });

    testWidgets('interrupteur activé : LoginScreen et SplashScreen ouvrent les nouveaux écrans', (t) async {
      ecran(t);
      final env = _Env();
      await env.settings.loadSettings();
      await t.pumpWidget(env.app(const LoginScreen()));
      await laisser(t);
      expect(find.byType(ConnexionScreen), findsOneWidget);
      expect(find.byType(AncienLoginScreen), findsNothing);
      await fermer(t);
      await t.pumpWidget(env.app(const SplashScreen()));
      expect(find.byType(LancementScreen), findsOneWidget);
      await fermer(t);
    });
  });
}
