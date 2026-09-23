import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/screens/prescription/prescription_check_screen.dart';
import 'package:prestige_vente_app/services/prescription_parser.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(baseUrl: 'http://localhost');
  final Map<String, List<ProductSearchResult>> catalog = {};
  final List<String> searches = [];
  final List<Map<String, dynamic>> added = [];
  final List<SaleItemDetail> cart = [];

  @override
  Future<List<ProductSearchResult>> searchProducts(String query) async {
    searches.add(query);
    return catalog[query.toLowerCase()] ?? [];
  }

  @override
  Future<String?> addItemToSale({
    required String produitId,
    required int qte,
    required int itemPu,
    String? venteId,
    bool isPrevente = false,
  }) async {
    added.add({'produitId': produitId, 'qte': qte, 'itemPu': itemPu, 'venteId': venteId, 'prevente': isPrevente});
    cart.add(SaleItemDetail(
      lgPREENREGISTREMENTDETAILID: 'd${cart.length}',
      lgFAMILLEID: produitId,
      strNAME: produitId,
      intCIP: '',
      intQUANTITY: qte,
      intPRICEUNITAIR: itemPu,
      intPRICE: itemPu * qte,
      strREF: '',
    ));
    return venteId ?? 'PV-1';
  }

  @override
  Future<List<SaleItemDetail>> getSaleDetails(String venteId) async => List.of(cart);

  @override
  Future<SaleSummary?> calculateNet(String venteId) async => null;
}

ProductSearchResult _p(String id, String name, int stock, {String? cip}) => ProductSearchResult(
      lgFAMILLEID: id,
      strNAME: name,
      intCIP: cip ?? id,
      intPRICE: 1575,
      intNUMBERAVAILABLE: stock,
      strLIBELLEE: '',
      intPAF: 1000,
    );

/// Texte tel que regroupé par ligne (OcrService.groupIntoRows) pour l'ordonnance éditée par Prestige.
const _ordonnancePrestige = [
  'ORDONNANCE ORD-202609-0001',
  'Client  ABRO BAKA SIMEON  Type  Assurance',
  'Téléphone  Date  23/09/2026',
  'Prescripteur  Non renseigné  Pièces  Aucune pièce jointe',
  'Établissement  KA',
  'PRODUITS PRESCRITS',
  'Qté : quantité PRESCRITE. Servie : quantité déclarée servie (— : non renseignée). Cette fiche n\'est pas un document de vente.',
  'Produit  CIP  Qté  Servie  Posologie',
  'EFFERALGAN 500MG CPR EFFV B/16  3257001  1  —  1CP par jour',
  'TOTAL : 1 produit(s) prescrit(s)',
  'OBSERVATIONS',
];

const _ordonnanceManuscrite = [
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

final _efferalganFamily = [
  _p('E1', 'EFFERALGAN 500MG CPR EFFV B/16', 35, cip: '3257001'),
  _p('E2', 'EFFERALGAN VITC 500MG/200MG CPR EFFV/16', 31, cip: '3637324'),
  _p('E3', 'EFFERALGAN 500MG CPR SEC B/16', 9, cip: '3256757'),
  _p('E4', 'EFFERALGAN PLUS 500MG/65MG CPR PELL B/10', 1, cip: '8487390'),
  _p('E5', 'EFFERALGAN 500MG GELU B/16', 2, cip: '2271128'),
];

void main() {
  group('Extraction', () {
    test('ordonnance éditée (tableau) : 1 seul produit, CIP, quantité et posologie', () {
      final lines = PrescriptionParser.extract(_ordonnancePrestige);
      expect(lines, hasLength(1));
      final l = lines.single;
      expect(l.text, 'EFFERALGAN 500MG CPR EFFV B/16');
      expect(l.cip, '3257001');
      expect(l.quantity, 1);
      expect(l.posology, '1CP par jour');
    });

    test('ordonnance classique : produits sans en-tête ni posologie', () {
      final lines = PrescriptionParser.extract(_ordonnanceManuscrite);
      expect(lines.map((l) => l.query).toList(), ['DOLIPRANE', 'AMOXICILLINE', 'Spasfon', 'Maalox']);
      expect(lines.first.dosage, '1000');
    });

    test('score : le bon dosage passe devant', () {
      final l = PrescriptionParser.extract(_ordonnanceManuscrite).first;
      expect(PrescriptionParser.score(l, 'DOLIPRANE 1000MG CP B/8'),
          greaterThan(PrescriptionParser.score(l, 'DOLIPRANE 500MG CP B/16')));
      expect(PrescriptionParser.score(l, 'EFFERALGAN 1G'), 0);
    });

    test('saisie forcée : nom ou CIP seul', () {
      expect(PrescriptionParser.parseLine('Smecta', force: true)!.query, 'Smecta');
      expect(PrescriptionParser.parseLine('Smecta'), isNull);
      expect(PrescriptionParser.parseLine('3257001', force: true)!.cip, '3257001');
      expect(PrescriptionParser.parseLine('3257001'), isNull);
    });
  });

  group('Écran', () {
    late _FakeApi api;
    late SaleProvider sale;
    var preventeOpened = 0;

    Future<void> pump(WidgetTester tester, List<String>? ocr) async {
      sale = SaleProvider(api);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ApiService>.value(value: api),
            ChangeNotifierProvider<SaleProvider>.value(value: sale),
          ],
          child: MaterialApp(
            home: PrescriptionCheckScreen(
              textReader: (_) async => ocr,
              openPrevente: (_) async => preventeOpened++,
            ),
          ),
        ),
      );
    }

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      preventeOpened = 0;
      api = _FakeApi()
        ..catalog['3257001'] = [_efferalganFamily.first]
        ..catalog['efferalgan'] = _efferalganFamily
        ..catalog['doliprane'] = [_p('A', 'DOLIPRANE 500MG CP', 12), _p('B', 'DOLIPRANE 1000MG CP', 3)]
        ..catalog['amoxicilline'] = [_p('C', 'AMOXICILLINE 500MG GEL', 0)]
        ..catalog['maalox'] = [_p('D', 'MAALOX SUSP BUV', 4)];
    });

    testWidgets('ordonnance de la capture : UN seul produit, CIP identique, rien d\'autre affiché', (tester) async {
      await pump(tester, _ordonnancePrestige);
      await tester.tap(find.text('Photographier l\'ordonnance'));
      await tester.pumpAndSettle();

      expect(find.text('EFFERALGAN 500MG CPR EFFV B/16'), findsNWidgets(2)); // ligne lue + produit retenu
      expect(find.text('CIP identique'), findsOneWidget);
      for (final other in _efferalganFamily.skip(1)) {
        expect(find.text(other.strNAME), findsNothing);
      }
      expect(find.text('Changer'), findsNothing); // correspondance exacte : pas d'alternative
      expect(find.text('Stock 35'), findsOneWidget);
      expect(find.textContaining('Créer la pré-vente (1 produit)'), findsOneWidget);
    });

    testWidgets('création de la pré-vente : même circuit que l\'écran Pré/Vente', (tester) async {
      await pump(tester, _ordonnancePrestige);
      await tester.tap(find.text('Photographier l\'ordonnance'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add_circle_outline).first); // quantité 1 -> 2
      await tester.pump();

      await tester.tap(find.textContaining('Créer la pré-vente'));
      await tester.pumpAndSettle();
      expect(find.text('• 2 x EFFERALGAN 500MG CPR EFFV B/16'), findsOneWidget);
      await tester.tap(find.text('Créer'));
      await tester.pumpAndSettle();

      expect(api.added, [
        {'produitId': 'E1', 'qte': 2, 'itemPu': 1575, 'venteId': null, 'prevente': true},
      ]);
      expect(sale.currentVenteId, 'PV-1');
      expect(preventeOpened, 1);
    });

    testWidgets('sans CIP : un seul produit proposé "à vérifier", les autres via Changer', (tester) async {
      await pump(tester, _ordonnanceManuscrite);
      await tester.tap(find.text('Photographier l\'ordonnance'));
      await tester.pumpAndSettle();

      final doliCard = find.ancestor(of: find.text('DOLIPRANE 1000 mg cp'), matching: find.byType(Card));
      expect(find.descendant(of: doliCard, matching: find.text('DOLIPRANE 1000MG CP')), findsOneWidget);
      expect(find.descendant(of: doliCard, matching: find.text('DOLIPRANE 500MG CP')), findsNothing);
      expect(find.descendant(of: doliCard, matching: find.text('À vérifier')), findsOneWidget);

      await tester.tap(find.descendant(of: doliCard, matching: find.text('Changer')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('DOLIPRANE 500MG CP'));
      await tester.pumpAndSettle();
      expect(find.descendant(of: doliCard, matching: find.text('DOLIPRANE 500MG CP')), findsOneWidget);
      expect(find.descendant(of: doliCard, matching: find.text('Choisi par l\'opérateur')), findsOneWidget);

      final amoxCard = find.ancestor(of: find.text('AMOXICILLINE 500mg gélules'), matching: find.byType(Card));
      expect(find.descendant(of: amoxCard, matching: find.text('Rupture')), findsWidgets);
      final spasfonCard = find.ancestor(of: find.text('Spasfon Lyoc 80'), matching: find.byType(Card));
      expect(find.descendant(of: spasfonCard, matching: find.text('Non trouvé')), findsOneWidget);
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
      expect(find.text('MAALOX SUSP BUV'), findsOneWidget);
      expect(find.text('Stock 4'), findsOneWidget);
    });
  });
}
