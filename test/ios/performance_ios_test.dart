// 4.5.0 — Performance sur iPhone / iPad (plateforme iOS simulée, application entière, faux serveur) : lancement
// → écran de connexion et connexion → accueil sur iPad Pro (le plus grand écran : le plus d'éléments à dessiner) et
// iPhone SE. Mêmes seuils que sur Android (test/outils/performance.dart) : iOS ne doit rien coûter de plus.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/accueil/accueil_screen.dart';
import 'package:prestige_vente_app/connexion/connexion_screen.dart';

import '../outils/app_e2e.dart';
import '../outils/performance.dart';
import '../performance/demarrage_test.dart' show jusqua;
import 'ergonomie_ios_test.dart' show ipadPro, iphoneSe;

void main() {
  for (final taille in [ipadPro, iphoneSe]) {
    testWidgets('$taille (iOS) : lancement → connexion, connexion → accueil', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        taille.appliquer(t);
        final app = AppE2E();
        await app.preparer(prefs: {'hiddenMenuIds': <String>[]});
        final sw = Stopwatch()..start();
        await app.lancer(t);
        await jusqua(t, find.byType(ConnexionScreen));
        mesurer('iOS $taille : démarrage → écran de connexion', sw.elapsedMicroseconds / 1000, seuil: Seuils.demarrageMs, unite: 'ms');
        await app.attendre(t, const Duration(seconds: 2));
        await t.enterText(find.byKey(const Key('connexion_login')), DonneesFictives.login);
        await t.enterText(find.byKey(const Key('connexion_mdp')), DonneesFictives.motDePasse);
        await t.ensureVisible(find.byKey(const Key('se_connecter')));
        await t.tap(find.byKey(const Key('se_connecter')));
        final ms = await jusqua(t, find.byType(AccueilScreen));
        mesurer('iOS $taille : connexion → accueil', ms, seuil: Seuils.accueilMs, unite: 'ms');
        expect(t.takeException(), isNull);
        await app.fermer(t);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
