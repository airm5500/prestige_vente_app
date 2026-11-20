// NON-RÉGRESSION — Prestige Mobile V3 (5.0.0) : NOUVELLE application Android, seule l'identité change.
//  - Gradle : applicationId com.dici.prestigemobile.v3 (saveur `mobile`), namespace INCHANGÉ (MainActivity, R, et
//    l'activité retirée par PrestigePOS : com.dici.prestige_vente_app.MainActivity) ; PrestigePOS et Prestige Pointage
//    gardent leur identifiant ; version 5.0.0+49 lue dans pubspec.yaml.
//  - Manifeste : nom « Prestige Mobile V3 », icône et icône ronde ; visibilité de l'ANCIENNE application seulement dans
//    la saveur `mobile` (src/mobile), jamais QUERY_ALL_PACKAGES ; canal natif : ancienne application seulement pour
//    « estInstallee » (jamais ouverte).
//  - Icônes : héritées, rondes et adaptatives (fond blanc, avant-plan contenu dans la zone de sécurité de 66 dp : le
//    badge « V3 » n'est coupé par aucun masque), toutes les densités, tailles exactes.
//  - Nom affiché : constante nomAppli, plus de « Prestige Mobile » en dur dans les écrans qui nomment l'application ;
//    contenu envoyé au serveur (support) inchangé.
//  - CI et Google Play : badging de l'APK (identifiant, nom, version), paquet Play ; note de version.
// L'APK lui-même est contrôlé par la CI (build-apk.yml, aapt2 dump badging) : aucun SDK Android ici.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:prestige_vente_app/identite_appli.dart';
import 'package:prestige_vente_app/support/support_centre.dart';

String _lire(String p) => File(p).readAsStringSync();

const _densites = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0};

void main() {
  group('Identité Android', () {
    final gradle = _lire('android/app/build.gradle.kts');

    test('applicationId com.dici.prestigemobile.v3 ; namespace inchangé ; aucun suffixe', () {
      expect(gradle, contains('applicationId = "com.dici.prestigemobile.v3"'));
      expect(gradle, contains('namespace = "com.dici.prestige_vente_app"'), reason: 'paquet Kotlin, R et activité inchangés');
      expect(RegExp(r'^\s*applicationId\s*=\s*"com\.dici\.prestige_vente_app"', multiLine: true).hasMatch(gradle), isFalse,
          reason: 'ancien identifiant : plus construit (fiche Sunmi gardée telle quelle)');
      expect(gradle, isNot(contains('applicationIdSuffix')));
      expect(File('android/app/src/main/kotlin/com/dici/prestige_vente_app/MainActivity.kt').existsSync(), isTrue);
    });

    test('Prestige Pointage garde son identifiant (saveur)', () {
      expect(gradle, contains('applicationId = "com.dici.prestigepointage"'));
      expect(_lire('android/app/src/pointage/AndroidManifest.xml'), contains('android:label="Prestige Pointage"'));
    });

    test('version 5.0.0+49 (pubspec.yaml, source unique)', () {
      expect(RegExp(r'^version: (\S+)$', multiLine: true).firstMatch(_lire('pubspec.yaml'))!.group(1), '5.0.0+49');
    });

    test('manifeste : nom « Prestige Mobile V3 », icône et icône ronde, aucune nouvelle permission', () {
      final m = _lire('android/app/src/main/AndroidManifest.xml');
      expect(m, contains('android:label="Prestige Mobile V3"'));
      expect(m, contains('android:icon="@mipmap/launcher_icon"'));
      expect(m, contains('android:roundIcon="@mipmap/launcher_icon_round"'),
          reason: 'même valeur que PrestigePOS et Prestige Pointage : aucun conflit de fusion du manifeste');
      expect(m, isNot(contains('QUERY_ALL_PACKAGES')));
      expect(m, isNot(contains('com.dici.prestige_vente_app')), reason: 'visibilité de l\'ancienne appli : saveur mobile seulement');
    });

    test('saveur mobile : visibilité de l\'ANCIENNE application seulement (aucune permission, aucune activité)', () {
      final m = _lire('android/app/src/mobile/AndroidManifest.xml');
      expect(m, contains('<package android:name="com.dici.prestige_vente_app" />'));
      expect(m, isNot(contains('uses-permission')));
      expect(m, isNot(contains('<activity')));
      expect(m, isNot(contains('<application')));
    });

    test('canal natif : ancienne application seulement pour estInstallee, jamais ouverte', () {
      final k = _lire('android/app/src/main/kotlin/com/dici/prestige_vente_app/MainActivity.kt');
      expect(k, contains('paquet == "com.dici.prestige_vente_app" && call.method == "estInstallee"'));
      expect(k, contains('paquet != "com.dici.prestigepointage"'), reason: '« ouvrir » toujours limité à Prestige Pointage');
    });

    test('aucun identifiant de paquet en dur dans lib/ hors de l\'identité (ancienne appli) et de Prestige Pointage', () {
      final trouves = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        final s = f.readAsStringSync();
        for (final id in ['com.dici.prestige_vente_app', 'com.dici.prestigemobile']) {
          if (s.contains("'$id") && !f.path.endsWith('identite_appli.dart')) trouves.add('${f.path} : $id');
        }
      }
      expect(trouves, isEmpty);
      expect(AncienneAppli.paquet, 'com.dici.prestige_vente_app');
    });
  });

  group('Icônes du lanceur (Prestige Mobile V3)', () {
    const res = 'android/app/src/main/res';

    test('icône adaptative : fond blanc, avant-plan ; versions ronde et carrée', () {
      for (final n in ['launcher_icon', 'launcher_icon_round']) {
        final x = _lire('$res/mipmap-anydpi-v26/$n.xml');
        expect(x, contains('<background android:drawable="@color/launcher_icon_background" />'));
        expect(x, contains('<foreground android:drawable="@mipmap/launcher_icon_foreground" />'));
      }
      expect(_lire('$res/values/couleurs_prestigemobile.xml'), contains('<color name="launcher_icon_background">#FFFFFF</color>'));
    });

    for (final e in _densites.entries) {
      test('${e.key} : icônes héritées ${(48 * e.value).round()} px, avant-plan ${(108 * e.value).round()} px dans la zone de sécurité',
          () {
        for (final n in ['launcher_icon', 'launcher_icon_round']) {
          final i = img.decodePng(File('$res/mipmap-${e.key}/$n.png').readAsBytesSync())!;
          expect(i.width, (48 * e.value).round(), reason: n);
          expect(i.height, (48 * e.value).round(), reason: n);
        }
        final fg = img.decodePng(File('$res/mipmap-${e.key}/launcher_icon_foreground.png').readAsBytesSync())!;
        final px = (108 * e.value).round();
        expect(fg.width, px);
        expect(fg.height, px);
        // Zone de sécurité : cercle de 66 dp de diamètre au centre de la toile de 108 dp (aucun masque ne la coupe).
        final rayonSur = 33 * e.value;
        var hors = 0, visibles = 0;
        for (var y = 0; y < px; y++) {
          for (var x = 0; x < px; x++) {
            final a = fg.getPixel(x, y).a;
            if (a <= 8) continue;
            visibles++;
            final d = math.sqrt(math.pow(x + 0.5 - px / 2, 2) + math.pow(y + 0.5 - px / 2, 2));
            if (d > rayonSur) hors++;
          }
        }
        expect(visibles, greaterThan(px * px ~/ 6), reason: 'avant-plan non vide (panier et badge)');
        expect(hors, 0, reason: 'pixels visibles hors de la zone de sécurité : le masque couperait le badge');
      });
    }

    test('logo de l\'application (écrans de connexion) : image V3, déclarée dans pubspec.yaml', () {
      final i = img.decodePng(File('assets/icon/icon_v3.png').readAsBytesSync())!;
      expect(i.width, 512);
      expect(_lire('pubspec.yaml'), contains('- assets/icon/icon_v3.png'));
      expect(_lire('lib/connexion/connexion_commun.dart'), contains("'assets/icon/icon_v3.png'"));
    });
  });

  group('Nom affiché', () {
    test('nomAppli = « Prestige Mobile V3 »', () => expect(nomAppli, 'Prestige Mobile V3'));

    test('écrans qui nomment l\'application : plus de « Prestige Mobile » en dur', () {
      for (final f in [
        'lib/connexion/connexion_screen.dart',
        'lib/connexion/lancement_screen.dart',
        'lib/connexion/qui_etes_vous_screen.dart',
        'lib/connexion/connexion_commun.dart',
        'lib/accueil/accueil_screen.dart',
        'lib/screens/home/home_screen.dart',
        'lib/main.dart',
      ]) {
        final code = _lire(f).split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
        expect(code, isNot(contains("'Prestige Mobile'")), reason: f);
        expect(code, isNot(contains("'Prestige Vente'")), reason: f);
      }
    });

    test('support : champ « application » envoyé au serveur inchangé (contrat du serveur)', () {
      expect(SupportCentre.application, 'Prestige Mobile');
    });
  });

  group('CI, Google Play et note de version', () {
    test('build-apk.yml : badging de l\'APK (identifiant, nom, version de pubspec.yaml)', () {
      final ci = _lire('.github/workflows/build-apk.yml');
      expect(ci, contains("grep -q \"^package: name='com.dici.prestigemobile.v3' versionCode='\${version#*+}' versionName='\${version%+*}'\" badging-mobile.txt"));
      expect(ci, contains("grep -q \"^application-label:'Prestige Mobile V3'\" badging-mobile.txt"));
      expect(ci, contains("launchable-activity: name='com.dici.prestige_vente_app.MainActivity'"));
      expect(ci, contains('identite-reference-v3.txt'), reason: 'identité de la 4.9.4 : seuls l\'identifiant et le nom changent');
      expect(ci, contains('diff -u permissions-reference-v3.txt actuel/permissions-mobile.txt'), reason: 'permissions identiques');
      expect(ci, contains('s/com\\.dici\\.prestige_vente_app\\./com.dici.prestigemobile.v3./g'),
          reason: 'seule la permission nommée d\'après l\'identifiant (DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION) suit le nouvel identifiant');
    });

    test('play.yml : paquet com.dici.prestigemobile.v3, envoi toujours gardé (secrets + DEMANDE_PLAY)', () {
      final play = _lire('.github/workflows/play.yml');
      expect(play, contains('echo "paquet=com.dici.prestigemobile.v3"'));
      expect(play, contains('echo "nom=Prestige Mobile V3"'));
      expect(play, contains("if: needs.verifier.outputs.cle == 'true'"));
      expect(play, contains("if: needs.verifier.outputs.envoi == 'true'"));
      expect(File('android/DEMANDE_PLAY').existsSync(), isFalse);
      expect(_lire('docs/android/README.md'), contains('com.dici.prestigemobile.v3'));
    });

    test('note de version 5.0.0 : nouvelle appli, ancienne fiche, reconfiguration, ventes hors ligne, dernier commit', () {
      final n = _lire('docs/NOTE_VERSION_5.0.0.md');
      for (final t in [
        'com.dici.prestigemobile.v3',
        'com.dici.prestige_vente_app',
        'Prestige Mobile V3',
        'hors ligne',
        'reconfigur',
        '48528e8647bc3819f9e461933e210e630579b465',
      ]) {
        expect(n, contains(t), reason: t);
      }
      expect(_lire('docs/VERSIONS_SUNMI.md'), contains('5.0.0+49'));
    });
  });
}
