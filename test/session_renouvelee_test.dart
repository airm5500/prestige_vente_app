// Session renouvelée à la connexion (serveur Prestige, audit du 12/10) : la lecture de la licence AVANT la
// connexion donne un premier JSESSIONID, la connexion en donne un NOUVEAU. Seul le nouveau doit être envoyé
// ensuite, sinon toutes les routes de données répondent 401.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';

class _RealHttp extends HttpOverrides {}

void main() {
  test('après POST /user/auth, seul le cookie de la réponse de connexion est envoyé', () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final cookiesVus = <String>[];
      server.listen((req) async {
        final res = req.response..headers.contentType = ContentType.json;
        final path = req.uri.path;
        if (path.endsWith('/licence/find')) {
          // Premier cookie, posé avec un chemin différent de celui de la connexion (cas le plus piégeux).
          res.headers.add('set-cookie', 'JSESSIONID=ancien; Path=/prestige; HttpOnly');
          res.write(jsonEncode({'id': 'x', 'date_start': '2026-01-01', 'date_end': '2027-01-01', 'type_licence': '1'}));
        } else if (path.endsWith('/user/auth')) {
          res.headers.add('set-cookie', 'JSESSIONID=nouveau; Path=/prestige/; HttpOnly');
          res.write(jsonEncode({'success': true, 'str_LOGIN': 'admin', 'str_USER_ID': 'u1', 'str_FIRST_NAME': 'A', 'str_LAST_NAME': 'B'}));
        } else if (path.endsWith('/officine')) {
          final c = req.headers.value('cookie') ?? '';
          cookiesVus.add(c);
          if (c.contains('JSESSIONID=nouveau') && !c.contains('JSESSIONID=ancien')) {
            res.write(jsonEncode([{'str_NOM_ABREGE': 'Pharmacie Démo'}]));
          } else {
            res.statusCode = 401;
            res.write('"Veuillez vous connecter"');
          }
        } else {
          res.statusCode = 404;
        }
        await res.close();
      });
      try {
        await DioClient.cookieJar.deleteAll();
        final api = ApiService(baseUrl: 'http://127.0.0.1:${server.port}/prestige/api/v1');
        await api.lookupLicence();
        final user = await api.login('admin', 'secret');
        expect(user, isNotNull);
        await api.fetchOfficineInfo();
        expect(cookiesVus, isNotEmpty);
        expect(cookiesVus.last, contains('JSESSIONID=nouveau'));
        expect(cookiesVus.last, isNot(contains('JSESSIONID=ancien')),
            reason: 'l\'ancien cookie (lecture de la licence) ne doit plus être envoyé après la connexion');
      } finally {
        await server.close(force: true);
        await DioClient.cookieJar.deleteAll();
      }
    }, _RealHttp());
  });
}
