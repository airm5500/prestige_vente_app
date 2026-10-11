// Mot de passe mémorisé (« Rester connecté ») : stockage sécurisé (flutter_secure_storage) au lieu de la clé
// `saved_password` en clair dans SharedPreferences. Migration transparente, échec du stockage sûr sans perte
// de la connexion automatique, effacement, connexion automatique et pré-remplissage inchangés, journal sans
// mot de passe.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/user.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/screens/auth/login_screen.dart';
import 'package:prestige_vente_app/services/identifiants_securises.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const mdp = 'Secret!42';

/// Stockage sûr en panne (Keystore indisponible) ; [relu] : relecture différente de l'écriture.
class CoffreEnPanne implements CoffreIdentifiants {
  final bool relectureFausse;
  final Map<String, String> donnees = {};
  int ecritures = 0;
  CoffreEnPanne({this.relectureFausse = false});

  @override
  Future<String?> lire(String cle) async {
    if (relectureFausse) return 'autre';
    throw PlatformException(code: 'KeyStoreException', message: 'Keystore indisponible ($mdp)');
  }

  @override
  Future<void> ecrire(String cle, String valeur) async {
    ecritures++;
    if (relectureFausse) {
      donnees[cle] = valeur;
      return;
    }
    throw Exception('écriture impossible : $valeur');
  }

  @override
  Future<void> effacer(String cle) async => throw PlatformException(code: 'KeyStoreException');
}

class FakeApi extends ApiService {
  FakeApi() : super(baseUrl: 'http://localhost');
  final logins = <(String, String)>[];

  @override
  Future<User?> login(String login, String password) async {
    logins.add((login, password));
    return password == mdp ? User(userId: 'u1', login: login, firstName: 'Awa', lastName: 'Kouassi', officineName: 'PHCIE TEST') : null;
  }

  @override
  Future<void> logout() async {}
}

Future<String?> lireSur() => const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true)).read(key: IdentifiantsSecurises.cleSure);

/// Aucune valeur des préférences en clair ne contient le mot de passe.
Future<void> aucuneTraceEnClair() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  expect(prefs.containsKey(IdentifiantsSecurises.cleClaire), isFalse);
  for (final k in prefs.getKeys()) {
    expect('${prefs.get(k)}', isNot(contains(mdp)), reason: 'clé $k');
  }
}

void main() {
  late JournalTerminal journal;
  late List<String> console;
  DebugPrintCallback? ancienPrint;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    journal = JournalTerminal(store: MemoryJournalStore());
    IdentifiantsSecurises.instance = IdentifiantsSecurises(journal: () => journal);
    console = [];
    ancienPrint = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => console.add(m ?? '');
  });
  tearDown(() => debugPrint = ancienPrint!);

  Future<String> journalTexte() async {
    await journal.idle;
    return [for (final e in await journal.lire()) '${e.action} ${e.motif} ${e.refLocale} ${e.refServeur}'].join('\n');
  }

  group('Migration', () {
    test('clé en clair → stockage sûr, relue, puis SUPPRIMÉE ; aucune trace en clair', () async {
      SharedPreferences.setMockInitialValues({'saved_login': 'awa', 'saved_password': mdp, 'stay_connected': true});
      expect(await IdentifiantsSecurises.instance.migrer(), isTrue);
      expect(await lireSur(), mdp);
      await aucuneTraceEnClair();
      expect(await IdentifiantsSecurises.instance.lire(), mdp);
      // le reste des préférences est intact
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('saved_login'), 'awa');
      expect(prefs.getBool('stay_connected'), isTrue);
      expect(await journalTexte(), contains('stockage sécurisé'));
      expect(await journalTexte(), isNot(contains(mdp)));
    });

    test('au démarrage (chargement des réglages) : migration faite', () async {
      SharedPreferences.setMockInitialValues({'saved_login': 'awa', 'saved_password': mdp, 'stay_connected': true});
      final s = SettingsProvider();
      await s.loadSettings();
      expect(s.stayConnected, isTrue);
      expect(s.savedLogin, 'awa');
      expect(await lireSur(), mdp);
      await aucuneTraceEnClair();
      expect(await s.getSavedPassword(), mdp);
    });

    test('rien à migrer : aucun accès inutile, idempotent', () async {
      final c = CoffreEnPanne();
      final svc = IdentifiantsSecurises(coffre: c, journal: () => journal);
      expect(await svc.migrer(), isTrue);
      expect(await svc.migrer(), isTrue);
      expect(c.ecritures, 0);
      expect(await journalTexte(), isEmpty);
    });

    test('stockage sûr en échec → clé en clair GARDÉE (connexion auto conservée), journalisé sans mot de passe, nouvel essai au lancement suivant', () async {
      SharedPreferences.setMockInitialValues({'saved_login': 'awa', 'saved_password': mdp, 'stay_connected': true});
      final panne = IdentifiantsSecurises(coffre: CoffreEnPanne(), journal: () => journal);
      expect(await panne.migrer(), isFalse);
      expect((await SharedPreferences.getInstance()).getString('saved_password'), mdp);
      expect(await panne.lire(), mdp);
      final j = await journalTexte();
      expect(j, contains('Migration du mot de passe'));
      expect(j, contains('stockage sécurisé indisponible'));
      expect(j, isNot(contains(mdp)));
      expect(console.join('\n'), isNot(contains(mdp)));
      expect(console.join('\n'), contains('nouvel essai au prochain lancement'));

      // connexion automatique toujours possible avec le stockage en panne
      IdentifiantsSecurises.instance = panne;
      final api = FakeApi();
      expect(await AuthProvider(api).tryAutoLogin(), isTrue);
      expect(api.logins.single, ('awa', mdp));

      // lancement suivant : le Keystore répond → migration faite
      final ok = IdentifiantsSecurises(journal: () => journal);
      expect(await ok.migrer(), isTrue);
      expect(await lireSur(), mdp);
      await aucuneTraceEnClair();
    });

    test('relecture différente → clé en clair gardée', () async {
      SharedPreferences.setMockInitialValues({'saved_password': mdp});
      final svc = IdentifiantsSecurises(coffre: CoffreEnPanne(relectureFausse: true), journal: () => journal);
      expect(await svc.migrer(), isFalse);
      expect((await SharedPreferences.getInstance()).getString('saved_password'), mdp);
      expect(await svc.lire(), mdp);
      expect(await journalTexte(), contains('relecture'));
    });
  });

  group('Écriture et effacement', () {
    test('« Rester connecté » coché : stockage sûr seulement ; décoché : effacé partout', () async {
      final s = SettingsProvider();
      await s.saveCredentials('awa', mdp, true);
      expect(s.savedLogin, 'awa');
      expect(await lireSur(), mdp);
      await aucuneTraceEnClair();
      expect(await s.getSavedPassword(), mdp);

      await s.saveCredentials('awa', mdp, false);
      expect(s.savedLogin, '');
      expect(await lireSur(), isNull);
      expect(await s.getSavedPassword(), '');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('stay_connected'), isFalse);
      expect(prefs.containsKey('saved_login'), isFalse);
      await aucuneTraceEnClair();
    });

    test('« décoché » efface aussi une ancienne clé en clair non migrée', () async {
      SharedPreferences.setMockInitialValues({'saved_login': 'awa', 'saved_password': mdp, 'stay_connected': true});
      FlutterSecureStorage.setMockInitialValues({IdentifiantsSecurises.cleSure: 'ancien'});
      await IdentifiantsSecurises.instance.effacer();
      expect(await lireSur(), isNull);
      expect((await SharedPreferences.getInstance()).containsKey('saved_password'), isFalse);
      expect(await IdentifiantsSecurises.instance.lire(), isNull);
    });

    test('écriture avec le stockage sûr en panne : ancien comportement (en clair), migré au lancement suivant', () async {
      final panne = IdentifiantsSecurises(coffre: CoffreEnPanne(), journal: () => journal);
      await panne.ecrire(mdp);
      expect((await SharedPreferences.getInstance()).getString('saved_password'), mdp);
      expect(await panne.lire(), mdp);
      expect(await journalTexte(), isNot(contains(mdp)));
      expect(console.join('\n'), isNot(contains(mdp)));
      final ok = IdentifiantsSecurises(journal: () => journal);
      expect(await ok.lire(), mdp);
      await aucuneTraceEnClair();
    });

    test('nouveau mot de passe enregistré après un repli : c\'est lui qui est relu', () async {
      FlutterSecureStorage.setMockInitialValues({IdentifiantsSecurises.cleSure: 'ancien'});
      final panne = IdentifiantsSecurises(coffre: CoffreEnPanne(relectureFausse: true), journal: () => journal);
      await panne.ecrire(mdp);
      expect(await IdentifiantsSecurises(journal: () => journal).lire(), mdp);
    });
  });

  group('Connexion automatique et écran de connexion', () {
    test('connexion auto inchangée (mot de passe migré) ; déconnexion = « Rester connecté » désactivé', () async {
      SharedPreferences.setMockInitialValues({'saved_login': 'awa', 'saved_password': mdp, 'stay_connected': true});
      final api = FakeApi();
      final auth = AuthProvider(api);
      expect(await auth.tryAutoLogin(), isTrue);
      expect(auth.status, AuthStatus.Authenticated);
      expect(api.logins.single, ('awa', mdp));
      await aucuneTraceEnClair();

      await auth.logout();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('stay_connected'), isFalse);
      expect(prefs.getString('saved_login'), 'awa'); // comme avant : seul « Rester connecté » est coupé
      expect(await AuthProvider(api).tryAutoLogin(), isFalse);
      expect(api.logins, hasLength(1));
    });

    test('sans mot de passe mémorisé ou sans « Rester connecté » : pas de connexion auto', () async {
      SharedPreferences.setMockInitialValues({'saved_login': 'awa', 'stay_connected': true});
      final api = FakeApi();
      expect(await AuthProvider(api).tryAutoLogin(), isFalse);
      SharedPreferences.setMockInitialValues({'saved_login': 'awa', 'stay_connected': false});
      FlutterSecureStorage.setMockInitialValues({IdentifiantsSecurises.cleSure: mdp});
      expect(await AuthProvider(api).tryAutoLogin(), isFalse);
      expect(api.logins, isEmpty);
    });

    testWidgets('écran de connexion : identifiant et mot de passe pré-remplis depuis le stockage sûr', (t) async {
      debugPrint = ancienPrint!; // les tests d'écran vérifient que debugPrint est rétabli
      SharedPreferences.setMockInitialValues({'saved_login': 'awa', 'saved_password': mdp, 'stay_connected': true});
      final settings = SettingsProvider();
      await t.runAsync(settings.loadSettings);
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider(create: (_) => AuthProvider(FakeApi())),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump();
      final champs = t.widgetList<TextFormField>(find.byType(TextFormField)).toList();
      expect(champs.map((c) => c.controller?.text), containsAll(['awa', mdp]));
      await t.runAsync(aucuneTraceEnClair);
    });
  });
}
