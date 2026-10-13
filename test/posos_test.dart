// Analyse posologie : gravités classées (jamais minimisées), lecture tolérante, mode démonstration toujours
// signalé, contrôles du contexte patient, client v1/posos contre un serveur local, écran. Données fictives.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/posos/posos_api.dart';
import 'package:prestige_vente_app/posos/posos_models.dart';
import 'package:prestige_vente_app/posos/posos_screen.dart';
import 'package:prestige_vente_app/serveur/client_prestige.dart';

import 'outils/serveur_json_local.dart';

Map<String, dynamic> _resultat({bool demo = false}) => {
      'success': true,
      'disponible': true,
      'message': '',
      'nombreMajeures': 1,
      'total': 3,
      'alertes': [
        {'type': 'Interaction', 'gravite': 'Précaution d\'emploi', 'libelle': 'Alerte précaution', 'majeure': false, 'produits': ['B']},
        {
          'type': 'Contre-indication',
          'gravite': 'Contre-indication',
          'libelle': 'Alerte grave',
          'recommandation': 'Ne pas associer',
          'majeure': true,
          'produits': ['A', 'B'],
          'proposer': ['paracetamol'],
          'equivalents': [
            {'nom': 'PARACETAMOL TEST 500', 'cip': '1', 'prix': 800, 'stock': 12},
            {'nom': ''}
          ]
        },
        {'gravite': 'inconnue du serveur', 'libelle': 'Alerte inconnue'},
      ],
      'produitsNonReconnus': ['PRODUIT X'],
      'demonstration': demo,
      'avertissement': demo ? 'DÉMONSTRATION — ce n\'est pas Posos.' : '',
    };

class _FakePosos extends PososApi {
  _FakePosos({this.demo = false}) : super(ClientPrestige(() => 'http://127.0.0.1:1/prestige/api/v1'));
  final bool demo;
  int analyses = 0;
  String? venteAnalysee;
  List<ProduitAnalyse>? produitsAnalyses;
  ContextePatient? contexte;

  @override
  Future<PososStatut> statut() async => PososStatut(configuree: !demo, mode: demo ? 'demonstration' : 'posos');
  @override
  Future<ResultatPosos> analyserProduits(List<ProduitAnalyse> produits, ContextePatient contexte) async {
    analyses++;
    produitsAnalyses = produits;
    this.contexte = contexte;
    return ResultatPosos.fromJson(_resultat(demo: demo));
  }

  @override
  Future<ResultatPosos> analyserVente(String venteId, ContextePatient contexte) async {
    analyses++;
    venteAnalysee = venteId;
    return ResultatPosos.fromJson(_resultat(demo: demo)..['venteProduits'] = [
          {'nom': 'PRODUIT A', 'quantite': 2, 'posologie': '1 matin'}
        ]);
  }
}

Future<void> _taille(WidgetTester t, Size s) async {
  t.view.physicalSize = s;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
}

void main() {
  group('gravités et modèles', () {
    test('classement : contre-indication > majeure > à vérifier > précaution > à prendre en compte > information', () {
      expect(NiveauGravite.classer('Contre-indication'), NiveauGravite.contreIndication);
      expect(NiveauGravite.classer('Association déconseillée'), NiveauGravite.majeure);
      expect(NiveauGravite.classer('Majeure'), NiveauGravite.majeure);
      expect(NiveauGravite.classer('Précaution d\'emploi'), NiveauGravite.precaution);
      expect(NiveauGravite.classer('À prendre en compte'), NiveauGravite.aPrendreEnCompte);
      expect(NiveauGravite.classer('Information'), NiveauGravite.information);
      // inconnue : jamais minimisée
      expect(NiveauGravite.classer(''), NiveauGravite.aVerifier);
      expect(NiveauGravite.classer('xyz', estMajeure: true), NiveauGravite.majeure);
      expect(NiveauGravite.contreIndication.index, lessThan(NiveauGravite.information.index));
    });

    test('résultat : alertes triées de la plus grave à la moins grave, champs manquants tolérés', () {
      final r = ResultatPosos.fromJson(_resultat());
      expect(r.alertes.map((a) => a.libelle), ['Alerte grave', 'Alerte inconnue', 'Alerte précaution']);
      expect(r.alertes.first.equivalents.single.stock, 12);
      expect(r.alertes[1].majeure, isTrue, reason: '« majeure » absent : considérée majeure');
      expect(r.parNiveau[NiveauGravite.contreIndication], 1);
      final vide = ResultatPosos.fromJson({'alertes': 'x', 'nombreMajeures': null});
      expect(vide.disponible, isTrue);
      expect(vide.alertes, isEmpty);
      expect(vide.nombreMajeures, 0);
      expect(ResultatPosos.fromJson({'disponible': false, 'message': 'Posos n\'est pas configuré'}).disponible, isFalse);
    });

    test('statut : démonstration si déclarée OU si Posos n\'est pas configuré', () {
      expect(PososStatut.fromJson({'configuree': true, 'mode': 'posos'}).demonstration, isFalse);
      expect(PososStatut.fromJson({'configuree': true, 'mode': 'demonstration'}).demonstration, isTrue);
      expect(PososStatut.fromJson({'configuree': false, 'mode': 'posos'}).demonstration, isTrue);
      expect(PososStatut.fromJson({}).demonstration, isTrue);
    });

    test('contexte patient : vide → absent ; âge et poids bornés', () {
      expect(const ContextePatient().toJson(), isNull);
      expect(const ContextePatient(age: 40, sexe: 'F', grossesse: true).toJson(), containsPair('grossesse', true));
      expect(validerAge(''), isNull);
      expect(validerAge('35'), isNull);
      expect(validerAge('130'), isNotNull);
      expect(validerAge('3a'), isNotNull);
      expect(validerPoids('0'), isNotNull);
      expect(validerPoids('301'), isNotNull);
      expect(validerPoids('72'), isNull);
      expect(const ProduitAnalyse(nom: 'A', quantite: 0, posologie: ' ').toJson(), {'nom': 'A'});
    });
  });

  group('client v1/posos', () {
    late ServeurJsonLocal srv;
    late PososApi api;
    setUp(() => avecVraiHttp(() async {
          srv = ServeurJsonLocal();
          await srv.demarrer();
          api = PososApi(ClientPrestige(() => srv.base, delaiReponse: const Duration(seconds: 2)));
        }));
    tearDown(() => avecVraiHttp(() => srv.arreter()));

    test('forme A (produits + contexte) et forme B (venteId)', () => avecVraiHttp(() async {
          srv.routes['POST /posos/analyse'] = (_) => ReponseLocale(_resultat(demo: true));
          srv.routes['GET /posos/status'] = (_) => const ReponseLocale({'success': true, 'configuree': false, 'mode': 'demonstration'});
          expect((await api.statut()).demonstration, isTrue);
          final r = await api.analyserProduits(const [ProduitAnalyse(nom: 'A', cip: '1', quantite: 2, posologie: '1 matin')], const ContextePatient(age: 70));
          expect(r.demonstration, isTrue);
          expect(srv.recuesSur('/analyse').last.json, {
            'produits': [
              {'nom': 'A', 'cip': '1', 'quantite': 2, 'posologie': '1 matin'}
            ],
            'contexte': {'age': 70, 'grossesse': false, 'allaitement': false, 'insuffisanceRenale': false, 'insuffisanceHepatique': false},
          });
          await api.analyserVente(' V123 ', const ContextePatient());
          expect(srv.recuesSur('/analyse').last.json, {'venteId': 'V123'});
        }));

    test('aucun produit : refusé sans appel ; refus serveur, 401, 500', () => avecVraiHttp(() async {
          await expectLater(api.analyserProduits(const [], const ContextePatient()), throwsA(isA<RefusMetier>()));
          expect(srv.recues, isEmpty);
          srv.routes['POST /posos/analyse'] = (_) => const ReponseLocale({'success': false, 'message': 'Demande illisible.'});
          await expectLater(api.analyserVente('V', const ContextePatient()), throwsA(isA<RefusMetier>()));
          srv.routes['POST /posos/analyse'] = (_) => const ReponseLocale('Veuillez vous connecter', statut: 401);
          await expectLater(api.analyserVente('V', const ContextePatient()), throwsA(isA<SessionExpiree>()));
          srv.routes['GET /posos/status'] = (_) => const ReponseLocale('x', statut: 500);
          await expectLater(api.statut(), throwsA(isA<ErreurHttp>()));
        }));
  });

  group('écran', () {
    testWidgets('mode démonstration : bandeau visible ; alertes classées ; avertissement non médical (Sunmi 720×1440)', (t) async {
      await _taille(t, const Size(720, 1440));
      final api = _FakePosos(demo: true);
      Future<ProductSearchResult?> choix(BuildContext c, {String? code}) async =>
          ProductSearchResult(lgFAMILLEID: 'F1', strNAME: 'PRODUIT A', intCIP: '111', intPRICE: 0, intNUMBERAVAILABLE: 0, strLIBELLEE: '', intPAF: 0);
      await t.pumpWidget(MaterialApp(home: PososScreen(api: api, choixProduit: choix)));
      await t.pumpAndSettle();
      expect(find.text('Mode démonstration — résultats non réels'), findsOneWidget);
      expect(find.textContaining('ne remplacent ni l\'avis du pharmacien'), findsOneWidget);
      final analyser = t.widget<ElevatedButton>(find.byKey(const ValueKey('posos-analyser')));
      expect(analyser.onPressed, isNull, reason: 'aucun produit : analyse impossible');
      await t.tap(find.byKey(const ValueKey('posos-rechercher')));
      await t.pumpAndSettle();
      expect(find.text('PRODUIT A'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('posos-analyser')));
      await t.pumpAndSettle();
      expect(api.analyses, 1);
      expect(api.produitsAnalyses!.single.cip, '111');
      expect(find.text('3 alerte(s), dont 1 majeure(s)'), findsOneWidget);
      expect(find.textContaining('DÉMONSTRATION'), findsOneWidget);
      await t.scrollUntilVisible(find.text('Alerte grave'), 200);
      expect(find.text('Conduite à tenir : Ne pas associer'), findsOneWidget);
      expect(find.textContaining('PARACETAMOL TEST 500 — stock 12'), findsOneWidget);
      // plus grave en premier
      expect(t.getTopLeft(find.text('Alerte grave')).dy, lessThan(t.getTopLeft(find.text('Alerte précaution')).dy));
      expect(t.takeException(), isNull);
    });

    testWidgets('depuis la vente : analyse par venteId, contexte invalide refusé avant envoi (tablette)', (t) async {
      await _taille(t, const Size(2048, 1536));
      final api = _FakePosos();
      await t.pumpWidget(MaterialApp(
          home: PososScreen(api: api, venteId: 'V42', referenceVente: 'REF-42', produitsInitiaux: const [ProduitAnalyse(nom: 'PRODUIT A', quantite: 2)])));
      await t.pumpAndSettle();
      expect(find.text('Mode démonstration — résultats non réels'), findsNothing);
      expect(find.text('Vente REF-42'), findsOneWidget);
      await t.tap(find.text('Contexte du patient (facultatif)'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('posos-age')), '150');
      await t.tap(find.byKey(const ValueKey('posos-analyser')));
      await t.pumpAndSettle();
      expect(find.text('Âge : 120 ans au plus.'), findsOneWidget);
      expect(api.analyses, 0);
      await t.enterText(find.byKey(const ValueKey('posos-age')), '67');
      await t.tap(find.byKey(const ValueKey('posos-analyser')));
      await t.pumpAndSettle();
      expect(api.venteAnalysee, 'V42');
      expect(find.text('Produits analysés'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}

