// PERFORMANCE — 5.2.0 : présentations Metro de l'accueil, données fictives.
//  - construction du corps Metro (mesure des libellés, placement de la mosaïque / des bandes, 26 tuiles) : meilleur
//    de 3, terminal (400 dp) et tablette paysage (1 280 dp), texte ×1,3 ;
//  - application entière : connexion → accueil Metro (même seuil que A / B / C), pire image en parcourant la page,
//    et aucune requête de plus que l'accueil actuel (le choix est local).
// Seuils : test/outils/performance.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/accueil/accueil_screen.dart';
import 'package:prestige_vente_app/connexion/connexion_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import '../outils/accueil_metro_fictif.dart';
import '../outils/app_e2e.dart';
import '../outils/performance.dart';
import 'demarrage_test.dart' show jusqua, plafondConnexion;

void main() {
  for (final p in [AccueilPresentation.metroMosaique, AccueilPresentation.metroBandes]) {
    for (final largeur in [400.0, 1280.0]) {
      testWidgets('${p.label} — construction du corps ($largeur dp, texte ×1,3), meilleur de 3', (t) async {
        final ms = await meilleurDe(3, () async {
          await t.pumpWidget(const SizedBox());
          final sw = Stopwatch()..start();
          await monterMetro(t, p, largeur: largeur, hauteur: 2400, texte: 1.3);
          return sw.elapsedMicroseconds / 1000;
        });
        mesurer('Accueil ${p.label} — construction du corps ($largeur dp)', ms, seuil: Seuils.constructionMetroMs, unite: 'ms');
        expect(t.takeException(), isNull);
      });
    }
  }

  for (final p in AccueilPresentation.values) {
    testWidgets('connexion → accueil ${p.label} : temps, pire image de la page, requêtes', (t) async {
      TailleEcran.sunmiV2s.appliquer(t);
      final app = AppE2E();
      await app.preparer(prefs: {'hiddenMenuIds': <String>[], PresentationPrefs.cleAccueil: p.name});
      await app.lancer(t);
      await jusqua(t, find.byType(ConnexionScreen));
      await app.attendre(t, const Duration(seconds: 1));
      await t.enterText(find.byKey(const Key('connexion_login')), DonneesFictives.login);
      await t.enterText(find.byKey(const Key('connexion_mdp')), DonneesFictives.motDePasse);
      await t.ensureVisible(find.byKey(const Key('se_connecter')));
      final avant = app.serveur.recues.length;
      await t.tap(find.byKey(const Key('se_connecter')));
      final ms = await jusqua(t, find.byType(AccueilScreen));
      await app.attendre(t, const Duration(seconds: 5));
      final rs = app.serveur.recues.sublist(avant);
      mesurer('Connexion → accueil ${p.label}', ms, seuil: Seuils.accueilMs, unite: 'ms');
      final liste = find.byType(Scrollable).first;
      await remonter(t, liste);
      await defilerJusquEnBas(t, liste, ChronoImages(), pas: 80);
      await remonter(t, liste);
      final chrono = ChronoImages();
      await defilerJusquEnBas(t, liste, chrono, pas: 80);
      mesurer('Accueil ${p.label} — pire image en parcourant la page (2e passage)', chrono.max, seuil: Seuils.imageAccueilMs, unite: 'ms', detail: chrono.resume);
      // Choix enregistré sur l'appareil : mêmes requêtes que l'accueil actuel (plafond de la connexion).
      mesurer('Connexion + accueil ${p.label} — requêtes', rs.length, seuil: plafondConnexion, unite: 'requêtes', detail: detailRequetes(rs));
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });
  }
}
