// Préfixe des routes des patchs serveur de l'appli de vente (H4, H5, O4, O5) : `/app-vente` (patchs actuels, session
// habituelle), repli sur l'ancien `/mobile` (premières versions des patchs, serveur de test), aucun (serveur sans patch).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/horsligne/routes_app_vente.dart';
import 'package:prestige_vente_app/ordonnances/o4/partage_o4.dart';
import 'package:prestige_vente_app/ordonnances/o5/lecture_avancee.dart';

class _RealHttp extends HttpOverrides {}

Future<void> _real(Future<void> Function() body) => HttpOverrides.runWithHttpOverrides(body, _RealHttp());

typedef _Rep = ({int status, Object? body});

void main() {
  setUp(RoutesAppVente.vider);

  group('routes', () {
    test('chemins sous le préfixe actuel et l\'ancien', () {
      expect(RoutesAppVente.capacites(), '/app-vente/capacites');
      expect(RoutesAppVente.capacites(RoutesAppVente.ancienPrefixe), '/mobile/capacites');
      expect(RoutesAppVente.clientRef('HL2-a b'), '/app-vente/client-ref/HL2-a%20b');
      expect(RoutesAppVente.clientRef('HL3-x', '/mobile'), '/mobile/client-ref/HL3-x');
      expect(RoutesAppVente.catalogueChangements(), '/app-vente/catalogue/changements');
      expect(RoutesAppVente.ordonnancesCorrections(), '/app-vente/ordonnances/corrections');
      expect(RoutesAppVente.lectureAvancee(), '/app-vente/ordonnances/lecture-avancee');
      expect(PartageO4.route, '/app-vente/ordonnances/corrections');
      expect(LectureAvancee.route, '/app-vente/ordonnances/lecture-avancee');
      expect(RoutesAppVente.prefixePour('http://inconnu/api/v1'), '/app-vente', reason: 'défaut : préfixe actuel');
    });
  });

  group('lireCapacites', () {
    Future<({List<String> appels, int status, String? prefixe})> lire(Map<String, _Rep> serveur, {String cle = 'srv'}) async {
      final appels = <String>[];
      final r = await RoutesAppVente.lireCapacites(cle, (chemin) async {
        appels.add(chemin);
        return serveur[chemin] ?? (status: 404, body: <String, dynamic>{});
      });
      return (appels: appels, status: r.status, prefixe: r.prefixe);
    }

    const ok = (status: 200, body: {'success': true, 'clientRef': true});
    const expire = (status: 401, body: {'success': false, 'expire': true});

    test('nouveau préfixe : une seule requête', () async {
      final r = await lire({'/app-vente/capacites': ok, '/mobile/capacites': expire});
      expect(r.appels, ['/app-vente/capacites']);
      expect(r.prefixe, '/app-vente');
      expect(RoutesAppVente.prefixePour('srv'), '/app-vente');
      expect(RoutesAppVente.connu('srv'), isTrue);
    });

    test('ancien préfixe : 404 puis repli sur /mobile/capacites', () async {
      final r = await lire({'/mobile/capacites': ok});
      expect(r.appels, ['/app-vente/capacites', '/mobile/capacites']);
      expect(r.prefixe, '/mobile');
      expect(RoutesAppVente.prefixePour('srv'), '/mobile');
      expect(RoutesAppVente.prefixePour('autre'), '/app-vente', reason: 'retenu par serveur');
    });

    test('aucun (serveur à jour sans les patchs) : 404 puis 401 « expire » rendus tels quels', () async {
      final r = await lire({'/mobile/capacites': expire});
      expect(r.appels, ['/app-vente/capacites', '/mobile/capacites']);
      expect(r.status, 401);
      expect(r.prefixe, isNull);
      expect(RoutesAppVente.connu('srv'), isFalse);
    });

    test('nouveau chemin sans session (401) ou en erreur (500) : pas de repli (indéterminé)', () async {
      for (final rep in [(status: 401, body: 'Veuillez vous connecter') as _Rep, (status: 500, body: null) as _Rep]) {
        final r = await lire({'/app-vente/capacites': rep, '/mobile/capacites': ok});
        expect(r.appels, ['/app-vente/capacites']);
        expect(r.status, rep.status);
        expect(r.prefixe, isNull);
      }
    });

    test('panne réseau : l\'exception remonte (indéterminé pour l\'appelant)', () async {
      expect(RoutesAppVente.lireCapacites('srv', (_) async => throw const SocketException('injoignable')), throwsA(isA<SocketException>()));
    });

    test('serveur mis à jour (/mobile → /app-vente) : le nouveau préfixe remplace l\'ancien', () async {
      await lire({'/mobile/capacites': ok});
      expect(RoutesAppVente.prefixePour('srv'), '/mobile');
      await lire({'/app-vente/capacites': ok});
      expect(RoutesAppVente.prefixePour('srv'), '/app-vente');
    });
  });

  group('O4 / O5 : routes Dio selon le préfixe détecté (serveur local)', () {
    late HttpServer server;
    final chemins = <String>[];
    String? prefixe;

    setUp(() async {
      chemins.clear();
      prefixe = '/app-vente';
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        await req.fold<int>(0, (n, b) => n + b.length);
        final p = req.uri.path.replaceFirst('/api', '');
        chemins.add('${req.method} $p');
        final r = req.response..headers.contentType = ContentType.json;
        if (prefixe != null && p == '$prefixe/capacites') {
          r.write(jsonEncode({'success': true, 'ordonnanceCorrections': true, 'lectureAvancee': true}));
        } else if (p == '/mobile/capacites') {
          r.statusCode = 401;
          r.write(jsonEncode({'success': false, 'expire': true}));
        } else if (prefixe != null && p.startsWith('$prefixe/ordonnances/')) {
          r.write(jsonEncode({'success': true, 'data': [], 'lignes': []}));
        } else {
          r.statusCode = 404;
          r.write('{}');
        }
        await r.close();
      });
    });
    tearDown(() => server.close(force: true));

    String base() => 'http://127.0.0.1:${server.port}/api';

    for (final cas in ['/app-vente', '/mobile', null]) {
      test('serveur ${cas ?? 'sans patch'}', () => _real(() async {
            prefixe = cas;
            final o4 = DioServeurCorrections(ApiService(baseUrl: base()));
            final cap = await o4.capacites();
            expect(PartageO4.capaciteDepuisReponse(cap.status, cap.body), cas != null);
            if (cas != null) {
              expect((await o4.envoyer(const [])).status, 200);
              expect((await o4.changements({'depuis': '2026-10-11 00:00:00'})).status, 200);
              final o5 = DioServeurLectureAvancee(ApiService(baseUrl: base()));
              expect((await o5.lire(Uint8List.fromList([0xff, 0xd8, 0xff]))).status, 200);
            }
            expect(chemins, [
              'GET /app-vente/capacites',
              if (cas != '/app-vente') 'GET /mobile/capacites',
              if (cas != null) ...['POST $cas/ordonnances/corrections', 'GET $cas/ordonnances/corrections', 'POST $cas/ordonnances/lecture-avancee'],
            ]);
          }));
    }
  });
}
