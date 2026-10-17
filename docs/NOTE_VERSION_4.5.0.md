# Prestige Mobile 4.5.0+21 — iPhone et iPad (TestFlight)

Guide pas à pas pour le pharmacien (secrets, App Store Connect, testeurs, installation) : `docs/ios/README.md`.

## Ce qui change

| Sujet | Ce qui change |
|---|---|
| Nouvelle plateforme | Prestige Mobile se construit pour **iPhone et iPad** (iOS 15.5 minimum, exigé par ML Kit) : portrait et paysage, iPad en plein écran avec les 4 orientations. Nom affiché « Prestige Mobile », textes d'autorisation en français, icône (chariot, fond blanc opaque) et écran de lancement. |
| Couche de capacités | `lib/plateforme/capacites.dart` : ce que la plateforme sait faire. Sur iOS, les fonctions propres aux terminaux Sunmi sont **masquées proprement** (aucun écran cassé, aucun appel natif) : imprimante Sunmi (les tickets s'affichent à l'écran, Réglages › Impression le dit, bouton « APERÇU D'UN TICKET »), lecteur d'empreinte (message « utilisez le badge »), NFC, borne libre-service (menu et rubrique des réglages), pointage local (menu « Empreinte » et section des réglages Équipe). |
| Fonctions disponibles sur iOS | Connexion, ventes, caisse, stock, réception, péremption, ordonnances, fiche client, réserve, analyses, scan caméra (codes-barres, DataMatrix, badges), lecture du texte (ML Kit), Photos produits, « Mon pointage », terminal de pointage par badge avec photo de contrôle, PDF (AirPrint / partage), stockage sécurisé (Trousseau). |
| Serveur en HTTP local | `NSAllowsLocalNetworking` (pas de `NSAllowsArbitraryLoads` : le client HTTP de Dart n'est pas soumis à l'ATS, l'accès HTTP au serveur de la pharmacie fonctionne sans ouvrir tout le HTTP) ; autorisation « Réseau local » demandée au premier lancement (`NSLocalNetworkUsageDescription`). |
| Bundle ID | Paramètre `PRESTIGE_BUNDLE_ID` de `ios/Flutter/Prestige.xcconfig`, valeur `com.dici.prestigeventeapp` **en attente de confirmation** du pharmacien (si l'app existe déjà dans App Store Connect, reprendre son bundle ID). |
| CI | Nouveau workflow « Build iOS (TestFlight) » (`.github/workflows/build-ios.yml`, macOS) : tests `test/ios` sur macOS, `flutter build ios --release --no-codesign`, contrôle de l'Info.plist produit (version = pubspec, bundle ID, autorisations, ATS). Job **TestFlight** prêt (signature automatique par la clé API, `xcodebuild archive` / export, envoi par `asc` 5.14.3 à somme de contrôle vérifiée) : **désactivé tant que les 4 secrets n'existent pas** (`APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_PRIVATE_KEY`, `APPLE_TEAM_ID`). |
| Android | **Aucun changement de comportement** : sur Android toutes les capacités restent actives (mêmes menus, mêmes canaux natifs). Le paquet `camera_avfoundation` (implémentation iOS de la caméra) est ajouté, sans effet sur l'APK. |

## Tests

Nouveaux tests `test/ios/` (dans la liste de la CI et `test/categories.json`) :

- `capacites_ios_test` (unitaires) : déduction de la plateforme, empreinte / NFC / kiosque / imprimante sans
  aucun appel natif sur iOS, appels inchangés sur Android, menus masqués sur iOS et présents sur Android ;
- `projet_ios_test` (non-régression) : Info.plist (clés et textes français, ATS, orientations), bundle ID,
  cible 15.5, Podfile, icônes opaques, workflow sans secret en clair ;
- `ergonomie_ios_test` (ergonomie) : tous les écrans de la suite d'ergonomie en iPhone 375×667 et 430×932, iPad
  768×1024, 1024×1366 portrait et paysage ; fonctions absentes masquées dans l'accueil et les réglages ;
- `reseau_ios_test` (réseau) : requêtes HTTP vers un serveur local sous iOS, coupure et reprise ;
- `performance_ios_test` (performance) : démarrage et connexion → accueil sur iPad Pro et iPhone SE.

## À tester

- Accepter « Réseau local » au premier lancement, puis se connecter au serveur de la pharmacie (adresse HTTP locale).
- Scanner un code-barres et un DataMatrix (recherche, péremption, réception).
- Photographier une étiquette (lecture lot / date) et ajouter une photo dans « Photos produits ».
- Pointer par badge sur le terminal avec la photo de contrôle (caméra avant).
- Faire une vente : le ticket s'affiche à l'écran (pas d'imprimante Sunmi).
- Vérifier l'affichage sur iPad en portrait et en paysage.

## À vérifier sur appareil

La capture guidée et la photo de contrôle utilisent l'image de la caméra iOS (`camera_avfoundation`) : comportement
couvert par les tests sur Android et à confirmer sur un vrai iPhone / iPad lors du premier envoi TestFlight.
