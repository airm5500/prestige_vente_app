// RÉSEAU — COUPURE puis RETOUR du serveur, plusieurs fois, et reprise de la file des ventes hors ligne
// (application entière, faux serveur Prestige en mémoire) :
//  - trois cycles coupure → prévente provisoire sur l'appareil → retour → confirmation → envoi : chaque vente
//    est créée UNE fois sur le serveur, la file est vide à la fin ;
//  - coupure PENDANT l'envoi de la file (le serveur crée la vente puis la connexion tombe avant la réponse) :
//    la vente concernée passe « à vérifier » (jamais renvoyée seule : pas de doublon possible), celles qui
//    n'ont pas pu partir restent en attente et partent au retour suivant.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/accueil/accueil_screen.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart' show CatalogueCategorie;
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import '../outils/app_e2e.dart';
import '../outils/parcours_vente.dart';

Future<AppE2E> lancerConnecte(WidgetTester t) async {
  TailleEcran.sunmiV2s.appliquer(t);
  final app = AppE2E();
  CatalogueFictif(app.serveur, nombre: 10);
  await app.preparer(prefs: prefsVente);
  await app.lancer(t);
  expect(await app.seConnecter(t), isTrue);
  await app.attendre(t, const Duration(seconds: 3));
  await app.horsLigne.store.replace(CatalogueCategorie.produits, [for (var i = 1; i <= 10; i++) produitFictif(i)], DateTime.now());
  await app.horsLigne.sync.refreshStats();
  return app;
}

/// Coupure du serveur, détectée par l'application, puis « Continuer hors ligne ».
Future<void> couperEtContinuer(WidgetTester t, AppE2E app) async {
  await app.serveur.couper();
  expect(await app.attendreQue(t, find.text('Continuer hors ligne'), max: const Duration(minutes: 3)), isTrue, reason: 'coupure détectée');
  await t.tap(find.text('Continuer hors ligne'));
  await app.attendre(t);
  expect(app.horsLigne.offline, isTrue);
}

/// Préventes provisoires des produits [produits] (une ligne chacune), enregistrées sur l'appareil.
Future<void> preventesHorsLigne(WidgetTester t, AppE2E app, List<int> produits) async {
  await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
  for (final i in produits) {
    expect(await ajouterAuPanier(t, app, nomCourt(i), qte: '1'), isTrue, reason: 'produit $i dans la copie locale');
    await app.attendre(t);
    await t.tap(find.byKey(const ValueKey('vente-hl-prevente')));
    await app.attendre(t);
    expect(find.text('Prévente provisoire enregistrée'), findsOneWidget);
    await t.tap(find.text('Non'));
    await app.attendre(t);
  }
  await app.retour(t);
  expect(find.byType(AccueilScreen), findsOneWidget);
}

/// Retour du serveur, confirmation de l'envoi, envoi.
Future<void> retablirEtEnvoyer(WidgetTester t, AppE2E app) async {
  await app.serveur.retablir();
  app.horsLigne.monitor.goOnline();
  expect(await app.attendreQue(t, find.byKey(const Key('confirmation_envoi')), max: const Duration(minutes: 2)), isTrue, reason: 'confirmation demandée');
  await t.tap(find.byKey(const Key('envoyer_selection')));
  await app.attendre(t, const Duration(seconds: 6));
}

void main() {
  testWidgets('trois cycles coupure → ventes hors ligne → retour : chaque vente créée une seule fois', (t) async {
    final app = await lancerConnecte(t);
    var attendues = 0;
    for (final cycle in [
      [1, 2],
      [3],
      [4, 5],
    ]) {
      await couperEtContinuer(t, app);
      await preventesHorsLigne(t, app, cycle);
      expect(app.horsLigne.ventes.enAttente, cycle.length);
      expect(app.serveur.ventes, hasLength(attendues), reason: 'rien n\'est envoyé pendant la coupure');
      await retablirEtEnvoyer(t, app);
      attendues += cycle.length;
      expect(app.horsLigne.ventes.enAttente, 0, reason: 'file reprise au retour');
      expect(app.horsLigne.ventes.aVerifier, 0);
      expect(app.serveur.ventes, hasLength(attendues), reason: 'chaque vente créée une seule fois');
      await app.attendre(t, const Duration(seconds: 2));
    }
    expect(app.serveur.recuesSur('/vente/add/vno'), hasLength(5));
    expect(app.serveur.statutVentes.values.toSet(), {'is_Process'}, reason: 'toutes enregistrées en prévente');
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  testWidgets('coupure PENDANT l\'envoi : vente « à vérifier » (pas de doublon), les suivantes partent au retour', (t) async {
    final app = await lancerConnecte(t);
    await couperEtContinuer(t, app);
    await preventesHorsLigne(t, app, [1, 2, 3]);
    expect(app.horsLigne.ventes.enAttente, 3);

    // La 2e création est traitée par le serveur, puis la connexion tombe avant la réponse.
    var creations = 0;
    app.serveur.routes['POST /vente/add/vno'] = (r) async {
      creations++;
      final f = app.serveur.routes.remove('POST /vente/add/vno')!;
      final rep = await app.serveur.repondre(r);
      app.serveur.routes['POST /vente/add/vno'] = f;
      if (creations == 2) await app.serveur.couper();
      return rep;
    };
    await retablirEtEnvoyer(t, app);
    expect(app.serveur.ventes, hasLength(2), reason: 'la 1re envoyée, la 2e créée par le serveur (réponse perdue)');
    expect(app.horsLigne.ventes.aVerifier, 1, reason: 'réponse perdue : à vérifier, pas renvoyée');
    expect(app.horsLigne.ventes.enAttente, 1, reason: 'la 3e attend le retour du serveur');

    // Retour : seule la 3e part ; la 2e n'est jamais renvoyée automatiquement.
    app.horsLigne.monitor.goOffline();
    await app.attendre(t);
    await retablirEtEnvoyer(t, app);
    expect(app.serveur.ventes, hasLength(3), reason: 'aucun doublon');
    expect(app.horsLigne.ventes.enAttente, 0);
    expect(app.horsLigne.ventes.aVerifier, 1);
    expect(creations, 3);
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });
}
