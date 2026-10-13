// Menu « Réserve » : modèles tolérants, règles de saisie, client des routes v1/suggestion-reserve contre un serveur
// local (refus métier, 401, 500, délai, création non idempotente), écrans (sens affichés, verrou, confirmation
// avant traitement, compte rendu, anti double appui, libération du verrou). Données fictives.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/reserve/reserve_api.dart';
import 'package:prestige_vente_app/reserve/reserve_models.dart';
import 'package:prestige_vente_app/reserve/reserve_panier_screen.dart';
import 'package:prestige_vente_app/reserve/reserve_regles.dart';
import 'package:prestige_vente_app/reserve/reserve_screen.dart';
import 'package:prestige_vente_app/reserve/reserve_traitement_screen.dart';
import 'package:prestige_vente_app/serveur/client_prestige.dart';

import 'outils/serveur_json_local.dart';

Map<String, dynamic> _entete({String id = 'S1', String cat = 'RAYON', String origine = 'AUTOMATIQUE', String statut = 'A_TRAITER'}) => {
      'lg_SUGGESTION_RESERVE_ID': id,
      'str_REF': 'SR-RAY-261013-101500',
      'str_CATEGORIE': cat,
      'str_ORIGINE': origine,
      'str_STATUT': statut,
      'motif_id': 1,
      'motif_libelle': 'Reappro rayon journalier',
      'str_USER_CREATEUR': 'Préparateur Test',
      'dt_CREATED': '13/10/2026 10:15',
      'nb_produits': 2,
    };

Map<String, dynamic> _ligne(String id, {int proposee = 5, Object? retenue, int rayon = 2, int reserve = 10, String etat = 'PROPOSEE'}) => {
      'lg_SUGGESTION_RESERVE_DETAIL_ID': id,
      'lg_FAMILLE_ID': 'F$id',
      'int_CIP': '100$id',
      'str_NAME': 'PRODUIT TEST $id',
      'int_QTE_PROPOSEE': proposee,
      'int_QTE_RETENUE': retenue,
      'int_STOCK_RAYON': rayon,
      'int_STOCK_RESERVE': reserve,
      'int_STOCK_RAYON_ACTUEL': rayon,
      'int_STOCK_RESERVE_ACTUEL': reserve,
      'str_FORMULE': 'A la creation : rayon $rayon',
      'str_ETAT': etat,
    };

class _FakeApi extends ReserveApi {
  _FakeApi() : super(ClientPrestige(() => 'http://127.0.0.1:1/prestige/api/v1'));

  List<EnteteSuggestion> attente = const [];
  List<MotifReserve> listeMotifs = const [MotifReserve(id: 1, libelle: 'Reappro rayon journalier', categorie: 'RAYON')];
  SuggestionOuverte Function() ouverture = () => SuggestionOuverte.fromJson({
        'entete': _entete(),
        'lignes': [_ligne('1'), _ligne('2', proposee: 4, reserve: 3)],
        'modifiable': true,
      });
  int ouvertures = 0, liberations = 0, traitements = 0, creations = 0;
  final quantites = <String, int>{};
  Completer<ResultatCreation>? creation;
  ArticleReserve? article = const ArticleReserve(familleId: 'FA', cip: '3400000000001', nom: 'PRODUIT A', stockRayon: 2, stockReserve: 6, qteSuggeree: 4);

  @override
  Future<List<EnteteSuggestion>> enAttente({int limit = 200}) async => attente;
  @override
  Future<List<MotifReserve>> motifs(SensReserve sens) async => listeMotifs;
  @override
  Future<SuggestionOuverte> ouvrir(String id) async {
    ouvertures++;
    return ouverture();
  }

  @override
  Future<void> liberer(String id) async => liberations++;
  @override
  Future<int> majQuantite(String detailId, int quantite) async => quantites[detailId] = quantite;
  @override
  Future<CompteRendu> traiter(String id) async {
    traitements++;
    return CompteRendu.fromJson({
      'success': true,
      'entete': _entete(statut: 'EN_COURS'),
      'total_demande': 2,
      'total_reussi': 1,
      'total_echoue': 1,
      'articles_traites': [_ligne('1', etat: 'TRAITEE')..['int_QTE_DEPLACEE'] = 5],
      'articles_non_traites': [
        _ligne('2', etat: 'ECHEC')
          ..['str_CODE_ECHEC'] = 'STOCK_RESERVE_INSUFFISANT'
          ..['str_MOTIF_LIGNE'] = 'Stock reserve insuffisant (3 disponibles)'
      ],
      'relancable': true,
    });
  }

  @override
  Future<ArticleReserve?> articleDuProduit({required String familleId, required String cip}) async => article;
  @override
  Future<ResultatCreation> creer(SensReserve sens, int motifId, String commentaire, List<LignePanier> panier) {
    creations++;
    return (creation ??= Completer<ResultatCreation>()).future;
  }
}

Future<void> _taille(WidgetTester t, Size s) async {
  t.view.physicalSize = s;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
}

Widget _app(Widget w) => MaterialApp(home: w);

void main() {
  group('vocabulaire et modèles', () {
    test('catégorie RESERVE = Rayon → Réserve ; RAYON (ou autre) = Réserve → Rayon', () {
      expect(SensReserve.depuisCategorie('RESERVE'), SensReserve.versReserve);
      expect(SensReserve.depuisCategorie('reserve'), SensReserve.versReserve);
      expect(SensReserve.depuisCategorie('RAYON'), SensReserve.versRayon);
      expect(SensReserve.depuisCategorie(null), SensReserve.versRayon);
      expect(SensReserve.versReserve.categorieApi, 'RESERVE');
      expect(SensReserve.versReserve.fleche, 'Rayon → Réserve');
      expect(SensReserve.versRayon.fleche, 'Réserve → Rayon');
      expect(SensReserve.versRayon.source, 'réserve');
    });

    test('ligne : champs manquants, nuls ou de type inattendu', () {
      final l = LigneSuggestion.fromJson({'lg_SUGGESTION_RESERVE_DETAIL_ID': 'D', 'int_QTE_PROPOSEE': '7', 'int_QTE_RETENUE': null, 'int_STOCK_RESERVE': 'x'});
      expect(l.qteProposee, 7);
      expect(l.qteRetenue, isNull);
      expect(l.qteATraiter, 7);
      expect(l.stockReserve, 0);
      expect(l.nom, '');
      expect(l.traitable, isTrue);
      expect(LigneSuggestion.fromJson({'str_ETAT': 'traitee', 'int_QTE_PROPOSEE': 3}).modifiable, isFalse);
      expect(LigneSuggestion.fromJson({}).traitable, isFalse);
    });

    test('suggestion ouverte : verrou d\'un autre, modifiable absent = lecture seule', () {
      final s = SuggestionOuverte.fromJson({
        'entete': _entete(),
        'lignes': 'pas une liste',
        'modifiable': false,
        'verrou_par': 'Autre Utilisateur',
        'verrou_depuis': '13/10/2026 09:00',
      });
      expect(s.occupeeParAutre, isTrue);
      expect(s.lignes, isEmpty);
      expect(SuggestionOuverte.fromJson({'entete': _entete()}).modifiable, isFalse);
      expect(SuggestionOuverte.fromJson({}).entete.id, '');
    });

    test('compte rendu et articles', () {
      final c = CompteRendu.fromJson({'entete': _entete(), 'total_reussi': '2', 'articles_traites': [_ligne('1')..['int_QTE_DEPLACEE'] = 3], 'relancable': 'false'});
      expect(c.totalReussi, 2);
      expect(c.boitesDeplacees, 3);
      expect(c.relancable, isFalse);
      final p = PageArticles.fromJson({
        'total': '12',
        'results': [
          {'lg_FAMILLE_ID': 'F1', 'str_NAME': null, 'str_DESCRIPTION': 'Désignation', 'int_STOCK_RAYON': 4, 'int_SEUIL_MINI_RAYON': null},
          {'lg_FAMILLE_ID': ''},
          'x',
        ]
      });
      expect(p.total, 12);
      expect(p.articles.single.nom, 'Désignation');
      expect(p.articles.single.seuilMiniRayon, isNull);
      expect(p.articles.single.disponible(SensReserve.versReserve), 4);
      expect(MotifReserve.fromJson({'libelle': 'sans id'}), isNull);
    });
  });

  group('règles de saisie', () {
    test('quantité : entier > 0, bornée par le stock source', () {
      const s = SensReserve.versRayon;
      expect(validerQuantite('', disponible: 10, sens: s), isNotNull);
      expect(validerQuantite('0', disponible: 10, sens: s), contains('supérieure à 0'));
      expect(validerQuantite('-2', disponible: 10, sens: s), isNotNull);
      expect(validerQuantite('2,5', disponible: 10, sens: s), contains('entier'));
      expect(validerQuantite('11', disponible: 10, sens: s), contains('réserve n\'en contient que 10'));
      expect(validerQuantite('3', disponible: 0, sens: s), contains('vide'));
      expect(validerQuantite('10', disponible: 10, sens: s), isNull);
      expect(validerQuantite('100000', disponible: 200000, sens: s), contains('trop grande'));
      expect(validerQuantite('5', disponible: 2, sens: SensReserve.versReserve), contains('rayon n\'en contient que 2'));
      expect(lireQuantite(' 7 '), 7);
      expect(lireQuantite('7a'), isNull);
    });

    test('quantité par défaut bornée au stock source ; panier sans doublon', () {
      const a = ArticleReserve(familleId: 'F', cip: '1', nom: 'A', stockRayon: 3, stockReserve: 8, qteSuggeree: 6);
      expect(quantiteParDefaut(a, SensReserve.versRayon), 6);
      expect(quantiteParDefaut(a, SensReserve.versReserve), 3);
      expect(quantiteParDefaut(const ArticleReserve(familleId: 'G', cip: '', nom: '', stockRayon: 0, stockReserve: 0, qteSuggeree: 2), SensReserve.versRayon), isNull);
      var p = ajouterAuPanier(const [], a, 2);
      p = ajouterAuPanier(p, a, 5);
      expect(p, hasLength(1));
      expect(p.single.quantite, 5);
      final corps = corpsCreation(SensReserve.versReserve, 4, '  ', p);
      expect(corps['categorie'], 'RESERVE');
      expect(corps['motifId'], 4);
      expect(corps['commentaire'], isNull);
      expect(corps['items'], [
        {'lg_FAMILLE_ID': 'F', 'int_QTE': 5}
      ]);
    });

    test('reprise : seulement les suggestions ouvertes du même sens et de la même origine', () {
      final l = [
        EnteteSuggestion.fromJson(_entete(id: 'a', cat: 'RAYON', origine: 'MANUELLE')),
        EnteteSuggestion.fromJson(_entete(id: 'b', cat: 'RESERVE', origine: 'MANUELLE')),
        EnteteSuggestion.fromJson(_entete(id: 'c', cat: 'RAYON', origine: 'AUTOMATIQUE')),
        EnteteSuggestion.fromJson(_entete(id: 'd', cat: 'RAYON', origine: 'MANUELLE', statut: 'TRAITEE')),
        EnteteSuggestion.fromJson(_entete(id: 'e', cat: 'RAYON', origine: 'MANUELLE', statut: 'EN_COURS')),
      ];
      expect(suggestionsAReprendre(l, SensReserve.versRayon, OrigineSuggestion.manuelle).map((s) => s.id), ['a', 'e']);
    });

    test('résumé avant traitement et lignes au-delà du stock', () {
      final lignes = [
        LigneSuggestion.fromJson(_ligne('1', proposee: 5, reserve: 10)),
        LigneSuggestion.fromJson(_ligne('2', proposee: 4, retenue: 6, reserve: 3)),
        LigneSuggestion.fromJson(_ligne('3', proposee: 4, etat: 'SUPPRIMEE')),
        LigneSuggestion.fromJson(_ligne('4', proposee: 2, etat: 'TRAITEE')),
      ];
      final r = resumeTraitement(lignes);
      expect(r.lignes, 2);
      expect(r.boites, 11);
      expect(lignesAuDelaDuStock(lignes, SensReserve.versRayon).map((l) => l.detailId), ['2']);
      expect(libelleCodeEchec('STOCK_RESERVE_INSUFFISANT', SensReserve.versRayon), 'Stock réserve insuffisant');
    });
  });

  group('client des routes contre un serveur local', () {
    late ServeurJsonLocal srv;
    late ReserveApi api;
    setUp(() => avecVraiHttp(() async {
          srv = ServeurJsonLocal();
          await srv.demarrer();
          api = ReserveApi(ClientPrestige(() => srv.base, delaiConnexion: const Duration(seconds: 2), delaiReponse: const Duration(milliseconds: 500)));
        }));
    tearDown(() => avecVraiHttp(() => srv.arreter()));

    test('en-attente, motifs (tableau nu), ouvrir, quantité, traiter, libérer', () => avecVraiHttp(() async {
          srv.routes['GET /suggestion-reserve/en-attente'] = (_) => ReponseLocale({'results': [_entete(), {'str_REF': 'sans id'}], 'total': 2});
          srv.routes['GET /suggestion-reserve/motifs'] = (_) => const ReponseLocale([
                {'id': 1, 'libelle': 'Reappro rayon journalier', 'categorie': 'RAYON'},
                {'id': 'x'}
              ]);
          srv.routes['PUT /S1/ouvrir'] = (_) => ReponseLocale({'success': true, 'entete': _entete(), 'lignes': [_ligne('1')], 'modifiable': true});
          srv.routes['PUT /ligne/1/quantite'] = (r) => ReponseLocale({'success': true, 'int_QTE_RETENUE': r.json['int_QTE'], 'str_ETAT': 'MODIFIEE'});
          srv.routes['PUT /S1/traiter'] = (_) => ReponseLocale({'success': true, 'entete': _entete(statut: 'TRAITEE'), 'total_reussi': 1, 'articles_traites': [_ligne('1')]});
          srv.routes['PUT /S1/liberer'] = (_) => const ReponseLocale({'success': true});
          expect((await api.enAttente()).single.id, 'S1');
          expect(srv.recuesSur('/en-attente').single.query['limit'], '200');
          final m = await api.motifs(SensReserve.versRayon);
          expect(m.single.id, 1);
          expect(srv.recuesSur('/motifs').single.query['categorie'], 'RAYON');
          final s = await api.ouvrir('S1');
          expect(s.modifiable, isTrue);
          expect(await api.majQuantite('1', 3), 3);
          expect(srv.recuesSur('/quantite').single.json, {'int_QTE': 3});
          expect((await api.traiter('S1')).totalReussi, 1);
          await api.liberer('S1');
          expect(srv.recuesSur('/liberer'), hasLength(1));
        }));

    test('quantité 0 ou négative refusée avant envoi', () => avecVraiHttp(() async {
          await expectLater(api.majQuantite('1', 0), throwsA(isA<RefusMetier>()));
          expect(srv.recues, isEmpty);
        }));

    test('créer : corps envoyé ; refus métier (motif obligatoire) ; suggestion occupée', () => avecVraiHttp(() async {
          srv.routes['POST /suggestion-reserve/creer'] = (r) => r.json['motifId'] == null
              ? const ReponseLocale({'success': false, 'code': 'MOTIF_OBLIGATOIRE', 'message': 'Le motif est obligatoire'})
              : const ReponseLocale({'success': true, 'lg_SUGGESTION_RESERVE_ID': 'N1', 'str_REF': 'SR-RES-1', 'lignes': 1, 'ignorees': 0});
          const a = ArticleReserve(familleId: 'F1', cip: '1', nom: 'A', stockRayon: 9, stockReserve: 0);
          final r = await api.creer(SensReserve.versReserve, 2, 'test', const [LignePanier(a, 4)]);
          expect(r.id, 'N1');
          expect(srv.recuesSur('/creer').single.json, {
            'categorie': 'RESERVE',
            'motifId': 2,
            'commentaire': 'test',
            'items': [
              {'lg_FAMILLE_ID': 'F1', 'int_QTE': 4}
            ]
          });
          srv.routes['PUT /S1/traiter'] = (_) => const ReponseLocale({'success': false, 'code': 'SUGGESTION_OCCUPEE', 'message': 'X a ouvert cette suggestion'});
          await expectLater(api.traiter('S1'), throwsA(isA<RefusMetier>().having((e) => e.code, 'code', 'SUGGESTION_OCCUPEE')));
        }));

    test('créer : délai dépassé après envoi → résultat incertain, jamais renvoyé automatiquement', () => avecVraiHttp(() async {
          srv.routes['POST /suggestion-reserve/creer'] =
              (_) => const ReponseLocale({'success': true, 'lg_SUGGESTION_RESERVE_ID': 'N1'}, delai: Duration(seconds: 2));
          const a = ArticleReserve(familleId: 'F1', cip: '1', nom: 'A', stockRayon: 9, stockReserve: 0);
          await expectLater(api.creer(SensReserve.versReserve, 2, '', const [LignePanier(a, 1)]),
              throwsA(isA<ServeurInjoignable>().having((e) => e.resultatIncertain, 'incertain', isTrue)));
          expect(srv.recuesSur('/creer'), hasLength(1));
        }));

    test('401, 500 ; libérer ne lève jamais d\'erreur', () => avecVraiHttp(() async {
          srv.routes['GET /suggestion-reserve/en-attente'] = (_) => const ReponseLocale('Veuillez vous connecter', statut: 401);
          srv.routes['PUT /S1/ouvrir'] = (_) => const ReponseLocale('erreur', statut: 500);
          srv.routes['PUT /S1/liberer'] = (_) => const ReponseLocale('erreur', statut: 500);
          await expectLater(api.enAttente(), throwsA(isA<SessionExpiree>()));
          await expectLater(api.ouvrir('S1'), throwsA(isA<ErreurHttp>()));
          await api.liberer('S1');
        }));

    test('article du produit : correspondance exacte par identifiant ; produit non suivi → null', () => avecVraiHttp(() async {
          srv.routes['GET /reserve/articles'] = (_) => const ReponseLocale({
                'total': 2,
                'results': [
                  {'lg_FAMILLE_ID': 'AUTRE', 'int_CIP': '12345'},
                  {'lg_FAMILLE_ID': 'F9', 'int_CIP': '123', 'str_NAME': 'B', 'int_STOCK_RESERVE': 7},
                ]
              });
          expect((await api.articleDuProduit(familleId: 'F9', cip: '123'))!.stockReserve, 7);
          expect(await api.articleDuProduit(familleId: 'F0', cip: '123'), isNull);
          expect(srv.recuesSur('/reserve/articles').first.query['search_value'], '123');
        }));
  });

  group('écrans', () {
    for (final taille in const [Size(720, 1440), Size(1080, 1920), Size(2048, 1536)]) {
      testWidgets('menu Réserve : 4 entrées avec les sens en clair, compteurs ($taille)', (t) async {
        await _taille(t, taille);
        final api = _FakeApi()
          ..attente = [
            EnteteSuggestion.fromJson(_entete(id: 'a', cat: 'RAYON', origine: 'AUTOMATIQUE')),
            EnteteSuggestion.fromJson(_entete(id: 'b', cat: 'RAYON', origine: 'AUTOMATIQUE')),
          ];
        await t.pumpWidget(_app(ReserveScreen(api: api)));
        await t.pumpAndSettle();
        expect(find.text('Ranger en réserve'), findsOneWidget);
        expect(find.text('Regarnir le rayon'), findsOneWidget);
        expect(find.text('Rayon à regarnir'), findsOneWidget);
        expect(find.text('Rayon → Réserve'), findsNWidgets(2));
        expect(find.text('Réserve → Rayon'), findsNWidgets(2));
        expect(find.text('2 à traiter'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('traitement : confirmation explicite, un seul traitement, compte rendu, verrou libéré en quittant', (t) async {
      await _taille(t, const Size(720, 1440));
      final api = _FakeApi();
      await t.pumpWidget(_app(Builder(
          builder: (ctx) => Scaffold(
              body: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => ReserveTraitementScreen(suggestionId: 'S1', api: api))),
                  child: const Text('ouvrir'))))));
      await t.tap(find.text('ouvrir'));
      await t.pumpAndSettle();
      expect(find.text('PRODUIT TEST 1'), findsOneWidget);
      expect(find.text('Rayon 2'), findsWidgets);
      expect(find.text('Réserve 10'), findsOneWidget);
      expect(find.textContaining('Dépasse le stock réserve actuel (3)'), findsOneWidget);
      expect(find.text('Traiter : 2 ligne(s), 9 boîte(s)'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('reserve-traiter')));
      await t.pumpAndSettle();
      expect(find.text('Déplacer le stock ?'), findsOneWidget);
      expect(find.textContaining('9 boîte(s) de 2 produit(s) vont passer du stock réserve au stock rayon'), findsOneWidget);
      expect(find.textContaining('Prestige les refusera'), findsOneWidget);
      expect(api.traitements, 0, reason: 'rien ne bouge avant la confirmation');
      await t.tap(find.byKey(const ValueKey('reserve-confirmer-traiter')));
      await t.pumpAndSettle();
      expect(api.traitements, 1);
      expect(find.text('Traitement partiel'), findsOneWidget);
      expect(find.text('Stock reserve insuffisant (3 disponibles)'), findsOneWidget);
      expect(find.text('Réessayer les échecs'), findsOneWidget);
      await t.tap(find.text('Terminer'));
      await t.pumpAndSettle();
      expect(api.liberations, 1);
      expect(t.takeException(), isNull);
    });

    testWidgets('traitement : annuler la confirmation ne déplace rien', (t) async {
      await _taille(t, const Size(720, 1440));
      final api = _FakeApi();
      await t.pumpWidget(_app(ReserveTraitementScreen(suggestionId: 'S1', api: api)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('reserve-traiter')));
      await t.pumpAndSettle();
      await t.tap(find.text('Annuler'));
      await t.pumpAndSettle();
      expect(api.traitements, 0);
    });

    testWidgets('suggestion ouverte par un autre : consultation seule, pas de bouton Traiter', (t) async {
      await _taille(t, const Size(720, 1440));
      final api = _FakeApi()
        ..ouverture = () => SuggestionOuverte.fromJson({
              'entete': _entete(),
              'lignes': [_ligne('1')],
              'modifiable': false,
              'verrou_par': 'Autre Préparateur',
              'verrou_depuis': '13/10/2026 09:00',
              'motif_lecture_seule': 'Autre Préparateur a ouvert cette suggestion depuis 13/10/2026 09:00.',
            });
      await t.pumpWidget(_app(ReserveTraitementScreen(suggestionId: 'S1', api: api)));
      await t.pumpAndSettle();
      expect(find.textContaining('Autre Préparateur a ouvert'), findsOneWidget);
      expect(find.byKey(const ValueKey('reserve-traiter')), findsNothing);
      await t.tap(find.byKey(const ValueKey('reserve-qte-1')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('reserve-quantite')), findsNothing, reason: 'aucune saisie sans le verrou');
      await t.pumpWidget(const SizedBox());
      expect(api.liberations, 0, reason: 'verrou jamais pris : rien à libérer');
    });

    testWidgets('saisie de quantité : 0 et dépassement du stock refusés, valeur valable enregistrée', (t) async {
      await _taille(t, const Size(720, 1440));
      final api = _FakeApi();
      await t.pumpWidget(_app(ReserveTraitementScreen(suggestionId: 'S1', api: api)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('reserve-qte-1')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('reserve-quantite')), '0');
      await t.tap(find.text('Valider'));
      await t.pump();
      expect(find.textContaining('supérieure à 0'), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('reserve-quantite')), '11');
      await t.tap(find.text('Valider'));
      await t.pump();
      expect(find.textContaining('n\'en contient que 10'), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('reserve-quantite')), '8');
      await t.tap(find.text('Valider'));
      await t.pumpAndSettle();
      expect(api.quantites, {'1': 8});
      expect(find.text('Traiter : 2 ligne(s), 12 boîte(s)'), findsOneWidget);
    });

    testWidgets('panier manuel : suggestion déjà en attente proposée, anti double appui sur Créer, puis traitement', (t) async {
      await _taille(t, const Size(720, 1440));
      final api = _FakeApi()..attente = [EnteteSuggestion.fromJson(_entete(id: 'M0', origine: 'MANUELLE'))];
      Future<ProductSearchResult?> choix(BuildContext c, {String? code}) async => ProductSearchResult(
          lgFAMILLEID: 'FA', strNAME: 'PRODUIT A', intCIP: '3400000000001', intPRICE: 0, intNUMBERAVAILABLE: 0, strLIBELLEE: 'PRODUIT A', intPAF: 0);
      await t.pumpWidget(_app(ReservePanierScreen(sens: SensReserve.versRayon, api: api, choixProduit: choix)));
      await t.pumpAndSettle();
      expect(find.text('Déjà en attente (1)'), findsOneWidget);
      await t.scrollUntilVisible(find.byKey(const ValueKey('reserve-rechercher')), 120);
      await t.tap(find.byKey(const ValueKey('reserve-rechercher')));
      await t.pumpAndSettle();
      // quantité proposée 4 (≤ réserve 6)
      expect(find.text('4'), findsWidgets);
      await t.enterText(find.byKey(const ValueKey('reserve-quantite')), '7');
      await t.tap(find.text('Valider'));
      await t.pump();
      expect(find.textContaining('n\'en contient que 6'), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('reserve-quantite')), '5');
      await t.tap(find.text('Valider'));
      await t.pumpAndSettle();
      expect(find.text('PRODUIT A'), findsOneWidget);
      final creer = find.byKey(const ValueKey('reserve-creer'));
      await t.ensureVisible(creer);
      await t.tap(creer);
      await t.pumpAndSettle();
      // une suggestion manuelle attend déjà : confirmation
      expect(find.text('Créer une nouvelle suggestion ?'), findsOneWidget);
      await t.tap(find.text('Créer quand même'));
      await t.pump();
      await t.tap(creer, warnIfMissed: false);
      await t.pump();
      expect(api.creations, 1, reason: 'un seul envoi même en cas de double appui');
      api.creation!.complete(const ResultatCreation(id: 'N1', ref: 'SR-RAY-1', lignes: 1));
      await t.pumpAndSettle();
      expect(find.byType(ReserveTraitementScreen), findsOneWidget);
      expect(api.ouvertures, 1);
    });

    testWidgets('panier : produit non suivi en réserve refusé avec un message', (t) async {
      await _taille(t, const Size(720, 1440));
      final api = _FakeApi()..article = null;
      Future<ProductSearchResult?> choix(BuildContext c, {String? code}) async =>
          ProductSearchResult(lgFAMILLEID: 'FZ', strNAME: 'PRODUIT Z', intCIP: '9', intPRICE: 0, intNUMBERAVAILABLE: 0, strLIBELLEE: '', intPAF: 0);
      await t.pumpWidget(_app(ReservePanierScreen(sens: SensReserve.versReserve, api: api, choixProduit: choix)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('reserve-rechercher')));
      await t.pumpAndSettle();
      expect(find.textContaining('n\'est pas suivi en réserve'), findsOneWidget);
      expect(find.byKey(const ValueKey('reserve-quantite')), findsNothing);
    });
  });
}
