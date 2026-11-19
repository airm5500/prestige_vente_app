// RÉSEAU — 4.15.1 : réponse du serveur à la demande 63 en VRAI HTTP (faux serveur Prestige sur un port local),
// données FICTIVES :
//  - route image lente (PNG gris attendu puis converti), coupée, tronquée : jamais d'exception ; après une réponse
//    JSON de la route (même 200 {success:false}), une coupure réseau ne recompose pas de ticket local ;
//  - vente/remise "0" dont la réponse est tronquée : remise relue (vide) = sans remise appliquée, net relu ;
//  - vente/remise avec `data` dont la réponse est tronquée : jamais affichée sans confirmation (relue).
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/droits/droits_vente.dart';
import 'package:prestige_vente_app/services/impression_ticket.dart';
import 'package:prestige_vente_app/services/ticket_serveur.dart';
import 'package:prestige_vente_app/ventes/common/remise_vente.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../outils/clients_vente_fictifs.dart';
import '../outils/demande63_fictive.dart';
import '../outils/faux_serveur_prestige.dart';
import '../outils/remises_fictives.dart';

const _remise = RemiseOption(id: 'REM-FICT-10', nom: 'REMISE FICTIVE 10 %');

void main() {
  late FauxServeurPrestige srv;
  late RemisesFictives rf;
  late Demande63Fictive d63;
  late ApiService api;

  setUp(() => avecVraiHttp(() async {
        SharedPreferences.setMockInitialValues({});
        srv = FauxServeurPrestige();
        ClientsVenteFictifs(srv);
        rf = RemisesFictives(srv);
        d63 = Demande63Fictive(srv, rf);
        srv.droitsComptes = {DonneesFictives.login: ['P_SM_VENTE', 'P_SM_CLOTURER_CAISSE', droitRemise]};
        TicketServeur.oublier();
        DroitsVente.instance.oublier();
        DroitsVente.instance.oublierControles();
        await srv.demarrer();
        await DioClient.cookieJar.deleteAll();
        api = ApiService(baseUrl: srv.base);
        expect(await api.login(DonneesFictives.login, DonneesFictives.motDePasse), isNotNull);
        await DroitsVente.instance.actualiser(api.dio, utilisateur: DonneesFictives.login);
      }));
  tearDown(() => avecVraiHttp(() async {
        await srv.arreter();
        await DioClient.cookieJar.deleteAll();
      }));

  Future<(VenteController, String)> venteOuverte() async {
    final gw = DioVenteGateway(api);
    final c = VenteController(gateway: gw);
    final p = (await gw.searchProducts('PRODUIT')).valueOrNull!.first;
    expect((await c.addProduct(p, 2)).isOk, isTrue);
    return (c, c.venteId!);
  }

  test('route image lente : PNG gris attendu (20 s) puis converti en 1 bit', () => avecVraiHttp(() async {
        final (_, id) = await venteOuverte();
        srv.statutVentes[id] = 'is_Closed';
        final avant = srv.routes['GET /image']!;
        srv.routes['GET /image'] = (r) async {
          final x = await avant(r);
          return ReponseLocale(x.corps, delai: const Duration(milliseconds: 1500));
        };
        final r = await TicketServeur.lire(api.dio, type: TypeTicketServeur.vno, id: id, largeur: 58) as TicketsServeur;
        expect(ImpressionTicket.rasters(r.tickets, 384)!.single.largeur, 384);
      }));

  test('route image tronquée ou serveur coupé : jamais d\'exception ; route vue (200 success:false) puis coupure → pas de ticket local', () => avecVraiHttp(() async {
        final (_, id) = await venteOuverte();
        expect(await TicketServeur.lire(api.dio, type: TypeTicketServeur.vno, id: id, largeur: 58), isA<TicketRefuseVente>());
        expect(TicketServeur.etat(api.dio.options.baseUrl), EtatRouteTicket.presente);
        srv.routes['GET /image'] = (_) => const ReponseLocale('{"success":tr', entetes: {'content-type': 'application/json; charset=utf-8'});
        expect(await TicketServeur.lire(api.dio, type: TypeTicketServeur.vno, id: id, largeur: 58), isA<TicketRefuse>());
        await srv.arreter();
        expect(await TicketServeur.lire(api.dio, type: TypeTicketServeur.vno, id: id, largeur: 58), isA<TicketReseauIndisponible>());
        expect(TicketServeur.etat(api.dio.options.baseUrl), EtatRouteTicket.presente, reason: '« Ticket non imprimé : réseau indisponible »');
      }));

  test('« Retirer » ("0") dont la réponse est tronquée : remise relue vide = sans remise, net relu', () => avecVraiHttp(() async {
        final (c, id) = await venteOuverte();
        final x = await c.choisirRemise(_remise);
        expect(x.isOk, isTrue, reason: x.message);
        expect(c.montantRemise, greaterThan(0));
        d63.couperReponsePose = true;
        final r = await c.retirerRemise();
        expect(r.isOk, isTrue, reason: 'appliquée sur le serveur : relue');
        expect(d63.lgRemise[id], '0');
        expect(c.remiseId, isNull);
        expect(c.montantRemise, 0);
      }));

  test('remise avec `data` tronquée : relue sur le serveur avant d\'être affichée', () => avecVraiHttp(() async {
        final (c, id) = await venteOuverte();
        d63.couperReponsePose = true;
        final r = await c.choisirRemise(_remise);
        expect(r.isOk, isTrue);
        expect(c.remiseId, 'REM-FICT-10');
        expect(rf.remiseDeVente[id], 'REM-FICT-10');
        expect(c.montantRemise, greaterThan(0), reason: 'net relu par net/vno (data perdu)');
      }));
}
