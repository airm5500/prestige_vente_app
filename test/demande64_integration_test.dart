// INTÉGRATION — 4.15.2 : demande 64 contre le faux serveur Prestige en VRAI HTTP (session de la connexion), règles de
// la branche serveur correctif/demande64-1911 (d6cf51fa5) lues dans le code, données FICTIVES :
//  - borne : POST v1/paiements-mobile cloturer:true, caisse du compte fermée → 200 {success:false, message} : refus
//    (pas une panne réseau, pas un 403), AUCUN paiement créé, une seule demande (jamais cloturer:false) ;
//  - sans `cloturer` (comptoir) ou avec `part` : accepté comme avant ;
//  - comptoir (nouvelle interface, DioVenteGateway) : ajout, quantité, retrait, remise refusés sur une prévente payée
//    ou au paiement en cours, `msg` du serveur tel quel, rien d'écrit ; verrou levé à l'annulation du paiement ;
//  - ancienne interface (ApiService, SaleProvider) : même refus, message rendu, panier inchangé ;
//  - serveur déployé (76aa5fc1, sans la demande 64) : comportement de 4.15.1 (paiement créé caisse fermée, panier
//    modifiable).
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/paiements/paiements_mobile.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'outils/clients_vente_fictifs.dart';
import 'outils/demande62_fictive.dart';
import 'outils/demande64_fictive.dart';
import 'outils/faux_serveur_prestige.dart';
import 'outils/parcours_vente.dart';

void main() {
  late FauxServeurPrestige srv;
  late Demande64Fictive d64;
  late ApiService api;
  late DioVenteGateway gw;
  late DioPaiementsMobileApi pm;

  Future<void> connecter({List<String>? droits}) async {
    if (droits != null) srv.droitsComptes = {DonneesFictives.login: droits};
    await DioClient.cookieJar.deleteAll();
    api = ApiService(baseUrl: srv.base);
    expect(await api.login(DonneesFictives.login, DonneesFictives.motDePasse), isNotNull);
    gw = DioVenteGateway(api);
    pm = DioPaiementsMobileApi(() => api.dio);
  }

  setUp(() => avecVraiHttp(() async {
        SharedPreferences.setMockInitialValues({});
        srv = FauxServeurPrestige();
        CatalogueFictif(srv, nombre: 5);
        ClientsVenteFictifs(srv);
        d64 = Demande64Fictive(srv);
        await srv.demarrer();
        await connecter(droits: ['P_SM_VENTE', droitBorne]);
      }));
  tearDown(() => avecVraiHttp(() async {
        await srv.arreter();
        await DioClient.cookieJar.deleteAll();
      }));

  Future<String> prevente({int pu = 4125}) async {
    final id = (await gw.addItemVno(produitId: 'F1', qte: 1, itemPu: pu, prevente: true)).valueOrNull!;
    expect((await gw.terminerPrevente(id)).isOk, isTrue);
    return id;
  }

  List<Map<String, dynamic>> lignes(String id) => [for (final l in srv.ventes[id]!) Map<String, dynamic>.from(l)];

  group('Borne : refus avant tout encaissement (point 1)', () {
    test('caisse fermée : 200 {success:false, message} → refus lisible, aucun paiement, une seule demande', () => avecVraiHttp(() async {
          final id = await prevente();
          final r = await pm.creer(venteId: id, operateur: 'wave', cloturer: true, cle: 'PM-FICT-64A');
          expect(r, isA<VenteRefused<PaiementMobile>>(), reason: 'pas une panne réseau');
          expect((r as VenteRefused).interdit, isFalse);
          expect(r.message, messageCaisseFermee);
          expect(estRefusPaiementImpossible(r.message), isTrue);
          expect(d64.d62.paiements, isEmpty, reason: 'rien créé, opérateur non appelé');
          final a = AttentePaiement(pm);
          await a.demarrer(venteId: id, operateur: 'wave', cloturer: true);
          expect((a.refusAvantPaiement, a.interdit, a.paiement, a.erreur), (true, false, null, messageCaisseFermee));
          expect(d64.d62.creations.map((c) => c['cloturer']), [true, true], reason: 'jamais de demande cloturer:false');
          expect(d64.d62.paiements, isEmpty);
          expect(srv.statutVentes[id], 'is_Process', reason: 'prévente gardée pour la caisse');
          a.dispose();
        }));

    test('caisse ouverte : paiement créé avec clôture automatique, puis vente terminée (inchangé)', () => avecVraiHttp(() async {
          d64.d62.caissesOuvertes.add(DonneesFictives.login);
          final id = await prevente();
          final a = AttentePaiement(pm);
          await a.demarrer(venteId: id, operateur: 'wave', cloturer: true);
          expect((a.refusAvantPaiement, a.paiement?.clotureAuto), (false, true));
          d64.d62.payer(a.paiement!.id);
          await a.interroger();
          expect(a.paiement!.clotureConfirmee, isTrue);
          expect(srv.statutVentes[id], 'is_Closed');
          a.dispose();
        }));

    test('sans cloturer (comptoir) ou avec part : accepté même caisse fermée (inchangé)', () => avecVraiHttp(() async {
          final id = await prevente();
          expect((await pm.creer(venteId: id, operateur: 'wave', cle: 'PM-FICT-64B')).isOk, isTrue);
          final id2 = await prevente();
          expect((await pm.creer(venteId: id2, operateur: 'wave', part: 2000, cloturer: true, cle: 'PM-FICT-64C')).isOk, isTrue);
          expect(d64.d62.paiements, hasLength(2));
        }));

    test('403 interdit (droit retiré) : refus de droit, pas « paiement impossible », aucune autre demande', () => avecVraiHttp(() async {
          await connecter(droits: ['P_SM_VENTE']);
          final id = await prevente();
          final a = AttentePaiement(pm);
          await a.demarrer(venteId: id, operateur: 'wave', cloturer: true);
          expect((a.interdit, a.refusAvantPaiement, a.paiement), (true, false, null));
          expect(d64.d62.creations, hasLength(1));
          a.dispose();
        }));
  });

  group('Comptoir : panier verrouillé (point 2), nouvelle interface', () {
    for (final paye in [true, false]) {
      final cas = paye ? 'payée (Wave)' : 'paiement en cours (Orange Money)';
      final attendu = paye ? messagePayeWave4125 : messageEnCoursOrange4125;
      test('prévente $cas : ajout, quantité, retrait, remise refusés, msg tel quel, rien d\'écrit', () => avecVraiHttp(() async {
            final id = await prevente();
            if (paye) {
              d64.d62.payeeALaBorne(id);
            } else {
              d64.paiementEnCours(id);
            }
            final avant = lignes(id);
            final ligne = (await gw.saleDetails(id)).valueOrNull!.single;
            final rs = <VenteResult<dynamic>>[
              await gw.addItemVno(produitId: 'F2', qte: 1, itemPu: 500, venteId: id, prevente: true),
              await gw.updateItem(itemId: ligne.lgPREENREGISTREMENTDETAILID, produitId: ligne.lgFAMILLEID, qte: 2, itemPu: 4125),
              await gw.removeItem(ligne.lgPREENREGISTREMENTDETAILID),
              await gw.appliquerRemise(id, 'R-FICT-10'),
              await gw.appliquerRemiseNet(id, null),
            ];
            for (final r in rs) {
              expect(r, isA<VenteRefused<dynamic>>());
              expect(r.message, attendu);
              expect((r as VenteRefused).panierVerrouille, isTrue);
              expect((r.interdit, r.caisseFermee, r.dejaCloturee, r.paiementMobile), (false, false, false, false));
            }
            expect(lignes(id), avant, reason: 'rien n\'est écrit');
            expect(d64.refus, hasLength(5));
            expect(d64.appliquees, isEmpty);
            expect(d64.remises.containsKey(id), isFalse);
            expect((await gw.netVno(id)).valueOrNull?.montantNet, 4125, reason: 'le net reste permis et inchangé');
          }));
    }

    test('paiement en cours annulé : le verrou tombe, la quantité passe de 1 à 2', () => avecVraiHttp(() async {
          final id = await prevente();
          final p = d64.paiementEnCours(id);
          final ligne = (await gw.saleDetails(id)).valueOrNull!.single;
          expect((await gw.updateItem(itemId: ligne.lgPREENREGISTREMENTDETAILID, produitId: 'F1', qte: 2, itemPu: 4125)).isOk, isFalse);
          d64.annuler(p);
          expect((await gw.updateItem(itemId: ligne.lgPREENREGISTREMENTDETAILID, produitId: 'F1', qte: 2, itemPu: 4125)).isOk, isTrue);
          expect(srv.ventes[id]!.single['intQUANTITY'], 2);
        }));
  });

  group('Ancienne interface (ApiService / SaleProvider)', () {
    test('ajout, quantité, retrait refusés : message du serveur rendu, panier relu inchangé', () => avecVraiHttp(() async {
          final id = await prevente();
          d64.d62.payeeALaBorne(id);
          final sp = SaleProvider(api);
          await sp.loadPrevente(id);
          final avant = [for (final i in sp.cartItems) (i.lgPREENREGISTREMENTDETAILID, i.intQUANTITY)];
          expect(avant, hasLength(1));
          final p = ProductSearchResult(lgFAMILLEID: 'F2', strNAME: 'PRODUIT FICTIF 2', intCIP: '2', intPRICE: 500, intNUMBERAVAILABLE: 9, strLIBELLEE: '', intPAF: 0);
          expect(await sp.addProductToCart(p, 1, isPrevente: true), messagePayeWave4125);
          expect(await sp.updateCartItem(sp.cartItems.single, 3, 4125), messagePayeWave4125);
          expect(await sp.removeProductFromCart(sp.cartItems.single.lgPREENREGISTREMENTDETAILID), messagePayeWave4125);
          expect([for (final i in sp.cartItems) (i.lgPREENREGISTREMENTDETAILID, i.intQUANTITY)], avant);
          expect(sp.currentVenteId, id);
          expect(api.prendreRefusPanier(), isNull, reason: 'message lu une seule fois');
          sp.dispose();
        }));

    test('vente modifiable : aucun message, panier relu (inchangé par rapport à 4.15.1)', () => avecVraiHttp(() async {
          final id = await prevente();
          final sp = SaleProvider(api);
          await sp.loadPrevente(id);
          expect(await sp.updateCartItem(sp.cartItems.single, 2, 4125), isNull);
          expect(sp.cartItems.single.intQUANTITY, 2);
          sp.dispose();
        }));
  });

  group('Serveur déployé en officine (76aa5fc1, sans la demande 64) : comme 4.15.1', () {
    test('caisse fermée : paiement créé (clôture refusée ensuite → ticket PAYÉE) ; panier modifiable', () => avecVraiHttp(() async {
          d64.d64 = false;
          final id = await prevente();
          final a = AttentePaiement(pm);
          await a.demarrer(venteId: id, operateur: 'wave', cloturer: true);
          expect((a.refusAvantPaiement, a.paiement?.clotureAuto), (false, true));
          d64.d62.payer(a.paiement!.id);
          await a.interroger();
          expect((a.paiement!.statut, a.paiement!.clotureConfirmee), (StatutPM.paye, false));
          final id2 = await prevente();
          d64.d62.payeeALaBorne(id2);
          final l = (await gw.saleDetails(id2)).valueOrNull!.single;
          expect((await gw.updateItem(itemId: l.lgPREENREGISTREMENTDETAILID, produitId: 'F1', qte: 2, itemPu: 4125)).isOk, isTrue);
          a.dispose();
        }));
  });
}
