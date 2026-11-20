// NON-RÉGRESSION — Prestige Mobile V3 (5.0.0) : NOUVELLE application Android, seule l'identité change.
//  - Gradle : applicationId com.dici.prestigemobile.v3 (saveur `mobile`), namespace INCHANGÉ (MainActivity, R, et
//    l'activité retirée par PrestigePOS : com.dici.prestige_vente_app.MainActivity) ; PrestigePOS et Prestige Pointage
//    gardent leur identifiant ; version 5.4.0+54 lue dans pubspec.yaml.
//  - Manifeste : nom « Prestige Mobile V3 », icône (5.0.1 : plus d'icône ronde) ; visibilité de l'ANCIENNE application seulement dans
//    la saveur `mobile` (src/mobile), jamais QUERY_ALL_PACKAGES ; canal natif : ancienne application seulement pour
//    « estInstallee » (jamais ouverte).
//  - Icônes (5.0.1) : SANS cadre, comme l'ancienne : PNG transparents seulement (ni adaptative, ni ronde), dessin
//    pleine toile à l'encombrement de l'ancienne icône, badge « V3 », aucun liseré blanc ; toutes les densités.
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

/// Ancienne icône (Prestige Mobile 4.15.2, commit 48528e8, PNG transparent sans cadre) : moyenne largeur / hauteur du
/// cadre du dessin (alpha > 8), rapportée à la toile, par densité (0,90 × 1,00 environ).
const _ancienneMoyenne = {'mdpi': 0.958, 'hdpi': 0.958, 'xhdpi': 0.948, 'xxhdpi': 0.951, 'xxxhdpi': 0.948};

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

    test('version 5.4.0+54 (pubspec.yaml, source unique)', () {
      expect(RegExp(r'^version: (\S+)$', multiLine: true).firstMatch(_lire('pubspec.yaml'))!.group(1), '5.4.0+54');
    });

    test('manifeste : nom « Prestige Mobile V3 », icône (sans icône ronde depuis 5.0.1), aucune nouvelle permission', () {
      final m = _lire('android/app/src/main/AndroidManifest.xml');
      expect(m, contains('android:label="Prestige Mobile V3"'));
      expect(m, contains('android:icon="@mipmap/launcher_icon"'));
      expect(m, isNot(contains('android:roundIcon')),
          reason: '5.0.1 : comme l\'ancienne application ; Prestige Pointage (et PrestigePOS) déclarent la leur');
      expect(_lire('android/app/src/pointage/AndroidManifest.xml'), contains('android:roundIcon="@mipmap/launcher_icon_round"'),
          reason: 'Prestige Pointage inchangée');
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

    test('5.0.1 : SANS cadre, comme l\'ancienne icône : ni icône adaptative ni fond blanc ni icône ronde', () {
      expect(Directory('$res/mipmap-anydpi-v26').existsSync() && Directory('$res/mipmap-anydpi-v26').listSync().isNotEmpty,
          isFalse, reason: 'icône adaptative = dessin réduit dans un carré blanc sur le lanceur Sunmi');
      for (final d in [...Directory(res).listSync().whereType<Directory>()]) {
        for (final f in d.listSync().whereType<File>()) {
          final nom = f.uri.pathSegments.last;
          expect(nom.startsWith('launcher_icon') && nom.endsWith('.xml'), isFalse, reason: f.path);
          expect(nom, isNot(anyOf('launcher_icon_round.png', 'launcher_icon_foreground.png')), reason: f.path);
        }
      }
      expect(File('$res/values/couleurs_prestigemobile.xml').existsSync(), isFalse, reason: 'fond blanc de l\'icône adaptative');
      final m = _lire('android/app/src/main/AndroidManifest.xml');
      expect(m, contains('android:icon="@mipmap/launcher_icon"'));
      expect(m, isNot(contains('roundIcon')), reason: 'l\'ancienne application n\'avait pas d\'icône ronde');
    });

    for (final e in _densites.entries) {
      final px = (48 * e.value).round();
      test('${e.key} : launcher_icon.png $px px transparent, dessin pleine toile comme l\'ancienne icône, badge « V3 »', () {
        final i = img.decodePng(File('$res/mipmap-${e.key}/launcher_icon.png').readAsBytesSync())!;
        expect([i.width, i.height], [px, px]);
        expect(i.numChannels, 4, reason: 'fond transparent (RGBA)');
        // Coins transparents (aucun fond, aucun cadre).
        for (final (x, y) in [(0, 0), (px - 1, 0), (0, px - 1), (px - 1, px - 1), (1, 1), (px - 2, px - 2)]) {
          expect(i.getPixel(x, y).a, 0, reason: 'coin ($x, $y)');
        }
        // Cadre du dessin (alpha > 8) : même encombrement que l'ancienne icône de la même densité (4.15.2, 48528e8).
        var x0 = px, y0 = px, x1 = -1, y1 = -1;
        var badge = 0, texteBadge = 0, liseres = 0;
        for (var y = 0; y < px; y++) {
          for (var x = 0; x < px; x++) {
            final p = i.getPixel(x, y);
            final a = p.a.toInt(), r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
            if (a > 8) {
              x0 = math.min(x0, x);
              y0 = math.min(y0, y);
              x1 = math.max(x1, x);
              y1 = math.max(y1, y);
            }
            final coinBadge = x >= px * 0.6 && y < px * 0.3;
            if (coinBadge && a > 200 && g > r + 40 && g > b + 20) badge++;
            if (coinBadge && a > 200 && math.min(r, math.min(g, b)) > 200) texteBadge++;
            // Liseré blanc : pixel semi-transparent quasi blanc hors du badge (bordé de blanc par dessin).
            if (!coinBadge && a > 0 && a < 200 && math.min(r, math.min(g, b)) > 235) liseres++;
          }
        }
        final largeur = (x1 - x0 + 1) / px, hauteur = (y1 - y0 + 1) / px;
        final moyenne = (largeur + hauteur) / 2;
        expect(moyenne, closeTo(_ancienneMoyenne[e.key]!, 0.03),
            reason: 'dessin ${largeur.toStringAsFixed(3)} × ${hauteur.toStringAsFixed(3)} de la toile '
                '(ancienne : ${_ancienneMoyenne[e.key]}) — 5.0.0 adaptative : environ 0,6 dans un cadre');
        expect(math.max(largeur, hauteur), greaterThan(0.9), reason: 'dessin grand, pas réduit');
        expect((x0 - (px - 1 - x1)).abs(), lessThanOrEqualTo(math.max(2, px ~/ 24)), reason: 'centré horizontalement');
        expect((y0 - (px - 1 - y1)).abs(), lessThanOrEqualTo(math.max(2, px ~/ 24)), reason: 'centré verticalement');
        expect(badge, greaterThan(px * px ~/ 60), reason: 'badge vert « V3 » en haut à droite');
        expect(texteBadge, greaterThan(0), reason: 'texte blanc du badge (bordure et « V3 »)');
        expect(liseres, 0, reason: 'aucun liseré blanc sur les bords (fond d\'écran sombre)');
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
      if (ci.contains('REFERENCE_MOBILE:')) {
        // Branche prestigepos (même fichier de test) : Prestige Mobile V3 comparée à la Prestige Mobile V3 de référence.
        expect(ci, contains('APK de référence (5.'), reason: 'référence : Prestige Mobile V3 (5.x, 5.1.0 depuis PrestigePOS 1.14.0)');
      } else {
        expect(ci, contains('identite-reference-v3.txt'), reason: 'identité de la 4.9.4 : seuls l\'identifiant et le nom changent');
        expect(ci, contains('diff -u permissions-reference-v3.txt actuel/permissions-mobile.txt'), reason: 'permissions identiques');
        expect(ci, contains('s/com\\.dici\\.prestige_vente_app\\./com.dici.prestigemobile.v3./g'),
            reason: 'seule la permission nommée d\'après l\'identifiant (DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION) suit le nouvel identifiant');
      }
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
