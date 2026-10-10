// Les trois présentations (A, B, C) du menu Mise à jour Emplacement :
// aucun débordement à 360 px, emplacement pris dans la liste, confirmation, pas de double envoi.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/product_search_result.dart';
import 'package:prestige_vente_app/api/models/rayon.dart';
import 'package:prestige_vente_app/providers/product_update_provider.dart';
import 'package:prestige_vente_app/screens/product_update/emplacement_update_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(baseUrl: 'http://localhost');

  final liteInfo = <Map<String, dynamic>>[];
  final searches = <String>[];
  String currentPlace = '';
  bool rayonsDown = false;
  int rayonCalls = 0;
  Completer<bool>? pendingUpdate;

  @override
  Future<List<Rayon>> getRayons() async {
    rayonCalls++;
    if (rayonsDown) return [];
    return [
      Rayon(id: 'r1', libelle: 'RAYON A1'),
      Rayon(id: 'r2', libelle: 'RAYON B2 - ANTALGIQUES ET ANTI-INFLAMMATOIRES'),
      Rayon(id: 'r3', libelle: 'FRIGO'),
    ];
  }

  @override
  Future<List<ProductSearchResult>> searchProducts(String query) async {
    searches.add(query);
    return [
      ProductSearchResult(
        lgFAMILLEID: 'p1',
        strNAME: 'DOLIPRANE 1000MG CP B/8 BOITE FAMILIALE',
        intCIP: '3595583',
        intPRICE: 1500,
        intNUMBERAVAILABLE: 12,
        strLIBELLEE: currentPlace,
        intPAF: 1100,
      ),
    ];
  }

  @override
  Future<ProductDetails?> getProductDetailsForSearch(String codeCip) async =>
      ProductDetails.fromJson({'lg_FAMILLE_ID': 'p1', 'int_CIP': codeCip, 'str_NAME': 'DOLIPRANE'});

  @override
  Future<bool> updateLiteInfo(Map<String, dynamic> data) async {
    liteInfo.add(data);
    if (pendingUpdate != null) return pendingUpdate!.future;
    return true;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  void small(WidgetTester tester) {
    tester.view.physicalSize = const Size(720, 1400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  Widget app(_FakeApi api, ListPresentation style) => ChangeNotifierProvider(
        create: (_) => ProductUpdateProvider(api),
        child: MaterialApp(home: EmplacementUpdateScreen(presentation: style)),
      );

  Future<void> openProduct(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).first, 'doliprane');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
  }

  Finder rayonField() => find.descendant(of: find.byType(DropdownMenu<Rayon>), matching: find.byType(TextField));

  group('contrôles de saisie', () {
    final rayons = [Rayon(id: 'r1', libelle: 'RAYON A1'), Rayon(id: 'r3', libelle: 'FRIGO')];

    test('recherche nettoyée : espaces, caractères de contrôle, longueur', () {
      expect(cleanSearchQuery('  doliprane \n'), 'doliprane');
      expect(cleanSearchQuery('dol\x00ip\trane'), 'dolip' 'rane');
      expect(cleanSearchQuery('x' * 200).length, emplacementMaxLength);
      expect(cleanSearchQuery('   '), '');
    });

    test('emplacement : seulement un rayon de la liste', () {
      expect(validateEmplacement(rayons, '', null), contains('Choisissez'));
      expect(validateEmplacement(rayons, 'RAYON ZZ', null), contains('pas un emplacement connu'));
      expect(validateEmplacement(rayons, ' frigo ', null), isNull);
      expect(resolveRayon(rayons, 'frigo', null)?.id, 'r3');
      // Texte modifié après la sélection : c'est le texte qui compte.
      expect(resolveRayon(rayons, 'RAYON A1', 'r3')?.id, 'r1');
      expect(resolveRayon(rayons, 'inconnu', 'r1'), isNull);
    });
  });

  for (final style in ListPresentation.values) {
    testWidgets('emplacement ${style.name} : recherche, valeur inconnue refusée, pas de double envoi', (tester) async {
      small(tester);
      final api = _FakeApi();
      await tester.pumpWidget(app(api, style));
      await tester.pumpAndSettle();
      expect(find.text('Mise à jour Emplacement'), findsOneWidget);
      expect(find.text('Scannez le code du produit ou recherchez-le par nom ou CIP.'), findsOneWidget);

      // Recherche nettoyée avant l'envoi.
      await tester.enterText(find.byType(TextField).first, '  doliprane  ');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(api.searches, ['doliprane']);
      expect(find.text('DOLIPRANE 1000MG CP B/8 BOITE FAMILIALE'), findsOneWidget);
      expect(find.text('Aucun emplacement enregistré'), findsOneWidget);
      expect(find.text('Valider'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Valeur fantaisiste : refusée, rien envoyé.
      await tester.enterText(rayonField(), 'RAYON IMAGINAIRE');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
      expect(find.textContaining('pas un emplacement connu'), findsOneWidget);
      expect(api.liteInfo, isEmpty);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      // Libellé exact tapé : accepté ; double envoi ignoré.
      await tester.enterText(rayonField(), 'frigo');
      await tester.pumpAndSettle();
      api.pendingUpdate = Completer<bool>();
      await tester.tap(find.text('Valider'));
      await tester.pump();
      expect(find.text('Valider'), findsNothing); // bouton remplacé pendant l'envoi
      api.pendingUpdate!.complete(true);
      await tester.pumpAndSettle();
      expect(api.liteInfo, [
        {'id': 'p1', 'rayonId': 'r3'}
      ]);
      expect(find.text('Emplacement mis à jour avec succès.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 4));
    });
  }

  testWidgets('emplacement : remplacement d\'un emplacement existant demandé avant envoi', (tester) async {
    small(tester);
    final api = _FakeApi()..currentPlace = 'RAYON A1';
    await tester.pumpWidget(app(api, ListPresentation.dashboard));
    await tester.pumpAndSettle();
    await openProduct(tester);
    expect(find.text('Emplacement actuel : RAYON A1'), findsOneWidget);

    // Choix dans la liste déroulante : envoi automatique, après confirmation.
    await tester.tap(rayonField());
    await tester.pumpAndSettle();
    await tester.tap(find.text('FRIGO').last);
    await tester.pumpAndSettle();
    expect(find.text('Remplacer l\'emplacement ?'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(api.liteInfo, isEmpty);

    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remplacer'));
    await tester.pumpAndSettle();
    expect(api.liteInfo, [
      {'id': 'p1', 'rayonId': 'r3'}
    ]);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('emplacement : même emplacement, pas de confirmation', (tester) async {
    small(tester);
    final api = _FakeApi()..currentPlace = 'RAYON A1';
    await tester.pumpWidget(app(api, ListPresentation.compact));
    await tester.pumpAndSettle();
    await openProduct(tester);
    await tester.enterText(rayonField(), 'rayon a1');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(find.text('Remplacer l\'emplacement ?'), findsNothing);
    expect(api.liteInfo, [
      {'id': 'p1', 'rayonId': 'r1'}
    ]);
    await tester.pump(const Duration(seconds: 4));
  });

  for (final style in ListPresentation.values) {
    testWidgets('emplacement ${style.name} : rayons indisponibles, message et Réessayer', (tester) async {
      small(tester);
      final api = _FakeApi()..rayonsDown = true;
      await tester.pumpWidget(app(api, style));
      await tester.pumpAndSettle();
      expect(find.textContaining('Impossible de charger la liste des emplacements'), findsOneWidget);
      await openProduct(tester);
      expect(find.text('Liste des emplacements indisponible.'), findsOneWidget);
      expect(tester.widget<ButtonStyleButton>(find.ancestor(of: find.text('Valider'), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton))).onPressed, isNull);
      expect(tester.takeException(), isNull);

      api.rayonsDown = false;
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(api.rayonCalls, 2);
      expect(find.textContaining('Impossible de charger la liste des emplacements'), findsNothing);
      expect(find.byType(DropdownMenu<Rayon>), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
