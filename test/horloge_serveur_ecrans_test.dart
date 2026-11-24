// 5.5.0 — Transmission du serveur du 24/11/2026 (plan/24112026) : HEURE DU SERVEUR FAUSSE, écrans (faux services).
//  - Écran de connexion : aucune lecture de GET v1/horloge/public en fonctionnement normal (aucune requête de plus) ;
//    après un refus 423 : bandeau « Heure du serveur fausse » si BLOQUE (heure du serveur affichée) ; OK ou
//    REGULARISATION : rien (débloqué) ; serveur ancien / pas de réponse : bandeau sans l'heure ; aucune lecture quand
//    le serveur ne répond pas ; la connexion reste possible.
//  - Ventes : refus 423 affiché avec le message du serveur, sans « Réessayer » (aucune relance).
//  - Modules (ErreurVue / BandeauErreur) : titre « Heure du serveur fausse », message tel quel, jamais « Serveur
//    injoignable ».
// Données fictives uniquement.
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/borne/borne_config.dart';
import 'package:prestige_vente_app/connexion/connexion_commun.dart';
import 'package:prestige_vente_app/connexion/connexion_reglages.dart';
import 'package:prestige_vente_app/connexion/connexion_screen.dart';
import 'package:prestige_vente_app/connexion/pin_personnel.dart';
import 'package:prestige_vente_app/interface_version.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/licence_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/serveur/client_prestige.dart';
import 'package:prestige_vente_app/serveur/erreur_vue.dart';
import 'package:prestige_vente_app/serveur/horloge_serveur.dart';
import 'package:prestige_vente_app/serveur/panne_serveur.dart';
import 'package:prestige_vente_app/services/identifiants_securises.dart';
import 'package:prestige_vente_app/ventes/common/vente_messages.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'outils/version_installee.dart';

const _msg = 'Opération refusée : l\'heure du serveur est fausse. L\'administrateur doit la corriger sur le serveur.';

class _Env {
  final api = ApiService(baseUrl: 'http://localhost');
  final settings = SettingsProvider();
  late final licence = LicenceProvider(api);
  late final auth = AuthProvider(api);
  bool serveurRepond = true;
  HorlogePublique? horloge;
  int lectures = 0;

  ConnexionServices get services => ConnexionServices(
        sonde: (s, ip) async => serveurRepond,
        horloge: (s) async {
          lectures++;
          return horloge;
        },
        accueil: () => const Scaffold(body: Text('ACCUEIL (test)')),
      );

  Widget app(Widget home) => MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          Provider<ApiService>.value(value: api),
          ChangeNotifierProvider<LicenceProvider>.value(value: licence),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ],
        child: MaterialApp(home: home),
      );
}

void main() {
  setUp(() {
    simulerVersionInstallee();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    ConnexionReglages.courant.value = const ConnexionConfig();
    ConnexionReglages.officine.value = '';
    BorneReglages.courant.value = const BorneConfig();
    PinPersonnel.instance = PinPersonnel(iterations: 1000);
    IdentifiantsSecurises.instance = IdentifiantsSecurises();
    InterfaceVersion.useNew.value = true;
    HorlogeServeur.instance.reinitialiser();
  });

  Future<_Env> ouvrir(WidgetTester t, {HorlogePublique? horloge, bool repond = true, bool bloque = true}) async {
    HorlogeServeur.instance.reinitialiser();
    if (bloque) HorlogeServeur.instance.signaler(_msg);
    t.view.physicalSize = const Size(720, 1600);
    t.view.devicePixelRatio = 2.0;
    addTearDown(t.view.reset);
    final env = _Env()
      ..horloge = horloge
      ..serveurRepond = repond;
    await env.settings.loadSettings();
    await t.pumpWidget(env.app(ConnexionScreen(services: env.services)));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    return env;
  }

  Future<void> fermer(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 11));
  }

  group('Écran de connexion', () {
    testWidgets('BLOQUE : bandeau avec l\'heure du serveur, connexion toujours proposée', (t) async {
      final env = await ouvrir(t, horloge: const HorlogePublique(EtatHorloge.bloque, '24/11/2026 20:52'));
      expect(env.lectures, 1);
      expect(find.byKey(const Key('bandeau_horloge_serveur')), findsOneWidget);
      expect(find.text(titreHorlogeBloquee), findsOneWidget);
      expect(find.textContaining('24/11/2026 20:52'), findsOneWidget);
      expect(find.byKey(const Key('se_connecter')), findsOneWidget);
      expect(find.byKey(const Key('encadre_injoignable')), findsNothing, reason: 'pas une panne');
      expect(HorlogeServeur.instance.bloquee, isTrue);
      await fermer(t);
    });

    testWidgets('fonctionnement normal : aucune lecture de horloge/public, aucun bandeau', (t) async {
      final env = await ouvrir(t, horloge: const HorlogePublique(EtatHorloge.bloque, ''), bloque: false);
      expect(env.lectures, 0, reason: 'aucune requête de plus au démarrage');
      expect(find.byKey(const Key('bandeau_horloge_serveur')), findsNothing);
      await fermer(t);
    });

    testWidgets('après un 423 : OK ou REGULARISATION → débloqué, aucun bandeau ; pas de réponse → bandeau sans l\'heure',
        (t) async {
      for (final h in [
        const HorlogePublique(EtatHorloge.ok, '24/11/2026 20:52'),
        const HorlogePublique(EtatHorloge.regularisation, '24/11/2026 20:52'),
      ]) {
        final env = await ouvrir(t, horloge: h);
        expect(env.lectures, 1);
        expect(find.byKey(const Key('bandeau_horloge_serveur')), findsNothing, reason: '$h');
        expect(HorlogeServeur.instance.bloquee, isFalse);
        await fermer(t);
      }
      final env = await ouvrir(t, horloge: null);
      expect(env.lectures, 1);
      expect(find.byKey(const Key('bandeau_horloge_serveur')), findsOneWidget);
      expect(find.textContaining('(serveur :'), findsNothing);
      await fermer(t);
    });

    testWidgets('serveur qui ne répond pas : aucune lecture de l\'horloge', (t) async {
      final env = await ouvrir(t, horloge: const HorlogePublique(EtatHorloge.bloque, ''), repond: false);
      expect(env.lectures, 0);
      expect(find.byKey(const Key('bandeau_horloge_serveur')), findsNothing);
      await fermer(t);
    });

    test('services de test sans lecteur d\'horloge : aucun appel réseau', () async {
      final r = await ConnexionServices(sonde: (s, ip) async => true).lireHorloge(SettingsProvider());
      expect(r, isNull);
    });
  });

  group('Messages', () {
    testWidgets('vente : refus 423 = message du serveur, sans « Réessayer »', (t) async {
      var relances = 0;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () => showVenteFailure(c, const VenteRefused<void>(_msg, code: VenteRefused.codeHorloge), onRetry: () => relances++),
              child: const Text('go'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('go'));
      await t.pump();
      expect(find.text(_msg), findsOneWidget);
      expect(find.text('Réessayer'), findsNothing);
      expect(relances, 0);
    });

    testWidgets('modules : titre « Heure du serveur fausse », message tel quel, jamais « Serveur injoignable »', (t) async {
      await t.pumpWidget(const MaterialApp(home: Scaffold(body: Column(children: [
        Expanded(child: ErreurVue(erreur: HorlogeBloquee(_msg))),
        BandeauErreur(erreur: HorlogeBloquee(_msg)),
      ]))));
      expect(find.text(titreHorlogeBloquee), findsOneWidget);
      expect(find.text(_msg), findsNWidgets(2));
      expect(find.text(MessagesServeur.titreInjoignable), findsNothing);
      expect(find.text('Se reconnecter'), findsNothing);
    });
  });
}
