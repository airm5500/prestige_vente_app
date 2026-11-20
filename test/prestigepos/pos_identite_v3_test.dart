// PrestigePOS 1.13.3 / 1.13.4 — Prestige Mobile V3 (5.0.0, puis 5.0.1 : icônes sans cadre) fusionnée : l'identité de PrestigePOS est
// INCHANGÉE (PrestigePOS ne fait pas partie de la V3).
//  - identifiant com.dici.prestigepos, nom « PrestigePOS », activité PosActivity (saveur pos) ;
//  - icônes : fichiers de src/pos/res identiques à ceux de PrestigePOS 1.13.2 (empreintes MD5) ; chaque ressource
//    d'icône que Prestige Mobile V3 ajoute dans src/main/res est remplacée par celle de src/pos (sinon l'APK
//    PrestigePOS prendrait le panier « V3 ») ;
//  - visibilité de l'ancienne Prestige Mobile (bandeau de la V3) : saveur mobile seulement, jamais dans PrestigePOS ;
//  - écrans de PrestigePOS : aucun nom de Prestige Mobile V3.
// L'APK lui-même est contrôlé par la CI (job prestigepos : aapt2 dump badging).
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

String _lire(String f) => File(f).readAsStringSync();

/// Empreintes des fichiers d'icône de PrestigePOS 1.13.2 (avant la fusion de Prestige Mobile V3).
const _empreintes = {
  'mipmap-hdpi/launcher_icon.png': '4bb0aa9010e7aad6e221ef72a3c32e4c',
  'mipmap-hdpi/launcher_icon_foreground.png': '872d265fa724ef4fc57e3ecd9a52f76e',
  'mipmap-hdpi/launcher_icon_round.png': '5153944e16ffb34b77a6af78a1622079',
  'mipmap-mdpi/launcher_icon.png': '5cc21101e3047802fbc34b5eba78ed50',
  'mipmap-mdpi/launcher_icon_foreground.png': 'a0cb04bee56ff5985b35aff5ccdb7b5e',
  'mipmap-mdpi/launcher_icon_round.png': '4ed1088c0aaef5cb467ad9158bac0387',
  'mipmap-xhdpi/launcher_icon.png': '5f958b8bce6258ff147e4648e4ff665d',
  'mipmap-xhdpi/launcher_icon_foreground.png': '241dd04dba42e287830d1b021b7c733f',
  'mipmap-xhdpi/launcher_icon_round.png': 'a549a1a30dc5fedbe38683f26667d892',
  'mipmap-xxhdpi/launcher_icon.png': 'd69e84a0bb64a413340a5fcf60c57897',
  'mipmap-xxhdpi/launcher_icon_foreground.png': '8f915d8d80aff22a86e6160820ab4d32',
  'mipmap-xxhdpi/launcher_icon_round.png': '6ae5895a0d0776c4e6a94185d41aae86',
  'mipmap-xxxhdpi/launcher_icon.png': 'f4b8ff9d1c474aae345ad2acffccc18c',
  'mipmap-xxxhdpi/launcher_icon_foreground.png': 'ed0ebc0a2c71356c61bd3c1ab97a5e4a',
  'mipmap-xxxhdpi/launcher_icon_round.png': '2cb8e5a31299f8229921489fe91ad84d',
  'mipmap-anydpi-v26/launcher_icon.xml': '32acab7e377090cc22731d0938aa324b',
  'mipmap-anydpi-v26/launcher_icon_round.xml': '32acab7e377090cc22731d0938aa324b',
  'values/couleurs_prestigepos.xml': '2d968f8e968f0b8061fd43a48be43fb4',
};

void main() {
  test('identifiant, nom et activité de PrestigePOS inchangés (Prestige Mobile V3 seulement dans la saveur mobile)', () {
    final g = _lire('android/app/build.gradle.kts');
    final pos = RegExp(r'create\("pos"\)\s*\{([^}]*)\}').firstMatch(g)!.group(1)!;
    expect(pos, contains('applicationId = "com.dici.prestigepos"'));
    expect(g, contains('applicationId = "com.dici.prestigemobile.v3"'), reason: 'defaultConfig = Prestige Mobile V3');
    final m = _lire('android/app/src/pos/AndroidManifest.xml');
    expect(m, contains('android:label="PrestigePOS"'));
    expect(m, contains('tools:replace="android:label,android:icon"'));
    expect(m, contains('android:roundIcon="@mipmap/launcher_icon_round"'),
        reason: 'icône ronde de PrestigePOS (src/pos) gardée ; Prestige Mobile V3 n\'en déclare plus (5.0.1)');
    expect(_lire('android/app/src/main/AndroidManifest.xml'), isNot(contains('roundIcon')), reason: 'Prestige Mobile V3 5.0.1 : sans cadre');
    expect(m, contains('com.dici.prestigepos.PosActivity'));
    expect(m, isNot(contains('<package android:name="com.dici.prestige_vente_app"')));
    expect(_lire('android/app/src/mobile/AndroidManifest.xml'), contains('<package android:name="com.dici.prestige_vente_app" />'),
        reason: 'visibilité de l\'ancienne application : saveur mobile seulement');
  });

  test('icônes de PrestigePOS : fichiers identiques à la 1.13.2', () {
    for (final e in _empreintes.entries) {
      final f = File('android/app/src/pos/res/${e.key}');
      expect(f.existsSync(), isTrue, reason: e.key);
      expect(md5.convert(f.readAsBytesSync()).toString(), e.value, reason: '${e.key} modifié');
    }
  });

  test('chaque ressource d\'icône de Prestige Mobile V3 (src/main) est remplacée par celle de PrestigePOS (src/pos)', () {
    final main = Directory('android/app/src/main/res')
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path.replaceAll('\\', '/').split('android/app/src/main/res/').last)
        .where((p) => p.startsWith('mipmap'))
        .toList();
    expect(main, isNotEmpty);
    for (final p in main) {
      expect(File('android/app/src/pos/res/$p').existsSync(), isTrue, reason: '$p de Prestige Mobile V3 sans remplaçant PrestigePOS');
    }
    // 1.13.4 (Prestige Mobile V3 5.0.1 : icônes sans cadre) : src/main n'a plus que des launcher_icon.png
    // transparents ; PrestigePOS garde son icône adaptative, ronde et son fond (src/pos), utilisés par son manifeste.
    expect(main.where((p) => p.contains('anydpi') || p.contains('_round') || p.contains('_foreground')), isEmpty);
    expect(File('android/app/src/main/res/values/couleurs_prestigemobile.xml').existsSync(), isFalse);
    expect(_lire('android/app/src/pos/res/values/couleurs_prestigepos.xml'), contains('name="launcher_icon_background"'));
    for (final n in ['launcher_icon', 'launcher_icon_round']) {
      expect(_lire('android/app/src/pos/res/mipmap-anydpi-v26/$n.xml'), contains('@color/launcher_icon_background'), reason: n);
    }
  });

  test('écrans de PrestigePOS : aucun nom de Prestige Mobile V3', () {
    for (final f in Directory('lib/prestigepos').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final s = f.readAsStringSync();
      expect(s, isNot(contains('identite_appli.dart')), reason: f.path);
      expect(s, isNot(contains('Prestige Mobile V3')), reason: f.path);
    }
    expect(_lire('lib/main_pos.dart'), isNot(contains('nomAppli')));
  });

  test('CI : badging de l\'APK PrestigePOS (identifiant, nom, activité, pas d\'identité de Prestige Mobile V3)', () {
    final ci = _lire('.github/workflows/build-apk.yml');
    expect(ci, contains("package: name='com.dici.prestigepos' versionCode='\$code' versionName='\$nom'"));
    expect(ci, contains("application-label:'PrestigePOS'"));
    expect(ci, contains("launchable-activity: name='com.dici.prestigepos.PosActivity'"));
    expect(ci, contains('grep -qE "prestigemobile|Prestige Mobile|com.dici.prestige_vente_app.MainActivity"'));
    expect(ci, contains('REFERENCE_MOBILE: f798f4180a02787a51d84fa5ce1286da338d1d66'), reason: 'référence : Prestige Mobile V3 5.2.0+52 (PrestigePOS 1.15.0)');
    expect(ci, contains(r"""grep -qE "^application: .*icon='[^']*\.xml'"""), reason: '1.13.4 : icône adaptative de PrestigePOS inchangée');
  });
}
