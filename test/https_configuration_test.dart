// 4.1.0 — HTTPS pour l'accès au serveur par Internet (ÉCRANS + E2E).
//   - Nouvelle interface (Réglages › Connexion au serveur) : choix http / https du serveur local et du serveur
//     distant, « https://… » collé dans le champ, port 8080 ↔ 443 qui suit le protocole (un autre port est gardé),
//     test de connexion et enregistrement à l'adresse https ; valeurs http inchangées.
//   - Interface d'origine (Configuration) : mêmes choix, enregistrement réel contre le faux serveur Prestige.
//   - Application entière configurée en https : TOUTES les requêtes (licence, connexion, accueil, surveillance,
//     synchro…) partent vers la même adresse https.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/licence_lookup.dart';
import 'package:prestige_vente_app/api/models/licence_model.dart';
import 'package:prestige_vente_app/api/models/payment_method_qr.dart';
import 'package:prestige_vente_app/api/models/user.dart';
import 'package:prestige_vente_app/parametres/parametres_logic.dart';
import 'package:prestige_vente_app/parametres/parametres_screen.dart';
import 'package:prestige_vente_app/parametres/parametres_services.dart';
import 'package:prestige_vente_app/pointage/pointage_repository.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/licence_provider.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/screens/auth/settings_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'outils/app_e2e.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(baseUrl: 'http://localhost');

  @override
  Future<User?> login(String login, String password) async =>
      User(userId: 'u1', login: login, firstName: 'Awa', lastName: 'Kouassi', officineName: 'PHCIE TEST');

  @override
  Future<LicenceLookup> lookupLicence() async =>
      LicenceLookup.found(LicenceModel(id: 'LIC-42', dateStart: '2026-01-01', dateEnd: '2099-12-31', typeLicence: 'ANNUELLE'));

  @override
  Future<List<PaymentMethodQr>> getPaymentMethodsWithQr() async => [];
}

/// Réglages sans réseau : chaque test de serveur est noté « adresse|port ».
class _Settings extends SettingsProvider {
  final sondes = <String>[];
  bool reponse = true;
  @override
  String get pingError => reponse ? '' : 'Connexion sécurisée (HTTPS) impossible : certificat du serveur refusé.';

  @override
  Future<bool> ping(String ip, String port, String appName) async {
    sondes.add('$ip|$port');
    return reponse;
  }
}

Finder _choix(String cle, String protocole) => find.descendant(of: find.byKey(Key(cle)), matching: find.text(protocole));

/// Nouvelle interface : bascule http:// ↔ https:// au début du champ, appuyée si besoin.
Future<void> _choisir(WidgetTester t, String cle, String protocole) async {
  await t.ensureVisible(find.byKey(Key(cle)));
  await t.pumpAndSettle();
  if (_bascule(t, cle) != protocole) await t.tap(find.byKey(Key(cle)));
  await t.pumpAndSettle();
  expect(_bascule(t, cle), protocole);
}

/// Protocole affiché par la bascule (« https:// » → « https »).
String _bascule(WidgetTester t, String cle) => t
    .widget<Text>(find.descendant(of: find.byKey(Key(cle)), matching: find.textContaining('://')))
    .data!
    .replaceAll('://', '');

String _texte(WidgetTester t, Key cle) => t.widget<TextField>(find.byKey(cle)).controller!.text;

void main() {
  group('Nouvelle interface : Réglages › Connexion au serveur', () {
    Future<_Settings> ouvrir(WidgetTester t, Map<String, Object> prefs) async {
      t.view.physicalSize = const Size(720, 2600); // page entière visible (barre Enregistrer comprise)
      t.view.devicePixelRatio = 2.0;
      addTearDown(t.view.reset);
      SharedPreferences.setMockInitialValues(prefs);
      final settings = _Settings();
      await settings.loadSettings();
      final api = _FakeApi();
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          Provider<ApiService>.value(value: api),
          ChangeNotifierProvider(create: (_) => LicenceProvider(api)),
          ChangeNotifierProvider(create: (_) => AuthProvider(api)),
          ChangeNotifierProvider(create: (_) => SaleProvider(api)),
        ],
        child: MaterialApp(
          home: ParametresScreen(
            services: ParametresServices(
              adminCheck: (_) async => true,
              printTestTicket: (_) async {},
              hardwareInfo: () async => const {},
              pointageRepository: MemoryPointageRepository(),
              afterServerSaved: (_) {},
            ),
          ),
        ),
      ));
      await t.pumpAndSettle();
      final f = find.byKey(Key('rubrique_${Rubrique.connexion.name}'));
      await t.scrollUntilVisible(f, 120, scrollable: find.byType(Scrollable).first);
      await t.tap(f);
      await t.pumpAndSettle();
      return settings;
    }

    testWidgets('anciens réglages : http sélectionné, valeurs inchangées, rien à enregistrer', (t) async {
      await ouvrir(t, {'local_ip': '192.168.1.50', 'remote_ip': '41.207.10.9', 'port': '8080'});
      expect(_texte(t, const Key('ip_locale')), '192.168.1.50');
      expect(_texte(t, const Key('port')), '8080');
      for (final cle in ['protocole_local', 'protocole_distant']) {
        expect(_bascule(t, cle), 'http', reason: cle);
      }
      expect(find.byKey(const Key('connexion_enregistrer')), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('serveur local en https : port 443, test et enregistrement à l\'adresse https', (t) async {
      final s = await ouvrir(t, {'local_ip': '192.168.1.50', 'port': '8080'});
      await _choisir(t, 'protocole_local', 'https');
      expect(_texte(t, const Key('port')), '443', reason: 'port par défaut du https');
      await t.enterText(find.byKey(const Key('ip_locale')), 'prestige.ma-pharmacie.ci');
      await t.pumpAndSettle();
      expect(find.textContaining('Format invalide'), findsNothing);

      await t.ensureVisible(find.text('TESTER LA CONNEXION'));
      await t.tap(find.text('TESTER LA CONNEXION'));
      await t.pumpAndSettle();
      expect(s.sondes.last, 'https://prestige.ma-pharmacie.ci|443');

      await t.tap(find.byKey(const Key('connexion_enregistrer')));
      await t.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('local_ip'), 'https://prestige.ma-pharmacie.ci');
      expect(prefs.getString('port'), '443');
      expect(s.baseUrl, 'https://prestige.ma-pharmacie.ci:443/prestige/api/v1');

      // Retour en http : 8080 revient ; un port choisi à la main est gardé.
      await _choisir(t, 'protocole_local', 'http');
      expect(_texte(t, const Key('port')), '8080');
      await t.enterText(find.byKey(const Key('port')), '8181');
      await _choisir(t, 'protocole_local', 'https');
      expect(_texte(t, const Key('port')), '8181');
      expect(t.takeException(), isNull);
    });

    testWidgets('serveur distant : « https://… » collé règle le choix ; 443 pour lui, 8080 pour le local', (t) async {
      final s = await ouvrir(t, {'local_ip': '192.168.1.50', 'port': '8080'});
      await t.enterText(find.byKey(const Key('ip_distante')), 'https://prestige.ma-pharmacie.ci');
      await t.pumpAndSettle();
      expect(_texte(t, const Key('ip_distante')), 'prestige.ma-pharmacie.ci', reason: 'protocole retiré du champ');
      expect(_bascule(t, 'protocole_distant'), 'https');
      expect(find.textContaining('Port 443 par défaut'), findsOneWidget);
      expect(_texte(t, const Key('port')), '8080', reason: 'le port du serveur local ne change pas');

      await t.ensureVisible(find.text('TESTER LA CONNEXION'));
      await t.tap(find.text('TESTER LA CONNEXION'));
      await t.pumpAndSettle();
      expect(s.sondes, ['192.168.1.50|8080', 'https://prestige.ma-pharmacie.ci|443']);
      expect(find.textContaining('IP distante joignable (https://prestige.ma-pharmacie.ci)'), findsOneWidget);

      await t.tap(find.byKey(const Key('connexion_enregistrer')));
      await t.pumpAndSettle();
      expect(s.remoteIp, 'https://prestige.ma-pharmacie.ci');
      expect(s.localIp, '192.168.1.50');
      expect(s.baseUrl, 'http://192.168.1.50:8080/prestige/api/v1', reason: 'mode local : inchangé');
      await s.setConnectionMode(true);
      expect(s.baseUrl, 'https://prestige.ma-pharmacie.ci:443/prestige/api/v1');
      expect(ParametresSummary.connexion(s), '192.168.1.50:8080 · prestige · IP distante');
    });

    testWidgets('certificat refusé : message affiché, rien d\'enregistré', (t) async {
      final s = await ouvrir(t, {'local_ip': '192.168.1.50', 'port': '8080'});
      s.reponse = false;
      await _choisir(t, 'protocole_local', 'https');
      await t.enterText(find.byKey(const Key('ip_locale')), 'prestige.ma-pharmacie.ci');
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('connexion_enregistrer')));
      await t.pumpAndSettle();
      expect(find.textContaining('certificat du serveur refusé'), findsWidgets);
      expect((await SharedPreferences.getInstance()).getString('local_ip'), '192.168.1.50', reason: 'ancienne valeur gardée');
      expect(s.localIp, '192.168.1.50');
    });
  });

  group('Interface d\'origine : Configuration', () {
    testWidgets('https choisi : port 443, enregistrement réel, application relancée en https', (t) async {
      TailleEcran.sunmiV2s.appliquer(t);
      final app = AppE2E();
      await app.preparer(interfaceNouvelle: false, prefs: const {'local_ip': '', 'remote_ip': ''});
      await app.lancer(t);
      expect(await app.attendreQue(t, find.byType(SettingsScreen)), isTrue);
      await app.attendre(t);

      await t.enterText(find.widgetWithText(TextFormField, 'Adresse IP Locale'), FauxServeurPrestige.hoteMemoire);
      await t.tap(_choix('protocole_local', 'https'));
      await t.pump();
      final port = find.widgetWithText(TextFormField, 'Port');
      expect(t.widget<TextFormField>(port).controller!.text, '443');
      // Distant : « https:// » saisi dans le champ, retiré et reporté sur le choix.
      await t.enterText(find.widgetWithText(TextFormField, 'Adresse IP Distante (Optionnel)'), 'https://prestige.ma-pharmacie.ci');
      await t.pump();
      expect(find.text('prestige.ma-pharmacie.ci'), findsOneWidget);
      expect(t.takeException(), isNull);

      final zone = find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Scrollable)).first;
      await app.defilerJusqua(t, find.text('Enregistrer'), zone: zone);
      app.serveur.tentatives.clear();
      await t.tap(find.text('Enregistrer'));
      await app.attendre(t, const Duration(seconds: 3));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('local_ip'), 'https://${FauxServeurPrestige.hoteMemoire}');
      expect(prefs.getString('remote_ip'), 'https://prestige.ma-pharmacie.ci');
      expect(prefs.getString('port'), '443');
      final premiere = app.serveur.tentatives.first;
      expect((premiere.scheme, premiere.host, premiere.port, premiere.path),
          ('https', FauxServeurPrestige.hoteMemoire, 443, '/prestige/api/v1/user/auth'), reason: 'test du serveur avant enregistrement');
      expect(app.serveur.tentatives.map((u) => '${u.scheme}://${u.host}:${u.port}').toSet(),
          {'https://${FauxServeurPrestige.hoteMemoire}:443'}, reason: 'test du serveur puis relance (licence…) en https');
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });
  });

  testWidgets('E2E : application configurée en https, toutes les requêtes vers la même adresse https', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final app = AppE2E();
    await app.preparer(prefs: const {'local_ip': 'https://${FauxServeurPrestige.hoteMemoire}', 'port': '443'});
    await app.lancer(t);
    expect(await app.seConnecter(t), isTrue);
    await app.attendre(t, const Duration(seconds: 3));
    final adresses = app.serveur.tentatives.map((u) => '${u.scheme}://${u.host}:${u.port}${u.path.substring(0, 16)}').toSet();
    expect(adresses, {'https://${FauxServeurPrestige.hoteMemoire}:443/prestige/api/v1'});
    final chemins = app.serveur.tentatives.map((u) => u.path).toSet();
    expect(chemins, containsAll(['/prestige/api/v1/licence/find', '/prestige/api/v1/user/auth']));
    expect(app.serveur.connexions, greaterThanOrEqualTo(1));
    expect(app.serveur.refusSession, 0, reason: 'le cookie de session suit l\'adresse https');
    await app.fermer(t);
  });
}
