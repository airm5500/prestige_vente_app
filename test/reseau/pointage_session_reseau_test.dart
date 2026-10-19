// 4.6.0 (demande 51) — « Mon pointage » sous la session de l'application, vrai HTTP vers le faux serveur Prestige :
// cookie de la session et X-Client-Ref envoyés ; même clé renvoyée = un seul pointage ; coupure → « serveur
// injoignable », reprise ensuite ; serveur sans v1/rh/moi → voie v1/mobile. Données fictives.
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/rh/mobile_api.dart';
import 'package:prestige_vente_app/rh/rh_api.dart';
import 'package:prestige_vente_app/rh/rh_models.dart';

import '../outils/faux_serveur_prestige.dart';

Future<(FauxServeurPrestige, MobileApi, DioRhServeur)> _demarrer({bool session = true}) async {
  final s = FauxServeurPrestige()..activerPointageMobile({DonneesFictives.login: 'TEST Awa'});
  if (session) s.activerPointageSession({DonneesFictives.login: 'TEST Awa'});
  await s.demarrer();
  addTearDown(s.arreter);
  await DioClient.cookieJar.deleteAll();
  addTearDown(DioClient.cookieJar.deleteAll);
  expect(await ApiService(baseUrl: s.base).login(DonneesFictives.login, DonneesFictives.motDePasse), isNotNull);
  final rh = DioRhServeur(() => s.base);
  final m = MobileApi(
    transport: DioTransportMobile(() => s.base),
    transportSession: TransportSessionRh(() => rh),
    coffre: CoffreJetonMemoire(),
    appareil: () => 'test-reseau',
    nomAppareil: () => 'Test réseau',
  );
  return (s, m, rh);
}

void main() {
  test('session : cookie et X-Client-Ref envoyés ; même clé deux fois = un seul pointage', () async {
    await avecVraiHttp(() async {
      final (s, m, rh) = await _demarrer();
      await m.lier(DonneesFictives.login);
      expect(m.voieSession, isTrue);
      expect((await m.pointer(sens: SensPointage.entree)).ok, isTrue);
      final r = s.recuesSur('/rh/moi/pointages').single;
      expect(r.jsessionid, isNotNull, reason: 'session de l\'application');
      expect(r.clientRef, startsWith('PT-'));
      // Renvoi de la même demande (réponse perdue) : le serveur rend la même réponse, un seul pointage.
      final again = await rh.requete('POST', '/rh/moi/pointages', corps: {'sens': 'ENTREE'}, clientRef: r.clientRef);
      expect(again.body?['success'], isTrue);
      expect(s.pointagesSession, hasLength(1));
      expect(s.connexionsMobile, isEmpty);
    });
  });

  test('coupure : « serveur injoignable », puis reprise ; serveur sans v1/rh/moi : voie v1/mobile', () async {
    await avecVraiHttp(() async {
      final (s, m, _) = await _demarrer();
      await m.lier(DonneesFictives.login);
      await s.couper();
      await expectLater(m.pointer(sens: SensPointage.sortie), throwsA(isA<MobileHorsLigne>()));
      await s.retablir();
      expect((await m.pointer(sens: SensPointage.sortie)).ok, isTrue);
      expect(s.pointagesSession.map((p) => p.sens), ['SORTIE']);
    });
    await avecVraiHttp(() async {
      final (s, m, _) = await _demarrer(session: false);
      await m.lier(DonneesFictives.login);
      expect(m.voieSession, isFalse, reason: '404 : voie v1/mobile');
      expect(await m.reprendre(), isNull, reason: 'connexion v1/mobile demandée comme avant');
      expect(s.recuesSur('/rh/moi'), hasLength(1));
    });
  });
}
