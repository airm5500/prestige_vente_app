// INTÉGRATION — 4.13.0 : passerelle de la vente comptant (DioVenteGateway, client HTTP de l'application) contre le
// faux serveur Prestige en VRAI HTTP (session ouverte par la connexion), données FICTIVES. Les trois routes et leurs
// refus, avec les règles du serveur réel :
//  - GET v1/client/lambda?query= (texte tel que tapé, espaces de bord retirés) ;
//  - POST v1/client/add/lambda {strFIRSTNAME, strLASTNAME, strADRESSE, lgTYPECLIENTID:"6"} ; refus → msg tel quel ;
//  - POST v1/vente/update/client {venteId, clientId} ; clientId null = retrait ; « Client inconnu » (success:true)
//    = refus (rien n'a changé) ; vente terminée → msg ;
//  - clôture : clientId = client rattaché, ou null (jamais le nom du mode) ;
//  - 403 interdit → refus de droit (code interdit) ; 409 sessionChangee → échec sans effet.
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';

import 'outils/clients_vente_fictifs.dart';
import 'outils/faux_serveur_prestige.dart';

void main() {
  late FauxServeurPrestige srv;
  late ClientsVenteFictifs cl;
  late DioVenteGateway gw;

  setUp(() => avecVraiHttp(() async {
        srv = FauxServeurPrestige();
        cl = ClientsVenteFictifs(srv);
        await srv.demarrer();
        await DioClient.cookieJar.deleteAll();
        final api = ApiService(baseUrl: srv.base);
        expect(await api.login(DonneesFictives.login, DonneesFictives.motDePasse), isNotNull);
        gw = DioVenteGateway(api);
      }));
  tearDown(() => avecVraiHttp(() async {
        await srv.arreter();
        await DioClient.cookieJar.deleteAll();
      }));

  Future<String> vente() async => (await gw.addItemVno(produitId: 'F1', qte: 1, itemPu: 1000, prevente: true)).valueOrNull!;

  test('recherche : GET client/lambda?query=, nom / prénom / téléphone lus', () => avecVraiHttp(() async {
        final r = await gw.rechercherClientsVente('  koffi-test ');
        expect(srv.recuesSur('/client/lambda').single.query, {'query': 'koffi-test'});
        expect(r.valueOrNull!.map((c) => (c.id, c.nomComplet, c.telephone)), [
          ('CL-FICT-1', 'KOFFI-TEST AMANI', '0700000001'),
          ('CL-FICT-2', 'KOFFI-TEST BINTOU', '0500000002'),
        ]);
        expect((await gw.rechercherClientsVente('0500')).valueOrNull!.single.id, 'CL-FICT-2', reason: 'numéro de la fiche');
        expect((await gw.rechercherClientsVente('INCONNU-ZZZ')).valueOrNull, isEmpty);
      }));

  test('création : corps du poste (type 6), nom en majuscules, trouvé ensuite ; refus → msg tel quel', () => avecVraiHttp(() async {
        final r = await gw.creerClientVente(nom: ' Nouveau-Fictif ', prenom: 'Essai', telephone: '0700009999');
        expect(cl.creations.single, {'strFIRSTNAME': 'Nouveau-Fictif', 'strLASTNAME': 'Essai', 'strADRESSE': '0700009999', 'lgTYPECLIENTID': '6'});
        expect((r.valueOrNull!.id, r.valueOrNull!.nomComplet), ('CL-CREE-1', 'NOUVEAU-FICTIF ESSAI'));
        expect((await gw.rechercherClientsVente('NOUVEAU')).valueOrNull!.single.id, 'CL-CREE-1');
        final vide = await gw.creerClientVente(nom: '', prenom: ' ', telephone: '07');
        expect(vide, isA<VenteRefused<ClientVente>>());
        expect(vide.message, 'Le nom ou le prénom du client est obligatoire.');
        final long = await gw.creerClientVente(nom: 'X' * 51, prenom: '', telephone: '');
        expect(long.message, 'Le nom ne doit pas dépasser 50 caractères.');
        expect(cl.clients.length, 4, reason: 'un seul client créé');
      }));

  test('rattachement, changement, retrait (clientId null), « Client inconnu », vente terminée', () => avecVraiHttp(() async {
        final id = await vente();
        expect((await gw.rattacherClientVente(id, 'CL-FICT-1')).isOk, isTrue);
        expect(srv.recuesSur('/vente/update/client').last.json, {'venteId': id, 'clientId': 'CL-FICT-1'});
        expect((await gw.rattacherClientVente(id, 'CL-FICT-2')).isOk, isTrue);
        expect(cl.clientDeVente[id], 'CL-FICT-2');
        final inconnu = await gw.rattacherClientVente(id, 'especes');
        expect(inconnu, isA<VenteRefused<void>>(), reason: 'success:true mais rien n\'a changé');
        expect(inconnu.message, 'Client inconnu : le client de la vente est inchangé.');
        expect(cl.clientDeVente[id], 'CL-FICT-2');
        expect((await gw.rattacherClientVente(id, null)).isOk, isTrue);
        expect(srv.recuesSur('/vente/update/client').last.json, {'venteId': id, 'clientId': null});
        expect(cl.clientDeVente.containsKey(id), isFalse);
        srv.statutVentes[id] = 'is_Closed';
        final fini = await gw.rattacherClientVente(id, 'CL-FICT-1');
        expect(fini.message, contains('déjà terminée'));
      }));

  test('relecture de la vente : champ client ; clôture avec le client rattaché, sinon null', () => avecVraiHttp(() async {
        final id = await vente();
        await gw.rattacherClientVente(id, 'CL-FICT-3');
        final lu = await gw.fullSale(id);
        expect(ClientVente.depuisJson(lu.valueOrNull!['client'])!.nomComplet, 'YAO-FICTIF CELESTE');
        final s = SaleSummary(montant: 1000, montantNet: 1000, venteId: id, reference: 'REF');
        expect((await gw.cloturerVno(venteId: id, summary: s, typeReglementId: '1', clientId: 'CL-FICT-3', userVendeurId: 'U1')).isOk, isTrue);
        expect(cl.clotures.last['clientId'], 'CL-FICT-3');
        final id2 = await vente();
        await gw.cloturerVno(venteId: id2, summary: s, typeReglementId: '10', clientId: '', userVendeurId: 'U1');
        expect(cl.clotures.last['clientId'], isNull);
        expect(cl.clientDeVente.containsKey(id2), isFalse);
        expect(cl.rattachements, hasLength(1), reason: 'aucun « client = mode » avant la clôture');
      }));

  test('403 interdit sur les trois routes : refus de droit avec le msg ; 409 : échec sans effet', () => avecVraiHttp(() async {
        final id = await vente();
        cl.forcerRecherche = (_) => ClientsVenteFictifs.interdit403;
        cl.forcerCreation = (_) => ClientsVenteFictifs.interdit403;
        cl.forcerRattachement = (_) => ClientsVenteFictifs.interdit403;
        for (final r in [
          await gw.rechercherClientsVente('KOFFI'),
          await gw.creerClientVente(nom: 'A', prenom: 'B', telephone: ''),
          await gw.rattacherClientVente(id, 'CL-FICT-1'),
        ]) {
          expect(r, isA<VenteRefused>());
          expect((r as VenteRefused).interdit, isTrue);
          expect(r.message, 'Vous n\'avez pas le droit d\'associer un client à une vente.');
        }
        cl.forcerRattachement = (_) => ClientsVenteFictifs.sessionChangee409;
        final r = await gw.rattacherClientVente(id, 'CL-FICT-1');
        expect(r, isA<VenteFailed<void>>());
        expect(r.uncertain, isFalse, reason: 'rien n\'a été exécuté');
        expect(cl.clientDeVente, isEmpty);
      }));
}
