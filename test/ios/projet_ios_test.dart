// 4.5.0 — Projet iOS (iPhone + iPad, TestFlight) : Info.plist en français, autorisations, ATS (HTTP vers le
// serveur local), orientations, version tirée de pubspec.yaml, bundle ID paramétré (xcconfig), iOS 15.5 minimum
// (ML Kit), icônes opaques, CI macOS et TestFlight sans aucun secret dans le dépôt.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

String _lire(String p) => File(p).readAsStringSync();

/// Valeur (texte) d'une clé du premier niveau de l'Info.plist.
String? _cle(String plist, String cle) {
  final m = RegExp('<key>${RegExp.escape(cle)}</key>\\s*<(string|true|false)\\s*/?>([^<]*)').firstMatch(plist);
  if (m == null) return null;
  return m.group(1) == 'string' ? m.group(2) : m.group(1);
}

List<String> _tableau(String plist, String cle) {
  final m = RegExp('<key>${RegExp.escape(cle)}</key>\\s*<array>(.*?)</array>', dotAll: true).firstMatch(plist);
  return m == null ? const [] : [for (final x in RegExp('<string>([^<]*)</string>').allMatches(m.group(1)!)) x.group(1)!];
}

void main() {
  final plist = _lire('ios/Runner/Info.plist');

  test('Info.plist : nom, langue française, version de pubspec.yaml', () {
    expect(_cle(plist, 'CFBundleDisplayName'), 'Prestige Mobile');
    expect(_cle(plist, 'CFBundleDevelopmentRegion'), 'fr');
    expect(_cle(plist, 'CFBundleShortVersionString'), r'$(FLUTTER_BUILD_NAME)');
    expect(_cle(plist, 'CFBundleVersion'), r'$(FLUTTER_BUILD_NUMBER)');
    expect(_cle(plist, 'CFBundleIdentifier'), r'$(PRODUCT_BUNDLE_IDENTIFIER)');
    expect(RegExp(r'^version: (\d+\.\d+\.\d+)\+(\d+)$', multiLine: true).firstMatch(_lire('pubspec.yaml'))!.group(0), 'version: 4.5.0+21');
  });

  test('autorisations : textes en français pour chaque fonction utilisée', () {
    const cles = {
      'NSCameraUsageDescription': 'appareil photo',
      'NSMicrophoneUsageDescription': 'son',
      'NSPhotoLibraryUsageDescription': 'photos',
      'NSPhotoLibraryAddUsageDescription': 'photos',
      'NSLocationWhenInUseUsageDescription': 'pointage',
      'NSLocationAlwaysAndWhenInUseUsageDescription': 'jamais en arrière-plan',
      'NSLocalNetworkUsageDescription': 'réseau local',
    };
    cles.forEach((k, mot) {
      final v = _cle(plist, k);
      expect(v, isNotNull, reason: k);
      expect(v, contains(mot), reason: k);
      expect(v!.length, greaterThan(30), reason: '$k : phrase explicite');
    });
    expect(plist, isNot(contains('NSBluetooth')), reason: 'aucune autre autorisation');
  });

  test('ATS : HTTP vers le réseau local permis (NSAllowsLocalNetworking), jamais NSAllowsArbitraryLoads', () {
    final ats = RegExp('<key>NSAppTransportSecurity</key>\\s*<dict>(.*?)</dict>', dotAll: true).firstMatch(plist)!.group(1)!;
    expect(ats, contains('<key>NSAllowsLocalNetworking</key>'));
    expect(RegExp(r'<key>NSAllowsLocalNetworking</key>\s*<true/>').hasMatch(ats), isTrue);
    expect(plist, isNot(contains('NSAllowsArbitraryLoads')));
    expect(_cle(plist, 'ITSAppUsesNonExemptEncryption'), 'false', reason: 'HTTPS standard seulement : pas de question à chaque build');
    // Le client HTTP de l'application (Dio → dart:io) n'est soumis à aucune politique « HTTP non sûr » : vérifié
    // dans le SDK Dart installé (aucun contrôle de ce type dans dart:io / dart:_http).
    final sdk = Directory('${Platform.environment['FLUTTER_ROOT'] ?? ''}/bin/cache/dart-sdk/lib/_http');
    if (sdk.existsSync()) {
      final contenu = sdk.listSync().whereType<File>().map((f) => f.readAsStringSync()).join();
      expect(contenu.contains('Insecure HTTP is not allowed'), isFalse);
    }
  });

  test('iPhone + iPad : orientations ; écran de lancement', () {
    expect(_tableau(plist, 'UISupportedInterfaceOrientations'),
        ['UIInterfaceOrientationPortrait', 'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight']);
    expect(_tableau(plist, 'UISupportedInterfaceOrientations~ipad'), hasLength(4), reason: 'iPad : 4 orientations (multitâche)');
    expect(_cle(plist, 'UILaunchStoryboardName'), 'LaunchScreen');
    final pbx = _lire('ios/Runner.xcodeproj/project.pbxproj');
    expect(RegExp(r'TARGETED_DEVICE_FAMILY = "1,2";').allMatches(pbx).length, greaterThanOrEqualTo(3), reason: 'iPhone (1) et iPad (2)');
  });

  test('bundle ID : paramètre unique (xcconfig), valide pour iOS ; iOS 15.5 minimum partout', () {
    final xc = _lire('ios/Flutter/Prestige.xcconfig');
    final id = RegExp(r'^PRESTIGE_BUNDLE_ID = (.+)$', multiLine: true).firstMatch(xc)!.group(1)!.trim();
    expect(id, 'com.dici.prestigeventeapp');
    expect(RegExp(r'^[A-Za-z0-9.-]+$').hasMatch(id), isTrue, reason: '« _ » interdit');
    for (final f in ['ios/Flutter/Debug.xcconfig', 'ios/Flutter/Release.xcconfig']) {
      expect(_lire(f), contains('#include "Prestige.xcconfig"'), reason: f);
      expect(_lire(f), contains('#include? "Pods/Target Support Files/Pods-Runner/'), reason: f);
    }
    final pbx = _lire('ios/Runner.xcodeproj/project.pbxproj');
    expect(pbx, isNot(contains('com.example')));
    expect(RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = "\$\(PRESTIGE_BUNDLE_ID\)";').allMatches(pbx).length, 3, reason: 'Debug, Profile, Release');
    expect(RegExp(r'IPHONEOS_DEPLOYMENT_TARGET = (\S+);').allMatches(pbx).map((m) => m.group(1)).toSet(), {'15.5'});
    expect(_lire('ios/Podfile'), contains("platform :ios, '15.5'"));
    expect(_lire('ios/Podfile'), contains("config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.5'"));
  });

  test('icônes : toutes présentes et OPAQUES (exigé par l\'App Store), 1024 px pour la fiche', () {
    final dir = Directory('ios/Runner/Assets.xcassets/AppIcon.appiconset');
    final pngs = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.png')).toList();
    // Chaque icône déclarée existe (iPhone, iPad, fiche 1024).
    final declarees = RegExp(r'"filename"\s*:\s*"([^"]+)"').allMatches(_lire('${dir.path}/Contents.json')).map((m) => m.group(1)!).toSet();
    expect(declarees.length, greaterThanOrEqualTo(15));
    for (final n in declarees) {
      expect(File('${dir.path}/$n').existsSync(), isTrue, reason: n);
    }
    for (final f in pngs) {
      final b = Uint8List.fromList(f.readAsBytesSync());
      expect(b[25], isNot(6), reason: '${f.path} : pas de couche alpha (RGBA)');
      expect(b[25], isNot(4), reason: f.path);
    }
    final grand = File('${dir.path}/Icon-App-1024x1024@1x.png').readAsBytesSync();
    final l = ByteData.sublistView(Uint8List.fromList(grand), 16, 24);
    expect([l.getUint32(0), l.getUint32(4)], [1024, 1024]);
    expect(File('ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png').lengthSync(), greaterThan(1000), reason: 'logo, plus l\'image vide d\'origine');
  });

  test('CI : build macOS sans signature ; TestFlight seulement avec les 4 secrets, jamais de secret en clair', () {
    final w = _lire('.github/workflows/build-ios.yml');
    expect(w, contains('runs-on: macos-15'));
    expect(w, contains('flutter build ios --release --no-codesign'));
    expect(w, contains('flutter test test/ios'));
    for (final s in ['APP_STORE_CONNECT_KEY_ID', 'APP_STORE_CONNECT_ISSUER_ID', 'APP_STORE_CONNECT_PRIVATE_KEY', 'APPLE_TEAM_ID']) {
      expect(w, contains('secrets.$s'), reason: s);
    }
    expect(w, contains("if: needs.ios-build.outputs.testflight == 'true'"));
    expect(w, contains('-allowProvisioningUpdates'));
    expect(w, contains('shasum -a 256 -c'), reason: 'outil asc vérifié');
    expect(w, contains("ASC_VERSION: '5.14.3'"));
    expect(w, isNot(contains('BEGIN PRIVATE KEY')));
    expect(w, isNot(contains('echo "\$PRIVATE_KEY"')), reason: 'clé jamais affichée');
    final export = _lire('ios/ExportOptions.plist');
    expect(export, contains('__TEAM_ID__'));
    expect(export, contains('<string>app-store-connect</string>'));
    // Aucun Team ID (10 caractères majuscules / chiffres) ni clé .p8 dans le dossier ios/.
    for (final f in Directory('ios').listSync(recursive: true).whereType<File>()) {
      if (f.path.endsWith('.png')) continue;
      final t = f.readAsStringSync();
      expect(t.contains('PRIVATE KEY'), isFalse, reason: f.path);
      expect(RegExp(r'DEVELOPMENT_TEAM = [A-Z0-9]{10};').hasMatch(t), isFalse, reason: f.path);
    }
    // Les jobs Android ne changent pas d'emplacement : la liste des tests reste ligne 32 de build-apk.yml.
    expect(_lire('.github/workflows/build-apk.yml').split('\n')[31], contains('flutter test test/datamatrix_parser_test.dart'));
  });
}
