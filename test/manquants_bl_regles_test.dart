// UNITAIRES — Prestige Mobile 4.12.0 (demandes 59 et 60 livrées par le serveur le 08/11) : lecture des réponses du
// serveur, sans écran ni réseau. Formats relevés dans le code du serveur (ManquantsReceptionService,
// CommandeServiceImpl, SuggestionReserveRessource, Droits.interdit). Données FICTIVES.
//  - GET v1/reception/{blId}/ecarts : modes RECU / PROVISOIRE / COMPLET, retourManquants null ou {retourId, ref, statut} ;
//  - POST v1/reception/{blId}/retour-manquants : création, `deja:true` (réponse sans lignes ni totalManquant), refus
//    409 BL_NON_ENTRE_AU_RECU / AUCUN_MANQUANT, 404 BL_INCONNU, 403 interdit ;
//  - PUT validerbl?mode=RECU : refus `AUCUN_RECU` reconnu ; totalManquant lu (ou somme des lignes) ;
//  - demande 60 : 403 « Droit manquant : Voir les suggestions de réserve » reconnu (et pas « Traiter la réserve ») ;
//    droit constaté → suggestions plus proposées, sans toucher au reste.
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
