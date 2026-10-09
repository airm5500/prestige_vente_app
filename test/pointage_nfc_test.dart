import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/pointage/pointage_logic.dart';
import 'package:prestige_vente_app/pointage/pointage_models.dart';
import 'package:prestige_vente_app/pointage/pointage_repository.dart';
import 'package:prestige_vente_app/screens/pointage/employees_screen.dart';
import 'package:prestige_vente_app/screens/pointage/pointage_kiosk_screen.dart';
import 'package:prestige_vente_app/services/nfc_service.dart';

class FakeNfc implements NfcReader {
  NfcAvailability state;
  final _tags = StreamController<String>.broadcast();
  bool started = false;
  int settingsOpened = 0;

  FakeNfc([this.state = NfcAvailability.ready]);

  void approach(String uid) => _tags.add(uid);

  @override
  Future<NfcAvailability> availability() async => state;
  @override
  Stream<String> get tags => _tags.stream;
  @override
  Future<bool> start() async => started = state == NfcAvailability.ready;
  @override
  Future<void> stop() async => started = false;
  @override
  Future<void> openSettings() async => settingsOpened++;
}

void main() {
  late MemoryPointageRepository repo;
  late FakeNfc nfc;
  const awa = Employee(id: 'awa', name: 'Awa Kouassi', pin: '1234', nfcUid: '04A1B2C3D4E5F6');
  const koffi = Employee(id: 'koffi', name: 'Koffi Yao', badgeCode: '0004567');
  final at = DateTime(2026, 10, 9, 8, 2);

  setUp(() {
    repo = MemoryPointageRepository()..employees.addAll([awa, koffi]);
    nfc = FakeNfc();
  });

  void bigScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpKiosk(WidgetTester tester, PointageSettings settings) async {
    bigScreen(tester);
    await tester.pumpWidget(MaterialApp(
      home: PointageKioskScreen(
        repository: repo,
        capability: const DeviceCapability(mode: PointageMode.androidBiometric, device: 'Test'),
        settings: settings,
        verifier: PointageVerifier(confirmFingerprint: (_) async => true, identify: (_) async => null),
        clock: () => at,
        nfc: nfc,
      ),
    ));
    await tester.pumpAndSettle();
  }

  test('identifiant NFC conservé (JSON), anciennes fiches sans NFC', () {
    expect(Employee.fromJson(awa.toJson()).nfcUid, '04A1B2C3D4E5F6');
    expect(Employee.fromJson({'id': 'x', 'name': 'X'}).hasNfc, isFalse);
  });

  testWidgets('pointage : badge NFC approché -> employé reconnu -> arrivée', (tester) async {
    await pumpKiosk(tester, const PointageSettings(badgeMode: BadgeMode.only));
    expect(nfc.started, isTrue);
    expect(find.textContaining('Badge NFC : approchez'), findsOneWidget);
    nfc.approach('04a1b2c3d4e5f6');
    await tester.pumpAndSettle();
    expect(find.text('Awa Kouassi'), findsOneWidget);
    nfc.approach('04A1B2C3D4E5F6'); // seconde lecture pendant le choix : ignorée
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arrivée'));
    await tester.pumpAndSettle();
    expect(repo.records.single.employeeId, 'awa');
    expect(repo.records.single.method, PointageMethod.badge);
  });

  testWidgets('NFC inconnu : message, aucun pointage ; le code-barres ne vaut pas pour le NFC', (tester) async {
    await pumpKiosk(tester, const PointageSettings(badgeMode: BadgeMode.both));
    nfc.approach('0004567');
    await tester.pumpAndSettle();
    expect(find.textContaining('Badge non reconnu'), findsWidgets);
    expect(repo.records, isEmpty);
  });

  testWidgets('NFC + PIN après le badge', (tester) async {
    await pumpKiosk(tester, const PointageSettings(badgeMode: BadgeMode.only, pinAfterBadge: true));
    nfc.approach('04A1B2C3D4E5F6');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '1234');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arrivée'));
    await tester.pumpAndSettle();
    expect(repo.records.single.method, PointageMethod.badgePin);
  });

  testWidgets('NFC désactivé : bouton Activer, lecteur non démarré', (tester) async {
    nfc.state = NfcAvailability.disabled;
    await pumpKiosk(tester, const PointageSettings(badgeMode: BadgeMode.only));
    expect(nfc.started, isFalse);
    await tester.tap(find.text('Activer'));
    expect(nfc.settingsOpened, 1);
  });

  testWidgets('sans NFC ou sans option badge : rien d\'affiché, lecteur arrêté en sortie', (tester) async {
    nfc.state = NfcAvailability.absent;
    await pumpKiosk(tester, const PointageSettings(badgeMode: BadgeMode.only));
    expect(find.textContaining('NFC'), findsNothing);

    nfc = FakeNfc();
    await tester.pumpWidget(const SizedBox());
    await pumpKiosk(tester, const PointageSettings());
    expect(nfc.started, isFalse);

    nfc = FakeNfc();
    await tester.pumpWidget(const SizedBox());
    await pumpKiosk(tester, const PointageSettings(badgeMode: BadgeMode.both));
    expect(nfc.started, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(nfc.started, isFalse);
  });

  testWidgets('fiche employé : lecture du badge NFC, doublon refusé', (tester) async {
    bigScreen(tester);
    await tester.pumpWidget(MaterialApp(home: EmployeeEditScreen(repository: repo, employee: koffi, nfc: nfc)));
    await tester.pumpAndSettle();
    expect(find.text('Badge NFC : aucun'), findsOneWidget);

    await tester.tap(find.text('Lire le badge NFC'));
    await tester.pumpAndSettle();
    expect(nfc.started, isTrue);
    nfc.approach('04a1b2c3d4e5f6');
    await tester.pumpAndSettle();
    expect(nfc.started, isFalse);
    expect(find.text('Badge NFC : 04A1B2C3D4E5F6'), findsOneWidget);
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.text('Ce badge NFC est déjà attribué à Awa Kouassi.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5)); // le message disparaît
    await tester.pumpAndSettle();

    await tester.tap(find.text('Lire le badge NFC'));
    await tester.pumpAndSettle();
    nfc.approach('1A2B3C4D');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(repo.employees.firstWhere((e) => e.id == 'koffi').nfcUid, '1A2B3C4D');
  });

  testWidgets('fiche employé : appareil sans NFC', (tester) async {
    bigScreen(tester);
    nfc.state = NfcAvailability.absent;
    await tester.pumpWidget(MaterialApp(home: EmployeeEditScreen(repository: repo, employee: koffi, nfc: nfc)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lire le badge NFC'));
    await tester.pumpAndSettle();
    expect(find.text('Cet appareil n\'a pas de lecteur NFC.'), findsOneWidget);
  });
}
