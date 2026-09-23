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
    await tester.pumpWidget(const MaterialApp(home: FingerprintDiagnosticScreen()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Service absent'), findsOneWidget);
    expect(calls, isNot(contains('connect')));
    final enrollBtn = tester.widget<ButtonStyleButton>(
        find.ancestor(of: find.text('Tester l\'enregistrement'), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)));
    expect(enrollBtn.onPressed, isNull);
  });

  testWidgets('parcours complet : capteur, enregistrement, reconnaissance, libération', (tester) async {
    mock();
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
}
