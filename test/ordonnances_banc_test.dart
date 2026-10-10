// Banc d'essai des ordonnances (O1) : normalisation, score, vérité terrain, pipeline de référence,
// rapports sans texte reconnu, écran à 360 px avec un pipeline factice.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/ordonnances/banc_essai/banc_essai_screen.dart';
import 'package:prestige_vente_app/ordonnances/banc_essai/historique_banc.dart';
import 'package:prestige_vente_app/ordonnances/banc_essai/normalisation_produit.dart';
import 'package:prestige_vente_app/ordonnances/banc_essai/pipeline_ordonnance.dart';
import 'package:prestige_vente_app/ordonnances/banc_essai/score_banc.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:shared_preferences/shared_preferences.dart';

bool _ok(String attendu, String propose) => NormalisationProduit.correspondTexte(attendu, propose);

ProductSearchResult _p(String name, {int stock = 5}) => ProductSearchResult(
      lgFAMILLEID: name,
      strNAME: name,
      intCIP: '',
      intPRICE: 1000,
      intNUMBERAVAILABLE: stock,
      strLIBELLEE: '',
      intPAF: 800,
    );

/// Catalogue factice, recherche « commence par » comme le serveur.
ProductPageSearch _catalogue(List<String> noms) => (q, start, limit) async {
      final all = [for (final n in noms) if (n.toLowerCase().startsWith(q.toLowerCase())) _p(n)];
      return VenteOk(ProductPage(all.skip(start).take(limit).toList(), all.length));
    };

class _PipelineFactice implements PipelineOrdonnance {
  @override
  final String id;
  @override
  final String libelle;
  final Map<String, List<String>> reponses;
  _PipelineFactice(this.id, this.libelle, this.reponses);

  @override
  Future<ResultatPipeline> analyser(String chemin) async =>
      ResultatPipeline(produits: reponses[VeriteTerrain.cleFichier(chemin)] ?? const []);
}

void main() {
  group('Normalisation', () {
    test('casse, accents, formes et ponctuation ignorés', () {
      final n = NormalisationProduit.normaliser('Débridat SP (suspension)');
      expect(n.mots, ['debridat']);
      expect(_ok('Débridat SP (suspension)', 'DEBRIDAT 4.8MG/ML SUSP BUV'), isTrue);
      expect(_ok('Efferalgan pédiatrique', 'EFFERALGAN PEDIATRIQUE 3% SOL BUV'), isTrue);
      expect(_ok('Antalgex gélules', 'ANTALGEX GEL B/20'), isTrue);
      expect(_ok('Verorab injectable', 'VERORAB INJ'), isTrue);
      expect(_ok('Spasmo-Apotel suppo', 'SPASMOAPOTEL SUPPO'), isTrue);
      expect(_ok('Bio-Ritmo AB (ampoule buvale)', 'BIO RITMO AB AMP BUV'), isTrue);
      expect(_ok('Monoprost collyre', 'MONOPROST 50MCG/ML COLLYRE'), isTrue);
    });

    test('dosage : comparé seulement s\'il est connu des deux côtés, 1 g = 1000 mg', () {
      expect(_ok('Curam 1 g', 'CURAM 1000MG CP'), isTrue);
      expect(_ok('Curam 1 g', 'CURAM 625MG CP'), isFalse);
      expect(_ok('Brustan 400 mg', 'BRUSTAN CP B/20'), isTrue);
      expect(_ok('Lufar 80/480', 'LUFART 80/480 CP'), isTrue);
      expect(_ok('Kaleorid LP 1000 mg ou 600 mg', 'KALEORID LP 600MG CP'), isTrue);
      expect(_ok('Dicloced 0,1 %', 'DICLOCED 0.1% COLLYRE'), isTrue);
      expect(_ok('Brustan B/20', 'BRUSTAN 400MG CP'), isTrue);
    });

    test('tolérance d\'écart de lettres selon la longueur', () {
      expect(NormalisationProduit.levenshtein('curam', 'ceuram'), 1);
      expect(_ok('Curam 1 g', 'CEURAM 1G'), isTrue); // 1 lettre sur 5
      expect(_ok('Brustan', 'BNSTOU'), isFalse); // trop loin
      expect(_ok('Dolowin Plus cp', 'DOLAREN PLUS CP'), isFalse);
      expect(_ok('Dontomycine 3m cp', 'SPIRAMYCINE 3MUI CP'), isFalse);
      expect(_ok('Flagyl', 'FLAGIL 500MG'), isTrue);
      expect(_ok('Predni 20 mg cp', 'PREDNISOLONE 20MG CP'), isTrue); // préfixe ≥ 5 lettres
    });

    test('qualificatifs qui changent le produit (Plus, Pro, T, AB, Denk…)', () {
      expect(_ok('Doliprane', 'DOLIPRANE PLUS CP'), isFalse);
      expect(_ok('Eludril Pro', 'ELUDRIL PRO SOLUTION'), isTrue);
      expect(_ok('Eludril Pro', 'ELUDRIL SOLUTION'), isFalse);
      expect(_ok('Antalgex T gélules', 'ANTALGEX GEL'), isFalse);
      expect(_ok('Antalgex gélules', 'ANTALGEX T GEL'), isFalse);
      expect(_ok('Tramadol Denk 50 mg', 'TRAMADOL DENK 50MG'), isTrue);
      expect(_ok('Efferalgan pédiatrique', 'EFFERALGAN 500MG CP'), isFalse); // souple mais attendu
      expect(_ok('Efferalgan', 'EFFERALGAN PEDIATRIQUE'), isTrue);
    });

    test('cas « (?) » : lecture incertaine marquée, ignorée pour la comparaison', () {
      final n = NormalisationProduit.normaliser('Propofan (?)');
      expect(n.incertain, isTrue);
      expect(n.mots, ['propofan']);
      expect(_ok('Propofan gel', 'Propofan (?)'), isTrue);
      expect(_ok('Gaspral 20 (?)', 'GASPRAL 20MG CP'), isTrue);
      expect(NormalisationProduit.normaliser('Gaspral 20').incertain, isFalse);
    });
  });

  group('Score', () {
    const v = VeriteOrdonnance('ordonnance (2).jpeg', [
      ProduitAttendu('Dontomycine 3m cp'),
      ProduitAttendu('Flagyl cp'),
      ProduitAttendu('Brustan cp'),
    ]);

    test('trouvés, manqués, faux positifs', () {
      final s = BancScore.evaluer('ordonnance (2).jpeg', v, ['FLAGYL 500MG CP', 'BRUSTAN 400MG CP', 'DOLIPRANE 1000MG']);
      expect(s.trouves.map((t) => t.$1.nom), ['Flagyl cp', 'Brustan cp']);
      expect(s.manques.map((m) => m.nom), ['Dontomycine 3m cp']);
      expect(s.fauxPositifs, ['DOLIPRANE 1000MG']);
      expect(s.entierementCorrecte, isFalse);
      expect(s.statut, '2/3');
    });

    test('une proposition en double compte comme faux positif', () {
      final s = BancScore.evaluer('x', const VeriteOrdonnance('x', [ProduitAttendu('Flagyl')]), ['FLAGYL CP', 'FLAGYL 500MG']);
      expect(s.trouves, hasLength(1));
      expect(s.fauxPositifs, ['FLAGYL 500MG']);
    });

    test('global : rappel, précision, ordonnances entièrement correctes ; sans vérité exclues', () {
      final g = ScoreGlobal([
        BancScore.evaluer('a', v, ['DONTOMYCINE 3MUI CP', 'FLAGYL CP', 'BRUSTAN CP']), // 3/3, correcte
        BancScore.evaluer('b', const VeriteOrdonnance('b', [ProduitAttendu('Curam 1 g'), ProduitAttendu('Tramadol Denk 50 mg')]),
            ['CURAM 1G', 'AUGMENTIN']), // 1/2, 1 FP
        BancScore.evaluer('c', const VeriteOrdonnance('c', [], aCompleter: true), ['X']), // vérité à compléter
        BancScore.evaluer('d', null, ['Y']), // inconnue
      ]);
      expect(g.nbComptees, 2);
      expect(g.nbAttendus, 5);
      expect(g.nbTrouves, 4);
      expect(g.nbFauxPositifs, 1);
      expect(g.rappel, closeTo(0.8, 1e-9));
      expect(g.precision, closeTo(0.8, 1e-9));
      expect(g.correctes, '1/2');
      expect(g.ordonnances[2].statut, 'Vérité à compléter');
      expect(g.ordonnances[3].statut, 'Pas de vérité terrain');
    });

    test('rien proposé : rappel 0, précision 1 ; erreur : jamais correcte', () {
      final g = ScoreGlobal([BancScore.evaluer('a', v, const [])]);
      expect(g.rappel, 0);
      expect(g.precision, 1);
      final e = BancScore.evaluer('a', const VeriteOrdonnance('a', [ProduitAttendu('Flagyl')]), ['FLAGYL'], erreur: 'panne');
      expect(e.entierementCorrecte, isFalse);
    });
  });

  group('Vérité terrain (asset)', () {
    final json = File('assets/ordonnances/verite_terrain.json').readAsStringSync();

    test('17 ordonnances indexées par nom de fichier, 15 avec vérité, 14 et 15 doublons de 3 et 2', () {
      final vt = VeriteTerrain.fromJsonString(json);
      expect(vt.ordonnances, hasLength(17));
      expect(vt.ordonnances.values.where((o) => o.scorable), hasLength(15));
      expect(vt.pour('/storage/emulated/0/Download/Ordonnance (14).JPEG')!.doublonDe, 'ordonnance (3).jpeg');
      expect(vt.pour('ordonnance (15).jpeg')!.doublonDe, 'ordonnance (2).jpeg');
      expect(vt.pour('ordonnance (15).jpeg')!.scorable, isFalse);
      expect(BancScore.evaluer('ordonnance (14).jpeg', vt.pour('ordonnance (14).jpeg'), ['CLAVAM 1G']).statut,
          'Doublon de ordonnance (3).jpeg');
      expect(vt.pour('ordonnance (8).jpeg')!.produits, hasLength(5));
      expect(vt.pour('autre.jpg'), isNull);
      final total = vt.ordonnances.values.fold<int>(0, (s, o) => s + o.produits.length);
      expect(total, 45);
    });

    test('seulement produits, posologie, quantité (aucune donnée patient / médecin)', () {
      final vt = VeriteTerrain.fromJsonString(json);
      for (final o in vt.ordonnances.values) {
        for (final p in o.produits) {
          expect(p.toJson().keys.toSet().difference({'nom', 'posologie', 'quantite'}), isEmpty);
        }
      }
      final lower = NormalisationProduit.sansAccents([
        for (final o in vt.ordonnances.values) ...[o.remarque ?? '', for (final p in o.produits) '${p.nom} ${p.posologie ?? ''}'],
      ].join('\n'));
      for (final mot in ['docteur', 'dr', 'patient', 'patiente', 'clinique', 'ne le', 'tel', 'adresse', 'age', 'nom', 'prenom']) {
        expect(RegExp('\\b$mot\\b').hasMatch(lower), isFalse, reason: mot);
      }
    });

    test('la vérité se retrouve elle-même (score parfait)', () {
      final vt = VeriteTerrain.fromJsonString(json);
      final g = ScoreGlobal([
        for (final o in vt.ordonnances.values) BancScore.evaluer(o.fichier, o, [for (final p in o.produits) p.nom]),
      ]);
      expect(g.correctes, '15/15');
    });

    test('versionAppli = version de pubspec.yaml', () {
      final v = RegExp(r'^version:\s*([0-9.]+)', multiLine: true).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1);
      expect(versionAppli, v);
    });
  });

  group('Pipeline de référence (scan actuel)', () {
    test('texte lu → lignes → catalogue ; rapport sans le texte reconnu', () async {
      final pipeline = PipelineTexteCatalogue.reference(
        _catalogue(['FLAGYL 500MG CP B/20', 'BRUSTAN 400MG CP B/20', 'DOLIPRANE 1000MG CP']),
        lecteur: (_) async => ['Docteur SECRETMED', 'Patient : NOMSECRET', '1. Flagyl 500 mg cp', '2. Brustan cp', 'Inconnu 20 mg'],
      );
      final r = await pipeline.analyser('/x/ordonnance (2).jpeg');
      expect(r.produits, ['FLAGYL 500MG CP B/20', 'BRUSTAN 400MG CP B/20']);
      expect(r.lignesDetectees, 3);
      expect(r.lignesSansProduit, 1);
      final score = ScoreGlobal([
        BancScore.evaluer('ordonnance (2).jpeg',
            const VeriteOrdonnance('ordonnance (2).jpeg', [ProduitAttendu('Flagyl cp'), ProduitAttendu('Brustan cp')]), r.produits),
      ]);
      final texte = RapportBanc.texte({pipeline.libelle: score});
      final csv = RapportBanc.csv({pipeline.libelle: score});
      for (final out in [texte, csv]) {
        expect(out, isNot(contains('NOMSECRET')));
        expect(out, isNot(contains('SECRETMED')));
        expect(out, contains('FLAGYL 500MG CP B/20'));
      }
      expect(csv.split('\n').first, 'pipeline;fichier;statut;resultat;attendu;propose');
      expect(texte, contains('1/1 ordonnances entièrement correctes'));
    });

    test('lecture impossible : erreur sans planter', () async {
      final pipeline = PipelineTexteCatalogue.reference(_catalogue(const []), lecteur: (_) async => throw StateError('x'));
      final r = await pipeline.analyser('a.jpg');
      expect(r.erreur, contains('Lecture impossible'));
      expect(r.produits, isEmpty);
    });
  });

  group('Historique', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('enregistré sur l\'appareil, le plus récent d\'abord', () async {
      final g = ScoreGlobal([BancScore.evaluer('a', const VeriteOrdonnance('a', [ProduitAttendu('Flagyl')]), ['FLAGYL'])]);
      await HistoriqueBanc.ajouter(EntreeHistorique.depuis(g, pipeline: 'Référence', date: DateTime(2026, 10, 1)));
      await HistoriqueBanc.ajouter(EntreeHistorique.depuis(g, pipeline: 'O2', date: DateTime(2026, 10, 2)));
      final h = await HistoriqueBanc.charger();
      expect(h.map((e) => e.pipeline), ['O2', 'Référence']);
      expect(h.first.version, versionAppli);
      expect(h.first.correctes, 1);
      expect(h.first.rappel, 1);
    });
  });

  group('Écran', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('360 px : choix des images, référence vs candidat, score, export sans texte lu', (tester) async {
      tester.view.physicalSize = const Size(720, 1400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final vt = VeriteTerrain.fromJsonString(File('assets/ordonnances/verite_terrain.json').readAsStringSync());
      final exports = <String, String>{};
      await tester.pumpWidget(MaterialApp(
        home: BancEssaiScreen(
          verite: vt,
          pipelines: [
            _PipelineFactice('reference', 'Référence (scan actuel)', {
              'ordonnance (7)': ['ANTALGEX GEL B/20'],
              'ordonnance (12)': ['CURAM 1G CP', 'DOLIPRANE 1000MG'],
            }),
            _PipelineFactice('o2', 'O2 (factice)', {
              'ordonnance (7)': ['ANTALGEX GEL B/20'],
              'ordonnance (12)': ['CURAM 1G CP', 'BRUSTAN 400MG CP B/20', 'TRAMADOL DENK 50MG CP'],
            }),
          ],
          choisirImages: () async => ['/d/ordonnance (12).jpeg', '/d/ordonnance (7).jpeg', '/d/ordonnance (14).jpeg'],
          exporter: (nom, contenu) async => exports[nom] = contenu,
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('banc_images')));
      await tester.pumpAndSettle();
      expect(find.text('3 image(s) choisie(s), dont 2 avec vérité terrain.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('banc_lancer')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('1/2'), findsOneWidget); // référence : ordonnance 7 correcte, 12 non
      await tester.scrollUntilVisible(find.byKey(const Key('banc_verdict')), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('2/2'), findsOneWidget); // candidat
      expect(find.text('Candidat meilleur que la référence.'), findsOneWidget);

      // Ordre naturel des fichiers ; ordonnance 14 exclue.
      await tester.scrollUntilVisible(find.byKey(const Key('banc_ord_2')), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('ordonnance (14).jpeg'), findsOneWidget);
      await tester.tap(find.text('ordonnance (14).jpeg'));
      await tester.pumpAndSettle();
      expect(find.text('Doublon de ordonnance (3).jpeg : exclue du score.'), findsWidgets);
      expect(tester.takeException(), isNull);

      await tester.scrollUntilVisible(find.byKey(const Key('banc_export_csv')), -200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byKey(const Key('banc_export_csv')));
      await tester.pumpAndSettle();
      final csv = exports.values.single;
      expect(csv, contains('"Référence (scan actuel)";"ordonnance (12).jpeg";"1/3";"faux_positif";"";"DOLIPRANE 1000MG"'));

      final h = await HistoriqueBanc.charger();
      expect(h.map((e) => e.pipeline).toSet(), {'Référence (scan actuel)', 'O2 (factice)'});
    });
  });
}
