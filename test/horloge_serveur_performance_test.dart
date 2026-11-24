// 5.5.0 — Performance du contrôle « heure du serveur fausse » (transmission du 24/11/2026) : aucune requête de plus en
// fonctionnement normal (horloge/public lu seulement après un 423), contrôle de chaque réponse négligeable, une seule
// requête par écriture refusée (aucune relance). Données fictives uniquement.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/serveur/horloge_serveur.dart';
import 'package:prestige_vente_app/serveur/panne_serveur.dart';

class _Transport implements HttpClientAdapter {
  int appels = 0;
  int statut = 200;
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    appels++;
    final corps = statut == 423 ? {'success': false, 'horlogeBloquee': true, 'msg': 'Refus fictif'} : {'success': true, 'data': []};
    return ResponseBody.fromString(jsonEncode(corps), statut, headers: {'content-type': ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUp(HorlogeServeur.instance.reinitialiser);

  test('100 000 réponses ordinaires contrôlées en moins de 300 ms', () {
    final corps = {'success': true, 'data': List.generate(50, (i) => {'id': i})};
    final chrono = Stopwatch()..start();
    for (var i = 0; i < 100000; i++) {
      horlogeBloqueeDe(i.isEven ? 200 : 404, corps);
    }
    expect(chrono.elapsedMilliseconds, lessThan(300));
  });

  test('fonctionnement normal : aucune requête de plus ; écriture refusée : une seule requête', () async {
    final t = _Transport();
    final d = avecDeploiement(Dio(BaseOptions(baseUrl: 'http://serveur-fictif/prestige/api/v1', validateStatus: (_) => true)))
      ..httpClientAdapter = t;
    for (var i = 0; i < 20; i++) {
      await d.post('/vente/add/item', data: {});
      await HorlogeServeur.instance.verifierSiBloquee(d);
    }
    expect(t.appels, 20, reason: 'aucune lecture de horloge/public quand rien n\'est bloqué');
    t.statut = 423;
    await d.post('/vente/cloturer/vno', data: {});
    expect(t.appels, 21);
    expect(HorlogeServeur.instance.bloquee, isTrue);
  });
}
