// PrestigePOS 1.3.0 — Google Play (piste « Test interne »), sans SDK Android :
//  - workflow play.yml : sur la branche prestigepos, saveur pos (com.dici.prestigepos), version de
//    prestigepos-version.properties, artefact prestigepos-aab ;
//  - targetSdk 36 seulement pour la version Play : la saveur pos ne fixe pas son targetSdk, l'APK des bornes Sunmi
//    (build-apk.yml, PC du pharmacien) est construit sans playStore ;
//  - règles de Google Play pour une borne (docs/android/README.md, section 11) : administrateur de l'appareil sans
//    politique, alias HOME désactivé par défaut, tâche verrouillée, démarrage automatique, Bluetooth, USB.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String lire(String f) => File(f).readAsStringSync();

void main() {
  final play = lire('.github/workflows/play.yml');
  final gradle = lire('android/app/build.gradle.kts');
  final pos = lire('android/app/src/pos/AndroidManifest.xml');

  test('workflow Play : branche prestigepos → saveur pos, com.dici.prestigepos, artefact prestigepos-aab', () {
    expect(play, contains("- 'prestigepos'"));
    final bloc = RegExp(r'if \[ "\$GITHUB_REF_NAME" = prestigepos \]; then(.*?)else', dotAll: true).firstMatch(play)!.group(1)!;
    expect(bloc, contains('android/app/prestigepos-version.properties'));
    expect(bloc, contains('echo "paquet=com.dici.prestigepos"'));
    expect(bloc, contains('echo "artefact=prestigepos-aab"'));
    expect(bloc, contains('echo "options=--flavor pos -t lib/main_pos.dart"'));
    expect(bloc, contains('build/app/outputs/bundle/posRelease/app-pos-release.aab'));
    expect(bloc, contains('build/app/outputs/flutter-apk/app-pos-release.apk'));
    expect(File('lib/main_pos.dart').existsSync(), isTrue);
  });

  test('targetSdk 36 pour la version Play seulement : la saveur pos ne le fixe pas, APK des bornes sans playStore', () {
    final saveur = RegExp(r'create\("pos"\)\s*\{([^}]*)\}').firstMatch(gradle)!.group(1)!;
    expect(saveur, isNot(contains('targetSdk')));
    expect(saveur, isNot(contains('compileSdk')));
    expect(gradle, contains('targetSdk = if (versionPlay) 36 else flutter.targetSdkVersion'));
    final ci = lire('.github/workflows/build-apk.yml');
    expect(ci, contains('flutter build apk --release --flavor pos -t lib/main_pos.dart'));
    expect(ci, isNot(contains('playStore')));
  });

  test('administrateur de l\'appareil sans aucune politique (propriétaire seulement par adb)', () {
    final admin = lire('android/app/src/pos/res/xml/prestigepos_admin.xml');
    expect(admin, contains('<uses-policies />'));
    expect(pos, contains('android:permission="android.permission.BIND_DEVICE_ADMIN"'));
  });

  test('HOME désactivé par défaut, tâche verrouillée autorisée seulement si permise, démarrage automatique', () {
    final alias = RegExp(r'<activity-alias(.*?)</activity-alias>', dotAll: true).firstMatch(pos)!.group(1)!;
    expect(alias, contains('android:enabled="false"'));
    expect(alias, contains('android.intent.category.HOME'));
    expect(pos, contains('android:lockTaskMode="if_whitelisted"'));
    expect(pos, contains('android.permission.RECEIVE_BOOT_COMPLETED'));
    expect(pos, isNot(contains('LOCKED_BOOT_COMPLETED')));
  });

  test('Bluetooth sans localisation, anciennes permissions limitées à Android 11, USB facultatif', () {
    expect(RegExp(r'BLUETOOTH_SCAN"\s*android:usesPermissionFlags="neverForLocation"').hasMatch(pos), isTrue);
    expect(RegExp(r'android.permission.BLUETOOTH" android:maxSdkVersion="30"').hasMatch(pos), isTrue);
    expect(RegExp(r'android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30"').hasMatch(pos), isTrue);
    expect(pos, contains('<uses-feature android:name="android.hardware.usb.host" android:required="false" />'));
    expect(pos, contains('<uses-feature android:name="android.hardware.bluetooth" android:required="false" />'));
    for (final interdite in ['ACCESS_BACKGROUND_LOCATION', 'QUERY_ALL_PACKAGES', 'SYSTEM_ALERT_WINDOW', 'REQUEST_INSTALL_PACKAGES']) {
      expect(pos, isNot(contains(interdite)), reason: '$interdite demanderait une déclaration Play');
    }
  });
}
