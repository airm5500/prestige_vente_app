// Étape O5 : lecture avancée en ligne avec consentement. Images SYNTHÉTIQUES générées ici, faux serveur / faux
// fournisseur : jamais de vraie ordonnance ni de vraie API. Désactivée par défaut, consentement, recadrage obligatoire,
// masquage, EXIF retiré, bouton absent sans capacité, hors ligne, lignes → O3, erreurs / délai, journal sans image,
// banc avec confirmation.
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart';
import 'package:prestige_vente_app/ordonnances/banc_essai/banc_essai_screen.dart';
import 'package:prestige_vente_app/ordonnances/banc_essai/pipeline_ordonnance.dart';
import 'package:prestige_vente_app/ordonnances/banc_essai/score_banc.dart';
import 'package:prestige_vente_app/ordonnances/o2/decoupage_ordonnance.dart';
import 'package:prestige_vente_app/ordonnances/o2/lecture_o2.dart';
import 'package:prestige_vente_app/ordonnances/o3/correspondance_o3.dart';
import 'package:prestige_vente_app/ordonnances/o4/apprentissage_o4.dart';
import 'package:prestige_vente_app/ordonnances/o5/banc_o5.dart';
import 'package:prestige_vente_app/ordonnances/o5/lecture_avancee.dart';
import 'package:prestige_vente_app/ordonnances/o5/lecture_avancee_screen.dart';
import 'package:prestige_vente_app/ordonnances/o5/masquage_o5.dart';
import 'package:prestige_vente_app/parametres/rubriques_pages.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/screens/prescription/prescription_check_screen.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _catalogue = ['CURAM 1G CP B/16', 'CURAM 625MG CP B/16', 'BRUSTAN 400MG CP B/20', 'BRUSTAN SUSP BUV', 'DOLIPRANE 1000MG CP B/8'];

ProductSearchResult _p(String n) =>
    ProductSearchResult(lgFAMILLEID: 'id-$n', strNAME: n, intCIP: '', intPRICE: 1000, intNUMBERAVAILABLE: 5, strLIBELLEE: '', intPAF: 800);

/// Page synthétique : en-tête et pied rouges (zones « personnelles »), corps bleu, avec EXIF.
Uint8List _pageSynthetique() {
  final page = img.Image(width: 600, height: 840);
  img.fill(page, color: img.ColorRgb8(250, 250, 250));
  img.fillRect(page, x1: 0, y1: 0, x2: 599, y2: 120, color: img.ColorRgb8(220, 0, 0)); // en-tête / patient
  img.fillRect(page, x1: 0, y1: 760, x2: 599, y2: 839, color: img.ColorRgb8(220, 0, 0)); // signature
  img.fillRect(page, x1: 60, y1: 300, x2: 400, y2: 330, color: img.ColorRgb8(20, 40, 160)); // ligne médicament
  img.drawString(page, '1. Curam 1g', font: img.arial24, x: 60, y: 340, color: img.ColorRgb8(20, 40, 160));
  page.exif.imageIfd['Make'] = 'TelephoneTest';
  return img.encodeJpg(page, quality: 90);
}

/// Faux serveur Prestige (le fournisseur est simulé derrière lui).
class _FauxServeur implements ServeurLectureAvancee {
  bool capacite = true;
  int envois = 0;
  ({int status, Object? body})? reponse;
  Object? exception;
  final List<Uint8List> recues = [];

  @override
  String get adresse => 'http://serveur-test/api/v1';

  @override
  Future<({int status, Object? body})> capacites() async => (status: 200, body: {'success': true, 'lectureAvancee': capacite});

  @override
  Future<({int status, Object? body})> lire(Uint8List jpeg) async {
    envois++;
    recues.add(jpeg);
    if (exception != null) throw exception!;
    return reponse ??
        (
          status: 200,
          body: {
            'success': true,
            'lignes': [
              {'nom': 'Curam', 'dosage': '1 g', 'forme': 'cp', 'posologie': '1 cp x 2/j pendant 7 jours', 'quantite': '2', 'confiance': 0.82},
              {'nom': 'Brustan', 'dosage': '400 mg', 'forme': 'cp', 'posologie': '1 cp x 3/j', 'quantite': '1', 'confiance': 0.74},
            ],
            'coutEstime': 0.000195,
            'quotaRestant': 49,
          }
        );
  }
}

Future<LectureAvancee> _active(_FauxServeur srv, {bool enLigne = true}) async {
  final la = LectureAvancee(serveur: srv, enLigne: () => enLigne);
  await la.definir(true);
  await la.verifierCapacite();
  return la;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    JournalTerminal.instance = JournalTerminal(store: MemoryJournalStore());
    LectureAvancee.instance = LectureAvancee();
    ApprentissagesO4.reinitialiserInstance();
  });

  group('Activation et consentement', () {
    test('consentement noté au journal du terminal (activation / désactivation)', () async {
      final la = LectureAvancee(serveur: _FauxServeur());
      await la.definir(true);
      await la.definir(false);
      await JournalTerminal.instance.idle;
      final j = await JournalTerminal.instance.lire();
      expect(j.where((e) => e.type == TypeJournal.lectureAvancee).map((e) => e.action),
          containsAll(['Lecture avancée activée (consentement donné)', 'Lecture avancée désactivée']));
    });

    test('désactivée par défaut : bouton non proposé, rien n\'est envoyé', () async {
      final srv = _FauxServeur();
      final la = LectureAvancee(serveur: srv);
      await la.charger();
      await la.verifierCapacite();
      expect(la.active.value, isFalse);
      expect(la.proposee, isFalse);
      final r = await la.lire(Uint8List.fromList([0xFF, 0xD8, 0xFF]));
      expect(r.ok, isFalse);
      expect(srv.envois, 0);
    });

    testWidgets('Réglages : activation seulement après l\'écran de consentement (case + « J\'accepte »)', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: LectureAvanceeReglages()))));
      await tester.pumpAndSettle();
      expect(LectureAvancee.instance.active.value, isFalse);
      await tester.tap(find.byKey(const Key('o5_reglage')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Service externe'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(find.byKey(const Key('o5_consentement_ok'))).onPressed, isNull); // case non cochée
      await tester.tap(find.text('Refuser'));
      await tester.pumpAndSettle();
      expect(LectureAvancee.instance.active.value, isFalse);
      await tester.tap(find.byKey(const Key('o5_reglage')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('o5_consentement_case')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('o5_consentement_case')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('o5_consentement_ok')));
      await tester.pumpAndSettle();
      expect(LectureAvancee.instance.active.value, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('ordonnance_o5_lecture_avancee_v1'), isTrue);
      expect(prefs.getString('ordonnance_o5_consentement_v1'), isNotNull);
    });
  });

  group('Image envoyée (protection des données)', () {
    test('recadrage OBLIGATOIRE : la page entière est refusée', () {
      final page = _pageSynthetique();
      expect(MasquageO5.zoneValide(const Rect.fromLTRB(0, 0, 1, 1)), isFalse);
      expect(MasquageO5.zoneValide(const Rect.fromLTRB(0.02, 0.02, 0.98, 0.98)), isFalse);
      expect(() => MasquageO5.preparer(page, const Rect.fromLTRB(0, 0, 1, 1)), throwsArgumentError);
      expect(MasquageO5.zoneValide(const Rect.fromLTRB(0.05, 0.25, 0.95, 0.6)), isTrue);
    });

    test('bandes haut / bas masquées automatiquement, masques à la main, EXIF retiré', () {
      final page = _pageSynthetique();
      expect(MasquageO5.contientExif(page), isTrue);
      // Zone qui déborde sur l'en-tête (rouge) et le pied (rouge).
      const zone = Rect.fromLTRB(0, 0.05, 0.84, 0.97);
      final out = MasquageO5.preparer(page, zone, masques: const [Rect.fromLTRB(0.05, 0.45, 0.5, 0.5)]);
      expect(MasquageO5.contientExif(out), isFalse);
      final z = img.decodeJpg(out)!;
      var rouge = 0;
      for (final p in z) {
        if (p.r > 150 && p.g < 90 && p.b < 90) rouge++;
      }
      expect(rouge, 0); // plus rien de l'en-tête ni du pied
      // Masque à la main : noir.
      final m = z.getPixel((0.25 * z.width).round(), (0.475 * z.height).round());
      expect(m.r + m.g + m.b, lessThan(60));
      // La ligne médicament (bleue) reste visible.
      var bleu = 0;
      for (final p in z) {
        if (p.b > 120 && p.r < 80) bleu++;
      }
      expect(bleu, greaterThan(100));
      expect(MasquageO5.masquesAuto(const Rect.fromLTRB(0.05, 0.25, 0.95, 0.6)), isEmpty);
    });

    testWidgets('écran de masquage : glisser = masque ajouté, renvoyé à « Continuer »', (tester) async {
      final zone = img.encodeJpg(img.Image(width: 400, height: 200)..clear(img.ColorRgb8(255, 255, 255)));
      List<Rect>? res;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async => res = await Navigator.of(ctx).push<List<Rect>>(MaterialPageRoute(builder: (_) => MasquageScreen(zone: zone))),
            child: const Text('ouvrir'),
          ),
        ),
      ));
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
      final centre = tester.getCenter(find.byKey(const Key('o5_masquage_zone')));
      await tester.dragFrom(centre - const Offset(40, 20), const Offset(80, 30));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('o5_masquage_ok')));
      await tester.pumpAndSettle();
      expect(res, hasLength(1));
      expect(res!.single.width, greaterThan(0.05));
    });
  });

  group('Envoi au serveur', () {
    test('faux fournisseur → lignes de médicaments → découpage O2 → correspondance O3', () async {
      final srv = _FauxServeur();
      final la = await _active(srv);
      expect(la.utilisable, isTrue);
      final image = MasquageO5.preparer(_pageSynthetique(), const Rect.fromLTRB(0.05, 0.25, 0.95, 0.6));
      final r = await la.lire(image);
      expect(r.ok, isTrue);
      expect(srv.recues.single, image); // exactement l'image montrée et confirmée
      expect(MasquageO5.contientExif(srv.recues.single), isFalse);
      expect(r.texte.first, startsWith('1. Curam 1 g cp'));
      final lignes = DecoupageOrdonnance.extraire(r.texte);
      expect(lignes, hasLength(2));
      expect(lignes.first.posology, contains('2/j'));
      final o3 = CorrespondanceO3.catalogue([for (final n in _catalogue) _p(n)]);
      expect([for (final l in lignes) (await o3.proposer(l)).meilleure?.produit.strNAME], ['CURAM 1G CP B/16', 'BRUSTAN 400MG CP B/20']);
    });

    test('erreurs : délai, quota, service indisponible, réseau ; une seule lecture à la fois ; pas de relance', () async {
      final srv = _FauxServeur();
      final la = await _active(srv);
      final image = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
      srv.reponse = (status: 504, body: {'success': false, 'msg': 'Lecture avancée impossible : délai dépassé.'});
      expect((await la.lire(image)).erreur, contains('délai dépassé'));
      srv.reponse = (status: 429, body: {'success': false, 'msg': 'Quota de lectures avancées du jour atteint (50).'});
      expect((await la.lire(image)).erreur, contains('Quota'));
      srv.reponse = null;
      srv.exception = DioException(requestOptions: RequestOptions(path: '/'), type: DioExceptionType.receiveTimeout);
      expect((await la.lire(image)).erreur, contains('trop de temps'));
      srv.exception = DioException(requestOptions: RequestOptions(path: '/'), type: DioExceptionType.connectionError);
      expect((await la.lire(image)).erreur, 'Serveur injoignable.');
      expect(srv.envois, 4); // une requête par demande : aucune relance automatique
      srv.exception = null;
      final a = la.lire(image), b = la.lire(image);
      expect((await b).erreur, contains('déjà en cours'));
      expect((await a).ok, isTrue);
      // Serveur qui n'a plus la capacité (404) : bouton retiré.
      srv.reponse = (status: 404, body: null);
      await la.lire(image);
      expect(la.proposee, isFalse);
    });

    test('hors ligne : rien n\'est envoyé (« Disponible en ligne uniquement »)', () async {
      final srv = _FauxServeur();
      final la = await _active(srv, enLigne: false);
      expect(la.proposee, isTrue);
      expect(la.utilisable, isFalse);
      expect((await la.lire(Uint8List.fromList([0xFF, 0xD8, 0xFF]))).erreur, 'Disponible en ligne uniquement.');
      expect(srv.envois, 0);
    });

    test('journal du terminal : date, taille, résultat — jamais l\'image ni le texte lu', () async {
      final srv = _FauxServeur();
      final la = await _active(srv);
      final image = MasquageO5.preparer(_pageSynthetique(), const Rect.fromLTRB(0.05, 0.25, 0.95, 0.6));
      await la.lire(image);
      await JournalTerminal.instance.idle;
      final e = (await JournalTerminal.instance.lire()).where((x) => x.type == TypeJournal.lectureAvancee && x.action.startsWith('Lecture avancée (')).single;
      expect(e.resultat, ResultatJournal.info);
      expect(e.motif, contains('Ko'));
      expect(e.motif, contains('2 médicament(s)'));
      expect(e.motif, isNot(contains('Curam')));
      expect(e.motif.length, lessThan(200));
    });
  });

  group('Écran Ordonnance', () {
    Future<void> ouvrir(WidgetTester tester, {required bool capacite, required bool enLigne, PrescriptionTextReader? lecteur}) async {
      SharedPreferences.setMockInitialValues({'ordonnance_lecture_mode_v1': 'o3', 'ordonnance_o5_lecture_avancee_v1': true});
      final srv = _FauxServeur()..capacite = capacite;
      LectureAvancee.instance = LectureAvancee(serveur: srv, enLigne: () => enLigne);
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
        child: MaterialApp(home: PrescriptionCheckScreen(textReader: lecteur ?? (_) async => null, presentation: ListPresentation.dashboard)),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('serveur sans capacité : bouton absent', (tester) async {
      await ouvrir(tester, capacite: false, enLigne: true);
      expect(find.byKey(const Key('o5_bouton')), findsNothing);
    });

    testWidgets('hors ligne : bouton désactivé « disponible en ligne uniquement »', (tester) async {
      await ouvrir(tester, capacite: true, enLigne: false);
      expect(find.textContaining('disponible en ligne uniquement'), findsOneWidget);
      expect(tester.widget<ButtonStyleButton>(find.byKey(const Key('o5_bouton'))).onPressed, isNull);
    });

    testWidgets('en ligne : lecture avancée → propositions O3, « à vérifier » ou proposées, rien au panier sans validation', (tester) async {
      await ouvrir(tester, capacite: true, enLigne: true, lecteur: (source) async {
        expect(source, PrescriptionSource.avancee);
        final r = await LectureAvancee.instance.lire(MasquageO5.preparer(_pageSynthetique(), const Rect.fromLTRB(0.05, 0.25, 0.95, 0.6)));
        return r.texte;
      });
      expect(LectureO2.correspondanceO3, isTrue);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('o5_bouton')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      expect(find.text('CURAM 1G CP B/16'), findsOneWidget);
      expect(find.text('BRUSTAN 400MG CP B/20'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Banc d\'essai', () {
    testWidgets('candidat « Lecture avancée » : confirmation explicite avant d\'envoyer le jeu d\'images', (tester) async {
      tester.view.physicalSize = const Size(720, 1400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final dir = (await tester.runAsync(() => Directory.systemTemp.createTemp('o5_banc')))!;
      addTearDown(() => dir.deleteSync(recursive: true));
      final chemin = '${dir.path}/ordonnance (1).jpeg';
      File(chemin).writeAsBytesSync(_pageSynthetique());
      final srv = _FauxServeur();
      final la = (await tester.runAsync(() => _active(srv)))!;
      final vt = VeriteTerrain.fromJsonString('{"ordonnances":{"ordonnance (1).jpeg":{"produits":[{"nom":"Curam 1 g"},{"nom":"Brustan 400 mg"}]}}}');
      await tester.pumpWidget(MaterialApp(
        home: BancEssaiScreen(
          verite: vt,
          pipelines: [
            _Vide(),
            PipelineLectureAvancee(service: la, correspondance: () async => CorrespondanceO3.catalogue([for (final n in _catalogue) _p(n)])),
          ],
          choisirImages: () async => [chemin],
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('banc_images')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('banc_lancer')));
      await tester.pumpAndSettle();
      expect(find.text('Envoyer les images au service externe ?'), findsOneWidget);
      expect(find.textContaining('DONNÉES DE SANTÉ'), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(srv.envois, 0);
      await tester.tap(find.byKey(const Key('banc_lancer')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('banc_o5_confirmer')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 100 && find.text('Lancer la mesure').evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(srv.envois, 1);
      expect(MasquageO5.contientExif(srv.recues.single), isFalse);
      // La bande d'en-tête (rouge) n'est jamais envoyée.
      var rouge = 0;
      for (final p in img.decodeJpg(srv.recues.single)!) {
        if (p.r > 150 && p.g < 90 && p.b < 90) rouge++;
      }
      expect(rouge, 0);
    });
  });
}

class _Vide implements PipelineOrdonnance {
  @override
  String get id => 'reference';
  @override
  String get libelle => 'Référence (factice)';
  @override
  Future<ResultatPipeline> analyser(String cheminImage) async => const ResultatPipeline(produits: []);
}

class _FakeApi extends ApiService {
  _FakeApi() : super(baseUrl: 'http://localhost');

  @override
  Future<ProductPage> searchProductsPageOrFail(String query, int start, int limit) async {
    final all = [for (final n in _catalogue) if (n.toLowerCase().startsWith(query.toLowerCase())) _p(n)];
    return ProductPage(all.skip(start).take(limit).toList(), all.length);
  }
}
