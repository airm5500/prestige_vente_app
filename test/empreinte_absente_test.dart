// 5.3.0 — ÉCRANS : terminal de pointage (Prestige Mobile, aussi celui de Prestige Pointage) selon le service
// d'empreinte Sunmi détecté à l'ouverture par le canal natif SIMULÉ `prestige/fingerprint` :
//  - ABSENT (SUNMI V3, Android 13) : bandeau clair (texte exact), « Scanner mon badge » (QR / code-barres par la
//    caméra), « Saisir mon code personnel » (clavier), lien discret « Détails techniques » (diagnostic) masqué en mode
//    borne ; pas de bouton empreinte ; la gestion des empreintes affiche le même bandeau, sans enrôlement ni recopie des
//    modèles partagés ; tablette sans lecteur : aucun bandeau ;
//  - PRÉSENT (ancien terminal, piste 4) : identification 1:N par le doigt et enrôlement INCHANGÉS, aucun bandeau ;
//  - réglage « Confirmer le pointage par empreinte » : désactivé par défaut dans Réglages › Équipe & pointage (rubrique
//    protégée par le code administrateur, comme la photo de contrôle), enregistré ; rappel sous la zone du badge.
// Données FICTIVES seulement.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestige_vente_app/parametres/parametres_logic.dart';
import 'package:prestige_vente_app/parametres/parametres_widgets.dart';
import 'package:prestige_vente_app/parametres/rubriques_pages.dart';
import 'package:prestige_vente_app/pointage/pointage_repository.dart';
import 'package:prestige_vente_app/rh/confirmation_empreinte.dart';
import 'package:prestige_vente_app/rh/empreintes_screen.dart';
import 'package:prestige_vente_app/rh/identification.dart';
import 'package:prestige_vente_app/rh/photo_controle.dart';
import 'package:prestige_vente_app/screens/pointage/fingerprint_diagnostic_screen.dart';
import 'package:prestige_vente_app/services/nfc_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'outils/empreinte_terminal_fictif.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('service d\'empreinte Sunmi ABSENT (SUNMI V3)', () {
    testWidgets('bandeau clair au lieu du diagnostic ; pas de bouton empreinte', (t) async {
      taille(t, const Size(360, 800));
      final e = TerminalEmpreinte();
      await e.preparer(t);
      await afficher(t, e.ecran());
      expect(find.byKey(const Key('rh_sans_empreinte')), findsOneWidget);
      expect(find.text(texteSansEmpreinte), findsOneWidget);
      expect(find.byKey(const Key('rh_empreinte')), findsNothing);
      expect(find.textContaining('com.sunmi.fingerprintservice'), findsNothing, reason: 'aucun diagnostic technique à l\'écran');
      expect(find.textContaining('non installé'), findsNothing);
      expect(find.byKey(const Key('rh_sans_empreinte_details')), findsOneWidget);
      expect(find.byKey(const Key('rh_gerer_empreintes')), findsNothing, reason: 'enrôlement impossible sur ce terminal');
      expect(e.canal.appelsDe('isServiceInstalled'), isNotEmpty, reason: 'détection automatique à l\'ouverture');
      expect(e.canal.appelsDe('authenticate'), isEmpty);
      expect(t.takeException(), isNull);
      await finir(t);
    });

    testWidgets('« Scanner mon badge » : QR / code-barres par la caméra → pointage', (t) async {
      taille(t, const Size(360, 800));
      final e = TerminalEmpreinte();
      await e.preparer(t);
      var cameras = 0;
      await afficher(t, e.ecran(camera: (_) async {
        cameras++;
        return badgeFictif1;
      }));
      await t.tap(find.byKey(const Key('rh_sans_empreinte_badge')));
      await t.pump();
      await t.pump();
      expect(cameras, 1);
      expect(find.text('Bonjour Alpha'), findsOneWidget);
      await t.pump(const Duration(seconds: 3));
      await t.pump();
      expect(e.rh.posts.single['employeId'], 'EX1');
      expect(e.rh.posts.single['motif'], 'Badge terminal Entrée');
      await finir(t);
    });

    testWidgets('« Saisir mon code personnel » : clavier affiché, matricule ou n° de badge → pointage', (t) async {
      taille(t, const Size(360, 800));
      final e = TerminalEmpreinte();
      await e.preparer(t);
      await afficher(t, e.ecran());
      expect(t.widget<TextField>(find.byKey(const Key('rh_badge_champ'))).keyboardType, TextInputType.none);
      await t.tap(find.byKey(const Key('rh_sans_empreinte_code')));
      await t.pump();
      await t.pump();
      final champ = t.widget<TextField>(find.byKey(const Key('rh_badge_champ')));
      expect(champ.keyboardType, TextInputType.text);
      expect(champ.focusNode!.hasFocus, isTrue);
      await lireBadge(t, matriculeFictif1);
      expect(find.text('Bonjour Alpha'), findsOneWidget);
      await t.tap(find.byKey(const Key('rh_valider')));
      await t.pump();
      await t.pump();
      expect(e.rh.posts.single['employeId'], 'EX1');
      await finir(t);
    });

    testWidgets('badge NFC toujours accepté', (t) async {
      taille(t, const Size(360, 800));
      final e = TerminalEmpreinte();
      e.nfc.etat = NfcAvailability.ready;
      await e.preparer(t);
      await afficher(t, e.ecran());
      e.nfc.approcher('0f:a1:b2:c3');
      await t.pump();
      await t.pump();
      expect(find.text('Bonjour Beta'), findsOneWidget);
      await finir(t);
    });

    testWidgets('« Détails techniques » ouvre le diagnostic du lecteur ; masqué en mode borne', (t) async {
      taille(t, const Size(360, 800));
      final e = TerminalEmpreinte();
      await e.preparer(t);
      await afficher(t, e.ecran());
      await t.tap(find.byKey(const Key('rh_sans_empreinte_details')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(FingerprintDiagnosticScreen), findsOneWidget);
      t.state<NavigatorState>(find.byType(Navigator).first).pop();
      await t.pump(const Duration(milliseconds: 400));
      await afficher(t, e.ecran(borne: true));
      expect(find.byKey(const Key('rh_sans_empreinte')), findsOneWidget);
      expect(find.byKey(const Key('rh_sans_empreinte_details')), findsNothing);
      expect(find.byKey(const Key('rh_sans_empreinte_badge')), findsOneWidget);
      await finir(t);
    });

    testWidgets('tablette sans lecteur : aucun bandeau (rien à expliquer)', (t) async {
      taille(t, const Size(1280, 800));
      final e = TerminalEmpreinte();
      e.canal.materiel = materielTablette();
      await e.preparer(t);
      await afficher(t, e.ecran());
      expect(find.byKey(const Key('rh_sans_empreinte')), findsNothing);
      expect(find.byKey(const Key('rh_badge_champ')), findsOneWidget);
      await finir(t);
    });

    testWidgets('gestion des empreintes : bandeau, aucun enrôlement, aucune recopie ; suppression possible', (t) async {
      taille(t, const Size(360, 800));
      final e = TerminalEmpreinte();
      await e.preparer(t);
      await e.identification.enregistrer(EmpreintesEmploye(employeId: 'EX1', modeles: [Uint8List.fromList([1, 2])], consentementLe: e.now));
      await t.pumpWidget(MaterialApp(home: EmpreintesScreen(rh: e.pr, identification: e.identification, codeAdmin: (_) async => true)));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('rh_sans_empreinte')), findsOneWidget);
      expect(find.text(texteSansEmpreinteGestion), findsOneWidget);
      expect(find.byKey(const Key('rh_enroler_EX1')), findsNothing);
      expect(find.byKey(const Key('rh_enroler_EX2')), findsNothing);
      expect(find.byKey(const Key('rh_supprimer_EX1')), findsOneWidget);
      expect(e.canal.appelsDe('enroll'), isEmpty);
      expect(e.canal.appelsDe('connect'), isEmpty);
      expect(e.rh.gets.where((g) => g.contains('empreintes')), isEmpty, reason: 'modèles partagés jamais recopiés ici');
      await t.ensureVisible(find.byKey(const Key('rh_supprimer_EX1')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('rh_supprimer_EX1')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('rh_supprimer_ok')));
      await t.pumpAndSettle();
      expect(e.coffre.donnees, isEmpty);
      expect(t.takeException(), isNull);
    });
  });

  group('service d\'empreinte Sunmi PRÉSENT (piste 4 : inchangé)', () {
    testWidgets('identification 1:N par le doigt, gestion proposée, aucun bandeau', (t) async {
      taille(t, const Size(360, 800));
      final e = TerminalEmpreinte();
      e.canal
        ..service = true
        ..materiel = materielAncienSunmi()
        ..indexIdentifie = 0;
      await e.preparer(t);
      await e.identification.enregistrer(EmpreintesEmploye(employeId: 'EX1', modeles: [Uint8List.fromList([7])], consentementLe: e.now));
      await afficher(t, e.ecran(gestion: true));
      expect(find.byKey(const Key('rh_sans_empreinte')), findsNothing);
      expect(find.byKey(const Key('rh_empreinte')), findsOneWidget);
      expect(find.byKey(const Key('rh_gerer_empreintes')), findsOneWidget);
      await t.tap(find.byKey(const Key('rh_empreinte')));
      await t.pump();
      await t.pump();
      await t.pump();
      expect(find.text('Bonjour Alpha'), findsOneWidget);
      expect(e.canal.appelsDe('identify'), hasLength(1));
      await t.pump(const Duration(seconds: 3));
      await t.pump();
      expect(e.rh.posts.single['motif'], 'Empreinte terminal Entrée');
      expect(e.canal.appelsDe('authenticate'), isEmpty);
      await finir(t);
    });

    testWidgets('enrôlement inchangé : consentement, 3 captures, test, enregistrement', (t) async {
      taille(t, const Size(360, 800));
      final e = TerminalEmpreinte();
      e.canal
        ..service = true
        ..materiel = materielAncienSunmi();
      await e.preparer(t);
      await t.pumpWidget(MaterialApp(home: EmpreintesScreen(rh: e.pr, identification: e.identification, codeAdmin: (_) async => true)));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('rh_sans_empreinte')), findsNothing);
      await t.tap(find.byKey(const Key('rh_enroler_EX1')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('rh_consentement_coche')));
      await t.pump();
      await t.tap(find.byKey(const Key('rh_consentement_coche')));
      await t.pump();
      await t.tap(find.byKey(const Key('rh_consentement_ok')));
      await t.pumpAndSettle();
      expect(e.canal.appelsDe('enroll'), hasLength(3));
      expect(e.coffre.donnees['EX1']!.modeles, hasLength(3));
      expect(find.textContaining('enregistrées et reconnues'), findsOneWidget);
    });

    testWidgets('réglage de confirmation ACTIVÉ : sans effet sur ce terminal (aucun rappel, aucune demande)', (t) async {
      SharedPreferences.setMockInitialValues({ReglagesPointageTerminal.prefConfirmationEmpreinte: true});
      taille(t, const Size(360, 800));
      final e = TerminalEmpreinte();
      e.canal
        ..service = true
        ..materiel = materielAncienSunmi();
      await e.preparer(t);
      await afficher(t, e.ecran());
      expect(find.byKey(const Key('rh_confirmation_info')), findsNothing);
      await lireBadge(t, badgeFictif1);
      expect(find.text('Bonjour Alpha'), findsOneWidget);
      expect(e.canal.appelsDe('authenticate'), isEmpty);
      await finir(t);
    });
  });

  group('réglage « Confirmer le pointage par empreinte »', () {
    testWidgets('Réglages › Équipe & pointage : désactivé par défaut, enregistré ; rubrique protégée (administrateur)', (t) async {
      taille(t, const Size(360, 800), densite: 2);
      expect(Rubrique.equipe.locked, isTrue, reason: 'même règle que la photo de contrôle : code administrateur');
      final photo = PhotoControle(registre: RegistrePhotosPointage(stockage: StockagePhotosMemoire()));
      await t.pumpWidget(MaterialApp(home: EquipePage(repository: MemoryPointageRepository(), photo: photo)));
      await t.pumpAndSettle();
      final k = find.byKey(const Key('rh_reglage_confirmation_empreinte'));
      await t.scrollUntilVisible(k, 200, scrollable: find.byType(Scrollable).first);
      await t.pumpAndSettle();
      final carte = t.widget<SwitchCard>(k);
      expect(carte.value, isFalse);
      expect(carte.title, titreReglageConfirmationEmpreinte);
      expect(carte.subtitle, contains('n\'identifie pas la personne'));
      await t.tap(find.descendant(of: k, matching: find.byType(Switch)));
      await t.pumpAndSettle();
      expect((await ReglagesPointageTerminal.charger()).confirmationEmpreinte, isTrue);
      expect(t.widget<SwitchCard>(k).value, isTrue);
      expect(t.takeException(), isNull);
    });

    testWidgets('activé sur un terminal sans service Sunmi : rappel sous la zone du badge', (t) async {
      SharedPreferences.setMockInitialValues({ReglagesPointageTerminal.prefConfirmationEmpreinte: true});
      taille(t, const Size(360, 800));
      final e = TerminalEmpreinte();
      await e.preparer(t);
      await afficher(t, e.ecran());
      expect(find.byKey(const Key('rh_confirmation_info')), findsOneWidget);
      expect(find.text(texteConfirmationActive), findsOneWidget);
      await finir(t);
    });

    testWidgets('désactivé (par défaut) : aucun rappel, aucune demande d\'empreinte', (t) async {
      taille(t, const Size(360, 800));
      final e = TerminalEmpreinte();
      await e.preparer(t);
      await afficher(t, e.ecran());
      expect(find.byKey(const Key('rh_confirmation_info')), findsNothing);
      await lireBadge(t, badgeFictif1);
      expect(find.text('Bonjour Alpha'), findsOneWidget);
      expect(e.canal.appelsDe('authenticate'), isEmpty);
      await finir(t);
    });
  });
}
