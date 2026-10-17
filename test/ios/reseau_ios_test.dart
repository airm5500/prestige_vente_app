// 4.5.0 — Réseau sur iPhone / iPad : le serveur Prestige est joint en HTTP simple sur le réseau local (adresse IP
// privée saisie dans les réglages). Le client de l'application (Dio → dart:io, sockets) n'est pas soumis à l'App
// Transport Security d'iOS ; l'Info.plist déclare quand même NSAllowsLocalNetworking (et le texte de l'autorisation
// « réseau local » demandée par iOS 14+), sans NSAllowsArbitraryLoads. Vérifié ici avec la plateforme iOS simulée :
// HTTP vers une adresse locale, coupure (« Serveur injoignable ») et reprise.
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/plateforme/capacites.dart';

import '../outils/serveur_json_local.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('HTTP simple vers une adresse IP locale (127.0.0.1) : réponse lue ; coupure puis reprise', () => avecVraiHttp(() async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        expect(CapacitesPlateforme.courant.ios, isTrue);
        final s = ServeurJsonLocal();
        await s.demarrer();
        s.routes['GET /officine'] = (_) => const ReponseLocale([
          {'nomComplet': 'PHARMACIE TEST'}
        ]);
        expect(s.base, startsWith('http://127.0.0.1:'));
        final dio = Dio(BaseOptions(baseUrl: s.base, connectTimeout: const Duration(seconds: 3)));
        final r = await dio.get<List<dynamic>>('/officine');
        expect(r.statusCode, 200);
        expect((r.data!.first as Map)['nomComplet'], 'PHARMACIE TEST');
        // Le client de l'application (même adresse, HTTP) : informations de l'officine.
        final officine = await ApiService(baseUrl: s.base).fetchOfficineInfo();
        expect(officine?.nomComplet, 'PHARMACIE TEST');
        await s.arreter();
        await expectLater(dio.get<Object>('/officine'), throwsA(isA<DioException>()));
        await s.demarrer();
        expect((await dio.get<Object>('/officine')).statusCode, 200, reason: 'reprise');
        await s.arreter();
      }));
}
