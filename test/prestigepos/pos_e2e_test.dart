// PrestigePOS — e2e de l'application ENTIÈRE (PrestigePosApp, initialisation de lib/main_pos.dart), contre le faux
// serveur Prestige en mémoire :
//  - premier lancement → code administrateur → assistant (serveur, utilisateur borne + « Tester la borne »,
//    présentation, imprimante Bluetooth « Rechercher » / « Ajouter » / test) → borne plein écran épinglée →
//    recherche → panier → prévente sur le serveur → ticket ESC/POS envoyé à l'imprimante Bluetooth ;
//  - sortie par code administrateur (mauvais code refusé), administration, reprise (manuelle et automatique) ;
//  - serveur injoignable puis rétabli ; session de l'utilisateur borne expirée ; imprimante en panne ;
//    licence absente.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/borne/borne_config.dart';
import 'package:prestige_vente_app/borne/borne_screen.dart';
import 'package:prestige_vente_app/prestigepos/impression/imprimante_reglages.dart';
import 'package:prestige_vente_app/prestigepos/impression/transports.dart';
import 'package:prestige_vente_app/prestigepos/pos_admin.dart';
import 'package:prestige_vente_app/prestigepos/pos_reglages.dart';
import 'package:prestige_vente_app/screens/auth/login_screen.dart';
import 'package:prestige_vente_app/serveur/nom_appareil.dart';
import 'package:prestige_vente_app/serveur/nom_appareil_serveur.dart';

import 'outils/pos_e2e.dart';

void tablettePortrait(WidgetTester t) {
  t.view.physicalSize = const Size(1200, 1920);
  t.view.devicePixelRatio = 1.5;
  addTearDown(t.view.reset);
}

/// Borne prête (données chargées) ?
Future<void> attendreBorne(WidgetTester t, PosE2E app) async {
  expect(await app.attendreQue(t, find.byKey(const ValueKey('borne-recherche')), max: const Duration(seconds: 20)), isTrue,
      reason: 'la borne doit s\'ouvrir avec ses données');
  // Fin de la transition d'ouverture (zoom Android).
  await app.attendre(t, const Duration(seconds: 1));
}

/// Client : « doli » → ajoute le 1er produit → panier → « Payer en caisse ».
Future<void> acheter(WidgetTester t, PosE2E app) async {
  await app.chercher(t, 'doli');
  await app.toucher(t, 'borne-ajouter-F1');
  // Le message « Ajouté : … » (2 s, en haut de l'écran depuis 4.3.0 / 1.1.0) : on attend qu'il disparaisse.
  await app.attendre(t, const Duration(milliseconds: 2600));
  await app.toucher(t, 'borne-voir-panier');
  await app.toucher(t, 'borne-payer');
  expect(await app.attendreQue(t, find.byKey(const ValueKey('borne-numero'))), isTrue, reason: 'écran du ticket');
}

void main() {
  testWidgets('premier lancement : assistant → borne → panier → prévente → ticket Bluetooth', (t) async {
    tablettePortrait(t);
    final app = PosE2E();
    await app.preparer();
    await app.lancer(t);

    // Écran d'accueil du premier lancement, puis code administrateur.
    expect(await app.attendreQue(t, find.byKey(const ValueKey('pos-bienvenue'))), isTrue);
    await app.toucher(t, 'pos-configurer');
    await app.saisirCode(t);
    expect(find.byKey(const ValueKey('pos-assistant')), findsOneWidget);
    expect(app.code.demandes, 1);

    // 1. Serveur : adresse vérifiée avant de continuer.
    await app.saisir(t, 'pos-serveur-adresse', FauxServeurPrestige.hoteMemoire);
    await app.saisir(t, 'pos-serveur-port', FauxServeurPrestige.portMemoire);
    await app.toucher(t, 'pos-serveur-verifier');
    await app.attendre(t);
    expect(find.text('2. Utilisateur borne'), findsOneWidget);

    // 2. Utilisateur borne + « Tester la borne ».
    await app.saisir(t, 'pos-borne-login', loginBorne);
    await app.saisir(t, 'pos-borne-mdp', mdpBorne);
    await app.toucher(t, 'pos-borne-tester');
    expect(await app.attendreQue(t, find.byKey(const ValueKey('borne-diagnostic-conclusion'))), isTrue);
    expect(find.textContaining('La borne est prête'), findsOneWidget);
    expect(await BorneReglages.secrets.lire(), mdpBorne, reason: 'mot de passe dans le stockage sécurisé');
    await app.toucher(t, 'pos-suivant');

    // 3. Présentation.
    expect(find.text('3. Présentation'), findsOneWidget);
    await app.toucher(t, 'pos-presentation-vitrine');
    await app.toucher(t, 'pos-suivant');

    // 4. Imprimante Bluetooth : Rechercher → choisir → Ajouter → Test d'impression.
    expect(find.text('4. Imprimante'), findsOneWidget);
    await app.toucher(t, 'imp-type-bluetooth');
    await app.toucher(t, 'imp-bt-rechercher');
    await app.attendre(t, const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('imp-bt-trouve-10:20:30:40:50:60')), findsOneWidget, reason: 'appareils découverts listés');
    await app.toucher(t, 'imp-bt-trouve-${imprimanteBt.adresse}');
    await app.toucher(t, 'imp-bt-ajouter');
    expect(ImprimanteReglages.courant.value.bluetooth, imprimanteBt);
    expect(ImprimanteReglages.courant.value.memorisees, [imprimanteBt]);
    await app.toucher(t, 'imp-test');
    await app.attendre(t);
    expect(app.pont.envois.length, 1, reason: 'ticket d\'essai envoyé');
    expect(find.textContaining('Ticket d\'essai imprimé'), findsOneWidget);
    await app.toucher(t, 'pos-suivant');

    // 5. Terminé → borne.
    expect(find.text('5. Terminé'), findsOneWidget);
    await app.toucher(t, 'pos-demarrer');
    // 1.5.1 : nom de cet appareil obligatoire avant la borne (pré-rempli : un appui sur « Enregistrer »).
    expect(await app.attendreQue(t, find.byKey(const Key('nom_appareil_etape'))), isTrue, reason: 'étape « Nom de cet appareil »');
    await t.binding.handlePopRoute();
    await app.attendre(t, const Duration(milliseconds: 500));
    expect(find.byKey(const Key('nom_appareil_etape')), findsOneWidget, reason: 'retour bloqué');
    await t.enterText(find.byKey(const Key('nom_appareil_champ')), 'Borne entrée');
    await t.tap(find.byKey(const Key('nom_appareil_enregistrer')));
    await attendreBorne(t, app);
    expect(NomAppareil.instance.saisi, 'Borne entrée');
    expect(PosReglages.courant.value.configure, isTrue);
    expect(BorneReglages.courant.value.actif, isTrue);
    expect(app.kiosque.demarrages, 1, reason: 'écran épinglé');
    expect(app.modesSysteme.last, 'SystemUiMode.immersiveSticky', reason: 'plein écran');

    // Client : recherche, panier, prévente, ticket.
    final ventesAvant = app.serveur.ventes.length;
    await acheter(t, app);
    expect(app.serveur.ventes.length, ventesAvant + 1, reason: 'prévente créée sur le serveur');
    expect(app.serveur.ventes.values.last.single['lgFAMILLEID'], 'F1');
    expect(app.pont.envois.length, 2);
    expect(app.pont.envois.last.$1, imprimanteBt.adresse);
    final ticket = app.ticketsTexte().last;
    for (final attendu in ['PRE-VENTE BORNE', 'TOTAL A PAYER: 1 500 F', 'REF-V-1', 'Presentez ce ticket a la caisse']) {
      expect(ticket, contains(attendu));
    }
    expect(find.text('Votre ticket s\'imprime.'), findsOneWidget);
    expect(find.byKey(const ValueKey('borne-impression-echec')), findsNothing);
    await app.fermer(t);
  });

  testWidgets('sortie par code administrateur → administration → reprise ; reprise automatique après 3 min', (t) async {
    tablettePortrait(t);
    final app = PosE2E();
    await app.preparer(configure: true);
    await app.lancer(t);
    await attendreBorne(t, app);

    // Mauvais code : la borne reste.
    await app.appuiLong(t, find.byKey(const ValueKey('borne-sortie')));
    await app.toucher(t, 'sortie-kiosque-confirmer');
    await app.saisirCode(t, '0000');
    if (find.text('Annuler').evaluate().isNotEmpty) {
      await t.tap(find.text('Annuler'));
      await app.attendre(t, const Duration(seconds: 1));
    }
    expect(find.byType(BorneScreen), findsOneWidget);
    expect(app.kiosque.arrets, 0);

    // Bon code : administration (jamais l'écran de connexion de Prestige Mobile).
    await app.quitterBorne(t);
    expect(await app.attendreQue(t, find.byType(PosAdminScreen)), isTrue);
    expect(find.byType(LoginScreen), findsNothing);
    expect(app.kiosque.arrets, 1, reason: 'désépinglé');
    expect(BorneReglages.courant.value.actif, isFalse);

    // Imprimante depuis l'administration, puis reprise manuelle.
    await app.toucher(t, 'pos-admin-imprimante');
    expect(find.byKey(const ValueKey('pos-imprimante-page')), findsOneWidget);
    expect(find.byKey(ValueKey('imp-bt-memorisee-${imprimanteBt.adresse}')), findsOneWidget);
    await t.binding.handlePopRoute();
    await app.attendre(t, const Duration(seconds: 1));
    await app.toucher(t, 'pos-admin-reprendre');
    await attendreBorne(t, app);
    expect(BorneReglages.courant.value.actif, isTrue);
    expect(app.kiosque.demarrages, 2);

    // Administration oubliée ouverte : la borne reprend seule après 3 min.
    await app.quitterBorne(t);
    expect(await app.attendreQue(t, find.byType(PosAdminScreen)), isTrue);
    await t.pump(const Duration(minutes: 3, seconds: 1));
    await attendreBorne(t, app);
    expect(app.kiosque.demarrages, 3);
    await app.fermer(t);
  });

  // 1.5.0 (Prestige Mobile 4.7.0) : nom de cet appareil dans l'en-tête X-Poste, réglé depuis l'administration.
  testWidgets('nom de cet appareil : modifiable dans l\'administration ; X-Poste sur toutes les requêtes de la borne', (t) async {
    tablettePortrait(t);
    final app = PosE2E();
    await app.preparer(configure: true, prefs: {NomAppareil.prefNom: 'Borne entrée'});
    await app.lancer(t);
    await attendreBorne(t, app);
    expect(app.serveur.recues, isNotEmpty);
    for (final r in app.serveur.recues) {
      expect(r.poste, 'Borne%20entr%C3%A9e', reason: '$r');
    }
    await app.quitterBorne(t);
    expect(await app.attendreQue(t, find.byType(PosAdminScreen)), isTrue);
    expect(find.text('Borne entrée'), findsOneWidget);
    await app.toucher(t, 'pos-admin-nom-appareil');
    expect(find.byKey(const ValueKey('pos-nom-appareil-page')), findsOneWidget);
    await t.enterText(find.byKey(const Key('nom_appareil_champ')), 'Borne #2');
    await t.pump();
    expect(find.text('Enregistré dans Prestige : « Borne 2 »'), findsOneWidget);
    await t.tap(find.byKey(const Key('nom_appareil_enregistrer')));
    await app.attendre(t, const Duration(seconds: 1));
    expect(NomAppareil.instance.entete, 'Borne%202');
    await t.binding.handlePopRoute();
    await app.attendre(t, const Duration(seconds: 1));
    expect(find.text('Borne 2'), findsOneWidget);
    expect(t.takeException(), isNull);
    await app.toucher(t, 'pos-admin-reprendre');
    await attendreBorne(t, app);
    final avant = app.serveur.recues.length;
    await acheter(t, app);
    final apres = app.serveur.recues.sublist(avant);
    expect(apres, isNotEmpty);
    for (final r in apres) {
      expect(r.poste, 'Borne%202', reason: '$r');
    }
    expect(app.serveur.recuesSur('/vente/add/vno').last.poste, 'Borne%202', reason: 'poste de saisie de la prévente');
    await app.fermer(t);
  });

  testWidgets('1.5.1 : administration sans nom enregistré : carte obligatoire, sortie refusée, puis reprise', (t) async {
    tablettePortrait(t);
    final app = PosE2E();
    await app.preparer(configure: true, nomAppareil: false);
    await app.lancer(t);
    await attendreBorne(t, app);
    expect(find.byKey(const Key('nom_appareil_etape')), findsNothing, reason: 'jamais d\'étape sur l\'écran de la borne');
    expect(find.byKey(const Key('nom_appareil_obligatoire')), findsNothing);
    await app.quitterBorne(t);
    expect(await app.attendreQue(t, find.byType(PosAdminScreen)), isTrue);
    expect(find.byKey(const Key('nom_appareil_obligatoire')), findsOneWidget);
    await app.toucher(t, 'pos-admin-reprendre');
    expect(find.byType(PosAdminScreen), findsOneWidget, reason: 'sortie refusée sans nom');
    expect(find.text('Saisissez le nom de cet appareil avant de quitter l\'administration.'), findsOneWidget);
    // Marque et modèle inconnus sous les tests (pas de canal natif) : champ vide, nom vide refusé.
    await t.tap(find.byKey(const Key('nom_appareil_enregistrer')));
    await app.attendre(t, const Duration(milliseconds: 500));
    expect(NomAppareil.instance.nomEnregistre, isFalse);
    await t.enterText(find.byKey(const Key('nom_appareil_champ')), 'Borne caisse');
    await t.tap(find.byKey(const Key('nom_appareil_enregistrer')));
    await app.attendre(t, const Duration(seconds: 1));
    expect(NomAppareil.instance.nomEnregistre, isTrue);
    expect(find.byKey(const Key('nom_appareil_obligatoire')), findsNothing);
    await app.toucher(t, 'pos-admin-reprendre');
    await attendreBorne(t, app);
    await app.fermer(t);
  });

  // 1.6.0 (demande 56) : réinstallation simulée (préférences sans nom, même empreinte) : le nom gardé par le serveur
  // revient dans l'administration sans rien demander ; la borne n'affiche rien au client.
  testWidgets('1.6.0 : réinstallation : nom retrouvé sur le serveur, carte obligatoire levée, X-Poste rétabli', (t) async {
    tablettePortrait(t);
    final app = PosE2E();
    final emp = 'b0b0cafe' * 8;
    app.serveur.activerNomAppareil();
    app.serveur.nomsAppareils[emp] = 'Borne entrée';
    await app.preparer(configure: true, nomAppareil: false);
    NomAppareilServeur.instance.empreinte = () async => emp;
    await app.lancer(t);
    await attendreBorne(t, app);
    expect(find.byKey(const Key('nom_appareil_obligatoire')), findsNothing);
    await app.quitterBorne(t);
    expect(await app.attendreQue(t, find.byType(PosAdminScreen)), isTrue);
    await app.attendre(t, const Duration(seconds: 1));
    expect(NomAppareil.instance.saisi, 'Borne entrée');
    expect(find.byKey(const Key('nom_appareil_obligatoire')), findsNothing, reason: 'nom retrouvé : plus de carte');
    final get = app.serveur.recues.where((r) => r.chemin.endsWith('/appareil/nom')).single;
    expect((get.methode, get.query['empreinte']), ('GET', emp));
    await app.toucher(t, 'pos-admin-reprendre');
    await attendreBorne(t, app);
    await acheter(t, app);
    expect(app.serveur.recuesSur('/vente/add/vno').last.poste, 'Borne%20entr%C3%A9e');
    await app.fermer(t);
  });

  testWidgets('serveur injoignable au démarrage : « momentanément indisponible », puis reprise automatique', (t) async {
    tablettePortrait(t);
    final app = PosE2E();
    await app.preparer(configure: true);
    await app.serveur.couper();
    await app.lancer(t);
    expect(await app.attendreQue(t, find.byKey(const ValueKey('borne-indisponible')), max: const Duration(seconds: 30)), isTrue);
    expect(find.text(BorneScreen.indisponibleTexte), findsOneWidget);
    expect(find.byKey(const ValueKey('borne-sortie')), findsOneWidget, reason: 'sortie possible depuis « indisponible »');

    await app.serveur.retablir();
    expect(await app.attendreQue(t, find.byKey(const ValueKey('borne-recherche')), max: const Duration(seconds: 70)), isTrue,
        reason: 'la borne reprend seule quand le serveur répond');
    await acheter(t, app);
    expect(app.pont.envois, isNotEmpty);
    await app.fermer(t);
  });

  testWidgets('session de l\'utilisateur borne expirée : reconnexion silencieuse, la vente continue', (t) async {
    tablettePortrait(t);
    final app = PosE2E();
    await app.preparer(configure: true);
    await app.lancer(t);
    await attendreBorne(t, app);
    expect(app.serveur.connexions, 1);
    app.serveur.expirerSessions();
    await acheter(t, app);
    expect(app.serveur.connexions, 2, reason: 'l\'utilisateur borne est reconnecté');
    expect(app.serveur.refusSession, greaterThan(0));
    expect(find.byType(LoginScreen), findsNothing);
    expect(app.pont.envois, isNotEmpty);
    await app.fermer(t);
  });

  testWidgets('imprimante en panne : message clair, ticket (QR) affiché à l\'écran', (t) async {
    tablettePortrait(t);
    final app = PosE2E();
    await app.preparer(configure: true);
    app.pont.echec = EchecImpression('CONNEXION', EchecImpression.messagePour('CONNEXION'));
    await app.lancer(t);
    await attendreBorne(t, app);
    await acheter(t, app);
    expect(find.byKey(const ValueKey('borne-impression-echec')), findsOneWidget);
    expect(find.textContaining('Imprimante Bluetooth injoignable'), findsOneWidget);
    expect(find.byKey(const ValueKey('borne-qr')), findsOneWidget, reason: 'le client peut photographier le QR');
    expect(find.byKey(const ValueKey('borne-reference')), findsOneWidget);
    await app.fermer(t);
  });

  testWidgets('autorisation Bluetooth refusée : message clair dans les réglages de l\'imprimante', (t) async {
    tablettePortrait(t);
    final app = PosE2E();
    await app.preparer(configure: true);
    app.pont.autorise = false;
    await app.lancer(t);
    await attendreBorne(t, app);
    await app.quitterBorne(t);
    await app.toucher(t, 'pos-admin-imprimante');
    await app.toucher(t, 'imp-bt-rechercher');
    expect(find.byKey(const ValueKey('imp-recherche-erreur')), findsOneWidget);
    expect(find.textContaining('Appareils à proximité'), findsOneWidget);
    app.pont
      ..autorise = true
      ..echecRecherche = EchecImpression('BT_INACTIF', EchecImpression.messagePour('BT_INACTIF'));
    await app.toucher(t, 'imp-bt-rechercher');
    expect(find.byKey(const ValueKey('imp-bt-activer')), findsOneWidget, reason: '« Activer le Bluetooth » proposé');
    await app.fermer(t);
  });

  testWidgets('licence absente sur le serveur : borne fermée, administration par code', (t) async {
    tablettePortrait(t);
    final app = PosE2E();
    await app.preparer(configure: true);
    app.serveur.licence = const ReponseLocale('');
    await app.lancer(t);
    expect(await app.attendreQue(t, find.byKey(const ValueKey('pos-licence'))), isTrue);
    expect(find.byType(BorneScreen), findsNothing);
    await app.toucher(t, 'pos-licence-admin');
    await app.saisirCode(t);
    expect(await app.attendreQue(t, find.byType(PosAdminScreen)), isTrue);
    await app.fermer(t);
  });

  testWidgets('bouton Retour d\'Android neutralisé dans la borne', (t) async {
    tablettePortrait(t);
    final app = PosE2E();
    await app.preparer(configure: true);
    await app.lancer(t);
    await attendreBorne(t, app);
    await t.binding.handlePopRoute();
    await app.attendre(t, const Duration(seconds: 1));
    expect(find.byType(BorneScreen), findsOneWidget);
    await app.fermer(t);
  });
}
