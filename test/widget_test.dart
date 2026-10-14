// Démarrage de l'application (remplace l'exemple « compteur » de Flutter, sans rapport avec Prestige Mobile) :
// l'application entière (MyApp) démarre sur l'écran de lancement, vérifie la licence auprès du serveur puis
// ouvre la connexion ; écran d'origine (interface d'origine) également. Faux serveur Prestige en mémoire.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/connexion/connexion_screen.dart';
import 'package:prestige_vente_app/connexion/lancement_screen.dart';
import 'package:prestige_vente_app/screens/auth/login_screen.dart';
import 'package:prestige_vente_app/screens/splash_screen.dart';

import 'outils/app_e2e.dart';

void main() {
  testWidgets('démarrage : lancement « Prestige Mobile », licence vérifiée, puis écran de connexion', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final app = AppE2E();
    await app.preparer();
    await app.lancer(t);
    expect(find.byType(LancementScreen), findsOneWidget);
    expect(find.text('Prestige Mobile'), findsWidgets);
    expect(await app.attendreQue(t, find.byType(ConnexionScreen)), isTrue);
    expect(app.serveur.recuesSur('/licence/find'), hasLength(1), reason: 'licence vérifiée une fois au lancement');
    expect(find.byKey(const Key('connexion_login')), findsOneWidget);
    expect(find.byKey(const Key('connexion_mdp')), findsOneWidget);
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  // ANO-08 (corrigée en 4.0.2) : avec l'interface d'origine, la 1re vérification de la licence partait vers
  // http://localhost:8080 (ApiService créé avant la lecture des réglages, recréé seulement à l'image suivante).
  // Contrôle de l'adresse du tout premier appel : non_regression_test (« ANO-08 »).
  testWidgets('démarrage avec l\'interface d\'origine : écran d\'origine puis connexion d\'origine (ANO-08 corrigée)', (t) async {
    TailleEcran.telephone.appliquer(t);
    final app = AppE2E();
    await app.preparer(interfaceNouvelle: false);
    await app.lancer(t);
    expect(find.byType(AncienSplashScreen), findsOneWidget);
    expect(find.text('Démarrage...'), findsOneWidget);
    expect(await app.attendreQue(t, find.byType(AncienLoginScreen)), isTrue);
    expect(app.serveur.recuesSur('/licence/find'), hasLength(1), reason: 'licence vérifiée une fois, sur le serveur configuré');
    expect(find.text('Serveur injoignable'), findsNothing);
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });
}
