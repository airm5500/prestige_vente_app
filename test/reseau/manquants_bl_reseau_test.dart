// RÉSEAU — Prestige Mobile 4.12.0 (demandes 59 et 60 livrées par le serveur le 08/11), en VRAI HTTP (faux serveur
// Prestige sur un port local, session par cookie), formats relevés dans le code du serveur. Données FICTIVES.
//  - GET v1/reception/parametres : clotureRecu / retourManquants (vraies, absentes, route 404, serveur coupé) ; les
//    deux capacités lues ensemble = UNE requête ;
//  - PUT v1/commande/validerbl/{id}?mode=RECU : en-tête X-Client-Ref ; refus AUCUN_RECU (HTTP 200, success:false) ;
//    403 interdit → message du droit, session gardée ; `reserve: []` sans effet ;
//  - GET v1/reception/{blId}/ecarts : PROVISOIRE, RECU avec retour existant, 404 BL_INCONNU ;
//  - POST v1/reception/{blId}/retour-manquants : X-Client-Ref, création, deja:true, 409 BL_NON_ENTRE_AU_RECU,
//    409 AUCUN_MANQUANT, 404 BL_INCONNU, 403 interdit (jamais de déconnexion), serveur coupé ;
//  - 4.12.1 (serveur du 11/11) : retourManquants abandonné / refusé avec lignes et totalManquant, ou sans (serveur
//    ancien) ; POST après un abandon → deja:false (nouveau retour) ; deja:true de même forme que la création ;
//    deja:true d'un abandonné (serveur ancien) signalé ; X-Client-Ref transmise telle quelle à chaque appel ;
//  - demande 60 : 403 « Voir les suggestions de réserve » sur en-attente / ouvrir → ErreurHttp droit manquant, jamais
//    SessionExpiree, droit constaté ; « Traiter la réserve » ne retire pas les suggestions ; creer et motifs permis.
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/droits/droits_modules.dart';
import 'package:prestige_vente_app/reception/manquants_bl.dart';
import 'package:prestige_vente_app/reception/reception_gateway.dart';
import 'package:prestige_vente_app/reserve/reserve_api.dart';
import 'package:prestige_vente_app/reserve/reserve_models.dart';
import 'package:prestige_vente_app/serveur/client_prestige.dart';

import '../outils/faux_serveur_prestige.dart';

const _ligne = {'detailId': 'D1', 'cip': '3595583', 'nom': 'PRODUIT FICTIF', 'commande': 10, 'recu': 7, 'ug': 0, 'manquant': 3};
const _droitRetours = 'Droit manquant : Retours fournisseur';
const _droitVoir = 'Droit manquant : Voir les suggestions de réserve';

ReponseLocale _statut(int statut, String code, String msg) => ReponseLocale({'success': false, 'code': code, 'msg': msg}, statut: statut);

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
        DroitsModules.instance.oublier();
      }));

  // Client de l'application (pot à cookies de la session, intercepteur de session).
  DioReceptionGateway gw() => DioReceptionGateway(DioClient.getClient(srv.base));

  test('capacités clotureRecu / retourManquants : vraies, absentes, 404, coupé ; lues ensemble en UNE requête', () => avecVraiHttp(() async {
        expect(await gw().retourManquantsDisponible(), isFalse, reason: 'serveur ancien : route absente (404)');
        srv.routes['GET /reception/parametres'] = (_) => FauxServeurPrestige.ok({'success': true, 'clotureRecu': true});
        expect(await gw().retourManquantsDisponible(), isFalse, reason: 'champ absent');
        expect(await gw().clotureRecuDisponible(), isTrue);
        srv.routes['GET /reception/parametres'] = (_) => FauxServeurPrestige.ok({'success': true, 'clotureRecu': true, 'retourManquants': true});
        final g = gw();
        final avant = srv.recuesSur('/reception/parametres').length;
        final r = await Future.wait([g.clotureRecuDisponible(), g.retourManquantsDisponible()]);
        expect(r, [true, true]);
        expect(srv.recuesSur('/reception/parametres').length - avant, 1, reason: 'une seule lecture pour les deux capacités');
        expect(await g.retourManquantsDisponible(), isTrue, reason: 'relu ensuite (rien gardé)');
        await srv.couper();
        expect(await gw().retourManquantsDisponible(), isFalse);
        await srv.retablir();
      }));

  test('PUT validerbl?mode=RECU : X-Client-Ref, refus AUCUN_RECU (200), 403 sans déconnexion, reserve:[] sans effet', () => avecVraiHttp(() async {
        var reponse = const ReponseLocale({'success': false, 'code': 'AUCUN_RECU', 'msg': 'Aucune ligne de ce BL n\'a de lot'});
        srv.routes['PUT /commande/validerbl/BL9'] = (_) => reponse;
        final r = await gw().validateRecu('BL9', clientRef: 'BLR-fictif-1');
        final q = srv.recuesSur('/commande/validerbl/BL9').last;
        expect(q.query, {'mode': 'RECU'});
        expect(q.clientRef, 'BLR-fictif-1');
        expect(estAucunRecu(r), isTrue);
        expect(r.success, isFalse);

        reponse = const ReponseLocale({'success': true, 'mode': 'RECU', 'msg': 'BL entré avec écart', 'ecarts': [_ligne], 'totalManquant': 3, 'reserve': []});
        final ok = await gw().validateRecu('BL9', clientRef: 'BLR-fictif-1');
        expect(ok.success, isTrue);
        expect(lignesEcart(ok.data['ecarts']).single.manquant, 3);
        expect(totalManquantDe(ok.data, const []), 3);
        expect(ok.data['reserve'], isEmpty);

        reponse = FauxServeurPrestige.interdit('Droit manquant : Entrée en stock');
        final refus = await gw().validateRecu('BL9', clientRef: 'BLR-fictif-2');
        expect((refus.success, refus.message), (false, 'Droit manquant : Entrée en stock'));
        expect(srv.connexions, 1, reason: '403 interdit : jamais une reconnexion');

        // Sans clé (appel 4.11.0) : aucun en-tête.
        await gw().validateRecu('BL9');
        expect(srv.recuesSur('/commande/validerbl/BL9').last.clientRef, isEmpty);
      }));

  test('GET reception/{blId}/ecarts : PROVISOIRE, RECU avec retour existant, 404 BL_INCONNU', () => avecVraiHttp(() async {
        srv.routes['GET /reception/BL1/ecarts'] = (_) => FauxServeurPrestige.ok(
            {'success': true, 'blId': 'BL1', 'ref': 'BL-FICTIF', 'mode': 'PROVISOIRE', 'provisoire': true, 'ecarts': [_ligne], 'totalManquant': 3, 'retourManquants': null});
        final p = await gw().ecartsBl('BL1');
        expect((p.success, p.provisoire, p.totalManquant, p.retour), (true, true, 3, null));
        expect(srv.recuesSur('/reception/BL1/ecarts').last.cookie, contains('JSESSIONID'));

        srv.routes['GET /reception/BL1/ecarts'] = (_) => FauxServeurPrestige.ok({
              'success': true,
              'mode': 'RECU',
              'provisoire': false,
              'ecarts': [_ligne],
              'totalManquant': 3,
              'retourManquants': {'retourId': 'R1', 'ref': 'RF-0001', 'statut': 'is_Waiting'}
            });
        final e = await gw().ecartsBl('BL1');
        expect((e.entreAuRecu, e.retour?.ref), (true, 'RF-0001'));

        srv.routes['GET /reception/BL2/ecarts'] = (_) => _statut(404, 'BL_INCONNU', 'Ce BL n\'existe pas.');
        final i = await gw().ecartsBl('BL2');
        expect((i.success, i.code, i.message), (false, 'BL_INCONNU', 'Ce BL n\'existe pas.'));
      }));

  test('POST retour-manquants : X-Client-Ref, création, deja, 409, 404, 403 sans déconnexion, coupé', () => avecVraiHttp(() async {
        var reponse = FauxServeurPrestige.ok({
          'success': true,
          'deja': false,
          'retourId': 'R1',
          'ref': 'RF-0001',
          'statut': 'is_Waiting',
          'lignes': 1,
          'totalManquant': 3,
          'route': 'POST v1/reception/{blId}/retour-manquants',
          'msg': 'Retour des manquants RF-0001 créé'
        });
        srv.routes['POST /reception/BL1/retour-manquants'] = (_) => reponse;
        final c = await gw().creerRetourManquants('BL1', clientRef: 'BLM-fictif-1');
        final q = srv.recuesSur('/reception/BL1/retour-manquants').last;
        expect(q.clientRef, 'BLM-fictif-1');
        expect(q.cookie, contains('JSESSIONID'));
        expect((c.success, c.deja, c.ref, c.lignes, c.totalManquant), (true, false, 'RF-0001', 1, 3));

        reponse = FauxServeurPrestige.ok(
            {'success': true, 'deja': true, 'retourId': 'R1', 'ref': 'RF-0001', 'statut': 'is_Waiting', 'route': '…', 'msg': 'existe déjà'});
        final d = await gw().creerRetourManquants('BL1', clientRef: 'BLM-fictif-2');
        expect(d.texte, 'Retour RF-0001 déjà créé (en attente de validation).');

        for (final (statut, code) in [(409, 'BL_NON_ENTRE_AU_RECU'), (409, 'AUCUN_MANQUANT'), (404, 'BL_INCONNU')]) {
          reponse = _statut(statut, code, 'message serveur');
          final r = await gw().creerRetourManquants('BL1', clientRef: 'BLM-fictif-3');
          expect((r.success, r.code, r.status, r.interdit), (false, code, statut, false), reason: code);
        }

        reponse = FauxServeurPrestige.interdit(_droitRetours);
        final f = await gw().creerRetourManquants('BL1', clientRef: 'BLM-fictif-4');
        expect((f.success, f.interdit, f.texte), (false, true, _droitRetours));
        expect(srv.connexions, 1, reason: '403 interdit : jamais une reconnexion');
        // La session reste utilisable.
        srv.routes['GET /reception/BL1/ecarts'] = (_) => FauxServeurPrestige.ok({'success': true, 'mode': 'RECU', 'ecarts': [], 'totalManquant': 0});
        expect((await gw().ecartsBl('BL1')).success, isTrue);

        await srv.couper();
        final x = await gw().creerRetourManquants('BL1', clientRef: 'BLM-fictif-5');
        expect((x.success, x.interdit), (false, false));
        expect(x.texte, isNotEmpty);
        await srv.retablir();
      }));

  test('4.12.1 : retourManquants abandonné / refusé / sans lignes (serveur ancien), en vrai HTTP', () => avecVraiHttp(() async {
        var retour = <String, Object?>{'retourId': 'R0', 'ref': 'RF-0000', 'statut': 'is_Abandoned', 'lignes': 1, 'totalManquant': 3};
        srv.routes['GET /reception/BL1/ecarts'] =
            (_) => FauxServeurPrestige.ok({'success': true, 'mode': 'RECU', 'ecarts': [_ligne], 'totalManquant': 3, 'retourManquants': retour});
        final a = (await gw().ecartsBl('BL1')).retour!;
        expect((a.abandonne, a.lignes, a.totalManquant), (true, 1, 3));
        expect(a.texte, 'Retour RF-0000 abandonné sur Prestige : il ne compte plus.');

        retour = {'retourId': 'R0', 'ref': 'RF-0000', 'statut': 'is_Refused', 'lignes': '1', 'totalManquant': '3'};
        final r = (await gw().ecartsBl('BL1')).retour!;
        expect((r.abandonne, r.lignes, r.totalManquant), (false, 1, 3));
        expect(r.texte, contains('à corriger dans « Retour fournisseur » sur Prestige'));

        retour = {'retourId': 'R0', 'ref': 'RF-0000', 'statut': 'enable'};
        final v = (await gw().ecartsBl('BL1')).retour!;
        expect((v.lignes, v.totalManquant, v.libelle), (null, null, 'Retour RF-0000 (validé)'));
      }));

  test('4.12.1 : POST après un abandon (deja:false), deja:true de même forme, abandonné d\'un serveur ancien', () => avecVraiHttp(() async {
        final corps = <String, Object?>{
          'success': true,
          'deja': false,
          'retourId': 'R1',
          'ref': 'RF-0001',
          'statut': 'is_Waiting',
          'lignes': 1,
          'totalManquant': 3,
          'route': 'POST v1/reception/{blId}/retour-manquants',
          'msg': 'Retour des manquants RF-0001 créé'
        };
        srv.routes['POST /reception/BL1/retour-manquants'] = (_) => FauxServeurPrestige.ok(Map.of(corps));
        final c = await gw().creerRetourManquants('BL1', clientRef: 'BLM-fictif-10');
        expect((c.success, c.deja, c.ref, c.retour.abandonne), (true, false, 'RF-0001', false));

        corps['deja'] = true;
        corps['statut'] = 'is_Refused';
        final d = await gw().creerRetourManquants('BL1', clientRef: 'BLM-fictif-11');
        expect((d.deja, d.lignes, d.totalManquant), (true, 1, 3));
        expect(d.texte, 'Retour RF-0001 déjà créé (refusé ; 1 ligne(s), 3 boîte(s)).');

        srv.routes['POST /reception/BL1/retour-manquants'] =
            (_) => FauxServeurPrestige.ok({'success': true, 'deja': true, 'retourId': 'R0', 'ref': 'RF-0000', 'statut': 'is_Abandoned', 'msg': '…'});
        final x = await gw().creerRetourManquants('BL1', clientRef: 'BLM-fictif-12');
        expect(x.texte, contains('aucun nouveau retour n\'a été créé'));
        expect(srv.recuesSur('/reception/BL1/retour-manquants').map((q) => q.clientRef), ['BLM-fictif-10', 'BLM-fictif-11', 'BLM-fictif-12']);
        expect(srv.connexions, 1);
      }));

  group('demande 60 : routes des suggestions de réserve', () {
    ClientPrestige client() => ClientPrestige(() => srv.base, delaiReponse: const Duration(seconds: 2));

    test('403 « Voir les suggestions de réserve » : droit manquant, jamais SessionExpiree, droit constaté', () => avecVraiHttp(() async {
          DroitsModules.instance.fixer(utilisateur: DonneesFictives.login, reserveDedie: true, reserveSuggestions: true);
          srv.routes['GET /suggestion-reserve/en-attente'] = (_) => FauxServeurPrestige.interdit(_droitVoir);
          final api = ReserveApi(client());
          Object? erreur;
          try {
            await api.enAttente();
          } catch (e) {
            erreur = e;
          }
          expect(erreur, isA<ErreurHttp>());
          expect((erreur as ErreurHttp).droitManquant, isTrue);
          expect(erreur.message, _droitVoir);
          expect(DroitsModules.instance.reserveSuggestions, isFalse);
          expect(srv.connexions, 1);
        }));

    test('ouvrir : 403 « Traiter la réserve » ne retire pas les suggestions ; 403 « Voir » oui', () => avecVraiHttp(() async {
          DroitsModules.instance.fixer(utilisateur: DonneesFictives.login, reserveDedie: true, reserveSuggestions: true);
          final api = ReserveApi(client());
          srv.routes['PUT /suggestion-reserve/S1/ouvrir'] = (_) => FauxServeurPrestige.interdit('Droit manquant : Traiter la réserve');
          await expectLater(api.ouvrir('S1'), throwsA(isA<ErreurHttp>()));
          expect(DroitsModules.instance.reserveSuggestions, isTrue);
          srv.routes['PUT /suggestion-reserve/S1/ouvrir'] = (_) => FauxServeurPrestige.interdit(_droitVoir);
          await expectLater(api.ouvrir('S1'), throwsA(isA<ErreurHttp>().having((e) => e.droitManquant, 'droit', isTrue)));
          expect(DroitsModules.instance.reserveSuggestions, isFalse);
        }));

    test('sans le droit : creer et motifs restent permis', () => avecVraiHttp(() async {
          DroitsModules.instance.fixer(utilisateur: DonneesFictives.login, reserveDedie: true, reserveSuggestions: false);
          srv.routes['GET /suggestion-reserve/motifs'] = (_) => FauxServeurPrestige.ok([
                {'id': 1, 'libelle': 'Motif fictif', 'categorie': 'RAYON'}
              ]);
          srv.routes['POST /suggestion-reserve/creer'] =
              (_) => FauxServeurPrestige.ok({'success': true, 'lg_SUGGESTION_RESERVE_ID': 'N1', 'str_REF': 'SR-FICTIVE', 'lignes': 1, 'ignorees': 0});
          final api = ReserveApi(client());
          expect((await api.motifs(SensReserve.versRayon)).single.id, 1);
          const a = ArticleReserve(familleId: 'F1', cip: '3595583', nom: 'PRODUIT FICTIF', stockRayon: 1, stockReserve: 5);
          final r = await api.creer(SensReserve.versRayon, 1, '', const [LignePanier(a, 2)]);
          expect(r.ref, 'SR-FICTIVE');
          expect(DroitsModules.instance.reserveSuggestions, isFalse);
        }));
  });
}
