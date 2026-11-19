// UNITAIRES — 4.15.0 : demande 62 (branche serveur correctif/demande62-1911, fb0a3cc2) et décision du pharmacien du
// 19/11 (remise ouverte aux comptes de prévente). Données FICTIVES uniquement.
//  - droit P_BORNE_PAIEMENT_MOBILE : clôture automatique de la borne, JAMAIS « Terminer une vente » ;
//  - repli sûr sur un 403 `interdit` à cloturer:true (une seule nouvelle demande, cloturer:false, même clé) ;
//  - « vente terminée » seulement si le serveur confirme la clôture (`cloture:true`) ;
//  - prévente payée : lecture de `paiementMobile` / `typeReglementAttente`, textes du bandeau et de la liste ;
//  - refus `{success:false, paiementMobile:true}` reconnu ; serveur ancien : rien de tout cela.
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/borne/borne_service.dart';
import 'package:prestige_vente_app/borne/borne_ticket.dart';
import 'package:prestige_vente_app/droits/droits_vente.dart';
import 'package:prestige_vente_app/paiements/etat_mobile_money.dart';
import 'package:prestige_vente_app/paiements/paiements_mobile.dart';
import 'package:prestige_vente_app/paiements/prevente_payee.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/common/remise_vente.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';

/// Vente de GET ventestats/{id} d'un serveur avec la demande 62 (valeurs fictives).
Map<String, dynamic> venteFictivePayee({int montant = 4125, String op = 'wave', String? type = '10'}) => {
      'lgPREENREGISTREMENTID': 'V-FICT-1',
      'strSTATUT': 'is_Process',
      'paiementMobile': {
        'id': 'PM-FICT-1',
        'venteId': 'V-FICT-1',
        'montant': montant,
        'operateur': op,
        'operateurLibelle': op == 'wave' ? 'Wave' : 'Orange Money',
        'typeReglement': type,
        'referenceFournisseur': 'TX-FICT-0042',
        'payeLe': '2026-11-19 10:42:07.0',
        'statut': 'paye',
      },
      if (type != null) 'typeReglementAttente': type,
    };

class _Api implements PaiementsMobileApi {
  final List<(bool, String)> creations = [];
  bool refuserCloture = true;
  @override
  Future<VenteResult<PaiementMobile>> creer({required String venteId, required String operateur, int? part, bool cloturer = false, required String cle}) async {
    creations.add((cloturer, cle));
    if (cloturer && refuserCloture) return const VenteRefused('Droit manquant (fictif).', code: VenteRefused.codeInterdit);
    return VenteOk(PaiementMobile(id: 'PM1', venteId: venteId, montant: 1500, operateur: operateur, statut: StatutPM.enAttente, clotureAuto: cloturer));
  }

  @override
  Future<VenteResult<PaiementMobile>> statut(String id) async => const VenteOk(PaiementMobile(id: 'PM1', venteId: 'V', montant: 1500, operateur: 'wave', statut: StatutPM.enAttente));
  @override
  Future<VenteResult<CapacitesPM>> capacites() async => const VenteOk(CapacitesPM(operateurs: ['wave']));
  @override
  Future<VenteResult<PaiementMobile>> annuler(String id) => statut(id);
  @override
  Future<VenteResult<List<PaiementMobile>>> historique(DateTime jour) async => const VenteOk([]);
}

void main() {
  group('Droit P_BORNE_PAIEMENT_MOBILE (point 3a)', () {
    test('le droit seul : clôture automatique, mais JAMAIS « Terminer une vente »', () {
      final d = DroitsVente()..fixer({'P_SM_VENTE', DroitsVente.bornePaiementMobileDroit});
      expect(d.bornePaiementMobile, isTrue);
      expect(d.cloturerPaiementMobile, isTrue);
      expect(d.terminerVente, isFalse, reason: 'aucun bouton ordinaire d\'encaissement');
      expect(d.preventeSeule, isTrue);
    });

    test('sans le droit : comme 4.14.0 (terminer une vente seulement) ; droits inconnus : comme avant', () {
      final d = DroitsVente()..fixer({'P_SM_VENTE'});
      expect(d.cloturerPaiementMobile, isFalse);
      d.fixer({'P_SM_CLOTURER_CAISSE'});
      expect((d.cloturerPaiementMobile, d.bornePaiementMobile), (true, false));
      d.fixer(null);
      expect((d.cloturerPaiementMobile, d.bornePaiementMobile, d.terminerVente), (true, false, true));
    });

    test('diagnostic de la borne : le droit seul → « Proposé », avec la condition de la caisse ouverte', () async {
      Future<DiagnosticMobileMoney> diag(Set<String>? d, {bool borne = true}) => diagnostiquerMobileMoney(
          actif: true,
          horsLigne: false,
          capacites: () async => const VenteOk(CapacitesPM(operateurs: ['wave'])),
          droits: () async => d,
          compte: 'borne.fictive',
          borne: borne);
      final b = await diag({'P_SM_VENTE', DroitsVente.bornePaiementMobileDroit});
      expect(b.etat, EtatMobileMoney.propose);
      expect(b.message, contains('P_BORNE_PAIEMENT_MOBILE'));
      expect(b.message, contains('caisse ouverte'));
      expect((await diag({'P_SM_VENTE'})).etat, EtatMobileMoney.proposeSansCloture, reason: 'inchangé (4.13.1)');
      final avec = await diag({'P_SM_CLOTURER_CAISSE'});
      expect(avec.message, 'Proposé au client : Wave.', reason: 'texte de 4.14.0 inchangé');
      expect((await diag({'P_SM_VENTE', DroitsVente.bornePaiementMobileDroit}, borne: false)).etat, EtatMobileMoney.sansDroit,
          reason: 'encaissement de l\'application : le droit de la borne ne suffit pas');
    });
  });

  group('Paiement de la borne : repli et clôture confirmée', () {
    test('403 interdit à cloturer:true, repli demandé : UNE nouvelle demande cloturer:false, même clé X-Client-Ref', () async {
      final api = _Api();
      final a = AttentePaiement(api);
      await a.demarrer(venteId: 'V1', operateur: 'wave', cloturer: true, repliSiInterdit: true);
      expect(api.creations.map((c) => c.$1), [true, false]);
      expect(api.creations[0].$2, api.creations[1].$2);
      expect((a.repliSansCloture, a.clotureDemandee, a.interdit, a.paiement?.id), (true, false, false, 'PM1'));
      a.dispose();
    });

    test('403 sans repli demandé (serveur sans la demande 62) : comportement de 4.14.0 (aucune nouvelle demande)', () async {
      final api = _Api();
      final a = AttentePaiement(api);
      await a.demarrer(venteId: 'V1', operateur: 'wave', cloturer: true);
      expect(api.creations.map((c) => c.$1), [true]);
      expect((a.interdit, a.paiement), (true, null));
      a.dispose();
    });

    test('second refus impossible à cloturer:false : jamais plus de deux demandes', () async {
      final api = _Api()..refuserCloture = false;
      final a = AttentePaiement(api);
      await a.demarrer(venteId: 'V1', operateur: 'wave', cloturer: true, repliSiInterdit: true);
      expect(api.creations, hasLength(1));
      expect((a.repliSansCloture, a.clotureDemandee), (false, true));
      a.dispose();
    });

    test('clôture confirmée seulement par cloture:true (payé + clôture refusée faute de caisse → non)', () {
      PaiementMobile p(StatutPM s, {bool auto = true, bool cloture = false}) =>
          PaiementMobile(id: 'P', venteId: 'V', montant: 1, operateur: 'wave', statut: s, clotureAuto: auto, cloture: cloture);
      expect(p(StatutPM.paye, cloture: true).clotureConfirmee, isTrue);
      expect(p(StatutPM.paye).clotureConfirmee, isFalse, reason: 'caisse de la borne fermée');
      expect(p(StatutPM.paye, auto: false).clotureConfirmee, isFalse, reason: 'cloturer:false');
      expect(p(StatutPM.enAttente, cloture: true).clotureConfirmee, isFalse);
    });

    test('ticket de la borne : « PAYÉE, présentez ce ticket à la caisse » tant que la vente n\'est pas terminée', () {
      final pv = BornePrevente(venteId: 'V1', reference: '261119_00042', total: 4125, lignes: const [], at: DateTime(2026, 11, 19, 10, 42));
      final aTerminer = BorneTicket(officine: 'PHARMACIE FICTIVE', prevente: pv, payePar: 'Wave', aTerminer: true);
      expect(aTerminer.invitationTexte, 'PAYÉE, présentez ce ticket à la caisse');
      expect(aTerminer.titre, 'VENTE BORNE - PAYEE');
      final terminee = BorneTicket(officine: 'PHARMACIE FICTIVE', prevente: pv, payePar: 'Wave');
      expect(terminee.invitationTexte, BorneTicket.invitationPayee);
      expect(BorneTicket(officine: 'X', prevente: pv).invitationTexte, BorneTicket.invitation);
    });
  });

  group('Prévente payée (point 3b)', () {
    test('lecture : opérateur, montant, numéro, date, mode imposé (typeReglementAttente)', () {
      final p = PreventePayee.depuisVente(venteFictivePayee())!;
      expect((p.operateur, p.operateurLibelle, p.typeReglement, p.montant, p.reference), ('wave', 'Wave', '10', 4125, 'TX-FICT-0042'));
      expect(p.bandeau, 'Déjà payée par Wave : ${Constants.formatNumber(4125)} F · n° TX-FICT-0042 · 19/11/2026 10:42');
      expect(p.colonne, startsWith('Payée Wave 4'));
      expect(p.consigne(4125), contains('Ne rien encaisser'));
      expect(p.consigne(5000), contains('complément'));
      expect(p.consigne(3000), contains('ne peut pas être terminée'));
    });

    test('mode : typeReglementAttente, sinon typeReglement, sinon celui de l\'opérateur', () {
      expect(PreventePayee.depuisVente(venteFictivePayee(type: null))!.typeReglement, '10');
      final v = venteFictivePayee(op: 'orange', type: null);
      (v['paiementMobile'] as Map).remove('typeReglement');
      expect(PreventePayee.depuisVente(v)!.typeReglement, '7');
    });

    test('serveur sans la demande 62 (aucun champ), champ illisible ou montant nul : rien', () {
      expect(PreventePayee.depuisVente({'strSTATUT': 'is_Process', 'lgTYPEVENTEID': '1'}), isNull);
      expect(PreventePayee.depuisVente({'paiementMobile': 'oui'}), isNull);
      expect(PreventePayee.depuisVente(venteFictivePayee(montant: 0)), isNull);
      expect(PreventePayee.depuisVente(null), isNull);
    });

    test('liste des préventes : champ lu dans la ligne, absent → null (badge d\'origine)', () {
      final avec = PreventeListItem.fromJson({
        'lgPREENREGISTREMENTID': 'V-FICT-1',
        'heure': '10:42:00',
        'dtUPDATED': '19/11/2026',
        'intPRICE': 4125,
        'strREF': 'REF-FICT',
        'userFullName': 'Vendeur Fictif',
        'lgTYPEVENTEID': '1',
        ...venteFictivePayee(),
      });
      expect(avec.paiementMobile?.montant, 4125);
      final sans = PreventeListItem.fromJson(
          {'lgPREENREGISTREMENTID': 'V2', 'heure': '', 'dtUPDATED': '', 'intPRICE': 1, 'strREF': '', 'userFullName': '', 'lgTYPEVENTEID': '1'});
      expect(sans.paiementMobile, isNull);
    });

    test('refus du serveur : code paiementMobile (message tel quel), distinct d\'une caisse fermée ou d\'une double clôture', () {
      const r = VenteRefused<void>('Cette prévente est déjà payée par Wave : 4125 F (n° TX-FICT-0042). Terminez-la avec le mode Wave pour ce '
          'montant, sans encaisser à nouveau.', code: VenteRefused.codePaiementMobile);
      expect(r.paiementMobile, isTrue);
      expect(r.caisseFermee, isFalse);
      expect(r.dejaCloturee, isFalse);
      expect(r.interdit, isFalse);
    });
  });

  group('Remise (décision du pharmacien du 19/11)', () {
    test('compte de prévente seulement : remise proposée, comme le web ; refus 403 du serveur : masquée', () {
      final d = DroitsVente()..fixer({'P_SM_VENTE'});
      expect(d.terminerVente, isFalse);
      expect(remiseAutorisee(d), isTrue);
      d.controleConstate(droitRemiseVente);
      expect(remiseAutorisee(d), isFalse);
    });

    test('compte de la borne (droit P_BORNE_PAIEMENT_MOBILE) : la remise dépend de l\'écran, la borne n\'en a pas', () {
      final d = DroitsVente()..fixer({DroitsVente.bornePaiementMobileDroit});
      expect(remiseAutorisee(d), isTrue, reason: 'règle du compte ; l\'écran de la borne n\'a aucune zone Remise (garde-fou)');
    });
  });
}
