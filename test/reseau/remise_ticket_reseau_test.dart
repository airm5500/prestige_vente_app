// RÉSEAU — 4.14.0 : remise et route image du ticket en VRAI HTTP (faux serveur Prestige sur un port local), données
// FICTIVES : serveur lent (réponse attendue), réponse tronquée (peut-être appliquée → relue), serveur coupé
// (injoignable), 403 interdit sans déconnexion ; route image lente, coupée, tronquée → jamais d'exception.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/serveur/panne_serveur.dart';
import 'package:prestige_vente_app/services/ticket_serveur.dart';
import 'package:prestige_vente_app/ventes/common/remise_vente.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../outils/clients_vente_fictifs.dart';
import '../outils/faux_serveur_prestige.dart';
import '../outils/remises_fictives.dart';

const _incomplet = ReponseLocale('{"success":tr', entetes: {'content-type': 'application/json; charset=utf-8'});
final _imageJson = {
  'success': true,
  'largeur': 58,
  'tickets': [{'modele': 'VENTE', 'png': base64Encode(RemisesFictives.pngFictif(384, 20)), 'largeurPoints': 384, 'hauteurPoints': 20}],
};
const _remise = RemiseOption(id: 'REM-FICT-10', nom: 'REMISE FICTIVE 10 %');

void main() {
  late FauxServeurPrestige srv;
  late RemisesFictives rf;
  late ApiService api;

  setUp(() => avecVraiHttp(() async {
        SharedPreferences.setMockInitialValues({});
        srv = FauxServeurPrestige();
        ClientsVenteFictifs(srv);
        rf = RemisesFictives(srv);
        TicketServeur.oublier();
        await srv.demarrer();
        await DioClient.cookieJar.deleteAll();
        api = ApiService(baseUrl: srv.base);
        expect(await api.login(DonneesFictives.login, DonneesFictives.motDePasse), isNotNull);
      }));
  tearDown(() => avecVraiHttp(() async {
        await srv.arreter();
        await DioClient.cookieJar.deleteAll();
      }));

  Future<VenteController> venteOuverte() async {
    final c = VenteController(gateway: DioVenteGateway(api));
    final p = (await DioVenteGateway(api).searchProducts('PRODUIT')).valueOrNull!.first;
    expect((await c.addProduct(p, 2)).isOk, isTrue);
    return c;
  }

  test('remise : serveur lent → appliquée après la réponse ; net relu avec la remise', () => avecVraiHttp(() async {
        final c = await venteOuverte();
        rf.delaiPose = const Duration(milliseconds: 1500);
        expect((await c.choisirRemise(_remise)).isOk, isTrue);
        expect(c.remiseId, 'REM-FICT-10');
        expect(c.montantRemise, greaterThan(0));
        expect(rf.netsVno.last['remiseId'], 'REM-FICT-10');
      }));

  test('remise : réponse tronquée → relue sur le serveur (appliquée) ; coupé → injoignable, rien affiché', () => avecVraiHttp(() async {
        final c = await venteOuverte();
        rf.forcerPose = (r) {
          rf.remiseDeVente['${r.json['venteId']}'] = '${r.json['remiseId']}';
          return _incomplet;
        };
        final r = await c.choisirRemise(_remise);
        expect(r.isOk, isTrue, reason: 'appliquée, vérifiée par GET ventestats');
        expect(c.remiseId, 'REM-FICT-10');
        rf.forcerPose = null;
        await srv.arreter();
        final coupe = await c.retirerRemise();
        expect(coupe.isOk, isFalse);
        expect(coupe.message, contains(MessagesServeur.injoignable));
        expect(c.remiseId, 'REM-FICT-10', reason: 'rien changé sans confirmation');
      }));

  test('remise : 403 interdit → refus de droit, session gardée', () => avecVraiHttp(() async {
        final c = await venteOuverte();
        rf.forcerPose = (_) => const ReponseLocale({'success': false, 'interdit': true, 'msg': 'Accès refusé (droit fictif).'}, statut: 403);
        final r = await c.choisirRemise(_remise);
        expect((r as VenteRefused).interdit, isTrue);
        expect((await DioVenteGateway(api).remisesVente()).isOk, isTrue, reason: 'toujours connecté');
      }));

  test('route image : lente (attendue), tronquée → refus (gabarit local), coupée → réseau indisponible', () => avecVraiHttp(() async {
        rf.routeImage = true;
        final d = api.dio;
        rf.forcerImage = (_) => ReponseLocale(_imageJson, delai: const Duration(milliseconds: 1500));
        expect(await TicketServeur.lire(d, type: TypeTicketServeur.vno, id: 'V-1', largeur: 58), isA<TicketsServeur>());
        rf.forcerImage = (_) => _incomplet;
        expect(await TicketServeur.lire(d, type: TypeTicketServeur.vno, id: 'V-1', largeur: 58), isA<TicketRefuse>());
        rf.forcerImage = null;
        await srv.arreter();
        expect(await TicketServeur.lire(d, type: TypeTicketServeur.vno, id: 'V-1', largeur: 58), isA<TicketReseauIndisponible>());
      }));
}
