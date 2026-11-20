// PrestigePOS 1.16.0 — Prestige Mobile V3 5.3.0 fusionnée (pointage sur un terminal sans service d'empreinte Sunmi) :
// PrestigePOS n'a AUCUN pointage (borne tournée vers les clients) ; rien de ce changement ne l'atteint :
//  - PosActivity reste une FlutterActivity (pas de FlutterFragmentActivity, pas de local_auth) ; le canal
//    « prestige/fingerprint » n'y sert qu'à la marque / au modèle et à l'empreinte de l'appareil (demande 56) ;
//  - lib/prestigepos et lib/main_pos.dart n'importent ni le terminal de pointage, ni la confirmation par empreinte, ni
//    la gestion des empreintes ; aucun bouton « Pointer » (Prestige Pointage tenue pour absente) ;
//  - le réglage « Confirmer le pointage par empreinte » n'est pas proposé dans l'administration de PrestigePOS.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _lire(String f) => File(f).readAsStringSync();

void main() {
  test('PosActivity : FlutterActivity inchangée, aucune bibliothèque d\'empreinte', () {
    final a = _lire('android/app/src/pos/kotlin/com/dici/prestigepos/PosActivity.kt');
    expect(a, contains('class PosActivity : FlutterActivity()'));
    expect(a, isNot(contains('FlutterFragmentActivity')));
    expect(a, isNot(contains('NfcBadgeBridge')));
    expect(_lire('pubspec.yaml'), isNot(contains('local_auth')));
  });

  test('aucun écran de pointage ni confirmation par empreinte dans PrestigePOS', () {
    final fichiers = [
      File('lib/main_pos.dart'),
      ...Directory('lib/prestigepos').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')),
    ];
    for (final f in fichiers) {
      final s = f.readAsStringSync();
      for (final interdit in [
        'rh/terminal_pointage_screen.dart',
        'rh/confirmation_empreinte.dart',
        'rh/empreintes_screen.dart',
        'confirmationEmpreinte',
        'Confirmer le pointage par empreinte',
      ]) {
        expect(s, isNot(contains(interdit)), reason: '${f.path} : $interdit');
      }
    }
    expect(_lire('lib/prestigepos/pos_app.dart'), contains('LanceurPointage.detecteur = () async => false;'));
  });
}
