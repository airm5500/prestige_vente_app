// ÉCRANS — Prestige Mobile 4.12.0 (demandes 59 et 60 livrées par le serveur le 08/11), faux services, données
// FICTIVES :
//  - « Entrer le reçu » : X-Client-Ref gardée d'un essai à l'autre ; refus AUCUN_RECU → message clair, le BL reste
//    ouvert (on reste sur le bilan) ;
//  - capacité `retourManquants` : écarts PROVISOIRES du serveur dans la confirmation, bilan relu après la clôture
//    (mode RECU), « Créer un retour en attente des manquants » → référence affichée ; `deja:true` → « Retour <ref> déjà
//    créé » ; retour existant relu → pas de bouton ; 403 → message du droit, plus de bouton ; délai dépassé → même
//    clé au nouvel essai ;
//  - sans la capacité : aucun bouton, aucune relecture, fenêtre de 4.11.0 ;
//  - réserve : 403 « Voir les suggestions de réserve » → « Droit manquant », pas de « Réessayer », pas de
//    déconnexion, suggestions plus proposées.
// 4.12.1 (serveur du 11/11) : retour existant ABANDONNÉ → « Retour <ref> abandonné », bouton reproposé, le retour créé
// le remplace ; refusé / validé / en attente → pas de bouton, texte selon le statut ; lignes et total du retour
// affichés s'ils sont donnés ; X-Client-Ref : même clé à chaque essai, NOUVELLE clé pour une création après un abandon.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/droits/droits_modules.dart';
import 'package:prestige_vente_app/reception/manquants_bl.dart';
import 'package:prestige_vente_app/reception/reception_gateway.dart';
import 'package:prestige_vente_app/reception/reception_logic.dart';
import 'package:prestige_vente_app/reception/reception_models.dart';
import 'package:prestige_vente_app/reserve/reserve_api.dart';
import 'package:prestige_vente_app/reserve/reserve_models.dart';
import 'package:prestige_vente_app/reserve/reserve_screen.dart';
import 'package:prestige_vente_app/screens/reception_bl/reception_summary_screen.dart';
import 'package:prestige_vente_app/serveur/client_prestige.dart';

import 'reception_bl_test.dart' show FakePrestigeRecu;

const _bl = ReceptionBl(id: 'bl1', ref: 'BL-778', grossiste: 'GROSSISTE FICTIF');

/// Serveur avec la demande 59 complète (clôture au reçu + écarts + retour des manquants).
class FakeManquants extends FakePrestigeRecu implements RetourManquantsGateway {
  bool capacite = true;
  final recuRefs = <String?>[];
  final retourRefs = <String>[];
  final ecartsLus = <String>[];
  ReceptionResult? reponseRecu;
  EcartsBl? provisoire;
  EcartsBl? apres;
  bool clos = false;
  final reponsesRetour = <RetourManquants>[];

  @override
  Future<ReceptionResult> validateRecu(String blId, {String? clientRef}) async {
    recuRefs.add(clientRef);
    final r = reponseRecu ?? await super.validateRecu(blId, clientRef: clientRef);
    if (r.success) clos = true;
    return r;
  }

  @override
  Future<bool> retourManquantsDisponible() async => capacite;

  @override
  Future<EcartsBl> ecartsBl(String blId) async {
    ecartsLus.add(clos ? 'RECU' : 'PROVISOIRE');
    return (clos ? apres : provisoire) ?? EcartsBl.refus('non lu');
  }

  @override
  Future<RetourManquants> creerRetourManquants(String blId, {required String clientRef}) async {
    retourRefs.add(clientRef);
    return reponsesRetour.isEmpty ? RetourManquants.refus('aucune réponse') : reponsesRetour.removeAt(0);
  }
}

const _lignes = [
  ReceptionLine(detailId: 'd1', produitId: 'p1', name: 'PRODUIT FICTIF UN', code: '3595583', ordered: 10, entered: 7, lots: ['L1'], blRef: 'BL-778'),
  ReceptionLine(detailId: 'd2', produitId: 'p2', name: 'PRODUIT FICTIF DEUX', code: '3000000', ordered: 5, blRef: 'BL-778'),
];

const _ecartsServeur = [
  LigneEcart(detailId: 'd1', cip: '3595583', nom: 'PRODUIT FICTIF UN', commande: 10, recu: 7, manquant: 3),
  LigneEcart(detailId: 'd2', cip: '3000000', nom: 'PRODUIT FICTIF DEUX', commande: 5, recu: 0, manquant: 5),
];

Future<void> _bilan(WidgetTester t, ReceptionGateway g) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 2.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (c) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => Navigator.of(c).push(MaterialPageRoute<bool>(
                builder: (_) => ReceptionSummaryScreen(
                    bl: _bl, gateway: g, settings: const ReceptionSettings(terminalValidation: true), lines: _lignes, clock: () => DateTime(2026, 11, 9)))),
            child: const Text('ouvrir'),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('ouvrir'));
  await t.pumpAndSettle();
}

Future<void> _entrerLeRecu(WidgetTester t) async {
  final b = find.byKey(const Key('bl_entrer_recu'));
  await t.ensureVisible(b);
  await t.tap(b);
  await t.pumpAndSettle();
  await t.tap(find.text('Entrer le reçu'));
  await t.pumpAndSettle();
}

Map<String, dynamic> _reponseRecu({int total = 8}) => {
      'success': true,
      'mode': 'RECU',
      'msg': 'BL entré en stock avec écart : 2 ligne(s), $total boîte(s) manquante(s)',
      'ecarts': [
        {'detailId': 'd1', 'cip': '3595583', 'nom': 'PRODUIT FICTIF UN', 'commande': 10, 'recu': 7, 'ug': 0, 'manquant': 3},
        {'detailId': 'd2', 'cip': '3000000', 'nom': 'PRODUIT FICTIF DEUX', 'commande': 5, 'recu': 0, 'ug': 0, 'manquant': 5},
      ],
      'totalManquant': total,
      'reserve': [],
    };

void main() {
  group('clôture au reçu (demande 59)', () {
    testWidgets('AUCUN_RECU : message clair, rien n\'est entré, on reste sur le bilan ; nouvel essai avec la même clé', (t) async {
      final g = FakeManquants()
        ..reponseRecu = const ReceptionResult(false, 'Aucune ligne reçue', {'success': false, 'code': 'AUCUN_RECU', 'msg': 'Aucune ligne reçue'});
      await _bilan(t, g);
      await _entrerLeRecu(t);
      expect(find.byKey(const Key('bl_aucun_recu')), findsOneWidget);
      expect(find.textContaining('rien n\'est entré en stock et le BL reste ouvert'), findsOneWidget);
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(find.text('Bilan BL BL-778'), findsOneWidget, reason: 'le BL reste ouvert : bilan toujours affiché');
      await _entrerLeRecu(t);
      expect(g.recuRefs, hasLength(2));
      expect(g.recuRefs.first, startsWith('BLR-'));
      expect(g.recuRefs.toSet(), hasLength(1), reason: 'même X-Client-Ref d\'un essai à l\'autre (le refus n\'est pas gardé)');
    });

    testWidgets('autre refus : message du serveur, on reste sur le bilan', (t) async {
      final g = FakeManquants()..reponseRecu = const ReceptionResult(false, 'BL déjà clôturé', {'success': false, 'msg': 'BL déjà clôturé'});
      await _bilan(t, g);
      await _entrerLeRecu(t);
      expect(find.byKey(const Key('bl_cloture_recu_refus')), findsOneWidget);
      expect(find.text('BL déjà clôturé'), findsOneWidget);
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(find.text('Bilan BL BL-778'), findsOneWidget);
    });

    testWidgets('capacité retourManquants : écarts provisoires du serveur dans la confirmation, bilan relu, retour créé', (t) async {
      final g = FakeManquants()
        ..reponseRecu = ReceptionResult(true, 'BL entré en stock avec écart', _reponseRecu())
        ..provisoire = const EcartsBl(success: true, mode: 'PROVISOIRE', provisoire: true, ecarts: _ecartsServeur, totalManquant: 8)
        ..apres = const EcartsBl(success: true, mode: 'RECU', ecarts: _ecartsServeur, totalManquant: 8)
        ..reponsesRetour.add(const RetourManquants(success: true, retourId: 'R1', ref: 'RF-0001', statut: 'is_Waiting', lignes: 2, totalManquant: 8));
      await _bilan(t, g);
      final b = find.byKey(const Key('bl_entrer_recu'));
      await t.ensureVisible(b);
      await t.tap(b);
      await t.pumpAndSettle();
      expect(g.ecartsLus, ['PROVISOIRE']);
      expect(find.textContaining('2 ligne(s) en écart, 8 boîte(s) manquante(s)'), findsOneWidget);
      await t.tap(find.text('Entrer le reçu'));
      await t.pumpAndSettle();
      expect(g.ecartsLus, ['PROVISOIRE', 'RECU'], reason: 'bilan relu sur le serveur après la clôture');
      expect(find.text('Total manquant : 8 boîte(s).'), findsOneWidget);
      final creer = find.byKey(const Key('bl_retour_manquants'));
      expect(creer, findsOneWidget);
      expect(find.text('Créer un retour en attente des manquants'), findsOneWidget);
      await t.tap(creer);
      await t.pumpAndSettle();
      expect(g.retourRefs.single, startsWith('BLM-'));
      expect(find.textContaining('Retour RF-0001 créé, en attente de validation'), findsOneWidget);
      expect(find.byKey(const Key('bl_retour_manquants_existant')), findsOneWidget);
      expect(creer, findsNothing, reason: 'un seul retour par BL');
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(find.text('ouvrir'), findsOneWidget, reason: 'BL entré : retour à la liste');
    });

    testWidgets('deja:true → « Retour <ref> déjà créé »', (t) async {
      final g = FakeManquants()
        ..reponseRecu = ReceptionResult(true, 'ok', _reponseRecu())
        ..reponsesRetour.add(const RetourManquants(success: true, deja: true, retourId: 'R1', ref: 'RF-0001', statut: 'is_Waiting'));
      await _bilan(t, g);
      await _entrerLeRecu(t);
      await t.tap(find.byKey(const Key('bl_retour_manquants')));
      await t.pumpAndSettle();
      expect(find.text('Retour RF-0001 déjà créé (en attente de validation).'), findsOneWidget);
      expect(find.byKey(const Key('bl_retour_manquants')), findsNothing);
    });

    testWidgets('retour déjà existant (relu par les écarts) : pas de bouton, sa référence', (t) async {
      final g = FakeManquants()
        ..reponseRecu = ReceptionResult(true, 'ok', _reponseRecu())
        ..apres = const EcartsBl(
            success: true, mode: 'RECU', ecarts: _ecartsServeur, totalManquant: 8, retour: RetourExistant(retourId: 'R9', ref: 'RF-0009', statut: 'is_Waiting'));
      await _bilan(t, g);
      await _entrerLeRecu(t);
      expect(find.byKey(const Key('bl_retour_manquants')), findsNothing);
      expect(find.textContaining('Retour RF-0009 (en attente de validation)'), findsOneWidget);
      expect(g.retourRefs, isEmpty);
    });

    testWidgets('403 (droit retours fournisseur manquant) : message du serveur, plus de bouton, pas de déconnexion', (t) async {
      final g = FakeManquants()
        ..reponseRecu = ReceptionResult(true, 'ok', _reponseRecu())
        ..reponsesRetour.add(RetourManquants.refus('Droit manquant : Retours fournisseur', interdit: true, status: 403));
      await _bilan(t, g);
      await _entrerLeRecu(t);
      await t.tap(find.byKey(const Key('bl_retour_manquants')));
      await t.pumpAndSettle();
      expect(find.text('Droit manquant : Retours fournisseur'), findsOneWidget);
      expect(find.byKey(const Key('bl_retour_manquants')), findsNothing);
      expect(find.byKey(const Key('bl_cloture_recu_resultat')), findsOneWidget, reason: 'aucune déconnexion, la fenêtre reste');
    });

    testWidgets('délai dépassé puis nouvel essai : MÊME X-Client-Ref (jamais deux retours)', (t) async {
      final g = FakeManquants()
        ..reponseRecu = ReceptionResult(true, 'ok', _reponseRecu())
        ..reponsesRetour.addAll([
          RetourManquants.refus('Le serveur ne répond pas.'),
          const RetourManquants(success: true, retourId: 'R1', ref: 'RF-0001', statut: 'is_Waiting', lignes: 2, totalManquant: 8),
        ]);
      await _bilan(t, g);
      await _entrerLeRecu(t);
      await t.tap(find.byKey(const Key('bl_retour_manquants')));
      await t.pumpAndSettle();
      expect(find.text('Le serveur ne répond pas.'), findsOneWidget);
      await t.tap(find.byKey(const Key('bl_retour_manquants')));
      await t.pumpAndSettle();
      expect(g.retourRefs, hasLength(2));
      expect(g.retourRefs.toSet(), hasLength(1));
      expect(find.textContaining('Retour RF-0001 créé'), findsOneWidget);
    });

    testWidgets('aucun manquant (tout reçu au final) : pas de bouton', (t) async {
      final g = FakeManquants()
        ..reponseRecu = const ReceptionResult(true, 'BL entré en stock : tout a été reçu', {'success': true, 'mode': 'RECU', 'ecarts': [], 'totalManquant': 0})
        ..apres = const EcartsBl(success: true, mode: 'RECU');
      await _bilan(t, g);
      await _entrerLeRecu(t);
      expect(find.byKey(const Key('bl_retour_manquants')), findsNothing);
    });

    testWidgets('SANS la capacité retourManquants : fenêtre de 4.11.0, aucune relecture, aucun bouton', (t) async {
      final g = FakeManquants()
        ..capacite = false
        ..reponseRecu = ReceptionResult(true, 'BL entré avec écart', _reponseRecu());
      await _bilan(t, g);
      await _entrerLeRecu(t);
      expect(find.byKey(const Key('bl_cloture_recu_resultat')), findsOneWidget);
      expect(find.text('Écart au rapport :'), findsOneWidget);
      expect(find.text('PRODUIT FICTIF UN — reçu 7/10, manquant 3'), findsWidgets);
      expect(find.byKey(const Key('bl_retour_manquants')), findsNothing);
      expect(find.byKey(const Key('bl_total_manquant')), findsNothing);
      expect(g.ecartsLus, isEmpty);
      expect(g.retourRefs, isEmpty);
    });

    testWidgets('passerelle 4.11.0 (sans RetourManquantsGateway) : comportement inchangé', (t) async {
      final g = FakePrestigeRecu()
        ..add('d1', 'PRODUIT FICTIF UN', '3595583', '3400935955838', 10, entered: 7, lots: ['L1'])
        ..add('d2', 'PRODUIT FICTIF DEUX', '3000000', '3400930000007', 5);
      await _bilan(t, g);
      await _entrerLeRecu(t);
      expect(g.recuCalls, 1);
      expect(find.byKey(const Key('bl_cloture_recu_resultat')), findsOneWidget);
      expect(find.byKey(const Key('bl_retour_manquants')), findsNothing);
    });
  });

  group('4.12.1 : retour abandonné et statuts (serveur du 11/11)', () {
    FakeManquants avecRetour(RetourExistant r) => FakeManquants()
      ..reponseRecu = ReceptionResult(true, 'ok', _reponseRecu())
      ..apres = EcartsBl(success: true, mode: 'RECU', ecarts: _ecartsServeur, totalManquant: 8, retour: r);

    testWidgets('retour abandonné : mention, bouton reproposé, le retour créé remplace l\'abandonné', (t) async {
      final g = avecRetour(const RetourExistant(retourId: 'R9', ref: 'RF-0009', statut: 'is_Abandoned', lignes: 2, totalManquant: 8))
        ..reponsesRetour.add(const RetourManquants(success: true, retourId: 'R10', ref: 'RF-0010', statut: 'is_Waiting', lignes: 2, totalManquant: 8));
      await _bilan(t, g);
      await _entrerLeRecu(t);
      expect(find.text('Retour RF-0009 abandonné sur Prestige : il ne compte plus.'), findsOneWidget);
      expect(find.textContaining('à valider'), findsNothing, reason: 'un abandonné n\'est pas « à valider »');
      final creer = find.byKey(const Key('bl_retour_manquants'));
      expect(creer, findsOneWidget, reason: 'un retour abandonné ne bloque pas');
      await t.tap(creer);
      await t.pumpAndSettle();
      expect(g.retourRefs.single, startsWith('BLM-'));
      expect(find.textContaining('Retour RF-0010 créé, en attente de validation'), findsOneWidget);
      expect(find.textContaining('RF-0009'), findsNothing, reason: 'le nouveau retour remplace l\'ancien à l\'affichage');
      expect(find.text('Retour RF-0010 (en attente de validation ; 2 ligne(s), 8 boîte(s)) : à valider dans « Retour fournisseur » sur Prestige ; rien ne sort du stock.'),
          findsOneWidget);
      expect(creer, findsNothing, reason: 'nouveau retour en attente : un seul par BL');
    });

    testWidgets('retour abandonné : délai dépassé puis nouvel essai → MÊME clé', (t) async {
      final g = avecRetour(const RetourExistant(retourId: 'R9', ref: 'RF-0009', statut: 'is_Abandoned'))
        ..reponsesRetour.addAll([
          RetourManquants.refus('Le serveur ne répond pas.'),
          const RetourManquants(success: true, retourId: 'R10', ref: 'RF-0010', statut: 'is_Waiting'),
        ]);
      await _bilan(t, g);
      await _entrerLeRecu(t);
      await t.tap(find.byKey(const Key('bl_retour_manquants')));
      await t.pumpAndSettle();
      expect(find.text('Le serveur ne répond pas.'), findsOneWidget);
      expect(find.textContaining('RF-0009 abandonné'), findsOneWidget, reason: 'l\'abandonné reste affiché tant que rien n\'est créé');
      await t.tap(find.byKey(const Key('bl_retour_manquants')));
      await t.pumpAndSettle();
      expect(g.retourRefs, hasLength(2));
      expect(g.retourRefs.toSet(), hasLength(1), reason: 'même tentative : même X-Client-Ref');
      expect(find.textContaining('Retour RF-0010 créé'), findsOneWidget);
    });

    testWidgets('serveur ancien (deja:true d\'un abandonné) : signalé, bouton reproposé avec une NOUVELLE clé', (t) async {
      final g = avecRetour(const RetourExistant(retourId: 'R9', ref: 'RF-0009', statut: 'is_Abandoned'))
        ..reponsesRetour.addAll([
          const RetourManquants(success: true, deja: true, retourId: 'R9', ref: 'RF-0009', statut: 'is_Abandoned'),
          const RetourManquants(success: true, retourId: 'R10', ref: 'RF-0010', statut: 'is_Waiting'),
        ]);
      await _bilan(t, g);
      await _entrerLeRecu(t);
      await t.tap(find.byKey(const Key('bl_retour_manquants')));
      await t.pumpAndSettle();
      expect(find.text('Retour RF-0009 abandonné : aucun nouveau retour n\'a été créé (serveur Prestige à mettre à jour).'), findsOneWidget);
      final m = t.widget<Text>(find.byKey(const Key('bl_retour_manquants_message')));
      expect(m.style?.color, Colors.red.shade800, reason: 'rien n\'a été créé');
      expect(find.byKey(const Key('bl_retour_manquants')), findsOneWidget);
      await t.tap(find.byKey(const Key('bl_retour_manquants')));
      await t.pumpAndSettle();
      expect(g.retourRefs, hasLength(2));
      expect(g.retourRefs[1], isNot(g.retourRefs[0]), reason: 'création après un abandon : nouvelle clé (sinon la réponse serait rejouée)');
      expect(g.retourRefs[1], startsWith('BLM-'));
      expect(find.textContaining('Retour RF-0010 créé'), findsOneWidget);
      expect(find.byKey(const Key('bl_retour_manquants')), findsNothing);
    });

    for (final (statut, attendu) in [
      ('is_Waiting', 'à valider dans « Retour fournisseur » sur Prestige'),
      ('is_Process', 'à valider dans « Retour fournisseur » sur Prestige'),
      ('is_Refused', 'à corriger dans « Retour fournisseur » sur Prestige'),
      ('enable', 'traité dans « Retour fournisseur » sur Prestige'),
    ]) {
      testWidgets('retour existant $statut : pas de bouton, « $attendu »', (t) async {
        final g = avecRetour(RetourExistant(retourId: 'R9', ref: 'RF-0009', statut: statut));
        await _bilan(t, g);
        await _entrerLeRecu(t);
        expect(find.byKey(const Key('bl_retour_manquants')), findsNothing, reason: '$statut bloque toujours');
        expect(find.textContaining(attendu), findsOneWidget);
        expect(find.textContaining('abandonné'), findsNothing);
        expect(g.retourRefs, isEmpty);
      });
    }

    testWidgets('deja:true d\'un retour refusé (nouvelle forme) : lignes et total affichés, plus de bouton', (t) async {
      final g = FakeManquants()
        ..reponseRecu = ReceptionResult(true, 'ok', _reponseRecu())
        ..reponsesRetour.add(const RetourManquants(success: true, deja: true, retourId: 'R1', ref: 'RF-0001', statut: 'is_Refused', lignes: 2, totalManquant: 8));
      await _bilan(t, g);
      await _entrerLeRecu(t);
      await t.tap(find.byKey(const Key('bl_retour_manquants')));
      await t.pumpAndSettle();
      expect(find.text('Retour RF-0001 déjà créé (refusé ; 2 ligne(s), 8 boîte(s)).'), findsOneWidget);
      expect(find.textContaining('à corriger dans « Retour fournisseur »'), findsOneWidget);
      expect(find.byKey(const Key('bl_retour_manquants')), findsNothing);
    });
  });

  group('réserve : 403 du droit « Voir les suggestions de réserve » (demande 60)', () {
    testWidgets('écran Réserve : « Droit manquant », pas de « Réessayer », suggestions plus proposées', (t) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 2.0;
      addTearDown(t.view.reset);
      DroitsModules.instance.fixer(reserveDedie: true, reserveSuggestions: null);
      addTearDown(DroitsModules.instance.oublier);
      final api = _Api403();
      await t.pumpWidget(MaterialApp(home: ReserveScreen(api: api)));
      await t.pumpAndSettle();
      expect(api.lectures, 1);
      expect(find.text('Droit manquant : Voir les suggestions de réserve'), findsOneWidget);
      expect(find.text('Réessayer'), findsNothing, reason: 'réessayer ne donnerait pas le droit');
      expect(find.text('Se reconnecter'), findsNothing, reason: 'jamais une déconnexion');
      expect(DroitsModules.instance.reserveSuggestions, isFalse);
    });
  });
}

class _Api403 extends ReserveApi {
  _Api403() : super(ClientPrestige(() => 'http://127.0.0.1:1/prestige/api/v1'));
  int lectures = 0;
  @override
  Future<List<EnteteSuggestion>> enAttente({int limit = 200}) async {
    lectures++;
    const e = ErreurHttp(403, detail: 'Droit manquant : Voir les suggestions de réserve');
    if (refusVoirSuggestions(e)) DroitsModules.instance.suggestionsRefusees();
    throw e;
  }
}
