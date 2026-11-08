// RÉSEAU — Prestige Mobile 4.11.0, plan du pharmacien du 08/11, en VRAI HTTP (faux serveur Prestige sur un port local) :
//  - réception (demande 59) : capacité `clotureRecu` de GET v1/reception/parametres (vraie, absente, route 404 d'un
//    serveur ancien, serveur coupé → chemin désactivé) ; PUT v1/commande/validerbl/{id}?mode=RECU (paramètre exact,
//    écarts lus) ; la clôture classique reste sans paramètre ;
//  - commandes : int_LINE lu tel que le serveur l'envoie ;
//  - réserve (demande 60) : `voirSuggestions` de GET v1/reserve/droits (vrai, faux, absent) lu avec la session ;
//    recherche de la saisie rapide (GET v1/reserve/articles?search_value=) ; création avec la catégorie du sens.
// Données FICTIVES.
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/droits/droits_modules.dart';
import 'package:prestige_vente_app/reception/reception_gateway.dart';
import 'package:prestige_vente_app/reserve/reserve_api.dart';
import 'package:prestige_vente_app/reserve/reserve_models.dart';
import 'package:prestige_vente_app/serveur/client_prestige.dart';

import '../outils/faux_serveur_prestige.dart';

void main() {
  late FauxServeurPrestige srv;
  setUp(() => avecVraiHttp(() async {
        srv = FauxServeurPrestige();
        await srv.demarrer();
        await DioClient.cookieJar.deleteAll();
        expect(await ApiService(baseUrl: srv.base).login(DonneesFictives.login, DonneesFictives.motDePasse), isNotNull);
      }));
  tearDown(() => avecVraiHttp(() async {
        await srv.arreter();
        await DioClient.cookieJar.deleteAll();
      }));

  // Client de l'application (pot à cookies de la session).
  DioReceptionGateway gw() => DioReceptionGateway(DioClient.getClient(srv.base));

  test('réception : capacité clotureRecu (vraie / absente / 404 / serveur coupé)', () => avecVraiHttp(() async {
        expect(await gw().clotureRecuDisponible(), isFalse, reason: 'serveur ancien : route absente');
        srv.routes['GET /reception/parametres'] = (_) => FauxServeurPrestige.ok({'success': true, 'peremptionObligatoire': false});
        expect(await gw().clotureRecuDisponible(), isFalse, reason: 'champ absent');
        srv.routes['GET /reception/parametres'] = (_) => FauxServeurPrestige.ok({'success': true, 'clotureRecu': true});
        expect(await gw().clotureRecuDisponible(), isTrue);
        await srv.couper();
        expect(await gw().clotureRecuDisponible(), isFalse, reason: 'injoignable : jamais d\'entrée d\'un BL incomplet');
        await srv.retablir();
      }));

  test('réception : PUT validerbl?mode=RECU, écarts lus ; clôture classique inchangée (sans paramètre)', () => avecVraiHttp(() async {
        srv.routes['PUT /commande/validerbl/BL9'] = (r) => FauxServeurPrestige.ok(r.query['mode'] == 'RECU'
            ? {
                'success': true,
                'msg': 'BL entré avec écart',
                'ecarts': [
                  {'detailId': 'D1', 'cip': '3595583', 'nom': 'PRODUIT FICTIF', 'commande': 10, 'recu': 7, 'ug': 0, 'manquant': 3}
                ],
                'totalManquant': 3
              }
            : {'success': true, 'msg': 'Opération effectuée'});
        final r = await gw().validateRecu('BL9');
        expect(r.success, isTrue);
        expect(srv.recues.last.query, {'mode': 'RECU'});
        final e = ecartsDe(r).single;
        expect((e.nom, e.commande, e.recu, e.manquant), ('PRODUIT FICTIF', 10, 7, 3));
        final c = await gw().validate('BL9');
        expect(c.success, isTrue);
        expect(srv.recues.last.query, isEmpty, reason: 'clôture classique : comportement d\'avant');
      }));

  test('commandes : int_LINE lu (nombre de lignes), quantité gardée à part', () => avecVraiHttp(() async {
        srv.routes['GET /commande/list'] = (_) => FauxServeurPrestige.ok({
              'data': [
                {'lg_ORDER_ID': 'O1', 'str_REF_ORDER': 'CMD-R', 'int_NBRE_PRODUIT': 48, 'int_LINE': 3, 'str_STATUT': 'is_Process'}
              ],
              'total': 1
            });
        srv.routes['GET /commande/list/passees'] = (_) => FauxServeurPrestige.ok({'data': [], 'total': 0});
        final o = (await gw().orders()).single;
        expect((o.lines, o.products, o.linesLabel), (3, 48, 'lignes'));
      }));

  test('réserve : voirSuggestions vrai / faux / absent, lu avec la session', () => avecVraiHttp(() async {
        final client = ClientPrestige(() => srv.base, delaiReponse: const Duration(seconds: 2));
        final d = DroitsModules();
        for (final (corps, attendu) in [
          ({'success': true, 'traiter': true, 'voirSuggestions': false}, false),
          ({'success': true, 'traiter': true, 'voirSuggestions': true}, true),
          ({'success': true, 'traiter': true}, true),
        ]) {
          srv.routes['GET /reserve/droits'] = (_) => FauxServeurPrestige.ok(corps);
          await d.actualiser(client, utilisateur: DonneesFictives.login, adminLocal: false, forcer: true);
          expect(d.reserveSuggestions, attendu, reason: '$corps');
          expect(srv.recuesSur('/reserve/droits').last.cookie, contains('JSESSIONID'));
        }
      }));

  test('réserve : recherche de la saisie rapide et création avec la catégorie du sens', () => avecVraiHttp(() async {
        srv.routes['GET /reserve/articles'] = (r) => FauxServeurPrestige.ok({
              'results': [
                {'lg_FAMILLE_ID': 'FR1', 'int_CIP': r.query['search_value'], 'str_NAME': 'PRODUIT FICTIF', 'int_STOCK_RAYON': 1, 'int_STOCK_RESERVE': 5}
              ],
              'total': 1
            });
        srv.routes['POST /suggestion-reserve/creer'] =
            (_) => FauxServeurPrestige.ok({'success': true, 'lg_SUGGESTION_RESERVE_ID': 'N1', 'str_REF': 'SR-RAY-R', 'lignes': 1, 'ignorees': 0});
        final api = ReserveApi(ClientPrestige(() => srv.base, delaiReponse: const Duration(seconds: 2)));
        final a = (await api.articles('3595583', limit: 30)).articles.single;
        final q = srv.recuesSur('/reserve/articles').last.query;
        expect(q['search_value'], '3595583');
        expect(q['limit'], '30');
        for (final sens in SensReserve.values) {
          final r = await api.creer(sens, 1, '', [LignePanier(a, 2)]);
          expect(r.ref, 'SR-RAY-R');
          expect(srv.recuesSur('/suggestion-reserve/creer').last.json,
              {'categorie': sens.categorieApi, 'motifId': 1, 'commentaire': null, 'items': [{'lg_FAMILLE_ID': 'FR1', 'int_QTE': 2}]});
        }
      }));
}
