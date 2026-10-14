// Version « installée » simulée pour les tests : celle de pubspec.yaml (source unique), via
// PackageInfo.setMockInitialValues — aucun numéro de version recopié dans les tests.
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:prestige_vente_app/version_app.dart';

/// `X.Y.Z+N` de pubspec.yaml.
String versionPubspec() =>
    RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1)!;

/// Simule le paquet installé construit depuis pubspec.yaml (versionName X.Y.Z, versionCode N) et oublie la
/// version déjà lue par [VersionApp]. Renvoie `X.Y.Z+N`.
String simulerVersionInstallee() {
  final v = versionPubspec().split('+');
  PackageInfo.setMockInitialValues(
    appName: 'Prestige Mobile',
    packageName: 'com.dici.prestige_vente_app',
    version: v.first,
    buildNumber: v.length > 1 ? v[1] : '',
    buildSignature: '',
  );
  VersionApp.oublier();
  return versionPubspec();
}
