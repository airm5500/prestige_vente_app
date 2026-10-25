# PrestigePOS — borne de vente libre-service

PrestigePOS est une **application Android distincte** de Prestige Mobile, installable à côté d'elle sur le même
appareil (identifiant `com.dici.prestigepos`, nom « PrestigePOS », icône chariot + coche verte). Elle ne contient
que la **borne libre-service** : le client cherche ses produits (recherche, catégories en images, produits mis en
avant), compose son panier, les prix et le stock sont revérifiés sur le serveur, une **prévente** est créée et un
**ticket avec QR** sort sur l'imprimante : le client paie **à la caisse** (espèces). Le mobile money est proposé en
plus si le serveur Prestige l'annonce (module paiements mobile).

PrestigePOS se connecte au **même serveur Prestige** que Prestige Mobile : mêmes routes, même session
(cookie JSESSIONID de l'utilisateur borne).

Captures : [`captures/`](captures/) (assistant, administration, imprimante Bluetooth, borne en tablette paysage,
borne verticale, panier, ticket, imprimante en panne, terminal Sunmi).

## Architecture : un projet, deux applications (saveurs Android)

| | Prestige Mobile | PrestigePOS |
|---|---|---|
| Saveur Android | `mobile` (par défaut) | `pos` |
| Point d'entrée | `lib/main.dart` (inchangé) | `lib/main_pos.dart` |
| applicationId | `com.dici.prestige_vente_app` | `com.dici.prestigepos` |
| Version | `pubspec.yaml` (4.9.0+31) | `android/app/prestigepos-version.properties` (1.7.0+17) |
| Nom, icône, activité | `android/app/src/main` | `android/app/src/pos` (remplace nom, icône, activité) |
| Permissions en plus | — | Bluetooth (SPP), USB (OTG), démarrage de l'appareil (1.1.0) : `src/pos/AndroidManifest.xml` |
| APK de la CI | artefact `prestige-vente-apk` (`app-release.apk`) | artefact `prestigepos-apk` (`PrestigePOS-1.7.0.apk`) |

**Code partagé** : la borne (`lib/borne/`) — recherche, catégories, fiche, panier, vérification prix / stock,
création de la prévente, ticket, kiosque (épinglage), sortie par code administrateur (`lib/widgets/sortie_kiosque.dart`),
« Tester la borne », réglages de la borne —, le client du serveur (`lib/api/`), la session, le code administrateur,
la taille d'écran, les paiements mobile money. **Une correction faite dans la borne profite aux deux applications.**

Propre à PrestigePOS (`lib/prestigepos/`) : démarrage, assistant de premier lancement, administration, imprimantes
de ticket ESC/POS (`lib/prestigepos/impression/`) et le pont Android Bluetooth / USB
(`android/app/src/pos/kotlin/com/dici/prestigepos/`), absent de Prestige Mobile.

`flutter build apk --release` **sans** `--flavor` construit toujours Prestige Mobile (`pubspec.yaml` :
`flutter › default-flavor: mobile`). La CI vérifie que l'APK de Prestige Mobile garde le même applicationId, le même
nom, la même version et **exactement les mêmes permissions** que la version 4.9.0+31 avant sa fusion dans PrestigePOS
(job `prestige-mobile-identique`, référence : commit `5772d0e` de `pres-/tender-thompson-ang0ls`).

## Ouvrir dans Android Studio

1. Récupérer la branche : `git fetch origin prestigepos && git checkout prestigepos`.
2. Ouvrir le dossier du projet dans Android Studio (extensions Flutter et Dart installées), puis
   `flutter pub get` (ou « Pub get » dans le bandeau d'Android Studio).
3. En haut, dans la liste des configurations d'exécution, choisir :
   - **« PrestigePOS »** : saveur `pos`, point d'entrée `lib/main_pos.dart` ;
   - **« Prestige Mobile »** : saveur `mobile`, point d'entrée `lib/main.dart`.

   Ces deux configurations sont versionnées dans `.run/` (`PrestigePOS.run.xml`, `Prestige Mobile.run.xml`) :
   Android Studio les affiche automatiquement. Ne pas utiliser une configuration « main.dart » sans saveur pour
   PrestigePOS (elle lancerait Prestige Mobile).
4. Brancher la tablette (débogage USB activé) et cliquer sur ▶. Les deux applications peuvent être installées
   ensemble sur le même appareil.

En ligne de commande :

```bash
flutter run --flavor pos -t lib/main_pos.dart        # PrestigePOS
flutter run                                          # Prestige Mobile (saveur mobile par défaut)
```

## Construire l'APK

```bash
flutter build apk --release --flavor pos -t lib/main_pos.dart
```

APK produit : `build/app/outputs/flutter-apk/app-pos-release.apk` (même fichier, nommé
`PrestigePOS-release-1.7.0.apk`, dans `build/app/outputs/apk/pos/release/`). La CI le publie dans l'artefact
**`prestigepos-apk`** à chaque envoi sur la branche `prestigepos`.

Version : modifier `android/app/prestigepos-version.properties` (`nomVersion`, et `codeVersion` **toujours
augmenté** pour une mise à jour). Le `pubspec.yaml` reste celui de Prestige Mobile.

## Installer

- Copier l'APK sur l'appareil et l'ouvrir (autoriser « Installer des applications inconnues »), ou
  `adb install -r PrestigePOS-1.1.0.apk`.
- Android 7 minimum ; testé pour tablettes Android 11+, terminaux Sunmi (V2s, V3) et bornes verticales.
- Prestige Mobile n'est pas touché : les deux applications ont chacune leurs réglages.

## Configurer (premier lancement)

Au premier lancement, PrestigePOS affiche « Bienvenue » ; **« Configurer PrestigePOS »** demande le **code
administrateur** de l'appareil (code par défaut `1234` à changer immédiatement, comme dans Prestige Mobile). Puis :

1. **Serveur** : adresse du serveur Prestige (IP `192.168.1.50` ou nom ; `https://…` pour une connexion chiffrée),
   port (8080) et application (`prestige`). L'adresse est vérifiée avant de continuer.
2. **Utilisateur borne** : créer dans Prestige un **compte dédié** à la borne, avec **uniquement le droit de créer
   des préventes** (ni encaissement, ni administration, ni retours). Saisir son login et son mot de passe
   (chiffré dans le stockage sécurisé d'Android). **« Tester la borne »** vérifie la connexion et la recherche de
   produits et donne la cause précise d'un échec.
3. **Présentation** : Vitrine (tablette, borne), Liste rapide (terminal Sunmi), Guidée (gros boutons, étapes) ;
   taille de l'écran (Automatique / Compact / Très compact) ; mobile money (proposé seulement si le serveur
   l'annonce).
4. **Imprimante** (voir ci-dessous) puis « Test d'impression ».
5. **Démarrer la borne** : plein écran, écran épinglé (Android peut demander « Épingler l'application ? » :
   accepter). Ensuite, PrestigePOS ouvre directement la borne à chaque lancement.

Catégories, produits mis en avant, plafonds de quantité, ticket discret : Administration › **Réglages de la borne**.

### Imprimante de ticket

Papier **58 mm** (32 caractères) ou **80 mm** (48 caractères), réglable.

- **Automatique / Sunmi intégrée** : sur un terminal Sunmi, l'imprimante intégrée est détectée, rien à configurer.
- **Bluetooth** : allumer l'imprimante, « **Rechercher** » (imprimantes appairées puis découverte d'environ 12 s,
  imprimantes en tête), toucher l'imprimante, « **Ajouter** » : elle est choisie et mémorisée (jusqu'à 8). Android
  demande l'autorisation « **Appareils à proximité** » (Android 12+) ou la **localisation** (Android 11 et moins,
  nécessaire à la découverte Bluetooth) : accepter.
- **USB** : brancher l'imprimante par un câble OTG, « Rechercher », la choisir ; Android demande l'accès au
  périphérique : accepter (cocher « toujours » si proposé).
- **Réseau** (Wi-Fi / Ethernet) : adresse IP de l'imprimante (lui donner une IP fixe) et port **9100**.
- **Aucune** : le ticket est affiché à l'écran (numéro, QR et référence).

Options : « QR code en image » (imprimantes qui n'impriment pas le QR natif), « Imprimer les accents » (page
PC858 ; désactivé, « é » est imprimé « e », lisible partout), « Couper le papier ».

Le ticket a le même contenu que celui de la borne de Prestige Mobile : officine, « PRE-VENTE BORNE », numéro en
grand, produits (ou nombre d'articles en ticket discret), total, QR de la référence, référence, « Présentez ce
ticket à la caisse », date. Si l'impression échoue, **la cause s'affiche en clair et le ticket reste à l'écran**
(30 s) : le client peut le photographier ou noter le numéro ; la caisse retrouve la prévente par sa référence.

## Sortir du mode kiosque

Maintenir **2 secondes** le **cadenas** en haut à droite de la borne (un anneau se remplit), confirmer
« Quitter », puis saisir le **code administrateur**. On arrive à l'**Administration** : reprendre la borne,
assistant, imprimante, réglages de la borne, tester la borne, démarrage automatique, revenir à Android (1.1.0),
fermer PrestigePOS. Sans action pendant 3 minutes,
la borne reprend toute seule.

Épinglage sans confirmation (recommandé pour une borne publique) : PrestigePOS déclare `lockTaskMode="if_whitelisted"` ;
PrestigePOS **propriétaire de l'appareil** (1.1.0, voir « Démarrage automatique » ci-dessous) ou une solution de
gestion d'appareils (MDM) qui autorise `com.dici.prestigepos` en mode tâche verrouillée l'épingle alors sans
question ni sortie possible par les boutons Android. Sans MDM, protéger
l'épinglage par le code de l'appareil (Paramètres › Sécurité › Épinglage d'écran › « Demander le code avant de
désépingler »).

## Démarrage automatique avec l'appareil (1.1.0)

But : après une **coupure de courant** ou un **redémarrage**, la borne se rouvre **toute seule**, en mode kiosque,
sans que personne touche l'écran. Réglage **désactivé par défaut**.

**Pourquoi deux étapes.** Depuis Android 10, une application n'a plus le droit d'ouvrir son écran toute seule au
démarrage (Android bloque les ouvertures « depuis l'arrière-plan »). La méthode fiable sur Android 7 à 14 et sur
les terminaux Sunmi est que PrestigePOS soit **l'application d'accueil** de l'appareil : au démarrage, c'est Android
lui-même qui l'ouvre, et la touche Accueil ramène à la borne. Le **verrouillage sans confirmation** demande en plus
que PrestigePOS soit **propriétaire de l'appareil** (facultatif, étape 3). Sur Android 9 et moins, PrestigePOS
rouvre aussi la borne par lui-même au démarrage.

### Mise en place sur la borne (pas à pas)

1. **Activer le réglage.** Sortir de la borne (cadenas 2 s, « Quitter », code administrateur) › Administration ›
   **Démarrage automatique** › activer **« Démarrer automatiquement avec l'appareil »**.
2. **Choisir PrestigePOS comme application d'accueil.** Toucher **« Choisir PrestigePOS comme accueil »** : Android
   ouvre « Application d'accueil » (selon le modèle : Paramètres › Applications › Applications par défaut ›
   Application d'accueil, ou « Écran d'accueil »). Choisir **PrestigePOS**. Si Android propose « Une seule fois /
   Toujours » (en appuyant sur la touche Accueil), toucher **« Toujours »**. De retour dans PrestigePOS, la ligne
   « PrestigePOS est l'application d'accueil » doit être cochée.
3. **(Facultatif, recommandé pour une borne publique) Verrouillage sans confirmation : propriétaire de
   l'appareil.** Sans cette étape, Android peut demander « Épingler l'application ? » à chaque démarrage (toucher
   « OK » une fois). Pour le supprimer :
   - l'appareil doit n'avoir **aucun compte** (Paramètres › Comptes : retirer le compte Google, Sunmi…) ; au besoin,
     le faire juste après une réinitialisation ;
   - activer les **options pour les développeurs** et le **débogage USB**, brancher l'appareil à un ordinateur avec
     `adb`, puis :

     ```bash
     adb shell dpm set-device-owner com.dici.prestigepos/.PosAdminReceiver
     ```

     Réponse attendue : « Success: Device owner set to package com.dici.prestigepos ». Dans PrestigePOS, la ligne
     « Propriétaire de l'appareil » est cochée ; la borne se verrouille désormais sans aucune question.
   - Les comptes peuvent être rajoutés ensuite ; désactiver le débogage USB.
4. **Vérifier** : éteindre l'appareil (ou le débrancher), le rallumer : après le démarrage d'Android (et le code
   de déverrouillage de l'écran s'il y en a un), la borne s'ouvre seule. Sans licence Prestige valide, PrestigePOS
   s'ouvre sur « Licence Prestige absente » : **la borne ne travaille pas**. Si le serveur n'est pas encore joignable
   (box qui redémarre), la borne affiche « momentanément indisponible » et reprend seule.

Conseil : ne pas mettre de code de déverrouillage de l'écran sur une borne (sinon Android attend ce code avant
d'ouvrir l'accueil) ; protéger plutôt l'appareil physiquement et par le code administrateur de PrestigePOS.

### Revenir à Android (sortie fiable)

- Administration › **« Revenir à Android »** (ou Démarrage automatique › « Revenir à Android ») : le réglage est
  désactivé, le verrouillage est arrêté, PrestigePOS **n'est plus l'application d'accueil** et l'accueil d'Android
  s'ouvre. Fonctionne même si PrestigePOS était l'accueil (« Fermer PrestigePOS » seul le rouvrirait).
- Pour remettre la borne : rouvrir PrestigePOS et réactiver le réglage (étapes 1 et 2).

### Annuler le « propriétaire de l'appareil »

- Dans PrestigePOS : Administration › Démarrage automatique › **« Retirer le propriétaire de l'appareil »**
  (visible seulement si PrestigePOS l'est) : PrestigePOS redevient une application ordinaire (désinstallable).
- En dernier recours (PrestigePOS inutilisable) : **réinitialisation d'usine** de l'appareil (Paramètres › Système ›
  Réinitialiser) ; la borne sera à reconfigurer. Un propriétaire de l'appareil ne peut pas être désinstallé
  directement.

PrestigePOS ne demande **aucune** politique de l'appareil (pas d'effacement à distance, pas de mot de passe imposé) :
le statut sert seulement à verrouiller la borne sans confirmation.

## Google Play, piste « Test interne » (1.3.0)

PrestigePOS est une **deuxième application** dans la Play Console (`com.dici.prestigepos`), à côté de Prestige Mobile
(`com.dici.prestige_vente_app`) ; **mêmes secrets** GitHub pour les deux. Guide pas à pas : `docs/android/README.md`
(sections 2, 6 et 9 : deux applications ; section 11 : règles de Google Play pour le propriétaire de l'appareil, la
tâche verrouillée, HOME, le démarrage automatique, le Bluetooth et l'USB).

- Workflow `.github/workflows/play.yml`, branche `prestigepos` : version Play construite avec
  `--flavor pos -t lib/main_pos.dart` et `--android-project-arg=playStore=true` (targetSdk 36), contrôlée à chaque
  envoi ; App Bundle signé en artefact **`prestigepos-aab`** dès que la clé d'envoi est déposée ; envoi en Test
  interne quand `android/DEMANDE_PLAY` de cette branche contient la version de PrestigePOS (ex. `1.7.0+17`).
- **L'APK des bornes Sunmi ne change pas** : construit sans `playStore` (targetSdk 35) et signé comme avant avec la
  clé debug du PC. Une borne installée depuis Play n'est pas propriétaire de l'appareil (pas d'`adb`) : le
  verrouillage passe alors par l'épinglage standard d'Android. Pour les bornes, garder l'APK du PC.

## Dépannage

| Problème | Que faire |
|---|---|
| Imprimante Bluetooth non trouvée | Allumée, chargée, à moins de 10 m, pas connectée à un autre téléphone ; l'appairer dans les réglages Bluetooth d'Android (code souvent `0000` ou `1234`), puis « Rechercher » : elle apparaît dans les appareils appairés. Sur Android 11 et moins, activer la **localisation**. |
| « Autorisation Bluetooth refusée » | Paramètres Android › Applications › PrestigePOS › Autorisations › **Appareils à proximité** (ou Localisation) : Autoriser. |
| « Le Bluetooth est désactivé » | Bouton « Activer le Bluetooth », ou depuis les réglages rapides. |
| Ticket sans QR ou caractères étranges | Activer « QR code en image » ; désactiver « Imprimer les accents ». |
| Ticket coupé / trop large | Vérifier la largeur du papier (58 / 80 mm) puis « Test d'impression ». |
| Imprimante réseau injoignable | Même réseau Wi-Fi, IP correcte (imprimer la page de configuration de l'imprimante), port 9100. |
| Borne « momentanément indisponible » | Serveur injoignable ou utilisateur borne refusé : la cause est affichée sous le message ; la borne reprend seule dès que le serveur répond. |
| Borne sans produits | Administration › **Tester la borne** : connexion, droits et recherche vérifiés étape par étape (mot de passe, compte désactivé, mots-clés des catégories, emplacement de stock de l'utilisateur borne). |
| « Licence Prestige absente » | Enregistrer la licence avec Prestige Mobile (licence du serveur), puis « Réessayer ». |

## Tests

```bash
flutter test test/prestigepos        # tests PrestigePOS (job CI « prestigepos »)
```

- `escpos_test.dart` : ticket type ESC/POS **octet par octet** en 58 et 80 mm (références commentées dans
  `test/prestigepos/references/`), QR natif / image, code-barres, accents, découpage des noms ;
- `imprimante_test.dart` : réglages de l'imprimante, choix de l'imprimante, messages d'échec, imprimante réseau
  réelle (socket TCP local) ;
- `paiement_test.dart` : « Payer en caisse » toujours, mobile money seulement si le serveur l'annonce ;
- `pos_integration_test.dart` : parcours borne complet contre le faux serveur en HTTP réel, ticket sur imprimante
  réseau ;
- `pos_e2e_test.dart` : application entière (premier lancement → assistant → borne → prévente → ticket ; sortie
  par code ; serveur injoignable ; session expirée ; imprimante en panne ; autorisation refusée ; licence absente) ;
- `pos_ergonomie_test.dart` : tablette paysage / portrait, borne verticale 1080 × 1920, Sunmi V2s / V3, texte ×1,0
  et ×1,3 : rendu, cibles ≥ 48 dp, contraste ;
- `pos_performance_test.dart` : démarrage, vitrine de 500 produits, recherche tapée vite ;
- `pos_reseau_test.dart` : serveur lent (2–8 s), coupure puis reprise ;
- `pos_droits_test.dart` (1.3.1) : droits de l'utilisateur borne (lus avec son en-tête), mobile money masqué sans droit
  de clôture, 403 pendant le paiement mobile → message et ticket de prévente, 409 branché ;
- `pos_play_test.dart` (1.3.0) : saveur pos dans le workflow Google Play, targetSdk 36 pour la version Play seulement
  (APK des bornes sans `playStore`), règles Play (administrateur sans politique, HOME désactivé par défaut, tâche
  verrouillée, démarrage, Bluetooth, USB) ;
- `pos_version_test.dart` : saveurs, version 1.0.0+1, manifestes, icônes, configurations Android Studio, CI.

Captures : `APERCUS=1 flutter test test/outils/captures_prestigepos_test.dart --update-goldens`.
