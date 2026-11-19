// ERGONOMIE — 4.15.1 : réponse du serveur à la demande 63, données FICTIVES :
//  - fenêtre « Ticket non imprimé » (200 {success:false}) : message long du serveur lisible, trois boutons ≥ 48 dp,
//    aucun débordement de 320 dp à la tablette, texte ×1.3 ;
//  - liste des remises avec « SANS REMISE » (serveur avec la demande 63) : lignes ≥ 48 dp, aucun débordement.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/droits/droits_vente.dart';
import 'package:prestige_vente_app/services/impression_ticket.dart';
import 'package:prestige_vente_app/services/ticket_serveur.dart';
import 'package:prestige_vente_app/ventes/common/remise_vente.dart';

import 'client_vente_test.dart' show ouvrirVente, ajouterArticle;
import 'demande63_ecrans_test.dart' show FauxVenteRemise63;
import 'remise_vente_test.dart' show choisirRemise;

const _tailles = [Size(320, 640), Size(360, 720), Size(960, 600)];

void _taille(WidgetTester t, Size s) {
  t.view.physicalSize = s * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
}

class _Refus implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async => ResponseBody.fromString(
      jsonEncode({'success': false, 'msg': 'Ticket introuvable : la vente fictive V-FICT-000000000001 n\'a aucun mouvement de caisse (vente non terminée).'}),
      200,
      headers: {Headers.contentTypeHeader: ['application/json']});
  @override
  void close({bool force = false}) {}
}

void main() {
  setUp(() {
    TicketServeur.oublier();
    DroitsVente.instance.fixer(null);
    DroitsVente.instance.oublierControles();
  });
  tearDown(ImpressionTicket.reinitialiser);

  for (final s in _tailles) {
    for (final texte in [1.0, 1.3]) {
      testWidgets('${s.width.toInt()} dp, texte ×$texte : « Ticket non imprimé » lisible, boutons ≥ 48 dp', (t) async {
        _taille(t, s);
        final dio = Dio(BaseOptions(baseUrl: 'http://serveur.fictif/prestige/api/v1'))..httpClientAdapter = _Refus();
        ImpressionTicket.dioDe = (_) => dio;
        await t.pumpWidget(MaterialApp(
          builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(texte)), child: w!),
          home: Builder(
            builder: (c) => Scaffold(
              body: ElevatedButton(
                onPressed: () => ImpressionTicket.parServeur(c, type: TypeTicketServeur.vno, venteId: 'V-FICT-1', largeur: 58, apercu: false),
                child: const Text('Imprimer'),
              ),
            ),
          ),
        ));
        await t.tap(find.text('Imprimer'));
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('ticket-refuse-serveur')), findsOneWidget);
        expect(t.takeException(), isNull, reason: 'aucun débordement');
        for (final k in ['ticket-refuse-fermer', 'ticket-refuse-local', 'ticket-reimprimer']) {
          final r = t.getRect(find.byKey(ValueKey(k)));
          expect(r.height, greaterThanOrEqualTo(47.9), reason: k);
          expect(r.right, lessThanOrEqualTo(s.width), reason: k);
        }
      });
    }

    testWidgets('${s.width.toInt()} dp : liste des remises avec « SANS REMISE », lignes ≥ 48 dp, aucun débordement', (t) async {
      _taille(t, s);
      DroitsVente.instance.fixer({'P_SM_VENTE', droitRemiseVente});
      await ouvrirVente(t, FauxVenteRemise63());
      await ajouterArticle(t);
      await t.tap(choisirRemise);
      await t.pumpAndSettle();
      final sans = find.byKey(const ValueKey('remise-option-0'));
      expect(sans, findsOneWidget);
      expect(t.getRect(sans).height, greaterThanOrEqualTo(47.9));
      expect(find.text('SANS REMISE'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
