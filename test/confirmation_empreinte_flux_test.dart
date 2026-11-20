// 5.3.0 — ÉCRANS : flux « Confirmer le pointage par empreinte » sur le terminal de pointage (Prestige Mobile ; le même
// écran sert Prestige Pointage), service Sunmi ABSENT, BiometricPrompt SIMULÉ par le canal `prestige/fingerprint` :
//  - reconnue → écran de confirmation habituel puis pointage enregistré (corps envoyé à Prestige INCHANGÉ) ;
//  - annulée / délai / trop d'essais → « pointage non enregistré », rien envoyé, nouvel essai possible tout de suite ;
//  - aucune empreinte enregistrée / pas de lecteur / lecteur en panne → pointage enregistré avec la mention ;
//  - hors ligne : pointage confirmé mis en file, mention gardée ;
//  - pendant la demande, les autres lectures (badge, NFC) sont ignorées ;
//  - journal du terminal : issue de la confirmation, sans nom, badge ni code.
// Données FICTIVES seulement.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestige_vente_app/rh/photo_controle.dart';
import 'package:prestige_vente_app/services/nfc_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'outils/empreinte_terminal_fictif.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  setUp(() => SharedPreferences.setMockInitialValues({ReglagesPointageTerminal.prefConfirmationEmpreinte: true}));

  Future<TerminalEmpreinte> ouvrir(WidgetTester t, {String? reponse, Map<String, Object?>? materiel}) async {
    taille(t, const Size(360, 800));
    final e = TerminalEmpreinte();
    e.canal.reponseAuthentification = reponse;
    if (materiel != null) e.canal.materiel = materiel;
    await e.preparer(t);
    await afficher(t, e.ecran());
    return e;
  }

  testWidgets('empreinte reconnue → confirmation habituelle → pointage enregistré, corps envoyé inchangé', (t) async {
    final e = await ouvrir(t);
    await lireBadge(t, badgeFictif1);
    expect(e.canal.appelsDe('authenticate'), hasLength(1));
    expect((e.canal.appelsDe('authenticate').single.arguments as Map)['subtitle'], 'Alpha, posez un doigt enregistré sur ce terminal');
    expect(find.byKey(const Key('rh_confirmation')), findsOneWidget);
    expect(find.text('Bonjour Alpha'), findsOneWidget);
    await t.pump(const Duration(seconds: 3));
    await t.pump();
    final p = e.rh.posts.single;
    expect(p['employeId'], 'EX1');
    expect(p['motif'], 'Badge terminal Entrée');
    expect(p.keys.toSet(), {'id', 'employeId', 'jour', 'heure', 'sens', 'motif'}, reason: 'mêmes champs qu\'avant (sans photo)');
    expect(p.toString(), isNot(contains('empreinte')), reason: 'rien de nouveau envoyé à Prestige');
    expect(find.text('Bonjour Alpha — ENTRÉE 08:02 ✓'), findsWidgets);
    expect(find.byKey(const Key('rh_resultat_confirmation')), findsNothing);
    expect(t.takeException(), isNull);
    await finir(t);
  });

  for (final (code, titre) in [('CANCELED', 'annulée'), ('TIMEOUT', 'délai dépassé'), ('LOCKOUT', 'trop d\'essais'), ('AUTH_ERROR', 'erreur de lecture')]) {
    testWidgets('$titre → pointage NON enregistré, message clair, nouvel essai possible tout de suite', (t) async {
      final e = await ouvrir(t, reponse: code);
      await lireBadge(t, badgeFictif1);
      expect(find.byKey(const Key('rh_confirmation')), findsNothing);
      expect(find.text('Alpha : pointage non enregistré'), findsOneWidget);
      expect(find.textContaining('Présentez de nouveau votre badge ou votre code pour réessayer.'), findsOneWidget);
      await t.pump(const Duration(seconds: 5));
      expect(e.rh.posts, isEmpty);
      expect(find.text('Déjà pointé'), findsNothing);
      // Nouvel essai, empreinte reconnue cette fois : pas de « déjà pointé ».
      e.canal.reponseAuthentification = null;
      await lireBadge(t, badgeFictif1);
      expect(find.text('Déjà pointé'), findsNothing);
      expect(find.byKey(const Key('rh_confirmation')), findsOneWidget);
      await t.tap(find.byKey(const Key('rh_valider')));
      await t.pump();
      await t.pump();
      expect(e.rh.posts.single['employeId'], 'EX1');
      expect(e.canal.appelsDe('authenticate'), hasLength(2));
      await finir(t);
    });
  }

  for (final (nom, materiel, reponse, mention) in [
    ('aucune empreinte enregistrée', materielSunmiV3(biometricStatus: 11), null, 'aucune empreinte enregistrée sur ce terminal'),
    ('pas de lecteur', materielSunmiV3(lecteur: false), null, 'pas de lecteur d\'empreinte'),
    ('lecteur en panne', materielSunmiV3(), 'HW_ERROR', 'lecteur d\'empreinte indisponible'),
  ]) {
    testWidgets('$nom → pointage enregistré quand même, avec la mention', (t) async {
      final e = await ouvrir(t, materiel: materiel, reponse: reponse);
      await lireBadge(t, badgeFictif1);
      expect(find.byKey(const Key('rh_confirmation')), findsOneWidget);
      await t.tap(find.byKey(const Key('rh_valider')));
      await t.pump();
      await t.pump();
      expect(e.rh.posts.single['employeId'], 'EX1');
      expect(find.byKey(const Key('rh_resultat_confirmation')), findsOneWidget);
      expect(find.textContaining(mention), findsOneWidget);
      await finir(t);
    });
  }

  testWidgets('hors ligne : pointage confirmé gardé en file, mention conservée', (t) async {
    final e = await ouvrir(t, materiel: materielSunmiV3(biometricStatus: 11));
    e.rh.offline = true;
    await lireBadge(t, badgeFictif1);
    await t.tap(find.byKey(const Key('rh_valider')));
    await t.pump();
    await t.pump();
    expect(e.pr.enAttente, 1);
    expect(find.byKey(const Key('rh_resultat_confirmation')), findsOneWidget);
    await finir(t);
  });

  testWidgets('« Corriger » et « Annuler » de l\'écran de confirmation inchangés après l\'empreinte', (t) async {
    final e = await ouvrir(t);
    await lireBadge(t, badgeFictif1);
    await t.tap(find.byKey(const Key('rh_corriger')));
    await t.pump();
    expect(find.text('SORTIE 08:02'), findsOneWidget);
    await t.tap(find.byKey(const Key('rh_annuler')));
    await t.pump();
    expect(e.rh.posts, isEmpty);
    await lireBadge(t, badgeFictif1);
    expect(find.byKey(const Key('rh_confirmation')), findsOneWidget, reason: 'relu tout de suite après Annuler');
    await finir(t);
  });

  testWidgets('pendant la demande d\'empreinte : panneau affiché, autres lectures (badge, NFC) ignorées', (t) async {
    taille(t, const Size(360, 800));
    final e = TerminalEmpreinte();
    e.nfc.etat = NfcAvailability.ready;
    await e.preparer(t);
    // Demande d'empreinte qui ne répond pas encore.
    var reponduAuthentification = false;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(CanalEmpreinteSimule.canal, (c) async {
      e.canal.appels.add(c);
      if (c.method == 'hardwareInfo') return e.canal.materiel;
      if (c.method == 'isServiceInstalled') return false;
      if (c.method == 'authenticate') {
        await Future<void>.delayed(const Duration(seconds: 2));
        reponduAuthentification = true;
        return true;
      }
      return null;
    });
    await afficher(t, e.ecran());
    await lireBadge(t, badgeFictif1);
    expect(find.byKey(const Key('rh_confirmation_empreinte')), findsOneWidget);
    expect(find.text('Bonjour Alpha'), findsOneWidget);
    e.nfc.approcher('0f:a1:b2:c3');
    await t.pump();
    await lireBadge(t, badgeFictif2);
    expect(find.text('Bonjour Beta'), findsNothing);
    await t.pump(const Duration(seconds: 2));
    await t.pump();
    expect(reponduAuthentification, isTrue);
    expect(find.byKey(const Key('rh_confirmation')), findsOneWidget);
    expect(find.text('Bonjour Alpha'), findsOneWidget);
    expect(e.canal.appelsDe('authenticate'), hasLength(1));
    await finir(t);
  });

  testWidgets('journal du terminal : issue notée sans nom, badge, matricule ni code', (t) async {
    final e = await ouvrir(t, reponse: 'CANCELED');
    await lireBadge(t, badgeFictif1);
    await t.pump(const Duration(seconds: 5));
    e.canal.reponseAuthentification = null;
    await lireBadge(t, matriculeFictif1);
    await t.pump(const Duration(seconds: 3));
    await t.pump();
    final j = await e.toutLeJournal();
    expect(j, contains('Confirmation par empreinte : annulée, pointage non enregistré'));
    expect(j, contains('Confirmation par empreinte : reconnue'));
    for (final interdit in ['Alpha', 'TESTEUR', badgeFictif1, matriculeFictif1]) {
      expect(j.split('\n').where((l) => l.contains('Confirmation par empreinte')).join('\n'), isNot(contains(interdit)));
    }
    await finir(t);
  });
}
