// RÉSEAU — 4.7.0 : en-tête X-Poste (nom de cet appareil) en vrai HTTP vers le faux serveur Prestige :
//  - connexion (ApiService / DioClient), client JSON (ClientPrestige), vérification du déploiement (GET /officine
//    après un 404 Payara) : en-tête présent, relu à l'identique après décodage (comme URLDecoder côté serveur) ;
//  - coupure puis retour du serveur : toujours envoyé ;
//  - aucun nom (marque et modèle inconnus, rien de saisi) : aucun en-tête, le serveur garde le nom réseau.
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/serveur/client_prestige.dart';
import 'package:prestige_vente_app/serveur/nom_appareil.dart';
import 'package:prestige_vente_app/serveur/panne_serveur.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../outils/faux_serveur_prestige.dart';

void main() {
  late FauxServeurPrestige srv;
  setUp(() => avecVraiHttp(() async {
        SharedPreferences.setMockInitialValues({});
        NomAppareil.reinitialiser();
        NomAppareil.instance.modele = () => 'SUNMI V2s';
        await NomAppareil.instance.charger();
        srv = FauxServeurPrestige();
        await srv.demarrer();
        SondeDeploiement.sondes = 0;
        await DioClient.cookieJar.deleteAll();
      }));
  tearDown(() => avecVraiHttp(() async {
        await srv.arreter();
        await DioClient.cookieJar.deleteAll();
        NomAppareil.reinitialiser();
      }));

  test('connexion, client JSON, vérification du déploiement : X-Poste relu à l\'identique', () => avecVraiHttp(() async {
        await NomAppareil.instance.enregistrer('Comptoir é-2');
        expect(await ApiService(baseUrl: srv.base).login(DonneesFictives.login, DonneesFictives.motDePasse), isNotNull);
        final auth = srv.recuesSur('/user/auth').last;
        expect(auth.poste, 'Comptoir%20%C3%A9-2');
        expect(Uri.decodeComponent(auth.poste), 'Comptoir é-2');
        srv.routes['GET /posos/droits'] = (_) => FauxServeurPrestige.payara404;
        final client = ClientPrestige(() => srv.base);
        await expectLater(client.get('/posos/droits'), throwsA(isA<ErreurHttp>()));
        expect(SondeDeploiement.sondes, 1);
        expect(srv.recuesSur('/posos/droits').last.poste, 'Comptoir%20%C3%A9-2');
        expect(srv.recuesSur('/officine').last.poste, 'Comptoir%20%C3%A9-2', reason: 'vérification du déploiement');
        for (final r in srv.recues) {
          expect(r.poste, isNotEmpty, reason: '$r');
        }
      }));

  test('coupure puis retour du serveur : en-tête toujours envoyé (nom par défaut)', () => avecVraiHttp(() async {
        final api = ApiService(baseUrl: srv.base);
        expect(await api.login(DonneesFictives.login, DonneesFictives.motDePasse), isNotNull);
        await srv.couper();
        final client = ClientPrestige(() => srv.base, delaiReponse: const Duration(seconds: 2));
        await expectLater(client.get('/officine'), throwsA(isA<Object>()));
        await srv.retablir();
        await DioClient.cookieJar.deleteAll();
        expect(await api.login(DonneesFictives.login, DonneesFictives.motDePasse), isNotNull, reason: 'reprise');
        expect(srv.recues.last.poste, 'SUNMI%20V2s');
        for (final r in srv.recues) {
          expect(r.poste, 'SUNMI%20V2s', reason: '$r');
        }
      }));

  test('aucun nom (modèle inconnu, rien de saisi) : aucun en-tête', () => avecVraiHttp(() async {
        NomAppareil.instance.modele = () => '';
        expect(await ApiService(baseUrl: srv.base).login(DonneesFictives.login, DonneesFictives.motDePasse), isNotNull);
        expect(srv.recuesSur('/user/auth').last.poste, isEmpty);
      }));
}
