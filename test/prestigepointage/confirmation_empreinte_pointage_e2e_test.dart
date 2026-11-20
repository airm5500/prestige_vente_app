// Prestige Pointage 1.1.0 (Prestige Mobile 5.3.0) — E2E : application ENTIÈRE (PrestigePointageApp, borne enrôlée,
// faux serveur Prestige en mémoire) sur un SUNMI V3 simulé (canal `prestige/fingerprint` : lecteur Android, AUCUN
// service d'identification Sunmi) :
//  - borne : bandeau « badge ou code personnel », sans le lien « Détails techniques » (mode borne) ; badge → pointage ;
//  - administration (code administrateur) : « Confirmer le pointage par empreinte » DÉSACTIVÉ par défaut, activé ;
//    « Lecteur d'empreinte : détails techniques » ouvre le diagnostic ;
//  - réglage activé : badge → empreinte ANNULÉE → rien reçu par le serveur ; nouvel essai reconnu → pointage signé reçu ;
//    réglage désactivé de nouveau → plus de demande ;
//  - ancien terminal (service présent, piste 4) : identification par le doigt inchangée, aucun bandeau.
// Données FICTIVES seulement.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/rh/confirmation_empreinte.dart';
import 'package:prestige_vente_app/rh/photo_controle.dart';
import 'package:prestige_vente_app/screens/pointage/fingerprint_diagnostic_screen.dart';

import '../outils/empreinte_terminal_fictif.dart' show CanalEmpreinteSimule, materielAncienSunmi;
import 'outils/pointage_e2e.dart';

void main() {
  void telephone(WidgetTester t) {
    t.view.physicalSize = const Size(720, 1440);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
  }

  Finder administration() => find.descendant(of: find.byKey(const Key('pointage_administration')), matching: find.byType(Scrollable)).first;

  Future<void> ouvrirAdministration(WidgetTester t, PointageE2E e) async {
    await t.tap(find.byKey(const Key('pointage_admin')));
    expect(await e.attendreQue(t, find.byKey(const Key('pointage_administration'))), isTrue);
    await e.attendre(t, const Duration(milliseconds: 500));
  }

  Future<void> basculerConfirmation(WidgetTester t, PointageE2E e, bool attenduAvant) async {
    final k = find.byKey(const Key('pointage_admin_confirmation_empreinte'));
    await t.scrollUntilVisible(k, 150, scrollable: administration());
    await t.ensureVisible(k);
    await t.pump();
    expect(t.widget<SwitchListTile>(k).value, attenduAvant);
    await t.tap(k);
    await e.attendre(t, const Duration(milliseconds: 500));
    expect(t.widget<SwitchListTile>(k).value, !attenduAvant);
  }

  testWidgets('SUNMI V3 : bandeau, réglage en administration (désactivé par défaut), badge + empreinte', (t) async {
    telephone(t);
    final canal = CanalEmpreinteSimule(service: false)..installer(t);
    final e = PointageE2E();
    await e.preparer(configure: true);
    await e.enrolerDirectement();
    await e.lancer(t);
    expect(await e.attendreQue(t, find.byKey(const Key('rh_sans_empreinte'))), isTrue);
    expect(find.text(texteSansEmpreinte), findsOneWidget);
    expect(find.byKey(const Key('rh_sans_empreinte_details')), findsNothing, reason: 'mode borne : pas de diagnostic');
    expect(find.byKey(const Key('rh_empreinte')), findsNothing);

    // Réglage désactivé : badge → pointage sans demande d'empreinte.
    await e.badge(t, 'B001');
    expect(await e.attendreQue(t, find.textContaining('Bonjour Awa — ENTRÉE')), isTrue);
    expect(canal.appelsDe('authenticate'), isEmpty);
    expect(e.bornes.pointages, hasLength(1));
    await e.attendre(t, const Duration(seconds: 3));

    // Administration : réglage désactivé par défaut → activé ; diagnostic accessible.
    await ouvrirAdministration(t, e);
    await basculerConfirmation(t, e, false);
    expect((await ReglagesPointageTerminal.charger()).confirmationEmpreinte, isTrue);
    final diag = find.byKey(const Key('pointage_admin_diagnostic'));
    await t.scrollUntilVisible(diag, 150, scrollable: administration());
    await t.ensureVisible(diag);
    await t.pump();
    await t.tap(diag);
    expect(await e.attendreQue(t, find.byType(FingerprintDiagnosticScreen)), isTrue);
    t.state<NavigatorState>(find.byType(Navigator).first).pop();
    await e.attendre(t, const Duration(milliseconds: 500));
    t.state<NavigatorState>(find.byType(Navigator).first).pop();
    await e.attendre(t, const Duration(milliseconds: 500));
    expect(find.byKey(const Key('rh_badge_champ')), findsOneWidget);

    // Réglage activé : empreinte annulée → rien reçu ; nouvel essai reconnu → pointage reçu.
    canal.reponseAuthentification = 'CANCELED';
    await e.badge(t, 'B002');
    expect(await e.attendreQue(t, find.text('Ali : pointage non enregistré')), isTrue);
    expect(e.bornes.pointages, hasLength(1));
    await e.attendre(t, const Duration(seconds: 3));
    canal.reponseAuthentification = null;
    await e.badge(t, 'B002');
    expect(await e.attendreQue(t, find.textContaining('Bonjour Ali — ENTRÉE')), isTrue);
    await e.attendre(t, const Duration(seconds: 2));
    expect(e.bornes.pointages, hasLength(2));
    expect(e.bornes.pointages.values.last['employeId'], 'E2');
    expect(canal.appelsDe('authenticate'), hasLength(2));

    // Réglage désactivé de nouveau (administration) : plus de demande.
    await e.attendre(t, const Duration(seconds: 3));
    await ouvrirAdministration(t, e);
    await basculerConfirmation(t, e, true);
    t.state<NavigatorState>(find.byType(Navigator).first).pop();
    await e.attendre(t, const Duration(milliseconds: 500));
    await e.badge(t, '03');
    expect(await e.attendreQue(t, find.textContaining('Bonjour Mariam — ENTRÉE')), isTrue);
    expect(canal.appelsDe('authenticate'), hasLength(2));
    expect(e.journaux.where((l) => l.contains('mpreinte')).join('\n'), isNot(contains('Ali')));
    expect(t.takeException(), isNull);
    await e.fermer(t);
  });

  testWidgets('ancien terminal (service Sunmi présent) : aucun bandeau, empreinte proposée, réglage sans effet', (t) async {
    telephone(t);
    CanalEmpreinteSimule(service: true, materiel: materielAncienSunmi()).installer(t);
    final e = PointageE2E();
    await e.preparer(configure: true, prefs: {ReglagesPointageTerminal.prefConfirmationEmpreinte: true});
    await e.enrolerDirectement();
    e.empreinte.present = true;
    await e.lancer(t);
    expect(await e.attendreQue(t, find.byKey(const Key('rh_badge_champ'))), isTrue);
    await e.attendre(t);
    expect(find.byKey(const Key('rh_sans_empreinte')), findsNothing);
    expect(find.byKey(const Key('rh_confirmation_info')), findsNothing);
    await e.badge(t, 'B001');
    expect(await e.attendreQue(t, find.textContaining('Bonjour Awa — ENTRÉE')), isTrue);
    expect(t.takeException(), isNull);
    await e.fermer(t);
  });
}
