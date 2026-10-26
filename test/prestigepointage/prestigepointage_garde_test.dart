// NON-RÉGRESSION — Prestige Pointage 1.0.0 (saveur `pointage`) et Prestige Mobile 4.10.0 :
//  - version propre (android/app/prestigepointage-version.properties), saveurs Gradle (`mobile` par défaut, identité
//    de Prestige Mobile inchangée ; `pointage` = com.dici.prestigepointage), manifeste de la saveur (nom, icône, pas de
//    position), visibilité du paquet depuis Prestige Mobile (<queries>), canal natif limité à CE paquet ;
//  - CI : APK de Prestige Pointage construit et contrôlé ; envoi Google Play SEULEMENT par son fichier de demande
//    (android/DEMANDE_PLAY_POINTAGE), absent ici ;
//  - secrets : le secret de la borne n'est lu que pour la signature ; aucun print/debugPrint dans lib/prestigepointage ;
//    le QR du badge n'est jamais gardé ; le secret ne figure dans aucun fichier du dépôt (données fictives des tests) ;
//  - terminal de pointage de Prestige Mobile : valeurs par défaut inchangées.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/rh/pointage_rh.dart';
import 'package:prestige_vente_app/rh/terminal_pointage_screen.dart';

String _lire(String p) => File(p).readAsStringSync();

void main() {
  test('version propre de Prestige Pointage : 1.0.0 (code 1)', () {
    final p = _lire('android/app/prestigepointage-version.properties');
    expect(RegExp(r'^nomVersion=(.+)$', multiLine: true).firstMatch(p)!.group(1)!.trim(), '1.0.0');
    expect(RegExp(r'^codeVersion=(.+)$', multiLine: true).firstMatch(p)!.group(1)!.trim(), '1');
  });

  test('Gradle : `mobile` par défaut et identité de Prestige Mobile inchangée ; `pointage` séparée', () {
    final g = _lire('android/app/build.gradle.kts');
    expect(g, contains('applicationId = "com.dici.prestige_vente_app"'));
    expect(g, contains('versionCode = flutter.versionCode'));
    expect(g, contains('versionName = flutter.versionName'));
    expect(g, contains('create("pointage")'));
    expect(g, contains('applicationId = "com.dici.prestigepointage"'));
    expect(g, contains('prestigepointage-version.properties'));
    expect(g, isNot(contains('applicationIdSuffix')), reason: 'Prestige Mobile garde son identifiant exact');
    expect(_lire('pubspec.yaml'), contains(RegExp(r'^  default-flavor: mobile$', multiLine: true)));
  });

  test('manifestes : nom et icône de Prestige Pointage dans sa saveur ; pas de position ; <queries> de Mobile', () {
    final m = _lire('android/app/src/pointage/AndroidManifest.xml');
    expect(m, contains('android:label="Prestige Pointage"'));
    expect(m, contains('ACCESS_FINE_LOCATION" tools:node="remove"'));
    expect(m, contains('ACCESS_COARSE_LOCATION" tools:node="remove"'));
    final main = _lire('android/app/src/main/AndroidManifest.xml');
    expect(main, contains('android:label="Prestige Mobile"'), reason: 'nom de Prestige Mobile inchangé');
    expect(main, contains('<package android:name="com.dici.prestigepointage" />'));
    for (final d in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      expect(File('android/app/src/pointage/res/mipmap-$d/launcher_icon.png').existsSync(), isTrue, reason: 'icône $d');
    }
    final k = _lire('android/app/src/main/kotlin/com/dici/prestige_vente_app/MainActivity.kt');
    expect(k, contains('"prestige/pointage"'));
    expect(k, contains('paquet != "com.dici.prestigepointage"'), reason: 'canal limité à Prestige Pointage');
  });

  test('CI : APK Prestige Pointage construit et contrôlé ; Google Play seulement par DEMANDE_PLAY_POINTAGE (absent)', () {
    final ci = _lire('.github/workflows/build-apk.yml');
    expect(ci, contains('flutter build apk --release --flavor pointage -t lib/main_pointage.dart'));
    expect(ci, contains("package: name='com.dici.prestigepointage'"));
    expect(ci, contains('prestige-mobile-identique'), reason: 'identité et permissions de Prestige Mobile comparées à la 4.9.4');
    final play = _lire('.github/workflows/play-pointage.yml');
    expect(play, contains("- 'android/DEMANDE_PLAY_POINTAGE'"));
    expect(play, contains('--flavor pointage -t lib/main_pointage.dart'));
    expect(play, contains('play-pointage-'));
    expect(File('android/DEMANDE_PLAY_POINTAGE').existsSync(), isFalse, reason: 'aucun envoi Google Play déclenché');
    expect(_lire('.github/workflows/play.yml'), isNot(contains('prestigepointage')), reason: 'envoi de Prestige Mobile inchangé');
    // Saveur par défaut `mobile` : commande inchangée, sorties nommées d'après la saveur par Flutter.
    expect(_lire('.github/workflows/play.yml'), contains('sortie=build/app/outputs/bundle/mobileRelease/app-mobile-release.aab'));
    expect(_lire('.github/workflows/play.yml'), contains('apk=build/app/outputs/flutter-apk/app-mobile-release.apk'));
  });

  test('secrets : secret de la borne lu seulement pour signer ; aucune trace dans lib/prestigepointage', () {
    final usages = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final s = f.readAsStringSync();
      if (RegExp(r'identite\.secret|\bi\.secret\b').hasMatch(s)) usages.add(f.path.replaceAll('\\', '/'));
    }
    expect(usages, ['lib/prestigepointage/client_borne.dart'], reason: 'seule la signature lit le secret');
    for (final f in Directory('lib/prestigepointage').listSync().whereType<File>()) {
      final s = f.readAsStringSync();
      expect(s, isNot(contains(RegExp(r'\b(debugPrint|print)\('))), reason: '${f.path} : rien d\'écrit dans le journal');
    }
    for (final n in ['identite_borne', 'client_borne', 'enrolement_borne', 'controleur_borne', 'signature_borne']) {
      expect(_lire('lib/prestigepointage/$n.dart'), isNot(contains('SharedPreferences.getInstance')), reason: '$n : identité seulement dans le stockage sécurisé');
    }
    expect(_lire('lib/prestigepointage/identite_borne.dart'), contains('FlutterSecureStorage'));
  });

  test('aucun secret réel dans le dépôt : pas de fichier d\'identité de borne ni de clé de compte de service', () {
    final suspects = <String>[];
    for (final f in Directory('.').listSync(recursive: true, followLinks: false).whereType<File>()) {
      final p = f.path.replaceAll('\\', '/');
      if (p.contains('/.git/') || p.contains('/build/') || p.contains('/.dart_tool/')) continue;
      if (RegExp(r'prestigepointage_borne_v1\.json$|service[-_]account.*\.json$').hasMatch(p)) suspects.add(p);
    }
    expect(suspects, isEmpty);
  });

  test('terminal de pointage de Prestige Mobile : valeurs par défaut inchangées', () {
    final t = TerminalPointageScreen(rh: PointageRh());
    expect(t.titre, 'Terminal de pointage');
    expect(t.confirmerEnvoi, isTrue);
    expect(t.borneAuDemarrage, isFalse);
    expect(t.bandeau, isNull);
    expect(t.actionsEnPlus, isNull);
    expect(t.rafraichirAuDemarrage, isTrue);
  });
}
