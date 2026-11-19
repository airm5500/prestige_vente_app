// ÉCRANS — 4.15.1 : réponse du serveur à la demande 63, passerelle et serveur simulés, données FICTIVES :
//  - remise comptant : `data` de vente/remise utilisé (aucun net/vno de plus) ; « Retirer » envoie "0" sur la
//    demande 63, null sur le serveur d'aujourd'hui ; « SANS REMISE » proposé seulement sur la demande 63 ;
//  - droit retiré au rôle (serveur prouvé) : zone Remise masquée ; serveur d'aujourd'hui : zone proposée ;
//  - refus {success:false, msg} et 403 : message tel quel, remise non affichée ;
//  - ticket : 200 {success:false} → message du serveur, « Réimprimer », « Ticket de l'application », « Fermer » ;
//    400 → gabarit local sans question ; tickets → images converties en 1 bit envoyées à l'imprimante.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/droits/droits_vente.dart';
import 'package:prestige_vente_app/services/impression_ticket.dart';
import 'package:prestige_vente_app/services/ticket_1bit.dart';
import 'package:prestige_vente_app/services/ticket_serveur.dart';
import 'package:prestige_vente_app/ventes/common/remise_vente.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';

import 'client_vente_test.dart' show ouvrirVente, ajouterArticle;
import 'outils/demande63_fictive.dart';
import 'remise_vente_test.dart' show FauxVenteRemise, zoneRemise, choisirRemise, retirerRemise, nomRemise, choisir;

/// Passerelle comptant du serveur avec la demande 63 : vente/remise rend le net (`data`).
class FauxVenteRemise63 extends FauxVenteRemise implements RemiseVenteNetGateway {
  final bool data;
  VenteResult<SaleSummary?>? reponseNet;
  FauxVenteRemise63({this.data = true});

  @override
  Future<VenteResult<SaleSummary?>> appliquerRemiseNet(String venteId, String? remiseId) async {
    final f = reponseNet;
    if (f != null) {
      poses.add((venteId, remiseId));
      return f;
    }
    final r = await appliquerRemise(venteId, remiseId == '0' ? null : remiseId);
    poses
      ..removeLast()
      ..add((venteId, remiseId));
    if (!r.isOk || !data) return r.map((_) => null);
    final t = (ventes[venteId] ?? const []).fold<int>(0, (s, i) => s + i.intPRICE);
    final avant = nets.length;
    final n = (await netVnoRemise(venteId, remiseDe[venteId])).valueOrNull!;
    nets.removeRange(avant, nets.length); // calcul interne du serveur, pas un appel de l'application
    return VenteOk(SaleSummary(montant: t, remise: n.remise, montantNet: n.montantNet, venteId: venteId));
  }
}

void _telephone(WidgetTester t) {
  t.view.physicalSize = const Size(720, 1440);
  t.view.devicePixelRatio = 2.0;
  addTearDown(t.view.reset);
}

String _net(WidgetTester t) => t.widget<Text>(find.byKey(const ValueKey('vente-net'))).data!;

class _Adaptateur implements HttpClientAdapter {
  final List<ResponseBody Function(RequestOptions o)> reponses;
  int appels = 0;
  _Adaptateur(this.reponses);
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async =>
      reponses[(appels++).clamp(0, reponses.length - 1)](o);
  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object corps, [int statut = 200]) =>
    ResponseBody.fromString(jsonEncode(corps), statut, headers: {Headers.contentTypeHeader: ['application/json']});

ResponseBody _tickets(RequestOptions o) {
  final p = o.queryParameters['largeur'] == 58 ? 384 : 576;
  final png = Demande63Fictive.ticketGris(p);
  return _json({
    'success': true,
    'largeur': p == 384 ? 58 : 80,
    'dpi': 203,
    'tickets': [{'modele': 'VENTE', 'png': base64Encode(png), 'largeurPoints': p, 'hauteurPoints': 274}],
  });
}

void main() {
  setUp(() {
    DroitsVente.instance.fixer(null);
    DroitsVente.instance.oublierControles();
  });

  group('Remise comptant', () {
    testWidgets('demande 63 : `data` utilisé (pas de net/vno de plus) ; « Retirer » envoie "0"', (t) async {
      _telephone(t);
      DroitsVente.instance.fixer({'P_SM_VENTE', droitRemiseVente});
      final gw = FauxVenteRemise63();
      await ouvrirVente(t, gw);
      await ajouterArticle(t);
      final brut = _net(t);
      final avant = gw.nets.length;
      await choisir(t, 'REM-FICT-10');
      expect(gw.poses.last.$2, 'REM-FICT-10');
      expect(gw.nets.length, avant, reason: 'net rendu par vente/remise : aucun appel à net/vno');
      expect(_net(t), isNot(brut));
      expect(find.text('Remise appliquée : REMISE FICTIVE 10 %.'), findsOneWidget);
      await t.pumpAndSettle(const Duration(seconds: 5));
      await t.tap(retirerRemise);
      await t.pumpAndSettle();
      expect(gw.poses.last.$2, '0');
      expect(_net(t), brut);
      expect(retirerRemise, findsNothing);
    });

    testWidgets('serveur d\'aujourd\'hui (pas de `data`, droit inconnu) : zone proposée, net/vno relu, « Retirer » envoie null', (t) async {
      _telephone(t);
      DroitsVente.instance.fixer({'P_SM_VENTE'});
      final gw = FauxVenteRemise63(data: false);
      await ouvrirVente(t, gw);
      await ajouterArticle(t);
      expect(zoneRemise, findsOneWidget);
      await t.tap(choisirRemise);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('remise-option-0')), findsNothing, reason: '« SANS REMISE » seulement sur la demande 63');
      await t.tap(find.byKey(const ValueKey('remise-option-REM-FICT-5')));
      await t.pumpAndSettle();
      expect(gw.nets.last, (gw.poses.last.$1, 'REM-FICT-5'), reason: 'net relu avec la remise, comme 4.15.0');
      await t.pumpAndSettle(const Duration(seconds: 5));
      await t.tap(retirerRemise);
      await t.pumpAndSettle();
      expect(gw.poses.last.$2, isNull);
    });

    testWidgets('demande 63 : « SANS REMISE » proposé et envoyé en "0"', (t) async {
      _telephone(t);
      DroitsVente.instance.fixer({'P_SM_VENTE', droitRemiseVente});
      final gw = FauxVenteRemise63();
      await ouvrirVente(t, gw);
      await ajouterArticle(t);
      await choisir(t, '0');
      expect(gw.poses.last.$2, '0');
      expect(find.text('Sans remise pour cette vente.'), findsOneWidget);
      expect(retirerRemise, findsNothing);
    });

    testWidgets('droit retiré au rôle (serveur prouvé, droits lus) : aucune zone Remise', (t) async {
      _telephone(t);
      DroitsVente.instance.controleConstate(droitRemiseVente);
      DroitsVente.instance.fixer({'P_SM_VENTE', 'P_SM_CLOTURER_CAISSE'});
      final gw = FauxVenteRemise63();
      await ouvrirVente(t, gw);
      await ajouterArticle(t);
      expect(zoneRemise, findsNothing);
    });

    testWidgets('refus {success:false, msg} : message tel quel, remise non affichée', (t) async {
      _telephone(t);
      DroitsVente.instance.fixer({'P_SM_VENTE', droitRemiseVente});
      final gw = FauxVenteRemise63()..reponseNet = const VenteRefused(messageRemiseInconnue);
      await ouvrirVente(t, gw);
      await ajouterArticle(t);
      await choisir(t, 'REM-FICT-10');
      expect(find.text(messageRemiseInconnue), findsOneWidget);
      expect(t.widget<Text>(nomRemise).data, 'Remise');
      expect(retirerRemise, findsNothing);
    });

    testWidgets('403 « Droit manquant : Remise sur une vente » : message tel quel, zone masquée', (t) async {
      _telephone(t);
      final gw = FauxVenteRemise63()..reponseNet = const VenteRefused(messageDroitRemise, code: VenteRefused.codeInterdit);
      await ouvrirVente(t, gw);
      await ajouterArticle(t);
      await choisir(t, 'REM-FICT-10');
      expect(find.text(messageDroitRemise), findsOneWidget);
      await t.pumpAndSettle();
      expect(zoneRemise, findsNothing);
    });
  });

  group('Ticket du serveur (route image)', () {
    late List<List<Raster1Bit>> imprimees;

    setUp(() {
      TicketServeur.oublier();
      ImpressionTicket.reinitialiser();
      imprimees = [];
      ImpressionTicket.imprimeur = (tickets) async {
        final r = ImpressionTicket.rasters(tickets, tickets.first.largeurPoints);
        if (r == null) return 'image illisible.';
        imprimees.add(r);
        return null;
      };
    });
    tearDown(ImpressionTicket.reinitialiser);

    Future<bool?> imprimer(WidgetTester t, _Adaptateur a, {int largeur = 58}) async {
      final dio = Dio(BaseOptions(baseUrl: 'http://serveur.fictif/prestige/api/v1'))..httpClientAdapter = a;
      ImpressionTicket.dioDe = (_) => dio;
      bool? res;
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(
            body: ElevatedButton(
              onPressed: () async => res = await ImpressionTicket.parServeur(c, type: TypeTicketServeur.vno, venteId: 'V-FICT-1', largeur: largeur, apercu: false),
              child: const Text('Imprimer'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('Imprimer'));
      await t.pumpAndSettle();
      return res;
    }

    for (final (mm, points) in [(58, 384), (80, 576)]) {
      testWidgets('$mm mm : images du serveur converties en 1 bit ($points points) et imprimées', (t) async {
        final a = _Adaptateur([_tickets]);
        expect(await imprimer(t, a, largeur: mm), isTrue);
        expect(imprimees.single.single.largeur, points);
        expect(ImpressionTicket.imagesImprimees, 1);
      });
    }

    testWidgets('200 {success:false} : message du serveur tel quel ; « Ticket de l\'application » → gabarit local', (t) async {
      final a = _Adaptateur([(_) => _json({'success': false, 'msg': 'Ticket introuvable : vente fictive non terminée.'})]);
      await imprimer(t, a);
      expect(find.byKey(const ValueKey('ticket-refuse-serveur')), findsOneWidget);
      expect(find.textContaining('Ticket introuvable : vente fictive non terminée.'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('ticket-refuse-local')));
      await t.pumpAndSettle();
      expect(imprimees, isEmpty);
    });

    testWidgets('200 {success:false} puis « Réimprimer » : nouvel essai, ticket du serveur imprimé', (t) async {
      final a = _Adaptateur([(_) => _json({'success': false, 'msg': 'Aucun ticket pour cette vente.'}), _tickets]);
      await imprimer(t, a);
      await t.tap(find.byKey(const ValueKey('ticket-reimprimer')));
      await t.pumpAndSettle();
      expect(a.appels, 2);
      expect(imprimees.length, 1);
    });

    testWidgets('200 {success:false} puis « Fermer » : aucun ticket', (t) async {
      final a = _Adaptateur([(_) => _json({'success': false, 'msg': 'Aucun ticket pour cette vente.'})]);
      await imprimer(t, a);
      await t.tap(find.byKey(const ValueKey('ticket-refuse-fermer')));
      await t.pumpAndSettle();
      expect((a.appels, imprimees.length), (1, 0));
    });

    testWidgets('400 (type inconnu) : gabarit local sans question', (t) async {
      final a = _Adaptateur([(_) => _json({'success': false, 'msg': 'Type de ticket inconnu : vno, vo ou prevente.'}, 400)]);
      expect(await imprimer(t, a), isFalse);
      expect(find.byKey(const ValueKey('ticket-refuse-serveur')), findsNothing);
    });

    testWidgets('404 (serveur d\'aujourd\'hui) : gabarit local, comme 4.15.0', (t) async {
      final a = _Adaptateur([(_) => ResponseBody.fromString('Not Found', 404)]);
      expect(await imprimer(t, a), isFalse);
      expect(DroitsVente.instance.controle(droitRemiseVente), isFalse);
    });
  });
}
