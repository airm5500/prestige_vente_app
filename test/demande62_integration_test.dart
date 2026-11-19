// INTÉGRATION — 4.15.0 : demande 62 contre le faux serveur Prestige en VRAI HTTP (session de la connexion), règles de
// la branche serveur correctif/demande62-1911 (fb0a3cc2) lues dans le code, données FICTIVES :
//  - GET v1/user/droits : P_BORNE_PAIEMENT_MOBILE lu ; il ne donne pas « Terminer une vente » ;
//  - POST v1/paiements-mobile cloturer:true : accepté avec le droit de la borne ; 403 interdit sans droit (rien créé),
//    puis cloturer:false accepté ; serveur d'aujourd'hui : le droit de la borne ne suffit pas ;
//  - clôture automatique sans caisse ouverte : statut payé, cloture:false, message « Clôture refusée » ;
//  - GET v1/ventestats/{id} et ventestats/preventes : paiementMobile + typeReglementAttente ; absents sinon ;
//  - POST v1/vente/cloturer/vno : refus {success:false, paiementMobile:true, msg} (message tel quel) si le mode de
//    l'opérateur ne porte pas le montant payé ; accepté avec ce mode, ou avec un complément.
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/droits/droits_vente.dart';
import 'package:prestige_vente_app/paiements/paiements_mobile.dart';
import 'package:prestige_vente_app/paiements/prevente_payee.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';

import 'outils/clients_vente_fictifs.dart';
import 'outils/demande62_fictive.dart';
import 'outils/faux_serveur_prestige.dart';
import 'outils/parcours_vente.dart';

void main() {
  late FauxServeurPrestige srv;
  late Demande62Fictive d62;
  late ApiService api;
  late DioVenteGateway gw;
  late DioPaiementsMobileApi pm;

  Future<void> connecter({List<String>? droits}) async {
    if (droits != null) srv.droitsComptes = {DonneesFictives.login: droits};
    await DioClient.cookieJar.deleteAll();
    api = ApiService(baseUrl: srv.base);
    expect(await api.login(DonneesFictives.login, DonneesFictives.motDePasse), isNotNull);
    gw = DioVenteGateway(api);
    pm = DioPaiementsMobileApi(() => api.dio);
  }

  setUp(() => avecVraiHttp(() async {
        srv = FauxServeurPrestige();
        CatalogueFictif(srv, nombre: 5);
        ClientsVenteFictifs(srv);
        d62 = Demande62Fictive(srv);
        await srv.demarrer();
        await connecter();
      }));
  tearDown(() => avecVraiHttp(() async {
        await srv.arreter();
        await DioClient.cookieJar.deleteAll();
      }));

  Future<String> prevente({int pu = 4125}) async {
    final id = (await gw.addItemVno(produitId: 'F1', qte: 1, itemPu: pu, prevente: true)).valueOrNull!;
    expect((await gw.terminerPrevente(id)).isOk, isTrue);
    return id;
  }

  group('Point 3a : droit de la borne', () {
    test('droit lu dans user/droits ; il donne la clôture automatique, pas « Terminer une vente »', () => avecVraiHttp(() async {
          await connecter(droits: ['P_SM_VENTE', droitBorne]);
          final d = DroitsVente();
          await d.actualiser(api.dio, utilisateur: DonneesFictives.login);
          expect((d.bornePaiementMobile, d.cloturerPaiementMobile, d.terminerVente), (true, true, false));
        }));

    test('cloturer:true avec le droit de la borne et caisse ouverte : payé et clôturé (vente terminée)', () => avecVraiHttp(() async {
          await connecter(droits: ['P_SM_VENTE', droitBorne]);
          d62.caissesOuvertes.add(DonneesFictives.login);
          final id = await prevente();
          final c = (await pm.creer(venteId: id, operateur: 'wave', cloturer: true, cle: 'PM-FICT-A')).valueOrNull!;
          expect(c.clotureAuto, isTrue);
          d62.payer(c.id);
          final s = (await pm.statut(c.id)).valueOrNull!;
          expect((s.statut, s.clotureConfirmee), (StatutPM.paye, true));
          expect(srv.statutVentes[id], 'is_Closed');
        }));

    test('droit de la borne SANS caisse ouverte : payé, cloture:false, « Clôture refusée » → prévente payée', () => avecVraiHttp(() async {
          await connecter(droits: ['P_SM_VENTE', droitBorne]);
          final id = await prevente();
          final c = (await pm.creer(venteId: id, operateur: 'wave', cloturer: true, cle: 'PM-FICT-B')).valueOrNull!;
          d62.payer(c.id);
          final s = (await pm.statut(c.id)).valueOrNull!;
          expect((s.statut, s.clotureAuto, s.cloture, s.clotureConfirmee), (StatutPM.paye, true, false, false));
          expect(s.message, startsWith('Clôture refusée'));
          expect(srv.statutVentes[id], 'is_Process');
          final v = (await gw.fullSale(id)).valueOrNull!;
          expect(PreventePayee.depuisVente(v)?.montant, 4125, reason: 'le comptoir la voit payée');
        }));

    test('sans droit : 403 interdit avant toute création ; 4.15.2 (demande 64) : AUCUNE demande cloturer:false ensuite', () => avecVraiHttp(() async {
          await connecter(droits: ['P_SM_VENTE']);
          final id = await prevente();
          final r = await pm.creer(venteId: id, operateur: 'wave', cloturer: true, cle: 'PM-FICT-C');
          expect((r as VenteRefused).interdit, isTrue);
          expect(d62.paiements, isEmpty, reason: 'rien créé');
          final a = AttentePaiement(pm);
          await a.demarrer(venteId: id, operateur: 'wave', cloturer: true);
          expect(d62.creations.map((c) => c['cloturer']), [true, true]);
          expect((a.interdit, a.paiement), (true, null));
          expect(d62.paiements, isEmpty, reason: 'jamais de prévente payée non terminée');
          a.dispose();
        }));

    test('serveur d\'aujourd\'hui : le droit de la borne (s\'il existait) ne suffit pas, 403 comme en 4.14.0', () => avecVraiHttp(() async {
          d62.d62 = false;
          await connecter(droits: ['P_SM_VENTE', droitBorne]);
          final id = await prevente();
          expect(((await pm.creer(venteId: id, operateur: 'wave', cloturer: true, cle: 'PM-FICT-D')) as VenteRefused).interdit, isTrue);
        }));
  });

  group('Point 3b : prévente payée au comptoir', () {
    test('ventestats/{id} et liste : paiementMobile + typeReglementAttente ; prévente non payée : rien', () => avecVraiHttp(() async {
          final payee = await prevente();
          final autre = await prevente(pu: 1500);
          d62.payeeALaBorne(payee);
          final p = PreventePayee.depuisVente((await gw.fullSale(payee)).valueOrNull);
          expect((p?.operateurLibelle, p?.typeReglement, p?.montant, p?.reference), ('Wave', '10', 4125, 'TX-FICT-0042'));
          expect(PreventePayee.depuisVente((await gw.fullSale(autre)).valueOrNull), isNull);
          final liste = (await gw.preventes()).valueOrNull!;
          expect({for (final l in liste) l.lgPREENREGISTREMENTID: l.paiementMobile?.colonne}, {payee: startsWith('Payée Wave'), autre: null});
        }));

    test('clôture en espèces refusée : {success:false, paiementMobile:true}, message tel quel, rien écrit', () => avecVraiHttp(() async {
          final id = await prevente();
          d62.payeeALaBorne(id);
          final net = (await gw.netVno(id)).valueOrNull!;
          final r = await gw.cloturerVno(venteId: id, summary: net, typeReglementId: '1', clientId: '', userVendeurId: 'U-FICT');
          expect(r, isA<VenteRefused<Map<String, dynamic>>>());
          expect((r as VenteRefused).paiementMobile, isTrue);
          expect(r.message, startsWith('Cette prévente est déjà payée par Wave : 4125 F (n° TX-FICT-0042).'));
          expect(srv.statutVentes[id], 'is_Process');
        }));

    test('clôture avec le mode de l\'opérateur pour le montant payé : acceptée, paiement marqué clôturé', () => avecVraiHttp(() async {
          final id = await prevente();
          final p = d62.payeeALaBorne(id);
          final net = (await gw.netVno(id)).valueOrNull!;
          final r = await gw.cloturerVno(venteId: id, summary: net, typeReglementId: '10', clientId: '', userVendeurId: 'U-FICT');
          expect(r.isOk, isTrue);
          expect(srv.statutVentes[id], 'is_Closed');
          expect((p.cloture, p.message), (true, 'Vente terminée au comptoir'));
          expect(d62.clotures.single['reglements'], [
            {'montant': 4125, 'montantAttentu': 4125, 'typeReglement': '10'}
          ]);
        }));

    test('net augmenté : Wave = montant payé + complément espèces, acceptée ; tout en Wave refusé', () => avecVraiHttp(() async {
          final id = await prevente();
          d62.payeeALaBorne(id, montant: 3000);
          final net = (await gw.netVno(id)).valueOrNull!;
          final tout = await gw.cloturerVno(venteId: id, summary: net, typeReglementId: '10', clientId: '', userVendeurId: 'U-FICT');
          expect((tout as VenteRefused).paiementMobile, isTrue);
          final r = await gw.cloturerVnoReglements(
            venteId: id,
            summary: net,
            reglements: const [(typeReglementId: '10', montant: 3000, montantVerse: null), (typeReglementId: '1', montant: 1125, montantVerse: 2000)],
            clientId: '',
            userVendeurId: 'U-FICT',
            montantRecu: 4125 + 875,
            montantRemis: 875,
          );
          expect(r.isOk, isTrue);
        }));

    test('serveur d\'aujourd\'hui : aucun champ, aucun contrôle (clôture en espèces acceptée, comme 4.14.0)', () => avecVraiHttp(() async {
          d62.d62 = false;
          final id = await prevente();
          d62.payeeALaBorne(id);
          expect(PreventePayee.depuisVente((await gw.fullSale(id)).valueOrNull), isNull);
          expect((await gw.preventes()).valueOrNull!.single.paiementMobile, isNull);
          final net = (await gw.netVno(id)).valueOrNull!;
          expect((await gw.cloturerVno(venteId: id, summary: net, typeReglementId: '1', clientId: '', userVendeurId: 'U-FICT')).isOk, isTrue);
        }));

    test('confidentialité : le numéro de transaction du paiement ne repart jamais vers le serveur', () => avecVraiHttp(() async {
          final id = await prevente();
          d62.payeeALaBorne(id);
          await gw.fullSale(id);
          for (final r in srv.recues) {
            expect(r.corps, isNot(contains('TX-FICT')), reason: 'le numéro de transaction ne repart jamais vers le serveur');
          }
        }));
  });
}
