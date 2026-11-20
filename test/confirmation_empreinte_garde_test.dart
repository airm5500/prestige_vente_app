// 5.3.0 — NON-RÉGRESSION (garde-fous) du pointage sans service d'empreinte Sunmi :
//  - aucune bibliothèque ajoutée (pas de local_auth) : la confirmation passe par le pont natif EXISTANT
//    (SunmiFingerprintBridge.authenticate, BiometricPrompt d'Android 9+ avec le contexte de l'activité) ; MainActivity
//    (Prestige Mobile et Prestige Pointage) reste une FlutterActivity : impression Sunmi, scanner, NFC et mode borne
//    (épinglage) inchangés ; permission USE_BIOMETRIC déjà présente, aucune nouvelle permission ;
//  - codes d'erreur natifs distingués (délai, lecteur absent, lecteur en panne) ;
//  - réglage désactivé par défaut, jamais appliqué quand le service Sunmi est présent (piste 4) ;
//  - aucune trace (print / debugPrint) ni stockage dans la confirmation ; rien de nouveau envoyé au serveur.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/rh/photo_controle.dart';

String _lire(String chemin) => File(chemin).readAsStringSync();

void main() {
  const kt = 'android/app/src/main/kotlin/com/dici/prestige_vente_app';

  test('aucune bibliothèque d\'empreinte ajoutée (pas de local_auth) ; pont natif existant', () {
    expect(_lire('pubspec.yaml'), isNot(contains('local_auth')));
    final pont = _lire('$kt/SunmiFingerprintBridge.kt');
    expect(pont, contains('"authenticate" -> authenticate('));
    expect(pont, contains('android.hardware.biometrics.BiometricPrompt.Builder(context)'));
    expect(_lire('lib/rh/confirmation_empreinte.dart'), contains('FingerprintService.authenticate'));
  });

  test('MainActivity reste une FlutterActivity (impression, scanner, NFC, borne inchangés)', () {
    final a = _lire('$kt/MainActivity.kt');
    expect(a, contains('class MainActivity : FlutterActivity()'));
    expect(a, isNot(contains('FlutterFragmentActivity')));
    expect(a, contains('SunmiFingerprintBridge(this, flutterEngine.dartExecutor.binaryMessenger)'));
    expect(a, contains('NfcBadgeBridge(this'));
    expect(a, contains('KiosqueBridge(this'));
  });

  test('permissions : USE_BIOMETRIC déjà présente ; Prestige Pointage n\'ajoute rien', () {
    final m = _lire('android/app/src/main/AndroidManifest.xml');
    expect(m, contains('android.permission.USE_BIOMETRIC'));
    expect(RegExp('uses-permission').allMatches(m), hasLength(7));
    final p = _lire('android/app/src/pointage/AndroidManifest.xml');
    expect(RegExp(r'<uses-permission[^>]*/>').allMatches(p).every((x) => x.group(0)!.contains('tools:node="remove"')), isTrue);
  });

  test('codes natifs : délai, lecteur absent, lecteur en panne distingués', () {
    final pont = _lire('$kt/SunmiFingerprintBridge.kt');
    for (final c in ['"CANCELED"', '"LOCKOUT"', '"NONE_ENROLLED"', '"TIMEOUT"', '"NO_HARDWARE"', '"HW_ERROR"', '"AUTH_ERROR"']) {
      expect(pont, contains(c));
    }
  });

  test('réglage désactivé par défaut ; jamais appliqué avec le service Sunmi (piste 4)', () {
    expect(const ReglagesPointageTerminal().confirmationEmpreinte, isFalse);
    final ecran = _lire('lib/rh/terminal_pointage_screen.dart');
    expect(ecran, contains('_reglages.confirmationEmpreinte && !_capacites.empreinte'));
    expect(ecran, contains('l.moyen != MoyenIdentification.empreinte'));
  });

  test('aucune trace ni stockage dans la confirmation ; corps du pointage inchangé', () {
    final c = _lire('lib/rh/confirmation_empreinte.dart');
    expect(c, isNot(contains('print(')));
    expect(c, isNot(contains('SharedPreferences')));
    expect(c, isNot(contains('FlutterSecureStorage')));
    final modeles = _lire('lib/rh/rh_models.dart');
    expect(modeles, isNot(contains('confirmation')), reason: 'rien de nouveau dans le corps envoyé à Prestige');
  });
}
