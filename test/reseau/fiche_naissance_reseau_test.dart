// RÉSEAU — Prestige Mobile 4.10.1 : date de naissance ajoutée à la fiche client en VRAI HTTP (faux serveur Prestige
// sur un port local, règles de POST v1/ordonnance-client/client/{id}/identite) :
//  - corps JSON exact `{naissance: AAAA-MM-JJ}`, session (cookie) envoyée ; fiche relue avec la date ;
//  - deuxième envoi : « Déjà renseigné » (jamais d'écrasement) ;
//  - serveur coupé : erreur réseau claire, rien d'enregistré ; retour du serveur : l'envoi aboutit.
//  - 4.10.2 (demande 58) : remplacer puis effacer (`remplacer:true`), refus « plus de 130 ans » rendu tel quel.
// Patient FICTIF.
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/fiche_client/fiche_client_api.dart';
import 'package:prestige_vente_app/serveur/client_prestige.dart';

import '../outils/faux_serveur_prestige.dart';

void main() {
  late FauxServeurPrestige srv;
  late FicheClientApi api;
  setUp(() => avecVraiHttp(() async {
        srv = FauxServeurPrestige()..activerModules();
        srv.naissanceC1 = '';
        await srv.demarrer();
        await DioClient.cookieJar.deleteAll();
        expect(await ApiService(baseUrl: srv.base).login(DonneesFictives.login, DonneesFictives.motDePasse), isNotNull);
        api = FicheClientApi(ClientPrestige(() => srv.base, delaiReponse: const Duration(seconds: 2)));
      }));
  tearDown(() => avecVraiHttp(() async {
        await srv.arreter();
        await DioClient.cookieJar.deleteAll();
      }));

  test('JSON exact avec la session ; fiche relue ; second envoi : « Déjà renseigné »', () => avecVraiHttp(() async {
        expect(await api.completerNaissance('C1', DateTime(1985, 3, 2)), 'Fiche complétée : date de naissance.');
        final r = srv.recuesSur('/client/C1/identite').single;
        expect(r.json, {'naissance': '1985-03-02'});
        expect(r.cookie, contains('JSESSIONID'));
        expect((await api.dossier('C1')).client.naissance, '1985-03-02');
        await expectLater(api.completerNaissance('C1', DateTime(1990, 1, 1)),
            throwsA(isA<RefusMetier>().having((e) => e.message, 'message', startsWith('Déjà renseigné'))));
        expect(srv.naissanceC1, '1985-03-02', reason: 'jamais écrasée');
      }));

  test('serveur coupé : erreur réseau, rien d\'enregistré ; retour : l\'envoi aboutit', () => avecVraiHttp(() async {
        await srv.couper();
        await expectLater(api.completerNaissance('C1', DateTime(1985, 3, 2)), throwsA(isA<ErreurPrestige>()));
        expect(srv.naissanceC1, '');
        await srv.retablir();
        expect(await api.completerNaissance('C1', DateTime(1985, 3, 2)), 'Fiche complétée : date de naissance.');
        expect(srv.naissanceC1, '1985-03-02');
      }));

  test('4.10.2 : modifier puis effacer, corps exacts ; refus du serveur ; capacité du dossier', () => avecVraiHttp(() async {
        srv.naissanceC1 = '1980-01-01';
        expect((await api.dossier('C1')).client.naissanceModifiable, isTrue);
        expect(await api.modifierNaissance('C1', DateTime(1979, 12, 31)), 'Date de naissance modifiée.');
        expect(srv.recuesSur('/client/C1/identite').last.json, {'naissance': '1979-12-31', 'remplacer': true});
        expect((await api.dossier('C1')).client.naissance, '1979-12-31');
        expect(await api.modifierNaissance('C1', null), 'Date de naissance effacée.');
        expect(srv.naissanceC1, '');
        srv.routes['POST /client/C1/identite'] = (_) => FauxServeurPrestige.ok({'success': false, 'message': 'La date de naissance donne plus de 130 ans.'});
        await expectLater(api.modifierNaissance('C1', DateTime(1990, 1, 1)),
            throwsA(isA<RefusMetier>().having((e) => e.message, 'message', 'La date de naissance donne plus de 130 ans.')));
      }));
}
