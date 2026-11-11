// UNITAIRES — Prestige Mobile 4.12.0 (demandes 59 et 60 livrées par le serveur le 08/11) : lecture des réponses du
// serveur, sans écran ni réseau. Formats relevés dans le code du serveur (ManquantsReceptionService,
// CommandeServiceImpl, SuggestionReserveRessource, Droits.interdit). Données FICTIVES.
//  - GET v1/reception/{blId}/ecarts : modes RECU / PROVISOIRE / COMPLET, retourManquants null ou {retourId, ref, statut} ;
//  - POST v1/reception/{blId}/retour-manquants : création, `deja:true` (réponse sans lignes ni totalManquant), refus
//    409 BL_NON_ENTRE_AU_RECU / AUCUN_MANQUANT, 404 BL_INCONNU, 403 interdit ;
//  - PUT validerbl?mode=RECU : refus `AUCUN_RECU` reconnu ; totalManquant lu (ou somme des lignes) ;
//  - demande 60 : 403 « Droit manquant : Voir les suggestions de réserve » reconnu (et pas « Traiter la réserve ») ;
//    droit constaté → suggestions plus proposées, sans toucher au reste.
// 4.12.1 (serveur du 11/11) : retour abandonné (ne bloque plus), texte selon le statut, `lignes` / `totalManquant` de
// `retourManquants` et de `deja:true` lus s'ils sont présents (absents : serveur plus ancien, comme 4.12.0) ; `deja:true`
// d'un abandonné (serveur ancien) signalé.
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/droits/droits_modules.dart';
import 'package:prestige_vente_app/reception/manquants_bl.dart';
import 'package:prestige_vente_app/reception/reception_gateway.dart';
import 'package:prestige_vente_app/reception/reception_models.dart';
import 'package:prestige_vente_app/reserve/reserve_api.dart';
import 'package:prestige_vente_app/serveur/client_prestige.dart';

const _ligne = {'detailId': 'D1', 'cip': '3595583', 'nom': 'PRODUIT FICTIF', 'commande': 10, 'recu': 7, 'ug': 1, 'manquant': 3};

void main() {
  group('écarts du BL (GET reception/{blId}/ecarts)', () {
    test('mode RECU, retour des manquants existant', () {
      final e = EcartsBl.fromJson({
        'success': true,
        'blId': 'BL1',
        'ref': 'BL-FICTIF',
        'mode': 'RECU',
        'provisoire': false,
        'ecarts': [_ligne],
        'totalManquant': 3,
        'retourManquants': {'retourId': 'R1', 'ref': 'RF-0001', 'statut': 'is_Waiting'},
      });
      expect(e.success, isTrue);
      expect(e.entreAuRecu, isTrue);
      expect(e.provisoire, isFalse);
      expect(e.ecarts.single.libelle, 'PRODUIT FICTIF — reçu 7/10, manquant 3');
      expect((e.ecarts.single.detailId, e.ecarts.single.ug), ('D1', 1));
      expect(e.totalManquant, 3);
      expect(e.retour!.libelle, 'Retour RF-0001 (en attente de validation)');
    });

    test('mode PROVISOIRE (BL ouvert), retourManquants null', () {
      final e = EcartsBl.fromJson({'success': true, 'mode': 'PROVISOIRE', 'provisoire': true, 'ecarts': [_ligne, _ligne], 'totalManquant': 6, 'retourManquants': null});
      expect((e.provisoire, e.entreAuRecu, e.ecarts.length, e.totalManquant, e.retour), (true, false, 2, 6, null));
    });

    test('mode COMPLET (ancienne voie) : aucun écart', () {
      final e = EcartsBl.fromJson({'success': true, 'mode': 'COMPLET', 'provisoire': false, 'ecarts': [], 'totalManquant': 0, 'retourManquants': null});
      expect((e.success, e.entreAuRecu, e.ecarts.length, e.totalManquant), (true, false, 0, 0));
    });

    test('totalManquant absent : somme des lignes ; nombres en texte tolérés', () {
      final e = EcartsBl.fromJson({'success': true, 'mode': 'recu', 'ecarts': [{..._ligne, 'manquant': '4'}, _ligne]});
      expect((e.totalManquant, e.entreAuRecu), (7, true));
    });

    test('refus BL_INCONNU, réponse illisible', () {
      final e = EcartsBl.fromJson({'success': false, 'code': 'BL_INCONNU', 'msg': 'Ce BL n\'existe pas.'});
      expect((e.success, e.code, e.message), (false, 'BL_INCONNU', 'Ce BL n\'existe pas.'));
      expect(EcartsBl.fromJson('<html>').success, isFalse);
    });
  });

  group('retour des manquants (POST reception/{blId}/retour-manquants)', () {
    test('création : référence, lignes, total, rien ne sort du stock', () {
      final r = RetourManquants.fromJson({
        'success': true,
        'deja': false,
        'retourId': 'R1',
        'ref': 'RF-0001',
        'statut': 'is_Waiting',
        'lignes': 2,
        'totalManquant': 9,
        'route': 'POST v1/reception/{blId}/retour-manquants',
        'msg': 'Retour des manquants RF-0001 créé',
      });
      expect((r.success, r.deja, r.retourId, r.ref, r.lignes, r.totalManquant), (true, false, 'R1', 'RF-0001', 2, 9));
      expect(r.texte, 'Retour RF-0001 créé, en attente de validation sur Prestige : rien ne sort du stock (2 ligne(s), 9 boîte(s)).');
    });

    test('second appel : deja:true (sans lignes ni totalManquant) → « Retour <ref> déjà créé »', () {
      final r = RetourManquants.fromJson({'success': true, 'deja': true, 'retourId': 'R1', 'ref': 'RF-0001', 'statut': 'is_Waiting', 'msg': '…'});
      expect(r.deja, isTrue);
      expect(r.texte, 'Retour RF-0001 déjà créé (en attente de validation).');
    });

    test('refus métier : message clair par code', () {
      for (final (code, attendu) in [
        ('BL_NON_ENTRE_AU_RECU', 'pas été entré au reçu'),
        ('AUCUN_MANQUANT', 'aucun manquant'),
        ('BL_INCONNU', 'n\'existe pas'),
      ]) {
        final r = RetourManquants.fromJson({'success': false, 'code': code, 'msg': 'message serveur'});
        expect((r.success, r.code), (false, code));
        expect(r.texte, contains(attendu), reason: code);
      }
      final autre = RetourManquants.fromJson({'success': false, 'msg': 'Autre refus'});
      expect(autre.texte, 'Autre refus');
    });

    test('statuts du retour en clair', () {
      expect(libelleStatutRetour('is_Waiting'), 'en attente de validation');
      expect(libelleStatutRetour('is_Refused'), 'refusé');
      expect(libelleStatutRetour('is_Abandoned'), 'abandonné');
      expect(libelleStatutRetour('enable'), 'validé');
    });

    test('clés X-Client-Ref : uniques, préfixées', () {
      final a = nouvelleCleRetourManquants(), b = nouvelleCleRetourManquants();
      expect(a, isNot(b));
      expect(a, startsWith('BLM-'));
      expect(nouvelleCleClotureRecu(), startsWith('BLR-'));
    });
  });

  group('4.12.1 : retour abandonné, statuts, lignes et totalManquant (serveur du 11/11)', () {
    test('écarts : retourManquants abandonné (le plus récent) avec lignes et totalManquant', () {
      final e = EcartsBl.fromJson({
        'success': true,
        'mode': 'RECU',
        'ecarts': [_ligne],
        'totalManquant': 3,
        'retourManquants': {'retourId': 'R1', 'ref': 'RF-0001', 'statut': 'is_Abandoned', 'lignes': 1, 'totalManquant': 3},
      });
      final r = e.retour!;
      expect((r.abandonne, r.lignes, r.totalManquant), (true, 1, 3));
      expect(r.texte, 'Retour RF-0001 abandonné sur Prestige : il ne compte plus.');
    });

    test('serveur plus ancien : lignes / totalManquant absents → null, libellé de 4.12.0', () {
      final r = RetourExistant.fromJson({'retourId': 'R1', 'ref': 'RF-0001', 'statut': 'is_Waiting'})!;
      expect((r.lignes, r.totalManquant, r.abandonne), (null, null, false));
      expect(r.libelle, 'Retour RF-0001 (en attente de validation)');
      expect(r.texte, 'Retour RF-0001 (en attente de validation) : à valider dans « Retour fournisseur » sur Prestige ; rien ne sort du stock.');
      final illisible = RetourExistant.fromJson({'retourId': 'R1', 'ref': 'RF-0001', 'statut': 'is_Waiting', 'lignes': 'x', 'totalManquant': null})!;
      expect((illisible.lignes, illisible.totalManquant), (null, null));
      expect(RetourExistant.fromJson({'retourId': 'R1', 'ref': 'RF-1', 'lignes': '2', 'totalManquant': 5.0})!.lignes, 2, reason: 'nombre en texte toléré');
    });

    test('texte selon le statut : en attente, en saisie, refusé, validé, abandonné, inconnu', () {
      RetourExistant r(String statut) => RetourExistant(retourId: 'R1', ref: 'RF-0001', statut: statut, lignes: 2, totalManquant: 8);
      expect(r('is_Waiting').texte, 'Retour RF-0001 (en attente de validation ; 2 ligne(s), 8 boîte(s)) : à valider dans « Retour fournisseur » sur Prestige ; rien ne sort du stock.');
      expect(r('is_Process').texte, contains('à valider dans « Retour fournisseur »'));
      expect(r('is_Refused').texte, 'Retour RF-0001 (refusé ; 2 ligne(s), 8 boîte(s)) : à corriger dans « Retour fournisseur » sur Prestige ; rien ne sort du stock.');
      expect(r('enable').texte, 'Retour RF-0001 (validé ; 2 ligne(s), 8 boîte(s)) : traité dans « Retour fournisseur » sur Prestige ; rien n\'est sorti du stock.');
      expect(r('is_Abandoned').texte, 'Retour RF-0001 abandonné sur Prestige : il ne compte plus.');
      expect(r('statut_futur').texte, contains('à valider'), reason: 'statut inconnu : texte de 4.12.0');
      for (final s in ['is_Waiting', 'is_Process', 'is_Refused', 'enable', 'statut_futur']) {
        expect(r(s).abandonne, isFalse, reason: '$s bloque une nouvelle création');
      }
    });

    test('deja:true de même forme que la création : lignes et totalManquant lus et affichés', () {
      final r = RetourManquants.fromJson({
        'success': true,
        'deja': true,
        'retourId': 'R1',
        'ref': 'RF-0001',
        'statut': 'is_Refused',
        'lignes': 2,
        'totalManquant': 8,
        'route': 'POST v1/reception/{blId}/retour-manquants',
        'msg': 'existe déjà',
      });
      expect((r.deja, r.lignes, r.totalManquant), (true, 2, 8));
      expect(r.texte, 'Retour RF-0001 déjà créé (refusé ; 2 ligne(s), 8 boîte(s)).');
      expect((r.retour.ref, r.retour.statut, r.retour.lignes, r.retour.totalManquant), ('RF-0001', 'is_Refused', 2, 8));
    });

    test('création après un abandon (deja:false) : nouveau retour, en attente', () {
      final r = RetourManquants.fromJson(
          {'success': true, 'deja': false, 'retourId': 'R2', 'ref': 'RF-0002', 'statut': 'is_Waiting', 'lignes': 1, 'totalManquant': 3, 'msg': 'créé'});
      expect(r.texte, startsWith('Retour RF-0002 créé, en attente de validation'));
      expect(r.retour.abandonne, isFalse);
    });

    test('serveur ancien : deja:true d\'un retour abandonné → signalé, aucun retour créé', () {
      final r = RetourManquants.fromJson({'success': true, 'deja': true, 'retourId': 'R1', 'ref': 'RF-0001', 'statut': 'is_Abandoned'});
      expect(r.texte, 'Retour RF-0001 abandonné : aucun nouveau retour n\'a été créé (serveur Prestige à mettre à jour).');
      expect(r.retour.abandonne, isTrue);
      expect((r.retour.lignes, r.retour.totalManquant), (null, null));
    });
  });

  group('clôture au reçu (PUT validerbl?mode=RECU)', () {
    test('refus AUCUN_RECU reconnu, autres refus non', () {
      expect(estAucunRecu(const ReceptionResult(false, 'x', {'success': false, 'code': 'AUCUN_RECU'})), isTrue);
      expect(estAucunRecu(const ReceptionResult(false, 'x', {'success': false, 'code': 'PRODUITS_NON_SAISIS'})), isFalse);
      expect(estAucunRecu(const ReceptionResult(true, 'x', {'code': 'AUCUN_RECU'})), isFalse);
      expect(messageAucunRecu, contains('le BL reste ouvert'));
    });

    test('totalManquant lu, sinon somme des lignes', () {
      final l = lignesEcart([_ligne, _ligne]);
      expect(totalManquantDe({'totalManquant': 10}, l), 10);
      expect(totalManquantDe(const {}, l), 6);
      expect(lignesEcart(null), isEmpty);
    });
  });

  group('demande 60 : droit « Voir les suggestions de réserve »', () {
    test('403 de ce droit reconnu ; « Traiter la réserve » et 403 sans message non', () {
      expect(refusVoirSuggestions(const ErreurHttp(403, detail: 'Droit manquant : Voir les suggestions de réserve')), isTrue);
      expect(refusVoirSuggestions(const ErreurHttp(403, detail: 'Droit manquant : Traiter la réserve')), isFalse);
      expect(refusVoirSuggestions(const ErreurHttp(403)), isFalse);
      expect(refusVoirSuggestions(const SessionExpiree()), isFalse);
      expect(estDroitManquant(const ErreurHttp(403, detail: 'Droit manquant : Traiter la réserve')), isTrue);
      expect(estDroitManquant(const ErreurHttp(500)), isFalse);
    });

    test('refus constaté : suggestions plus proposées, le reste des droits inchangé', () {
      final d = DroitsModules();
      d.fixer(reserveDedie: true, reserveSuggestions: true, adminServeur: true);
      var notifs = 0;
      d.addListener(() => notifs++);
      d.suggestionsRefusees();
      expect(d.reserveSuggestions, isFalse);
      expect(d.reserve, isTrue);
      expect(notifs, 1);
      d.suggestionsRefusees();
      expect(notifs, 1, reason: 'déjà constaté : rien de plus');
    });
  });
}
