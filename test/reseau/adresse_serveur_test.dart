// RÉSEAU — passage LOCAL ↔ DISTANT (application entière, DEUX faux serveurs Prestige en mémoire : « local »
// = prestige.test, « distant » = distant.test) :
//  - serveur local coupé sur l'écran de connexion : « Serveur injoignable » ; « Changer » (code administrateur)
//    → Serveur distant → « Serveur distant connecté », connexion et accueil sur le distant ; plus RIEN n'est
//    envoyé au serveur local ;
//  - retour au serveur local rétabli : connexion sur le local, plus rien vers le distant ; la session (cookie)
//    de l'un n'est jamais envoyée à l'autre.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/accueil/accueil_screen.dart';
import 'package:prestige_vente_app/connexion/connexion_commun.dart';
import 'package:prestige_vente_app/connexion/connexion_screen.dart';

import '../outils/app_e2e.dart';

const hoteDistant = 'distant.test';

/// « Changer » de serveur sur l'écran de connexion (les deux adresses sont testées et leur état affiché), puis
/// la ligne [cle] (serveur_local / serveur_distant). [etats] : états attendus dans la liste.
Future<void> changerServeur(WidgetTester t, AppE2E app, String cle, {Map<String, int> etats = const {}}) async {
  await t.ensureVisible(find.byKey(const Key('changer_serveur')));
  await t.tap(find.byKey(const Key('changer_serveur')));
  await app.attendre(t, const Duration(seconds: 2));
  etats.forEach((etat, n) => expect(find.text(etat), findsNWidgets(n), reason: 'état « $etat » dans la liste des serveurs'));
  expect(find.byKey(Key(cle)), findsOneWidget);
  await t.tap(find.byKey(Key(cle)));
  await app.attendre(t, const Duration(seconds: 3));
}

void main() {
  testWidgets('local coupé → distant → local : chaque requête vers le serveur choisi, aucune vers l\'autre', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final app = AppE2E();
    final local = app.serveur;
    await app.preparer(prefs: const {'remote_ip': hoteDistant});
    final distant = FauxServeurPrestige(hoteEnMemoire: hoteDistant)..installerEnMemoire();
    addTearDown(distant.desinstaller);
    ConnexionServices.instance = ConnexionServices(adminCheck: (_) async => true);
    addTearDown(() => ConnexionServices.instance = const ConnexionServices());

    await app.lancer(t);
    expect(await app.attendreQue(t, find.byType(ConnexionScreen)), isTrue);
    await app.attendre(t);
    expect(find.text('Serveur local connecté'), findsOneWidget);
    expect(distant.recues, isEmpty, reason: 'distant jamais appelé tant que le local est choisi');

    // Coupure du serveur local, puis passage au distant (la liste montre le local injoignable).
    await local.couper();
    await changerServeur(t, app, 'serveur_distant', etats: {'Injoignable': 1, 'Répond': 1});
    expect(await app.attendreQue(t, find.text('Serveur distant connecté'), max: const Duration(seconds: 15)), isTrue);
    final localAvant = local.tentatives.length;
    expect(await app.seConnecter(t), isTrue);
    await app.attendre(t, const Duration(seconds: 3));
    expect(find.byType(AccueilScreen), findsOneWidget);
    expect(distant.connexions, 1, reason: 'connexion sur le distant');
    expect(distant.recuesSur('/ventestats/preventes'), isNotEmpty, reason: 'chargements de l\'accueil sur le distant');
    expect(local.tentatives.length, localAvant, reason: 'plus aucune requête vers le serveur local');
    expect(distant.refusSession, 0, reason: 'session du distant envoyée au distant');

    // Déconnexion, serveur local rétabli, retour au local.
    await app.fermer(t);
    await local.retablir();
    await app.lancer(t);
    expect(await app.attendreQue(t, find.byType(ConnexionScreen)), isTrue);
    await app.attendre(t);
    expect(find.text('Serveur distant connecté'), findsOneWidget, reason: 'choix du distant mémorisé');
    await changerServeur(t, app, 'serveur_local', etats: {'Répond': 2});
    expect(await app.attendreQue(t, find.text('Serveur local connecté'), max: const Duration(seconds: 15)), isTrue);
    final distantAvant = distant.recues.length;
    final sessionsLocal = local.connexions;
    expect(await app.seConnecter(t), isTrue);
    await app.attendre(t, const Duration(seconds: 3));
    expect(local.connexions, sessionsLocal + 1, reason: 'connexion sur le local');
    expect(distant.recues.length, distantAvant, reason: 'plus aucune requête vers le distant');
    expect(local.refusSession, 0, reason: 'aucune session du distant envoyée au local');
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });
}
