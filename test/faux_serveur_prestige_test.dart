// Auto-contrôle du faux serveur Prestige (test/outils/faux_serveur_prestige.dart) : mêmes comportements en réseau
// local et en mémoire (sessions JSESSIONID, refus 401 / 403 « Veuillez vous connecter », routes scriptées
// prioritaires, refus métier, 5xx, délai, coupure), compatibilité de ServeurJsonLocal.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_test/flutter_test.dart';

import 'outils/faux_serveur_prestige.dart';

Dio _client(String base, {Duration delai = const Duration(seconds: 5)}) =>
    Dio(BaseOptions(baseUrl: base, validateStatus: (_) => true, connectTimeout: delai, receiveTimeout: delai))..interceptors.add(CookieManager(CookieJar()));

/// Attente d'une réponse : directe en réseau local, image par image (temps simulé) en mémoire.
typedef Attente = Future<Response<dynamic>> Function(Future<Response<dynamic>> f);

Future<Response<dynamic>> _direct(Future<Response<dynamic>> f) => f;

Attente _parImages(WidgetTester t) => (f) async {
      Response<dynamic>? v;
      Object? e;
      var fini = false;
      f.then<void>((x) {
        v = x;
      }, onError: (Object x) {
        e = x;
      }).whenComplete(() => fini = true);
      for (var i = 0; !fini && i < 2000; i++) {
        await t.pump(const Duration(milliseconds: 10));
      }
      if (e != null) throw e!;
      return v!;
    };

/// Scénario commun aux deux transports.
Future<void> _scenario(FauxServeurPrestige s, Dio d0, Attente w) async {
  final d = _Attendu(d0, w);
  // Sans session : refusé, requête non exécutée.
  var executee = false;
  s.routes['GET /stock/ligne'] = (_) {
    executee = true;
    return FauxServeurPrestige.ok({'success': true, 'stock': 3});
  };
  var r = await d.get('/stock/ligne');
  expect((r.statusCode, r.data), (401, 'Veuillez vous connecter'));
  expect(executee, isFalse);
  s.refusEn403 = true;
  r = await d.get('/stock/ligne');
  expect((r.statusCode, r.data), (403, 'Veuillez vous connecter'));
  s.refusEn403 = false;

  // Routes publiques sans cookie.
  expect((await d.get('/licence/find')).statusCode, 200);
  expect((await d.get('/officine')).data, isA<List>());

  // Connexion : identifiants refusés puis acceptés ; cookie posé et contrôlé.
  r = await d.post('/user/auth', data: {'login': DonneesFictives.login, 'password': 'faux'});
  expect(r.data['success'], isFalse);
  r = await d.post('/user/auth', data: {'login': DonneesFictives.login, 'password': DonneesFictives.motDePasse});
  expect(r.data['success'], isTrue);
  expect(s.derniereSession, isNotNull);
  r = await d.get('/stock/ligne');
  expect(r.data['stock'], 3);
  expect(s.recuesSur('/stock/ligne').last.jsessionid, s.derniereSession);

  // Nouvelle connexion = NOUVEAU JSESSIONID.
  final premiere = s.derniereSession;
  await d.post('/user/auth', data: {'login': DonneesFictives.login, 'password': DonneesFictives.motDePasse});
  expect(s.derniereSession, isNot(premiere));

  // Refus métier, 5xx, route inconnue.
  s.routes['POST /vente/add/vno'] = (_) => FauxServeurPrestige.refus('Stock insuffisant', code: 'STOCK');
  r = await d.post('/vente/add/vno', data: {});
  expect((r.statusCode, r.data['success'], r.data['code']), (200, false, 'STOCK'));
  s.routes['GET /stock/ligne'] = (_) => FauxServeurPrestige.erreurServeur(503);
  expect((await d.get('/stock/ligne')).statusCode, 503);
  expect((await d.get('/route/inexistante')).statusCode, 404);

  // Expiration des sessions.
  s.expirerSessions();
  expect((await d.get('/stock/ligne')).statusCode, 401);
}

/// Client Dio dont chaque requête passe par l'attente du transport.
class _Attendu {
  final Dio d;
  final Attente w;
  _Attendu(this.d, this.w);
  Future<Response<dynamic>> get(String p) => w(d.get(p));
  Future<Response<dynamic>> post(String p, {Object? data}) => w(d.post(p, data: data));
}

void main() {
  test('réseau local : sessions, refus, scripts, coupure puis reprise', () => avecVraiHttp(() async {
        final s = FauxServeurPrestige();
        await s.demarrer();
        addTearDown(s.arreter);
        final d = _client(s.base);
        await _scenario(s, d, _direct);
        await s.couper();
        await expectLater(d.get('/licence/find'), throwsA(isA<DioException>().having((e) => e.type, 'type', DioExceptionType.connectionError)));
        await s.retablir();
        expect((await d.get('/licence/find')).statusCode, 200);
      }));

  test('réseau local : délai de réponse dépassé côté client', () => avecVraiHttp(() async {
        final s = FauxServeurPrestige();
        await s.demarrer();
        addTearDown(s.arreter);
        s.routes['GET /licence/find'] = (_) => FauxServeurPrestige.lent(DonneesFictives.licence(), const Duration(milliseconds: 600));
        final d = _client(s.base, delai: const Duration(milliseconds: 200));
        await expectLater(d.get('/licence/find'), throwsA(isA<DioException>().having((e) => e.type, 'type', DioExceptionType.receiveTimeout)));
      }));

  testWidgets('en mémoire : même scénario, coupure et délai en temps simulé', (t) async {
    final s = FauxServeurPrestige()..installerEnMemoire();
    addTearDown(s.desinstaller);
    expect(s.base, 'http://prestige.test:8080/prestige/api/v1');
    final d = _client(s.base);
    final w = _parImages(t);
    await _scenario(s, d, w);
    await s.couper();
    Object? coupure;
    try {
      await w(d.get('/licence/find'));
    } catch (e) {
      coupure = e;
    }
    expect(coupure, isA<DioException>().having((e) => e.error, 'erreur', isA<SocketException>()));
    await s.retablir();
    s.latence = const Duration(seconds: 8);
    Response<dynamic>? lente;
    Object? erreur;
    d.get('/licence/find').then<void>((r) {
      lente = r;
    }, onError: (Object e) {
      erreur = e;
    });
    await t.pump(const Duration(seconds: 6));
    expect(lente, isNull);
    expect(erreur, isA<DioException>().having((e) => e.type, 'type', DioExceptionType.receiveTimeout), reason: 'délai de 5 s du client dépassé');
    await t.pump(const Duration(seconds: 5));
  });

  test('ServeurJsonLocal d\'origine : interface inchangée (routes par suffixe, en-têtes, recuesSur)', () => avecVraiHttp(() async {
        final s = ServeurJsonLocal();
        await s.demarrer();
        addTearDown(s.arreter);
        s.routes['GET /ok'] = (r) => ReponseLocale({'cookie': r.cookie}, entetes: const {'x-test': '1'});
        final r = await Dio(BaseOptions(validateStatus: (_) => true)).get('${s.base}/ok', options: Options(headers: {'cookie': 'JSESSIONID=abc'}));
        expect(r.data, {'cookie': 'JSESSIONID=abc'});
        expect(r.headers.value('x-test'), '1');
        expect(s.recuesSur('/ok').single.jsessionid, 'abc');
        expect((await Dio(BaseOptions(validateStatus: (_) => true)).get('${s.base}/autre')).statusCode, 404);
      }));
}
