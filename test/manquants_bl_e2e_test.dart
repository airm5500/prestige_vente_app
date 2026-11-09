// E2E — Prestige Mobile 4.12.0 (demandes 59 et 60 livrées par le serveur le 08/11) : application ENTIÈRE contre le
// faux serveur Prestige en mémoire, Sunmi V2s, données FICTIVES. BL de 2 lignes : une non saisie (0/24), une
// incomplète (4/10).
//  1. serveur complet : écarts provisoires du serveur dans la confirmation (GET reception/BL1/ecarts), PUT
//     validerbl?mode=RECU avec X-Client-Ref, bilan relu, « Créer un retour en attente des manquants » → POST
//     retour-manquants avec X-Client-Ref → référence affichée ;
//  2. refus AUCUN_RECU : message clair, BL laissé ouvert (bilan toujours affiché) ;
//  3. profil sans droit retours fournisseur : 403 → message du droit, aucune déconnexion ;
//  4. serveur qui n'annonce que clotureRecu (4.11.0) : aucun bouton, aucune lecture des écarts.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
      'str_REF_LIVRAISON': 'BL-E2E-2',
      'int_QTE_RECUE_BIS': -1,
    };

const _ecarts = [
  {'detailId': 'D1', 'cip': '3595583', 'nom': 'PRODUIT FICTIF UN', 'commande': 24, 'recu': 0, 'ug': 0, 'manquant': 24},
  {'detailId': 'D2', 'cip': '3000000', 'nom': 'PRODUIT FICTIF DEUX', 'commande': 10, 'recu': 4, 'ug': 0, 'manquant': 6},
];

enum _Cas { complet, aucunRecu, sansDroitRetour, serveur4110 }

AppE2E _app(_Cas cas) {
  final app = AppE2E(serveur: FauxServeurPrestige(comptes: {DonneesFictives.admin: DonneesFictives.motDePasseAdmin}));
  final s = app.serveur;
  final lignes = [_ligneBl('D1', 'PRODUIT FICTIF UN', '3595583', 24), _ligneBl('D2', 'PRODUIT FICTIF DEUX', '3000000', 10, saisie: 4, lots: 'Z9')];
  var clos = false;
  s.routes['GET /commande/list'] = (_) => const ReponseLocale({'data': [], 'total': 0});
  s.routes['GET /commande/list/passees'] = (_) => const ReponseLocale({'data': [], 'total': 0});
  s.routes['GET /commande/list-bons'] = (_) => const ReponseLocale({
        'data': [
          {'lg_BON_LIVRAISON_ID': 'BL1', 'str_REF_LIVRAISON': 'BL-E2E-2', 'str_GROSSISTE_LIBELLE': 'GROSSISTE FICTIF', 'int_NBRE_LIGNE_BL_DETAIL': 2, 'int_NBRE_PRODUIT': 34}
        ],
        'total': 1
      });
  s.routes['GET /commande/bon/items/BL1'] = (_) => ReponseLocale({'data': lignes, 'total': lignes.length});
  s.routes['GET /commande/entree-stock/autorisation'] = (_) => const ReponseLocale({'authorize': true});
  s.routes['GET /reception/parametres'] = (_) => ReponseLocale(
      {'success': true, 'peremptionObligatoire': false, 'clotureRecu': true, if (cas != _Cas.serveur4110) 'retourManquants': true});
  s.routes['GET /reception/BL1/ecarts'] = (_) => ReponseLocale({
        'success': true,
        'blId': 'BL1',
        'ref': 'BL-E2E-2',
        'mode': clos ? 'RECU' : 'PROVISOIRE',
        'provisoire': !clos,
        'ecarts': _ecarts,
        'totalManquant': 30,
        'retourManquants': null
      });
  s.routes['PUT /commande/validerbl/BL1'] = (r) {
    if (r.query['mode'] != 'RECU') return const ReponseLocale({'success': false, 'msg': 'mode attendu'});
    if (cas == _Cas.aucunRecu) return const ReponseLocale({'success': false, 'code': 'AUCUN_RECU', 'msg': 'Aucune ligne de ce BL n\'a de lot'});
    clos = true;
    return const ReponseLocale(
        {'success': true, 'mode': 'RECU', 'msg': 'BL entré en stock avec écart : 2 ligne(s), 30 boîte(s) manquante(s)', 'ecarts': _ecarts, 'totalManquant': 30, 'reserve': []});
  };
  s.routes['POST /reception/BL1/retour-manquants'] = (_) => cas == _Cas.sansDroitRetour
      ? FauxServeurPrestige.interdit('Droit manquant : Retours fournisseur')
      : const ReponseLocale({
          'success': true,
          'deja': false,
          'retourId': 'R1',
          'ref': 'RF-E2E-1',
          'statut': 'is_Waiting',
          'lignes': 2,
          'totalManquant': 30,
          'route': 'POST v1/reception/{blId}/retour-manquants',
          'msg': 'Retour des manquants RF-E2E-1 créé, en attente de validation ; rien ne sort du stock'
        });
  return app;
}

void main() {
  for (final cas in _Cas.values) {
    testWidgets('réception : BL incomplet entré au reçu, manquants — ${cas.name}', (t) async {
      TailleEcran.sunmiV2s.appliquer(t);
      final app = _app(cas);
      await app.preparer(prefs: {
        'hiddenMenuIds': <String>[],
        'reception_bl_settings_v1': jsonEncode({'shortExpiryMonths': 6, 'terminalValidation': true}),
      });
      await app.lancer(t);
      expect(await app.seConnecter(t, login: DonneesFictives.admin, motDePasse: DonneesFictives.motDePasseAdmin), isTrue);
      final connexions = app.serveur.connexions;
      await app.ouvrirMenu(t, ListPresentation.dashboard, 'reception_bl');
      await app.attendre(t, const Duration(seconds: 2));
      await t.tap(find.text('BL à entrer · 1'));
      await app.attendre(t);
      await t.tap(find.text('Continuer'));
      await app.attendre(t, const Duration(seconds: 2));
      final terminer = find.text('Terminer et vérifier');
      await t.ensureVisible(terminer);
      await t.tap(terminer);
      await app.attendre(t, const Duration(seconds: 2));
      final b = find.byKey(const Key('bl_entrer_recu'));
      await t.ensureVisible(b);
      await t.tap(b);
      await app.attendre(t);
      final ecartsLus = app.serveur.recuesSur('/reception/BL1/ecarts');
      if (cas == _Cas.serveur4110) {
        expect(ecartsLus, isEmpty, reason: 'serveur 4.11.0 : aucune lecture des écarts');
      } else {
        expect(ecartsLus, hasLength(1));
        expect(find.textContaining('2 ligne(s) en écart, 30 boîte(s) manquante(s)'), findsOneWidget);
      }
      await t.tap(find.text('Entrer le reçu'));
      await app.attendre(t, const Duration(seconds: 2));
      final v = app.serveur.recuesSur('/commande/validerbl/BL1').single;
      expect(v.query['mode'], 'RECU');
      expect(v.clientRef, startsWith('BLR-'));

      if (cas == _Cas.aucunRecu) {
        expect(find.byKey(const Key('bl_aucun_recu')), findsOneWidget);
        await t.tap(find.text('OK'));
        await app.attendre(t);
        expect(find.text('Bilan BL BL-E2E-2'), findsOneWidget, reason: 'BL laissé ouvert');
        expect(app.serveur.recuesSur('/reception/BL1/retour-manquants'), isEmpty);
      } else if (cas == _Cas.serveur4110) {
        expect(find.byKey(const Key('bl_cloture_recu_resultat')), findsOneWidget);
        expect(find.byKey(const Key('bl_retour_manquants')), findsNothing);
        expect(app.serveur.recuesSur('/reception/BL1/ecarts'), isEmpty);
      } else {
        expect(app.serveur.recuesSur('/reception/BL1/ecarts'), hasLength(2), reason: 'bilan relu après la clôture');
        final creer = find.byKey(const Key('bl_retour_manquants'));
        expect(creer, findsOneWidget);
        await t.tap(creer);
        await app.attendre(t, const Duration(seconds: 2));
        final p = app.serveur.recuesSur('/reception/BL1/retour-manquants').single;
        expect(p.clientRef, startsWith('BLM-'));
        if (cas == _Cas.complet) {
          expect(find.textContaining('Retour RF-E2E-1 créé, en attente de validation'), findsOneWidget);
          expect(creer, findsNothing);
        } else {
          expect(find.text('Droit manquant : Retours fournisseur'), findsOneWidget);
          expect(creer, findsNothing);
          expect(app.serveur.connexions, connexions, reason: '403 : jamais une déconnexion');
        }
        await t.tap(find.text('OK'));
        await app.attendre(t, const Duration(seconds: 2));
        expect(find.text('Bilan BL BL-E2E-2'), findsNothing, reason: 'BL entré : retour à la réception');
      }
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });
  }
}
