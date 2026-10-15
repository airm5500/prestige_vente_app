// RÉSEAU — réponses TRONQUÉES (connexion fermée au milieu du corps) et JSON INVALIDE (réponse complète mais
// illisible), application entière contre le faux serveur Prestige en mémoire :
//  - recherche de la vente, Analyse article (GET /info), préventes à encaisser : message d'erreur et
//    « Réessayer », JAMAIS une liste vide ni « aucun produit » ; la réponse correcte suivante est affichée ;
//  - licence au lancement : problème de serveur, jamais « aucune licence » ni l'écran de clé ;
//  - encaissement dont la réponse est coupée APRÈS la clôture côté serveur : l'application vérifie la vente
//    au lieu de la renvoyer — une seule clôture, vente encaissée.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/screens/analysis/article_analysis_screen.dart';
import 'package:prestige_vente_app/screens/auth/licence_registration_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import '../outils/app_e2e.dart';
import '../outils/parcours_vente.dart';

/// Un message d'erreur est-il affiché ?
Finder messageErreur() => find.byWidgetPredicate((w) {
      if (w is! Text) return false;
      final t = (w.data ?? w.textSpan?.toPlainText() ?? '').toLowerCase();
      return t.contains('injoignable') ||
          t.contains('illisible') ||
          t.contains('inattendue') ||
          t.contains('erreur') ||
          t.contains('impossible') ||
          t.contains('ne répond pas') ||
          t.contains('réessayer');
    });

/// Message « rien trouvé » (faux : le serveur n'a pas dit cela).
Finder rienTrouve() => find.byWidgetPredicate((w) {
      if (w is! Text) return false;
      final t = (w.data ?? w.textSpan?.toPlainText() ?? '').toLowerCase();
      return t.contains('aucun produit') || t.contains('aucune prévente') || t.contains('aucun résultat');
    });

/// Les deux pannes de réponse étudiées, pour une réponse normale [corps].
Map<String, ReponseLocale Function(Object corps)> pannes = {
  'JSON partiel (réponse complète, illisible)': (corps) {
    final texte = ReponseLocale(corps).texte;
    return FauxServeurPrestige.jsonInvalide(texte.substring(0, texte.length ~/ 2));
  },
  'connexion fermée au milieu du corps': (corps) => FauxServeurPrestige.coupeeEnCours(corps),
};

Future<(AppE2E, CatalogueFictif)> lancerConnecte(WidgetTester t, {int preventes = 0}) async {
  TailleEcran.sunmiV2s.appliquer(t);
  final app = AppE2E();
  final c = CatalogueFictif(app.serveur, nombre: 20, preventes: preventes);
  await app.preparer(prefs: prefsVente);
  await app.lancer(t);
  expect(await app.seConnecter(t), isTrue);
  await app.attendre(t, const Duration(seconds: 3));
  return (app, c);
}

void main() {
  pannes.forEach((nom, panne) {
    group(nom, () {
      testWidgets('vente : recherche → message d\'erreur (pas « aucun produit »), puis la réponse correcte suivante', (t) async {
        final (app, c) = await lancerConnecte(t);
        await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
        final normale = app.serveur.routes['GET /vente/search']!;
        app.serveur.routes['GET /vente/search'] = (r) async => panne((await normale(r)).corps!);
        await t.enterText(champRechercheVente, nomCourt(3));
        await app.attendre(t, const Duration(seconds: 2));
        expect(messageErreur(), findsWidgets, reason: 'panne signalée');
        expect(rienTrouve(), findsNothing, reason: 'jamais « aucun produit » sur une réponse illisible');
        expect(champQuantite, findsNothing);

        app.serveur.routes['GET /vente/search'] = normale;
        await t.enterText(champRechercheVente, nomCourt(4));
        expect(await app.attendreQue(t, champQuantite), isTrue, reason: 'réponse correcte : produit trouvé');
        expect(c.produits, hasLength(20));
        expect(t.takeException(), isNull);
        await app.fermer(t);
      });

      testWidgets('Analyse article : GET /info → erreur + Réessayer, la liste reste ; Réessayer → détail', (t) async {
        final (app, _) = await lancerConnecte(t);
        final info = [
          {'codeCip': '3400900000007', 'libelle': 'PRODUIT 0007 CPR B/20', 'produitId': 'F7', 'stock': 50, 'prixVente': 1007, 'emplacement': 'RAYON FICTIF 7', 'grossiste': 'GROSSISTE DEMO'},
        ];
        app.serveur.routes['GET /info'] = (_) => panne(info);
        await app.ouvrirMenu(t, ListPresentation.dashboard, 'analyse_article');
        expect(find.byType(ArticleAnalysisScreen), findsOneWidget);
        await t.enterText(find.byType(TextField).first, nomCourt(7));
        await app.attendre(t, const Duration(seconds: 1));
        await t.tap(find.text('PRODUIT 0007 CPR B/20').hitTestable().first);
        await app.attendre(t, const Duration(seconds: 2));
        expect(find.byKey(const ValueKey('analyse-detail-erreur')), findsOneWidget);
        expect(find.text('Réessayer'), findsOneWidget);
        app.serveur.routes['GET /info'] = (_) => FauxServeurPrestige.ok(info);
        await t.tap(find.text('Réessayer'));
        await app.attendre(t, const Duration(seconds: 2));
        expect(find.byKey(const ValueKey('analyse-detail')), findsOneWidget);
        expect(find.text('RAYON FICTIF 7'), findsOneWidget);
        expect(t.takeException(), isNull);
        await app.fermer(t);
      });

      testWidgets('préventes à encaisser : erreur (pas « aucune prévente »), puis la liste', (t) async {
        final (app, _) = await lancerConnecte(t, preventes: 30);
        await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
        final normale = app.serveur.routes['GET /ventestats/preventes']!;
        app.serveur.routes['GET /ventestats/preventes'] = (r) async => panne((await normale(r)).corps!);
        await t.tap(find.text('Préventes à encaisser').first);
        await app.attendre(t, const Duration(seconds: 2));
        expect(messageErreur(), findsWidgets);
        expect(rienTrouve(), findsNothing, reason: 'jamais « aucune prévente » sur une réponse illisible');
        app.serveur.routes['GET /ventestats/preventes'] = normale;
        await t.tap(find.text('Réessayer').first);
        expect(await app.attendreQue(t, find.textContaining('30 préventes')), isTrue);
        expect(t.takeException(), isNull);
        await app.fermer(t);
      });

      testWidgets('licence au lancement : problème de serveur, jamais « aucune licence »', (t) async {
        TailleEcran.sunmiV2s.appliquer(t);
        final app = AppE2E();
        app.serveur.licence = panne(DonneesFictives.licence());
        await app.preparer();
        await app.lancer(t);
        expect(await app.attendreQue(t, find.byKey(const Key('lancement_injoignable'))), isTrue);
        expect(find.byKey(const Key('lancement_licence')), findsNothing);
        expect(find.textContaining('Aucune licence'), findsNothing);
        expect(find.byType(LicenceRegistrationScreen), findsNothing);
        expect(t.takeException(), isNull);
        await app.fermer(t);
      });
    });
  });

  testWidgets('encaissement : réponse coupée APRÈS la clôture côté serveur → vérification, une seule clôture', (t) async {
    final (app, c) = await lancerConnecte(t);
    await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
    expect(await ajouterAuPanier(t, app, nomCourt(2), qte: '1'), isTrue);
    await app.attendre(t, const Duration(seconds: 2));
    final cloture = app.serveur.routes['POST /vente/cloturer/vno']!;
    app.serveur.routes['POST /vente/cloturer/vno'] = (r) async => FauxServeurPrestige.coupeeEnCours((await cloture(r)).corps);
    await validerEncaissementEspeces(t, app);
    await app.attendre(t, const Duration(seconds: 5));
    expect(c.clotures, 1, reason: 'la vente n\'est pas renvoyée : elle est vérifiée');
    expect(app.serveur.statutVentes.values.single, 'is_Closed');
    expect(app.serveur.recues.where((r) => RegExp(r'/ventestats/V-\d+$').hasMatch(r.chemin)), isNotEmpty, reason: 'statut relu sur le serveur');
    expect(find.text('Le panier est vide'), findsOneWidget, reason: 'vente vérifiée encaissée');
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });
}
