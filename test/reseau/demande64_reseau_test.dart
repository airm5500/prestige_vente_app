// RÉSEAU — 4.15.2 : demande 64 en VRAI HTTP (faux serveur Prestige sur un port local), données FICTIVES :
//  - borne : refus « Paiement mobile money impossible » reçu lentement → refus (jamais pris pour une panne), aucune
//    autre demande ; réponse tronquée → panne (pas un refus), aucune demande cloturer:false ; serveur coupé : une
//    seule tentative ;
//  - comptoir : refus du verrou reçu lentement → message tel quel, panier relu inchangé ; serveur coupé pendant une
//    modification : panne réseau (jamais un verrou), panier relu après une réponse perdue.
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/paiements/paiements_mobile.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../outils/clients_vente_fictifs.dart';
import '../outils/demande62_fictive.dart';
import '../outils/demande64_fictive.dart';
import '../outils/faux_serveur_prestige.dart';

const _incomplet = ReponseLocale('{"success":fal', entetes: {'content-type': 'application/json; charset=utf-8'});

void main() {
  late FauxServeurPrestige srv;
  late Demande64Fictive d64;
  late ApiService api;
  late DioPaiementsMobileApi pm;

  setUp(() => avecVraiHttp(() async {
        SharedPreferences.setMockInitialValues({});
        srv = FauxServeurPrestige();
        ClientsVenteFictifs(srv);
        d64 = Demande64Fictive(srv);
        srv.droitsComptes = {DonneesFictives.login: ['P_SM_VENTE', droitBorne]};
        await srv.demarrer();
        await DioClient.cookieJar.deleteAll();
        api = ApiService(baseUrl: srv.base);
        expect(await api.login(DonneesFictives.login, DonneesFictives.motDePasse), isNotNull);
        pm = DioPaiementsMobileApi(() => api.dio);
      }));
  tearDown(() => avecVraiHttp(() async {
        await srv.arreter();
        await DioClient.cookieJar.deleteAll();
      }));

  test('borne : refus « caisse fermée » reçu lentement → refus lisible, aucune autre demande', () => avecVraiHttp(() async {
        final id = d64.d62.preventeDeLaBorne(payee: false);
        srv.latence = const Duration(milliseconds: 800);
        final a = AttentePaiement(pm);
        await a.demarrer(venteId: id, operateur: 'wave', cloturer: true);
        expect((a.refusAvantPaiement, a.erreur), (true, messageCaisseFermee));
        expect(d64.d62.creations, hasLength(1));
        expect(d64.d62.paiements, isEmpty);
        a.dispose();
      }));

  test('borne : réponse tronquée → panne (pas un refus), une seule demande, aucune demande cloturer:false', () => avecVraiHttp(() async {
        final id = d64.d62.preventeDeLaBorne(payee: false);
        final route = srv.routes['POST /paiements-mobile']!;
        var n = 0;
        srv.routes['POST /paiements-mobile'] = (r) async {
          n++;
          await route(r);
          return _incomplet;
        };
        final a = AttentePaiement(pm);
        await a.demarrer(venteId: id, operateur: 'wave', cloturer: true);
        expect((a.refusAvantPaiement, a.interdit, a.paiement), (false, false, null));
        expect(a.erreur, isNotNull);
        expect(n, 1);
        expect(d64.d62.creations.map((c) => c['cloturer']), [true]);
        a.dispose();
      }));

  test('borne : serveur coupé → panne, une seule tentative, rien de créé', () => avecVraiHttp(() async {
        final id = d64.d62.preventeDeLaBorne(payee: false);
        await srv.arreter();
        final a = AttentePaiement(pm);
        await a.demarrer(venteId: id, operateur: 'wave', cloturer: true);
        expect((a.refusAvantPaiement, a.interdit, a.paiement), (false, false, null));
        expect(a.erreur, contains('injoignable'));
        a.dispose();
      }));

  test('comptoir : refus du verrou reçu lentement → message tel quel, panier relu inchangé', () => avecVraiHttp(() async {
        final id = d64.d62.preventeDeLaBorne();
        final c = VenteController(gateway: DioVenteGateway(api));
        await c.loadVente(id);
        final avant = [for (final i in c.items) (i.lgPREENREGISTREMENTDETAILID, i.intQUANTITY)];
        srv.latence = const Duration(milliseconds: 800);
        final r = await c.updateLine(c.items.single, 3, 4125);
        expect(r.message, messagePayeWave4125);
        expect((r as VenteRefused).panierVerrouille, isTrue);
        expect([for (final i in c.items) (i.lgPREENREGISTREMENTDETAILID, i.intQUANTITY)], avant);
        final r2 = await c.removeLine(c.items.single);
        expect(r2.message, messagePayeWave4125);
        expect(c.items, hasLength(1));
        expect(srv.ventes[id]!.single['intQUANTITY'], 1);
      }));

  test('comptoir : réponse tronquée sur une modification → panne relue, jamais un verrou ; serveur coupé : panne', () => avecVraiHttp(() async {
        final id = d64.d62.preventeDeLaBorne(payee: false);
        final c = VenteController(gateway: DioVenteGateway(api));
        await c.loadVente(id);
        final ligne = c.items.single;
        srv.filtreAvantSession = (r) => r.chemin.endsWith('/vente/update/item/vno') ? _incomplet : null;
        final r = await c.updateLine(ligne, 2, 4125);
        expect(r.isOk, isFalse);
        expect(r is VenteRefused && r.panierVerrouille, isFalse);
        expect(c.items.single.intQUANTITY, 1, reason: 'panier relu : rien n\'a changé sur le serveur');
        await srv.arreter();
        final r2 = await c.removeLine(ligne);
        expect(r2, isA<VenteFailed<void>>());
        expect(c.items, hasLength(1));
      }));
}
