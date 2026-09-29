import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/screens/pointage/fingerprint_diagnostic_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('prestige/fingerprint');
  const events = MethodChannel('prestige/fingerprint/events');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <String>[];

  void mock({bool installed = true}) {
    calls.clear();
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'isServiceInstalled':
          return installed;
        case 'hardwareInfo':
          return {
            'manufacturer': 'SUNMI', 'model': 'V3H', 'android': '13', 'sdk': 33,
            'featureFingerprint': true, 'biometricStatus': 0,
            'sunmiServices': installed ? ['com.sunmi.fingerprintservice/.FingerprintService'] : <String>[],
            'sunmiPackages': <String>[],
          };
        case 'connect':
        case 'engage':
          return true;
        case 'deviceInfo':
          return {'device_manufacturer': 'Aratek', 'device_model': 'A400'};
        case 'capacity':
          return {'capacity': 1000, 'enrolled': 0};
        case 'enroll':
          return Uint8List.fromList(List.filled(512, 7));
        case 'identify':
          final templates = (call.arguments as Map)['templates'] as List;
          return {'index': templates.length - 1, 'score': 87};
        case 'release':
        case 'cancel':
          return 0;
      }
      return null;
    });
  }

  tearDown(() {
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockMethodCallHandler(events, null);
  });

  testWidgets('terminal sans service Sunmi : message clair, tests désactivés', (tester) async {
    mock(installed: false);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: FingerprintDiagnosticScreen()));
    await tester.pumpAndSettle();
    // Lecteur Android présent, mais pas le service Sunmi d'identification : explication précise
    expect(find.textContaining('Lecteur présent'), findsOneWidget);
    expect(find.textContaining('Le lecteur existe, mais le service Sunmi'), findsOneWidget);
    expect(calls, isNot(contains('connect')));
    final enrollBtn = tester.widget<ButtonStyleButton>(
        find.ancestor(of: find.text('Tester l\'enregistrement'), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)));
    expect(enrollBtn.onPressed, isNull);
  });

  testWidgets('parcours complet : capteur, enregistrement, reconnaissance, libération', (tester) async {
    mock();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: FingerprintDiagnosticScreen()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Aratek · A400'), findsOneWidget);
    expect(find.textContaining('capacité 1000'), findsOneWidget);

    await tester.ensureVisible(find.text('Tester l\'enregistrement'));
    await tester.tap(find.text('Tester l\'enregistrement'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Empreinte n°1 enregistrée (gabarit 512 octets)'), findsOneWidget);

    await tester.ensureVisible(find.text('Tester la reconnaissance'));
    await tester.tap(find.text('Tester la reconnaissance'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Reconnue : empreinte n°1 (score 87)'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(calls, contains('release'));
  });

  testWidgets('téléphone non Sunmi : étapes Sunmi masquées, test de la confirmation Android', (tester) async {
    calls.clear();
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call.method);
      return switch (call.method) {
        'hardwareInfo' => {
            'manufacturer': 'Nothing', 'model': 'A015', 'android': '16',
            'featureFingerprint': true, 'biometricStatus': 0, 'sunmiServices': <String>[],
          },
        'isServiceInstalled' => false,
        'authenticate' => true,
        _ => 0,
      };
    });
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: FingerprintDiagnosticScreen()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Lecteur présent'), findsOneWidget);
    expect(find.text('Service d\'identification Sunmi'), findsNothing);
    expect(find.text('Tester l\'enregistrement'), findsNothing);
    expect(calls, isNot(contains('connect')));
    await tester.tap(find.text('Tester la confirmation par empreinte'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Empreinte reconnue'), findsOneWidget);
  });
}
