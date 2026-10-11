// Étape O3b : reconnaissance par fragments sûrs (« contient », avec prudence). Catalogue et lectures SYNTHÉTIQUES :
// fragments sûrs vs ambigus, confiance ML Kit, fragments fréquents ignorés, classement après les correspondances
// complètes, jamais « sûr » ni coché, recherche serveur avec joker, performance 10 000 produits, banc, écran.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart';
import 'package:prestige_vente_app/ordonnances/banc_essai/pipelines_disponibles.dart';
import 'package:prestige_vente_app/ordonnances/o2/lecture_o2.dart';
import 'package:prestige_vente_app/ordonnances/o3/correspondance_o3.dart';
import 'package:prestige_vente_app/ordonnances/o3/fragments_o3.dart';
import 'package:prestige_vente_app/ordonnances/o4/apprentissage_o4.dart';
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
      lgFAMILLEID: id ?? 'id-$name',
      strNAME: name,
      intCIP: '',
      intPRICE: 1000,
      intNUMBERAVAILABLE: stock,
      strLIBELLEE: '',
      intPAF: 800,
    );

const _catalogue = [
  'CARPHOS AB SACHET',
  'LUFART 80/480 CP B/6',
  'LUFART DT 20/120 CP',
  'NOVALGIN 500MG CP B/20',
  'CURAM 1G CP B/16',
  'BRUSTAN 400MG CP B/20',
  'DOLIPRANE 1000MG CP B/8',
  'FLAGYL 500MG CP B/14',
];

CorrespondanceO3 _o3({bool fragments = true, List<String> noms = _catalogue, SourceApprentissages? a}) =>
    CorrespondanceO3.catalogue([for (final n in noms) _p(n)], fragments: fragments, apprentissages: a);

PrescriptionLine _l(String t) => PrescriptionLine(text: t, query: t);

ProductPageSearch _recherche(List<String> noms, {List<String>? requetes}) => (q, start, limit) async {
      requetes?.add(q);
      final motif = q.toLowerCase();
      bool ok(String n) {
        final s = n.toLowerCase();
        if (!motif.startsWith('%')) return s.startsWith(motif);
        var pos = 0;
        for (final part in motif.split('%').where((x) => x.isNotEmpty)) {
          final i = s.indexOf(part, pos);
          if (i < 0) return false;
          pos = i + part.length;
        }
        return true;
      }

      final all = [for (final n in noms) if (ok(n)) _p(n)];
      return VenteOk(ProductPage(all.skip(start).take(limit).toList(), all.length));
    };

void main() {
  tearDown(ConfianceLecture.vider);

  group('Fragments sûrs', () {
    test('heuristique : coupure aux confusions à plusieurs lettres (m, d, rn, cl…), 4 caractères au moins', () {
      expect(FragmentsO3.extraire('arphos Ab').map((f) => f.brut), ['arphos']);
      expect(FragmentsO3.extraire('Lufarmxkq 80/480').map((f) => f.brut), ['lufar']);
      expect(FragmentsO3.extraire('Ceuram 1g').map((f) => f.brut), ['ceura']);
      expect(FragmentsO3.extraire('Amox'), isEmpty); // « m » ambigu : reste « a », « ox » (< 4)
      expect(FragmentsO3.extraire('Abc Xyz'), isEmpty); // 3 caractères : interdits
      expect(FragmentsO3.extraire('cornprime').map((f) => f.brut), isNot(contains('cornprime'))); // « rn » retiré
      expect(FragmentsO3.extraire('Novalgin 500 1cp x 3/j pdt 5 jours').map((f) => f.brut), ['novalgin']); // posologie ignorée
    });

    test('pliage des confusions d\'une lettre (u/n, a/o, i/l/1, e/c) : même forme pour le lu et le catalogue', () {
      expect(FragmentsO3.plier('lufar'), FragmentsO3.plier('infor'));
      expect(FragmentsO3.plier('ceura'), FragmentsO3.plier('eenro'));
      expect(FragmentsO3.nomIndexe('LUFART 80/480 CP'), contains(FragmentsO3.plier('lnfor')));
    });

    test('confiance ML Kit par caractère : seuls les caractères sûrs forment les fragments', () {
      ConfianceLecture.remplacer({'2. Zqarphoszt 20': '1110011111100111'});
      final m = ConfianceLecture.masquePour('Zqarphoszt 20');
      expect(m, '0011111100111');
      expect(FragmentsO3.extraire('Zqarphoszt 20', masque: m).map((f) => f.brut), ['arphos']);
      // Sans masque : un seul mot, « zqarphoszt », que rien ne contient.
      expect(FragmentsO3.extraire('Zqarphoszt 20').map((f) => f.brut), ['zqarphoszt']);
    });
  });

  group('Propositions par fragments', () {
    test('nom lisible en partie : proposé APRÈS les correspondances complètes, « à vérifier », indication …ARPHOS…', () async {
      ConfianceLecture.remplacer({'Zqarphoszt': '0011111100'});
      final r = await _o3().proposer(_l('Zqarphoszt'));
      expect(r.meilleure!.produit.strNAME, 'CARPHOS AB SACHET');
      expect(r.meilleure!.fragment, '…ARPHOS…');
      expect(r.meilleure!.confiance, lessThan(CorrespondanceO3.seuilSur));
      expect(r.sur, isFalse);
      // Sans l'option : O3 ne propose rien.
      expect((await _o3(fragments: false).proposer(_l('Zqarphoszt'))).meilleure, isNull);
    });

    test('dosage lu : filtre (Lufar 80/480 → LUFART 80/480, pas LUFART 20/120)', () async {
      final r = await _o3().proposer(_l('Lufarmxkq 80/480'));
      final noms = r.propositions.map((p) => p.produit.strNAME).toList();
      expect(noms.first, 'LUFART 80/480 CP B/6');
      expect(noms, isNot(contains('LUFART DT 20/120 CP')));
    });

    test('correspondance complète d\'abord ; les fragments ne changent ni son rang ni « sûr »', () async {
      final sans = await _o3(fragments: false).proposer(_l('Doliprane 1000 mg'));
      final avec = await _o3().proposer(_l('Doliprane 1000 mg'));
      expect(avec.meilleure!.produit.strNAME, sans.meilleure!.produit.strNAME);
      expect(avec.meilleure!.fragment, isNull);
      expect(avec.sur, sans.sur);
      final complets = avec.propositions.takeWhile((p) => p.fragment == null).length;
      expect(avec.propositions.skip(complets).every((p) => p.fragment != null), isTrue);
      expect(avec.propositions.where((p) => p.fragment != null).length, lessThanOrEqualTo(FragmentsO3.maximum));
    });

    test('fragment trop fréquent (> 30 produits) ignoré, sauf avec le dosage lu', () async {
      final noms = [
        for (var i = 0; i < 40; i++) 'PARACETAMOL ${100 + i}MG CP',
        'PARACETAMOL 500MG CP',
      ];
      final o3 = _o3(noms: noms);
      expect((await o3.proposer(_l('Paradkq'))).propositions.where((p) => p.fragment != null), isEmpty);
      final r = await o3.proposer(_l('Paradkq 500 mg'));
      expect(r.propositions.where((p) => p.fragment != null).map((p) => p.produit.strNAME), ['PARACETAMOL 500MG CP']);
    });

    test('bonus apprentissages O4 et produits en stock à fragment égal', () async {
      final noms = ['XAVPHOS A CP', 'ZAVPHOS B CP'];
      final a = ApprentissagesO4.memoire();
      await a.apprendre(segment: 'zavphos b', produitId: 'id-ZAVPHOS B CP');
      ConfianceLecture.remplacer({'Qmavphoszkt': '00111111000'});
      final r = await _o3(noms: noms, a: a).proposer(_l('Qmavphoszkt'));
      ConfianceLecture.vider();
      expect(r.propositions, isNotEmpty);
      expect(r.propositions.first.produit.strNAME, 'ZAVPHOS B CP');
    });

    test('sans copie locale : recherche serveur avec le joker % (« %frag1%frag2 »), bornée', () async {
      final requetes = <String>[];
      final o3 = CorrespondanceO3.recherche(_recherche(_catalogue, requetes: requetes), fragments: true);
      final r = await o3.proposer(_l('arphos Ab'));
      expect(requetes, contains('%arphos'));
      expect(r.propositions.map((p) => p.produit.strNAME), contains('CARPHOS AB SACHET'));
    });

    test('phrase (en-tête, mention) : jamais de fragments', () async {
      for (final t in ['Clinique des carphos de la rue principale du quartier', 'Dr Larphos', 'Patient Garphos']) {
        final r = await _o3().proposer(_l(t));
        expect(r.propositions.where((p) => p.fragment != null), isEmpty, reason: t);
      }
    });
  });

  test('performance : < 50 ms par ligne sur 10 000 produits (correspondance complète + fragments)', () {
    final rnd = math.Random(11);
    const lettres = 'abcdefghijklmnopqrstuvwxyz';
    final produits = <ProductSearchResult>[
      for (var i = 0; i < 10000; i++)
        _p('${List.generate(5 + rnd.nextInt(6), (_) => lettres[rnd.nextInt(26)]).join().toUpperCase()} '
            '${[100, 250, 500, 1000][rnd.nextInt(4)]}MG CP', id: 'p$i'),
      for (final n in _catalogue) _p(n),
    ];
    final o3 = CorrespondanceO3.catalogue(produits, fragments: true);
    const lectures = ['arphos Ab', 'Lufarmxkq 80/480', 'Ceuram 1g', 'Novalgin 500', 'Bnstou', 'Paradkq 500 mg', 'Zqarphoszt'];
    o3.proposer(_l('echauffement'));
    final sw = Stopwatch()..start();
    for (var k = 0; k < 5; k++) {
      for (final l in lectures) {
        o3.proposer(_l(l));
      }
    }
    sw.stop();
    final parLigne = sw.elapsedMicroseconds / (5 * lectures.length) / 1000;
    // ignore: avoid_print
    print('O3b : ${parLigne.toStringAsFixed(1)} ms par ligne sur ${produits.length} produits');
    expect(parLigne, lessThan(50));
  });

  test('banc d\'essai : candidat « O3 + fragments + apprentissages »', () {
    final p = pipelinesBanc(_recherche(_catalogue), lecteur: (_) async => const [], correspondanceO3: () async => _o3(fragments: false));
    expect(p.map((x) => x.id), containsAllInOrder(['reference', 'o3', 'o3_appris', 'o3_fragments']));
    expect(p.last.libelle, 'O3 + fragments + apprentissages');
  });

  group('Réglage et écran Ordonnance', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      LectureO2.mode.value = ModeLecture.actuelle;
      ApprentissagesO4.reinitialiserInstance();
    });

    testWidgets('Réglages : choix « O3+ » ; « Actuelle » reste le défaut', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: LectureO2Reglages()))));
      await tester.pumpAndSettle();
      expect(LectureO2.mode.value, ModeLecture.actuelle);
      await tester.tap(find.text('O3+'));
      await tester.pumpAndSettle();
      expect(LectureO2.mode.value, ModeLecture.o3Fragments);
      expect(LectureO2.correspondanceO3, isTrue);
    });

    testWidgets('proposition par fragment affichée « trouvé par fragment », jamais cochée d\'office', (tester) async {
      SharedPreferences.setMockInitialValues({'ordonnance_lecture_mode_v1': 'o3Fragments'});
      final store = MemoryLocalStore();
      await tester.runAsync(() => store.replace(CatalogueCategorie.produits, [
            for (final n in _catalogue)
              {'lgFAMILLEID': 'id-$n', 'strNAME': n, 'intCIP': '', 'intPRICE': 1000, 'intNUMBERAVAILABLE': 5, 'strLIBELLEE': '', 'intPAF': 800},
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
            textReader: (_) async => const ['1. Lufarmxkq 80/480', '1cp x 2/j'],
            presentation: ListPresentation.dashboard,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Photographier l\'ordonnance'));
      await tester.pumpAndSettle();
      expect(find.text('LUFART 80/480 CP B/6'), findsOneWidget);
      expect(find.textContaining('Trouvé par fragment : …LUFAR…'), findsOneWidget);
      expect(find.textContaining('À vérifier ·'), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
      expect(find.textContaining('Créer la pré-vente (0 produit)'), findsOneWidget);
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
