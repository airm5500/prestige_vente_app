// NON-RÉGRESSION — Prestige Mobile V3 5.0.1 : version de l'APK lue DIRECTEMENT dans pubspec.yaml par Gradle.
// Un build lancé depuis Android Studio sans commande flutter prenait flutter.versionName / flutter.versionCode dans un
// android/local.properties périmé (APK 4.10.0+36, « prestigepos-release-4.10.0.apk », au lieu de 5.0.0+49).
//  - android/app/build.gradle.kts : versionPubspec = expression appliquée à ../../pubspec.yaml ; l'expression est
//    reprise ici telle qu'écrite dans Gradle et appliquée au vrai pubspec.yaml (même résultat que l'APK) ;
//  - repli sur les valeurs de Flutter seulement si pubspec.yaml est absent ou sans « version: X.Y.Z+N » ;
//  - Prestige Pointage garde sa propre version (prestigepointage-version.properties) ;
//  - nom du fichier APK : PrestigeMobileV3-release-<versionName>.apk ; la CI le vérifie.
// L'APK lui-même est contrôlé par la CI (build-apk.yml : version de l'APK = pubspec.yaml, badging).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _lire(String p) => File(p).readAsStringSync();

/// Gradle sans commentaires de ligne (les expressions régulières de Gradle ne contiennent pas « // »).
String _sansCommentaires(String s) => s.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '').replaceAll(RegExp(r'//.*'), '');

/// Expression régulière de versionPubspec, telle qu'écrite dans build.gradle.kts (chaîne brute Kotlin """…""").
RegExp _expressionGradle(String gradle) {
  final m = RegExp(r'Regex\("""(.*?)""", RegexOption\.MULTILINE\)').firstMatch(gradle);
  expect(m, isNotNull, reason: 'Regex("""…""", RegexOption.MULTILINE) introuvable dans build.gradle.kts');
  return RegExp(m!.group(1)!, multiLine: true);
}

/// Ce que Gradle met dans l'APK : pubspec.yaml s'il donne X.Y.Z+N, sinon les valeurs de Flutter (local.properties).
(String, int) _versionApk(RegExp expression, String? pubspec, Map<String, String> localProperties) {
  final m = pubspec == null ? null : expression.firstMatch(pubspec);
  if (m != null) return (m.group(1)!, int.parse(m.group(2)!));
  return (localProperties['flutter.versionName']!, int.parse(localProperties['flutter.versionCode']!));
}

void main() {
  final gradle = _lire('android/app/build.gradle.kts');
  final code = _sansCommentaires(gradle);
  final pubspec = _lire('pubspec.yaml');
  final version = RegExp(r'^version:\s*(\S+)\s*$', multiLine: true).firstMatch(pubspec)!.group(1)!;

  group('Version lue dans pubspec.yaml (build Android Studio sans commande flutter)', () {
    test('Gradle lit ../../pubspec.yaml (depuis android/app : le pubspec.yaml du projet)', () {
      expect(code, contains('val versionPubspec: Pair<String, Int>? = file("../../pubspec.yaml")'));
      expect(File('android/app/../../pubspec.yaml').resolveSymbolicLinksSync(), File('pubspec.yaml').resolveSymbolicLinksSync());
      expect(code.indexOf('val versionPubspec'), lessThan(code.indexOf('android {')), reason: 'lue avant defaultConfig');
    });

    test('defaultConfig : pubspec.yaml d\'abord, valeurs de Flutter en repli seulement', () {
      expect(code, contains('versionCode = versionPubspec?.second ?: flutter.versionCode'));
      expect(code, contains('versionName = versionPubspec?.first ?: flutter.versionName'));
      // defaultConfig (Prestige Mobile V3), Prestige Pointage et, sur la branche prestigepos, PrestigePOS.
      expect(RegExp(r'^\s*versionCode\s*=', multiLine: true).allMatches(code), hasLength(code.contains('create("pos")') ? 3 : 2));
    });

    test('l\'expression de Gradle appliquée au vrai pubspec.yaml donne la version attendue de l\'APK', () {
      final (nom, numero) = _versionApk(_expressionGradle(gradle), pubspec, {});
      expect('$nom+$numero', version);
      expect('$nom+$numero', '5.4.0+54');
    });

    test('local.properties périmé (4.10.0+36) : ignoré, la version vient de pubspec.yaml', () {
      final perime = {'flutter.versionName': '4.10.0', 'flutter.versionCode': '36'};
      expect(_versionApk(_expressionGradle(gradle), pubspec, perime), ('5.4.0', 54));
    });

    test('repli : pubspec.yaml absent ou sans « version: X.Y.Z+N » → valeurs de Flutter', () {
      final e = _expressionGradle(gradle);
      final flutter = {'flutter.versionName': '9.9.9', 'flutter.versionCode': '99'};
      expect(_versionApk(e, null, flutter), ('9.9.9', 99));
      expect(_versionApk(e, 'name: x\nversion: 1.2.3\n', flutter), ('9.9.9', 99), reason: 'sans +N');
      expect(_versionApk(e, 'name: x\n  version: 1.2.3+4\n', flutter), ('9.9.9', 99), reason: 'clé indentée (pas la version)');
      expect(_versionApk(e, 'name: x\nversion: 1.2.3+4\nenvironment:\n', flutter), ('1.2.3', 4));
      expect(_versionApk(e, 'version: 10.20.30+400   \n', flutter), ('10.20.30', 400), reason: 'espaces en fin de ligne');
      expect(_versionApk(e, 'description: "version: 7.7.7+7"\nversion: 1.0.0+2\n', flutter), ('1.0.0', 2));
    });

    test('Prestige Pointage garde sa propre version (prestigepointage-version.properties)', () {
      expect(code, contains('versionCode = versionPointage.getProperty("codeVersion").trim().toInt()'));
      expect(code, contains('versionName = versionPointage.getProperty("nomVersion").trim()'));
    });
  });

  group('Nom du fichier APK', () {
    test('Prestige Mobile V3 : PrestigeMobileV3-release-<versionName>.apk (plus « prestigepos-release-… »)', () {
      expect(code, contains('else -> "PrestigeMobileV3"'));
      expect(code, contains('"pointage" -> "PrestigePointage"'));
      expect(code, contains(r'outputImpl.outputFileName = "$prefixe-${variante.buildType.name}-${variante.versionName}.apk"'));
      expect(code, isNot(contains('else -> "prestigepos"')));
    });

    test('CI : fichier nommé vérifié ; copie de Flutter (flutter-apk/app-mobile-release.apk) toujours renommée', () {
      final ci = _lire('.github/workflows/build-apk.yml');
      expect(ci, contains(r'ls ../apk/mobile/release/PrestigeMobileV3-release-${version%+*}.apk'));
      expect(ci, contains('if [ -f app-mobile-release.apk ]; then mv app-mobile-release.apk app-release.apk; fi'));
      expect(ci, contains(r"""grep -qE "^application: .*icon='[^']*\.png'" badging-mobile.txt"""),
          reason: '5.0.1 : icône sans cadre (PNG), jamais l\'icône adaptative XML');
    });

    test('note de version 5.0.1', () {
      final n = _lire('docs/NOTE_VERSION_5.0.1.md');
      for (final t in ['5.0.1+50', 'icônes sans cadre, comme les anciennes', 'pubspec.yaml', 'Android Studio',
        'PrestigeMobileV3-release-5.0.1.apk', 'local.properties']) {
        expect(n, contains(t), reason: t);
      }
      expect(_lire('docs/VERSIONS_SUNMI.md'), contains('5.0.1+50'));
    });
  });
}
