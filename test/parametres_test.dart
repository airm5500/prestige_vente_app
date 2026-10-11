// Nouveaux réglages par rubriques : navigation, résumés, cadenas / code admin (une fois par visite),
// contrôles IP / port / nom d'application, barre Enregistrer seulement si modifié, avant connexion, 360 px.
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
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(baseUrl: 'http://localhost');

  @override
  Future<User?> login(String login, String password) async =>
      User(userId: 'u1', login: login, firstName: 'Awa', lastName: 'Kouassi', officineName: 'PHCIE TEST');

  @override
  Future<void> logout() async {}

  @override
  Future<LicenceLookup> lookupLicence() async => LicenceLookup.found(LicenceModel(
        id: 'LIC-42',
        dateStart: '2026-01-01',
        dateEnd: DateTime.now().add(const Duration(days: 21)).toIso8601String().substring(0, 10),
        typeLicence: 'ANNUELLE',
      ));

  @override
  Future<List<PaymentMethodQr>> getPaymentMethodsWithQr() async =>
      [PaymentMethodQr(id: '10', name: 'WAVE'), PaymentMethodQr(id: '4', name: 'CHEQUE')];
}

/// Réglages sans réseau : le test de connexion est simulé.
class _FakeSettings extends SettingsProvider {
  bool pingOk = true;
  String pingReason = '';
  final pinged = <String>[];

  @override
  String get pingError => pingReason;

  @override
  Future<bool> ping(String ip, String port, String appName) async {
    pinged.add('$ip:$port/$appName');
    return pingOk;
  }
}

class _Env {
  final settings = _FakeSettings();
  final api = _FakeApi();
  late final auth = AuthProvider(api);
  late final licence = LicenceProvider(api);
  late final sale = SaleProvider(api);
  int adminChecks = 0;
  bool adminAnswer = true;
  int printed = 0;
  int saved = 0;
  final pointage = MemoryPointageRepository();

  ParametresServices get services => ParametresServices(
        adminCheck: (_) async {
          adminChecks++;
          return adminAnswer;
        },
        printTestTicket: (_) async => printed++,
        hardwareInfo: () async => {'manufacturer': 'SUNMI', 'model': 'V2s', 'android': '11', 'sdk': 30},
        pointageRepository: pointage,
        afterServerSaved: (_) => saved++,
        organiserAccueil: () => const Scaffold(body: Text('ORGANISER (test)')),
      );

  Widget app() => MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          Provider<ApiService>.value(value: api),
          ChangeNotifierProvider<LicenceProvider>.value(value: licence),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<SaleProvider>.value(value: sale),
        ],
        child: MaterialApp(home: ParametresScreen(services: services)),
      );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(720, 1400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  Future<_Env> start(WidgetTester tester, {String? login}) async {
    phone(tester);
    final env = _Env();
    await env.settings.loadSettings();
    if (login != null) await env.auth.login(login, 'x');
    await tester.pumpWidget(env.app());
    await tester.pumpAndSettle();
    return env;
  }

  Future<void> back(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Retour'));
    await tester.pumpAndSettle();
  }

  Future<void> seek(WidgetTester tester, Finder f) async {
    // Rubrique au-dessus de la partie visible : on repart du haut de la liste.
    if (f.evaluate().isEmpty) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
      await tester.pumpAndSettle();
    }
    await tester.scrollUntilVisible(f, 120, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, Rubrique r) async {
    await seek(tester, find.byKey(Key('rubrique_${r.name}')));
    await tester.tap(find.byKey(Key('rubrique_${r.name}')));
    await tester.pumpAndSettle();
  }

  group('Contrôles de saisie', () {
    test('IP, port et nom d\'application', () {
      expect(ParametresChecks.host('192.168.1.20', required: true), isNull);
      expect(ParametresChecks.host('41.207.300.9', required: true), isNotNull);
      expect(ParametresChecks.host('192.168.1', required: true), isNotNull);
      expect(ParametresChecks.host('', required: true), 'Ce champ est requis');
      expect(ParametresChecks.host('', required: false), isNull);
      expect(ParametresChecks.host('pharmacie.ddns.net', required: false), isNull);
      expect(ParametresChecks.host('mauvais nom', required: false), isNotNull);
      expect(ParametresChecks.port('8080'), isNull);
      expect(ParametresChecks.port('0'), isNotNull);
      expect(ParametresChecks.port('65536'), isNotNull);
      expect(ParametresChecks.port(''), isNotNull);
      expect(ParametresChecks.appName('prestige'), isNull);
      expect(ParametresChecks.appName('pres tige'), isNotNull);
      expect(ParametresChecks.appName('a/b'), isNotNull);
    });

    test('recherche sans accents', () {
      expect(rubriqueMatches(Rubrique.impression, '', 'ticket'), isTrue);
      expect(rubriqueMatches(Rubrique.connexion, '', 'ticket'), isFalse);
      expect(rubriqueMatches(Rubrique.securite, '', 'securite'), isTrue);
      expect(rubriqueMatches(Rubrique.stock, '', 'PEREMPTION'), isTrue);
    });
  });

  testWidgets('Avant connexion : rubriques, résumés, grisées expliquées, pas de déconnexion', (tester) async {
    final env = await start(tester);
    expect(find.text('Réglages'), findsOneWidget);
    expect(find.text('Non connecté'), findsOneWidget);
    expect(find.text('58 mm · 1 ticket · QR code'), findsOneWidget);
    expect(find.text('192.168.1.50:8080 · prestige'), findsOneWidget);
    for (final r in Rubrique.values) {
      await seek(tester, find.byKey(Key('rubrique_${r.name}')));
    }
    expect(find.text('Disponible après la connexion'), findsOneWidget);
    expect(find.text('Se déconnecter'), findsNothing);

    // Rubrique grisée : explication, pas de code demandé.
    await open(tester, Rubrique.securite);
    expect(env.adminChecks, 0);
    expect(find.textContaining('Sécurité : Disponible après la connexion'), findsOneWidget);

    // Connexion au serveur toujours accessible (code administrateur).
    await open(tester, Rubrique.connexion);
    expect(env.adminChecks, 1);
    expect(find.text('TESTER LA CONNEXION'), findsOneWidget);
    await back(tester);

    // Impression sans code.
    await open(tester, Rubrique.impression);
    expect(find.text('IMPRIMER UN TICKET D\'ESSAI'), findsOneWidget);
    await tester.tap(find.text('IMPRIMER UN TICKET D\'ESSAI'));
    await tester.pumpAndSettle();
    expect(env.printed, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Connecté (admin) : déconnexion avec confirmation, recherche', (tester) async {
    await start(tester, login: 'admin');
    expect(find.text('Awa Kouassi'), findsOneWidget);
    await seek(tester, find.text('Se déconnecter'));
    expect(find.text('Disponible après la connexion'), findsNothing);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('recherche_reglage')), 'ticket');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rubrique_impression')), findsOneWidget);
    expect(find.byKey(const Key('rubrique_connexion')), findsNothing);
    expect(find.text('Se déconnecter'), findsNothing);

    await tester.enterText(find.byKey(const Key('recherche_reglage')), 'zzzz');
    await tester.pumpAndSettle();
    expect(find.textContaining('Aucun réglage'), findsOneWidget);
    await tester.tap(find.text('Effacer la recherche'));
    await tester.pumpAndSettle();

    await seek(tester, find.byKey(const Key('se_deconnecter')));
    await tester.tap(find.byKey(const Key('se_deconnecter')));
    await tester.pumpAndSettle();
    expect(find.text('Se déconnecter ?'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(find.text('Réglages'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cadenas : code demandé une seule fois par visite ; refus = rubrique fermée', (tester) async {
    final env = await start(tester, login: 'admin');
    env.adminAnswer = false;
    await open(tester, Rubrique.ventes);
    expect(env.adminChecks, 1);
    expect(find.text('Modes de paiement proposés'.toUpperCase()), findsNothing);
    expect(find.byIcon(Icons.lock), findsWidgets);

    env.adminAnswer = true;
    await open(tester, Rubrique.ventes);
    expect(env.adminChecks, 2);
    expect(find.text('MODES DE PAIEMENT PROPOSÉS'), findsOneWidget);
    expect(find.text('WAVE'), findsOneWidget);
    expect(find.text('Code administrateur vérifié'), findsOneWidget);
    await back(tester);

    for (final r in [Rubrique.stock, Rubrique.equipe, Rubrique.securite, Rubrique.connexion]) {
      await open(tester, r);
      expect(find.text(r.title), findsOneWidget);
      await back(tester);
    }
    expect(env.adminChecks, 2);
    expect(find.byIcon(Icons.lock_open), findsNWidgets(5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Connexion : contrôles, Enregistrer seulement si modifié, Annuler', (tester) async {
    final env = await start(tester);
    await open(tester, Rubrique.connexion);
    expect(find.byKey(const Key('connexion_enregistrer')), findsNothing);

    await tester.enterText(find.byKey(const Key('ip_distante')), '41.207.300.9');
    await tester.pumpAndSettle();
    expect(find.textContaining('Format invalide'), findsOneWidget);
    expect(find.text('Corrigez l\'IP distante pour enregistrer'), findsOneWidget);
    var save = tester.widget<ElevatedButton>(find.byKey(const Key('connexion_enregistrer')));
    expect(save.onPressed, isNull);

    await tester.enterText(find.byKey(const Key('ip_distante')), '');
    await tester.enterText(find.byKey(const Key('port')), '70000');
    await tester.pumpAndSettle();
    expect(find.text('Port de 1 à 65535'), findsOneWidget);
    save = tester.widget<ElevatedButton>(find.byKey(const Key('connexion_enregistrer')));
    expect(save.onPressed, isNull);

    // Annuler : valeurs enregistrées, barre masquée.
    await tester.tap(find.text('ANNULER'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('connexion_enregistrer')), findsNothing);

    // Modification valide : enregistrement après test du serveur.
    await tester.enterText(find.byKey(const Key('ip_locale')), '192.168.1.20');
    await tester.enterText(find.byKey(const Key('nom_appli')), ' prestige ');
    await tester.pumpAndSettle();
    save = tester.widget<ElevatedButton>(find.byKey(const Key('connexion_enregistrer')));
    expect(save.onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('connexion_enregistrer')));
    await tester.pumpAndSettle();
    expect(env.saved, 1);
    expect(env.settings.localIp, '192.168.1.20');
    expect(env.settings.appName, 'prestige');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('local_ip'), '192.168.1.20');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Connexion : échec d\'enregistrement si le serveur ne répond pas', (tester) async {
    final env = await start(tester);
    await open(tester, Rubrique.connexion);
    env.settings
      ..pingOk = false
      ..pingReason = 'Aucun serveur ne répond à 10.0.0.9:8080 (Wifi, IP, serveur éteint).';
    await tester.enterText(find.byKey(const Key('ip_locale')), '10.0.0.9');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('connexion_enregistrer')));
    await tester.pumpAndSettle();
    expect(env.saved, 0);
    expect(env.settings.localIp, '192.168.1.50');
    expect(find.textContaining('Non enregistré'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Connexion : test détaillé (serveur, application, licence)', (tester) async {
    final env = await start(tester);
    await open(tester, Rubrique.connexion);
    await tester.tap(find.text('TESTER LA CONNEXION'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Serveur joignable'), findsOneWidget);
    expect(find.textContaining('Application Prestige trouvée'), findsOneWidget);
    expect(find.textContaining('Licence valide'), findsOneWidget);

    env.settings
      ..pingOk = false
      ..pingReason = 'Un serveur répond à 192.168.1.50:8080, mais l\'application "prestige" n\'y est pas.';
    await tester.tap(find.text('TESTER LA CONNEXION'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Serveur joignable'), findsOneWidget);
    expect(find.textContaining('n\'y est pas'), findsOneWidget);
    expect(find.text('Licence : non vérifiée'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Impression : choix appliqués immédiatement, compteurs bornés, valeurs par défaut', (tester) async {
    final env = await start(tester);
    await open(tester, Rubrique.impression);
    await tester.tap(find.text('80 mm'));
    await tester.tap(find.text('Code-barres'));
    await tester.pumpAndSettle();
    expect(env.settings.paperWidth, 80);
    expect(env.settings.ticketCodeType, 'BARCODE');

    final plus = find.descendant(of: find.byKey(const Key('tickets_vente')), matching: find.byIcon(Icons.add));
    for (var i = 0; i < 4; i++) {
      await tester.tap(plus);
      await tester.pumpAndSettle();
    }
    expect(env.settings.numberOfTickets, 3);

    await tester.scrollUntilVisible(find.text('Rétablir les valeurs par défaut'), 200);
    await tester.tap(find.text('Rétablir les valeurs par défaut'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rétablir'));
    await tester.pumpAndSettle();
    expect(env.settings.paperWidth, 58);
    expect(env.settings.numberOfTickets, 1);
    await back(tester);
    expect(find.text('58 mm · 1 ticket · QR code'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Apparence : présentation commune et Organiser l\'accueil protégé', (tester) async {
    // Choix de la présentation réservé au compte administrateur (retour client).
    final env = await start(tester, login: 'admin');
    await open(tester, Rubrique.apparence);
    await tester.tap(find.byKey(const Key('presentation_guided')));
    await tester.pumpAndSettle();
    expect(await PresentationPrefs.load(), ListPresentation.guided);
    await tester.tap(find.text('Organiser l\'accueil'));
    await tester.pumpAndSettle();
    expect(env.adminChecks, 1);
    expect(find.text('ORGANISER (test)'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    await back(tester);
    expect(find.text('Présentation C · organiser l\'accueil'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('360 px : toutes les rubriques s\'ouvrent sans débordement', (tester) async {
    final env = await start(tester, login: 'admin');
    await env.licence.checkLicence();
    await tester.pumpAndSettle();
    for (final r in Rubrique.values) {
      await open(tester, r);
      expect(tester.takeException(), isNull, reason: r.title);
      await back(tester);
    }
    expect(find.text('Valide · 21 jours'), findsOneWidget);
  });
}
