// Étape O4 : apprentissage par correction (lectures et catalogue SYNTHÉTIQUES) : filtrage des segments,
// priorité dans O3, confirmations / contradictions, oubli, partage entre terminaux (faux serveur), file hors ligne,
// avec / sans capacité, partage désactivé, banc d'essai simulé, écran Ordonnance, Réglages.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/horsligne/catalogue_delta.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart';
import 'package:prestige_vente_app/ordonnances/banc_essai/pipelines_disponibles.dart';
import 'package:prestige_vente_app/ordonnances/banc_essai/score_banc.dart';
import 'package:prestige_vente_app/ordonnances/o2/lecture_o2.dart';
import 'package:prestige_vente_app/ordonnances/o3/correspondance_o3.dart';
import 'package:prestige_vente_app/ordonnances/o4/apprentissage_o4.dart';
import 'package:prestige_vente_app/ordonnances/o4/apprentissages_screen.dart';
import 'package:prestige_vente_app/ordonnances/o4/banc_o4.dart';
import 'package:prestige_vente_app/ordonnances/o4/partage_o4.dart';
import 'package:prestige_vente_app/ordonnances/o4/segment_medicament.dart';
import 'package:prestige_vente_app/parametres/rubriques_pages.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/screens/prescription/prescription_check_screen.dart';
import 'package:prestige_vente_app/services/prescription_parser.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProductSearchResult _p(String name, {int stock = 5}) => ProductSearchResult(
      lgFAMILLEID: 'id-$name',
      strNAME: name,
      intCIP: '${name.hashCode.abs() % 9000000 + 1000000}',
      intPRICE: 1000,
      intNUMBERAVAILABLE: stock,
      strLIBELLEE: '',
      intPAF: 800,
    );

const _catalogue = [
  'CURAM 1G CP B/16',
  'CURAM 625MG CP B/16',
  'BRUSTAN 400MG CP B/20',
  'BRUSTAN SUSP BUV',
  'BRUFEN 400MG CP',
  'EFFERALGAN PEDIATRIQUE 3% SOL BUV',
  'DOLIPRANE 1000MG CP B/8',
  'FLAGYL 500MG CP B/14',
  'TRAMADOL DENK 50MG CP',
  'LUFART 80/480 CP B/6',
  'DONTOMYCINE 3MUI CP B/16',
  'SPIRAMYCINE 3MUI CP',
];

String _id(String nom) => 'id-$nom';

CorrespondanceO3 _o3([SourceApprentissages? a]) => CorrespondanceO3.catalogue([for (final n in _catalogue) _p(n)], apprentissages: a);

ProductPageSearch _recherche(List<String> noms) => (q, start, limit) async {
      final all = [for (final n in noms) if (n.toLowerCase().startsWith(q.toLowerCase())) _p(n)];
      return VenteOk(ProductPage(all.skip(start).take(limit).toList(), all.length));
    };

PrescriptionLine _ligne(String t) => PrescriptionLine(text: t, query: t);

/// Faux serveur des corrections (comme le patch : idempotent par clé, différentiel avec horloge du serveur).
class _FauxServeur implements ServeurCorrections {
  bool capacite = true;
  bool panne = false;
  final Map<String, Map<String, dynamic>> table = {};
  final List<String> recuLe = [];
  int envois = 0, lectures = 0, capacitesLues = 0;
  var _t = DateTime.utc(2026, 10, 11, 8);

  @override
  String get adresse => 'http://serveur-test/api/v1';

  void _tick() => _t = _t.add(const Duration(seconds: 5));

  @override
  Future<({int status, Object? body})> capacites() async {
    capacitesLues++;
    if (panne) throw Exception('réseau');
    return (status: 200, body: {'success': true, 'clientRef': true, if (capacite) 'ordonnanceCorrections': true});
  }

  void ajouterAutre(String cle, String segment, String produit) {
    _tick();
    table[cle] = {'cle': cle, 'segment': segment, 'produitId': _id(produit), 'nom': produit, 'recuLe': CatalogueDelta.ecrireHeure(_t)};
  }

  @override
  Future<({int status, Object? body})> envoyer(List<Map<String, dynamic>> lot) async {
    if (panne) throw Exception('réseau');
    if (!capacite) return (status: 404, body: null);
    envois++;
    var n = 0, deja = 0;
    _tick();
    for (final c in lot) {
      if (table.containsKey(c['cle'])) {
        deja++;
      } else {
        table['${c['cle']}'] = {...c, 'recuLe': CatalogueDelta.ecrireHeure(_t)};
        n++;
      }
    }
    return (status: 200, body: {'success': true, 'recus': lot.length, 'enregistres': n, 'dejaConnus': deja, 'rejetes': []});
  }

  @override
  Future<({int status, Object? body})> changements(Map<String, dynamic> query) async {
    if (panne) throw Exception('réseau');
    lectures++;
    final depuis = query['depuis'] == null ? null : CatalogueDelta.lireHeure('${query['depuis']}');
    final data = [
      for (final e in table.values)
        if (depuis == null || CatalogueDelta.lireHeure('${e['recuLe']}')!.isAfter(depuis)) e,
    ];
    return (status: 200, body: {'success': true, 'serveurMaintenant': CatalogueDelta.ecrireHeure(_t), 'total': data.length, 'data': data});
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ApprentissagesO4.reinitialiserInstance();
    PartageO4.instance = PartageO4();
    JournalTerminal.instance = JournalTerminal(store: MemoryJournalStore());
  });

  group('Segment médicament (filtrage, données de santé)', () {
    test('seul le segment médicament est gardé : sans numéro, posologie ni quantité', () {
      expect(SegmentMedicament.extraire('1. Bnstou 400 mg  2cp x 2/j pdt 5 jrs'), 'bnstou 400mg');
      expect(SegmentMedicament.extraire('Efferalgan pédiatrique 1 dose 3kg x 3/j'), 'efferalgan pediatrique');
      expect(SegmentMedicament.extraire('2) Ceuram 1g → 02 bts'), 'ceuram 1g');
      expect(SegmentMedicament.extraire('Lufar 80/480'), 'lufar 80/480');
    });

    test('lignes personnelles refusées : nom avec titre, téléphone, date, e-mail, adresse, âge', () {
      for (final t in [
        'Dr KOUASSI Jean',
        'Mme Aya Koné',
        'Patient : Traoré',
        'Tél : 07 08 09 10 11',
        'Né le 12/03/1990',
        'contact@clinique.ci',
        'BP 1234 Abidjan',
        'Age : 5 ans',
        'Matricule 12345678',
        '15/09/2026',
      ]) {
        expect(SegmentMedicament.extraire(t), isNull, reason: t);
      }
    });

    test('borné : 4 mots, 40 caractères ; phrase ou ligne sans lettres refusée', () {
      final s = SegmentMedicament.extraire('Amoxicilline acide clavulanique enfant 100mg/12,5mg');
      expect(s, isNotNull);
      expect(s!.split(' ').length, lessThanOrEqualTo(SegmentMedicament.motsMax));
      expect(s.length, lessThanOrEqualTo(SegmentMedicament.longueurMax));
      expect(SegmentMedicament.extraire('prendre un comprimé le matin et un le soir avant repas'), isNull);
      expect(SegmentMedicament.extraire('12 500'), isNull);
    });
  });

  group('Apprentissage et priorité dans O3', () {
    test('lecture illisible pour O3 : apprise, proposée en tête « à vérifier » puis « sûre » après 2 validations', () async {
      final a = ApprentissagesO4.memoire();
      expect((await _o3(a).proposer(_ligne('Xqzvt 400 mg'))).meilleure, isNull);
      await a.apprendre(segment: SegmentMedicament.extraire('Xqzvt 400 mg')!, produitId: _id('BRUSTAN 400MG CP B/20'), nom: 'BRUSTAN 400MG CP B/20');
      var r = await _o3(a).proposer(_ligne('2. Xqzvt 400 mg'));
      expect(r.meilleure!.produit.strNAME, 'BRUSTAN 400MG CP B/20');
      expect(r.meilleure!.apprise, isNotNull);
      expect(r.meilleure!.confiance, greaterThanOrEqualTo(CorrespondanceO3.seuilProposition));
      expect(r.sur, isFalse); // 1 confirmation : à vérifier
      await a.apprendre(segment: 'xqzvt 400mg', produitId: _id('BRUSTAN 400MG CP B/20'));
      r = await _o3(a).proposer(_ligne('Xqzvt 400 mg'));
      expect(r.sur, isTrue); // 2 confirmations : sûre (au-dessus du seuil, nettement devant)
      // Presque identique (une lettre lue autrement) : même apprentissage.
      expect((await _o3(a).proposer(_ligne('Xqzvl 400 mg'))).meilleure!.produit.strNAME, 'BRUSTAN 400MG CP B/20');
      // Texte différent : pas d'apprentissage appliqué.
      expect((await _o3(a).proposer(_ligne('Doliprane 1000 mg'))).meilleure!.apprise, isNull);
    });

    test('apprentissage prioritaire sur une correspondance O3 trompeuse (BRUFEN lu → le pharmacien veut BRUSTAN)', () async {
      final a = ApprentissagesO4.memoire();
      expect(_o3(a).proposerTexte('Brufen 400 mg').first.produit.strNAME, 'BRUFEN 400MG CP');
      await a.apprendre(segment: 'brufen 400mg', produitId: _id('BRUSTAN 400MG CP B/20'));
      final p = _o3(a).proposerTexte('Brufen 400 mg');
      expect(p.first.produit.strNAME, 'BRUSTAN 400MG CP B/20');
      expect(p.map((x) => x.produit.strNAME), contains('BRUFEN 400MG CP')); // reste consultable (« Changer »)
      expect(p[1].confiance, lessThanOrEqualTo(p.first.confiance));
    });

    test('contredite plusieurs fois : perd sa priorité ; le nouveau produit prend la tête', () async {
      final a = ApprentissagesO4.memoire();
      for (var i = 0; i < 2; i++) {
        await a.apprendre(segment: 'dontomycine 3m', produitId: _id('SPIRAMYCINE 3MUI CP'));
      }
      expect(_o3(a).proposerTexte('Dontomycine 3m').first.produit.strNAME, 'SPIRAMYCINE 3MUI CP');
      await a.apprendre(segment: 'dontomycine 3m', produitId: _id('DONTOMYCINE 3MUI CP B/16'));
      final ancien = a.liste.firstWhere((x) => x.produitId == _id('SPIRAMYCINE 3MUI CP'));
      expect(ancien.contradictions, 1);
      await a.apprendre(segment: 'dontomycine 3m', produitId: _id('DONTOMYCINE 3MUI CP B/16'));
      expect(ancien.active, isFalse);
      final r = await _o3(a).proposer(_ligne('Dontomycine 3m'));
      expect(r.meilleure!.produit.strNAME, 'DONTOMYCINE 3MUI CP B/16');
      expect(r.sur, isTrue);
    });

    test('oublier une association, tout réinitialiser ; enregistré sur l\'appareil', () async {
      final a = await ApprentissagesO4.charger();
      await a.apprendre(segment: 'ceuram 1g', produitId: _id('CURAM 1G CP B/16'), nom: 'CURAM 1G CP B/16');
      await a.apprendre(segment: 'bnstou', produitId: _id('BRUSTAN SUSP BUV'), nom: 'BRUSTAN SUSP BUV');
      ApprentissagesO4.reinitialiserInstance();
      final b = await ApprentissagesO4.charger();
      expect(b.nombre, 2);
      expect(b.rechercher('curam').single.segment, 'ceuram 1g');
      await b.oublier(b.rechercher('ceuram').single);
      expect(_o3(b).proposerTexte('Ceuram 1g').first.apprise, isNull);
      await b.reinitialiser();
      ApprentissagesO4.reinitialiserInstance();
      expect((await ApprentissagesO4.charger()).nombre, 0);
      // Seuls des segments et produits sont stockés.
      final raw = (await SharedPreferences.getInstance()).getString(ApprentissagesO4.cle)!;
      expect(raw, isNot(contains('Patient')));
    });

    test('le bonus « produits vendus » se nourrit des validations reçues des autres terminaux', () async {
      final a = ApprentissagesO4.memoire();
      await a.apprendre(segment: 'flagyl', produitId: _id('FLAGYL 500MG CP B/14'), partagee: true);
      final pop = PopulariteAvecApprentissages(const PopulariteMemoire({}), a);
      expect(pop.ventes(_id('FLAGYL 500MG CP B/14')), 1);
      expect(pop.ventes(_id('CURAM 1G CP B/16')), 0);
    });

    test('sans apprentissages : O3 strictement inchangé', () {
      final sans = CorrespondanceO3.catalogue([for (final n in _catalogue) _p(n)]);
      final vide = _o3(ApprentissagesO4.memoire());
      for (final t in ['Ceuram 1g', 'Bnstou 400 mg', 'Tramadol denk', 'Lufar 80/480']) {
        expect(vide.proposerTexte(t).map((x) => '${x.produit.strNAME}${x.confiance}'), sans.proposerTexte(t).map((x) => '${x.produit.strNAME}${x.confiance}'));
      }
    });
  });

  group('Partage entre terminaux', () {
    test('hors ligne : validation en file, envoyée au retour (sans confirmation), journal « info », idempotent', () async {
      final srv = _FauxServeur();
      var enLigne = false;
      final partage = PartageO4(serveur: srv, enLigne: () => enLigne);
      final seg = await partage.enregistrerValidation(texteLu: '1. Bnstou 400 mg 2cp x 2/j', produitId: _id('BRUSTAN 400MG CP B/20'), nom: 'BRUSTAN 400MG CP B/20');
      expect(seg, 'bnstou 400mg');
      expect(partage.enAttente.value, 1);
      await partage.synchroniser();
      expect(srv.envois, 0);
      // Apprentissage local immédiat, même hors ligne.
      expect((await ApprentissagesO4.charger()).chercher('bnstou 400mg'), isNotEmpty);
      enLigne = true;
      final b = await partage.synchroniser();
      expect(b.envoyees, 1);
      expect(partage.enAttente.value, 0);
      expect(srv.table.values.single['segment'], 'bnstou 400mg');
      expect(srv.table.values.single.toString(), isNot(contains('2cp')));
      await JournalTerminal.instance.idle;
      final j = await JournalTerminal.instance.lire();
      expect(j.where((e) => e.type == TypeJournal.ordonnance && e.resultat == ResultatJournal.info), isNotEmpty);
      // Renvoi de la même clé : rien de plus côté serveur.
      final cle = srv.table.keys.single;
      await srv.envoyer([srv.table[cle]!]);
      expect(srv.table.length, 1);
    });

    test('panne pendant l\'envoi : la file est gardée et le journal le note', () async {
      final srv = _FauxServeur();
      final partage = PartageO4(serveur: srv);
      await partage.verifierCapacite();
      srv.panne = true;
      await partage.enregistrerValidation(texteLu: 'Ceuram 1g', produitId: _id('CURAM 1G CP B/16'));
      final b = await partage.synchroniser();
      expect(b.envoyees, 0);
      expect(partage.enAttente.value, 1);
      srv.panne = false;
      await partage.synchroniser();
      expect(partage.enAttente.value, 0);
      expect(srv.table, hasLength(1));
    });

    test('réception différentielle : validations des autres terminaux apprises une fois ; les siennes ignorées', () async {
      final srv = _FauxServeur();
      final partage = PartageO4(serveur: srv);
      await partage.enregistrerValidation(texteLu: 'Ceuram 1g', produitId: _id('CURAM 1G CP B/16'));
      srv.ajouterAutre('O4-autre-1', 'xqzvt 400mg', 'BRUSTAN 400MG CP B/20');
      srv.ajouterAutre('O4-autre-2', 'xqzvt 400mg', 'BRUSTAN 400MG CP B/20');
      var b = await partage.synchroniser();
      expect(b.recues, 2);
      final a = await ApprentissagesO4.charger();
      expect(a.chercher('xqzvt 400mg').first.association.confirmations, 2);
      expect(a.chercher('xqzvt 400mg').first.sure, isTrue);
      expect(a.validationsPartagees(_id('BRUSTAN 400MG CP B/20')), 2);
      // Sa propre validation (renvoyée par le serveur) n'est pas comptée deux fois.
      expect(a.chercher('ceuram 1g').first.association.confirmations, 1);
      // Nouvelle synchro (chevauchement de 2 min) : rien n'est réappliqué.
      b = await partage.synchroniser();
      expect(b.recues, 0);
      srv.ajouterAutre('O4-autre-3', 'tramadol denk', 'TRAMADOL DENK 50MG CP');
      b = await partage.synchroniser();
      expect(b.recues, 1);
    });

    test('serveur sans capacité : apprentissage local seulement, rien n\'est envoyé ni demandé', () async {
      final srv = _FauxServeur()..capacite = false;
      final partage = PartageO4(serveur: srv);
      await partage.enregistrerValidation(texteLu: 'Ceuram 1g', produitId: _id('CURAM 1G CP B/16'));
      await partage.synchroniser();
      expect(srv.envois + srv.lectures, 0);
      expect(partage.enAttente.value, 0);
      expect(partage.actif, isFalse);
      await partage.enregistrerValidation(texteLu: 'Flagyl 500', produitId: _id('FLAGYL 500MG CP B/14'));
      expect(partage.enAttente.value, 0);
      expect((await ApprentissagesO4.charger()).nombre, 2);
    });

    test('capacité présente : partage activé par défaut ; désactivé dans les Réglages : plus rien ne part', () async {
      final srv = _FauxServeur();
      final partage = PartageO4(serveur: srv);
      expect(await partage.verifierCapacite(), isTrue);
      expect(partage.actif, isTrue);
      await partage.definirPartage(false);
      expect(partage.actif, isFalse);
      await partage.enregistrerValidation(texteLu: 'Ceuram 1g', produitId: _id('CURAM 1G CP B/16'));
      expect(partage.enAttente.value, 0);
      srv.ajouterAutre('O4-autre-1', 'xqzvt', 'BRUSTAN SUSP BUV');
      await partage.synchroniser();
      expect(srv.envois + srv.lectures, 0);
      expect((await SharedPreferences.getInstance()).getBool('ordonnance_o4_partage_v1'), isFalse);
    });

    test('capacité lue sur /mobile/capacites (404 / 401 « expire » = non ; autre = indéterminé)', () {
      expect(PartageO4.capaciteDepuisReponse(200, {'ordonnanceCorrections': true}), isTrue);
      expect(PartageO4.capaciteDepuisReponse(200, {'clientRef': true}), isFalse);
      expect(PartageO4.capaciteDepuisReponse(404, null), isFalse);
      expect(PartageO4.capaciteDepuisReponse(401, {'expire': true}), isFalse);
      expect(PartageO4.capaciteDepuisReponse(500, null), isNull);
    });

    test('ligne non apprenable (donnée personnelle) : rien d\'appris ni envoyé', () async {
      final srv = _FauxServeur();
      final partage = PartageO4(serveur: srv);
      expect(await partage.enregistrerValidation(texteLu: 'Dr Kouassi 07 08 09 10 11', produitId: _id('CURAM 1G CP B/16')), isNull);
      expect(partage.enAttente.value, 0);
      expect((await ApprentissagesO4.charger()).nombre, 0);
    });
  });

  group('Banc d\'essai : O3 + apprentissages, apprentissage simulé', () {
    test('2ᵉ passage meilleur que le 1ᵉʳ ; rien de réel enregistré', () async {
      final lectures = {
        'o (1).jpeg': ['1. Xqzvt 400 mg', '2cp x 2/j', '2. Ceuram 1g'],
        'o (2).jpeg': ['1. Dontomycine 3m', '2. Zrrkp 500'],
      };
      final vt = VeriteTerrain.fromJsonString('{"ordonnances":{'
          '"o (1).jpeg":{"produits":[{"nom":"Brustan 400 mg"},{"nom":"Curam 1 g"}]},'
          '"o (2).jpeg":{"produits":[{"nom":"Dontomycine 3 MUI"},{"nom":"Flagyl 500 mg"}]}}}');
      final pipelines = pipelinesBanc(
        _recherche(_catalogue),
        lecteur: (c) async => lectures[c]!,
        correspondanceO3: () async => _o3(),
        apprentissages: () async => ApprentissagesO4.memoire(),
      );
      final p = pipelines.whereType<PipelineO3Appris>().single;
      expect(p.libelle, 'O3 + apprentissages');
      final s = await simulerApprentissage(p, lectures.keys.toList(), vt);
      expect(s.lignesApprises, greaterThanOrEqualTo(2));
      expect(s.passage2.rappel, greaterThan(s.passage1.rappel));
      expect(s.passage2.nbCorrectes, 2);
      expect(p.simule, isNull); // simulation terminée : apprentissages en mémoire oubliés
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => k.startsWith('ordonnance_o4')), isEmpty);
      expect(PartageO4.instance.enAttente.value, 0);
    });
  });

  group('Écran Ordonnance et Réglages', () {
    testWidgets('O3 : correction du pharmacien apprise à la validation, proposée en tête la fois suivante', (tester) async {
      SharedPreferences.setMockInitialValues({'ordonnance_lecture_mode_v1': 'o3'});
      final store = MemoryLocalStore();
      await tester.runAsync(() => store.replace(CatalogueCategorie.produits, [
            for (final n in _catalogue)
              {'lgFAMILLEID': _id(n), 'strNAME': n, 'intCIP': _p(n).intCIP, 'intPRICE': 1000, 'intNUMBERAVAILABLE': 5, 'strLIBELLEE': '', 'intPAF': 800},
          ], DateTime(2026, 10, 1)));
      final previous = HorsLigne.instance;
      HorsLigne.instance = HorsLigne(store: store);
      addTearDown(() => HorsLigne.instance = previous);
      final api = _FakeApi();
      Widget ecran() => MultiProvider(
            providers: [
              Provider<ApiService>.value(value: api),
              ChangeNotifierProvider<SaleProvider>.value(value: SaleProvider(api)),
            ],
            child: MaterialApp(
              home: PrescriptionCheckScreen(
                textReader: (_) async => const ['1. Brufen 400 mg', '2cp x 2/j'],
                presentation: ListPresentation.dashboard,
                openPrevente: (_) async {},
              ),
            ),
          );
      await tester.pumpWidget(ecran());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Photographier l\'ordonnance'));
      await tester.pumpAndSettle();
      expect(find.text('BRUFEN 400MG CP'), findsOneWidget);
      // Le pharmacien choisit BRUSTAN (« Corriger ») puis crée la pré-vente.
      await tester.tap(find.byTooltip('Corriger'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Brustan 400 mg');
      await tester.tap(find.text('Rechercher'));
      await tester.pumpAndSettle();
      expect(find.text('BRUSTAN 400MG CP B/20'), findsOneWidget);
      final cb = find.byType(Checkbox);
      if (!tester.widget<Checkbox>(cb).value!) await tester.tap(cb);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Créer la pré-vente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Créer'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      final a = await tester.runAsync(ApprentissagesO4.charger);
      expect(a!.liste.single.segment, 'brufen 400mg'); // texte LU (pas la correction tapée)
      expect(a.liste.single.produitId, _id('BRUSTAN 400MG CP B/20'));
      // Nouvelle ordonnance : la correction apprise passe en tête.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(ecran());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Photographier l\'ordonnance'));
      await tester.pumpAndSettle();
      expect(find.text('BRUSTAN 400MG CP B/20'), findsOneWidget);
      expect(find.text('Appris des validations précédentes'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Réglages : partage, écran de gestion (liste, recherche, oublier, réinitialiser)', (tester) async {
      final a = ApprentissagesO4.memoire();
      await tester.runAsync(() async {
        await a.apprendre(segment: 'ceuram 1g', produitId: _id('CURAM 1G CP B/16'), nom: 'CURAM 1G CP B/16');
        await a.apprendre(segment: 'bnstou', produitId: _id('BRUSTAN SUSP BUV'), nom: 'BRUSTAN SUSP BUV');
      });
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ApprentissagesReglages()))));
      await tester.pumpAndSettle();
      expect(find.text('Partager les apprentissages avec les autres terminaux'), findsOneWidget);
      expect(find.byKey(const Key('apprentissages_ordonnances')), findsOneWidget);
      await tester.pumpWidget(MaterialApp(home: ApprentissagesScreen(apprentissages: a)));
      await tester.pumpAndSettle();
      expect(find.text('2 association(s)'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('appr_recherche')), 'curam');
      await tester.pumpAndSettle();
      expect(find.text('1 association(s)'), findsOneWidget);
      await tester.tap(find.byTooltip('Oublier'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmer'));
      await tester.pumpAndSettle();
      expect(a.nombre, 1);
      await tester.tap(find.byKey(const Key('appr_reinitialiser')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmer'));
      await tester.pumpAndSettle();
      expect(a.nombre, 0);
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
