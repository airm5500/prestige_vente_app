// PrestigePOS 1.11.0 — UNITAIRES et ÉCRANS : client facultatif de la vente comptant de la borne (données FICTIVES) :
//  - BorneClientEtat : seuils de recherche (rien sous 3 caractères / 4 chiffres), réponse d'une frappe précédente
//    ignorée, choix (liste effacée), création (refus msg tel quel), vider() efface TOUT ;
//  - BorneService.creerPrevente : client rattaché avant terminerprevente ; refus → prévente valable + message ;
//    sans client, ou passerelle sans la capacité : aucun appel ; jamais le nom du mode de règlement ;
//  - écran : zone (cibles ≥ 56), croix rouge puis second appui, page (clavier nom / téléphone).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/borne/borne_client.dart';
import 'package:prestige_vente_app/borne/borne_panier.dart';
import 'package:prestige_vente_app/borne/borne_produit.dart';
import 'package:prestige_vente_app/borne/borne_service.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';

import '../client_vente_test.dart' show FauxVenteClient, FauxVenteSansClient, clientA;

class _Clients implements ClientVenteGateway {
  final List<String> recherches = [];
  final Map<String, Completer<VenteResult<List<ClientVente>>>> attentes = {};
  VenteResult<ClientVente>? creation;

  @override
  Future<VenteResult<List<ClientVente>>> rechercherClientsVente(String texte) {
    recherches.add(texte);
    return (attentes[texte] ??= Completer()).future;
  }

  @override
  Future<VenteResult<ClientVente>> creerClientVente({required String nom, required String prenom, required String telephone}) async =>
      creation ?? VenteOk(ClientVente(id: 'CL-N', nom: nom.toUpperCase(), prenom: prenom.toUpperCase(), telephone: telephone));

  @override
  Future<VenteResult<void>> rattacherClientVente(String venteId, String? clientId) async => const VenteOk(null);
}

final _ligne = BorneLigne(
    BorneProduit(ProductSearchResult(lgFAMILLEID: 'P1', strNAME: 'PRODUIT FICTIF', intCIP: '3400930000001', intPRICE: 1500, intNUMBERAVAILABLE: 9, strLIBELLEE: '', intPAF: 0)),
    1);

void main() {
  group('BorneClientEtat', () {
    test('seuils : rien sous 3 caractères ou 4 chiffres ; réponse d\'une frappe précédente ignorée', () async {
      final g = _Clients();
      final e = BorneClientEtat(g);
      await e.chercher('KO');
      await e.chercher('070');
      expect(g.recherches, isEmpty);
      final f1 = e.chercher('KOF');
      final f2 = e.chercher('KOFFI');
      g.attentes['KOFFI']!.complete(const VenteOk([clientA]));
      await f2;
      g.attentes['KOF']!.complete(const VenteOk([]));
      await f1;
      expect(e.resultats, [clientA], reason: 'la réponse de « KOF », arrivée après, est ignorée');
    });

    test('choisir : liste effacée ; vider : client, résultats, erreurs effacés', () async {
      final g = _Clients();
      final e = BorneClientEtat(g);
      final f = e.chercher('KOFFI');
      g.attentes['KOFFI']!.complete(const VenteOk([clientA]));
      await f;
      e.choisir(clientA);
      expect((e.choisi, e.resultats), (clientA, null));
      e.erreur = 'x';
      e.vider();
      expect((e.choisi, e.resultats, e.erreur, e.cherche, e.occupe), (null, null, null, false, false));
    });

    test('création : refus msg tel quel ; nom et prénom vides refusés sans appel ; vente abandonnée entre-temps', () async {
      final g = _Clients()..creation = const VenteRefused('Le nom ne doit pas dépasser 50 caractères.');
      final e = BorneClientEtat(g);
      expect(await e.creer(nom: ' ', prenom: '', telephone: '07'), isFalse);
      expect(e.erreur, 'Le nom ou le prénom est obligatoire.');
      expect(await e.creer(nom: 'X', prenom: '', telephone: ''), isFalse);
      expect(e.erreur, 'Le nom ne doit pas dépasser 50 caractères.');
      g.creation = null;
      final f = e.creer(nom: 'Nouveau', prenom: 'Fictif', telephone: '07');
      e.vider();
      expect(await f, isFalse, reason: 'abandon pendant la création : rien de retenu');
      expect(e.choisi, isNull);
      expect(await e.creer(nom: 'Nouveau', prenom: 'Fictif', telephone: '07'), isTrue);
      expect(e.choisi!.nomComplet, 'NOUVEAU FICTIF');
    });

    test('sans la capacité : indisponible', () => expect(BorneClientEtat(null).disponible, isFalse));
  });

  group('BorneService.creerPrevente', () {
    test('client rattaché avant de terminer la prévente ; sans client : aucun appel', () async {
      final gw = FauxVenteClient()..delai = Duration.zero;
      final s = BorneService(gw, nouvelleCle: () => 'BORNE-TEST');
      final p = (await s.creerPrevente([_ligne], client: clientA)).valueOrNull!;
      expect(gw.rattachements, ['CL-A']);
      expect((p.clientAssocie, p.clientRefus), (true, null));
      final p2 = (await s.creerPrevente([_ligne])).valueOrNull!;
      expect(gw.rattachements, ['CL-A']);
      expect((p2.clientAssocie, p2.clientRefus), (false, null));
      expect(gw.updateClientAppels, isEmpty, reason: 'jamais le nom du mode de règlement');
    });

    test('rattachement refusé : prévente valable, message gardé', () async {
      final gw = FauxVenteClient()
        ..delai = Duration.zero
        ..reponseRattachement = (_) => const VenteRefused('Refus fictif du serveur.');
      final p = (await BorneService(gw, nouvelleCle: () => 'K').creerPrevente([_ligne], client: clientA)).valueOrNull!;
      expect((p.clientAssocie, p.clientRefus), (false, 'Refus fictif du serveur.'));
      expect(gw.statut[p.venteId], 'pending', reason: 'terminerPrevente appelé (faux service)');
    });

    test('passerelle sans la capacité : client ignoré', () async {
      final gw = FauxVenteSansClient()..delai = Duration.zero;
      final p = (await BorneService(gw, nouvelleCle: () => 'K').creerPrevente([_ligne], client: clientA)).valueOrNull!;
      expect(p.clientAssocie, isFalse);
    });
  });

  group('écran', () {
    Future<BorneClientEtat> zone(WidgetTester t) async {
      final e = BorneClientEtat(_Clients())..choisir(clientA);
      var ouvert = 0;
      await t.pumpWidget(MaterialApp(
          home: Scaffold(body: StatefulBuilder(builder: (c, set) => BorneClientZone(etat: e, onOuvrir: () => ouvert++, onActivite: () => set(() {}))))));
      return e;
    }

    testWidgets('croix : rouge au 1er appui, retrait au 2e ; cibles ≥ 56', (t) async {
      final e = await zone(t);
      final croix = find.byKey(const ValueKey('borne-client-retirer'));
      expect(t.getSize(croix).height, greaterThanOrEqualTo(56));
      await t.tap(croix);
      await t.pump();
      expect(find.byKey(const ValueKey('borne-client-confirmer')), findsOneWidget);
      expect(e.choisi, isNotNull);
      await t.tap(croix);
      await t.pump();
      expect(e.choisi, isNull);
      await t.pump(const Duration(seconds: 5));
    });

    testWidgets('page : clavier nom / téléphone, « Retour au panier »', (t) async {
      final e = BorneClientEtat(_Clients());
      var retours = 0;
      await t.pumpWidget(MaterialApp(home: Scaffold(body: BorneClientVue(etat: e, onRetour: () => retours++, onActivite: () {}))));
      expect(t.widget<TextField>(find.byKey(const ValueKey('borne-client-recherche'))).keyboardType, TextInputType.name);
      await t.tap(find.byKey(const ValueKey('borne-client-nouveau')));
      await t.pump();
      expect(t.widget<TextField>(find.byKey(const ValueKey('borne-client-telephone-saisi'))).keyboardType, TextInputType.phone);
      expect(t.getSize(find.byKey(const ValueKey('borne-client-creer'))).height, greaterThanOrEqualTo(56));
      await t.tap(find.byKey(const ValueKey('borne-client-retour')));
      expect(retours, 1);
    });
  });
}
