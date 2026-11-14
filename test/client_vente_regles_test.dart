// UNITAIRES — 4.13.0 : client d'une vente comptant (règles, contrôleur, sans écran ; données FICTIVES) :
//  - seuil de recherche : 3 caractères, ou 4 chiffres pour un numéro (espaces, points, tirets ignorés) ;
//  - lecture d'un client du serveur (lgCLIENTID obligatoire ; strADRESSE = téléphone) ; toString sans donnée ;
//  - « Client inconnu : le client de la vente est inchangé » (success:true) reconnu ;
//  - contrôleur : client retenu seulement après la confirmation, gardé sur un refus ; réponse perdue → relecture ;
//    nouvelle vente → client oublié ; reprise → client lu (type comptant seulement) ; hors ligne → aucune zone ;
//  - encaissement : clientId = client rattaché, sinon vide ; jamais le nom du mode de règlement ;
//  - plusieurs modes : idem.
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/horsligne/catalogue_sync.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart';
import 'package:prestige_vente_app/horsligne/server_monitor.dart';
import 'package:prestige_vente_app/horsligne/vente_hors_ligne.dart';
import 'package:prestige_vente_app/horsligne/ventes_sync.dart';
import 'package:prestige_vente_app/ventes/core/paiement_multiple.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'client_vente_test.dart' show FauxVenteClient, FauxVenteSansClient, clientA, clientB, produitFictif;

class _FauxCloture extends FauxVenteClient {
  final List<String> multiples = [];
  @override
  Future<VenteResult<Map<String, dynamic>>> cloturerVnoReglements({
    required String venteId,
    required SaleSummary summary,
    required List<VenteReglement> reglements,
    required String clientId,
    required String userVendeurId,
    required int montantRecu,
    required int montantRemis,
  }) async {
    multiples.add(clientId);
    return const VenteOk({'success': true});
  }
}

Future<VenteController> _vente(FauxVenteSansClient gw) async {
  final c = VenteController(gateway: gw);
  expect((await c.addProduct(produitFictif, 1)).isOk, isTrue);
  return c;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('seuil de recherche', () {
    for (final (t, ok) in [
      ('', false),
      ('KO', false),
      ('  KO ', false),
      ('KOF', true),
      ('a b', true),
      ('070', false),
      ('0700', true),
      ('07 00', true),
      ('07.0', false),
      ('+2250', true),
      ('+225', false),
      ('+22', false),
      ('07-00-01', true),
      ('12A', true),
    ]) {
      test('« $t » → ${ok ? 'recherche' : 'rien'}', () => expect(rechercheClientPossible(t), ok));
    }
  });

  group('client lu du serveur', () {
    test('champs du client rapide ; strADRESSE = téléphone ; sans identifiant → null', () {
      final c = ClientVente.depuisJson({'lgCLIENTID': 'CL-1', 'strFIRSTNAME': 'NOM-FICTIF', 'strLASTNAME': 'PRENOM', 'strADRESSE': '0700000000', 'email': null});
      expect((c!.id, c.nom, c.prenom, c.telephone, c.nomComplet), ('CL-1', 'NOM-FICTIF', 'PRENOM', '0700000000', 'NOM-FICTIF PRENOM'));
      expect(ClientVente.depuisJson({'strFIRSTNAME': 'SANS-ID'}), isNull);
      expect(ClientVente.depuisJson({'lgCLIENTID': ''}), isNull);
      expect(ClientVente.depuisJson(null), isNull);
      expect(ClientVente.depuisJson('CL-1'), isNull);
      expect(ClientVente.depuisJson({'lgCLIENTID': 'CL-2', 'strADRESSE': null})!.nomComplet, 'Client');
      expect(ClientVente.depuisJson({'lgCLIENTID': 'CL-2', 'strADRESSE': 'null'})!.telephone, '');
    });

    test('toString ne contient ni nom ni téléphone', () {
      final s = '$clientA';
      for (final x in [clientA.nom, clientA.prenom, clientA.telephone, clientA.id]) {
        expect(s, isNot(contains(x)));
      }
    });

    test('« Client inconnu : le client de la vente est inchangé » reconnu ; succès normal non', () {
      expect(clientInchangeDe({'success': true, 'msg': 'Client inconnu : le client de la vente est inchangé.'}), isTrue);
      expect(clientInchangeDe({'success': true, 'msg': 'Opération effectuée avec success'}), isFalse);
      expect(clientInchangeDe({'success': true}), isFalse);
      expect(clientInchangeDe('x'), isFalse);
    });
  });

  group('contrôleur', () {
    test('client retenu après la confirmation ; refus → client précédent gardé ; changé → seul le second', () async {
      final gw = FauxVenteClient();
      final c = await _vente(gw);
      expect(c.clientDisponible, isTrue);
      expect((await c.choisirClient(clientA)).isOk, isTrue);
      expect(c.client?.id, 'CL-A');
      gw.reponseRattachement = (_) => const VenteRefused('Refus fictif du serveur.');
      final r = await c.choisirClient(clientB);
      expect(r.message, 'Refus fictif du serveur.');
      expect(c.client?.id, 'CL-A');
      gw.reponseRattachement = null;
      expect((await c.choisirClient(clientB)).isOk, isTrue);
      expect(c.client?.id, 'CL-B');
      expect(gw.rattachements, ['CL-A', 'CL-B', 'CL-B']);
    });

    test('retrait : clientId null ; échec → client gardé', () async {
      final gw = FauxVenteClient();
      final c = await _vente(gw);
      await c.choisirClient(clientA);
      gw.reponseRattachement = (_) => const VenteFailed('Serveur injoignable (retirer le client)');
      expect((await c.retirerClient()).isOk, isFalse);
      expect(c.client?.id, 'CL-A');
      gw.reponseRattachement = null;
      expect((await c.retirerClient()).isOk, isTrue);
      expect(c.client, isNull);
      expect(gw.rattachements, ['CL-A', null, null]);
    });

    test('réponse perdue au rattachement : client relu sur la vente (affiché seulement s\'il y est)', () async {
      final gw = FauxVenteClient();
      final c = await _vente(gw);
      gw.reponseRattachement = (_) => const VenteFailed('Le serveur met trop de temps à répondre.', maybeApplied: true);
      gw.clientLu = {'lgCLIENTID': 'CL-A', 'strFIRSTNAME': 'KOFFI-TEST', 'strLASTNAME': 'AMANI'};
      expect((await c.choisirClient(clientA)).isOk, isTrue, reason: 'appliqué : relu sur la vente');
      expect(c.client?.id, 'CL-A');
      gw.clientLu = {'lgCLIENTID': 'CL-A'};
      final r = await c.choisirClient(clientB);
      expect(r.isOk, isFalse);
      expect(r.message, contains('Client non confirmé'));
      expect(c.client?.id, 'CL-A', reason: 'le serveur porte toujours A');
    });

    test('aucune vente créée : rien envoyé ; vente terminée : refusé sans appel', () async {
      final gw = FauxVenteClient();
      final c = VenteController(gateway: gw);
      expect(c.clientDisponible, isFalse);
      expect((await c.choisirClient(clientA)).isOk, isFalse);
      expect((await c.creerClient(nom: 'X', prenom: '', telephone: '')).isOk, isFalse);
      expect(gw.rattachements, isEmpty);
      expect(gw.creationsClient, isEmpty);
    });

    test('création : nom et prénom vides refusés sans appel', () async {
      final gw = FauxVenteClient();
      final c = await _vente(gw);
      final r = await c.creerClient(nom: '  ', prenom: '', telephone: '0700');
      expect(r.message, 'Le nom ou le prénom du client est obligatoire.');
      expect(gw.creationsClient, isEmpty);
    });

    test('recherche sous le seuil : refusée sans appel', () async {
      final gw = FauxVenteClient();
      final c = await _vente(gw);
      expect((await c.rechercherClients('KO')).message, VenteController.messageClientRecherche);
      expect(gw.recherches, isEmpty);
      expect((await c.rechercherClients('KOF')).valueOrNull, hasLength(2));
    });

    test('nouvelle vente : client oublié ; reprise : client lu (comptant seulement)', () async {
      final gw = FauxVenteClient();
      final c = await _vente(gw);
      await c.choisirClient(clientA);
      c.reset();
      expect(c.client, isNull);
      gw.clientLu = {'lgCLIENTID': 'CL-A', 'strFIRSTNAME': 'KOFFI-TEST', 'strLASTNAME': 'AMANI', 'strADRESSE': '0700000001'};
      await c.loadVente('V1');
      expect(c.client?.telephone, '0700000001');
      gw.lectureForcee = const VenteOk({'strSTATUT': 'pending', 'lgTYPEVENTEID': '2', 'client': {'lgCLIENTID': 'CL-ASSU'}});
      await c.loadVente('V1');
      expect(c.client, isNull, reason: 'une vente assurance n\'est pas une vente comptant');
      gw.lectureForcee = const VenteFailed('Serveur injoignable (charger la vente)');
      await c.loadVente('V1');
      expect(c.clientNonLu, contains('injoignable'));
      gw.lectureForcee = null;
      await c.relireClient();
      expect(c.clientNonLu, isNull);
      expect(c.client?.id, 'CL-A');
    });

    test('passerelle sans la capacité : aucune relecture ajoutée, aucune zone', () async {
      final gw = FauxVenteSansClient();
      final c = await _vente(gw);
      await c.loadVente('V1');
      expect(gw.lectures, 0);
      expect(c.clientDisponible, isFalse);
      expect((await c.rechercherClients('KOFFI')).isOk, isFalse);
    });

    test('encaissement : clientId = client rattaché, sinon vide ; jamais le nom du mode', () async {
      final gw = FauxVenteClient();
      var c = await _vente(gw);
      await c.encaisser(method: PaymentMethod(id: '10', name: 'WAVE'), userId: 'U1', expectedChanges: c.changes);
      c = await _vente(gw);
      await c.choisirClient(clientB);
      await c.encaisser(method: PaymentMethod(id: '1', name: 'Espèces'), userId: 'U1', expectedChanges: c.changes);
      expect(gw.clotureClientIds, ['', 'CL-B']);
      expect(gw.updateClientAppels, isEmpty);
      expect(gw.rattachements, ['CL-B']);
    });

    test('plusieurs modes : même règle', () async {
      final gw = _FauxCloture();
      final c = await _vente(gw);
      await c.choisirClient(clientA);
      final net = c.summary.montantNet;
      final r = await c.encaisserReglements(
        lignes: [
          ReglementLigne(PaymentMethod(id: '1', name: 'Espèces'), net - 500, recu: net - 500),
          ReglementLigne(PaymentMethod(id: '10', name: 'WAVE'), 500, confirme: true),
        ],
        userId: 'U1',
        expectedChanges: c.changes,
        montantRecu: net,
        montantRemis: 0,
      );
      expect(r.isOk, isTrue, reason: r.message);
      expect(gw.multiples, ['CL-A']);
      expect(gw.updateClientAppels, isEmpty);
    });

    test('hors ligne : aucune zone Client, recherche refusée sans appel', () async {
      final store = MemoryLocalStore();
      final hl = HorsLigne(monitor: ServerMonitor(), store: store, sync: CatalogueSync(store: store, occupee: () => false), ventes: FileVentesHL(store: MemoryVentesHLStore()));
      final avant = HorsLigne.instance;
      HorsLigne.instance = hl;
      addTearDown(() => HorsLigne.instance = avant);
      final gw = FauxVenteClient();
      final c = await _vente(gw);
      await c.choisirClient(clientA);
      hl.monitor.goOffline();
      expect(c.clientDisponible, isFalse);
      expect((await c.rechercherClients('KOFFI')).message, VenteController.messageClientHorsLigne);
      expect((await c.retirerClient()).message, VenteController.messageClientHorsLigne);
      expect(gw.recherches, isEmpty);
      expect(c.client?.id, 'CL-A', reason: 'client rattaché en ligne : gardé sur le serveur et à l\'écran');
    });
  });
}
