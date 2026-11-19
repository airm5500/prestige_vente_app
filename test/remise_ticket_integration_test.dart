// INTÉGRATION — 4.14.0 : remise (DioVenteGateway) et route image du ticket (TicketServeur) contre le faux serveur
// Prestige en VRAI HTTP (session de la connexion), données FICTIVES, règles du serveur réel (f0282bf0) :
//  - GET v1/common/remises-client : « SANS REMISE » (id null) écartée ;
//  - POST v1/vente/remise {venteId, remiseId} ; null = retrait ; vente inconnue → success:false (msg tel quel) ;
//  - POST v1/vente/net/vno {venteId, remiseId, checkUg:false} : remise du serveur ; sans remiseId → remise effacée ;
//  - GET v1/vente/ticket/{type}/{id}/image?largeur=&dpi=203 : 404 aujourd'hui ; contrat de la demande du 19/11 sinon.
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/services/ticket_serveur.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';

import 'outils/clients_vente_fictifs.dart';
import 'outils/faux_serveur_prestige.dart';
import 'outils/remises_fictives.dart';

void main() {
  late FauxServeurPrestige srv;
  late RemisesFictives rf;
  late ApiService api;
  late DioVenteGateway gw;

  setUp(() => avecVraiHttp(() async {
        srv = FauxServeurPrestige();
        ClientsVenteFictifs(srv);
        rf = RemisesFictives(srv);
        TicketServeur.oublier();
        await srv.demarrer();
        await DioClient.cookieJar.deleteAll();
        api = ApiService(baseUrl: srv.base);
        expect(await api.login(DonneesFictives.login, DonneesFictives.motDePasse), isNotNull);
        gw = DioVenteGateway(api);
      }));
  tearDown(() => avecVraiHttp(() async {
        await srv.arreter();
        await DioClient.cookieJar.deleteAll();
      }));

  Future<String> vente() async => (await gw.addItemVno(produitId: 'F1', qte: 4, itemPu: 2500, prevente: true)).valueOrNull!;

  test('liste : mêmes choix que le web, « SANS REMISE » écartée', () => avecVraiHttp(() async {
        final l = (await gw.remisesVente()).valueOrNull!;
        expect(l.map((r) => (r.id, r.nom)), [('REM-FICT-10', 'REMISE FICTIVE 10 %'), ('REM-FICT-5', 'REMISE FICTIVE 5 %')]);
        expect(srv.recuesSur('/common/remises-client').single.methode, 'GET');
      }));

  test('appliquer puis net : corps du web, montants du serveur ; retirer : remise null, net sans remise', () => avecVraiHttp(() async {
        final id = await vente();
        expect((await gw.appliquerRemise(id, 'REM-FICT-10')).isOk, isTrue);
        expect(srv.recuesSur('/vente/remise').single.json, {'remiseId': 'REM-FICT-10', 'venteId': id});
        final net = (await gw.netVnoRemise(id, 'REM-FICT-10')).valueOrNull!;
        expect((net.montant, net.remise, net.montantNet), (10000, 1000, 9000));
        expect(rf.netsVno.last, {'remiseId': 'REM-FICT-10', 'venteId': id, 'checkUg': false});
        // Calcul SANS remiseId (ancien appel) : le serveur efface la remise (VC-06) — d'où l'envoi systématique.
        expect((await gw.netVno(id)).valueOrNull!.remise, 0);
        expect((await gw.appliquerRemise(id, null)).isOk, isTrue);
        expect(srv.recuesSur('/vente/remise').last.json, {'remiseId': null, 'venteId': id});
        expect((await gw.netVnoRemise(id, null)).valueOrNull!.remise, 0);
      }));

  test('refus : vente inconnue (success:false) → msg tel quel ; 403 interdit → refus de droit', () => avecVraiHttp(() async {
        final r = await gw.appliquerRemise('V-INCONNUE', 'REM-FICT-10');
        expect(r, isA<VenteRefused<void>>());
        expect(r.message, 'Erreur::: L\'Opération n\'a pas aboutie');
        rf.forcerPose = (_) => const ReponseLocale({'success': false, 'interdit': true, 'msg': 'Accès refusé (droit fictif).'}, statut: 403);
        final i = await gw.appliquerRemise(await vente(), 'REM-FICT-10');
        expect((i as VenteRefused).interdit, isTrue);
        expect(i.message, 'Accès refusé (droit fictif).');
      }));

  test('route image absente (serveur d\'aujourd\'hui) : 404 → gabarit local', () => avecVraiHttp(() async {
        final id = await vente();
        expect(await TicketServeur.lire(api.dio, type: TypeTicketServeur.vno, id: id, largeur: 58), isA<RouteTicketAbsente>());
        expect(TicketServeur.etat(api.dio.options.baseUrl), EtatRouteTicket.absente);
      }));

  test('route image présente : chemin, paramètres, PNG 384 / 576 points', () => avecVraiHttp(() async {
        rf.routeImage = true;
        final id = await vente();
        final r58 = await TicketServeur.lire(api.dio, type: TypeTicketServeur.vno, id: id, largeur: 58);
        expect((r58 as TicketsServeur).tickets.single.largeurPoints, 384);
        final r80 = await TicketServeur.lire(api.dio, type: TypeTicketServeur.prevente, id: id, largeur: 80);
        expect((r80 as TicketsServeur).tickets.single.largeurPoints, 576);
        expect(rf.images, ['vno $id 58', 'prevente $id 80']);
        expect(srv.recuesSur('/image').first.query, {'largeur': '58', 'dpi': '203'});
        rf.ticketsParImage = 3;
        expect(((await TicketServeur.lire(api.dio, type: TypeTicketServeur.vo, id: id, largeur: 58)) as TicketsServeur).tickets, hasLength(3));
      }));

  test('aucun appel aux routes qui impriment sur l\'imprimante du serveur (POST ticket/vno, ticket/vo)', () => avecVraiHttp(() async {
        rf.routeImage = true;
        final id = await vente();
        await TicketServeur.lire(api.dio, type: TypeTicketServeur.vo, id: id, largeur: 58);
        expect(srv.recues.where((r) => r.methode == 'POST' && RegExp(r'/vente/ticket/(vno|vo)$').hasMatch(r.chemin)), isEmpty);
      }));
}
