// Centre de support (API EXISTANTE du serveur : POST /api/v1/support/events, POST /prestige/support-contact) :
// - format identique au web (AJAX / APPLICATION / erreurs non gérées en MOBILE), payloadJson avec le contexte ;
// - erreurs Flutter capturées (FlutterError.onError, PlatformDispatcher.onError), réseau pur ignoré ;
// - intercepteur Dio filtré (pas les 401, pas le réseau, pas les envois du support), fil d'Ariane sans paramètres ;
// - signalement manuel (objet obligatoire, gravité, contexte, demande de contact + capture) ;
// - file hors ligne persistante et renvoi ; anti-tempête (20 / session, doublons, 30 / heure) ;
// - troncature aux bornes du serveur ; filtrage des données sensibles ; réglage désactivé ; route absente (404).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/support/signaler_probleme_screen.dart';
import 'package:prestige_vente_app/support/support_capture.dart';
import 'package:prestige_vente_app/support/support_centre.dart';
import 'package:prestige_vente_app/support/support_event.dart';
import 'package:prestige_vente_app/support/support_file.dart';
import 'package:prestige_vente_app/support/support_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -----------------------------------------------------------------------------
// Outils
// -----------------------------------------------------------------------------

/// Faux serveur : enregistre les corps reçus et répond [reponse].
class _Serveur {
  final corps = <Map<String, Object?>>[];
  SupportReponse reponse = SupportReponse.ok;
  Future<SupportReponse> call(Map<String, Object?> c) async {
    corps.add(c);
    return reponse;
  }

  Map<String, dynamic> payload([int i = -1]) => jsonDecode(corps[i < 0 ? corps.length + i : i]['payloadJson'] as String) as Map<String, dynamic>;
}

class _Adapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions o) handler;
  _Adapter(this.handler);
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) => handler(o);
  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, [int code = 200, String? statusMessage]) => ResponseBody.fromString(jsonEncode(body), code,
    statusMessage: statusMessage, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});

SupportEvent _auto(String msg, {String ecran = 'VenteScreen', String? stack, Map<String, Object?> donnees = const {}}) => SupportEvent(
    type: TypeSupport.mobile, niveau: NiveauSupport.error, module: 'VENTE', messageCourt: msg, urlOuEcran: ecran, stack: stack, donnees: donnees);

(SupportCentre, _Serveur) _centre({DateTime Function()? clock, SupportFileStore? file}) {
  final s = _Serveur();
  final c = SupportCentre(envoi: s.call, clock: clock, file: file)..login = 'caisse1';
  return (c, s);
}

Future<void> _attendre() => Future<void>.delayed(Duration.zero);

void main() {
  late JournalTerminal journal;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    journal = JournalTerminal()
      ..terminalId = 'T-ABC123'
      ..terminalNom = 'SUNMI V2s';
    JournalTerminal.instance = journal;
  });

  group('format identique au web', () {
    test('échec HTTP 500 : AJAX / ERROR, « Échec Ajax HTTP 500 … », url sans paramètres, corps filtré', () async {
      final (c, srv) = _centre();
      final dio = Dio(BaseOptions(baseUrl: 'http://srv:8080/prestige/api/v1'))
        ..httpClientAdapter = _Adapter((o) async => o.path.contains('cloturer')
            ? _json({'success': false, 'msg': 'NullPointerException', 'nom': 'KONE AWA', 'token': 'x'}, 500, 'Internal Server Error')
            : _json({'success': true, 'data': []}))
        ..interceptors.add(SupportInterceptor(centre: () => c));
      await dio.get('/vente/search', queryParameters: {'query': 'KONE AWA'});
      await expectLater(dio.post('/vente/cloturer/vno', data: {'password': 'secret'}), throwsA(isA<DioException>()));
      await _attendre();
      expect(srv.corps, hasLength(1));
      final e = srv.corps.single;
      expect(e.keys.toSet(), {'type', 'niveau', 'module', 'messageCourt', 'urlOuEcran', 'stack', 'payloadJson'});
      expect(e['type'], 'AJAX');
      expect(e['niveau'], 'ERROR');
      expect(e['module'], 'VENTE');
      expect(e['messageCourt'], 'Échec Ajax HTTP 500 Internal Server Error');
      expect(e['urlOuEcran'], '/prestige/api/v1/vente/cloturer/vno');
      expect(e['stack'], '{"success":false,"msg":"NullPointerException"}');
      final p = srv.payload();
      expect(p['application'], 'Prestige Mobile');
      expect(p['version'], SupportCentre.version);
      expect(p['terminal'], {'id': 'T-ABC123', 'modele': 'SUNMI V2s'});
      expect(p['utilisateur'], 'caisse1');
      final fil = (p['fil_ariane'] as List).cast<String>();
      expect(fil, hasLength(2));
      expect(fil[0], matches(RegExp(r'^\d\d:\d\d:\d\d  API GET /prestige/api/v1/vente/search$')));
      expect(fil[1], endsWith('  API POST /prestige/api/v1/vente/cloturer/vno'));
      expect(jsonEncode(e), isNot(contains('KONE')));
      expect(jsonEncode(e), isNot(contains('secret')));
    });

    test('4xx : WARN ; module déduit du chemin (STOCK, MOBILE)', () async {
      final (c, srv) = _centre();
      final dio = Dio(BaseOptions(baseUrl: 'http://srv/prestige/api/v1'))
        ..httpClientAdapter = _Adapter((o) async => _json({'msg': 'introuvable'}, o.path.contains('commande') ? 404 : 400))
        ..interceptors.add(SupportInterceptor(centre: () => c));
      await expectLater(dio.get('/commande/list'), throwsA(isA<DioException>()));
      await expectLater(dio.get('/officine/xyz'), throwsA(isA<DioException>()));
      await _attendre();
      expect(srv.corps.map((e) => '${e['niveau']} ${e['module']} ${e['messageCourt']}'),
          ['WARN STOCK Échec Ajax HTTP 404', 'WARN MOBILE Échec Ajax HTTP 400']);
    });

    test('anomalie de synchronisation hors ligne : APPLICATION / WARN, payload {vente, issue, explication}, client masqué', () async {
      final (c, srv) = _centre();
      final r = await c.anomalieSynchro(
        module: 'VENTE',
        quoi: 'vente carnet',
        nature: 'Bon déjà utilisé / refusé',
        motif: 'Le bon N° B9 de MME TRAORE est déjà utilisé',
        vente: 'HL-0002',
        masquer: ['MME TRAORE', 'B9'],
      );
      expect(r, SupportIssue.envoye);
      final e = srv.corps.single;
      expect(e['type'], 'APPLICATION');
      expect(e['niveau'], 'WARN');
      expect(e['module'], 'VENTE');
      expect(e['messageCourt'], 'Synchronisation hors ligne : vente carnet refusé(e) (Bon déjà utilisé / refusé)');
      expect(e['urlOuEcran'], 'SYNCHRO ventes hors ligne');
      final p = srv.payload();
      expect(p['vente'], 'HL-0002');
      expect(p['issue'], 'Bon déjà utilisé / refusé');
      expect(p['explication'], contains('Le bon N° *** de *** est déjà utilisé'));
      expect(jsonEncode(e), isNot(contains('TRAORE')));
      // Stock : operation au lieu de vente.
      await c.anomalieSynchro(module: 'STOCK', quoi: 'réception', nature: 'ligne refusée', motif: 'Lot déjà saisi', operation: 'op-1');
      expect(srv.payload()['operation'], 'op-1');
      expect(srv.corps.last['urlOuEcran'], 'SYNCHRO stock hors ligne');
    });

    test('la version annoncée est celle de pubspec.yaml', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final v = RegExp(r'^version:\s*([0-9.]+)', multiLine: true).firstMatch(pubspec)!.group(1);
      expect(SupportCentre.version, v);
    });

    test('réponses du serveur : succès, session, refus, 404, 5xx, HTML ; contact text/html avec JSON', () {
      expect(lireReponseSupport(200, {'success': true, 'msg': ''}), SupportReponse.ok);
      expect(lireReponseSupport(200, {'success': false, 'msg': 'Veuillez vous connecter'}), SupportReponse.session);
      expect(lireReponseSupport(200, {'success': false, 'msg': 'Message obligatoire'}), SupportReponse.rejete);
      expect(lireReponseSupport(404, '<html>Not Found</html>'), SupportReponse.routeAbsente);
      expect(lireReponseSupport(500, null), SupportReponse.echec);
      expect(lireReponseSupport(401, null), SupportReponse.session);
      expect(lireReponseSupport(200, '<html><body>login</body></html>'), SupportReponse.session);
      expect(lireReponseSupport(200, '{"success":true,"msg":"Votre demande a été enregistrée (réf. 12)"}'), SupportReponse.ok);
    });
  });

  group('erreurs Flutter non gérées', () {
    test('FlutterError.onError et PlatformDispatcher.onError : MOBILE / ERROR, écran courant ; réseau pur ignoré', () async {
      final (c, srv) = _centre();
      c.noterEcran('VenteScreen');
      final avantFlutter = FlutterError.onError;
      final avantDispatcher = PlatformDispatcher.instance.onError;
      final presentes = <FlutterErrorDetails>[];
      FlutterError.onError = presentes.add;
      try {
        installerCaptureErreurs(centre: () => c);
        FlutterError.onError!(FlutterErrorDetails(
          exception: StateError('Bad state: panier vide 42'),
          stack: StackTrace.fromString('#0      VenteController.valider (package:prestige_vente_app/ventes/x.dart:12:3)'),
        ));
        PlatformDispatcher.instance.onError!(const SocketException('Connection refused'), StackTrace.empty);
        PlatformDispatcher.instance.onError!(ArgumentError('valeur invalide'), StackTrace.current);
        await _attendre();
      } finally {
        FlutterError.onError = avantFlutter;
        PlatformDispatcher.instance.onError = avantDispatcher;
      }
      expect(presentes, hasLength(1), reason: 'le gestionnaire précédent est toujours appelé');
      expect(srv.corps, hasLength(2));
      final e = srv.corps.first;
      expect(e['type'], 'MOBILE');
      expect(e['niveau'], 'ERROR');
      expect(e['module'], 'VENTE');
      expect(e['urlOuEcran'], 'VenteScreen');
      expect(e['messageCourt'], contains('panier vide 42'));
      expect(e['stack'] as String, contains('VenteController.valider'));
      expect(srv.payload(0)['ecran'], 'VenteScreen');
      expect(srv.corps.last['messageCourt'], contains('valeur invalide'));
    });

    test('débordement de mise en page : WARN', () {
      final e = evenementErreur(FlutterError('A RenderFlex overflowed by 12 pixels on the right.'), null, ecran: 'AccueilScreen')!;
      expect(e.niveau, NiveauSupport.warn);
      expect(e.module, 'MOBILE');
      expect(evenementErreur(DioException(requestOptions: RequestOptions(), type: DioExceptionType.connectionError), null, ecran: ''), isNull);
    });

    testWidgets('observateur de navigation : écran courant et fil d\'Ariane', (tester) async {
      final (c, _) = _centre();
      await tester.pumpWidget(MaterialApp(
        navigatorObservers: [SupportNavigatorObserver(centre: () => c)],
        home: const AccueilEssaiScreen(),
      ));
      await tester.pumpAndSettle();
      expect(c.ecran, 'AccueilEssaiScreen', reason: 'route initiale « / » : nom lu dans la page');
      Navigator.of(tester.element(find.byType(AccueilEssaiScreen))).push(MaterialPageRoute(builder: (_) => const ReceptionEssaiPage()));
      await tester.pumpAndSettle();
      expect(c.ecran, 'ReceptionEssaiPage');
      expect(moduleDeLEcran(c.ecran), 'STOCK');
      expect(c.filAriane.last, endsWith('  Écran ReceptionEssaiPage'));
      Navigator.of(tester.element(find.byType(ReceptionEssaiPage))).pop();
      await tester.pumpAndSettle();
      expect(c.ecran, 'AccueilEssaiScreen');
      expect(c.filAriane.last, endsWith('  Écran AccueilEssaiScreen'));
    });
  });

  group('intercepteur Dio filtré', () {
    test('pas les 401, ni le réseau pur, ni les annulations, ni les envois du support', () async {
      final (c, srv) = _centre();
      final dio = Dio(BaseOptions(baseUrl: 'http://srv/prestige/api/v1'))
        ..httpClientAdapter = _Adapter((o) async {
          if (o.path.contains('reseau')) throw DioException(requestOptions: o, type: DioExceptionType.connectionError);
          if (o.path.contains('session')) return _json({'msg': 'Veuillez vous connecter'}, 401);
          if (o.path.contains('support')) return _json({'success': false}, 500);
          return _json({'success': true});
        })
        ..interceptors.add(SupportInterceptor(centre: () => c));
      for (final p in ['/reseau', '/session', '/support/events', '/../support-contact']) {
        await expectLater(dio.get(p), throwsA(isA<DioException>()));
      }
      final cancel = CancelToken()..cancel();
      await expectLater(dio.get('/ok', cancelToken: cancel), throwsA(isA<DioException>()));
      await dio.get('/ok', options: Options(extra: {SupportCles.ignorer: true}));
      await _attendre();
      expect(srv.corps, isEmpty);
      expect(c.filAriane.where((f) => f.contains('support')), isEmpty, reason: 'les envois du support ne vont pas au fil');
    });
  });

  group('signalement manuel', () {
    Future<void> ouvrir(WidgetTester tester, SupportCentre c, {Future<SupportPieceJointe?> Function()? capture}) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(
                    builder: (_) => SignalerProblemeScreen(centre: c, ecranOrigine: 'CaisseScreen', choisirCapture: capture))),
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('objet obligatoire ; envoi APPLICATION avec gravité, module, description ; confirmation', (tester) async {
      final (c, srv) = _centre();
      c.noterAction('Écran CaisseScreen');
      await ouvrir(tester, c);
      await tester.tap(find.byKey(const Key('support_envoyer')));
      await tester.pumpAndSettle();
      expect(find.text('L\'objet est obligatoire'), findsOneWidget);
      expect(srv.corps, isEmpty);

      await tester.enterText(find.byKey(const Key('support_objet')), 'Le tiroir caisse ne s\'ouvre pas');
      await tester.enterText(find.byKey(const Key('support_description')), 'Après encaissement. mot de passe: abc123');
      await tester.tap(find.text('Bloquant'));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('support_envoyer')));
      await tester.tap(find.byKey(const Key('support_envoyer')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('support_confirmation')), findsOneWidget);
      expect(find.text('Signalement envoyé'), findsOneWidget);
      final e = srv.corps.single;
      expect(e['type'], 'APPLICATION');
      expect(e['niveau'], 'ERROR');
      expect(e['module'], 'VENTE', reason: 'module proposé d\'après l\'écran (CaisseScreen)');
      expect(e['messageCourt'], 'Le tiroir caisse ne s\'ouvre pas');
      expect(e['urlOuEcran'], 'CaisseScreen');
      expect(e['stack'], 'Après encaissement. mot de passe: ***');
      final p = srv.payload();
      expect(p['signalement'], 'manuel');
      expect(p['terminal'], {'id': 'T-ABC123', 'modele': 'SUNMI V2s'});
      expect((p['fil_ariane'] as List).single, endsWith('Écran CaisseScreen'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byType(SignalerProblemeScreen), findsNothing);
    });

    testWidgets('sans contexte technique ; demande de contact avec capture (urgence HAUTE)', (tester) async {
      final (c, srv) = _centre();
      final contacts = <Map<String, Object?>>[];
      c.contact = ({required objet, required message, required moduleConcerne, required urgence, pieces = const []}) async {
        contacts.add({'objet': objet, 'message': message, 'module': moduleConcerne, 'urgence': urgence, 'pieces': pieces});
        return (SupportReponse.ok, 'Votre demande a été enregistrée et transmise au support (réf. 7)');
      };
      await ouvrir(tester, c, capture: () async => SupportPieceJointe('capture.png', List.filled(100, 1)));
      await tester.enterText(find.byKey(const Key('support_objet')), 'Impression lente');
      await tester.tap(find.text('Bloquant'));
      await tester.tap(find.byKey(const Key('support_contexte')));
      await tester.tap(find.byKey(const Key('support_contact')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('support_capture')));
      await tester.pumpAndSettle();
      expect(find.text('Capture : capture.png'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('support_envoyer')));
      await tester.tap(find.byKey(const Key('support_envoyer')));
      await tester.pumpAndSettle();
      final p = srv.payload();
      expect(p.keys.toSet(), {'signalement', 'objet', 'application', 'version'});
      expect(contacts.single['urgence'], 'HAUTE');
      expect(contacts.single['message'], 'Impression lente');
      expect((contacts.single['pieces'] as List).single, isA<SupportPieceJointe>());
      expect(find.textContaining('réf. 7'), findsOneWidget);
    });

    testWidgets('serveur injoignable : signalement gardé sur le terminal', (tester) async {
      final (c, srv) = _centre();
      srv.reponse = SupportReponse.echec;
      await ouvrir(tester, c);
      await tester.enterText(find.byKey(const Key('support_objet')), 'Écran figé');
      await tester.ensureVisible(find.byKey(const Key('support_envoyer')));
      await tester.tap(find.byKey(const Key('support_envoyer')));
      await tester.pumpAndSettle();
      expect(find.text('Signalement enregistré'), findsOneWidget);
      expect(find.textContaining('gardé sur le terminal'), findsOneWidget);
      expect(c.enAttente, 1);
    });
  });

  group('file hors ligne et renvoi', () {
    test('hors ligne : gardé sans appel ; échec : gardé ; retour en ligne : renvoyé et file vidée', () async {
      final (c, srv) = _centre(file: PrefsSupportFileStore());
      var offline = true;
      c.horsLigne = () => offline;
      expect(await c.signaler(_auto('Erreur A')), SupportIssue.enAttente);
      expect(srv.corps, isEmpty);
      offline = false;
      srv.reponse = SupportReponse.echec;
      expect(await c.signaler(_auto('Erreur B')), SupportIssue.enAttente);
      expect(c.enAttente, 2);
      // Persistance : relue par une nouvelle instance (redémarrage de l'appli).
      final (c2, srv2) = _centre(file: PrefsSupportFileStore());
      await c2.chargerReglage();
      expect(c2.enAttente, 2);
      expect(await c2.renvoyer(), 2);
      expect(srv2.corps.map((e) => e['messageCourt']), ['Erreur A', 'Erreur B']);
      expect(c2.enAttente, 0);
      expect((await PrefsSupportFileStore().lire()), isEmpty);
    });

    test('session absente : arrêt du renvoi sans insister ; abandon après 8 essais ; plafond 50 ; jamais d\'exception', () async {
      final (c, srv) = _centre();
      srv.reponse = SupportReponse.session;
      for (var i = 0; i < 3; i++) {
        await c.signaler(SupportEvent(type: 'APPLICATION', niveau: 'WARN', module: 'VENTE', messageCourt: 'M$i', auto: false));
      }
      expect(c.enAttente, 3);
      srv.corps.clear();
      expect(await c.renvoyer(), 0);
      expect(srv.corps, hasLength(1), reason: 'arrêt au premier échec');
      for (var i = 0; i < 10; i++) {
        await c.renvoyer();
      }
      expect(c.enAttente, 2, reason: 'le premier est abandonné après 8 essais');
      for (var i = 0; i < 60; i++) {
        await c.signaler(SupportEvent(type: 'APPLICATION', niveau: 'WARN', module: 'VENTE', messageCourt: 'N$i', auto: false));
      }
      expect(c.enAttente, SupportCentre.maxFile);
      c.envoi = (_) async => throw StateError('panne');
      expect(await c.signaler(_auto('x')), SupportIssue.enAttente);
    });
  });

  group('anti-tempête', () {
    test('20 envois automatiques par session, pas deux fois la même paire messageCourt|urlOuEcran', () async {
      final (c, srv) = _centre();
      expect(await c.signaler(_auto('Erreur 1')), SupportIssue.envoye);
      expect(await c.signaler(_auto('Erreur 1')), SupportIssue.dejaSignale);
      expect(await c.signaler(_auto('Erreur 1', ecran: 'AutreScreen')), SupportIssue.envoye);
      for (var i = 2; i < 30; i++) {
        await c.signaler(_auto('Erreur $i'));
      }
      expect(srv.corps, hasLength(20));
      expect(await c.signaler(_auto('Encore')), SupportIssue.limite);
      // Les signalements manuels ne sont pas limités.
      expect(await c.signaler(const SupportEvent(type: 'APPLICATION', niveau: 'INFO', module: 'MOBILE', messageCourt: 'Manuel', auto: false)),
          SupportIssue.envoye);
    });

    test('30 par heure, même après une nouvelle session ; de nouveau possible une heure plus tard', () async {
      var now = DateTime(2026, 10, 11, 9);
      final (c, srv) = _centre(clock: () => now);
      for (var i = 0; i < 20; i++) {
        await c.signaler(_auto('A$i'));
      }
      c.nouvelleSession('caisse1');
      for (var i = 0; i < 20; i++) {
        await c.signaler(_auto('B$i'));
      }
      expect(srv.corps, hasLength(30));
      now = now.add(const Duration(minutes: 61));
      expect(await c.signaler(_auto('C')), SupportIssue.envoye);
    });
  });

  group('troncature et filtrage', () {
    test('bornes du serveur : 500 / 255 / 4000 / payloadJson ≤ 4000 et toujours du JSON', () async {
      final (c, srv) = _centre();
      for (var i = 0; i < 40; i++) {
        c.noterAction('Action ${'x' * 400} $i');
      }
      expect(c.filAriane, hasLength(15));
      expect(c.filAriane.every((f) => f.length <= 200), isTrue);
      await c.signaler(_auto('m' * 600, ecran: 'e' * 300, stack: 's' * 9000, donnees: {'explication': 'z' * 5000}));
      final e = srv.corps.single;
      expect((e['messageCourt'] as String).length, 500);
      expect((e['urlOuEcran'] as String).length, 255);
      expect((e['stack'] as String).length, 4000);
      final pj = e['payloadJson'] as String;
      expect(pj.length, lessThanOrEqualTo(4000));
      expect(() => jsonDecode(pj), returnsNormally);
      expect(payloadBorne({'fil_ariane': List.filled(15, 'a' * 200), 'version': '1'}).length, lessThanOrEqualTo(4000));
    });

    test('données sensibles : mots de passe, jetons, cookies, e-mail, téléphone ; corps réduit au message', () {
      final t = SupportFiltre.texte('password=abc token: "xyz" Cookie: JSESSIONID=123ABC Authorization: Bearer eyJhbGc.x '
          'mail awa@pharma.ci tel 07 07 12 34 56 id 52141743589144800410');
      expect(t, isNot(contains('abc ')));
      expect(t, isNot(contains('xyz')));
      expect(t, isNot(contains('123ABC')));
      expect(t, isNot(contains('eyJhbGc')));
      expect(t, isNot(contains('awa@pharma.ci')));
      expect(t, isNot(contains('07 07 12 34 56')));
      expect(t, contains('52141743589144800410'), reason: 'identifiant technique gardé');
      expect(SupportFiltre.corpsReponse({'success': false, 'msg': 'Erreur', 'data': {'client': 'KONE'}}), '{"success":false,"msg":"Erreur"}');
      expect(SupportFiltre.corpsReponse('<html><head><style>p{}</style></head><body><h1>HTTP 500</h1><p>Erreur interne</p></body></html>'),
          'HTTP 500 Erreur interne');
      expect(SupportFiltre.chemin('http://srv:8080/prestige/api/v1/client/search?query=KONE%20AWA'), '/prestige/api/v1/client/search');
      expect(SupportFiltre.json({'msg': 'ok', 'nomClient': 'KONE', 'numSecu': '123', 'ordonnance': {}, 'qte': 2}), {'msg': 'ok', 'qte': 2});
    });
  });

  group('réglage et route absente', () {
    test('envoi automatique désactivé : rien ne part (le manuel si) ; réglage gardé, activé par défaut', () async {
      final (c, srv) = _centre();
      await c.chargerReglage();
      expect(c.envoiAuto, isTrue);
      await c.reglerEnvoiAuto(false);
      expect(await c.signaler(_auto('Erreur')), SupportIssue.desactive);
      expect(srv.corps, isEmpty);
      expect(await c.signaler(const SupportEvent(type: 'APPLICATION', niveau: 'WARN', module: 'MOBILE', messageCourt: 'Manuel', auto: false)),
          SupportIssue.envoye);
      final (c2, _) = _centre();
      await c2.chargerReglage();
      expect(c2.envoiAuto, isFalse);
      final j = await journal.lire();
      // Journal du terminal : type « Centre de support », résultat info.
      expect(j.every((e) => e.type == TypeJournal.support && e.resultat == ResultatJournal.info), isTrue);
      expect(j.map((e) => e.action), contains('Signalement transmis au centre de support'));
      expect(j.map((e) => e.action), contains('Envoi automatique des anomalies désactivé'));
    });

    test('centre inactif (instance par défaut des autres tests) : aucun envoi ni journal', () async {
      final c = SupportCentre(actif: false, envoi: (_) async => fail('aucun envoi'));
      expect(await c.signaler(_auto('x')), SupportIssue.desactive);
      expect(await c.renvoyer(), 0);
      expect(await journal.lire(), isEmpty);
    });

    test('route absente (404) : envoi suspendu proprement, file conservée, nouvel essai explicite ou autre serveur', () async {
      final (c, srv) = _centre();
      srv.reponse = SupportReponse.routeAbsente;
      expect(await c.signaler(_auto('Erreur 1')), SupportIssue.enAttente);
      expect(c.routeAbsente, isTrue);
      expect(await c.signaler(_auto('Erreur 2')), SupportIssue.enAttente);
      expect(srv.corps, hasLength(1), reason: 'plus d\'appel une fois la route absente');
      expect(c.enAttente, 2);
      expect(await c.renvoyer(), 0);
      expect(srv.corps, hasLength(1));
      final j = await journal.lire();
      expect(j.where((e) => e.action.startsWith('Centre de support absent')), hasLength(1));
      srv.reponse = SupportReponse.ok;
      c.serveurChange();
      expect(c.routeAbsente, isFalse);
      expect(await c.renvoyer(forcer: true), 2);
      expect(c.enAttente, 0);
    });

    test('envoi réel par Dio : 404 de la route → routeAbsente (serveur ancien)', () async {
      final envoi = DioSupportEnvoi(() => 'http://srv/prestige/api/v1');
      String? appel;
      envoi.dio.httpClientAdapter = _Adapter((o) async {
        appel = '${o.method} ${o.uri}';
        return ResponseBody.fromString('<html>404</html>', 404);
      });
      expect(await envoi.call({'messageCourt': 'x'}), SupportReponse.routeAbsente);
      expect(appel, 'POST http://srv/prestige/api/v1/support/events');
      expect(envoi.racine, 'http://srv/prestige');
      envoi.dio.httpClientAdapter = _Adapter((o) async {
        appel = '${o.method} ${o.uri}';
        return ResponseBody.fromString('{"success":true,"msg":"Votre demande a été enregistrée et transmise au support (réf. 9)"}', 200,
            headers: {Headers.contentTypeHeader: ['text/html;charset=UTF-8']});
      });
      final (r, msg) = await envoi.contacter(objet: 'o', message: 'm', moduleConcerne: 'VENTE', urgence: 'BASSE',
          pieces: [SupportPieceJointe('c.png', List.filled(10, 1))]);
      expect(r, SupportReponse.ok);
      expect(msg, contains('réf. 9'));
      expect(appel, 'POST http://srv/prestige/support-contact');
    });

    testWidgets('Réglages › Centre de support : modification protégée par le code administrateur', (tester) async {
      final (c, _) = _centre();
      var codeOk = false;
      await tester.pumpWidget(MaterialApp(home: SupportPage(centre: c, adminCheck: (_) async => codeOk)));
      await tester.tap(find.byKey(const Key('support_envoi_auto')));
      await tester.pumpAndSettle();
      expect(c.envoiAuto, isTrue);
      codeOk = true;
      await tester.tap(find.byKey(const Key('support_envoi_auto')));
      await tester.pumpAndSettle();
      expect(c.envoiAuto, isFalse);
      expect(find.text('Aucune anomalie en attente'), findsOneWidget);
    });
  });
}

class AccueilEssaiScreen extends StatelessWidget {
  const AccueilEssaiScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('accueil'));
}

class ReceptionEssaiPage extends StatelessWidget {
  const ReceptionEssaiPage({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('réception'));
}
