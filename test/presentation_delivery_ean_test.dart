// Les trois présentations (A, B, C) des menus Contrôle Livraison et Mise à jour EAN :
// mêmes données et mêmes actions, aucun débordement à 360 px, saisies absurdes refusées.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/commande.dart';
import 'package:prestige_vente_app/api/models/commande_item.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/product_search_result.dart';
import 'package:prestige_vente_app/providers/delivery_control_provider.dart';
import 'package:prestige_vente_app/providers/product_update_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/screens/delivery_control/delivery_detail_screen.dart';
import 'package:prestige_vente_app/screens/delivery_control/delivery_list_screen.dart';
import 'package:prestige_vente_app/screens/delivery_control/delivery_report_screen.dart';
import 'package:prestige_vente_app/screens/product_update/ean_update_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart' show ProductPage;

class _FakeApi extends ApiService {
  // Recherche par pages : mêmes produits que la recherche simulée ci-dessous.
  @override
  Future<ProductPage> searchProductsPageOrFail(String query, int start, int limit) async {
    final all = await searchProducts(query);
    return ProductPage(all.skip(start).take(limit).toList(), all.length);
  }

  _FakeApi() : super(baseUrl: 'http://localhost');

  final posted = <(String, int)>[];
  final liteInfo = <Map<String, dynamic>>[];
  String currentEan = '';
  Completer<bool>? pendingUpdate;

  @override
  Future<List<Commande>> getCommandes() async => [
        Commande(
          id: 'c1',
          ref: 'CMD-2026-0042',
          grossiste: 'LABOREX COTE D\'IVOIRE DISTRIBUTION',
          date: DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now()),
          nbreProduit: 2,
          prixAchatTotal: 1254300,
          statut: 'is_Process',
          statutTraitement: 'A_FAIRE',
        ),
        Commande(
          id: 'c2',
          ref: 'CMD-2025-0007',
          grossiste: 'DPCI',
          date: '2025-01-15 09:00:00',
          nbreProduit: 5,
          prixAchatTotal: 5000,
          statut: 'is_Process',
          statutTraitement: 'TERMINE',
        ),
      ];

  @override
  Future<List<CommandeItem>> getCommandeItems(String orderId) async => [
        CommandeItem(
            id: 'd1',
            produitId: 'p1',
            nomProduit: 'DOLIPRANE 1000MG CP B/8 BOITE FAMILIALE',
            cip: '3595583',
            qteCommandee: 10,
            prixAchat: 1100,
            isChecked: false,
            checkedQuantity: 0),
        CommandeItem(
            id: 'd2', produitId: 'p2', nomProduit: 'EFFERALGAN 500MG', cip: '3000001', qteCommandee: 4, prixAchat: 900, isChecked: true, checkedQuantity: 3),
      ];

  @override
  Future<bool> postCheckedQuantity({required String detailId, required int quantity}) async {
    posted.add((detailId, quantity));
    return true;
  }

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

  @override
  Future<ProductDetails?> getProductDetailsForSearch(String codeCip) async =>
      ProductDetails.fromJson({'lg_FAMILLE_ID': 'p1', 'int_CIP': codeCip, 'str_NAME': 'DOLIPRANE', 'codeEanFabriquant': currentEan});

  @override
  Future<bool> updateLiteInfo(Map<String, dynamic> data) async {
    liteInfo.add(data);
    if (pendingUpdate != null) return pendingUpdate!.future;
    return true;
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  void small(WidgetTester tester) {
    tester.view.physicalSize = const Size(720, 1400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  Widget delivery(_FakeApi api, DeliveryControlProvider provider, Widget home) => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider.value(value: provider),
        ],
        child: MaterialApp(home: home),
      );

  group('contrôles de saisie', () {
    test('EAN : chiffres, longueur 8/12/13/14, clé EAN-13', () {
      expect(validateEanCode(''), 'Veuillez saisir un code');
      expect(validateEanCode('12AB5678'), contains('chiffres'));
      expect(validateEanCode('1234567'), contains('Longueur invalide'));
      expect(validateEanCode('3400930000015'), contains('Clé EAN-13 incorrecte'));
      expect(validateEanCode('3400930000014'), isNull);
      expect(validateEanCode('4006381333931'), isNull);
      expect(validateEanCode('12345670'), isNull);
      expect(validateEanCode('012345678905'), isNull);
      expect(validateEanCode('01234567890128'), isNull);
    });

    test('quantité contrôlée : entier de 0 à 10 000', () {
      expect(parseCheckedQuantity('0'), 0);
      expect(parseCheckedQuantity('12'), 12);
      expect(parseCheckedQuantity('10000'), 10000);
      expect(parseCheckedQuantity('10001'), isNull);
      expect(parseCheckedQuantity('3400930000014'), isNull);
      expect(parseCheckedQuantity('-1'), isNull);
      expect(parseCheckedQuantity('1,5'), isNull);
      expect(parseCheckedQuantity(''), isNull);
    });

    test('date de commande lue dans les deux formats', () {
      expect(parseCommandeDate('2026-10-10 14:30:00'), DateTime(2026, 10, 10));
      expect(parseCommandeDate('10/10/2026 14:30'), DateTime(2026, 10, 10));
      expect(parseCommandeDate(''), isNull);
      expect(parseCommandeDate('n/a'), isNull);
    });
  });

  for (final style in ListPresentation.values) {
    testWidgets('liste des commandes ${style.name} : période, chiffres, ouverture', (tester) async {
      small(tester);
      final api = _FakeApi();
      final provider = DeliveryControlProvider(api);
      await tester.pumpWidget(delivery(api, provider, DeliveryListScreen(presentation: style)));
      await tester.pumpAndSettle();
      expect(find.text('Contrôle Livraison'), findsOneWidget);
      expect(find.textContaining('CMD-2026-0042'), findsOneWidget);
      expect(find.textContaining('CMD-2025-0007'), findsOneWidget);
      expect(find.text('Aujourd\'hui'), findsWidgets);
      expect(find.textContaining('1 / 2'), findsOneWidget); // progression : 1 terminée sur 2
      expect(tester.takeException(), isNull);

      // Période « Aujourd'hui » : l'ancienne commande disparaît.
      await tester.tap(find.text('Aujourd\'hui').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('CMD-2025-0007'), findsNothing);
      expect(find.textContaining('CMD-2026-0042'), findsOneWidget);

      // Recherche sans résultat : état vide explicite.
      await tester.enterText(find.byType(TextField).first, 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('Aucune commande pour ces critères.'), findsOneWidget);
      await tester.tap(find.text('Voir toutes les commandes'));
      await tester.pumpAndSettle();
      expect(find.textContaining('CMD-2025-0007'), findsOneWidget);

      // Ouverture de la commande : écran de contrôle.
      await tester.tap(find.textContaining('CMD-2026-0042').first);
      await tester.pumpAndSettle();
      expect(find.byType(DeliveryDetailScreen), findsOneWidget);
      expect(find.text('DOLIPRANE 1000MG CP B/8 BOITE FAMILIALE'), findsOneWidget);
      expect(find.text('1 ligne(s) à contrôler'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('contrôle ${style.name} : quantités bornées, rapport', (tester) async {
      small(tester);
      final api = _FakeApi();
      final provider = DeliveryControlProvider(api);
      await provider.fetchCommandes();
      await provider.selectCommande(provider.commandes.first);
      await tester.pumpWidget(delivery(api, provider, DeliveryDetailScreen(presentation: style)));
      await tester.pumpAndSettle();
      expect(find.text('CMD-2026-0042'), findsWidgets);
      expect(find.text('EFFERALGAN 500MG'), findsOneWidget);
      expect(find.text('Écart : -1'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final qty = find.widgetWithText(TextField, 'Qté reçue');
      // Valeur absurde (code-barres tapé dans la quantité) : refusée, rien envoyé.
      await tester.enterText(qty.first, '999999');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.textContaining('Quantité invalide'), findsOneWidget);
      expect(api.posted, isEmpty);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      // Lettres : filtrées à la saisie.
      await tester.enterText(qty.first, 'abc');
      expect(tester.widget<TextField>(qty.first).controller!.text, '');

      // Scan rapide : CIP + Entrée → popup, valeur trop grande refusée puis valeur correcte.
      await tester.enterText(find.byType(TextField).first, '3595583');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('Saisir la quantité comptée :'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, '50000');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Valider'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Mauvaise valeur'), findsOneWidget);
      expect(api.posted, isEmpty);
      await tester.enterText(find.byType(TextField).last, '10');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Valider'));
      await tester.pumpAndSettle();
      expect(api.posted, [('d1', 10)]);
      expect(find.text('Voir le rapport'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Voir le rapport'));
      await tester.pumpAndSettle();
      expect(find.byType(DeliveryReportScreen), findsOneWidget);
      expect(find.text('Anomalies détectées :'), findsOneWidget);
      expect(find.text('Écart: -1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('rapport ${style.name} : aucune anomalie', (tester) async {
      small(tester);
      final api = _FakeApi();
      final provider = DeliveryControlProvider(api);
      await provider.fetchCommandes();
      await provider.selectCommande(provider.commandes.first);
      provider.updateCheckedQuantity('d1', 10);
      provider.updateCheckedQuantity('d2', 4);
      await tester.pumpWidget(delivery(api, provider, DeliveryReportScreen(presentation: style)));
      await tester.pumpAndSettle();
      expect(find.text('Rapport de Contrôle'), findsOneWidget);
      expect(find.text('Aucune anomalie détectée.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('EAN ${style.name} : recherche, code invalide refusé, pas de double envoi', (tester) async {
      small(tester);
      final api = _FakeApi();
      await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => ProductUpdateProvider(api),
        child: MaterialApp(home: EanUpdateScreen(presentation: style)),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Mise à jour EAN Fabricant'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'doliprane');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('DOLIPRANE 1000MG CP B/8 BOITE FAMILIALE'), findsOneWidget);
      expect(find.text('Aucun EAN Fabricant enregistré'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final ean = find.widgetWithText(TextFormField, 'Code EAN Fabricant');
      await tester.enterText(ean, '1234567');
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Longueur invalide'), findsOneWidget);

      await tester.enterText(ean, '3400930000015');
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Clé EAN-13 incorrecte'), findsOneWidget);
      expect(api.liteInfo, isEmpty);

      await tester.enterText(ean, '3400930000014');
      api.pendingUpdate = Completer<bool>();
      await tester.tap(find.text('Valider'));
      await tester.pump();
      expect(find.text('Valider'), findsNothing); // bouton remplacé pendant l'envoi
      await tester.testTextInput.receiveAction(TextInputAction.done); // second envoi ignoré
      await tester.pump();
      api.pendingUpdate!.complete(true);
      await tester.pumpAndSettle();
      expect(api.liteInfo, [
        {'id': 'p1', 'codeEanFabriquant': '3400930000014'}
      ]);
      expect(find.text('EAN mis à jour avec succès.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 3));
    });
  }

  testWidgets('EAN : remplacement d\'un code existant demandé avant envoi', (tester) async {
    small(tester);
    final api = _FakeApi()..currentEan = '4006381333931';
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => ProductUpdateProvider(api),
      child: const MaterialApp(home: EanUpdateScreen(presentation: ListPresentation.dashboard)),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'doliprane');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('EAN Fabricant actuel : 4006381333931'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Code EAN Fabricant'), '3400930000014');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(find.text('Remplacer l\'EAN Fabricant ?'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(api.liteInfo, isEmpty);
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remplacer'));
    await tester.pumpAndSettle();
    expect(api.liteInfo.length, 1);
    await tester.pump(const Duration(seconds: 3));
  });
}
