import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/pointage/pointage_logic.dart';
import 'package:prestige_vente_app/pointage/pointage_models.dart';
import 'package:prestige_vente_app/pointage/pointage_repository.dart';
import 'package:prestige_vente_app/screens/pointage/employees_screen.dart';
import 'package:prestige_vente_app/screens/pointage/pointage_home_screen.dart';
import 'package:prestige_vente_app/screens/pointage/pointage_kiosk_screen.dart';

void main() {
  late MemoryPointageRepository repo;
  const awa = Employee(id: 'awa', name: 'Awa Kouassi', pin: '1234', badgeCode: 'PV12AB34');
  const koffi = Employee(id: 'koffi', name: 'Koffi Yao', badgeCode: '0004567');
  final at = DateTime(2026, 10, 6, 8, 2);
  final badgeField = find.widgetWithText(TextField, 'Scannez votre badge');

  setUp(() => repo = MemoryPointageRepository()..employees.addAll([awa, koffi]));

  void bigScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpKiosk(WidgetTester tester, PointageSettings settings, {String? cameraValue}) async {
    bigScreen(tester);
    await tester.pumpWidget(MaterialApp(
      home: PointageKioskScreen(
        repository: repo,
        capability: const DeviceCapability(mode: PointageMode.androidBiometric, device: 'Test'),
        settings: settings,
        verifier: PointageVerifier(confirmFingerprint: (_) async => true, identify: (_) async => null),
        clock: () => at,
        badgeCamera: (_) async => cameraValue,
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// Le scanner Sunmi "tape" le code d'un coup (avec retour chariot) ; validation après 300 ms.
  Future<void> scan(WidgetTester tester, String code) async {
    await tester.enterText(badgeField, code);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
  }

  group('Modèle', () {
    test('normalisation : espaces, retour chariot, majuscules', () {
      expect(normalizeBadge(' pv12ab34\r\n'), 'PV12AB34');
      expect(normalizeBadge('\x1D0004567'), '0004567');
    });
    test('badge et réglages conservés (JSON), anciennes fiches sans badge', () {
      expect(Employee.fromJson(awa.toJson()).badgeCode, 'PV12AB34');
      expect(Employee.fromJson({'id': 'x', 'name': 'X'}).hasBadge, isFalse);
      const s = PointageSettings(badgeMode: BadgeMode.both, pinAfterBadge: true);
      final back = PointageSettings.fromJson(s.toJson());
      expect(back.badgeMode, BadgeMode.both);
      expect(back.pinAfterBadge, isTrue);
      expect(PointageSettings.fromJson({}).badgeMode, BadgeMode.off);
    });
  });

  testWidgets('badge uniquement : scan Sunmi -> employé reconnu -> arrivée "Badge"', (tester) async {
    await pumpKiosk(tester, const PointageSettings(badgeMode: BadgeMode.only));
    expect(find.text('Awa Kouassi'), findsNothing); // pas de liste de noms
    await scan(tester, 'pv12ab34\n');
    expect(find.text('Awa Kouassi'), findsOneWidget);
    await tester.tap(find.text('Arrivée'));
    await tester.pumpAndSettle();
    expect(repo.records.single.employeeId, 'awa');
    expect(repo.records.single.method, PointageMethod.badge);
  });

  testWidgets('badge inconnu : message, aucun pointage', (tester) async {
    await pumpKiosk(tester, const PointageSettings(badgeMode: BadgeMode.only));
    await scan(tester, 'INCONNU');
    expect(find.textContaining('Badge non reconnu'), findsWidgets);
    expect(repo.records, isEmpty);
  });

  testWidgets('badge par la caméra', (tester) async {
    await pumpKiosk(tester, const PointageSettings(badgeMode: BadgeMode.only), cameraValue: '0004567');
    await tester.tap(find.byTooltip('Scanner le badge (caméra)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arrivée'));
    await tester.pumpAndSettle();
    expect(repo.records.single.employeeId, 'koffi');
  });

  testWidgets('PIN après le badge : faux refusé, juste accepté ; sans PIN défini refusé', (tester) async {
    await pumpKiosk(tester, const PointageSettings(badgeMode: BadgeMode.only, pinAfterBadge: true));
    await scan(tester, 'PV12AB34');
    await tester.enterText(find.byType(TextField).last, '9999');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(repo.records, isEmpty);

    await scan(tester, 'PV12AB34');
    await tester.enterText(find.byType(TextField).last, '1234');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arrivée'));
    await tester.pumpAndSettle();
    expect(repo.records.single.method, PointageMethod.badgePin);

    await scan(tester, '0004567'); // Koffi n'a pas de PIN
    expect(find.textContaining('aucun PIN n\'est défini pour Koffi Yao'), findsWidgets);
    expect(repo.records, hasLength(1));
  });

  testWidgets('badge ou empreinte : les deux sont proposés', (tester) async {
    await pumpKiosk(tester, const PointageSettings(badgeMode: BadgeMode.both));
    expect(badgeField, findsOneWidget);
    await tester.tap(find.text('Koffi Yao'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arrivée'));
    await tester.pumpAndSettle();
    expect(repo.records.single.method, PointageMethod.androidBiometric);

    await scan(tester, 'PV12AB34');
    await tester.tap(find.text('Arrivée'));
    await tester.pumpAndSettle();
    expect(repo.records.last.method, PointageMethod.badge);
  });

  testWidgets('sans option badge : pas de zone badge (comme avant)', (tester) async {
    await pumpKiosk(tester, const PointageSettings());
    expect(badgeField, findsNothing);
    expect(find.text('Awa Kouassi'), findsOneWidget);
  });

  testWidgets('fiche employé : badge scanné enregistré, badge déjà attribué refusé', (tester) async {
    bigScreen(tester);
    await tester.pumpWidget(MaterialApp(
      home: EmployeeEditScreen(repository: repo, employee: koffi, badgeCamera: (_) async => ' pv12ab34 '),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Scanner le badge (caméra)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.text('Ce badge est déjà attribué à Awa Kouassi.'), findsOneWidget);
    expect(repo.employees.firstWhere((e) => e.id == 'koffi').badgeCode, '0004567');

    await tester.tap(find.text('Générer un code'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(repo.employees.firstWhere((e) => e.id == 'koffi').badgeCode, matches(RegExp(r'^PV[0-9A-F]{8}$')));
  });

  testWidgets('accueil : réglage "Badge uniquement + PIN" (code admin)', (tester) async {
    bigScreen(tester);
    await tester.pumpWidget(MaterialApp(
      home: PointageHomeScreen(
        repository: repo,
        detectCapability: () async => const DeviceCapability(mode: PointageMode.androidBiometric, device: 'Nothing A015'),
        adminCheck: (_) async => true,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Méthode de pointage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Badge uniquement (code-barres, QR ou NFC)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Code PIN après le badge'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(repo.settings.badgeMode, BadgeMode.only);
    expect(repo.settings.pinAfterBadge, isTrue);
    expect(find.text('Badge uniquement · PIN après le badge'), findsOneWidget);
  });
}
