// UNITAIRES — 4.15.2 : réponse du serveur aux demandes 64 (correctif/demande64-1911, d6cf51fa5) et 65
// (plan/support-1811, f8ef5afa6), données FICTIVES uniquement :
//  - refus « Paiement mobile money impossible : … Le client paie à la caisse. » (champ `message`) reconnu, distinct
//    d'un 403 `interdit`, d'une panne réseau et d'une caisse fermée du comptoir ;
//  - AttentePaiement : une seule demande, jamais de nouvelle demande `cloturer:false`, aucun paiement à suivre ;
//  - messages du verrou du panier (payé / en cours) reconnus, distincts des autres refus ;
//  - diagnostic Mobile Money : borne sans droit de clôture → non proposé (règle du pharmacien du 19/11) ;
//  - demande 65 : contrat de la route image inchangé (tickets lus ; refus `success:false` gardé tel quel).
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/droits/droits_vente.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/paiements/etat_mobile_money.dart';
import 'package:prestige_vente_app/paiements/paiements_mobile.dart';
import 'package:prestige_vente_app/services/ticket_serveur.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';

import 'outils/demande64_fictive.dart';

/// Faux module de paiement : réponse de création choisie, demandes notées.
class _Api implements PaiementsMobileApi {
  _Api(this.reponse);
  VenteResult<PaiementMobile> reponse;
  final List<bool> cloturers = [];
  int statuts = 0;
  @override
  Future<VenteResult<PaiementMobile>> creer({required String venteId, required String operateur, int? part, bool cloturer = false, required String cle}) async {
    cloturers.add(cloturer);
    return reponse;
  }

  @override
  Future<VenteResult<PaiementMobile>> statut(String id) async {
    statuts++;
    return const VenteOk(PaiementMobile(id: 'PM1', venteId: 'V', montant: 4125, operateur: 'wave', statut: StatutPM.enAttente));
  }

  @override
  Future<VenteResult<CapacitesPM>> capacites() async => const VenteOk(CapacitesPM(operateurs: ['wave']));
  @override
  Future<VenteResult<PaiementMobile>> annuler(String id) => statut(id);
  @override
  Future<VenteResult<List<PaiementMobile>>> historique(DateTime jour) async => const VenteOk([]);
}

/// PNG fictif minimal (en-tête seulement : suffit à la lecture du contrat).
final _png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, ...List.filled(24, 0)]);

void main() {
  group('Borne : refus « Paiement mobile money impossible » (point 1)', () {
    test('reconnu par son début, quel que soit le motif ; jamais pris pour un autre refus', () {
      for (final motif in ['la caisse de la borne est fermée.', 'stock insuffisant pour PRODUIT FICTIF.', 'la vente n\'a aucun produit.']) {
        final m = refusPaiementFictif(motif);
        expect(estRefusPaiementImpossible(m), isTrue, reason: motif);
        final r = VenteRefused<void>(m);
        expect((r.interdit, r.caisseFermee, r.dejaCloturee, r.panierVerrouille), (false, false, false, false), reason: motif);
      }
      expect(estRefusPaiementImpossible(messageCaisseFermee), isTrue);
      for (final autre in [
        'Droit manquant : Terminer une vente.',
        'Vente déjà clôturée.',
        'Le service de paiement n\'a pas créé la transaction. Réessayez ou payez autrement.',
        'Paiement : serveur injoignable (connectionError).',
        null,
        '',
      ]) {
        expect(estRefusPaiementImpossible(autre), isFalse, reason: '$autre');
      }
    });

    test('champ `message` lu (pas `msg`) : refus du serveur, pas une panne', () {
      // Même lecture que DioPaiementsMobileApi.creer (corps 200 {success:false, message}).
      final r = jsonDecode(jsonEncode({'success': false, 'message': messageCaisseFermee})) as Map;
      expect(r['msg'], isNull);
      expect('${r['message'] ?? r['msg']}', messageCaisseFermee);
    });

    test('AttentePaiement : une seule demande cloturer:true, refusAvantPaiement, aucun suivi, rien à annuler', () async {
      final avant = JournalTerminal.instance;
      final journal = JournalTerminal(clock: DateTime.now);
      JournalTerminal.instance = journal;
      addTearDown(() => JournalTerminal.instance = avant);
      final api = _Api(const VenteRefused(messageCaisseFermee));
      final a = AttentePaiement(api);
      await a.demarrer(venteId: 'V-FICT', operateur: 'wave', cloturer: true);
      expect(api.cloturers, [true]);
      expect((a.refusAvantPaiement, a.interdit, a.paiement, a.erreur, a.termine), (true, false, null, messageCaisseFermee, false));
      await a.interroger();
      expect(api.statuts, 0, reason: 'aucun paiement à suivre');
      // Journal : motif du serveur (sans donnée de client ni de ticket).
      await journal.idle;
      final j = (await journal.store.lire(const JournalFiltre())).where((e) => e.action.contains('refusé avant paiement')).toList();
      expect(j, hasLength(1));
      expect(j.single.motif, messageCaisseFermee);
      a.dispose();
    });

    test('403 interdit : interdit, pas refusAvantPaiement ; panne réseau : ni l\'un ni l\'autre ; une demande chaque fois', () async {
      for (final (r, interdit) in [
        (const VenteRefused<PaiementMobile>('Droit manquant (fictif).', code: VenteRefused.codeInterdit), true),
        (const VenteFailed<PaiementMobile>('Paiement : serveur injoignable (connectionError).'), false),
      ]) {
        final api = _Api(r);
        final a = AttentePaiement(api);
        await a.demarrer(venteId: 'V-FICT', operateur: 'wave', cloturer: true);
        expect(api.cloturers, [true]);
        expect((a.interdit, a.refusAvantPaiement), (interdit, false));
        a.dispose();
      }
    });

    test('nouvelle tentative après un refus : refusAvantPaiement remis à zéro', () async {
      final api = _Api(const VenteRefused(messageCaisseFermee));
      final a = AttentePaiement(api);
      await a.demarrer(venteId: 'V-FICT', operateur: 'wave', cloturer: true);
      expect(a.refusAvantPaiement, isTrue);
      api.reponse = const VenteOk(PaiementMobile(id: 'PM1', venteId: 'V-FICT', montant: 4125, operateur: 'wave', statut: StatutPM.enAttente, clotureAuto: true));
      await a.demarrer(venteId: 'V-FICT', operateur: 'wave', cloturer: true);
      expect((a.refusAvantPaiement, a.paiement?.id), (false, 'PM1'));
      a.dispose();
    });
  });

  group('Comptoir : verrou du panier (point 2)', () {
    test('messages exacts du serveur reconnus (payé et en cours), opérateur et montant gardés', () {
      expect(refusModificationPanierFictif('wave', 4125, paye: true), messagePayeWave4125);
      expect(refusModificationPanierFictif('orange', 4125, paye: false), messageEnCoursOrange4125);
      for (final op in ['wave', 'orange', 'moov', 'mtn']) {
        for (final paye in [true, false]) {
          final r = VenteRefused<void>(refusModificationPanierFictif(op, 1500, paye: paye));
          expect(r.panierVerrouille, isTrue, reason: '$op $paye');
          expect((r.interdit, r.caisseFermee, r.dejaCloturee, r.paiementMobile), (false, false, false, false), reason: '$op $paye');
          expect(r.message, contains('1500 F'));
        }
      }
    });

    test('autres refus du panier : pas un verrou', () {
      for (final m in [
        'Vente déjà clôturée.',
        'Ce produit n\'est plus dans la vente : actualisez l\'écran avant de continuer.',
        'Votre caisse est fermée',
        'Stock insuffisant',
      ]) {
        expect(VenteRefused<void>(m).panierVerrouille, isFalse, reason: m);
      }
    });
  });

  group('Diagnostic Mobile Money de la borne (règle du pharmacien du 19/11)', () {
    Future<DiagnosticMobileMoney> diag(Set<String>? d, {bool borne = true}) => diagnostiquerMobileMoney(
        actif: true,
        horsLigne: false,
        capacites: () async => const VenteOk(CapacitesPM(operateurs: ['wave'])),
        droits: () async => d,
        compte: 'borne.fictive',
        borne: borne);

    test('sans droit de clôture : non proposé ; avec P_BORNE_PAIEMENT_MOBILE ou « Terminer une vente » : proposé', () async {
      final sans = await diag({'P_SM_VENTE'});
      expect((sans.etat, sans.propose), (EtatMobileMoney.sansDroit, false));
      expect(sans.message, contains('P_BORNE_PAIEMENT_MOBILE'));
      expect((await diag({'P_SM_VENTE', DroitsVente.bornePaiementMobileDroit})).etat, EtatMobileMoney.propose);
      expect((await diag({'P_SM_CLOTURER_CAISSE'})).message, 'Proposé au client : Wave.');
      expect((await diag(null)).etat, EtatMobileMoney.propose, reason: 'droits inconnus (serveur ancien) : comme avant');
      for (final d in [<String>{}, {'P_SM_VENTE'}, {'P_SM_CLOTURER_CAISSE'}, null]) {
        expect((await diag(d)).etat, isNot(EtatMobileMoney.proposeSansCloture), reason: '$d');
      }
    });

    test('droit de la borne : la note dit que caisse fermée = le client paie à la caisse', () async {
      final d = await diag({'P_SM_VENTE', DroitsVente.bornePaiementMobileDroit});
      expect(d.message, contains('sinon le client paie à la caisse'));
    });

    test('encaissement de l\'application : texte d\'avant inchangé', () async {
      expect((await diag({'P_SM_VENTE'}, borne: false)).message,
          'Mobile Money activé, mais le compte « borne.fictive » n\'a pas le droit de clôturer : donnez-lui P_SM_CLOTURER_CAISSE (ou P_SM_DEPOT_EXTENSION, P_BT_MODIFICATION_DE_VENTE).');
    });
  });

  group('Demande 65 : route image du ticket inchangée', () {
    Dio dio(int code, Object? corps) {
      final d = Dio(BaseOptions(baseUrl: 'http://prestige.fictif/prestige/api/v1'));
      d.httpClientAdapter = _Adaptateur(code, jsonEncode(corps));
      return d;
    }

    setUp(TicketServeur.oublier);
    tearDown(TicketServeur.oublier);

    test('chemin et paramètres de la route inchangés', () {
      expect(TicketServeur.chemin(TypeTicketServeur.vno, 'V-FICT'), '/vente/ticket/vno/V-FICT/image');
      expect(TicketServeur.chemin(TypeTicketServeur.prevente, 'V-FICT'), '/vente/ticket/prevente/V-FICT/image');
    });

    test('serveur avec la demande 65 (sans imprimante) : tickets rendus et lus comme en 4.15.1', () async {
      final r = await TicketServeur.lire(
          dio(200, {
            'success': true,
            'largeur': 58,
            'dpi': 203,
            'tickets': [
              {'modele': 'VENTE', 'png': base64Encode(_png), 'largeurPoints': 384, 'hauteurPoints': 600}
            ],
          }),
          type: TypeTicketServeur.vno,
          id: 'V-FICT',
          largeur: 58);
      expect(r, isA<TicketsServeur>());
      expect((r as TicketsServeur).tickets.single.largeurPoints, 384);
    });

    test('serveur déployé sans imprimante (refus 200 success:false) : message gardé tel quel, comme en 4.15.1', () async {
      const m = 'Ticket non imprimé : aucune imprimante n\'est installée sur le poste serveur.';
      final r = await TicketServeur.lire(dio(200, {'success': false, 'msg': m, 'imprimanteAbsente': true}),
          type: TypeTicketServeur.vno, id: 'V-FICT', largeur: 58);
      expect(r, isA<TicketRefuseVente>());
      expect((r as TicketRefuseVente).message, m);
    });
  });
}

/// Adaptateur HTTP en mémoire (réponse JSON fixe).
class _Adaptateur implements HttpClientAdapter {
  _Adaptateur(this.code, this.corps);
  final int code;
  final String corps;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      ResponseBody.fromString(corps, code, headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8']
      });
  @override
  void close({bool force = false}) {}
}
