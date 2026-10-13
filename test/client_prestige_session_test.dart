// Réserve, Analyse posologie, Fiche client : leur client JSON suit le mécanisme global de session expirée
// (reconnexion silencieuse puis requête rejouée une fois ; sinon retour à l'écran de connexion).
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/api/session_expiree.dart' as globale;
import 'package:prestige_vente_app/serveur/client_prestige.dart';

import 'outils/serveur_json_local.dart';

void main() {
  late ServeurJsonLocal srv;
  late ClientPrestige client;
  late globale.SessionExpiree session;

  setUp(() async {
    await avecVraiHttp(() async {
      srv = ServeurJsonLocal();
      await srv.demarrer();
    });
    client = ClientPrestige(() => srv.base, delaiConnexion: const Duration(seconds: 2), delaiReponse: const Duration(seconds: 2));
    session = globale.SessionExpiree()..connecte = () => true;
    globale.SessionExpiree.instance = session;
  });
  tearDown(() async {
    globale.SessionExpiree.instance = globale.SessionExpiree();
    await DioClient.cookieJar.deleteAll();
    await avecVraiHttp(() => srv.arreter());
  });

  test('401 puis reconnexion silencieuse réussie : la requête est rejouée une fois et réussit', () => avecVraiHttp(() async {
        var appels = 0;
        session.reconnecter = () async => true;
        srv.routes['POST /suggestion-reserve/creer'] = (_) =>
            ++appels == 1 ? const ReponseLocale('Veuillez vous connecter', statut: 401) : const ReponseLocale({'success': true, 'id': 'S1'});
        final j = await client.post('/suggestion-reserve/creer', {'categorie': 'RAYON'});
        expect(j['id'], 'S1');
        expect(appels, 2, reason: 'une seule relance, pas de boucle');
      }));

  test('401 sans reconnexion possible : retour à la connexion et SessionExpiree levée', () => avecVraiHttp(() async {
        String? message;
        session.reconnecter = () async => false;
        session.versConnexion = (m) => message = m;
        srv.routes['GET /posos/status'] = (_) => const ReponseLocale('Veuillez vous connecter', statut: 401);
        await expectLater(client.get('/posos/status'), throwsA(isA<SessionExpiree>()));
        expect(message, globale.SessionExpiree.message);
        expect(srv.recues.length, 1);
      }));

  test('utilisateur non connecté : rien n\'est intercepté (comportement d\'origine)', () => avecVraiHttp(() async {
        session.connecte = () => false;
        var reconnexions = 0;
        session.reconnecter = () async => ++reconnexions > 0;
        srv.routes['GET /a'] = (_) => const ReponseLocale('Veuillez vous connecter', statut: 401);
        await expectLater(client.get('/a'), throwsA(isA<SessionExpiree>()));
        expect(reconnexions, 0);
      }));
}
