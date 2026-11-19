// INTÉGRATION — 4.15.1 : réponse du serveur à la demande 63 contre le faux serveur Prestige en VRAI HTTP (session de
// la connexion), règles de la branche serveur correctif/demande63-1911 (bb6b4604) lues dans le code, données FICTIVES :
//  - route image : forme exacte {success, largeur, dpi, tickets:[{modele, png, largeurPoints, hauteurPoints}]}, PNG en
//    niveaux de gris converti en 1 bit (384 / 576) ; vo : plusieurs tickets dans l'ordre ; 400 (type inconnu) ;
//    200 {success:false} (vente non terminée) ; serveur d'aujourd'hui : 404 → gabarit local, aucune preuve ;
//  - P_REMISE_VENTE lu dans user/droits ; 403 « Droit manquant : Remise sur une vente » ;
//  - vente/remise : `data` (comptant) = net de net/vno ; pas de `data` en assurance ; refus {success:false, msg} ;
//  - "0" : sans remise (fiche du client retirée) sur la demande 63 ; sur l'intégration d'aujourd'hui, "0" est écrit tel
//    quel et la fiche reste appliquée (d'où null tant que le serveur n'est pas prouvé).
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/droits/droits_vente.dart';
import 'package:prestige_vente_app/services/impression_ticket.dart';
import 'package:prestige_vente_app/services/ticket_serveur.dart';
import 'package:prestige_vente_app/ventes/common/remise_vente.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';

import 'outils/demande63_fictive.dart';
import 'outils/faux_serveur_prestige.dart';
import 'outils/parcours_vente.dart';
import 'outils/remises_fictives.dart';

void main() {
  late FauxServeurPrestige srv;
  late RemisesFictives rf;
  late Demande63Fictive d63;
  late ApiService api;
  late DioVenteGateway gw;

  Future<void> connecter({List<String>? droits}) async {
    if (droits != null) srv.droitsComptes = {DonneesFictives.login: droits};
    await DioClient.cookieJar.deleteAll();
    api = ApiService(baseUrl: srv.base);
    expect(await api.login(DonneesFictives.login, DonneesFictives.motDePasse), isNotNull);
    gw = DioVenteGateway(api);
  }

  Future<void> monter({bool nouveau = true, List<String>? droits}) => avecVraiHttp(() async {
        srv = FauxServeurPrestige();
        CatalogueFictif(srv, nombre: 5);
        rf = RemisesFictives(srv);
        d63 = Demande63Fictive(srv, rf, d63: nouveau);
        await srv.demarrer();
        await connecter(droits: droits);
      });

  setUp(() {
    TicketServeur.oublier();
    DroitsVente.instance.oublier();
    DroitsVente.instance.oublierControles();
  });
  tearDown(() => avecVraiHttp(() async {
        await srv.arreter();
        await DioClient.cookieJar.deleteAll();
      }));

  Future<String> vente({bool terminee = false}) async {
    final id = (await gw.addItemVno(produitId: 'F1', qte: 2, itemPu: 2500, prevente: false)).valueOrNull!;
    if (terminee) srv.statutVentes[id] = 'is_Closed';
    return id;
  }

  group('Route image (point 1)', () {
    for (final (mm, points) in [(58, 384), (80, 576)]) {
      test('vno $mm mm : forme exacte lue, PNG gris converti en 1 bit de $points points ; preuve de la demande 63', () => avecVraiHttp(() async {
            await monter();
            final id = await vente(terminee: true);
            final r = await TicketServeur.lire(api.dio, type: TypeTicketServeur.vno, id: id, largeur: mm);
            expect(r, isA<TicketsServeur>());
            final t = (r as TicketsServeur).tickets.single;
            expect((r.largeur, t.modele, t.largeurPoints), (mm, 'VENTE', points));
            expect(d63.images.single, 'vno $id $mm 203');
            final raster = ImpressionTicket.rasters(r.tickets, points)!.single;
            expect((raster.largeur, raster.hauteur), (points, t.hauteurPoints));
            expect(raster.pointsNoirs, greaterThan(0));
            expect(raster.pointsNoirs, lessThan(points * raster.hauteur ~/ 4), reason: 'fond blanc gardé (pas un rectangle noir)');
            expect(TicketServeur.etat(api.dio.options.baseUrl), EtatRouteTicket.presente);
            expect(DroitsVente.instance.controle(droitRemiseVente), isTrue);
          }));
    }

    test('vo : tous les tickets de la vente dans l\'ordre (pas de vo-combine) ; prévente : un ticket', () => avecVraiHttp(() async {
          await monter();
          final id = await vente(terminee: true);
          final vo = await TicketServeur.lire(api.dio, type: TypeTicketServeur.vo, id: id, largeur: 80) as TicketsServeur;
          expect(vo.tickets.length, 2);
          expect(TypeTicketServeur.values.map((t) => t.chemin), ['vno', 'vo', 'prevente']);
          final p = await TicketServeur.lire(api.dio, type: TypeTicketServeur.prevente, id: id, largeur: 58) as TicketsServeur;
          expect(p.tickets.single.modele, 'PREVENTE');
        }));

    test('200 {success:false} (vente non terminée) : message du serveur tel quel, route présente', () => avecVraiHttp(() async {
          await monter();
          final id = await vente();
          final r = await TicketServeur.lire(api.dio, type: TypeTicketServeur.vno, id: id, largeur: 58);
          expect(r, isA<TicketRefuseVente>().having((x) => x.message, 'msg', 'Ticket introuvable : vente $id non terminée.'));
          expect(TicketServeur.etat(api.dio.options.baseUrl), EtatRouteTicket.presente);
        }));

    test('400 (type inconnu) : TicketTypeInconnu → gabarit local', () => avecVraiHttp(() async {
          await monter();
          d63.typesConnus = {'vno', 'vo'};
          final id = await vente(terminee: true);
          final r = await TicketServeur.lire(api.dio, type: TypeTicketServeur.prevente, id: id, largeur: 58);
          expect(r, isA<TicketTypeInconnu>().having((x) => x.message, 'msg', 'Type de ticket inconnu : vno, vo ou prevente.'));
        }));

    test('serveur d\'aujourd\'hui : 404 → route absente (gabarit local), aucune preuve de la demande 63', () => avecVraiHttp(() async {
          await monter(nouveau: false);
          final id = await vente(terminee: true);
          expect(await TicketServeur.lire(api.dio, type: TypeTicketServeur.vno, id: id, largeur: 58), isA<RouteTicketAbsente>());
          expect(DroitsVente.instance.controle(droitRemiseVente), isFalse);
        }));
  });

  group('P_REMISE_VENTE (point 2)', () {
    test('droit lu dans user/droits : serveur prouvé, remise proposée', () => avecVraiHttp(() async {
          await monter(droits: ['P_SM_VENTE', droitRemise]);
          await DroitsVente.instance.actualiser(api.dio, utilisateur: DonneesFictives.login);
          expect(DroitsVente.instance.controle(droitRemiseVente), isTrue);
          expect(remiseAutorisee(DroitsVente.instance), isTrue);
        }));

    test('droit retiré au rôle : 403 interdit, message « Droit manquant : Remise sur une vente », rien d\'écrit', () => avecVraiHttp(() async {
          await monter(droits: ['P_SM_VENTE']);
          final id = await vente();
          final r = await gw.appliquerRemiseNet(id, 'REM-FICT-10');
          expect(r, isA<VenteRefused>().having((x) => x.interdit, 'interdit', isTrue).having((x) => x.message, 'msg', messageDroitRemise));
          expect(rf.remiseDeVente[id], isNull);
          expect(d63.refus403, 1);
        }));

    test('serveur d\'aujourd\'hui : droit absent de la liste, remise acceptée (comme 4.15.0)', () => avecVraiHttp(() async {
          await monter(nouveau: false, droits: ['P_SM_VENTE']);
          await DroitsVente.instance.actualiser(api.dio, utilisateur: DonneesFictives.login);
          expect(remiseAutorisee(DroitsVente.instance), isTrue);
          final id = await vente();
          expect((await gw.appliquerRemiseNet(id, 'REM-FICT-10')).isOk, isTrue);
        }));
  });

  group('Réponse de vente/remise (point 5) et « sans remise » (point 3)', () {
    test('comptant : `data` = net de net/vno (pas de second appel nécessaire)', () => avecVraiHttp(() async {
          await monter(droits: ['P_SM_VENTE', droitRemise]);
          final id = await vente();
          final r = (await gw.appliquerRemiseNet(id, 'REM-FICT-10')).valueOrNull!;
          final net = (await gw.netVnoRemise(id, 'REM-FICT-10')).valueOrNull!;
          expect((r.montant, r.remise, r.montantNet), (net.montant, net.remise, net.montantNet));
          expect(r.remise, greaterThan(0));
        }));

    test('assurance / carnet : pas de `data` → net/assurance comme avant', () => avecVraiHttp(() async {
          await monter(droits: ['P_SM_VENTE', droitRemise]);
          final id = await vente();
          d63.ventesVo.add(id);
          final r = await gw.appliquerRemiseNet(id, 'REM-FICT-5');
          expect(r.isOk, isTrue);
          expect(r.valueOrNull, isNull);
        }));

    test('serveur d\'aujourd\'hui : pas de `data` → net/vno relu comme avant', () => avecVraiHttp(() async {
          await monter(nouveau: false);
          final id = await vente();
          final r = await gw.appliquerRemiseNet(id, 'REM-FICT-5');
          expect((r.isOk, r.valueOrNull), (true, null));
        }));

    test('refus {success:false, msg} : remise inconnue, vente terminée, vente inconnue — message tel quel, vente non touchée', () => avecVraiHttp(() async {
          await monter(droits: ['P_SM_VENTE', droitRemise]);
          final id = await vente();
          expect((await gw.appliquerRemiseNet(id, 'REM-INCONNUE')).message, messageRemiseInconnue);
          expect(rf.remiseDeVente[id], isNull);
          srv.statutVentes[id] = 'is_Closed';
          expect((await gw.appliquerRemiseNet(id, 'REM-FICT-10')).message, messageVenteTerminee);
          expect((await gw.appliquerRemiseNet('V-INCONNUE', 'REM-FICT-10')).message, messageVenteInconnue);
          expect(rf.remiseDeVente, isEmpty);
        }));

    test('demande 63 : "0" retire la remise de la fiche du client pour CETTE vente ; null garde la fiche', () => avecVraiHttp(() async {
          await monter(droits: ['P_SM_VENTE', droitRemise]);
          final a = await vente(), b = await vente();
          for (final v in [a, b]) {
            d63.ventesVo.add(v);
            d63.remiseFiche[v] = 'REM-FICT-5';
          }
          expect((await gw.appliquerRemise(a, '0')).isOk, isTrue);
          expect((await gw.appliquerRemise(b, null)).isOk, isTrue);
          expect(d63.remiseAppliquee(a), isNull);
          expect(d63.remiseAppliquee(b), 'REM-FICT-5');
        }));

    test('intégration d\'aujourd\'hui : "0" écrit tel quel dans lg_REMISE_ID, la fiche reste appliquée → l\'application envoie null', () => avecVraiHttp(() async {
          await monter(nouveau: false);
          final a = await vente();
          d63.ventesVo.add(a);
          d63.remiseFiche[a] = 'REM-FICT-5';
          expect((await gw.appliquerRemise(a, '0')).isOk, isTrue);
          expect(d63.lgRemise[a], '0');
          expect(d63.remiseAppliquee(a), 'REM-FICT-5', reason: '"0" ne retire rien sur l\'ancien serveur');
          expect(remiseIdEnvoye(null, DroitsVente.instance), isNull, reason: 'serveur non prouvé : null, comme 4.15.0');
        }));
  });
}
