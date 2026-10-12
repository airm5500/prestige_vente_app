// Aperçus PNG RÉELS (rendu Flutter de l'application) du nouveau lancement et de la nouvelle connexion,
// écrits dans docs/maquettes/apercus/app_connexion_*.png.
// Hors de la suite de la CI (ignoré sans la variable APERCUS). Pour régénérer :
//   APERCUS=1 flutter test test/outils/apercus_connexion_test.dart --update-goldens
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/licence_lookup.dart';
import 'package:prestige_vente_app/api/models/licence_model.dart';
import 'package:prestige_vente_app/api/models/user.dart';
import 'package:prestige_vente_app/borne/borne_config.dart';
import 'package:prestige_vente_app/connexion/connexion_commun.dart';
import 'package:prestige_vente_app/connexion/connexion_reglages.dart';
import 'package:prestige_vente_app/connexion/connexion_screen.dart';
import 'package:prestige_vente_app/connexion/lancement_screen.dart';
import 'package:prestige_vente_app/connexion/pin_personnel.dart';
import 'package:prestige_vente_app/connexion/qui_etes_vous_screen.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/licence_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _actif = Platform.environment.containsKey('APERCUS');

class _Api extends ApiService {
  _Api() : super(baseUrl: 'http://localhost');
  LicenceLookup Function() licence = () => LicenceLookup.found(LicenceModel(id: '1', dateStart: '', dateEnd: '2099-12-31', typeLicence: ''));
  Completer<void>? bloquer;

  @override
  Future<LicenceLookup> lookupLicence() async {
    if (bloquer != null) await bloquer!.future;
    return licence();
  }

  @override
  Future<User?> login(String login, String password) async => null;
}

Future<void> _polices() async {
  final dossier = '${Platform.environment['FLUTTER_ROOT'] ?? File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.parent.path}'
      '/bin/cache/artifacts/material_fonts';
  Future<ByteData> lire(String f) async => ByteData.sublistView(await File('$dossier/$f').readAsBytes());
  final roboto = FontLoader('Roboto');
  for (final f in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']) {
    roboto.addFont(lire(f));
  }
  await roboto.load();
  // Styles sans famille (boutons) : police par défaut des tests remplacée par Roboto, comme sur l'appareil.
  final defaut = FontLoader('FlutterTest');
  for (final f in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']) {
    defaut.addFont(lire(f));
  }
  await defaut.load();
  await (FontLoader('MaterialIcons')..addFont(lire('MaterialIcons-Regular.otf'))).load();
}

void main() {
  setUpAll(() async {
    if (_actif) await _polices();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'remote_ip': '41.207.10.9', ConnexionReglages.cleOfficine: 'PHARMACIE LES PALMIERS'});
    FlutterSecureStorage.setMockInitialValues({});
    ConnexionReglages.courant.value = const ConnexionConfig();
    ConnexionReglages.officine.value = 'PHARMACIE LES PALMIERS';
    BorneReglages.courant.value = const BorneConfig();
    PinPersonnel.instance = PinPersonnel(iterations: 1000);
  });

  Future<void> capture(WidgetTester t, String nom, Widget home,
      {_Api? api,
      Size taille = const Size(360, 800),
      ThemeData? theme,
      Future<void> Function()? avant,
      Duration attente = const Duration(milliseconds: 400)}) async {
    t.view.physicalSize = taille * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final a = api ?? _Api();
    final settings = SettingsProvider();
    await settings.loadSettings();
    ConnexionServices.instance = ConnexionServices(
      adminCheck: (_) async => true,
      sonde: (s, ip) async => !nom.contains('injoignable'),
      chargements: (_) async {},
      accueil: () => const Scaffold(),
    );
    addTearDown(() => ConnexionServices.instance = const ConnexionServices());
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        Provider<ApiService>.value(value: a),
        ChangeNotifierProvider<LicenceProvider>(create: (_) => LicenceProvider(a)),
        ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider(a)),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: home,
      ),
    ));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    if (avant != null) await avant();
    await t.pump(attente);
    await t.runAsync(() async {
      for (final e in find.byType(Image).evaluate()) {
        await precacheImage((e.widget as Image).image, e);
      }
    });
    await t.pump();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('../../docs/maquettes/apercus/app_connexion_$nom.png'));
    if (a.bloquer != null && !a.bloquer!.isCompleted) {
      a.bloquer!.complete();
      await t.pump();
    }
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 11));
  }

  testWidgets('aperçus', (t) async {
    final bloque = _Api()..bloquer = Completer<void>();
    await capture(t, 'lancement', const LancementScreen(), api: bloque);

    await capture(t, 'lancement_injoignable', const LancementScreen(),
        api: _Api()..licence = () => const LicenceLookup.failure(LicenceIssue.unreachable, null));
    await capture(t, 'lancement_licence', const LancementScreen(),
        api: _Api()..licence = () => LicenceLookup.found(LicenceModel(id: '1', dateStart: '', dateEnd: '2026-09-30', typeLicence: '')));

    await capture(t, 'formulaire', const ConnexionScreen(), avant: () async {
      await t.enterText(find.byKey(const Key('connexion_login')), 'kone.awa');
      await t.enterText(find.byKey(const Key('connexion_mdp')), 'Secret!42');
    });
    await capture(t, 'erreur', const ConnexionScreen(), avant: () async {
      await t.enterText(find.byKey(const Key('connexion_login')), 'kone.awa');
      await t.enterText(find.byKey(const Key('connexion_mdp')), 'faux');
      await t.tap(find.byKey(const Key('se_connecter')));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
    });
    await capture(t, 'serveur_injoignable', const ConnexionScreen());
    await capture(t, 'tablette', const ConnexionScreen(), taille: const Size(1280, 800));
    await capture(t, 'sombre', const ConnexionScreen(), theme: ThemeData.dark());

    ConnexionReglages.courant.value = const ConnexionConfig(connexionRapide: true);
    final base = DateTime.now().subtract(const Duration(hours: 2));
    final gens = [
      ('diallo.fatou', 'Diallo Fatou', 'Vendeuse'),
      ('bamba.jean', 'Bamba Jean', 'Préparateur'),
      ('toure.mariam', 'Touré Mariam', 'Caissière'),
      ('yao.serge', 'Yao Serge', 'Vendeur'),
      ('admin', 'Kouassi Paul', 'Administrateur'),
      ('kone.awa', 'Koné Awa', 'Caissière'),
    ];
    for (var i = 0; i < gens.length; i++) {
      await t.runAsync(() => DerniersUtilisateurs.noter(login: gens[i].$1, nom: gens[i].$2, role: gens[i].$3, date: base.subtract(Duration(days: 5 - i))));
    }
    await capture(t, 'qui_etes_vous', const QuiEtesVousScreen());
    await t.runAsync(() => PinPersonnel.instance.definir('kone.awa', '2580', 'Secret!42'));
    await capture(t, 'pin', UtilisateurConnexionScreen(utilisateur: DernierUtilisateur(login: 'kone.awa', nom: 'Koné Awa', role: 'Caissière', date: base)),
        avant: () async {
      for (final c in ['2', '5']) {
        await t.tap(find.byKey(Key('touche_$c')));
        await t.pump();
      }
    });
  }, skip: !_actif);
}
