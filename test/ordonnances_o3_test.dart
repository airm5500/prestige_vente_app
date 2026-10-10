// Étape O3 : correspondance catalogue améliorée (mini-catalogue et lectures déformées SYNTHÉTIQUES),
// performance (< 50 ms par ligne sur 10 000 produits), banc d'essai, réglage, écran Ordonnance.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart';
import 'package:prestige_vente_app/ordonnances/banc_essai/pipelines_disponibles.dart';
import 'package:prestige_vente_app/ordonnances/banc_essai/score_banc.dart';
import 'package:prestige_vente_app/ordonnances/o2/lecture_o2.dart';
import 'package:prestige_vente_app/ordonnances/o3/correspondance_o3.dart';
import 'package:prestige_vente_app/ordonnances/o3/similarite.dart';
import 'package:prestige_vente_app/parametres/rubriques_pages.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/screens/prescription/prescription_check_screen.dart';
import 'package:prestige_vente_app/services/prescription_parser.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProductSearchResult _p(String name, {int stock = 5, String? id}) => ProductSearchResult(
      lgFAMILLEID: id ?? name,
      strNAME: name,
      intCIP: '',
      intPRICE: 1000,
      intNUMBERAVAILABLE: stock,
      strLIBELLEE: '',
      intPAF: 800,
    );

const _catalogue = [
  'CURAM 1G CP B/16',
  'CURAM 625MG CP B/16',
  'CURAM 500MG/62.5MG SUSP BUV',
  'BRUSTAN 400MG CP B/20',
  'BRUSTAN SUSP BUV',
  'EFFERALGAN PEDIATRIQUE 3% SOL BUV',
  'EFFERALGAN 500MG CP EFFV B/16',
  'EFFERALGAN 1G CP B/8',
  'DOLIPRANE 1000MG CP B/8',
  'DOLIPRANE 500MG CP B/16',
  'DOLI PLUS CP',
  'DOLAREN PLUS CP',
  'DOLOWIN PLUS CP',
  'FLAGYL 500MG CP B/14',
  'FLAGYL 125MG/5ML SUSP BUV',
  'AMOXICILLINE 1G CP B/14',
  'AMOXICILLINE 500MG GEL B/12',
  'SPASMO-APOTEL SUPPO',
  'SPASMO-APOTEL CP',
  'BIO RITMO AB AMP BUV B/20',
  'ELUDRIL PRO SOLUTION 300ML',
  'ELUDRIL SOLUTION 90ML',
  'ANTALGEX GEL B/20',
  'ANTALGEX T GEL B/20',
  'TRAMADOL DENK 50MG CP',
  'TRAMADOL 50MG GEL',
  'MONOPROST 50MCG/ML COLLYRE',
  'VERORAB INJ',
  'PREDNI 20MG CP EFFV B/20',
];

CorrespondanceO3 _o3({Map<String, int> ventes = const {}}) =>
    CorrespondanceO3.catalogue([for (final n in _catalogue) _p(n)], popularite: PopulariteMemoire(ventes));

String? _top(String lu, {CorrespondanceO3? o3}) {
  final r = (o3 ?? _o3()).proposerTexte(lu);
  return r.isEmpty || r.first.confiance < CorrespondanceO3.seuilProposition ? null : r.first.produit.strNAME;
}

ProductPageSearch _recherche(List<String> noms, {List<String>? requetes}) => (q, start, limit) async {
      requetes?.add(q);
      final all = [for (final n in noms) if (n.toLowerCase().startsWith(q.toLowerCase())) _p(n)];
      return VenteOk(ProductPage(all.skip(start).take(limit).toList(), all.length));
    };

void main() {
  group('Similarité', () {
    test('confusions de l\'écriture moins chères qu\'une lettre quelconque', () {
      expect(Similarite.distance('curam', 'curam'), 0);
      expect(Similarite.distance('cnram', 'curam'), lessThan(Similarite.distance('cxram', 'curam')));
      expect(Similarite.distance('modiprane', 'rnodiprane'), lessThan(10)); // m lu « rn »
      expect(Similarite.distance('dolo', 'clolo'), lessThan(10)); // d lu « cl »
      expect(Similarite.ressemblance('flagyl', 'flagil'), greaterThan(0.9));
    });

    test('phonétique française', () {
      expect(Similarite.phonetique('flagyl'), Similarite.phonetique('flaguil'));
      expect(Similarite.phonetique('pharmacie'), Similarite.phonetique('farmassie'));
      expect(Similarite.phonetique('cetirizine'), Similarite.phonetique('setirisine'));
    });
  });

  group('Correspondance (lectures déformées)', () {
    test('« Ceuram 1g » → CURAM 1G ; « Bnstou » → BRUSTAN ; « Efferalgan pediat » → EFFERALGAN PÉDIATRIQUE', () {
      expect(_top('Ceuram 1g'), 'CURAM 1G CP B/16');
      expect(_top('Bnstou'), startsWith('BRUSTAN'));
      expect(_top('Bnstou 400 mg'), 'BRUSTAN 400MG CP B/20');
      expect(_top('Efferalgan pediat'), 'EFFERALGAN PEDIATRIQUE 3% SOL BUV');
      expect(_top('Spasmo apotel suppo'), 'SPASMO-APOTEL SUPPO');
      expect(_top('Bio-Ritmo AB'), 'BIO RITMO AB AMP BUV B/20');
      expect(_top('Flaguil 500'), 'FLAGYL 500MG CP B/14');
      expect(_top('Verorab inj'), 'VERORAB INJ');
    });

    test('dosage et forme discriminants', () {
      expect(_top('Curam 625'), 'CURAM 625MG CP B/16');
      expect(_top('Curam 1 g'), 'CURAM 1G CP B/16');
      expect(_top('Curam susp'), 'CURAM 500MG/62.5MG SUSP BUV');
      expect(_top('Amoxicilline 500 gél'), 'AMOXICILLINE 500MG GEL B/12');
      expect(_top('Amoxicilline 1g'), 'AMOXICILLINE 1G CP B/14');
      expect(_top('Flagyl sp'), 'FLAGYL 125MG/5ML SUSP BUV');
      expect(_top('Spasmo-Apotel cp'), 'SPASMO-APOTEL CP');
      expect(_top('Efferalgan 1 g'), 'EFFERALGAN 1G CP B/8');
    });

    test('qualificatifs : Plus, Pro, T, Denk', () {
      expect(_top('Dolowin Plus'), 'DOLOWIN PLUS CP');
      expect(_top('Eludril pro'), 'ELUDRIL PRO SOLUTION 300ML');
      expect(_top('Eludril'), 'ELUDRIL SOLUTION 90ML');
      expect(_top('Antalgex T'), 'ANTALGEX T GEL B/20');
      expect(_top('Antalgex gel'), 'ANTALGEX GEL B/20');
      expect(_top('Tramadol denk'), 'TRAMADOL DENK 50MG CP');
      final colle = CorrespondanceO3.catalogue([_p('ELUDRILPRO BAIN BCHE F/200ML'), _p('ELUDRIL COLLUTOIRE F/90ML')]);
      expect(colle.proposerTexte('Eludril pro').first.produit.strNAME, 'ELUDRILPRO BAIN BCHE F/200ML');
      expect(colle.proposerTexte('Eludril').first.produit.strNAME, 'ELUDRIL COLLUTOIRE F/90ML');
    });

    test('faux positifs évités : texte sans rapport, mots trop courts', () {
      expect(_top('Ein it'), isNull);
      expect(_top('Médecin ophtalmologiste'), isNull);
      expect(_top('xq'), isNull);
      expect(_top('Paracetamol 500'), isNull); // absent du catalogue : rien plutôt qu'un faux
      expect(_top('Zyrtec'), isNull);
    });

    test('top 3 avec confiance ; « à vérifier » sous le seuil', () async {
      final r = await _o3().proposer(const PrescriptionLine(text: 'Ceuram 1g', query: 'Ceuram'));
      expect(r.propositions.length, inInclusiveRange(1, 3));
      expect(r.propositions.first.produit.strNAME, 'CURAM 1G CP B/16');
      for (var i = 1; i < r.propositions.length; i++) {
        expect(r.propositions[i].confiance, lessThanOrEqualTo(r.propositions[i - 1].confiance));
      }
      final exact = await _o3().proposer(const PrescriptionLine(text: 'Curam 1g cp', query: 'Curam'));
      expect(exact.sur, isTrue);
      final flou = await _o3().proposer(const PrescriptionLine(text: 'Bnstou', query: 'Bnstou'));
      expect(flou.meilleure, isNotNull);
      expect(flou.sur, isFalse); // lecture déformée : à vérifier par le pharmacien
    });

    test('bonus stock et produits réellement vendus', () {
      final egal = CorrespondanceO3.catalogue([_p('KALEORID LP 600MG CP', id: 'a', stock: 0), _p('KALEORID LP 1000MG CP', id: 'b', stock: 0)]);
      final vendu = CorrespondanceO3.catalogue(
        [_p('KALEORID LP 600MG CP', id: 'a', stock: 0), _p('KALEORID LP 1000MG CP', id: 'b', stock: 0)],
        popularite: const PopulariteMemoire({'b': 30}),
      );
      expect(egal.proposerTexte('Kaleorid').first.confiance, closeTo(egal.proposerTexte('Kaleorid')[1].confiance, 1e-9));
      expect(vendu.proposerTexte('Kaleorid').first.produit.lgFAMILLEID, 'b');
      final stock = CorrespondanceO3.catalogue([_p('KALEORID LP 600MG CP', id: 'a', stock: 0), _p('KALEORID LP 1000MG CP', id: 'b', stock: 4)]);
      expect(stock.proposerTexte('Kaleorid').first.produit.lgFAMILLEID, 'b');
    });

    test('sans copie locale : candidats par la recherche serveur existante', () async {
      final requetes = <String>[];
      final o3 = CorrespondanceO3.recherche(_recherche(_catalogue, requetes: requetes));
      final r = await o3.proposer(const PrescriptionLine(text: 'Ceuram 1g', query: 'Ceuram'));
      expect(requetes, containsAll(['ceu', 'ce']));
      // « Ceuram » ne commence pas comme CURAM : seuls des préfixes communs permettent de le retrouver.
      expect(r.meilleure?.produit.strNAME, anyOf(isNull, 'CURAM 1G CP B/16'));
      final b = await o3.proposer(const PrescriptionLine(text: 'Brustam 400', query: 'Brustam'));
      expect(b.meilleure?.produit.strNAME, 'BRUSTAN 400MG CP B/20');
    });

    test('auto : copie locale si elle contient des produits, sinon recherche', () async {
      final local = await CorrespondanceO3.auto(_recherche(const []), chargerTout: () async => [for (final n in _catalogue) _p(n)]);
      expect(local.tailleIndex, _catalogue.length);
      final vide = await CorrespondanceO3.auto(_recherche(_catalogue), chargerTout: () async => const []);
      expect(vide.tailleIndex, 0);
    });
  });

  test('performance : < 50 ms par ligne sur 10 000 produits', () {
    final rnd = math.Random(7);
    const lettres = 'abcdefghijklmnopqrstuvwxyz';
    const formes = ['CP', 'GEL', 'SUSP BUV', 'AMP', 'SUPPO', 'COLLYRE', 'INJ', 'SACHET'];
    final produits = <ProductSearchResult>[
      for (var i = 0; i < 10000; i++)
        _p('${List.generate(5 + rnd.nextInt(6), (_) => lettres[rnd.nextInt(26)]).join().toUpperCase()} '
            '${[100, 250, 500, 1000][rnd.nextInt(4)]}MG ${formes[rnd.nextInt(formes.length)]}', id: 'p$i'),
      for (final n in _catalogue) _p(n),
    ];
    final o3 = CorrespondanceO3.catalogue(produits);
    const lectures = ['Ceuram 1g', 'Bnstou', 'Efferalgan pediat', 'Spasmo apotel suppo', 'Dolowin Plus', 'Tramadol denk', 'Flaguil 500', 'Ein it'];
    o3.proposerTexte('echauffement');
    final sw = Stopwatch()..start();
    for (final l in lectures) {
      o3.proposerTexte(l);
    }
    sw.stop();
    final parLigne = sw.elapsedMicroseconds / lectures.length / 1000;
    // ignore: avoid_print
    print('O3 : ${parLigne.toStringAsFixed(1)} ms par ligne sur ${produits.length} produits');
    expect(parLigne, lessThan(50));
    expect(o3.proposerTexte('Ceuram 1g').first.produit.strNAME, 'CURAM 1G CP B/16');
  });

  group('Banc d\'essai', () {
    test('candidat O3 branché, comparable à la référence et à O2', () async {
      const lu = ['1. Ceuram 1g —> 02 bts', '1cp x 3/j pdt 10j', '2. Bnstou 400 mg', '2cp x 2/j', '3. Tramadol denk'];
      final pipelines = pipelinesBanc(
        _recherche(_catalogue),
        lecteur: (_) async => lu,
        correspondanceO3: () async => _o3(),
      );
      expect(pipelines.map((p) => p.id), ['reference', 'o2', 'o2_image', 'o3']);
      final vt = VeriteTerrain.fromJsonString('{"ordonnances":{"o (1).jpeg":{"produits":'
          '[{"nom":"Curam 1 g"},{"nom":"Brustan 400 mg"},{"nom":"Tramadol Denk 50 mg"}]}}}');
      final scores = <String, ScoreOrdonnance>{};
      for (final p in [pipelines[0], pipelines[1], pipelines[3]]) {
        final r = await p.analyser('o (1).jpeg');
        scores[p.id] = BancScore.evaluer('o (1).jpeg', vt.pour('o (1).jpeg'), r.produits);
      }
      expect(scores['o3']!.entierementCorrecte, isTrue);
      expect(scores['o3']!.trouves.length, greaterThan(scores['o2']!.trouves.length));
      expect(scores['o2']!.trouves.length, greaterThanOrEqualTo(scores['reference']!.trouves.length));
    });
  });

  group('Réglage et écran Ordonnance', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      LectureO2.mode.value = ModeLecture.actuelle;
      LectureO2.ameliorerImage.value = false;
    });

    testWidgets('Réglages : « Actuelle » par défaut, choix O2 / O3', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: LectureO2Reglages()))));
      await tester.pumpAndSettle();
      expect(LectureO2.mode.value, ModeLecture.actuelle);
      await tester.tap(find.text('O3'));
      await tester.pumpAndSettle();
      expect(LectureO2.mode.value, ModeLecture.o3);
      expect((await SharedPreferences.getInstance()).getString('ordonnance_lecture_mode_v1'), 'o3');
      expect(find.byKey(const Key('lecture_o2_image')), findsOneWidget);
    });

    test('ancien réglage O2 (booléen) repris', () async {
      SharedPreferences.setMockInitialValues({'ordonnance_lecture_o2_v1': true});
      await LectureO2.charger();
      expect(LectureO2.mode.value, ModeLecture.o2);
    });

    testWidgets('O3 : propositions avec confiance, lecture déformée « à vérifier » non cochée', (tester) async {
      SharedPreferences.setMockInitialValues({'ordonnance_lecture_mode_v1': 'o3'});
      // Copie locale du catalogue (hors ligne) : index complet, même pour une lecture très déformée.
      final store = MemoryLocalStore();
      await tester.runAsync(() => store.replace(CatalogueCategorie.produits, [
            for (final n in _catalogue)
              {'lgFAMILLEID': n, 'strNAME': n, 'intCIP': '', 'intPRICE': 1000, 'intNUMBERAVAILABLE': 5, 'strLIBELLEE': '', 'intPAF': 800},
          ], DateTime(2026, 10, 1)));
      final previous = HorsLigne.instance;
      HorsLigne.instance = HorsLigne(store: store);
      addTearDown(() => HorsLigne.instance = previous);
      final api = _FakeApi();
      await tester.pumpWidget(MultiProvider(
        providers: [
          Provider<ApiService>.value(value: api),
          ChangeNotifierProvider<SaleProvider>.value(value: SaleProvider(api)),
        ],
        child: MaterialApp(
          home: PrescriptionCheckScreen(
            textReader: (_) async => const ['1. Curam 1g cp', '1cp x 3/j', '2. Bnstou 400 mg', '2cp x 2/j'],
            presentation: ListPresentation.dashboard,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Photographier l\'ordonnance'));
      await tester.pumpAndSettle();
      expect(LectureO2.mode.value, ModeLecture.o3);
      expect(find.text('CURAM 1G CP B/16'), findsOneWidget);
      expect(find.text('BRUSTAN 400MG CP B/20'), findsOneWidget);
      expect(find.textContaining('Proposé ·'), findsOneWidget);
      expect(find.textContaining('À vérifier ·'), findsOneWidget);
      // Seule la proposition sûre est cochée : la pré-vente ne contient que celle-ci tant que le pharmacien n'a pas validé l'autre.
      expect(find.textContaining('Créer la pré-vente (1 produit)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

class _FakeApi extends ApiService {
  _FakeApi() : super(baseUrl: 'http://localhost');

  @override
  Future<ProductPage> searchProductsPageOrFail(String query, int start, int limit) async {
    final all = [for (final n in _catalogue) if (n.toLowerCase().startsWith(query.toLowerCase())) _p(n)];
    return ProductPage(all.skip(start).take(limit).toList(), all.length);
  }
}
