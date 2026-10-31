// PrestigePOS — construction : deux applications dans le même projet (saveurs Android), sans toucher Prestige Mobile.
//  - version de PrestigePOS 1.8.2+24 (android/app/prestigepos-version.properties), pubspec.yaml inchangé ;
//  - saveurs `mobile` (par défaut, sans applicationId propre) et `pos` (com.dici.prestigepos) ;
//  - permissions Bluetooth / USB et activité PrestigePOS dans le manifeste de la saveur pos SEULEMENT ;
//  - icônes PrestigePOS (toutes densités, adaptative, ronde) ; configurations Android Studio versionnées ;
//  - CI : job prestigepos-apk ;
//  - 1.8.0 : saveur `pointage` (Prestige Pointage) à côté ; aucun bouton « Pointer » dans PrestigePOS.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

String lire(String f) => File(f).readAsStringSync();

/// Largeur et hauteur d'un PNG (en-tête IHDR).
(int, int) taillePng(String f) {
  final b = ByteData.sublistView(File(f).readAsBytesSync());
  return (b.getUint32(16), b.getUint32(20));
}

void main() {
  test('version de PrestigePOS : 1.8.2+24, propre à la saveur pos', () {
    final p = lire('android/app/prestigepos-version.properties');
    expect(RegExp(r'^nomVersion=(.+)$', multiLine: true).firstMatch(p)!.group(1)!.trim(), '1.8.2');
    expect(RegExp(r'^codeVersion=(\d+)$', multiLine: true).firstMatch(p)!.group(1), '24');
    final g = lire('android/app/build.gradle.kts');
    expect(g, contains('getProperty("nomVersion")'));
    expect(g, contains('getProperty("codeVersion")'));
    expect(lire('pubspec.yaml'), matches(RegExp(r'^version: 4\.\d+\.\d+\+\d+', multiLine: true)), reason: 'pubspec = Prestige Mobile');
  });

  test('saveurs : mobile par défaut (Prestige Mobile inchangé), pos = com.dici.prestigepos', () {
    final g = lire('android/app/build.gradle.kts');
    expect(g, contains('applicationId = "com.dici.prestige_vente_app"'), reason: 'defaultConfig de Prestige Mobile');
    final mobile = RegExp(r'create\("mobile"\)\s*\{([^}]*)\}').firstMatch(g)!.group(1)!;
    expect(mobile, isNot(contains('applicationId')), reason: 'Prestige Mobile garde son applicationId');
    expect(mobile, isNot(contains('version')));
    final pos = RegExp(r'create\("pos"\)\s*\{([^}]*)\}').firstMatch(g)!.group(1)!;
    expect(pos, contains('applicationId = "com.dici.prestigepos"'));
    expect(lire('pubspec.yaml'), matches(RegExp(r'^  default-flavor: mobile$', multiLine: true)),
        reason: '« flutter build apk --release » sans --flavor construit Prestige Mobile');
  });

  test('manifestes : Bluetooth / USB et activité PrestigePOS dans la saveur pos seulement', () {
    final main = lire('android/app/src/main/AndroidManifest.xml');
    final pos = lire('android/app/src/pos/AndroidManifest.xml');
    for (final p in ['BLUETOOTH', 'BLUETOOTH_ADMIN', 'BLUETOOTH_SCAN', 'BLUETOOTH_CONNECT']) {
      expect(pos, contains('android.permission.$p"'));
      expect(main, isNot(contains('android.permission.$p"')), reason: 'Prestige Mobile sans $p');
    }
    expect(pos, contains('android:maxSdkVersion="30"'), reason: 'BLUETOOTH / BLUETOOTH_ADMIN : Android ≤ 11');
    expect(pos, contains('neverForLocation'));
    expect(pos, contains('android:label="PrestigePOS"'));
    expect(pos, contains('com.dici.prestigepos.PosActivity'));
    expect(pos, contains('tools:node="remove"'));
    expect(main, contains('android:label="Prestige Mobile"'));
    expect(File('android/app/src/pos/kotlin/com/dici/prestigepos/ImprimantesPlugin.kt').existsSync(), isTrue);
    expect(Directory('android/app/src/main/kotlin').listSync(recursive: true).where((f) => f.path.contains('Imprimantes')), isEmpty,
        reason: 'pont des imprimantes absent de Prestige Mobile');
  });

  test('icônes PrestigePOS : toutes densités, adaptative (fond blanc), ronde', () {
    const dens = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0};
    for (final e in dens.entries) {
      final d = 'android/app/src/pos/res/mipmap-${e.key}';
      expect(taillePng('$d/launcher_icon.png'), ((48 * e.value).round(), (48 * e.value).round()), reason: e.key);
      expect(taillePng('$d/launcher_icon_round.png'), ((48 * e.value).round(), (48 * e.value).round()), reason: e.key);
      expect(taillePng('$d/launcher_icon_foreground.png'), ((108 * e.value).round(), (108 * e.value).round()), reason: e.key);
    }
    for (final f in ['launcher_icon.xml', 'launcher_icon_round.xml']) {
      final x = lire('android/app/src/pos/res/mipmap-anydpi-v26/$f');
      expect(x, contains('<adaptive-icon'));
      expect(x, contains('@color/launcher_icon_background'));
    }
    expect(lire('android/app/src/pos/res/values/couleurs_prestigepos.xml'), contains('#FFFFFF'));
  });

  test('Android Studio : configurations « Prestige Mobile » et « PrestigePOS » versionnées', () {
    final m = lire('.run/Prestige Mobile.run.xml');
    expect(m, contains('name="Prestige Mobile"'));
    expect(m, contains('<option name="buildFlavor" value="mobile" />'));
    expect(m, contains('lib/main.dart'));
    final p = lire('.run/PrestigePOS.run.xml');
    expect(p, contains('name="PrestigePOS"'));
    expect(p, contains('<option name="buildFlavor" value="pos" />'));
    expect(p, contains('lib/main_pos.dart'));
  });

  test('CI : APK Prestige Mobile inchangé (même commande, même artefact) et APK PrestigePOS', () {
    final ci = lire('.github/workflows/build-apk.yml');
    expect(ci, contains('run: flutter build apk --release\n'));
    expect(ci, contains('name: prestige-vente-apk'));
    expect(ci, contains('flutter build apk --release --flavor pos -t lib/main_pos.dart'));
    expect(ci, contains('name: prestigepos-apk'));
    expect(ci, contains('flutter test test/prestigepos'));
    expect(ci, contains('GITHUB_STEP_SUMMARY'));
  });

  test('1.8.0 : trois saveurs (mobile, pos, pointage) ; aucun « Pointer » dans PrestigePOS', () {
    final g = lire('android/app/build.gradle.kts');
    final pointage = RegExp(r'create\("pointage"\)\s*\{([^}]*)\}').firstMatch(g)!.group(1)!;
    expect(pointage, contains('applicationId = "com.dici.prestigepointage"'));
    expect(g, contains('"pos" -> "PrestigePOS"'));
    expect(g, contains('"pointage" -> "PrestigePointage"'));
    final ci = lire('.github/workflows/build-apk.yml');
    expect(ci, contains('flutter build apk --release --flavor pointage -t lib/main_pointage.dart'));
    // Borne tournée vers les clients : ni bouton ni canal natif de Prestige Pointage dans la saveur pos.
    for (final d in ['lib/prestigepos', 'lib/borne']) {
      for (final f in Directory(d).listSync(recursive: true).whereType<File>()) {
        expect(f.readAsStringSync(), isNot(contains('BoutonPointer')), reason: f.path);
        expect(f.readAsStringSync(), isNot(contains('menuPrestigePointage')), reason: f.path);
      }
    }
    expect(lire('android/app/src/pos/kotlin/com/dici/prestigepos/PosActivity.kt'), isNot(contains('prestige/pointage')));
    expect(lire('lib/prestigepos/pos_app.dart'), contains('LanceurPointage.detecteur = () async => false;'));
  });
}
