// Rapport de tests de LIVRAISON (même script que Prestige Inventaire, étendu à la table des catégories).
//
// Lit les sorties JSON de `flutter test` (format `--machine`, écrites par la CI avec
// `--file-reporter json:build/rapport_tests/tests.json`) et produit un résumé Markdown :
//  - par catégorie : nombre de tests, réussis, sautés, échecs, durée ;
//  - les tests en échec et les tests sautés (avec leur motif, ex. « sauté : ANO-09 ») ;
//  - les MESURES de performance et de requêtes (lignes « PRESTIGE_MESURE {json} » — ou « PRESTINV_MESURE » —
//    imprimées par test/outils/performance.dart) : valeur, seuil, part du seuil utilisée.
//
// Catégorie d'un test : celle de son FICHIER dans test/categories.json (table versionnée, contrôlée par
// test/non_regression_test.dart) ; à défaut, le nom du fichier de résultats (« 3-e2e.json » → e2e, comme
// dans Prestige Inventaire où chaque catégorie a son étape).
//
// Utilisation :
//   dart run tool/rapport_tests.dart build/rapport_tests            # Markdown sur la sortie standard
//   dart run tool/rapport_tests.dart build/rapport_tests >> "$GITHUB_STEP_SUMMARY"
// Écrit aussi build/rapport_tests/rapport.md et build/rapport_tests/resume.json (artefact « rapport-tests »).
// Code de sortie 0 : le rapport ne décide pas du succès du job (l'étape de test échoue d'elle-même).
import 'dart:convert';
import 'dart:io';

/// Table versionnée : application, libellés des catégories, catégorie de chaque fichier de test.
class Table {
  final String application;
  final Map<String, String> libelles;
  final Map<String, String> fichiers;
  Table(this.application, this.libelles, this.fichiers);

  static Table lire(String chemin) {
    final f = File(chemin);
    if (!f.existsSync()) return Table('', const {}, const {});
    final j = json.decode(f.readAsStringSync()) as Map<String, dynamic>;
    return Table('${j['application'] ?? ''}', Map<String, String>.from(j['categories'] as Map? ?? const {}),
        Map<String, String>.from(j['fichiers'] as Map? ?? const {}));
  }
}

class Categorie {
  final String cle;
  final String libelle;
  int tests = 0, reussis = 0, sautes = 0, echecs = 0, fichiers = 0;

  /// Somme des durées de ses fichiers (les fichiers tournent en parallèle : durée cumulée).
  int dureeMs = 0;
  final List<String> enEchec = [];
  final List<String> sautesNoms = [];
  Categorie(this.cle, this.libelle);
}

class Mesure {
  final String categorie, nom, unite;
  final num valeur, seuil;
  final String? detail;
  Mesure(this.categorie, this.nom, this.valeur, this.seuil, this.unite, this.detail);
  double get part => seuil == 0 ? (valeur == 0 ? 0 : double.infinity) : valeur / seuil;
}

/// « /home/runner/work/x/x/test/reseau/https_test.dart » → « test/reseau/https_test.dart ».
String cheminRelatif(String p) {
  final n = p.replaceAll('\\', '/');
  final i = n.lastIndexOf('/test/');
  return i < 0 ? n : n.substring(i + 1);
}

/// « 3-e2e.json » → « e2e » (Prestige Inventaire : un fichier de résultats par catégorie).
String cleDeFichier(String fichier) {
  var n = fichier.split(Platform.pathSeparator).last.replaceAll('.json', '');
  final m = RegExp(r'^\d+-').firstMatch(n);
  if (m != null) n = n.substring(m.end);
  return n;
}

String duree(int ms) {
  final s = ms ~/ 1000;
  return s >= 60 ? '${s ~/ 60} min ${(s % 60).toString().padLeft(2, '0')} s' : '$s s';
}

String nombre(num v) {
  if (v is int || v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(1).replaceAll('.', ',');
}

final _prefixeMesure = RegExp(r'^PRESTI(GE|NV)_MESURE ');

void main(List<String> args) {
  final dossier = Directory(args.isEmpty ? 'build/rapport_tests' : args.first);
  final table = Table.lire(args.length > 1 ? args[1] : 'test/categories.json');
  final fichiers = dossier.existsSync()
      ? (dossier.listSync().whereType<File>().where((f) => f.path.endsWith('.json') && !f.path.endsWith('resume.json')).toList()
        ..sort((a, b) => a.path.compareTo(b.path)))
      : <File>[];

  // Catégories dans l'ordre de la table, puis celles rencontrées.
  final categories = <String, Categorie>{for (final e in table.libelles.entries) e.key: Categorie(e.key, e.value)};
  Categorie categorie(String cle) => categories.putIfAbsent(cle, () => Categorie(cle, cle == 'non_classes' ? 'Non classés (absents de test/categories.json)' : cle));
  final mesures = <Mesure>[];
  var dureeTotaleMs = 0;
  var interrompu = false;

  for (final f in fichiers) {
    final parDefaut = cleDeFichier(f.path);
    final suites = <int, String>{}; // suite → chemin relatif
    final debutSuite = <int, int>{}, finSuite = <int, int>{};
    final testSuite = <int, int>{}; // test → suite
    final noms = <int, String>{};
    final skipMotif = <int, String?>{};
    var termine = false;
    var tempsMax = 0;
    String cleSuite(int? suite) {
      final chemin = suite == null ? null : suites[suite];
      if (chemin == null) return table.fichiers.isEmpty ? parDefaut : 'non_classes';
      return table.fichiers[chemin] ?? (table.fichiers.isEmpty ? parDefaut : 'non_classes');
    }

    for (final ligne in f.readAsLinesSync()) {
      if (!ligne.startsWith('{')) continue;
      final Map<String, dynamic> e;
      try {
        e = json.decode(ligne) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      final t = e['time'];
      if (t is int && t > tempsMax) tempsMax = t;
      switch (e['type']) {
        case 'suite':
          final s = e['suite'] as Map<String, dynamic>;
          suites[s['id'] as int] = cheminRelatif('${s['path']}');
        case 'testStart':
          final test = e['test'] as Map<String, dynamic>;
          final id = test['id'] as int;
          final suite = test['suiteID'] as int?;
          noms[id] = '${test['name']}';
          if (suite != null) {
            testSuite[id] = suite;
            debutSuite.putIfAbsent(suite, () => t as int);
          }
          skipMotif[id] = (test['metadata'] as Map?)?['skipReason'] as String?;
        case 'testDone':
          final id = e['testID'] as int;
          final suite = testSuite[id];
          if (suite != null && t is int) finSuite[suite] = t;
          final c = categorie(cleSuite(suite));
          final nom = noms[id] ?? '?';
          if (e['hidden'] == true) {
            // Chargement d'un fichier en échec (erreur de compilation) : compté comme un échec.
            if (e['result'] != 'success') {
              c.tests++;
              c.echecs++;
              c.enEchec.add(nom);
            }
            continue;
          }
          c.tests++;
          if (e['skipped'] == true) {
            c.sautes++;
            final motif = skipMotif[id];
            c.sautesNoms.add(motif == null || motif.isEmpty ? nom : '$nom — $motif');
          } else if (e['result'] == 'success') {
            c.reussis++;
          } else {
            c.echecs++;
            c.enEchec.add('$nom (${suite == null ? '?' : suites[suite]})');
          }
        case 'print':
          final cle = cleSuite(testSuite[e['testID']]);
          for (final l in '${e['message']}'.split('\n')) {
            final m = _prefixeMesure.firstMatch(l);
            if (m == null) continue;
            try {
              final d = json.decode(l.substring(m.end)) as Map<String, dynamic>;
              mesures.add(Mesure(cle, '${d['nom']}', d['valeur'] as num, d['seuil'] as num, '${d['unite']}', d['detail'] as String?));
            } catch (_) {}
          }
        case 'done':
          termine = true;
      }
    }
    for (final s in suites.keys) {
      final c = categorie(cleSuite(s));
      c.fichiers++;
      final d = debutSuite[s], fin = finSuite[s];
      if (d != null && fin != null && fin > d) c.dureeMs += fin - d;
    }
    dureeTotaleMs += tempsMax;
    if (!termine) interrompu = true;
  }

  final utilisees = [for (final c in categories.values) if (c.tests > 0 || c.fichiers > 0) c];
  final total = Categorie('total', 'Total');
  for (final c in utilisees) {
    total
      ..tests += c.tests
      ..reussis += c.reussis
      ..sautes += c.sautes
      ..echecs += c.echecs
      ..fichiers += c.fichiers
      ..dureeMs += c.dureeMs;
  }

  final b = StringBuffer();
  final pubspec = File('pubspec.yaml');
  final version = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec.existsSync() ? pubspec.readAsStringSync() : '')?.group(1);
  final appli = table.application.isEmpty ? 'Prestige' : table.application;
  b.writeln('## Rapport de tests de livraison — $appli${version == null ? '' : ' $version'}');
  b.writeln();
  if (utilisees.isEmpty) {
    b.writeln('Aucun résultat de test trouvé dans `${dossier.path}`.');
  } else {
    b.writeln(total.echecs == 0 && !interrompu
        ? '**Tous les tests exécutés sont réussis.**'
        : '**${total.echecs} test(s) en échec${interrompu ? ' — exécution interrompue' : ''}.**');
    b.writeln();
    b.writeln('| Catégorie | Fichiers | Tests | Réussis | Sautés | Échecs | Durée cumulée |');
    b.writeln('|---|---:|---:|---:|---:|---:|---:|');
    for (final c in utilisees) {
      b.writeln('| ${c.libelle} | ${c.fichiers} | ${c.tests} | ${c.reussis} | ${c.sautes} | ${c.echecs == 0 ? '0' : '**${c.echecs}**'} | ${duree(c.dureeMs)} |');
    }
    b.writeln('| **Total** | **${total.fichiers}** | **${total.tests}** | **${total.reussis}** | **${total.sautes}** | **${total.echecs}** | **${duree(total.dureeMs)}** |');
    b.writeln();
    b.writeln('Durée réelle de la suite (fichiers en parallèle) : ${duree(dureeTotaleMs)}.');
    b.writeln();
  }

  if (mesures.isNotEmpty) {
    b.writeln('### Mesures de performance et de requêtes (seuils qui font échouer la CI)');
    b.writeln();
    b.writeln('| Catégorie | Mesure | Valeur | Seuil | Part du seuil | État |');
    b.writeln('|---|---|---:|---:|---:|:---:|');
    for (final m in mesures) {
      final part = m.part.isFinite ? '${(m.part * 100).round()} %' : '—';
      final etat = m.valeur > m.seuil ? '❌ dépassé' : (m.part > 0.8 && m.unite == 'ms' ? '⚠️ proche' : '✅');
      final detail = m.detail == null || m.detail!.isEmpty ? '' : '<br><sub>${m.detail}</sub>';
      b.writeln('| ${categories[m.categorie]?.libelle ?? m.categorie} | ${m.nom}$detail | ${nombre(m.valeur)} ${m.unite} | ${nombre(m.seuil)} ${m.unite} | $part | $etat |');
    }
    b.writeln();
  }

  final echecs = [for (final c in utilisees) for (final n in c.enEchec) '- ${c.libelle} : $n'];
  if (echecs.isNotEmpty) {
    b.writeln('### Tests en échec');
    b.writeln();
    echecs.forEach(b.writeln);
    b.writeln();
  }
  final sautes = [for (final c in utilisees) for (final n in c.sautesNoms) '- ${c.libelle} : $n'];
  if (sautes.isNotEmpty) {
    b.writeln('<details><summary>Tests sautés (${sautes.length}) — anomalies connues, voir test/README.md</summary>');
    b.writeln();
    sautes.forEach(b.writeln);
    b.writeln();
    b.writeln('</details>');
  }

  final texte = b.toString();
  stdout.write(texte);
  if (dossier.existsSync()) {
    File('${dossier.path}/rapport.md').writeAsStringSync(texte);
    File('${dossier.path}/resume.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
      'application': appli,
      'version': version,
      'dureeMs': dureeTotaleMs,
      'categories': [
        for (final c in utilisees)
          {
            'categorie': c.cle,
            'libelle': c.libelle,
            'fichiers': c.fichiers,
            'tests': c.tests,
            'reussis': c.reussis,
            'sautes': c.sautes,
            'echecs': c.echecs,
            'dureeMs': c.dureeMs,
          },
      ],
      'mesures': [
        for (final m in mesures) {'categorie': m.categorie, 'nom': m.nom, 'valeur': m.valeur, 'seuil': m.seuil, 'unite': m.unite, if (m.detail != null) 'detail': m.detail},
      ],
    }));
  }
}
