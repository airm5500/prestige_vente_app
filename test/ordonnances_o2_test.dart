// Étape O2 : découpage par lignes numérotées (textes OCR SYNTHÉTIQUES uniquement), préparation de l'image,
// interrupteurs (désactivés par défaut), branchement au banc d'essai et à l'écran Ordonnance.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/ordonnances/banc_essai/pipelines_disponibles.dart';
import 'package:prestige_vente_app/ordonnances/banc_essai/score_banc.dart';
import 'package:prestige_vente_app/ordonnances/o2/decoupage_ordonnance.dart';
import 'package:prestige_vente_app/ordonnances/o2/lecture_o2.dart';
import 'package:prestige_vente_app/ordonnances/o2/preparation_page.dart';
import 'package:prestige_vente_app/ordonnances/o2/zone_medicaments_screen.dart';
import 'package:prestige_vente_app/parametres/rubriques_pages.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/screens/prescription/prescription_check_screen.dart';
import 'package:prestige_vente_app/services/capture/capture_geometry.dart';
import 'package:prestige_vente_app/services/prescription_parser.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ordonnance manuscrite numérotée (texte fictif, tel que regroupé par ligne).
const _manuscrite = [
  'Clinique Exemple',
  'Tél : 07 00 00 00 00 / 27 00 00 00 00',
  'Abidjan, le 14/05/2025',
  'ORDONNANCE MEDICALE',
  'Nom : Patient Fictif',
  '1. Curam 1g —> 02 bts',
  '1cp x 3/j pdt 10j',
  '2. Brustan B/20 → 01 bte',
  '2cp x 2/j pdt 5j',
  '3. Tramadol denk', // dosage non lu (écriture cursive)
  '1 cp effervescent',
  'Dr Fictif',
  'Chirurgien Dentiste',
  'ONMCI : 000',
];

/// Ordonnance imprimée à tirets, posologie en toutes lettres.
const _imprimee = [
  'Centre Médical Exemple',
  'ORDONNANCE MEDICALE',
  'Abidjan, le 20/05/2025',
  '- DICLOCED 0,1% :',
  'Une goutte trois fois par jour dans l\'oeil droit pendant un mois.',
  '- DIAMOX cp séc 250 mg : 24 :',
  'Un comprimé trois fois par jour au repas',
  '=MONOPROST COLLYRE:',
  'Une goutte le soir dans les deux yeux :',
  'Médecin Ophtalmologiste',
];

/// Numéros entourés (lus « ① » ou « (1) ») et quantités entre parenthèses.
const _cercles = [
  '① Clavam 1g cp (1 bte)',
  '1cp x 2/j pdt 6 jrs',
  '(2) Propofan gél (1 bte)',
  '1 gél x 2/j pdt 3 jrs',
  '③ Eludril pro (1 fl)',
  '10ml + eau x 2/j',
];

ProductSearchResult _p(String name, {int stock = 5}) => ProductSearchResult(
      lgFAMILLEID: name,
      strNAME: name,
      intCIP: '',
      intPRICE: 1000,
      intNUMBERAVAILABLE: stock,
      strLIBELLEE: '',
      intPAF: 800,
    );

const _noms = ['CURAM 1G CP B/16', 'BRUSTAN 400MG CP B/20', 'TRAMADOL DENK 50MG CP', 'DOLIPRANE 1000MG CP'];

ProductPageSearch _catalogue(List<String> noms) => (q, start, limit) async {
      final all = [for (final n in noms) if (n.toLowerCase().startsWith(q.toLowerCase())) _p(n)];
      return VenteOk(ProductPage(all.skip(start).take(limit).toList(), all.length));
    };

class _FakeApi extends ApiService {
  _FakeApi() : super(baseUrl: 'http://localhost');

  @override
  Future<ProductPage> searchProductsPageOrFail(String query, int start, int limit) async {
    final all = [for (final n in _noms) if (n.toLowerCase().startsWith(query.toLowerCase())) _p(n)];
    return ProductPage(all.skip(start).take(limit).toList(), all.length);
  }
}

img.Image _pageSynthetique({bool ombre = true}) {
  final im = img.Image(width: 240, height: 320);
  for (var y = 0; y < im.height; y++) {
    for (var x = 0; x < im.width; x++) {
      final fond = ombre ? 90 + (x * 140 ~/ im.width) : 230; // ombre à gauche
      final trait = (y ~/ 6).isOdd && (y ~/ 24).isEven && x > 20 && x < 220 && (x ~/ 5).isEven;
      final v = trait ? (fond * 0.25).round() : fond;
      im.setPixelRgb(x, y, v, v, v);
    }
  }
  return im;
}

void main() {
  group('Découpage par lignes numérotées', () {
    test('manuscrite : en-têtes, date, nom, tampon ignorés ; posologie et quantité rattachées', () {
      final d = DecoupageOrdonnance.decouper(_manuscrite);
      expect(d.map((l) => l.nom), ['Curam 1g', 'Brustan B/20', 'Tramadol denk']);
      expect(d[0].posologie, '1cp x 3/j pdt 10j');
      expect(d[0].quantite, 2);
      expect(d[1].posologie, '2cp x 2/j pdt 5j');
      expect(d[1].quantite, 1);
      expect(d[2].posologie, '1 cp effervescent');
      expect(d[2].quantite, isNull);
    });

    test('imprimée à tirets : posologie en toutes lettres sur la ligne suivante', () {
      final d = DecoupageOrdonnance.decouper(_imprimee);
      expect(d.map((l) => l.nom), ['DICLOCED 0,1%', 'DIAMOX cp séc 250 mg', 'MONOPROST COLLYRE']);
      expect(d[0].posologie, startsWith('Une goutte trois fois par jour'));
      expect(d[1].posologie, 'Un comprimé trois fois par jour au repas');
    });

    test('numéros entourés ① / (2) et quantités entre parenthèses', () {
      final d = DecoupageOrdonnance.decouper(_cercles);
      expect(d.map((l) => l.nom), ['Clavam 1g cp', 'Propofan gél', 'Eludril pro']);
      expect(d.map((l) => l.quantite), [1, 1, 1]);
      expect(d[2].posologie, '10ml + eau x 2/j');
    });

    test('posologie sur la même ligne, numéro seul sur sa ligne, quantité seule', () {
      final d = DecoupageOrdonnance.decouper([
        '1. Predni 20 cp effervescent 3cp x 1/j pdt 6 jrs (01 bte)',
        '2.',
        'Actisoufre spray',
        '1 pulv x 2/j',
        '→ 02 bts',
        '3) Flagyl 500 mg',
        '- 1cp x 2/j',
      ]);
      expect(d.map((l) => l.nom), ['Predni 20 cp effervescent', 'Actisoufre spray', 'Flagyl 500 mg']);
      expect(d[0].posologie, '3cp x 1/j pdt 6 jrs');
      expect(d[0].quantite, 1);
      expect(d[1].posologie, '1 pulv x 2/j');
      expect(d[1].quantite, 2);
      expect(d[2].posologie, '1cp x 2/j');
    });

    test('tiret mal lu en lettre isolée (« L KALEORID ») : produit gardé, lettre retirée', () {
      final l = DecoupageOrdonnance.extraire([
        '- DIAMOX cp séc 250 mg : 24 :',
        'Un comprimé trois fois par jour au repas',
        'L KALEORID LP cp enrobé LP 1 000 mg ou 600 mg : 30 :',
        'Un comprimé le matin au repas',
      ]);
      expect(l.map((e) => e.query), ['DIAMOX', 'KALEORID']);
      expect(l[1].posology, 'Un comprimé le matin au repas');
    });

    test('« 1 comprimé… » et « 26 BP 1099 » ne sont pas des numéros de ligne', () {
      expect(DecoupageOrdonnance.sansMarqueur('1 comprimé le matin'), isNull);
      expect(DecoupageOrdonnance.sansMarqueur('1cp x 2/j'), isNull);
      expect(DecoupageOrdonnance.sansMarqueur('20/05/2025'), isNull);
      expect(DecoupageOrdonnance.sansMarqueur('01 Clavam 1g'), 'Clavam 1g');
      expect(DecoupageOrdonnance.sansMarqueur('1. Curam'), 'Curam');
      expect(DecoupageOrdonnance.estBruit('26 BP 1099 Abidjan 26'), isTrue);
      expect(DecoupageOrdonnance.estBruit('E-mail : clinique@exemple.com'), isTrue);
      expect(DecoupageOrdonnance.estPosologie('pendant 5 jours'), isTrue);
      expect(DecoupageOrdonnance.estPosologie('Predni 20 cp 3cp x 1/j'), isFalse);
    });

    test('sans ligne numérotée : exactement le découpage d\'origine', () {
      const lignes = ['DOLIPRANE 1000MG CP  1  1 cp x 3/j', 'Tél 07 00 00 00 00', 'AMOXICILLINE 500 mg gél'];
      final o2 = DecoupageOrdonnance.extraire(lignes);
      final ref = PrescriptionParser.extract(lignes);
      expect(o2.map((l) => l.query), ref.map((l) => l.query));
      expect(o2.map((l) => l.posology), ref.map((l) => l.posology));
    });

    test('extraire : lignes pour la correspondance catalogue (quantité, posologie, dosage)', () {
      final l = DecoupageOrdonnance.extraire(_manuscrite);
      expect(l.map((e) => e.query), ['Curam', 'Brustan B20', 'Tramadol denk']);
      expect(l[0].dosage, '1');
      expect(l[0].quantity, 2);
      expect(l[2].posology, '1 cp effervescent');
    });
  });

  group('Banc d\'essai : candidat O2', () {
    test('référence vs O2 sur un texte synthétique', () async {
      final vt = VeriteTerrain.fromJsonString('{"ordonnances":{"ordo (1).jpeg":{"produits":['
          '{"nom":"Curam 1 g"},{"nom":"Brustan B/20"},{"nom":"Tramadol Denk 50 mg"}]}}}');
      final pipelines = pipelinesBanc(_catalogue(_noms), lecteur: (_) async => _manuscrite);
      expect(pipelines.map((p) => p.id).take(4), ['reference', 'o2', 'o2_image', 'o3']);
      final ref = await pipelines[0].analyser('ordo (1).jpeg');
      final o2 = await pipelines[1].analyser('ordo (1).jpeg');
      final sRef = BancScore.evaluer('ordo (1).jpeg', vt.pour('ordo (1).jpeg'), ref.produits);
      final sO2 = BancScore.evaluer('ordo (1).jpeg', vt.pour('ordo (1).jpeg'), o2.produits);
      expect(sO2.entierementCorrecte, isTrue);
      expect(sO2.trouves.length, greaterThan(sRef.trouves.length)); // « Tramadol denk » sans forme : manqué par la référence
    });
  });

  group('Préparation de l\'image', () {
    test('ombres supprimées, texte conservé', () {
      final page = _pageSynthetique();
      final out = PreparationPage.ameliorer(page);
      num fond(img.Image i, int x) => i.getPixel(x, 2).r; // ligne sans trait
      expect((fond(page, 230) - fond(page, 5)).abs(), greaterThan(100));
      expect((fond(out, 230) - fond(out, 5)).abs(), lessThan(40));
      // Un trait reste nettement plus sombre que le fond.
      expect(out.getPixel(22, 7).r, lessThan(fond(out, 22) - 100));
    });

    test('netteté : photo floue refusée', () {
      final nette = _pageSynthetique(ombre: false);
      final floue = img.gaussianBlur(nette.clone(), radius: 8);
      expect(PreparationPage.nettete(floue), lessThan(PreparationPage.nettete(nette) / 3));
      expect(PreparationPage.estFloue(floue), isTrue);
      expect(PreparationPage.estFloue(nette), isFalse);
    });

    test('recadrage sur la zone des médicaments', () {
      final r = PreparationPage.recadrer(_pageSynthetique(), const Rect.fromLTRB(0.5, 0.25, 1, 0.75));
      expect(r.width, 120);
      expect(r.height, 160);
    });

    test('cadre « page » A5/A4 portrait dans l\'écran', () {
      const view = Size(360, 640);
      final f = CaptureGeometry.pageFrameInView(view);
      expect(f.height / f.width, closeTo(1.414, 0.01));
      expect(f.top, greaterThan(64)); // place pour la consigne
      expect(f.left, greaterThanOrEqualTo(0));
      expect(f.right, lessThanOrEqualTo(360));
    });
  });

  group('Interrupteurs (désactivés par défaut)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      LectureO2.mode.value = ModeLecture.actuelle;
      LectureO2.ameliorerImage.value = false;
    });

    testWidgets('Réglages : nouvelle lecture désactivée par défaut, amélioration de l\'image proposée ensuite', (tester) async {
      tester.view.physicalSize = const Size(720, 1400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: LectureO2Reglages()))));
      await tester.pumpAndSettle();
      expect(LectureO2.mode.value, ModeLecture.actuelle);
      expect(find.byKey(const Key('lecture_o2_image')), findsNothing);
      await tester.tap(find.text('O2'));
      await tester.pumpAndSettle();
      expect(LectureO2.mode.value, ModeLecture.o2);
      expect((await SharedPreferences.getInstance()).getString('ordonnance_lecture_mode_v1'), 'o2');
      expect(find.byKey(const Key('lecture_o2_image')), findsOneWidget);
      expect(LectureO2.ameliorerImage.value, isFalse);
      expect(tester.takeException(), isNull);
    });

    Future<void> scan(WidgetTester tester) async {
      final api = _FakeApi();
      await tester.pumpWidget(MultiProvider(
        providers: [
          Provider<ApiService>.value(value: api),
          ChangeNotifierProvider<SaleProvider>.value(value: SaleProvider(api)),
        ],
        child: MaterialApp(
          home: PrescriptionCheckScreen(textReader: (_) async => _manuscrite, presentation: ListPresentation.dashboard),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Photographier l\'ordonnance'));
      await tester.pumpAndSettle();
    }

    testWidgets('écran Ordonnance : découpage d\'origine par défaut', (tester) async {
      await scan(tester);
      expect(find.text('TRAMADOL DENK 50MG CP'), findsNothing);
      expect(find.text('CURAM 1G CP B/16'), findsOneWidget);
    });

    testWidgets('écran Ordonnance : découpage O2 quand il est activé', (tester) async {
      SharedPreferences.setMockInitialValues({'ordonnance_lecture_mode_v1': 'o2'});
      await scan(tester);
      expect(LectureO2.mode.value, ModeLecture.o2);
      expect(find.text('TRAMADOL DENK 50MG CP'), findsOneWidget);
      expect(find.text('CURAM 1G CP B/16'), findsOneWidget);
    });
  });

  group('Zone des médicaments', () {
    testWidgets('360 px : page entière ou zone déplacée', (tester) async {
      tester.view.physicalSize = const Size(720, 1400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      Rect? zone;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async => zone = await Navigator.of(context).push<Rect>(MaterialPageRoute(
              builder: (_) => ZoneMedicamentsScreen(image: MemoryImage(img.encodePng(_pageSynthetique())), taille: const Size(240, 320)),
            )),
            child: const Text('ouvrir'),
          ),
        ),
      ));
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.drag(find.byKey(const Key('zone_hautGauche')), const Offset(0, 40));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('zone_valider')));
      await tester.pumpAndSettle();
      expect(zone, isNotNull);
      expect(zone!.top, greaterThan(0.22));
      expect(zone!.right, closeTo(0.96, 1e-6));

      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('zone_page_entiere')));
      await tester.pumpAndSettle();
      expect(zone, ZoneMedicamentsScreen.pageEntiere);
    });
  });
}
