// Prestige Pointage — E2E : application ENTIÈRE (PrestigePointageApp, initialisation de lib/main_pointage.dart) contre
// le faux serveur Prestige en mémoire, bornes de la demande 57 comprises (règles du vrai serveur, commit 31622a33) :
//  - premier lancement : serveur → code administrateur → compte de l'administrateur → nom de l'appareil OBLIGATOIRE
//    (pré-rempli) → POST v1/rh/bornes → identité dans le coffre → session fermée aussitôt ; plus jamais de connexion ;
//  - pointage par QR (secret du badge nulle part), douchette 1D, NFC ; « Bonjour <prénom> — ENTRÉE hh:mm » ;
//    relecture < 2 min ignorée ;
//  - file hors ligne : serveur coupé → pointage gardé ; retour → envoi automatique (sans confirmation), renvoi
//    idempotent (même id → deja) ;
//  - borne retirée → bandeau « Appareil retiré » + pointage gardé ; réenrôlement → la file part ;
//  - hors du réseau de l'officine, serveur sans la demande 57, horloge décalée : bandeaux ;
//  - empreintes partagées recopiées puis pointage par empreinte ; DESACTIVE → enrôlement local par un compte RH
//    TEMPORAIRE (déconnecté ensuite).
// Données FICTIVES seulement.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/prestigepointage/client_borne.dart';
import 'package:prestige_vente_app/prestigepointage/pointage_app.dart';
import 'package:prestige_vente_app/rh/empreintes_partagees.dart';
import 'package:prestige_vente_app/rh/empreintes_screen.dart';

import 'outils/pointage_e2e.dart';

void main() {
  void telephone(WidgetTester t) {
    t.view.physicalSize = const Size(720, 1440);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
  }

  Future<String> toutLeJournal() async =>
      [for (final x in await JournalTerminal.instance.lire()) [x.action, x.motif, x.refLocale, x.refServeur, x.utilisateur, x.terminal].join('|')].join('\n');

  /// Tout ce qui est sorti de l'appareil (chemins, en-têtes, corps).
  String toutLeReseau(FauxServeurPrestige s) => [for (final r in s.recues) '${r.cible}|${r.entetes}|${r.corps}'].join('\n');

  group('premier lancement', () {
    testWidgets('serveur → code admin → compte admin → nom OBLIGATOIRE (pré-rempli) → borne enrôlée, session fermée', (t) async {
      telephone(t);
      final e = PointageE2E();
      await e.preparer(sansNom: true);
      await e.lancer(t);
      expect(find.byKey(const Key('pointage_assistant')), findsOneWidget);
      await t.enterText(find.byKey(const Key('pointage_serveur_adresse')), FauxServeurPrestige.hoteMemoire);
      await t.enterText(find.byKey(const Key('pointage_serveur_port')), FauxServeurPrestige.portMemoire);
      await t.tap(find.byKey(const Key('pointage_serveur_suivant')));
      expect(await e.attendreQue(t, find.byKey(const Key('pointage_admin_login'))), isTrue);
      expect(e.codesAdmin, 1, reason: 'code administrateur de l\'appareil avant le compte');
      await t.enterText(find.byKey(const Key('pointage_admin_login')), DonneesFictives.admin);
      await t.enterText(find.byKey(const Key('pointage_admin_mdp')), DonneesFictives.motDePasseAdmin);
      await t.tap(find.byKey(const Key('pointage_enroler')));
      expect(await e.attendreQue(t, find.byKey(const Key('nom_appareil_etape'))), isTrue, reason: 'nom de l\'appareil obligatoire');
      expect(t.widget<TextField>(find.byKey(const Key('nom_appareil_champ'))).controller!.text, 'SUNMI V2s', reason: 'pré-rempli');
      expect(e.bornes.bornes, isEmpty, reason: 'rien d\'enrôlé avant le nom');
      await t.enterText(find.byKey(const Key('nom_appareil_champ')), 'Borne entrée');
      await t.tap(find.byKey(const Key('nom_appareil_enregistrer')));
      expect(await e.attendreQue(t, find.byKey(const Key('rh_badge_champ'))), isTrue, reason: 'borne prête');
      final b = e.bornes.bornes.values.single;
      expect(b.nom, 'Borne entrée');
      expect(b.empreinte, empreinteE2E);
      expect(e.serveur.recuesSur('/rh/bornes').single.json, {'empreinte': empreinteE2E, 'nom': 'Borne entrée'});
      expect(e.serveur.recuesSur('/user/logout'), hasLength(1), reason: 'déconnexion immédiate');
      expect(e.serveur.sessions, isEmpty);
      expect(await DioClient.cookieJar.loadForRequest(Uri.parse(e.serveur.base)), isEmpty);
      final i = (await e.coffre.lire())!;
      expect(i.borneId, b.id);
      expect(i.secret, b.secret);
      expect(find.text('Prestige Pointage'), findsWidgets);
      expect(e.modesSysteme.toString(), contains('immersiveSticky'), reason: 'mode borne dès l\'ouverture');

      // Plus aucune connexion : pointage signé.
      final logins = e.serveur.recuesSur('/user/login').length;
      await e.badge(t, 'B001');
      expect(await e.attendreQue(t, find.textContaining('Bonjour Awa — ENTRÉE')), isTrue);
      expect(e.bornes.pointages.values.single['employeId'], 'E1');
      expect(e.bornes.pointages.values.single['borne'], b.id);
      expect(e.serveur.recuesSur('/user/login'), hasLength(logins), reason: 'plus jamais de connexion');
      // Le secret de la borne n'est jamais sorti (seule la signature circule), ni journalisé.
      final s64 = base64Url.encode(b.secret).replaceAll('=', '');
      final hors = [for (final r in e.serveur.recues) if (!r.chemin.endsWith('/rh/bornes')) '${r.cible}|${r.entetes}|${r.corps}'].join('\n');
      expect(hors, isNot(contains(s64)));
      expect(await toutLeJournal(), isNot(contains(s64)));
      expect(e.journaux.join('\n'), isNot(contains(s64)));
      expect(e.journaux.join('\n'), isNot(contains(empreinteE2E)), reason: 'empreinte jamais journalisée');
      expect(await toutLeJournal(), isNot(contains(empreinteE2E)));
      expect(t.takeException(), isNull);
      await e.fermer(t);
    });

    testWidgets('compte sans le droit : message clair, aucune borne, aucune session', (t) async {
      telephone(t);
      final e = PointageE2E();
      await e.preparer(configure: true);
      await e.lancer(t);
      await e.attendre(t, const Duration(milliseconds: 500));
      expect(t.widget<TextField>(find.byKey(const Key('pointage_serveur_adresse'))).controller!.text, FauxServeurPrestige.hoteMemoire,
          reason: 'adresse enregistrée reprise');
      await t.tap(find.byKey(const Key('pointage_serveur_suivant')));
      expect(await e.attendreQue(t, find.byKey(const Key('pointage_admin_login'))), isTrue);
      await t.enterText(find.byKey(const Key('pointage_admin_login')), DonneesFictives.login);
      await t.enterText(find.byKey(const Key('pointage_admin_mdp')), DonneesFictives.motDePasse);
      await t.tap(find.byKey(const Key('pointage_enroler')));
      expect(await e.attendreQue(t, find.byKey(const Key('pointage_assistant_erreur'))), isTrue);
      expect(find.textContaining('Ressources humaines'), findsWidgets);
      expect(e.bornes.bornes, isEmpty);
      expect(e.serveur.sessions, isEmpty);
      expect(await e.coffre.lire(), isNull);
      await e.fermer(t);
    });
  });

  group('pointage', () {
    testWidgets('QR (secret nulle part), douchette 1D, NFC ; relecture < 2 min ignorée', (t) async {
      telephone(t);
      final e = PointageE2E();
      await e.preparer(configure: true);
      final i = await e.enrolerDirectement();
      await e.lancer(t);
      expect(await e.attendreQue(t, find.byKey(const Key('rh_badge_champ'))), isTrue);
      await e.attendre(t);

      await e.badge(t, qrBadgeE2E);
      expect(await e.attendreQue(t, find.textContaining('Bonjour Awa — ENTRÉE')), isTrue);
      await e.attendre(t, const Duration(seconds: 3));
      await e.badge(t, 'B002');
      expect(await e.attendreQue(t, find.textContaining('Bonjour Ali — ENTRÉE')), isTrue);
      await e.attendre(t, const Duration(seconds: 3));
      e.nfc.approcher('04:a1:b2:c3');
      await t.pump();
      expect(await e.attendreQue(t, find.textContaining('Bonjour Mariam — ENTRÉE')), isTrue);
      await e.attendre(t, const Duration(seconds: 3));
      expect([for (final p in e.bornes.pointages.values) p['employeId']], ['E1', 'E2', 'E3']);
      for (final p in e.bornes.pointages.values) {
        expect(p['id'], matches(RegExp(r'^[A-Za-z0-9-]{8,40}$')), reason: 'id obligatoire du serveur');
        expect(p['borne'], i.borneId);
      }
      // Relecture du même badge : rien envoyé.
      await t.enterText(find.byKey(const Key('rh_badge_champ')), 'B002');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      expect(find.textContaining('Ali, vous avez déjà pointé'), findsWidgets);
      await e.attendre(t, const Duration(seconds: 3));
      expect(e.bornes.pointages, hasLength(3));
      // Secret du badge : ni envoyé, ni journalisé, ni gardé ; contenu brut du scan jamais journalisé.
      expect(toutLeReseau(e.serveur), isNot(contains(secretBadgeE2E)));
      expect(toutLeReseau(e.serveur), isNot(contains('PRESTIGE-BADGE')));
      expect(await toutLeJournal(), isNot(contains(secretBadgeE2E)));
      expect(e.journaux.join('\n'), isNot(contains(secretBadgeE2E)));
      expect(jsonEncode([for (final p in PointageApp.controleur.rh!.file) p.toJson()]), isNot(contains(secretBadgeE2E)));
      expect(e.bornes.refusSignature, 0);
      expect(t.takeException(), isNull);
      await e.fermer(t);
    });

    testWidgets('file hors ligne : serveur coupé → gardé ; retour → envoyé seul ; renvoi idempotent (deja)', (t) async {
      telephone(t);
      final e = PointageE2E();
      await e.preparer(configure: true);
      await e.enrolerDirectement();
      PointageApp.controleur.intervalleVerification = const Duration(seconds: 20);
      await e.lancer(t);
      expect(await e.attendreQue(t, find.byKey(const Key('rh_badge_champ'))), isTrue);
      await e.attendre(t);
      await e.serveur.couper();
      await e.badge(t, 'B001');
      expect(await e.attendreQue(t, find.textContaining('Hors ligne')), isTrue);
      final rh = PointageApp.controleur.rh!;
      expect(rh.enAttente, 1);
      expect(e.bornes.pointages, isEmpty);
      final id = rh.file.single.id;
      await e.serveur.retablir();
      // Vérification périodique → en ligne → file envoyée sans confirmation.
      await e.attendre(t, const Duration(seconds: 45));
      expect(rh.enAttente, 0);
      expect(e.bornes.pointages.keys, [id]);
      expect(find.byKey(const Key('rh_confirmation_envoi')), findsNothing, reason: 'aucune confirmation sur la borne');
      // Réponse perdue puis renvoi : même id → « deja », rien de créé.
      final corps = e.serveur.recues.lastWhere((r) => r.chemin.endsWith('/borne-pointage/pointages')).json;
      final r = await e.fini(t, PointageApp.controleur.client!.post('/rh/pointages', corps));
      expect(r.body?['deja'], isTrue);
      expect(e.bornes.pointages, hasLength(1));
      await e.fermer(t);
    });
  });

  group('états de la borne', () {
    testWidgets('borne retirée : bandeau « Appareil retiré », pointage gardé ; réenrôlement → la file part', (t) async {
      telephone(t);
      final e = PointageE2E();
      await e.preparer(configure: true);
      final i = await e.enrolerDirectement();
      await e.lancer(t);
      expect(await e.attendreQue(t, find.byKey(const Key('rh_badge_champ'))), isTrue);
      await e.attendre(t);
      e.bornes.retirer(i.borneId);
      await e.badge(t, 'B001');
      expect(await e.attendreQue(t, find.byKey(const Key('pointage_bandeau_revoquee'))), isTrue);
      expect(find.textContaining('Appareil retiré : faites-le enrôler à nouveau'), findsOneWidget);
      expect(PointageApp.controleur.rh!.enAttente, 1);
      await e.attendre(t, const Duration(seconds: 5));
      // Administration → enrôler à nouveau.
      await t.tap(find.byKey(const Key('pointage_admin')));
      expect(await e.attendreQue(t, find.byKey(const Key('pointage_administration'))), isTrue);
      expect(find.textContaining('Appareil retiré'), findsWidgets);
      await t.scrollUntilVisible(find.byKey(const Key('pointage_admin_reenroler')), 150,
          scrollable: find.descendant(of: find.byKey(const Key('pointage_administration')), matching: find.byType(Scrollable)).first);
      await t.ensureVisible(find.byKey(const Key('pointage_admin_reenroler')));
      await t.pump();
      await t.tap(find.byKey(const Key('pointage_admin_reenroler')));
      expect(await e.attendreQue(t, find.byKey(const Key('pointage_serveur_suivant'))), isTrue);
      await t.tap(find.byKey(const Key('pointage_serveur_suivant')));
      expect(await e.attendreQue(t, find.byKey(const Key('pointage_admin_login'))), isTrue);
      await t.enterText(find.byKey(const Key('pointage_admin_login')), DonneesFictives.admin);
      await t.enterText(find.byKey(const Key('pointage_admin_mdp')), DonneesFictives.motDePasseAdmin);
      await t.tap(find.byKey(const Key('pointage_enroler')));
      expect(await e.attendreQue(t, find.byKey(const Key('rh_badge_champ'))), isTrue);
      await e.attendre(t, const Duration(seconds: 3));
      final nouvelle = (await e.coffre.lire())!;
      expect(nouvelle.borneId, isNot(i.borneId));
      expect(nouvelle.nom, 'Borne entrée', reason: 'nom de l\'appareil gardé');
      expect(PointageApp.controleur.rh!.enAttente, 0);
      expect(e.bornes.pointages.values.single['borne'], nouvelle.borneId);
      expect(find.byKey(const Key('pointage_bandeau_revoquee')), findsNothing);
      expect(e.serveur.sessions, isEmpty);
      await e.fermer(t);
    });

    for (final c in [
      (nom: 'hors du réseau de l\'officine', etat: EtatBorne.reseau, texte: 'Borne utilisable seulement sur le réseau de l\'officine'),
      (nom: 'serveur sans la demande 57', etat: EtatBorne.serveurAncien, texte: 'Serveur à mettre à jour'),
      (nom: 'horloge décalée de 10 min', etat: EtatBorne.horloge, texte: 'Heure du terminal incorrecte'),
    ]) {
      testWidgets('${c.nom} → bandeau « ${c.texte} », pointage gardé en file', (t) async {
        telephone(t);
        final e = PointageE2E();
        await e.preparer(configure: true);
        await e.enrolerDirectement();
        await e.lancer(t);
        expect(await e.attendreQue(t, find.byKey(const Key('rh_badge_champ'))), isTrue);
        await e.attendre(t); // copie des employés reçue
        switch (c.etat) {
          case EtatBorne.reseau:
            e.bornes.horsReseau = true;
          case EtatBorne.serveurAncien:
            e.serveur.filtreAvantSession = null;
          default:
            e.bornes.horloge = () => DateTime.now().add(const Duration(minutes: 10));
        }
        await e.fini(t, PointageApp.controleur.verifier());
        expect(await e.attendreQue(t, find.byKey(Key('pointage_bandeau_${c.etat.name}'))), isTrue);
        expect(find.textContaining(c.texte), findsOneWidget);
        await e.badge(t, 'B001');
        await e.attendre(t, const Duration(seconds: 3));
        expect(PointageApp.controleur.rh!.enAttente, 1);
        expect(e.bornes.pointages, isEmpty);
        expect(t.takeException(), isNull);
        await e.fermer(t);
      });
    }
  });

  group('empreintes', () {
    testWidgets('partagées : recopiées à l\'ouverture puis pointage par empreinte (motif « Empreinte terminal »)', (t) async {
      telephone(t);
      final e = PointageE2E();
      await e.preparer(configure: true);
      await e.enrolerDirectement();
      e.empreinte.present = true;
      e.empreinte.reconnu = 0;
      e.bornes.empreintesPartagees = true;
      e.bornes.modelesEmpreintes = [
        {'id': 'M1', 'employeId': 'E1', 'format': formatEmpreinteSunmi, 'capteur': 'A400', 'doigt': 'INDEX_D', 'modele': base64Encode([1, 2, 3]), 'dtCreation': '2026-10-26T07:00:00'},
      ];
      await e.lancer(t);
      expect(await e.attendreQue(t, find.byKey(const Key('rh_empreinte'))), isTrue, reason: 'modèle recopié');
      expect(e.coffreEmpreintes.donnees.keys, ['E1']);
      await t.tap(find.byKey(const Key('rh_empreinte')));
      expect(await e.attendreQue(t, find.textContaining('Bonjour Awa — ENTRÉE')), isTrue);
      await e.attendre(t, const Duration(seconds: 3));
      expect(e.bornes.pointages.values.single['motif'], 'Empreinte terminal Borne entrée');
      expect(toutLeReseau(e.serveur), isNot(contains(base64Encode([1, 2, 3]))) , reason: 'aucun modèle envoyé');
      await e.fermer(t);
    });

    testWidgets('DESACTIVE : enrôlement local par un compte RH temporaire, déconnecté au retour', (t) async {
      telephone(t);
      final e = PointageE2E();
      await e.preparer(configure: true);
      await e.enrolerDirectement();
      e.empreinte.present = true;
      e.serveur.activerTerminalRh();
      e.serveur.droitsRh[DonneesFictives.admin] = (pointer: true, gerer: true);
      await e.lancer(t);
      expect(await e.attendreQue(t, find.byKey(const Key('rh_badge_champ'))), isTrue);
      await e.attendre(t);
      expect(find.byKey(const Key('rh_empreinte')), findsNothing, reason: 'aucun employé enrôlé');
      await t.tap(find.byKey(const Key('pointage_admin')));
      expect(await e.attendreQue(t, find.byKey(const Key('pointage_admin_empreintes'))), isTrue);
      await t.scrollUntilVisible(find.byKey(const Key('pointage_admin_empreintes')), 150,
          scrollable: find.descendant(of: find.byKey(const Key('pointage_administration')), matching: find.byType(Scrollable)).first);
      await t.ensureVisible(find.byKey(const Key('pointage_admin_empreintes')));
      await t.pump();
      await t.tap(find.byKey(const Key('pointage_admin_empreintes')));
      expect(await e.attendreQue(t, find.byKey(const Key('pointage_rh_login'))), isTrue);
      await t.enterText(find.byKey(const Key('pointage_rh_login')), DonneesFictives.admin);
      await t.enterText(find.byKey(const Key('pointage_rh_mdp')), DonneesFictives.motDePasseAdmin);
      await t.tap(find.byKey(const Key('pointage_rh_valider')));
      expect(await e.attendreQue(t, find.byType(EmpreintesScreen)), isTrue);
      expect(e.serveur.sessions, hasLength(1), reason: 'session temporaire ouverte pendant l\'enrôlement');
      Navigator.of(t.element(find.byType(EmpreintesScreen))).pop();
      await e.attendre(t);
      expect(find.byType(EmpreintesScreen), findsNothing);
      expect(e.serveur.sessions, isEmpty, reason: 'déconnectée au retour');
      expect(await DioClient.cookieJar.loadForRequest(Uri.parse(e.serveur.base)), isEmpty);
      // La borne pointe toujours avec sa clé (aucune session).
      expect(await e.fini(t, PointageApp.controleur.verifier()), isTrue);
      await e.fermer(t);
    });
  });
}
