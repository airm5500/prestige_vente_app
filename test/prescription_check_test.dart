import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/screens/prescription/prescription_check_screen.dart';
import 'package:prestige_vente_app/services/prescription_parser.dart';
import 'package:provider/provider.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(baseUrl: 'http://localhost');
  final Map<String, List<ProductSearchResult>> catalog = {};
  final List<String> searches = [];

  @override
  Future<List<ProductSearchResult>> searchProducts(String query) async {
    searches.add(query);
    return catalog[query.toLowerCase()] ?? [];
  }
}

ProductSearchResult _p(String id, String name, int stock) => ProductSearchResult(
      lgFAMILLEID: id,
      strNAME: name,
      intCIP: id,
      intPRICE: 1500,
      intNUMBERAVAILABLE: stock,
      strLIBELLEE: '',
      intPAF: 1000,
    );

const _ordonnance = [
  'Dr KOUASSI Jean',
  'Médecin généraliste',
  'Tél : 07 08 09 10 11',
  'Abidjan, le 22/09/2026',
  'Patient : Mme YAO Awa  Age : 34 ans',
  '1) DOLIPRANE 1000 mg cp',
  '1 cp matin et soir pendant 5 jours',
  '2) AMOXICILLINE 500mg gélules',
  '2 gélules 3 fois par jour',
  '- Spasfon Lyoc 80',
  '3/ Maalox suspension buvable',
  'QSP 1 mois',
];

void main() {
  group('Extraction des produits', () {
    final lines = PrescriptionParser.extract(_ordonnance);

    test('garde les produits, écarte en-tête, patient et posologie', () {
      expect(lines.map((l) => l.query).toList(), ['DOLIPRANE', 'AMOXICILLINE', 'Spasfon Lyoc'.split(' ').first, 'Maalox']);
    });

    test('dosage extrait', () {
      expect(lines.first.dosage, '1000');
      expect(lines[1].dosage, '500');
    });

    test('score : le bon dosage passe devant', () {
      final l = lines.first;
      expect(PrescriptionParser.score(l, 'DOLIPRANE 1000MG CP B/8'),
          greaterThan(PrescriptionParser.score(l, 'DOLIPRANE 500MG CP B/16')));
      expect(PrescriptionParser.score(l, 'EFFERALGAN 1G'), 0);
    });

    test('saisie forcée (ajout manuel) acceptée même sans dosage', () {
      expect(PrescriptionParser.parseLine('Smecta', force: true)!.query, 'Smecta');
      expect(PrescriptionParser.parseLine('Smecta'), isNull);
    });
  });

  group('Écran', () {
    late _FakeApi api;

    Future<void> pump(WidgetTester tester, List<String>? ocr) async {
      await tester.pumpWidget(
        Provider<ApiService>.value(
          value: api,
          child: MaterialApp(home: PrescriptionCheckScreen(textReader: (_) async => ocr)),
        ),
      );
    }

    setUp(() {
      api = _FakeApi()
        ..catalog['doliprane'] = [_p('A', 'DOLIPRANE 500MG CP', 12), _p('B', 'DOLIPRANE 1000MG CP', 3)]
        ..catalog['amoxicilline'] = [_p('C', 'AMOXICILLINE 500MG GEL', 0)]
        ..catalog['maalox'] = [_p('D', 'MAALOX SUSP BUV', 4)];
    });

    testWidgets('photo -> produits -> disponibilité', (tester) async {
      await pump(tester, _ordonnance);
      await tester.tap(find.text('Photographier l\'ordonnance'));
      await tester.pumpAndSettle();

      // Doliprane 1000 (bon dosage) classé en premier, disponible
      final doliCard = find.ancestor(of: find.text('DOLIPRANE 1000 mg cp'), matching: find.byType(Card));
      expect(find.descendant(of: doliCard, matching: find.text('Disponible')), findsOneWidget);
      final names = tester.widgetList<Text>(find.descendant(of: doliCard, matching: find.byType(Text))).map((t) => t.data ?? '').toList();
      expect(names.indexWhere((n) => n.startsWith('DOLIPRANE 1000MG')), lessThan(names.indexWhere((n) => n.startsWith('DOLIPRANE 500MG'))));

      final amoxCard = find.ancestor(of: find.text('AMOXICILLINE 500mg gélules'), matching: find.byType(Card));
      expect(find.descendant(of: amoxCard, matching: find.text('Rupture')), findsWidgets);

      final spasfonCard = find.ancestor(of: find.text('Spasfon Lyoc 80'), matching: find.byType(Card));
      expect(find.descendant(of: spasfonCard, matching: find.text('Non trouvé')), findsOneWidget);

      // Résumé : 4 produits, 2 disponibles, 1 rupture, 1 non trouvé
      expect(find.text('Disponibles'), findsOneWidget);
      expect(api.searches, containsAll(['DOLIPRANE', 'AMOXICILLINE', 'Maalox']));
    });

    testWidgets('prise de vue annulée : rien ne change', (tester) async {
      await pump(tester, null);
      await tester.tap(find.text('Photographier l\'ordonnance'));
      await tester.pumpAndSettle();
      expect(find.text('Photographier l\'ordonnance'), findsOneWidget);
      expect(api.searches, isEmpty);
    });

    testWidgets('ligne du texte lu ajoutée à la main', (tester) async {
      await pump(tester, ['Ordonnance', 'Maalox']);
      await tester.tap(find.text('Photographier l\'ordonnance'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3)); // snackbar "aucun produit"
      await tester.tap(find.textContaining('Texte lu non retenu'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Maalox'));
      await tester.pumpAndSettle();
      expect(find.textContaining('MAALOX SUSP BUV'), findsOneWidget);
      expect(find.text('Stock 4'), findsOneWidget);
    });
  });
}
