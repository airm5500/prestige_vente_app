// Socle des ventes : passerelle serveur (messages du serveur conservés, panne ≠ liste vide),
// file d'opérations (pas de double création de vente), contrôles de saisie, vente en cours mémorisée.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/ventes/core/pending_sale_store.dart';
import 'package:prestige_vente_app/ventes/core/sale_op_queue.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_input.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RealHttp extends HttpOverrides {}

Future<void> _real(Future<void> Function() body) => HttpOverrides.runWithHttpOverrides(body, _RealHttp());

void main() {
  group('Passerelle', () {
    late HttpServer server;
    final bodies = <String, dynamic>{};
    final received = <String>[];

    setUp(() async {
      received.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final payload = await utf8.decoder.bind(req).join();
        received.add('${req.method} ${req.uri.path} $payload');
        final r = req.response;
        final key = req.uri.path.replaceFirst('/api', '');
        final b = bodies[key];
        if (b == null) {
          r.statusCode = 500;
        } else {
          r.headers.contentType = ContentType.json;
          r.write(jsonEncode(b));
        }
        await r.close();
      });
    });
    tearDown(() => server.close(force: true));

    DioVenteGateway gw() => DioVenteGateway(ApiService(baseUrl: 'http://127.0.0.1:${server.port}/api'));

    test('ajout du 1ᵉʳ article : identifiant de vente lu, mêmes données qu\'avant', () => _real(() async {
          bodies['/vente/add/vno'] = {'success': true, 'data': {'lgPREENREGISTREMENTID': 'V1'}};
          final r = await gw().addItemVno(produitId: 'P1', qte: 2, itemPu: 1500, prevente: true);
          expect(r.valueOrNull, 'V1');
          final sent = jsonDecode(received.single.split(' ').skip(2).join(' ')) as Map;
          expect(sent['produitId'], 'P1');
          expect(sent['qte'], 2);
          expect(sent['qteServie'], 2);
          expect(sent['prevente'], true);
          expect(sent['typeVenteId'], '1');
          expect(sent['venteId'], isNull);
        }));

    test('refus du serveur : SON message est conservé', () => _real(() async {
          bodies['/vente/add/assurance'] = {'success': false, 'msg': 'Plafond atteint pour ce client'};
          final r = await gw().addItemAssurance(
            produitId: 'P1',
            qte: 1,
            itemPu: 100,
            clientId: 'C',
            ayantDroitId: 'A',
            natureVenteId: '1',
            typeVenteId: '2',
            userVendeurId: 'U',
            tierspayants: [(compteTp: 'T1', numBon: 'B1', taux: 80)],
          );
          expect(r, isA<VenteRefused<String>>());
          expect(r.message, 'Plafond atteint pour ce client');
        }));

    test('caisse fermée reconnue à la clôture', () => _real(() async {
          bodies['/vente/terminerprevente/V1'] = {
            'success': false,
            'msg': 'Désolé votre caisse est fermée. Veuillez l\'ouvrir avant de proceder à validation'
          };
          final r = await gw().terminerPrevente('V1');
          expect((r as VenteRefused).caisseFermee, isTrue);
        }));

    test('panne : échec explicite, jamais une liste vide', () => _real(() async {
          final r = await gw().searchProducts('doli'); // 500
          expect(r, isA<VenteFailed<dynamic>>());
          expect(r.valueOrNull, isNull);
          final port = server.port;
          await server.close(force: true);
          final down = await DioVenteGateway(ApiService(baseUrl: 'http://127.0.0.1:$port/api')).searchProducts('doli');
          expect(down.message, contains('injoignable'));
          expect(down.uncertain, isFalse); // rien n'a pu partir
        }));

    test('écriture en erreur serveur : marquée « peut-être appliquée »', () => _real(() async {
          final r = await gw().removeItem('L1'); // 500
          expect(r.uncertain, isTrue);
        }));

    test('liste vide renvoyée seulement si le serveur a répondu', () => _real(() async {
          bodies['/vente/search'] = {'data': []};
          final r = await gw().searchProducts('zzz');
          expect(r.valueOrNull, isEmpty);
        }));
  });

  group('File d\'opérations', () {
    test('deux scans rapides du 1ᵉʳ produit : une seule vente créée', () async {
      final q = SaleOpQueue();
      String? venteId;
      var creations = 0;
      Future<void> add() => q.run(() async {
            if (venteId == null) {
              creations++;
              await Future.delayed(const Duration(milliseconds: 30));
              venteId = 'V$creations';
            }
          });
      await Future.wait([add(), add(), add()]);
      expect(creations, 1);
      expect(venteId, 'V1');
      expect(q.busy, isFalse);
    });

    test('une erreur n\'arrête pas la file', () async {
      final q = SaleOpQueue();
      final f1 = q.run<int>(() async => throw StateError('x'));
      final f2 = q.run<int>(() async => 2);
      await expectLater(f1, throwsStateError);
      expect(await f2, 2);
    });
  });

  group('Saisie', () {
    test('quantité, prix, recherche, bons', () {
      expect(VenteInput.parseQuantity('0'), isNull);
      expect(VenteInput.parseQuantity('-3'), isNull);
      expect(VenteInput.parseQuantity('10000'), isNull);
      expect(VenteInput.parseQuantity(' 12 '), 12);
      expect(VenteInput.parsePrice('-1'), isNull);
      expect(VenteInput.parsePrice('0'), 0);
      expect(VenteInput.parsePrice('1000000000'), isNull);
      expect(VenteInput.cleanQuery('  doli\u0007prane\n'), 'doliprane');
      expect(VenteInput.cleanBon(' B 12 '), 'B 12');
      expect(VenteInput.hasDuplicateBons({'T1': 'ab12', 'T2': ' AB12'}), isTrue);
      expect(VenteInput.hasDuplicateBons({'T1': 'ab12', 'T2': ''}), isFalse);
      expect(VenteInput.parseTaux('0', min: 1), isNull);
      expect(VenteInput.parseTaux('101'), isNull);
      expect(VenteInput.cleanName('  KOUASSI   Awa '), 'KOUASSI Awa');
    });
  });

  test('vente en cours mémorisée puis effacée', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await PendingSaleStore.load(VenteMenu.prevente), isNull);
    await PendingSaleStore.save(
      VenteMenu.prevente,
      PendingSale(venteId: 'V9', reference: 'PV-9', itemCount: 3, total: 5400, savedAt: DateTime(2026, 10, 10), extra: {'k': 'v'}),
    );
    final p = await PendingSaleStore.load(VenteMenu.prevente);
    expect(p!.venteId, 'V9');
    expect(p.total, 5400);
    expect(p.extra['k'], 'v');
    expect(await PendingSaleStore.load(VenteMenu.assurance), isNull);
    await PendingSaleStore.clear(VenteMenu.prevente);
    expect(await PendingSaleStore.load(VenteMenu.prevente), isNull);
  });
}
