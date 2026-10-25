// RÉSEAU — 4.8.0 (demande 56) : nom de l'appareil gardé par le serveur, en vrai HTTP vers le faux serveur Prestige :
//  - lecture sans session : nom trouvé (gardé sur l'appareil), inconnu (null), 400, 429, 404, délai dépassé
//    (≤ 3 s puis repli) ; X-Poste et aucun cookie de session requis ;
//  - envoi avec la session : nom enregistré, nom renvoyé par le serveur gardé ; sans session : rien n'est envoyé.
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/api/utilisateur_session.dart';
import 'package:prestige_vente_app/serveur/nom_appareil.dart';
import 'package:prestige_vente_app/serveur/nom_appareil_serveur.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../outils/faux_serveur_prestige.dart';

final _emp = 'ab12cd34' * 8;

void main() {
  late FauxServeurPrestige srv;
  setUp(() => avecVraiHttp(() async {
        SharedPreferences.setMockInitialValues({});
        NomAppareil.reinitialiser();
        NomAppareil.instance.modele = () => 'SUNMI V2s';
        await NomAppareil.instance.charger();
        NomAppareilServeur.reinitialiser();
        NomAppareilServeur.instance.empreinte = () async => _emp;
        srv = FauxServeurPrestige()..activerNomAppareil();
        await srv.demarrer();
        await DioClient.cookieJar.deleteAll();
      }));
  tearDown(() => avecVraiHttp(() async {
        await srv.arreter();
        await DioClient.cookieJar.deleteAll();
        UtilisateurSession.id = null;
      }));

  test('lecture sans session : trouvé → gardé sur l\'appareil ; inconnu ; 429 / 404 / 400 → indisponible', () => avecVraiHttp(() async {
        final s = NomAppareilServeur.instance;
        expect(await s.retrouver(srv.base), LectureNomServeur.inconnu);
        expect(NomAppareil.instance.nomEnregistre, isFalse);
        final r = srv.recuesSur('/appareil/nom').single;
        expect((r.methode, r.query['empreinte']), ('GET', _emp));
        expect(r.jsessionid, isNull, reason: 'sans session');
        expect(r.poste, 'SUNMI%20V2s', reason: 'X-Poste aussi sur cette route');
        srv.nomsAppareils[_emp] = 'Caisse mobile 1';
        expect(await s.retrouver(srv.base), LectureNomServeur.trouve);
        expect(NomAppareil.instance.saisi, 'Caisse mobile 1');
        expect((await SharedPreferences.getInstance()).getString(NomAppareil.prefNom), 'Caisse mobile 1');
        for (final statut in [429, 404, 405]) {
          srv.statutLectureNom = statut;
          expect(await s.retrouver(srv.base), LectureNomServeur.indisponible, reason: 'HTTP $statut');
        }
        srv.statutLectureNom = null;
        NomAppareilServeur.reinitialiser();
        NomAppareilServeur.instance.empreinte = () async => 'pas-une-empreinte';
        final avant = srv.recues.length;
        expect(await NomAppareilServeur.instance.retrouver(srv.base), LectureNomServeur.indisponible);
        expect(srv.recues.length, avant, reason: 'empreinte invalide : rien n\'est envoyé');
      }));

  test('délai dépassé : repli au plus tard après 3 s', () => avecVraiHttp(() async {
        srv.delaiLectureNom = const Duration(seconds: 6);
        final sw = Stopwatch()..start();
        expect(await NomAppareilServeur.instance.retrouver(srv.base), LectureNomServeur.indisponible);
        sw.stop();
        expect(sw.elapsed, lessThan(const Duration(milliseconds: 4500)));
      }));

  test('envoi avec la session : nom renvoyé par le serveur gardé ; sans session : rien envoyé', () => avecVraiHttp(() async {
        await NomAppareil.instance.enregistrer('Caisse mobile 1');
        await NomAppareilServeur.instance.synchroniser();
        expect(srv.recuesSur('/appareil/nom'), isEmpty, reason: 'pas de session');
        expect(await ApiService(baseUrl: srv.base).login(DonneesFictives.login, DonneesFictives.motDePasse), isNotNull);
        UtilisateurSession.id = 'U-${DonneesFictives.login}';
        srv.nomEnregistreServeur = (n) => '${n.trim()} bis';
        await NomAppareilServeur.instance.synchroniser();
        final put = srv.recuesSur('/appareil/nom').single;
        expect(put.methode, 'PUT');
        expect(put.json, {'empreinte': _emp, 'nom': 'Caisse mobile 1'});
        expect(put.jsessionid, isNotNull, reason: 'avec la session');
        expect(NomAppareil.instance.saisi, 'Caisse mobile 1 bis', reason: 'nom tel qu\'enregistré par le serveur');
        await NomAppareilServeur.instance.synchroniser();
        expect(srv.recuesSur('/appareil/nom'), hasLength(1), reason: 'confirmé : pas de nouvel envoi');
      }));
}
