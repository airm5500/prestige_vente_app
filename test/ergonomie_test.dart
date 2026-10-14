// Ergonomie et cohérence d'affichage des écrans principaux (application entière, faux serveur Prestige en mémoire).
//
// Pour chaque écran × taille (Sunmi 720×1440 densité 2, Sunmi 1080×1920 densité 2,625, téléphone 360×640 dp,
// téléphone 1080×2400 densité 3 (360×800 dp), tablette 1920×1200 densité 1,5) × échelle de texte (1,0 et 1,3) :
//   (4.0.1 : réglage « Taille de l'écran » en Automatique, comme sur un appareil neuf → sur les petits écrans — les
//   deux Sunmi et 360×640 dp — Compact est appliqué d'office, l'interface voit 400 dp de large ; les cibles tactiles
//   y sont mesurées à 48 dp de l'interface = 43,2 dp réels. Écrans aux trois tailles : ergonomie_taille_ecran_test.)
//   - aucun débordement ni exception de rendu ;
//   - cibles tactiles ≥ 48 dp de l'interface (androidTapTargetGuideline à la taille normale) ;
//   - contraste des textes (textContrastGuideline) ;
//   - en-têtes / barres aux couleurs de la charte (pas de lavande Material par défaut) ;
//   - écrans de saisie (connexion, vente, quantités réserve, mesures fiche client) : champ visible au-dessus du
//     clavier (viewInsets simulés).
// Pas de captures de référence (goldens) : uniquement des règles mesurables.
// Anomalies connues : sautées UNIQUEMENT sur la configuration touchée, avec leur identifiant (test/README.md).
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/connexion/connexion_screen.dart';

import 'outils/app_e2e.dart';
import 'outils/ecrans_ergonomie.dart';
import 'outils/ergonomie.dart';

void main() {
  for (final taille in TailleEcran.toutes) {
    for (final echelle in const [1.0, 1.3]) {
      group('$taille, texte ×$echelle', () {
        for (final e in ecransErgonomie) {
          final controles = [for (final c in Controle.values) if (c != Controle.clavier || e.champ != null) c];
          final sautes = <Controle, String>{};
          for (final c in controles) {
            final a = anomalieConnue(e.id, c, taille, echelle);
            if (a != null) sautes[c] = a;
          }
          // Anomalie connue : contrôle sauté sur cette configuration seulement, avec son identifiant.
          sautes.forEach((c, a) => testWidgets('${e.nom} — ${c.libelle} — sauté : $a', skip: true, (t) async {}));
          testWidgets(e.nom, (t) async {
            taille.appliquer(t);
            t.platformDispatcher.textScaleFactorTestValue = echelle;
            addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
            final app = AppE2E()..serveur.activerModules();
            await app.preparer(prefs: {'hiddenMenuIds': <String>[], if (e.presentation != null) 'presentation_listes_v1': e.presentation!.name});
            await app.lancer(t);
            if (e.avantConnexion) {
              expect(await app.attendreQue(t, find.byType(ConnexionScreen)), isTrue);
            } else {
              expect(await app.seConnecter(t, login: DonneesFictives.admin, motDePasse: DonneesFictives.motDePasseAdmin), isTrue);
              await app.attendre(t);
              await e.ouvrir?.call(t, app);
            }
            await verifierEcran(t, app, e, sautes: sautes.keys.toSet());
            await app.fermer(t);
          });
        }
      });
    }
  }
}
