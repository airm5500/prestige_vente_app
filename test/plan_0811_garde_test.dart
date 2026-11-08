// NON-RÉGRESSION — Prestige Mobile 4.11.0 (plan du pharmacien du 08/11) : garde-fous sur le code.
//  - UNE règle de saisie de la péremption et UN chemin de lecture lot / date (DataMatrix, photo) : « Mise à jour
//    péremption » et la réception des BL les partagent (lib/services/saisie_peremption.dart,
//    lib/screens/common/lecture_lot_date.dart), aucune copie de la règle ;
//  - clôture classique du BL inchangée (aucun paramètre) ; la clôture « au reçu » n'existe que par la capacité du
//    serveur (demande 59) ;
//  - icônes : écran CLIENT de la borne exclu ; PrestigePOS (lib/main_pos.dart) sans l'agrandissement ;
//  - réserve : droit « Voir les suggestions » absent = comportement d'avant.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _lire(String f) => File(f).readAsStringSync();

void main() {
  test('péremption : règle unique, partagée, jamais recopiée', () {
    final regle = _lire('lib/services/saisie_peremption.dart');
    expect(regle, contains('DateTime? lireDatePeremption('));
    final maj = _lire('lib/screens/expiration_update/expiration_update_screen.dart');
    expect(maj, contains('lireDatePeremption('));
    expect(maj, isNot(contains("digits.substring")), reason: 'ancienne copie de la règle supprimée');
    expect(_lire('lib/reception/reception_logic.dart'), contains('parseExpiryInput(String input) => lireDatePeremption(input)'));
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      if (f.path.endsWith('saisie_peremption.dart')) continue;
      expect(RegExp(r"switch \(t\.length\)[\s\S]{0,40}4 =>").hasMatch(f.readAsStringSync()), isFalse, reason: '${f.path} : copie de la règle');
    }
  });

  test('lot / date : un seul chemin (caméra et photo) pour les deux écrans', () {
    final maj = _lire('lib/screens/expiration_update/expiration_update_screen.dart');
    final rec = _lire('lib/screens/reception_bl/reception_bl_screen.dart');
    expect(maj, contains('photoLotDate('));
    expect(rec, contains('photoLotDate('));
    expect(rec, contains('scannerLotDate('));
    expect(maj, isNot(contains('class _LabelConfirmDialog')), reason: 'confirmation partagée (ConfirmationLotDate)');
    expect(rec, isNot(contains('GuidedCaptureScreen.open(')), reason: 'plus l\'ancienne photo sans les codes ni la confirmation');
  });

  test('réception : clôture classique inchangée, « au reçu » seulement par la capacité du serveur', () {
    final g = _lire('lib/reception/reception_gateway.dart');
    expect(g, contains("dio.put('/commande/validerbl/\$blId');"));
    expect(g, contains("queryParameters: {'mode': 'RECU'}"));
    expect(g, contains("['clotureRecu'] == true"));
    final s = _lire('lib/screens/reception_bl/reception_summary_screen.dart');
    expect(s, contains('_clotureRecu == true'));
  });

  test('icônes : borne (écran client) et PrestigePOS exclus', () {
    expect(_lire('lib/borne/borne_screen.dart'), contains('SansEchelleIcones('));
    // Branche PrestigePOS seulement (lib/main_pos.dart absent de Prestige Mobile).
    if (File('lib/main_pos.dart').existsSync()) expect(_lire('lib/main_pos.dart'), isNot(contains('ResponsiveTheme')));
    expect(_lire('lib/widgets/responsive.dart'), contains('EchelleIcones.of(context)'));
  });

  test('réserve : voirSuggestions absent = vrai (serveur actuel)', () {
    expect(_lire('lib/droits/droits_modules.dart'), contains('_reserveSuggestions != false'));
  });
}
