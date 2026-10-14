// 4.1.0 — HTTPS pour l'accès au serveur par Internet (INTÉGRATION) : vrais clients HTTP de l'application contre le
// faux serveur Prestige servi en HTTPS (`HttpServer.bindSecure`, certificat de test auto-signé créé à la volée).
//
// La confiance dans ce certificat est ajoutée au contexte du TEST seulement (test/outils/certificat_tls.dart) : le
// code de l'application ne contourne jamais la vérification (aucun badCertificateCallback). Sans cette confiance,
// le certificat est refusé comme sur un téléphone.
//   - tous les clients (Dio principal, ClientPrestige, RH, transport /mobile/, support, images) utilisent la même
//     adresse https ; le cookie de session RENOUVELÉ à la connexion suit l'adresse https ;
//   - session expirée en https : reconnexion silencieuse (intercepteur 401), requête rejouée ;
//   - certificat non approuvé : « certificat du serveur refusé », distinct de « serveur injoignable » et de la licence ;
//   - https vers un port HTTP : « ne répond pas en HTTPS » ; serveur arrêté : « injoignable » (pas un échec TLS) ;
//   - http inchangé.

import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/api/models/licence_lookup.dart';
import 'package:prestige_vente_app/api/session_expiree.dart';
import 'package:prestige_vente_app/connexion/session_expiree_app.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/images/produit_images.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/licence_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/rh/mobile_api.dart';
import 'package:prestige_vente_app/rh/rh_api.dart';
import 'package:prestige_vente_app/serveur/adresse_serveur.dart';
import 'package:prestige_vente_app/serveur/client_prestige.dart' hide SessionExpiree;
import 'package:prestige_vente_app/serveur/erreur_vue.dart';
import 'package:prestige_vente_app/services/identifiants_securises.dart';
import 'package:prestige_vente_app/support/support_centre.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'outils/certificat_tls.dart';
import 'outils/faux_serveur_prestige.dart';

class _Coffre implements CoffreIdentifiants {
  final Map<String, String> v = {};
  @override
  Future<String?> lire(String cle) async => v[cle];

  @override
  Future<void> ecrire(String cle, String valeur) async => v[cle] = valeur;
  @override
  Future<void> effacer(String cle) async => v.remove(cle);
}

Future<SettingsProvider> _reglages(String localIp, {Map<String, Object> autres = const {}}) async {
  SharedPreferences.setMockInitialValues({'local_ip': localIp, 'port': '8080', 'app_name': 'prestige', ...autres});
  final s = SettingsProvider();
  await s.loadSettings();
  return s;
}

void main() {
  late CertificatTest cert;
  late _Coffre coffre;

  setUpAll(() async => cert = await CertificatTest.creer());

  setUp(() async {
    coffre = _Coffre();
    IdentifiantsSecurises.instance = IdentifiantsSecurises(coffre: coffre, journal: () => JournalTerminal());
    SessionExpiree.instance = SessionExpiree();
    await DioClient.cookieJar.deleteAll();
    // Le Dio principal est unique dans l'application : client HTTP neuf pour chaque test, créé sous la confiance
    // (ou non) du test en cours.
    DioClient.getClient('').httpClientAdapter = IOHttpClientAdapter();
  });
  tearDown(() async => DioClient.cookieJar.deleteAll());

  /// Faux serveur Prestige en HTTPS (certificat de test) sur 127.0.0.1.
  Future<FauxServeurPrestige> serveurHttps() async {
    final s = FauxServeurPrestige()..contexteTls = cert.contexteServeur;
    await s.demarrer();
    addTearDown(s.arreter);
    return s;
  }

  test('tous les clients HTTP utilisent la même adresse https et le cookie de session renouvelé', () async {
    await avecConfianceTest(cert, () async {
      final s = await serveurHttps();
      s.routes['GET /reserve/essai'] = (_) => FauxServeurPrestige.ok({'success': true, 'data': 'reserve'});
      s.routes['GET /rh/essai'] = (_) => FauxServeurPrestige.ok({'success': true});
      s.routes['POST /support/events'] = (_) => FauxServeurPrestige.ok({'success': true, 'id': 'EV-1'});
      s.routes['GET /produit-images/F1'] = (_) => FauxServeurPrestige.ok({'success': true, 'data': []});
      s.routes['GET /mobile/capacites'] = (_) => FauxServeurPrestige.ok({'success': true});

      // Adresse saisie avec son protocole et le port du serveur de test.
      final settings = await _reglages('https://${s.hote}');
      expect(settings.baseUrl, s.base);
      expect(settings.baseUrl, startsWith('https://127.0.0.1:'));

      final api = ApiService(baseUrl: settings.baseUrl);
      expect(api.dio.options.baseUrl, settings.baseUrl, reason: 'Dio principal');
      expect((await api.lookupLicence()).licence, isNotNull, reason: 'licence lue en https');
      expect(await settings.ping(settings.localIp, settings.portPour(settings.localIp), 'prestige'), isTrue,
          reason: 'test de connexion de la Configuration en https');

      // Connexion, puis NOUVELLE connexion : nouveau JSESSIONID, seul envoyé ensuite.
      expect(await api.login(DonneesFictives.login, DonneesFictives.motDePasse), isNotNull);
      final premiere = s.derniereSession;
      expect(await api.login(DonneesFictives.login, DonneesFictives.motDePasse), isNotNull);
      final session = s.derniereSession;
      expect(session, isNot(premiere));
      final avant = s.recues.length;

      // Chaque client de l'application, construit comme dans l'application (adresse lue sur le Dio principal).
      String base() => api.dio.options.baseUrl;
      expect(await api.fetchArticleAnalysisOrFail('para'), isNotEmpty, reason: 'Dio principal (GET /info)');
      expect((await ClientPrestige(() => settings.baseUrl).get('/reserve/essai'))['data'], 'reserve', reason: 'ClientPrestige');
      expect((await DioRhServeur(base).get('/rh/essai')).status, 200, reason: 'RH / pointage');
      expect(await DioSupportEnvoi(base).call({'type': 'essai'}), isNot(SupportReponse.echec), reason: 'support');
      expect(await DioProduitImagesApi(base).lister('F1'), isA<VenteOk<ImagesListe?>>(), reason: 'images');
      expect((await DioTransportMobile(base).envoyer('GET', 'capacites')).status, 200, reason: 'transport /mobile/');

      final apres = s.recues.sublist(avant);
      expect(apres.map((r) => r.chemin), containsAll(<String>[
        '/prestige/api/v1/info',
        '/prestige/api/v1/reserve/essai',
        '/prestige/api/v1/rh/essai',
        '/prestige/api/v1/support/events',
        '/prestige/api/v1/produit-images/F1',
        '/prestige/api/v1/mobile/capacites',
      ]));
      for (final r in apres) {
        if (r.chemin.contains('/mobile/')) continue; // transport /mobile/ : jeton, jamais de cookie (inchangé)
        expect(r.jsessionid, session, reason: '$r : cookie de la DERNIÈRE connexion, envoyé en https');
      }
      expect(s.refusSession, 0, reason: 'aucune requête refusée faute de session');
    });
  });

  test('session expirée en https : reconnexion silencieuse, requête rejouée (intercepteur 401)', () async {
    await avecConfianceTest(cert, () async {
      final s = await serveurHttps();
      final settings = await _reglages('https://${s.hote}',
          autres: {'stay_connected': true, 'saved_login': DonneesFictives.login});
      coffre.v[IdentifiantsSecurises.cleSure] = DonneesFictives.motDePasse;
      final api = ApiService(baseUrl: settings.baseUrl);
      final auth = AuthProvider(api);
      brancherSessionExpiree(auth);
      final retours = <String>[];
      SessionExpiree.instance
        ..journal = (_, {required ok, motif = ''}) {}
        ..versConnexion = retours.add;
      expect(await auth.login(DonneesFictives.login, DonneesFictives.motDePasse), isTrue);
      final connexions = s.connexions;

      s.expirerSessions();
      expect(await api.fetchArticleAnalysisOrFail('para'), isNotEmpty);
      expect(s.connexions, connexions + 1, reason: 'une reconnexion silencieuse, en https');
      expect(SessionExpiree.instance.rejouees, 1);
      expect(retours, isEmpty);
      expect(s.recuesSur('/info').last.jsessionid, s.derniereSession, reason: 'nouveau cookie suivi en https');
    });
  });

  test('certificat non approuvé : « certificat du serveur refusé », ni injoignable ni licence', () async {
    await avecVraiHttp(() async {
      final s = await serveurHttps();
      final settings = await _reglages('https://${s.hote}');

      // Test de connexion de la Configuration.
      expect(await settings.ping(settings.localIp, settings.portPour(settings.localIp), 'prestige'), isFalse);
      expect(settings.pingTls, ErreurTls.certificat);
      expect(settings.pingError, contains('certificat du serveur refusé'));
      expect(settings.pingError, isNot(contains('Aucun serveur')));

      // Vérification de licence : cause distincte, la licence n'est pas en cause.
      final api = ApiService(baseUrl: settings.baseUrl);
      expect((await api.lookupLicence()).issue, LicenceIssue.certificate);
      final licence = LicenceProvider(api);
      expect(await licence.checkLicence(), LicenceStatus.error);
      expect(licence.errorTitle, 'Certificat du serveur refusé');
      expect(licence.errorMessage, contains('licence n\'est pas en cause'));
      expect(await licence.mustBlockAccess(), isFalse, reason: 'un certificat refusé ne bloque pas comme une licence absente');

      // Modules (ClientPrestige) et listes de l'API.
      Object? erreur;
      try {
        await ClientPrestige(() => settings.baseUrl).get('/reserve/essai');
      } catch (e) {
        erreur = e;
      }
      expect(erreur, isA<ConnexionSecuriseeRefusee>());
      expect(titreErreur(erreur!), 'Certificat du serveur refusé');
      expect(messageErreur(erreur), contains('certificat du serveur refusé'));
      await expectLater(api.getCommandes(),
          throwsA(isA<ApiLoadException>().having((e) => e.message, 'message', contains('certificat du serveur refusé'))));

      expect(s.recues, isEmpty, reason: 'aucune requête n\'est partie : la vérification n\'est jamais contournée');
    });
  });

  test('https vers un port HTTP : « ne répond pas en HTTPS » ; serveur arrêté : injoignable', () async {
    await avecVraiHttp(() async {
      final http = FauxServeurPrestige();
      await http.demarrer();
      addTearDown(http.arreter);
      final settings = await _reglages('https://${http.hote}');
      expect(await settings.ping(settings.localIp, '0', 'prestige'), isFalse);
      expect(settings.pingTls, ErreurTls.protocole);
      expect(settings.pingError, contains('ne répond pas en HTTPS'));

      final s = await serveurHttps();
      final hote = s.hote;
      await s.arreter();
      expect(await settings.ping('https://$hote', '0', 'prestige'), isFalse);
      expect(settings.pingTls, isNull);
      expect(settings.pingError, startsWith('Aucun serveur ne répond à https://$hote'));
    });
  });

  test('http inchangé : même adresse qu\'avant, connexion et cookie comme avant', () async {
    await avecVraiHttp(() async {
      final s = FauxServeurPrestige();
      await s.demarrer();
      addTearDown(s.arreter);
      final port = s.hote.split(':').last;
      final settings = await _reglages('127.0.0.1', autres: {'port': port});
      expect(settings.baseUrl, 'http://127.0.0.1:$port/prestige/api/v1');
      expect(settings.baseUrl, s.base);
      expect(await settings.ping(settings.localIp, settings.port, 'prestige'), isTrue);
      final api = ApiService(baseUrl: settings.baseUrl);
      await api.login(DonneesFictives.login, DonneesFictives.motDePasse);
      expect(await api.fetchArticleAnalysisOrFail('para'), isNotEmpty);
      expect(s.recuesSur('/info').last.jsessionid, s.derniereSession);
    });
  });
}
