// Session expirée (serveur Prestige : expiration après KEY_DUREE_SESSION_MINUTES sans requête, 401
// « Veuillez vous connecter » du filtre, sans exécuter la requête) — intercepteur GLOBAL du client Dio :
// - « Rester connecté » + mot de passe mémorisé : reconnexion silencieuse, requête rejouée, données affichées ;
// - requêtes simultanées : UNE seule reconnexion ;
// - sans mot de passe mémorisé (ou reconnexion refusée) : retour à l'écran de connexion avec
//   « Votre session a expiré, reconnectez-vous », files hors ligne conservées ;
// - routes publiques (connexion, licence, officine…) jamais interceptées ; jamais de boucle.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/api/models/user.dart';
import 'package:prestige_vente_app/api/session_expiree.dart';
import 'package:prestige_vente_app/connexion/session_expiree_app.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/screens/auth/login_screen.dart';
import 'package:prestige_vente_app/services/identifiants_securises.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RealHttp extends HttpOverrides {}

/// Stockage sûr en mémoire.
class _Coffre implements CoffreIdentifiants {
  final Map<String, String> v = {};
  bool panne = false;
  @override
  Future<String?> lire(String cle) async {
    if (panne) throw PlatformException(code: 'x');
    return v[cle];
  }

  @override
  Future<void> ecrire(String cle, String valeur) async => v[cle] = valeur;
  @override
  Future<void> effacer(String cle) async => v.remove(cle);
}

/// Faux serveur Prestige (vrai HTTP local) : sessions par cookie, expiration pilotée par le test.
class _Prestige {
  late HttpServer server;
  int prochaine = 1;
  final valides = <String>{};
  int connexions = 0;
  int infos = 0;
  bool refuserConnexion = false;
  bool toujours401 = false;

  String get base => 'http://127.0.0.1:${server.port}/prestige/api/v1';

  /// Toutes les sessions expirent (12 h sans requête).
  void expirer() => valides.clear();

  Future<void> demarrer() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final res = req.response;
      final path = req.uri.path;
      final cookie = req.headers.value('cookie') ?? '';
      final session = RegExp(r'JSESSIONID=([^;]+)').firstMatch(cookie)?.group(1);
      final connecte = session != null && valides.contains(session) && !toujours401;
      if (path.endsWith('/user/auth')) {
        connexions++;
        await utf8.decoder.bind(req).join();
        if (refuserConnexion) {
          res.headers.contentType = ContentType.json;
          res.write(jsonEncode({'success': false}));
        } else {
          final id = 's${prochaine++}';
          valides.add(id);
          res.headers.add('set-cookie', 'JSESSIONID=$id; Path=/prestige; HttpOnly');
          res.headers.contentType = ContentType.json;
          res.write(jsonEncode({'success': true, 'str_LOGIN': 'admin', 'str_USER_ID': 'u1', 'str_FIRST_NAME': 'A', 'str_LAST_NAME': 'B'}));
        }
      } else if (path.endsWith('/officine') || path.endsWith('/licence/find')) {
        // Route publique mais renvoyant 401 ici : ne doit JAMAIS déclencher de reconnexion.
        res.statusCode = 401;
        res.write('Veuillez vous connecter');
      } else if (!connecte) {
        // AuthenticationFilter : 401 texte, requête non exécutée.
        res.statusCode = 401;
        res.write('Veuillez vous connecter');
      } else if (path.endsWith('/info')) {
        infos++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode([
          {'codeCip': '3529422', 'libelle': 'DOLIPRANE 1000MG', 'produitId': 'f1', 'stock': 18, 'prixVente': 1475},
        ]));
      } else {
        res.statusCode = 404;
      }
      await res.close();
    });
  }
}

void main() {
  late _Coffre coffre;

  setUp(() async {
    coffre = _Coffre();
    IdentifiantsSecurises.instance = IdentifiantsSecurises(coffre: coffre, journal: () => JournalTerminal());
    SessionExpiree.instance = SessionExpiree();
    // 4.5.1 : faux ApiService (aucun serveur) : pas de lecture des droits de vente à la connexion.
    AuthProvider.lireDroitsVente = (_, __) async {};
    await DioClient.cookieJar.deleteAll();
  });

  /// Préférences « Rester connecté » (+ mot de passe dans le stockage sûr si [motDePasse]).
  Future<void> resterConnecte({String? motDePasse, bool actif = true, Map<String, Object> autres = const {}}) async {
    SharedPreferences.setMockInitialValues({'stay_connected': actif, 'saved_login': 'admin', ...autres});
    if (motDePasse != null) coffre.v[IdentifiantsSecurises.cleSure] = motDePasse;
  }

  Future<void> reel(Future<void> Function(_Prestige p) corps) => HttpOverrides.runWithHttpOverrides(() async {
        final p = _Prestige();
        await p.demarrer();
        try {
          await corps(p);
        } finally {
          await p.server.close(force: true);
          await DioClient.cookieJar.deleteAll();
        }
      }, _RealHttp());

  test('session expirée + « Rester connecté » : reconnexion silencieuse, requête rejouée, données reçues', () async {
    await reel((p) async {
      await resterConnecte(motDePasse: 'secret');
      final api = ApiService(baseUrl: p.base);
      final auth = AuthProvider(api);
      final journal = <String>[];
      final retours = <String>[];
      brancherSessionExpiree(auth);
      final s = SessionExpiree.instance;
      s.journal = (a, {required ok, motif = ''}) => journal.add('$a|$ok');
      s.versConnexion = retours.add;
      expect(await auth.login('admin', 'secret'), isTrue);
      expect(p.connexions, 1);

      p.expirer(); // 12 h sans requête
      final lignes = await api.fetchArticleAnalysisOrFail('dol');
      expect(lignes.single.libelle, 'DOLIPRANE 1000MG');
      expect(p.connexions, 2, reason: 'une reconnexion silencieuse');
      expect(p.infos, 1, reason: 'la requête refusée (non exécutée) est rejouée une fois');
      expect(s.reconnexions, 1);
      expect(s.rejouees, 1);
      expect(retours, isEmpty, reason: 'pas de retour à l\'écran de connexion');
      expect(auth.status, AuthStatus.Authenticated);
      expect(journal, ['Session expirée : reconnexion automatique réussie|true']);
      expect(journal.join(), isNot(contains('secret')), reason: 'jamais de secret dans le journal');
    });
  });

  test('requêtes simultanées : une seule reconnexion pour toutes', () async {
    await reel((p) async {
      await resterConnecte(motDePasse: 'secret');
      final api = ApiService(baseUrl: p.base);
      final auth = AuthProvider(api);
      brancherSessionExpiree(auth);
      SessionExpiree.instance.journal = (_, {required ok, motif = ''}) {};
      await auth.login('admin', 'secret');
      p.expirer();
      final r = await Future.wait([for (var i = 0; i < 6; i++) api.fetchArticleAnalysisOrFail('dol$i')]);
      expect(r.every((l) => l.length == 1), isTrue);
      expect(p.connexions, 2, reason: 'connexion initiale + UNE reconnexion');
      expect(SessionExpiree.instance.reconnexions, 1);
      expect(p.infos, 6);
    });
  });

  test('sans mot de passe mémorisé : retour à la connexion avec le message, pas de reconnexion', () async {
    await reel((p) async {
      await resterConnecte(actif: false);
      final api = ApiService(baseUrl: p.base);
      final auth = AuthProvider(api);
      final retours = <String>[];
      brancherSessionExpiree(auth);
      final s = SessionExpiree.instance;
      final journal = <String>[];
      s.journal = (a, {required ok, motif = ''}) => journal.add(a);
      s.versConnexion = (m) {
        auth.sessionExpiree();
        retours.add(m);
      };
      await auth.login('admin', 'secret');
      p.expirer();
      await expectLater(api.fetchArticleAnalysisOrFail('dol'), throwsA(isA<ApiLoadException>()));
      expect(p.connexions, 1, reason: 'aucune reconnexion sans identifiants mémorisés');
      expect(retours, ['Votre session a expiré, reconnectez-vous']);
      expect(auth.status, AuthStatus.Unauthenticated);
      // Une seule redirection même si d'autres requêtes échouent ensuite… (plus connecté : plus interceptées)
      await expectLater(api.fetchArticleAnalysisOrFail('dol'), throwsA(isA<ApiLoadException>()));
      expect(retours, hasLength(1));
      expect(journal.last, 'Session expirée : retour à l\'écran de connexion');
    });
  });

  test('reconnexion refusée (mot de passe changé) : retour à la connexion, jamais de boucle', () async {
    await reel((p) async {
      await resterConnecte(motDePasse: 'ancien');
      final api = ApiService(baseUrl: p.base);
      final auth = AuthProvider(api);
      final retours = <String>[];
      brancherSessionExpiree(auth);
      SessionExpiree.instance
        ..journal = (_, {required ok, motif = ''}) {}
        ..versConnexion = retours.add;
      await auth.login('admin', 'ancien');
      p
        ..expirer()
        ..refuserConnexion = true;
      await expectLater(api.fetchArticleAnalysisOrFail('dol'), throwsA(isA<ApiLoadException>()));
      expect(p.connexions, 2, reason: 'une seule tentative');
      expect(retours, ['Votre session a expiré, reconnectez-vous']);
    });
  });

  test('requête rejouée et de nouveau refusée : rendue telle quelle (pas de boucle)', () async {
    await reel((p) async {
      await resterConnecte(motDePasse: 'secret');
      final api = ApiService(baseUrl: p.base);
      final auth = AuthProvider(api);
      brancherSessionExpiree(auth);
      SessionExpiree.instance
        ..journal = (_, {required ok, motif = ''}) {}
        ..versConnexion = (_) {};
      await auth.login('admin', 'secret');
      p.toujours401 = true;
      await expectLater(
          api.fetchArticleAnalysisOrFail('dol'), throwsA(isA<ApiLoadException>().having((e) => e.message, 'm', contains('Session expirée'))));
      expect(p.connexions, 2, reason: 'connexion + UNE reconnexion, pas de boucle');
      expect(SessionExpiree.instance.rejouees, 1);
    });
  });

  test('routes publiques jamais interceptées (connexion, licence, officine)', () async {
    expect(routeSansSession('/prestige/api/v1/user/auth'), isTrue);
    expect(routeSansSession('/prestige/api/v1/licence/find'), isTrue);
    expect(routeSansSession('/prestige/api/v1/officine'), isTrue);
    expect(routeSansSession('/prestige/api/v1/app/info'), isTrue);
    expect(routeSansSession('/prestige/api/v1/mobile/pointage'), isTrue);
    expect(routeSansSession('/prestige/api/v1/info'), isFalse);
    expect(routeSansSession('/prestige/api/v1/vente/search'), isFalse);
    expect(routeSansSession('/prestige/api/v1/app-vente/ventes'), isFalse);
    await reel((p) async {
      await resterConnecte(motDePasse: 'secret');
      final api = ApiService(baseUrl: p.base);
      final auth = AuthProvider(api);
      brancherSessionExpiree(auth);
      SessionExpiree.instance
        ..journal = (_, {required ok, motif = ''}) {}
        ..versConnexion = (_) => fail('pas de retour à la connexion pour une route publique');
      await auth.login('admin', 'secret');
      await api.fetchOfficineInfo(); // 401 sur une route publique
      await api.lookupLicence();
      expect(p.connexions, 1);
      expect(SessionExpiree.instance.reconnexions, 0);
    });
  });

  test('utilisateur non connecté : rien n\'est intercepté', () async {
    await reel((p) async {
      await resterConnecte(motDePasse: 'secret');
      final api = ApiService(baseUrl: p.base);
      brancherSessionExpiree(AuthProvider(api));
      SessionExpiree.instance.versConnexion = (_) => fail('non connecté : pas de redirection');
      await expectLater(api.fetchArticleAnalysisOrFail('dol'), throwsA(isA<ApiLoadException>()));
      expect(p.connexions, 0);
    });
  });

  testWidgets('écran : retour à la connexion avec le message ; files hors ligne et « Rester connecté » conservés', (tester) async {
    final autres = <String, Object>{
      // Files hors ligne (ventes HL, stock, pointage, support) : clés quelconques, jamais effacées.
      'ventes_hors_ligne_v1': '[{"id":"HL-1"}]',
      'stock_hors_ligne_v1': '[{"id":"ST-1"}]',
      'pointage_file_v1': '[{"id":"PT-1"}]',
      'support_file_v1': '[{"id":"SP-1"}]',
    };
    await resterConnecte(actif: false, autres: autres);
    final api = _ApiFaux();
    final auth = AuthProvider(api);
    await auth.login('admin', 'x');
    final nav = GlobalKey<NavigatorState>();
    brancherSessionExpiree(auth, navigateur: nav, ecranConnexion: (m) => Scaffold(body: Center(child: Text('CONNEXION : $m'))));
    SessionExpiree.instance.journal = (_, {required ok, motif = ''}) {};
    final avant = (await SharedPreferences.getInstance()).getKeys().toSet();
    await tester.pumpWidget(MaterialApp(navigatorKey: nav, home: const Scaffold(body: Text('ACCUEIL'))));
    expect(find.text('ACCUEIL'), findsOneWidget);

    SessionExpiree.instance.deconnecter(); // ce que fait l'intercepteur quand la reconnexion est impossible
    await tester.pumpAndSettle();
    expect(find.text('CONNEXION : Votre session a expiré, reconnectez-vous'), findsOneWidget);
    expect(find.text('ACCUEIL'), findsNothing);
    expect(auth.status, AuthStatus.Unauthenticated);
    expect(api.deconnexionsServeur, 0, reason: 'déconnexion locale seulement');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().toSet(), avant);
    for (final e in autres.entries) {
      expect(prefs.getString(e.key), e.value, reason: '${e.key} conservée');
    }
    // Reconnexion manuelle : un nouveau retour à la connexion redevient possible.
    await auth.login('admin', 'x');
    expect(auth.status, AuthStatus.Authenticated);
  });

  test('LoginScreen transmet le message', () {
    const l = LoginScreen(message: SessionExpiree.message);
    expect(l.message, 'Votre session a expiré, reconnectez-vous');
  });

  test('intercepteur présent sur le client partagé ; 403 « Veuillez vous connecter » = refus de session', () {
    final dio = DioClient.getClient('http://x');
    expect(dio.interceptors.whereType<IntercepteurSession>(), hasLength(1));
    final ro = RequestOptions(path: '/info');
    expect(refusDeSession(Response(requestOptions: ro, statusCode: 401)), isTrue);
    expect(refusDeSession(Response(requestOptions: ro, statusCode: 403, data: 'Veuillez vous connecter')), isTrue);
    expect(refusDeSession(Response(requestOptions: ro, statusCode: 403, data: {'message': 'droit insuffisant'})), isFalse);
    expect(refusDeSession(Response(requestOptions: ro, statusCode: 500)), isFalse);
  });
}

class _ApiFaux extends ApiService {
  _ApiFaux() : super(baseUrl: 'http://localhost');
  int deconnexionsServeur = 0;

  @override
  Future<User?> login(String login, String password) async =>
      User(userId: 'u1', login: login, firstName: 'Awa', lastName: 'Kouassi', officineName: 'PHCIE TEST');

  @override
  Future<void> logout() async => deconnexionsServeur++;
}
