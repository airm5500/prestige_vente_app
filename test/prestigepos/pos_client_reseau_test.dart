// PrestigePOS 1.11.0 — RÉSEAU / INTÉGRATION en VRAI HTTP (faux serveur Prestige sur un port local, session de
// l'utilisateur borne), données FICTIVES : service de la borne (BorneService sur DioVenteGateway) et client de la
// vente :
//  - prévente avec client : add/vno → update/client {venteId, clientId} → net → terminerprevente ;
//  - rattachement 403 interdit, 409 sessionChangee, serveur lent : la prévente est créée, le refus est gardé ;
//  - « Client inconnu » (success:true) : refus (nom jamais annoncé comme associé) ;
//  - recherche / création de la borne : 403 → message, réponse illisible → erreur (jamais « aucun client »).
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/borne/borne_client.dart';
import 'package:prestige_vente_app/borne/borne_panier.dart';
import 'package:prestige_vente_app/borne/borne_produit.dart';
import 'package:prestige_vente_app/borne/borne_service.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';

import '../outils/clients_vente_fictifs.dart';
import '../outils/faux_serveur_prestige.dart';

final _ligne = BorneLigne(
    BorneProduit(ProductSearchResult(lgFAMILLEID: 'F1', strNAME: 'PRODUIT FICTIF', intCIP: '3400930000001', intPRICE: 1500, intNUMBERAVAILABLE: 9, strLIBELLEE: '', intPAF: 0)),
    1);
const _a = ClientVente(id: 'CL-FICT-1', nom: 'KOFFI-TEST', prenom: 'AMANI');

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

  String route(RequeteRecue r) => '${r.methode} ${r.chemin.replaceFirst(RegExp(r'^.*/api/v1'), '').replaceAll(RegExp(r'V-\d+'), '{id}')}';

  test('prévente avec client : rattaché AVANT terminerprevente, corps {venteId, clientId}', () => avecVraiHttp(() async {
        final p = (await BorneService(gw, nouvelleCle: () => 'BORNE-K1').creerPrevente([_ligne], client: _a)).valueOrNull!;
        expect(p.clientAssocie, isTrue);
        final routes = [for (final r in srv.recues) route(r)].where((r) => !r.contains('/user/') && !r.contains('capacites')).toList();
        expect(routes, containsAllInOrder(['POST /vente/add/vno', 'POST /vente/update/client', 'POST /vente/net/vno', 'PUT /vente/terminerprevente/{id}']));
        expect(srv.recuesSur('/vente/update/client').single.json, {'venteId': p.venteId, 'clientId': 'CL-FICT-1'});
        expect(cl.clientDeVente[p.venteId], 'CL-FICT-1');
      }));

  test('rattachement 403, 409, « Client inconnu » : prévente créée, refus gardé, rien d\'associé', () => avecVraiHttp(() async {
        final s = BorneService(gw, nouvelleCle: () => 'BORNE-K2');
        for (final (rep, attendu) in [
          (ClientsVenteFictifs.interdit403, 'pas le droit'),
          (ClientsVenteFictifs.sessionChangee409, 'Un autre compte'),
        ]) {
          cl.forcerRattachement = (_) => rep;
          final p = (await s.creerPrevente([_ligne], client: _a)).valueOrNull!;
          expect(p.clientAssocie, isFalse);
          expect(p.clientRefus, contains(attendu));
          expect(srv.statutVentes[p.venteId], 'is_Process', reason: 'prévente terminée');
        }
        cl.forcerRattachement = null;
        final p = (await s.creerPrevente([_ligne], client: const ClientVente(id: 'INCONNU', nom: 'X', prenom: ''))).valueOrNull!;
        expect(p.clientAssocie, isFalse);
        expect(p.clientRefus, contains('Client inconnu'));
        expect(cl.clientDeVente, isEmpty);
      }));

  test('rattachement lent : attendu, puis associé', () => avecVraiHttp(() async {
        cl.delaiRattachement = const Duration(milliseconds: 1500);
        final p = (await BorneService(gw, nouvelleCle: () => 'BORNE-K3').creerPrevente([_ligne], client: _a)).valueOrNull!;
        expect(p.clientAssocie, isTrue);
      }));

  test('recherche / création de la borne : 403 → message, réponse illisible → erreur, serveur coupé → injoignable', () => avecVraiHttp(() async {
        final e = BorneClientEtat(gw);
        await e.chercher('KOFFI');
        expect(e.resultats, hasLength(2));
        cl.forcerRecherche = (_) => ClientsVenteFictifs.interdit403;
        await e.chercher('KOFFI-TEST');
        expect(e.resultats, isNull);
        expect(e.erreur, contains('pas le droit'));
        cl.forcerRecherche = (_) => const ReponseLocale('{"success":true,"data":[{"lgCL', entetes: {'content-type': 'application/json'});
        await e.chercher('KOFFI-T');
        expect(e.resultats, isNull, reason: 'jamais « aucun client » sur une réponse illisible');
        expect(e.erreur, isNotNull);
        cl.forcerRecherche = null;
        cl.forcerCreation = (_) => ClientsVenteFictifs.interdit403;
        expect(await e.creer(nom: 'A', prenom: 'B', telephone: ''), isFalse);
        expect(e.erreur, contains('pas le droit'));
        cl.forcerCreation = null;
        await srv.couper();
        await e.chercher('YAO-F');
        expect(e.erreur, isNotNull);
        await srv.retablir();
        expect(srv.connexions, 1, reason: 'aucune déconnexion');
      }));
}
