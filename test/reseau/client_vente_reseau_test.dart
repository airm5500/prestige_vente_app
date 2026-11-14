// RÉSEAU — 4.13.0 : client d'une vente comptant en VRAI HTTP (faux serveur Prestige sur un port local, session par
// cookie), données FICTIVES. Les trois routes et leurs refus :
//  - GET v1/client/lambda : serveur lent (réponse attendue), réponse incomplète / illisible → échec (jamais « aucun
//    client »), serveur coupé → message « injoignable », 403 interdit, 409 sessionChangee, 401 session absente ;
//  - POST v1/client/add/lambda : refus msg, 403, coupé, réponse sans identifiant (création à vérifier) ;
//  - POST v1/vente/update/client : lent puis délai dépassé (peut-être appliqué → le contrôleur relit la vente),
//    tronqué, coupé, 403, 409, « Client inconnu » ; jamais de déconnexion sur 403.
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/serveur/panne_serveur.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../outils/clients_vente_fictifs.dart';
import '../outils/faux_serveur_prestige.dart';

/// Réponse incomplète (JSON coupé) : l'application ne sait pas si l'opération a été faite.
const _incomplet = ReponseLocale('{"success":tr', entetes: {'content-type': 'application/json; charset=utf-8'});

void main() {
  late FauxServeurPrestige srv;
  late ClientsVenteFictifs cl;
  late ApiService api;

  setUp(() => avecVraiHttp(() async {
        SharedPreferences.setMockInitialValues({});
        srv = FauxServeurPrestige();
        cl = ClientsVenteFictifs(srv);
        await srv.demarrer();
        await DioClient.cookieJar.deleteAll();
        api = ApiService(baseUrl: srv.base);
        expect(await api.login(DonneesFictives.login, DonneesFictives.motDePasse), isNotNull);
      }));
  tearDown(() => avecVraiHttp(() async {
        await srv.arreter();
        await DioClient.cookieJar.deleteAll();
      }));

  DioVenteGateway gw() => DioVenteGateway(api);
  Future<String> vente() async => (await gw().addItemVno(produitId: 'F1', qte: 1, itemPu: 1000, prevente: true)).valueOrNull!;

  test('recherche : lente (attendue), incomplète / illisible → échec, coupée → injoignable', () => avecVraiHttp(() async {
        cl.delaiRecherche = const Duration(milliseconds: 1500);
        final lente = await gw().rechercherClientsVente('KOFFI');
        expect(lente.valueOrNull, hasLength(2));
        cl.delaiRecherche = Duration.zero;
        cl.forcerRecherche = (_) => const ReponseLocale('{"success":true,"data":[{"lgCLIENTID":"CL-FICT-1","strFIRSTNA',
            entetes: {'content-type': 'application/json; charset=utf-8'});
        final tronquee = await gw().rechercherClientsVente('KOFFI');
        expect(tronquee.isOk, isFalse, reason: 'jamais « aucun client » sur une réponse incomplète');
        cl.forcerRecherche = (_) => const ReponseLocale({'success': true, 'data': 'pas une liste'});
        expect((await gw().rechercherClientsVente('KOFFI')).message, contains('Réponse inattendue'));
        cl.forcerRecherche = (_) => const ReponseLocale('<html>Erreur</html>', entetes: {'content-type': 'text/html'});
        expect((await gw().rechercherClientsVente('KOFFI')).isOk, isFalse);
        cl.forcerRecherche = null;
        await srv.couper();
        final coupee = await gw().rechercherClientsVente('KOFFI');
        expect(coupee.message, contains(MessagesServeur.injoignable));
        await srv.retablir();
        expect((await gw().rechercherClientsVente('KOFFI')).valueOrNull, hasLength(2));
      }));

  test('les trois routes : 403 interdit (session gardée), 409 sessionChangee, 401 session absente', () => avecVraiHttp(() async {
        final id = await vente();
        cl.forcerRecherche = (_) => ClientsVenteFictifs.interdit403;
        cl.forcerCreation = (_) => ClientsVenteFictifs.interdit403;
        cl.forcerRattachement = (_) => ClientsVenteFictifs.interdit403;
        final refus = [
          await gw().rechercherClientsVente('KOFFI'),
          await gw().creerClientVente(nom: 'A', prenom: 'B', telephone: ''),
          await gw().rattacherClientVente(id, 'CL-FICT-1'),
          await gw().rattacherClientVente(id, null),
        ];
        for (final r in refus) {
          expect((r as VenteRefused).interdit, isTrue);
        }
        expect(srv.connexions, 1, reason: 'aucune déconnexion / reconnexion');
        expect((await gw().saleDetails(id)).isOk, isTrue, reason: 'session toujours valide après un 403');
        cl.forcerRecherche = (_) => ClientsVenteFictifs.sessionChangee409;
        cl.forcerCreation = (_) => ClientsVenteFictifs.sessionChangee409;
        cl.forcerRattachement = (_) => ClientsVenteFictifs.sessionChangee409;
        for (final r in [
          await gw().rechercherClientsVente('KOFFI'),
          await gw().creerClientVente(nom: 'A', prenom: 'B', telephone: ''),
          await gw().rattacherClientVente(id, 'CL-FICT-1'),
        ]) {
          expect(r, isA<VenteFailed>());
          expect(r.uncertain, isFalse);
          expect(r.message, contains('Un autre compte'));
        }
        cl.forcerRecherche = cl.forcerCreation = cl.forcerRattachement = null;
        await DioClient.cookieJar.deleteAll(); // session perdue
        final r401 = await gw().rechercherClientsVente('KOFFI');
        expect(r401.isOk, isFalse);
        expect(cl.clientDeVente, isEmpty);
        expect(cl.clients, hasLength(3), reason: 'aucun client créé');
      }));

  test('création : refus msg, coupée, réponse sans identifiant → à vérifier (jamais un 2e client à l\'aveugle)', () => avecVraiHttp(() async {
        expect((await gw().creerClientVente(nom: '', prenom: '', telephone: '')).message, 'Le nom ou le prénom du client est obligatoire.');
        cl.forcerCreation = (_) => const ReponseLocale({'success': true, 'data': {}});
        final sansId = await gw().creerClientVente(nom: 'SANS-ID', prenom: '', telephone: '');
        expect(sansId.uncertain, isTrue);
        cl.forcerCreation = null;
        await srv.couper();
        final c = await gw().creerClientVente(nom: 'COUPE', prenom: '', telephone: '');
        expect(c.message, contains(MessagesServeur.injoignable));
        expect(c.uncertain, isFalse, reason: 'connexion refusée : rien n\'est parti');
        await srv.retablir();
      }));

  test('rattachement : lent, réponse incomplète (peut-être appliqué → relu), coupé, « Client inconnu »', () => avecVraiHttp(() async {
        final c = VenteController(gateway: gw());
        expect((await c.addProduct(ProductSearchResult(lgFAMILLEID: 'F1', strNAME: 'PRODUIT FICTIF', intCIP: '1', intPRICE: 1000, intNUMBERAVAILABLE: 9, strLIBELLEE: '', intPAF: 0), 1)).isOk, isTrue);
        final id = c.venteId!;
        cl.delaiRattachement = const Duration(milliseconds: 1500);
        expect((await c.choisirClient(const ClientVente(id: 'CL-FICT-1', nom: 'KOFFI-TEST', prenom: 'AMANI'))).isOk, isTrue);
        cl.delaiRattachement = Duration.zero;
        // Réponse incomplète APRÈS application : le contrôleur relit la vente et constate le client.
        cl.forcerRattachement = (r) {
          cl.clientDeVente[id] = 'CL-FICT-2';
          return _incomplet;
        };
        final perdu = await c.choisirClient(const ClientVente(id: 'CL-FICT-2', nom: 'KOFFI-TEST', prenom: 'BINTOU'));
        expect(perdu.isOk, isTrue, reason: perdu.message);
        expect(c.client?.id, 'CL-FICT-2');
        expect(c.client?.prenom, 'BINTOU', reason: 'relu sur la vente');
        // Réponse incomplète, rien appliqué : relecture → client d'avant gardé, message.
        cl.forcerRattachement = (_) => _incomplet;
        final pasApplique = await c.choisirClient(const ClientVente(id: 'CL-FICT-3', nom: 'YAO-FICTIF', prenom: 'CELESTE'));
        expect(pasApplique.isOk, isFalse);
        expect(c.client?.id, 'CL-FICT-2');
        cl.forcerRattachement = null;
        await srv.couper();
        final coupe = await c.retirerClient();
        expect(coupe.message, contains(MessagesServeur.injoignable));
        expect(c.client?.id, 'CL-FICT-2');
        await srv.retablir();
        final inconnu = await gw().rattacherClientVente(id, 'wave');
        expect(inconnu.message, 'Client inconnu : le client de la vente est inchangé.');
        expect(cl.clientDeVente[id], 'CL-FICT-2');
        expect((await c.retirerClient()).isOk, isTrue);
        expect(cl.clientDeVente.containsKey(id), isFalse);
      }));
}
