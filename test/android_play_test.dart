// Google Play (Prestige Mobile 4.5.0, PrestigePOS 1.3.0) : projet Android et envoi, sans SDK Android.
//  - signature : clé d'envoi lue dans les variables d'environnement puis android/key.properties (jamais commité) ;
//    repli sur la clé DEBUG avec un avertissement quand elle manque (APK Sunmi construits sur le PC du pharmacien et
//    APK de la CI : même signature qu'avant) ;
//  - targetSdk / compileSdk 36 SEULEMENT pour la version Play (propriété Gradle playStore passée par play.yml) ; les
//    builds locaux et l'APK de build-apk.yml gardent les valeurs de Flutter (35) : terminaux Sunmi inchangés ;
//  - comportements d'Android 16 neutralisés dans le manifeste (retour prédictif, orientation sur grand écran) ;
//  - play.yml : conventions communes aux 4 applications (noms des secrets, android/DEMANDE_PLAY), deux applications
//    (une par branche), aucun secret affiché, action épinglée par SHA, piste « internal », repli « draft », nettoyage.
// Ce fichier est le même sur les branches Prestige Mobile et prestigepos.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String lire(String chemin) => File(chemin).readAsStringSync();

void main() {
  final gradle = lire('android/app/build.gradle.kts');
  final play = lire('.github/workflows/play.yml');

  group('Signature', () {
    test('clé d\'envoi : variables d\'environnement, puis key.properties ; quatre réglages', () {
      for (final (env, prop) in [
        ('ANDROID_KEYSTORE_PATH', 'storeFile'),
        ('ANDROID_KEYSTORE_PASSWORD', 'storePassword'),
        ('ANDROID_KEY_ALIAS', 'keyAlias'),
        ('ANDROID_KEY_PASSWORD', 'keyPassword'),
      ]) {
        expect(gradle, contains('reglageCle("$env", "$prop")'));
      }
      expect(gradle, contains('rootProject.file("key.properties")'));
      expect(gradle, contains('System.getenv(variable)'), reason: 'la CI passe avant le fichier local');
    });

    test('repli sur la clé DEBUG si la clé manque ou si le fichier n\'existe pas, avec avertissement', () {
      expect(gradle, contains('fichierCle != null && fichierCle.exists()'));
      expect(gradle, contains('if (cleEnvoiComplete) {\n                signingConfigs.getByName("release")'));
      expect(gradle, contains('signingConfigs.getByName("debug")'));
      expect(gradle, contains('logger.warn('));
      expect(gradle, isNot(contains(RegExp(r'storePassword\s*=\s*"'))), reason: 'aucun mot de passe en clair');
      expect(gradle, isNot(contains(RegExp(r'keyPassword\s*=\s*"'))));
    });

    test('key.properties et fichiers de clé jamais commités', () {
      final ignore = lire('android/.gitignore');
      expect(ignore, contains('key.properties'));
      expect(ignore, contains('**/*.jks'));
      expect(ignore, contains('**/*.keystore'));
      expect(File('android/key.properties').existsSync(), isFalse);
      expect(Directory('android').listSync(recursive: true).where((f) => RegExp(r'\.(jks|keystore)$').hasMatch(f.path)), isEmpty);
    });
  });

  group('targetSdk 36 pour la version Play seulement (terminaux Sunmi inchangés)', () {
    test('propriété playStore : 36 si elle vaut true, sinon les valeurs de Flutter (35)', () {
      expect(gradle, contains('val versionPlay = (findProperty("playStore") as String?)?.trim()?.toBoolean() == true'));
      expect(gradle, contains('compileSdk = if (versionPlay) 36 else flutter.compileSdkVersion'));
      expect(gradle, contains('targetSdk = if (versionPlay) 36 else flutter.targetSdkVersion'));
      expect(RegExp(r'^\s*targetSdk\s*=', multiLine: true).allMatches(gradle), hasLength(1), reason: 'aucune saveur ne fixe son targetSdk');
      expect(lire('android/gradle.properties'), contains('android.suppressUnsupportedCompileSdk=36'));
    });

    test('Flutter 3.32.8 propose bien 35 : les builds sans playStore restent en targetSdk 35', () {
      // Valeur de FlutterExtension.kt de Flutter 3.32.8 (version de la CI). Si Flutter change, revoir ce choix.
      final ci = lire('.github/workflows/build-apk.yml');
      expect(ci, contains("flutter-version: '3.32.8'"));
      expect(ci, isNot(contains('playStore')), reason: 'APK de la CI (et du PC du pharmacien) : jamais la version Play');
      expect(ci, contains('flutter build apk --release'));
    });

    test('manifeste : retour prédictif désactivé, dérogation d\'orientation sur grand écran (neutres en 35)', () {
      final m = lire('android/app/src/main/AndroidManifest.xml');
      expect(m, contains('android:enableOnBackInvokedCallback="false"'));
      expect(m, contains('android:name="android.window.PROPERTY_COMPAT_ALLOW_RESTRICTED_RESIZABILITY"'));
      expect(m, contains('android:networkSecurityConfig="@xml/network_security_config"'), reason: 'HTTP vers le serveur local');
      expect(m, isNot(contains('windowOptOutEdgeToEdgeEnforcement')), reason: 'option supprimée par Android 16');
      for (final styles in Directory('android/app/src/main/res').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('styles.xml'))) {
        expect(styles.readAsStringSync(), isNot(contains('windowOptOutEdgeToEdgeEnforcement')), reason: styles.path);
      }
    });

    test('permissions de Prestige Mobile inchangées (aucune ne demande de déclaration Play)', () {
      final m = lire('android/app/src/main/AndroidManifest.xml');
      final permissions = RegExp(r'<uses-permission[^>]*android:name="([^"]+)"').allMatches(m).map((x) => x.group(1)).toSet();
      expect(permissions, {
        'android.permission.INTERNET',
        'android.permission.ACCESS_NETWORK_STATE',
        'android.permission.CAMERA',
        'android.permission.USE_BIOMETRIC',
        'android.permission.NFC',
        'android.permission.ACCESS_FINE_LOCATION',
        'android.permission.ACCESS_COARSE_LOCATION',
      });
      expect(m, isNot(contains('ACCESS_BACKGROUND_LOCATION')));
      expect(m, isNot(contains('QUERY_ALL_PACKAGES')));
      expect(m, contains('android:label="Prestige Mobile"'));
    });
  });

  group('Workflow Google Play', () {
    test('conventions communes aux 4 applications : secrets et fichier déclencheur', () {
      for (final s in ['ANDROID_KEYSTORE_BASE64', 'ANDROID_KEYSTORE_PASSWORD', 'ANDROID_KEY_ALIAS', 'ANDROID_KEY_PASSWORD', 'PLAY_SERVICE_ACCOUNT_JSON']) {
        expect(play, contains('secrets.$s'));
      }
      expect(play, contains('android/DEMANDE_PLAY'));
      expect(File('android/DEMANDE_PLAY').existsSync(), isFalse, reason: 'écrit seulement sur demande du pharmacien');
    });

    test('deux applications, une par branche : paquet, artefact, saveur, version', () {
      expect(play, contains("- 'pres-/tender-thompson-ang0ls'"));
      expect(play, contains("- 'prestigepos'"));
      expect(play, contains('echo "paquet=com.dici.prestige_vente_app"'));
      expect(play, contains('echo "artefact=prestige-mobile-aab"'));
      expect(play, contains('echo "paquet=com.dici.prestigepos"'));
      expect(play, contains('echo "artefact=prestigepos-aab"'));
      expect(play, contains('echo "options=--flavor pos -t lib/main_pos.dart"'));
      expect(play, contains('android/app/prestigepos-version.properties'));
      expect(play, contains('if [ "\$GITHUB_REF_NAME" = prestigepos ]'));
      expect(play, contains('(arrivée par fusion)'), reason: 'demande de Prestige Mobile ignorée sur prestigepos');
    });

    test('version Play : playStore=true partout où le bundle est construit ; contrôle targetSdk 36 et 16 Ko', () {
      expect(RegExp(r'flutter build appbundle --release \$OPTIONS --android-project-arg=playStore=true').allMatches(play), hasLength(2));
      expect(play, contains('flutter build apk --release \$OPTIONS --android-project-arg=playStore=true'));
      expect(play, contains("grep -q \"^targetSdkVersion:'36'\""));
      expect(play, contains('readelf -lW'));
      expect(play, contains('-lt 16384'));
    });

    test('envoi : action épinglée par SHA, piste internal, completed puis draft, nettoyage, aucun secret affiché', () {
      expect(RegExp(r'uses: r0adkll/upload-google-play@[0-9a-f]{40}').allMatches(play), hasLength(2));
      expect(play, contains('tracks: internal'));
      expect(play, contains('status: completed'));
      expect(play, contains('status: draft'));
      expect(play, contains('packageName: \${{ needs.verifier.outputs.paquet }}'));
      expect(play, contains('CN=Android Debug'), reason: 'un bundle signé en debug est refusé avant l\'envoi');
      expect(play, contains('rm -rf "\$RUNNER_TEMP/cle_android"'));
      expect(play, contains('umask 077'));
      expect(play, isNot(contains(RegExp(r'echo "?\$(KS|KSP|KA|KP|SA|ANDROID_KEYSTORE_PASSWORD|ANDROID_KEY_PASSWORD)\b'))), reason: 'aucun secret affiché');
      expect(play, isNot(contains('set -x')));
    });
  });
}
