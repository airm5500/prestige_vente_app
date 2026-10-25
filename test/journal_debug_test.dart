// NON-RÉGRESSION — 4.7.1 (sécurité) : le journal de la console du mode DÉBOGAGE ne contient jamais de secret ni de
// donnée de client : ni mot de passe, ni cookie de session, ni jeton, ni clé X-Client-Ref, ni corps de requête ou de
// réponse, ni paramètres (recherche d'un client). Les tests tournent en mode débogage : le journal HTTP de DioClient
// y est actif, comme sur un téléphone de développement.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/utils/journal_debug.dart';

import 'outils/faux_serveur_prestige.dart';

void main() {
  late List<String> journal;
  late DebugPrintCallback avant;
  setUp(() {
    journal = [];
    avant = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => journal.add(m ?? '');
  });
  tearDown(() => debugPrint = avant);

  test('mode débogage : connexion, recherche d\'un client, erreur : ni mot de passe, ni cookie, ni corps, ni paramètre', () async {
    expect(kDebugMode, isTrue, reason: 'journal HTTP de DioClient actif sous les tests');
    await avecVraiHttp(() async {
      final s = FauxServeurPrestige();
      await s.demarrer();
      addTearDown(s.arreter);
      await DioClient.cookieJar.deleteAll();
      addTearDown(DioClient.cookieJar.deleteAll);
      s.routes['GET /client/all'] = (_) => FauxServeurPrestige.ok({
            'data': [
              {'lgCLIENTID': 'C1', 'strFIRSTNAME': 'PATIENTE', 'strLASTNAME': 'FICTIVE-NOM', 'strNUMEROSECURITESOCIAL': 'SECU-424242'}
            ]
          });
      s.routes['GET /officine'] = (_) => const ReponseLocale('<html>réponse illisible PATIENT-HTML</html>');
      final api = ApiService(baseUrl: s.base);
      expect(await api.login(DonneesFictives.login, DonneesFictives.motDePasse), isNotNull);
      await api.searchClientAssurance('FICTIVE-NOM');
      await api.fetchOfficineInfo();
      await DioClient.getClient(s.base).post('/vente/add/vno', data: {'clientId': 'C1'}, options: Options(headers: {'X-Client-Ref': 'HL2-cle-secrete-42'}));
      final cookie = (await DioClient.cookieJar.loadForRequest(Uri.parse(s.base))).map((c) => c.value).join(' ');
      final tout = journal.join('\n');
      expect(journal.where((l) => l.startsWith('HTTP POST /prestige/api/v1/user/auth → 200')), hasLength(1), reason: tout);
      for (final interdit in [
        DonneesFictives.motDePasse,
        DonneesFictives.login,
        'password',
        'FICTIVE-NOM',
        'PATIENTE',
        'SECU-424242',
        'PATIENT-HTML',
        'HL2-cle-secrete-42',
        'clientId',
        'JSESSIONID',
        'Set-Cookie',
        'set-cookie',
        'X-Prestige-Utilisateur',
        'X-Poste',
        'query=',
        if (cookie.isNotEmpty) cookie,
      ]) {
        expect(tout, isNot(contains(interdit)), reason: 'journal de la console : « $interdit »');
      }
    });
  });

  test('chemin journalisé sans valeur ; erreur résumée sans son message', () {
    expect(cheminSansParametres(Uri.parse('http://x/prestige/api/v1/licence/save/ABCD-1234-XYZ?y=1')), '/prestige/api/v1/licence/save/*');
    expect(cheminSansParametres(Uri.parse('http://x/prestige/api/v1/app-vente/client-ref/HL2-a1')), '/prestige/api/v1/app-vente/client-ref/*');
    expect(cheminSansParametres(Uri.parse('http://x/prestige/api/v1/vente/search?query=NOM')), '/prestige/api/v1/vente/search');
    final e = DioException(
      requestOptions: RequestOptions(path: 'http://x/prestige/api/v1/client/all?query=PATIENTE', method: 'GET'),
      response: Response(requestOptions: RequestOptions(path: 'x'), statusCode: 500, data: 'PATIENTE'),
      type: DioExceptionType.badResponse,
      message: 'PATIENTE',
    );
    expect(resumeErreur(e), 'DioException badResponse, HTTP 500 · GET /prestige/api/v1/client/all');
    expect(resumeErreur(const FormatException('Unexpected character <html>PATIENTE')), 'FormatException');
    journalErreur('Erreur test', const FormatException('PRESTIGE-BADGE|1|B001|login|SECRET'));
    expect(journal.single, 'Erreur test : FormatException');
  });

  test('garde-fou sur le code : aucun LogInterceptor, aucune erreur ni corps recopié dans la console', () {
    final interdits = [
      RegExp(r'LogInterceptor\('),
      // Le type d'une erreur (${e.runtimeType}) est permis, jamais l'erreur elle-même.
      RegExp(r'''\b(debugPrint|print)\([^;]*\$\{?(e|err|error|detail|url|response|data|body|corps)\b(?!\.runtimeType)'''),
      RegExp(r'''\bprint\('''),
    ];
    final fautes = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final lignes = f.readAsLinesSync();
      for (var i = 0; i < lignes.length; i++) {
        final l = lignes[i].trimLeft();
        if (l.startsWith('//')) continue;
        for (final r in interdits) {
          if (r.hasMatch(l)) fautes.add('${f.path}:${i + 1} : $l');
        }
      }
    }
    expect(fautes, isEmpty);
  });
}
