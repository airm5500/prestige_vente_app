// PERFORMANCE — 4.7.0 : l'en-tête X-Poste est lu à CHAQUE requête : valeur gardée (nettoyage et encodage refaits
// seulement quand le nom ou le modèle change), coût négligeable, aucune requête de plus.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/serveur/nom_appareil.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NomAppareil.reinitialiser();
  });

  test('20 000 requêtes : en-tête posé valeur gardée, en moins de 400 ms', () async {
    final n = NomAppareil.instance..modele = () => 'SUNMI V2s';
    await n.charger();
    await n.enregistrer('Caisse mobile 1');
    final i = IntercepteurPoste();
    final h = _Suivant();
    final sw = Stopwatch()..start();
    for (var k = 0; k < 20000; k++) {
      i.onRequest(RequestOptions(path: '/vente/add/vno'), h);
    }
    sw.stop();
    expect(h.dernier?.headers[entetePoste], 'Caisse%20mobile%201');
    expect(sw.elapsedMilliseconds, lessThan(400), reason: '${sw.elapsedMilliseconds} ms');
  });

  test('nom très long (10 000 caractères) : nettoyé en moins de 50 ms', () {
    final sw = Stopwatch()..start();
    final r = nettoyerNomPoste('Caisse éèà #/! ' * 700);
    sw.stop();
    expect(r!.length, lessThanOrEqualTo(longueurMaxPoste));
    expect(sw.elapsedMilliseconds, lessThan(50));
  });
}

class _Suivant extends RequestInterceptorHandler {
  RequestOptions? dernier;
  @override
  void next(RequestOptions requestOptions) => dernier = requestOptions;
}
