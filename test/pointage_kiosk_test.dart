import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/pointage/pointage_logic.dart';
import 'package:prestige_vente_app/pointage/pointage_models.dart';
import 'package:prestige_vente_app/pointage/pointage_repository.dart';
import 'package:prestige_vente_app/screens/pointage/pointage_home_screen.dart';
import 'package:prestige_vente_app/screens/pointage/pointage_kiosk_screen.dart';
import 'package:prestige_vente_app/services/fingerprint_service.dart';

void main() {
  late MemoryPointageRepository repo;
  const awa = Employee(id: 'awa', name: 'Awa Kouassi', pin: '1234');
  const koffi = Employee(id: 'koffi', name: 'Koffi Yao', fingerprintTemplates: ['AAAA']);
  final at = DateTime(2026, 9, 29, 8, 2);

  setUp(() {
    repo = MemoryPointageRepository()..employees.addAll([awa, koffi]);
  });

  Future<void> pumpKiosk(WidgetTester tester, PointageMode mode, PointageVerifier verifier) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: PointageKioskScreen(
        repository: repo,
        capability: DeviceCapability(mode: mode, device: 'Test'),
        verifier: verifier,
        clock: () => at,
      ),
    ));
    await tester.pumpAndSettle();
  }

  PointageVerifier verifier({bool Function(Employee)? fingerprint, Object? fingerprintError, Employee? identified}) =>
      PointageVerifier(
        confirmFingerprint: (e) async {
          if (fingerprintError != null) throw fingerprintError;
          return fingerprint?.call(e) ?? true;
        },
        identify: (_) async => identified,
      );

  testWidgets('téléphone (lecteur Android) : nom + empreinte -> arrivée enregistrée', (tester) async {
    await pumpKiosk(tester, PointageMode.androidBiometric, verifier());
    await tester.tap(find.text('Awa Kouassi'));
    await tester.pumpAndSettle();
    expect(find.text('08:02 · Nom + empreinte'), findsOneWidget);
    await tester.tap(find.text('Arrivée'));
    await tester.pumpAndSettle();

    expect(repo.records, hasLength(1));
    expect(repo.records.single.type, PointageType.arrivee);
    expect(repo.records.single.method, PointageMethod.androidBiometric);
    expect(find.textContaining('Arrivée enregistrée à 08:02 — Bonjour Awa Kouassi'), findsOneWidget);
    expect(find.text('Arrivée à 08:02'), findsOneWidget);
  });

  testWidgets('empreinte annulée : aucun pointage', (tester) async {
    await pumpKiosk(tester, PointageMode.androidBiometric, verifier(fingerprint: (_) => false));
    await tester.tap(find.text('Awa Kouassi'));
    await tester.pumpAndSettle();
    expect(find.text('Arrivée'), findsNothing);
    expect(repo.records, isEmpty);
  });

  testWidgets('empreinte indisponible : repli sur le code PIN (faux puis juste)', (tester) async {
    await pumpKiosk(
      tester,
      PointageMode.androidBiometric,
      verifier(fingerprintError: const FingerprintException('LOCKOUT', 'Trop d\'essais')),
    );
    await tester.tap(find.text('Awa Kouassi'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '0000');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(repo.records, isEmpty);

    await tester.tap(find.text('Awa Kouassi'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '1234');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arrivée'));
    await tester.pumpAndSettle();
    expect(repo.records.single.method, PointageMethod.pin);
  });

  testWidgets('sans lecteur : employé sans PIN -> "Nom seul", enchaînement arrivée puis pause', (tester) async {
    await pumpKiosk(tester, PointageMode.pinOrName, verifier());
    await tester.tap(find.text('Koffi Yao'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arrivée'));
    await tester.pumpAndSettle();
    expect(repo.records.single.method, PointageMethod.manual);

    await tester.tap(find.text('Koffi Yao'));
    await tester.pumpAndSettle();
    expect(find.text('Arrivée'), findsNothing);
    expect(find.text('Début pause'), findsOneWidget);
    expect(find.text('Départ'), findsOneWidget);
  });

  testWidgets('Sunmi : le doigt identifie l\'employé', (tester) async {
    await pumpKiosk(tester, PointageMode.sunmiIdentify, verifier(identified: koffi));
    expect(find.text('Posez votre doigt sur le lecteur'), findsOneWidget);
    await tester.tap(find.text('Pointer'));
    await tester.pumpAndSettle();
    expect(find.text('Koffi Yao'), findsOneWidget);
    await tester.tap(find.text('Arrivée'));
    await tester.pumpAndSettle();
    expect(repo.records.single.employeeId, 'koffi');
    expect(repo.records.single.method, PointageMethod.sunmiFingerprint);
  });

  testWidgets('accueil : mode affiché selon l\'appareil, employés protégés par code admin', (tester) async {
    var adminAsked = 0;
    await tester.pumpWidget(MaterialApp(
      home: PointageHomeScreen(
        repository: repo,
        detectCapability: () async =>
            const DeviceCapability(mode: PointageMode.androidBiometric, device: 'Nothing A015', hasReader: true, readerReady: true),
        adminCheck: (_) async {
          adminAsked++;
          return false;
        },
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Mode : Nom + empreinte'), findsOneWidget);
    expect(find.textContaining('Nothing A015'), findsOneWidget);
    await tester.tap(find.text('Employés'));
    await tester.pumpAndSettle();
    expect(adminAsked, 1);
    expect(find.text('Ajouter'), findsNothing); // accès refusé sans code
  });
}
