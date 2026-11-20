// 5.3.0 — E2E (application entière Prestige Mobile V3, faux serveur Prestige en mémoire, canal d'empreinte SIMULÉ comme
// sur le SUNMI V3 du pharmacien : lecteur Android, AUCUN service d'identification Sunmi) :
//  1. Réglages › Équipe & pointage (code administrateur) : « Confirmer le pointage par empreinte » désactivé par
//     défaut, activé par l'administrateur ;
//  2. Pointage présence › Terminal : bandeau « badge ou code personnel » (pas de diagnostic technique) ;
//  3. badge lu, empreinte ANNULÉE → rien envoyé au serveur, message clair ; nouvel essai, empreinte reconnue → pointage
//     reçu par le serveur ; code personnel (matricule) au clavier → empreinte → pointage reçu ;
//  4. aucune donnée personnelle ni code dans le journal du terminal ni dans les traces (debugPrint).
// Données FICTIVES seulement.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/parametres/parametres_logic.dart';
import 'package:prestige_vente_app/parametres/parametres_widgets.dart';
import 'package:prestige_vente_app/rh/confirmation_empreinte.dart';
import 'package:prestige_vente_app/rh/photo_controle.dart';
import 'package:prestige_vente_app/rh/terminal_pointage_screen.dart';
import 'package:prestige_vente_app/services/pin_securise.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import 'outils/app_e2e.dart';
import 'outils/empreinte_terminal_fictif.dart';

class _Code extends CodeAdmin {
  @override
  Future<Duration?> attenteRestante() async => null;
  @override
  Future<VerificationPin> verifier(String saisie) async => saisie == '4827' ? VerificationPin.accepte : VerificationPin.refuse;
}

void main() {
  setUp(() {
    final avant = CodeAdmin.instance;
    CodeAdmin.instance = _Code();
    addTearDown(() => CodeAdmin.instance = avant);
  });

  testWidgets('SUNMI V3 sans service Sunmi : réglage activé par l\'administrateur, bandeau, badge / code + empreinte', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final canal = CanalEmpreinteSimule(service: false)..installer(t);
    final traces = <String>[];
    final printAvant = debugPrint;
    debugPrint = (m, {wrapWidth}) => traces.add(m ?? '');

    final app = AppE2E()..serveur.activerTerminalRh();
    app.serveur.droitsRh[DonneesFictives.admin] = (pointer: true, gerer: false);
    await app.preparer(prefs: const {'hiddenMenuIds': <String>[], 'rh_photo_badge_v1': false});
    await app.lancer(t);
    expect(await app.seConnecter(t, login: DonneesFictives.admin, motDePasse: DonneesFictives.motDePasseAdmin), isTrue);

    // 1. Réglage (rubrique protégée par le code administrateur).
    await t.tap(find.text('Réglages').last);
    await app.attendre(t, const Duration(seconds: 1));
    await app.defilerJusqua(t, find.byKey(Key('rubrique_${Rubrique.equipe.name}')));
    await t.tap(find.byKey(Key('rubrique_${Rubrique.equipe.name}')));
    await app.attendre(t, const Duration(seconds: 1));
    expect(find.byKey(const Key('pin_admin_saisie')), findsOneWidget, reason: 'code administrateur exigé');
    await t.enterText(find.byKey(const Key('pin_admin_saisie')), '4827');
    await t.tap(find.text('Valider'));
    await app.attendre(t, const Duration(seconds: 1));
    final reglage = find.byKey(const Key('rh_reglage_confirmation_empreinte'));
    await app.defilerJusqua(t, reglage);
    expect(t.widget<SwitchCard>(reglage).value, isFalse, reason: 'désactivé par défaut');
    await t.tap(find.descendant(of: reglage, matching: find.byType(Switch)));
    await app.attendre(t, const Duration(milliseconds: 500));
    expect(t.widget<SwitchCard>(reglage).value, isTrue);
    expect((await ReglagesPointageTerminal.charger()).confirmationEmpreinte, isTrue);
    await app.retour(t);
    await app.retour(t);

    // 2. Terminal de pointage.
    await app.ouvrirMenu(t, ListPresentation.dashboard, 'pointage_rh');
    expect(await app.attendreQue(t, find.byKey(const Key('rh_voie_b'))), isTrue);
    await t.tap(find.byKey(const Key('rh_voie_b')));
    expect(await app.attendreQue(t, find.byType(TerminalPointageScreen)), isTrue);
    await app.attendre(t);
    expect(find.text(texteSansEmpreinte), findsOneWidget);
    expect(find.byKey(const Key('rh_empreinte')), findsNothing);
    expect(find.textContaining('com.sunmi'), findsNothing);
    expect(find.byKey(const Key('rh_confirmation_info')), findsOneWidget);

    // 3a. Badge, empreinte annulée : rien d'envoyé.
    final champ = find.byKey(const Key('rh_badge_champ'));
    canal.reponseAuthentification = 'CANCELED';
    await t.enterText(champ, 'B001');
    await t.testTextInput.receiveAction(TextInputAction.done);
    expect(await app.attendreQue(t, find.text('Awa : pointage non enregistré')), isTrue);
    await app.attendre(t, const Duration(seconds: 3));
    expect(app.serveur.pointagesTerminal, isEmpty);

    // 3b. Nouvel essai, empreinte reconnue.
    canal.reponseAuthentification = null;
    await t.enterText(champ, 'B001');
    await t.testTextInput.receiveAction(TextInputAction.done);
    expect(await app.attendreQue(t, find.byKey(const Key('rh_confirmation'))), isTrue);
    await t.tap(find.byKey(const Key('rh_valider')));
    await app.attendre(t);
    expect(app.serveur.pointagesTerminal.single['employeId'], 'E1');

    // 3c. Code personnel (matricule) au clavier.
    await app.attendre(t, const Duration(seconds: 4));
    await t.tap(find.byKey(const Key('rh_sans_empreinte_code')));
    await app.attendre(t, const Duration(milliseconds: 300));
    expect(t.widget<TextField>(champ).keyboardType, TextInputType.text);
    await t.enterText(champ, '02');
    await t.testTextInput.receiveAction(TextInputAction.done);
    expect(await app.attendreQue(t, find.text('Bonjour Ali')), isTrue);
    await t.tap(find.byKey(const Key('rh_valider')));
    await app.attendre(t);
    expect(app.serveur.pointagesTerminal.map((p) => p['employeId']), ['E1', 'E2']);
    expect(canal.appelsDe('authenticate'), hasLength(3));

    // 4. Aucune donnée personnelle ni code dans le journal / les traces de la confirmation.
    final journal = [for (final x in await JournalTerminal.instance.lire()) x.action].where((a) => a.contains('empreinte')).join('\n');
    expect(journal, contains('Confirmation par empreinte : annulée'));
    for (final interdit in ['Awa', 'Ali', 'KOUASSI', 'TRAORE', 'B001', 'B002']) {
      expect(journal, isNot(contains(interdit)));
      expect(traces.where((l) => l.contains('mpreinte')).join('\n'), isNot(contains(interdit)));
    }
    debugPrint = printAvant;
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });
}
