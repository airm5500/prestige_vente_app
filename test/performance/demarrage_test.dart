// PERFORMANCE — DÉMARRAGE de l'application entière (MyApp, vrais providers, vrai Dio) jusqu'à l'écran de
// connexion, puis connexion → accueil dans les présentations A (tableau de bord), B (liste groupée) et
// C (parcours guidé), contre le faux serveur Prestige en mémoire : temps réel mesuré dans le test, nombre
// d'images rendues, pire image en parcourant l'accueil, nombre de requêtes. Seuils : test/outils/performance.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/accueil/accueil_screen.dart';
import 'package:prestige_vente_app/connexion/connexion_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import '../outils/app_e2e.dart';
import '../outils/performance.dart';

/// Pompe image par image (16 ms simulées) jusqu'à ce que [f] soit affiché ; renvoie le temps réel (ms).
Future<double> jusqua(WidgetTester t, Finder f, {int maxImages = 600}) async {
  final sw = Stopwatch()..start();
  var n = 0;
  while (f.evaluate().isEmpty && n < maxImages) {
    await t.pump(const Duration(milliseconds: 16));
    n++;
  }
  expect(f, findsWidgets, reason: 'écran attendu après $n images : $f');
  return sw.elapsedMicroseconds / 1000;
}

void main() {
  testWidgets('lancement → écran de connexion (à froid) : temps, images, requêtes', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final app = AppE2E();
    await app.preparer();
    final images0 = imagesRendues();
    final sw = Stopwatch()..start();
    await app.lancer(t);
    await jusqua(t, find.byType(ConnexionScreen));
    final ms = sw.elapsedMicroseconds / 1000;
    final images = imagesRendues() - images0;
    // Licence (GET /licence/find) + test du serveur affiché sur l'écran de connexion (POST /user/auth sans
    // identifiants : « Serveur local connecté »).
    final rs = app.serveur.recues;
    mesurer('Démarrage → écran de connexion (à froid)', ms, seuil: Seuils.demarrageMs, unite: 'ms', detail: '$images images');
    mesurer('Démarrage → écran de connexion — requêtes', rs.length, seuil: Seuils.demarrageRequetes + 1, unite: 'requêtes', detail: detailRequetes(rs));
    expect(rs.first.chemin, endsWith('/licence/find'), reason: 'la licence d\'abord');
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  for (final style in ListPresentation.values) {
    testWidgets('connexion → accueil ${style.label} : temps, pire image de la page, requêtes', (t) async {
      TailleEcran.sunmiV2s.appliquer(t);
      final app = AppE2E();
      await app.preparer(prefs: {'hiddenMenuIds': <String>[], 'presentation_listes_v1': style.name});
      await app.lancer(t);
      await jusqua(t, find.byType(ConnexionScreen));
      await app.attendre(t, const Duration(seconds: 1));
      await t.enterText(find.byKey(const Key('connexion_login')), DonneesFictives.login);
      await t.enterText(find.byKey(const Key('connexion_mdp')), DonneesFictives.motDePasse);
      await t.ensureVisible(find.byKey(const Key('se_connecter')));
      final avant = app.serveur.recues.length;
      await t.tap(find.byKey(const Key('se_connecter')));
      final ms = await jusqua(t, find.byType(AccueilScreen));
      // Chargements de l'accueil (officine, préventes, BL, droits, catalogue hors ligne…) terminés.
      await app.attendre(t, const Duration(seconds: 5));
      final rs = app.serveur.recues.sublist(avant);
      mesurer('Connexion → accueil ${style.label}', ms, seuil: Seuils.accueilMs, unite: 'ms');

      // Parcours de la page d'accueil (tous les menus) : aucune image lente.
      final liste = find.byType(Scrollable).first;
      if (style == ListPresentation.guided && find.text('Voir tous les menus').evaluate().isNotEmpty) {
        await app.defilerJusqua(t, find.text('Voir tous les menus'));
        await t.tap(find.text('Voir tous les menus'));
        await t.pump();
      }
      // Deux passages : le premier construit les menus (à froid), le second est mesuré.
      await remonter(t, liste);
      await defilerJusquEnBas(t, liste, ChronoImages(), pas: 80);
      await remonter(t, liste);
      final chrono = ChronoImages();
      await defilerJusquEnBas(t, liste, chrono, pas: 80);
      mesurer('Accueil ${style.label} — pire image en parcourant la page (2e passage)', chrono.max, seuil: Seuils.imageAccueilMs, unite: 'ms', detail: chrono.resume);

      // Plafond = requêtes voulues (connexion, licence, chargements de l'accueil, droits, copie hors ligne du
      // catalogue et des clients) : une requête de plus est une régression. 4.3.0 : 24 = 26 de la 4.2 − 3 lectures en
      // double supprimées (ANO-09 : officine, préventes, BL du jour) + 1 droit Posos (GET /posos/droits, demande 5).
      mesurer('Connexion + accueil ${style.label} — requêtes', rs.length, seuil: plafondConnexion, unite: 'requêtes', detail: detailRequetes(rs));
      expect(rs.where((r) => r.chemin.endsWith('/user/auth')), hasLength(1), reason: 'une seule connexion');
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });
  }

  testWidgets('connexion → accueil : aucune lecture en double (même route, mêmes paramètres) sauf les 2 gardées exprès (ANO-09)', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final app = AppE2E();
    await app.preparer(prefs: {'hiddenMenuIds': <String>[]});
    await app.lancer(t);
    expect(await app.attendreQue(t, find.byType(ConnexionScreen)), isTrue);
    await app.attendre(t, const Duration(seconds: 1));
    await t.enterText(find.byKey(const Key('connexion_login')), DonneesFictives.login);
    await t.enterText(find.byKey(const Key('connexion_mdp')), DonneesFictives.motDePasse);
    await t.ensureVisible(find.byKey(const Key('se_connecter')));
    final avant = app.serveur.recues.length; // à partir de l'appui sur « Se connecter »
    await t.tap(find.byKey(const Key('se_connecter')));
    expect(await app.attendreQue(t, find.byType(AccueilScreen)), isTrue);
    await app.attendre(t, const Duration(seconds: 5));
    final vues = <String, int>{};
    for (final r in app.serveur.recues.skip(avant)) {
      final k = '${r.methode} ${r.chemin}${r.query.isEmpty ? '' : ' ${r.query}'}';
      vues[k] = (vues[k] ?? 0) + 1;
    }
    final doubles = {for (final e in vues.entries) if (e.value > 1) e.key.split(' ').take(2).join(' '): e.value};
    // Gardés exprès (test/README.md, ANO-09) : GET /officine = données de l'officine (connexion) + test « serveur
    // joignable » de l'accueil (état à l'instant de l'affichage) ; GET /modereglement/all = modes avec QR pour la
    // session + copie hors ligne du catalogue (autre usage, autre moment, autre client HTTP).
    expect(doubles, {'GET /prestige/api/v1/officine': 2, 'GET /prestige/api/v1/modereglement/all': 2},
        reason: 'lectures en double à la connexion : $doubles');
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });
}

/// Requêtes de la connexion jusqu'à l'accueil chargé (4.2.0 : 26 dont 5 lectures en double ; 4.3.0 : 24 — ANO-09
/// traitée : 3 doubles supprimés, 2 gardés exprès ; + GET /posos/droits ; 4.5.1 : 25 — + GET /user/droits, droits de
/// vente lus à chaque connexion, demande du serveur du 19/10/2026 : sécurité des ventes ; 4.9.0 : 26 — + GET
/// /app-params/value/KEY_VENTE_LECTURE_GS1, réglage de lecture GS1 à la vente, lu comme le web, en parallèle des droits).
const plafondConnexion = 26;
