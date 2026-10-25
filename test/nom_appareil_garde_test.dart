// NON-RÉGRESSION — 4.7.0 : tout client HTTP de l'application qui parle à Prestige porte l'en-tête X-Poste. Garde-fou
// sur le code : chaque fichier de lib/ qui crée un Dio le branche (avecDeploiement, qui pose IntercepteurPoste, ou
// IntercepteurPoste.brancher), et aucun autre client HTTP (HttpClient, paquet http) n'est utilisé.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chaque Dio créé dans lib/ reçoit IntercepteurPoste', () {
    final sansPoste = <String>[];
    var creations = 0;
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final code = f.readAsStringSync();
      final n = RegExp(r'\bDio\(').allMatches(code).length;
      if (n == 0) continue;
      creations += n;
      final branches = RegExp(r'avecDeploiement\(|IntercepteurPoste\.brancher\(').allMatches(code).length;
      // panne_serveur.dart définit avecDeploiement (une occurrence de plus que ses appels).
      if (branches < n) sansPoste.add('${f.path} : $n Dio, $branches branchement(s)');
    }
    expect(creations, greaterThan(10), reason: 'garde-fou actif');
    expect(sansPoste, isEmpty);
  });

  test('aucun autre client HTTP vers le serveur (HttpClient, paquet http)', () {
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final code = f.readAsStringSync();
      expect(code.contains("package:http/"), isFalse, reason: f.path);
      expect(RegExp(r'\bHttpClient\(').hasMatch(code), isFalse, reason: f.path);
    }
  });

  test('avecDeploiement pose IntercepteurPoste', () {
    final code = File('lib/serveur/panne_serveur.dart').readAsStringSync();
    final i = code.indexOf('Dio avecDeploiement(Dio d) {');
    expect(i, greaterThan(0));
    expect(code.substring(i, code.indexOf('\n}', i)), contains('IntercepteurPoste.brancher(d)'));
  });
}
