// Sécurité des codes : PIN administrateur (empreinte salée PBKDF2 dans le stockage sûr, migration de
// l'ancienne clé en clair, repli si le stockage sûr échoue, anti-force brute, changement obligatoire du
// code par défaut), PIN des employés du pointage local (empreinte, migration au chargement), aucune trace
// en clair dans les préférences, bouton « Présentation » réservé à l'administrateur.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/pointage/pointage_logic.dart';
import 'package:prestige_vente_app/pointage/pointage_models.dart';
import 'package:prestige_vente_app/pointage/pointage_repository.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/screens/pointage/pointage_kiosk_screen.dart';
import 'package:prestige_vente_app/services/identifiants_securises.dart';
import 'package:prestige_vente_app/services/pin_securise.dart';
import 'package:prestige_vente_app/widgets/pin_code_dialog.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stockage sûr en mémoire, avec panne simulable.
class _Coffre implements CoffreIdentifiants {
  final Map<String, String> valeurs = {};
  bool panne = false;

  @override
  Future<String?> lire(String cle) async {
    if (panne) throw PlatformException(code: 'KEYSTORE');
    return valeurs[cle];
  }

  @override
  Future<void> ecrire(String cle, String valeur) async {
    if (panne) throw PlatformException(code: 'KEYSTORE');
    valeurs[cle] = valeur;
  }

  @override
  Future<void> effacer(String cle) async {
    if (panne) throw PlatformException(code: 'KEYSTORE');
    valeurs.remove(cle);
  }
}

class _Auth extends AuthProvider {
  _Auth({required this.admin}) : super(ApiService(baseUrl: 'http://localhost'));
  final bool admin;
  @override
  bool get isAdmin => admin;
}

String _hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

/// Toutes les chaînes des préférences (valeurs JSON dépliées).
Future<List<String>> _chainesPreferences() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final out = <String>[];
  void collecter(Object? v) {
    if (v is String) {
      out.add(v);
      try {
        final d = jsonDecode(v);
        if (d is! String) collecter(d);
      } catch (_) {}
    } else if (v is Map) {
      for (final e in v.entries) {
        out.add('${e.key}');
        collecter(e.value);
      }
    } else if (v is List) {
      v.forEach(collecter);
    } else if (v != null) {
      out.add('$v');
    }
  }

  for (final k in prefs.getKeys()) {
    out.add(k);
    collecter(prefs.get(k));
  }
  return out;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('PBKDF2-HMAC-SHA256 et empreintes', () {
    test('vecteurs de référence (RFC 7914, hashlib)', () {
      expect(_hex(Pbkdf2Sha256.deriver(utf8.encode('passwd'), utf8.encode('salt'), 1, 64)),
          '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783');
      expect(_hex(Pbkdf2Sha256.deriver(utf8.encode('password'), utf8.encode('salt'), 4096, 32)),
          'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a');
      expect(_hex(Pbkdf2Sha256.deriver(utf8.encode('1234'), List.generate(16, (i) => i), 120000, 32)),
          '5070321ca34dbdafe9b25371d1c0f83bcafe073fbae1f2274f00a6d6c68e9899');
      // Clé de plus de 64 octets (hachée d'abord) et sel de plus d'un bloc.
      expect(
          _hex(Pbkdf2Sha256.deriver(utf8.encode('k' * 100), utf8.encode('saltSALTsaltSALTsaltSALTsaltSALTsaltSALTsaltSALTsaltSALTsalt'), 2, 40)),
          '9236dd243423956a38f50548f651a04b33edb4b1551c3f0954d2816acf63b21c51276076e27d5430');
    });

    test('empreinte salée : ≥ 100 000 itérations, sel aléatoire, vérification', () {
      final a = EmpreintePin.creer('4827');
      final b = EmpreintePin.creer('4827');
      final p = a.split('\$');
      expect(p[0], 'pbkdf2-sha256');
      expect(int.parse(p[1]), greaterThanOrEqualTo(100000));
      expect(base64Decode(p[2]), hasLength(16));
      expect(base64Decode(p[3]), hasLength(32));
      expect(a, isNot(b), reason: 'sel différent à chaque empreinte');
      expect(a, isNot(contains('4827')));
      expect(EmpreintePin.estEmpreinte(a), isTrue);
      expect(EmpreintePin.estEmpreinte('4827'), isFalse);
      expect(EmpreintePin.verifier('4827', a), isTrue);
      expect(EmpreintePin.verifier('4827', b), isTrue);
      expect(EmpreintePin.verifier('4828', a), isFalse);
      expect(EmpreintePin.verifier('', a), isFalse);
      // Empreintes abîmées : refusées.
      expect(EmpreintePin.verifier('4827', 'pbkdf2-sha256\$abc\$x\$y'), isFalse);
      expect(EmpreintePin.verifier('4827', 'pbkdf2-sha256\$999999999\$AAAA\$AAAA'), isFalse);
      expect(EmpreintePin.verifier('4827', '${p[0]}\$${p[1]}\$${p[2]}'), isFalse);
      // Ancienne valeur en clair (mémoire) : encore reconnue, en temps constant.
      expect(EmpreintePin.correspond('4827', '4827'), isTrue);
      expect(EmpreintePin.correspond('482', '4827'), isFalse);
      expect(EmpreintePin.correspond('4827', null), isFalse);
      expect(EmpreintePin.securiser(a), a);
      expect(EmpreintePin.estEmpreinte(EmpreintePin.securiser('4827')), isTrue);
    });

    test('comparaison en temps constant : parcourt toute la longueur', () {
      expect(EmpreintePin.egauxTempsConstant([1, 2, 3], [1, 2, 3]), isTrue);
      expect(EmpreintePin.egauxTempsConstant([1, 2, 3], [9, 2, 3]), isFalse);
      expect(EmpreintePin.egauxTempsConstant([1, 2, 3], [1, 2, 9]), isFalse);
      expect(EmpreintePin.egauxTempsConstant([1, 2], [1, 2, 0]), isFalse);
      expect(EmpreintePin.egauxTempsConstant([], []), isTrue);
    });
  });

  group('PIN administrateur', () {
    late _Coffre coffre;
    late DateTime maintenant;
    CodeAdmin code() => CodeAdmin(coffre: coffre, horloge: () => maintenant);

    setUp(() {
      coffre = _Coffre();
      maintenant = DateTime(2026, 10, 11, 9);
    });

    test('migration : ancien PIN en clair haché, vérifié, clé en clair supprimée ; ancien PIN accepté', () async {
      SharedPreferences.setMockInitialValues({CodeAdmin.cleClaire: '4827'});
      final c = code();
      expect(await c.migrer(), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(CodeAdmin.cleClaire), isFalse);
      final e = coffre.valeurs[CodeAdmin.cleSure]!;
      expect(EmpreintePin.estEmpreinte(e), isTrue);
      expect(EmpreintePin.verifier('4827', e), isTrue);
      expect(await c.verifier('4827'), VerificationPin.accepte);
      expect(await c.verifier('1234'), VerificationPin.refuse);
      // Nouvelle instance (relance) : même résultat, rien à migrer.
      expect(await code().verifier('4827'), VerificationPin.accepte);
    });

    test('migration au chargement des réglages (démarrage)', () async {
      SharedPreferences.setMockInitialValues({CodeAdmin.cleClaire: '4827'});
      final ancien = CodeAdmin.instance;
      CodeAdmin.instance = code();
      addTearDown(() => CodeAdmin.instance = ancien);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(CodeAdmin.cleClaire), isTrue);
      await SettingsProvider().loadSettings();
      expect(prefs.containsKey(CodeAdmin.cleClaire), isFalse);
      expect(await CodeAdmin.instance.verifier('4827'), VerificationPin.accepte);
    });

    test('stockage sûr en échec : ancien fonctionnement gardé, aucune perte, nouvel essai réussi ensuite', () async {
      SharedPreferences.setMockInitialValues({CodeAdmin.cleClaire: '4827'});
      coffre.panne = true;
      final c = code();
      expect(await c.migrer(), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(CodeAdmin.cleClaire), '4827', reason: 'code conservé');
      expect(await c.verifier('4827'), VerificationPin.accepte);
      expect(await c.verifier('0000'), VerificationPin.refuse);

      // Changement du code pendant la panne : enregistré à l'ancienne, pas perdu.
      expect(await c.definir('5937'), isNull);
      expect(prefs.getString(CodeAdmin.cleClaire), '5937');
      expect(await c.verifier('5937'), VerificationPin.accepte);

      // Keystore revenu : migration au prochain accès, clé en clair supprimée.
      coffre.panne = false;
      expect(await c.verifier('5937'), VerificationPin.accepte);
      expect(prefs.containsKey(CodeAdmin.cleClaire), isFalse);
      expect(EmpreintePin.verifier('5937', coffre.valeurs[CodeAdmin.cleSure]!), isTrue);
    });

    test('stockage sûr illisible sans ancienne clé : vérification impossible, accès refusé', () async {
      final c = code();
      expect(await c.definir('5937'), isNull);
      coffre.panne = true;
      expect(await c.verifier('5937'), VerificationPin.indisponible);
      expect(await c.verifier('1234'), VerificationPin.indisponible, reason: 'jamais de repli sur le code par défaut');
    });

    test('anti-force brute : attente progressive persistée après 5 erreurs', () async {
      final c = code();
      expect(await c.definir('5937'), isNull);
      for (var i = 0; i < 4; i++) {
        expect(await c.verifier('0000'), VerificationPin.refuse);
      }
      expect(await c.attenteRestante(), isNull);
      expect(await c.verifier('0000'), VerificationPin.bloque);
      expect(await c.attenteRestante(), const Duration(seconds: 30));
      // Pendant l'attente, même le bon code est refusé (et rien n'est vérifié).
      expect(await c.verifier('5937'), VerificationPin.bloque);
      // Attente persistée : une nouvelle instance (relance de l'appli) la voit.
      expect(await code().attenteRestante(), const Duration(seconds: 30));

      maintenant = maintenant.add(const Duration(seconds: 31));
      expect(await c.verifier('0000'), VerificationPin.bloque);
      expect(await c.attenteRestante(), const Duration(minutes: 1));
      maintenant = maintenant.add(const Duration(minutes: 1, seconds: 1));
      expect(await c.verifier('0000'), VerificationPin.bloque);
      expect(await c.attenteRestante(), const Duration(minutes: 5));
      maintenant = maintenant.add(const Duration(minutes: 5, seconds: 1));
      expect(await c.verifier('0000'), VerificationPin.bloque);
      expect(await c.attenteRestante(), const Duration(minutes: 15));

      maintenant = maintenant.add(const Duration(minutes: 16));
      expect(await c.verifier('5937'), VerificationPin.accepte);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(CodeAdmin.cleEchecs), isFalse, reason: 'compteur remis à zéro');
      expect(await c.verifier('0000'), VerificationPin.refuse, reason: 'de nouveau 5 essais');
    });

    test('code par défaut 1234 : n\'ouvre que le changement obligatoire', () async {
      final c = code();
      expect(await c.verifier('1234'), VerificationPin.changementObligatoire);
      expect(await c.verifier('4827'), VerificationPin.refuse);
      // Ancien 1234 en clair : migré, toujours « par défaut ».
      SharedPreferences.setMockInitialValues({CodeAdmin.cleClaire: '1234'});
      expect(await code().verifier('1234'), VerificationPin.changementObligatoire);
      expect(await code().definir('4827'), isNull);
      expect(await code().verifier('1234'), VerificationPin.refuse);
      expect(await code().verifier('4827'), VerificationPin.accepte);
    });

    test('règles du nouveau PIN : 4 à 8 chiffres, codes évidents refusés', () async {
      for (final mauvais in [
        '', '123', '123456789', '12a4', ' 4827', '1234', '0000', '1111', '99999999', '2345', '4321', '0123',
        '98765', '7890', '3210', '12345678', '1212', '123123', '0101',
      ]) {
        expect(ReglesPin.refus(mauvais), isNotNull, reason: mauvais);
      }
      for (final bon in ['4827', '190275', '58130462', '1357', '2580', '1243']) {
        expect(ReglesPin.refus(bon), isNull, reason: bon);
      }
      final c = code();
      expect(await c.definir('0000'), isNotNull);
      expect(coffre.valeurs, isEmpty, reason: 'code refusé : rien enregistré');
    });

    testWidgets('écran : 1234 → changement obligatoire (saisie double, refus) puis accès', (tester) async {
      final ancien = CodeAdmin.instance;
      CodeAdmin.instance = code();
      addTearDown(() => CodeAdmin.instance = ancien);
      bool? acces;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async => acces = await PinCodeDialog.show(ctx),
              child: const Text('Zone admin'),
            ),
          ),
        ),
      ));

      // Annuler le changement obligatoire : accès refusé, le code par défaut reste.
      await tester.tap(find.text('Zone admin'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('pin_admin_saisie')), '1234');
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
      expect(find.text('Changement du code obligatoire'), findsOneWidget);
      await tester.tap(find.text('Annuler (accès refusé)'));
      await tester.pumpAndSettle();
      expect(acces, isFalse);

      await tester.tap(find.text('Zone admin'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('pin_admin_saisie')), '1234');
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
      // Code évident refusé.
      await tester.enterText(find.byKey(const Key('pin_admin_nouveau')), '1111');
      await tester.enterText(find.byKey(const Key('pin_admin_confirmation')), '1111');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pin_admin_erreur')), findsOneWidget);
      // Saisies différentes refusées.
      await tester.enterText(find.byKey(const Key('pin_admin_nouveau')), '4827');
      await tester.enterText(find.byKey(const Key('pin_admin_confirmation')), '4828');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(find.text('Les deux saisies sont différentes.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('pin_admin_confirmation')), '4827');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(acces, isTrue);
      expect(find.text('Changement du code obligatoire'), findsNothing);

      // Le code par défaut ne marche plus ; le nouveau ouvre directement.
      await tester.tap(find.text('Zone admin'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('pin_admin_saisie')), '1234');
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
      expect(find.text('Code incorrect'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('pin_admin_saisie')), '4827');
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
      expect(acces, isTrue);
      expect(find.text('Changement du code obligatoire'), findsNothing);
      expect((await SharedPreferences.getInstance()).containsKey(CodeAdmin.cleClaire), isFalse);
    });
  });

  group('PIN des employés du pointage local', () {
    String employes(List<Map<String, dynamic>> l) => jsonEncode(l);

    test('migration au chargement : PIN haché, vérification inchangée, jamais réécrit en clair', () async {
      SharedPreferences.setMockInitialValues({
        'pointage_employees_v1': employes([
          {'id': 'awa', 'name': 'Awa', 'pin': '2468'},
          {'id': 'koffi', 'name': 'Koffi'},
        ]),
      });
      final repo = LocalPointageRepository();
      final liste = await repo.loadEmployees();
      final awa = liste.firstWhere((e) => e.id == 'awa');
      expect(EmpreintePin.estEmpreinte(awa.pin), isTrue);
      expect(awa.hasPin, isTrue);
      expect(awa.verifierPin('2468'), isTrue);
      expect(awa.verifierPin('1357'), isFalse);
      expect(liste.firstWhere((e) => e.id == 'koffi').hasPin, isFalse);

      final brut = (jsonDecode((await SharedPreferences.getInstance()).getString('pointage_employees_v1')!) as List).cast<Map>();
      expect(EmpreintePin.estEmpreinte(brut.first['pin'] as String), isTrue);
      expect(brut.first['pin'], awa.pin, reason: 'empreinte réécrite au chargement');
      expect(await _chainesPreferences(), isNot(contains('2468')));

      // Deuxième chargement : empreinte gardée telle quelle.
      expect((await repo.loadEmployees()).firstWhere((e) => e.id == 'awa').pin, awa.pin);

      // Enregistrement d'un nouveau PIN : haché ; modification sans PIN : empreinte conservée.
      await repo.saveEmployee(awa.copyWith(pin: '9753'));
      var relu = (await repo.loadEmployees()).firstWhere((e) => e.id == 'awa');
      expect(relu.verifierPin('9753'), isTrue);
      expect(relu.verifierPin('2468'), isFalse);
      await repo.saveEmployee(relu.copyWith(name: 'Awa K.'));
      relu = (await repo.loadEmployees()).firstWhere((e) => e.id == 'awa');
      expect(relu.verifierPin('9753'), isTrue);
      expect(await _chainesPreferences(), isNot(contains('9753')));
      // Export / sauvegarde (toJson) : jamais en clair.
      const enClair = Employee(id: 'x', name: 'X', pin: '8642');
      expect(EmpreintePin.estEmpreinte(enClair.toJson()['pin'] as String), isTrue);
      expect(Employee.fromJson(enClair.toJson()).verifierPin('8642'), isTrue);
      expect(const Employee(id: 'y', name: 'Y').toJson()['pin'], isNull);
    });

    testWidgets('borne de pointage : PIN migré accepté, mauvais PIN refusé', (tester) async {
      SharedPreferences.setMockInitialValues({
        'pointage_employees_v1': employes([
          {'id': 'awa', 'name': 'Awa Kouassi', 'pin': '2468'},
        ]),
      });
      final repo = LocalPointageRepository();
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: PointageKioskScreen(
          repository: repo,
          capability: const DeviceCapability(mode: PointageMode.pinOrName, device: 'Test'),
          verifier: PointageVerifier(confirmFingerprint: (_) async => true, identify: (_) async => null),
          clock: () => DateTime(2026, 10, 11, 8, 2),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Awa Kouassi'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '1357');
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
      expect(find.text('Code PIN incorrect.'), findsOneWidget);
      expect(await repo.loadRecords(), isEmpty);

      await tester.tap(find.text('Awa Kouassi'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '2468');
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Arrivée'));
      await tester.pumpAndSettle();
      expect((await repo.loadRecords()).single.method, PointageMethod.pin);
    });
  });

  test('après migration, les préférences en clair ne contiennent plus aucun code', () async {
    SharedPreferences.setMockInitialValues({
      CodeAdmin.cleClaire: '4827',
      IdentifiantsSecurises.cleClaire: 'MotDePasse!42',
      'pointage_employees_v1': jsonEncode([
        {'id': 'awa', 'name': 'Awa', 'pin': '2468'},
        {'id': 'yao', 'name': 'Yao', 'pin': '135790'},
      ]),
      'saved_login': 'awa',
    });
    final coffre = _Coffre();
    expect(await CodeAdmin(coffre: coffre).migrer(), isTrue);
    expect(await IdentifiantsSecurises(coffre: coffre).migrer(), isTrue);
    await LocalPointageRepository().loadEmployees();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(CodeAdmin.cleClaire), isFalse);
    expect(prefs.containsKey(IdentifiantsSecurises.cleClaire), isFalse);
    final chaines = await _chainesPreferences();
    for (final secret in ['4827', 'MotDePasse!42', '2468', '135790', '1234']) {
      expect(chaines.where((s) => s == secret || s.contains('"$secret"')), isEmpty, reason: secret);
    }
    // Les empreintes ne se trouvent que pour le pointage (préférences) et dans le stockage sûr (admin).
    expect(EmpreintePin.verifier('4827', coffre.valeurs[CodeAdmin.cleSure]!), isTrue);
    expect(coffre.valeurs[IdentifiantsSecurises.cleSure], 'MotDePasse!42');
  });

  group('Bouton « Présentation » réservé à l\'administrateur', () {
    Future<void> monter(WidgetTester tester, {bool? admin}) async {
      final ecran = MaterialApp(
        home: PresentationScaffold(
          style: ListPresentation.dashboard,
          title: 'Écran',
          actions: (c) => [PresentationMenuButton(value: ListPresentation.dashboard, onChanged: (_) {}, color: c)],
          body: const SizedBox(),
        ),
      );
      await tester.pumpWidget(admin == null
          ? ecran
          : ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth(admin: admin), child: ecran));
      await tester.pumpAndSettle();
    }

    testWidgets('administrateur : bouton présent', (tester) async {
      await monter(tester, admin: true);
      expect(find.byTooltip('Présentation'), findsOneWidget);
    });

    testWidgets('non-admin ou compte inconnu : bouton absent', (tester) async {
      await monter(tester, admin: false);
      expect(find.byTooltip('Présentation'), findsNothing);
      await monter(tester);
      expect(find.byTooltip('Présentation'), findsNothing);
    });
  });
}
