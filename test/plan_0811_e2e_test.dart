// E2E — Prestige Mobile 4.11.0, plan du pharmacien du 08/11 : application ENTIÈRE contre le faux serveur Prestige en
// mémoire, Sunmi V2s, données FICTIVES.
//  1. Réception BL :
//     - commandes à réceptionner : nombre de LIGNES (int_LINE), plus la quantité affichée comme des « produits » ;
//     - saisie au clavier / douchette : lot → Entrée → péremption sans barres (« 0128 » = 01/01/2028) → Entrée →
//       quantité attendue pré-sélectionnée → Entrée enregistre (POST commande/add-lot) ;
//     - BL incomplet : écarts au bilan ; serveur avec la clôture « au reçu » (demande 59) → PUT validerbl?mode=RECU ;
//       serveur actuel → jamais d'entrée en stock d'un BL incomplet par ce chemin ;
//  2. Réserve : saisie manuelle (CIP, quantité, produit suivant), confirmation du sens, création
//     (POST suggestion-reserve/creer, catégorie du sens) ; droit « Voir les suggestions » (demande 60) faux :
//     onglet Automatique masqué, aucune lecture des suggestions, demande créée mais jamais ouverte.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/reserve/reserve_traitement_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import 'outils/app_e2e.dart';

Map<String, dynamic> _ligneBl(String id, String nom, String cip, int cmde, {int saisie = 0, String lots = ''}) => {
      'lg_BON_LIVRAISON_DETAIL': id,
      'lg_FAMILLE_ID': 'F$id',
      'lg_FAMILLE_NAME': nom,
      'lg_FAMILLE_CIP': cip,
      'int_QTE_CMDE': cmde,
      'quantiteSaisie': saisie,
      'freeQty': 0,
      'lots': lots,
      'datePeremption': '',
      'str_REF_LIVRAISON': 'BL-E2E-1',
      'int_QTE_RECUE_BIS': -1,
    };

/// Faux serveur : une commande (3 lignes, 48 boîtes), un BL de 2 lignes, lots enregistrés en mémoire.
AppE2E _appReception({required bool clotureRecu}) {
  final app = AppE2E(serveur: FauxServeurPrestige(comptes: {DonneesFictives.admin: DonneesFictives.motDePasseAdmin}));
  final lignes = [_ligneBl('D1', 'PRODUIT FICTIF UN', '3595583', 24), _ligneBl('D2', 'PRODUIT FICTIF DEUX', '3000000', 10, saisie: 4, lots: 'Z9')];
  final s = app.serveur;
  s.routes['GET /commande/list'] = (_) => const ReponseLocale({
        'data': [
          {'lg_ORDER_ID': 'O1', 'str_REF_ORDER': 'CMD-E2E', 'str_GROSSISTE_LIBELLE': 'GROSSISTE FICTIF', 'int_NBRE_PRODUIT': 48, 'int_LINE': 3, 'PRIX_ACHAT_TOTAL': 45000, 'str_STATUT': 'passed'}
        ],
        'total': 1
      });
  s.routes['GET /commande/list/passees'] = (_) => const ReponseLocale({'data': [], 'total': 0});
  s.routes['GET /commande/list-bons'] = (_) => const ReponseLocale({
        'data': [
          {'lg_BON_LIVRAISON_ID': 'BL1', 'str_REF_LIVRAISON': 'BL-E2E-1', 'str_GROSSISTE_LIBELLE': 'GROSSISTE FICTIF', 'int_NBRE_LIGNE_BL_DETAIL': 2, 'int_NBRE_PRODUIT': 34}
        ],
        'total': 1
      });
  s.routes['GET /commande/bon/items/BL1'] = (r) {
    final q = r.query['query'] ?? '';
    return ReponseLocale({
      'data': [for (final l in lignes) if (q.isEmpty || l['lg_FAMILLE_CIP'] == q) l],
      'total': lignes.length
    });
  };
  s.routes['POST /commande/add-lot'] = (r) {
    final j = jsonDecode(r.corps) as Map<String, dynamic>;
    final l = lignes.firstWhere((x) => x['lg_BON_LIVRAISON_DETAIL'] == j['idBonDetail']);
    l['quantiteSaisie'] = (l['quantiteSaisie'] as int) + (j['qty'] as int);
    l['lots'] = [if ((l['lots'] as String).isNotEmpty) l['lots'], j['numLot']].join('|');
    return const ReponseLocale({'success': true, 'msg': 'Lot enregistré'});
  };
  s.routes['GET /commande/entree-stock/autorisation'] = (_) => const ReponseLocale({'authorize': true});
  s.routes['GET /reception/parametres'] = (_) => ReponseLocale({'success': true, 'peremptionObligatoire': false, if (clotureRecu) 'clotureRecu': true});
  s.routes['PUT /commande/validerbl/BL1'] = (r) => ReponseLocale(r.query['mode'] == 'RECU'
      ? {
          'success': true,
          'msg': 'BL BL-E2E-1 entré avec écart',
          'ecarts': [
            for (final l in lignes)
              if ((l['quantiteSaisie'] as int) < (l['int_QTE_CMDE'] as int))
                {'cip': l['lg_FAMILLE_CIP'], 'nom': l['lg_FAMILLE_NAME'], 'commande': l['int_QTE_CMDE'], 'recu': l['quantiteSaisie'], 'manquant': (l['int_QTE_CMDE'] as int) - (l['quantiteSaisie'] as int)}
          ]
        }
      : {'success': false, 'code': 'PRODUITS_NON_SAISIS', 'produits': ['3000000 PRODUIT FICTIF DEUX (4/10)'], 'msg': 'Produits non saisis'});
  return app;
}

Future<void> _ouvrirReception(WidgetTester t, AppE2E app) async {
  TailleEcran.sunmiV2s.appliquer(t);
  await app.preparer(prefs: {
    'hiddenMenuIds': <String>[],
    'reception_bl_settings_v1': jsonEncode({'shortExpiryMonths': 6, 'terminalValidation': true}),
  });
  await app.lancer(t);
  expect(await app.seConnecter(t, login: DonneesFictives.admin, motDePasse: DonneesFictives.motDePasseAdmin), isTrue);
  await app.ouvrirMenu(t, ListPresentation.dashboard, 'reception_bl');
  await app.attendre(t, const Duration(seconds: 2));
}

void main() {
  for (final recu in [true, false]) {
    testWidgets('réception : lignes des commandes, saisie enchaînée, BL incomplet (serveur ${recu ? 'avec' : 'sans'} « au reçu »)', (t) async {
      final app = _appReception(clotureRecu: recu);
      await _ouvrirReception(t, app);
      expect(find.textContaining('3 lignes'), findsWidgets, reason: 'nombre de lignes de la commande');
      expect(find.textContaining('48'), findsNothing);
      expect(find.textContaining('produit'), findsNothing);

      // BL à entrer → saisie.
      await t.tap(find.text('BL à entrer · 1'));
      await app.attendre(t);
      await t.tap(find.text('Continuer'));
      await app.attendre(t, const Duration(seconds: 2));
      await t.enterText(find.byType(TextField).first, '3595583');
      await app.attendre(t, const Duration(seconds: 2));
      expect(find.text('PRODUIT FICTIF UN'), findsWidgets);
      final lot = find.widgetWithText(TextField, 'N° de lot');
      final date = find.widgetWithText(TextField, 'Péremption (JJ/MM/AAAA ou MM/AAAA)');
      final qte = find.widgetWithText(TextField, 'Quantité (boîtes)');
      await t.tap(lot);
      await t.enterText(lot, 'LE2E');
      await t.testTextInput.receiveAction(TextInputAction.next);
      await app.attendre(t, const Duration(milliseconds: 500));
      expect(t.widget<TextField>(date).focusNode!.hasFocus, isTrue);
      await t.enterText(date, '0128');
      await t.testTextInput.receiveAction(TextInputAction.next);
      await app.attendre(t, const Duration(milliseconds: 500));
      expect(t.widget<TextField>(date).controller!.text, '01/01/2028');
      final cq = t.widget<TextField>(qte).controller!;
      expect(t.widget<TextField>(qte).focusNode!.hasFocus, isTrue);
      expect(cq.selection, TextSelection(baseOffset: 0, extentOffset: cq.text.length), reason: 'quantité pré-sélectionnée');
      t.testTextInput.updateEditingValue(const TextEditingValue(text: '20', selection: TextSelection.collapsed(offset: 2)));
      await t.pump();
      await t.testTextInput.receiveAction(TextInputAction.done);
      await app.attendre(t, const Duration(seconds: 2));
      final ajout = app.serveur.recuesSur('/commande/add-lot').single;
      expect(jsonDecode(ajout.corps), containsPair('datePeremption', '2028-01-01'));
      expect(jsonDecode(ajout.corps), containsPair('qty', 20));

      // BL incomplet : la ligne (20/24) reste ouverte ; on la ferme, puis bilan et écarts.
      await t.tap(find.byTooltip('Fermer').first);
      await app.attendre(t);
      final terminer = find.text('Terminer et vérifier');
      await t.ensureVisible(terminer);
      await t.tap(terminer);
      await app.attendre(t, const Duration(seconds: 2));
      await app.defilerJusqua(t, find.byKey(const Key('bl_ecarts')));
      expect(find.byKey(const Key('bl_ecarts')), findsOneWidget);
      if (!recu) {
        expect(find.byKey(const Key('bl_entrer_recu')), findsNothing);
        expect(app.serveur.recuesSur('/commande/validerbl/BL1'), isEmpty);
      } else {
        final b = find.byKey(const Key('bl_entrer_recu'));
        await t.ensureVisible(b);
        await t.tap(b);
        await app.attendre(t);
        await t.tap(find.text('Entrer le reçu'));
        await app.attendre(t, const Duration(seconds: 2));
        final v = app.serveur.recuesSur('/commande/validerbl/BL1').single;
        expect(v.query['mode'], 'RECU');
        expect(find.text('Reçu entré en stock'), findsOneWidget);
        final resultat = find.byKey(const Key('bl_cloture_recu_resultat'));
        expect(find.descendant(of: resultat, matching: find.textContaining('reçu 20/24, manquant 4')), findsOneWidget);
        expect(find.descendant(of: resultat, matching: find.textContaining('reçu 4/10, manquant 6')), findsOneWidget);
      }
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });
  }

  for (final voir in [true, false]) {
    testWidgets('réserve : saisie manuelle, confirmation du sens, création ; droit « Voir les suggestions » = $voir', (t) async {
      TailleEcran.sunmiV2s.appliquer(t);
      final app = AppE2E(serveur: FauxServeurPrestige(comptes: {DonneesFictives.admin: DonneesFictives.motDePasseAdmin}));
      final s = app.serveur;
      s.routes['GET /reserve/droits'] = (_) => ReponseLocale({'success': true, 'traiter': true, 'annulerMouvement': false, 'voirSuggestions': voir});
      s.routes['GET /reserve/articles'] = (r) => ReponseLocale({
            'results': [
              if ((r.query['search_value'] ?? '') == '3595583')
                {'lg_FAMILLE_ID': 'FR1', 'int_CIP': '3595583', 'str_NAME': 'PRODUIT RESERVE FICTIF', 'int_STOCK_RAYON': 2, 'int_STOCK_RESERVE': 9}
            ],
          });
      s.routes['GET /suggestion-reserve/motifs'] = (_) => const ReponseLocale([
            {'id': 1, 'libelle': 'Reappro rayon journalier', 'categorie': 'RAYON'}
          ]);
      s.routes['GET /suggestion-reserve/en-attente'] = (_) => const ReponseLocale({'results': [], 'total': 0});
      s.routes['POST /suggestion-reserve/creer'] =
          (_) => const ReponseLocale({'success': true, 'lg_SUGGESTION_RESERVE_ID': 'N1', 'str_REF': 'SR-RAY-E2E', 'lignes': 1, 'ignorees': 0});
      s.routes['PUT /N1/ouvrir'] = (_) => ReponseLocale({
            'success': true,
            'entete': DonneesFictives.enteteReserve(id: 'N1'),
            'lignes': [DonneesFictives.ligneReserve('1')],
            'modifiable': true,
          });
      await app.preparer(prefs: {'hiddenMenuIds': <String>[]});
      await app.lancer(t);
      expect(await app.seConnecter(t, login: DonneesFictives.admin, motDePasse: DonneesFictives.motDePasseAdmin), isTrue);
      await app.attendre(t, const Duration(seconds: 2));
      await app.ouvrirMenu(t, ListPresentation.dashboard, 'reserve');
      await app.attendre(t, const Duration(seconds: 2));
      expect(find.byKey(const ValueKey('reserve-onglet-auto')), voir ? findsOneWidget : findsNothing);
      final lecturesAvant = s.recuesSur('/suggestion-reserve/en-attente').length;
      if (!voir) expect(lecturesAvant, 0, reason: 'jamais de lecture des suggestions sans le droit');

      await t.tap(find.descendant(of: find.byKey(const ValueKey('reserve-manuel-versRayon')), matching: find.text('Préparer')));
      await app.attendre(t, const Duration(seconds: 2));
      final champ = find.byKey(const ValueKey('reserve-saisie'));
      await t.tap(champ);
      await t.enterText(champ, '3595583');
      await t.testTextInput.receiveAction(TextInputAction.search);
      await app.attendre(t, const Duration(seconds: 2));
      await t.enterText(find.byKey(const ValueKey('reserve-quantite')), '3');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await app.attendre(t);
      expect(find.text('PRODUIT RESERVE FICTIF'), findsOneWidget);
      expect(t.widget<TextField>(champ).focusNode!.hasFocus, isTrue, reason: 'produit suivant');

      final creer = find.byKey(const ValueKey('reserve-creer'));
      await t.ensureVisible(creer);
      await t.tap(creer);
      await app.attendre(t);
      expect(find.textContaining('vous confirmez le sens ?'), findsOneWidget);
      expect(find.text('Réserve → Rayon'), findsWidgets);
      await t.tap(find.byKey(const ValueKey('reserve-confirmer-sens-oui')));
      await app.attendre(t, const Duration(seconds: 2));
      final c = s.recuesSur('/suggestion-reserve/creer').single;
      expect(jsonDecode(c.corps), containsPair('categorie', 'RAYON'));
      expect((jsonDecode(c.corps)['items'] as List).single, {'lg_FAMILLE_ID': 'FR1', 'int_QTE': 3});
      if (voir) {
        expect(find.byType(ReserveTraitementScreen), findsOneWidget, reason: 'avec le droit : la suggestion s\'ouvre comme avant');
      } else {
        expect(find.byType(ReserveTraitementScreen), findsNothing);
        expect(s.recuesSur('/N1/ouvrir'), isEmpty);
        expect(find.textContaining('elle sera traitée par une personne habilitée'), findsOneWidget);
        expect(s.recuesSur('/suggestion-reserve/en-attente'), isEmpty);
      }
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });
  }
}
