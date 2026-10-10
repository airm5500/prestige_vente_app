// Les trois présentations (A, B, C) des écrans Mise à jour péremption et Pointage :
// mêmes données et mêmes actions, et aucun débordement sur un petit téléphone (360 px).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/pointage/pointage_logic.dart';
import 'package:prestige_vente_app/pointage/pointage_models.dart';
import 'package:prestige_vente_app/pointage/pointage_repository.dart';
import 'package:prestige_vente_app/providers/expiration_update_provider.dart';
import 'package:prestige_vente_app/screens/expiration_update/expiration_update_screen.dart';
import 'package:prestige_vente_app/screens/pointage/employees_screen.dart';
import 'package:prestige_vente_app/screens/pointage/pointage_home_screen.dart';
import 'package:prestige_vente_app/screens/pointage/pointage_kiosk_screen.dart';
import 'package:prestige_vente_app/screens/pointage/pointage_report_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(baseUrl: 'http://localhost');

  @override
  Future<List<ProductSearchResult>> searchProducts(String query) async => [
        ProductSearchResult(
          lgFAMILLEID: 'p1',
          strNAME: 'DOLIPRANE 1000MG CP B/8 BOITE FAMILIALE',
          intCIP: '3595583',
          intPRICE: 1500,
          intNUMBERAVAILABLE: 12,
          strLIBELLEE: '',
          intPAF: 1100,
        ),
      ];
}

void main() {
  const awa = Employee(id: 'awa', name: 'Awa Kouassi Aya Marie-Josée', matricule: 'M-0042', pin: '1234', badgeCode: 'PV1234');
  const koffi = Employee(id: 'koffi', name: 'Koffi Yao', fingerprintTemplates: ['AAAA'], active: false);
  const phone = DeviceCapability(mode: PointageMode.androidBiometric, device: 'Nothing A015', hasReader: true, readerReady: true);
  late MemoryPointageRepository repo;

  setUpAll(() => initializeDateFormatting('fr_FR'));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    repo = MemoryPointageRepository()
      ..employees.addAll([awa, koffi])
      ..records.addAll([
        PointageRecord(id: 'r1', employeeId: 'awa', type: PointageType.arrivee, time: today.add(const Duration(hours: 8, minutes: 25)), method: PointageMethod.pin),
        PointageRecord(
            id: 'r2', employeeId: 'awa', type: PointageType.arrivee, time: today.subtract(const Duration(hours: 16)), method: PointageMethod.badge),
        PointageRecord(id: 'r3', employeeId: 'awa', type: PointageType.depart, time: today.subtract(const Duration(hours: 7)), method: PointageMethod.badge),
      ]);
  });

  Future<void> pumpSmall(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(720, 1400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MaterialApp(home: home));
    await tester.pumpAndSettle();
  }

  for (final style in ListPresentation.values) {
    testWidgets('péremption ${style.name} : recherche, fiche produit, Valider en bas', (tester) async {
      tester.view.physicalSize = const Size(720, 1400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => ExpirationUpdateProvider(_FakeApi()),
        child: MaterialApp(home: ExpirationUpdateScreen(presentation: style)),
      ));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'doliprane');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('DOLIPRANE 1000MG CP B/8 BOITE FAMILIALE'), findsWidgets);
      expect(find.text('Valider'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('pointage accueil ${style.name} : mode, chiffres du jour, tuiles', (tester) async {
      await pumpSmall(
        tester,
        PointageHomeScreen(repository: repo, detectCapability: () async => phone, adminCheck: (_) async => true, presentation: style),
      );
      expect(find.text('Mode : Nom + empreinte'), findsOneWidget);
      expect(find.textContaining('Nothing A015'), findsOneWidget);
      expect(find.text('POINTER'), findsOneWidget);
      for (final t in ['Méthode de pointage', 'Employés', 'Rapport et analyse', 'Diagnostic du lecteur']) {
        await tester.scrollUntilVisible(find.text(t), 200, scrollable: find.byType(Scrollable).last);
        expect(find.text(t), findsOneWidget);
      }
      await tester.scrollUntilVisible(find.text('POINTER'), -200, scrollable: find.byType(Scrollable).last);
      if (style != ListPresentation.guided) expect(find.text('1'), findsWidgets); // 1 présente, 1 employé actif
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('POINTER'));
      await tester.pumpAndSettle();
      expect(find.byType(PointageKioskScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('employés ${style.name} : liste, recherche, fiche', (tester) async {
      await pumpSmall(tester, EmployeesScreen(repository: repo, capability: phone, presentation: style));
      expect(find.text('Awa Kouassi Aya Marie-Josée'), findsOneWidget);
      expect(find.text('Koffi Yao (inactif)'), findsOneWidget);
      expect(find.text('Ajouter'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'koffi');
      await tester.pumpAndSettle();
      expect(find.text('Awa Kouassi Aya Marie-Josée'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Koffi Yao (inactif)'));
      await tester.pumpAndSettle();
      expect(find.text('Modifier l\'employé'), findsOneWidget);
      expect(find.text('Enregistrer'), findsOneWidget);
      final form = find.byWidget(tester.widget(find.ancestor(of: find.text('Identité'), matching: find.byType(Scrollable)).first));
      for (final t in ['Horaires', 'Badge NFC', 'Empreintes']) {
        await tester.scrollUntilVisible(find.text(t), 200, scrollable: form);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('rapport ${style.name} : périodes, chiffres, détail employé', (tester) async {
      await pumpSmall(tester, PointageReportScreen(repository: repo, presentation: style));
      expect(find.text('Awa Kouassi Aya Marie-Josée'), findsOneWidget);
      expect(find.text('Aujourd\'hui'), findsWidgets);
      expect(find.text('Retards'), findsWidgets);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Aujourd\'hui').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Awa Kouassi Aya Marie-Josée'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Horaires 08:00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
