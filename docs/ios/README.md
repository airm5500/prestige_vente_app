# Prestige Mobile sur iPhone et iPad (TestFlight)

Depuis la version **4.5.0**, Prestige Mobile se construit aussi pour iPhone et iPad. La diffusion se fait par
**TestFlight** (l'application TestFlight d'Apple installe les versions de test sur les appareils invités).

- Construction **sans signature** à chaque envoi sur GitHub : job `ios-build` du workflow « Build iOS
  (TestFlight) » (`.github/workflows/build-ios.yml`). Il prouve que l'application se compile pour iOS.
- Envoi **automatique à TestFlight** : job `testflight` du même workflow. Il ne démarre **que lorsque les quatre
  secrets ci-dessous existent** dans GitHub ; tant qu'ils manquent, il est simplement sauté (aucune erreur).

Personne n'a besoin d'un Mac : tout se fait sur les machines macOS de GitHub.

---

## 1. Ce qui marche sur iPhone / iPad, ce qui est masqué

| Fonction | iPhone / iPad |
|---|---|
| Connexion, accueil, ventes, caisse, stock, réception, péremption, ordonnances, fiche client, réserve, analyses | ✅ comme sur Android (tout passe par le serveur Prestige) |
| Appareil photo : scan des codes-barres / DataMatrix, photo des ordonnances et étiquettes, Photos produits | ✅ |
| Lecture du texte des étiquettes et ordonnances (ML Kit) | ✅ |
| Pointage présence : « Mon pointage », terminal par badge (clavier, caméra), photo de contrôle (caméra avant) | ✅ |
| Lecteur de codes-barres Bluetooth en mode clavier | ✅ (comme la douchette Sunmi) |
| Documents PDF | ✅ impression AirPrint ou partage |
| Imprimante de tickets Sunmi | ➖ absente : les tickets s'affichent à l'écran (Réglages › Impression le dit) |
| Lecteur d'empreinte Sunmi | ➖ masqué (« indisponible sur iPhone / iPad : utilisez le badge ») |
| NFC des badges | ➖ masqué |
| Borne libre-service (épinglage de l'écran, ticket Sunmi) | ➖ menu et rubrique masqués |
| Pointage local (empreinte / PIN du terminal) | ➖ menu et réglages masqués |

Aucun écran n'appelle une fonction absente : la couche `lib/plateforme/capacites.dart` répond « indisponible »
sans appel natif (tests : `test/ios/`).

**Serveur en HTTP sur le réseau de la pharmacie** : l'adresse du serveur est saisie dans les réglages (souvent une
adresse IP privée, en HTTP). Le client de l'application (Dio, sockets de Dart) n'est pas soumis à l'App Transport
Security d'iOS ; l'Info.plist déclare tout de même `NSAllowsLocalNetworking` et **n'autorise pas** les connexions
HTTP arbitraires (`NSAllowsArbitraryLoads` absent). Au premier lancement, iOS demande l'autorisation « Réseau
local » : il faut **l'accepter** (sinon : Réglages iOS › Confidentialité › Réseau local › Prestige Mobile). Pour un
accès par Internet, utiliser l'adresse **HTTPS** du serveur (réglage disponible depuis la 4.1.0).

**iOS 15.5 minimum** (exigé par la lecture de texte ML Kit).

---

## 2. Ce que le pharmacien doit fournir (une seule fois)

| Valeur | Où la trouver | Où la mettre |
|---|---|---|
| **Bundle ID** de l'application | App Store Connect › Apps › (l'app) › Informations sur l'app › Identifiant de bundle | Fichier `ios/Flutter/Prestige.xcconfig` (`PRESTIGE_BUNDLE_ID`), à transmettre à l'équipe ; valeur proposée : `com.dici.prestigeventeapp` |
| **Team ID** (10 caractères) | [developer.apple.com/account](https://developer.apple.com/account) › Abonnement (Membership details) › Team ID | Secret GitHub `APPLE_TEAM_ID` |
| **Key ID** de la clé API | App Store Connect › Utilisateurs et accès › Intégrations › Clés API de l'App Store Connect (colonne « ID de clé ») | Secret `APP_STORE_CONNECT_KEY_ID` |
| **Issuer ID** | Même page, en haut : « ID de l'émetteur » | Secret `APP_STORE_CONNECT_ISSUER_ID` |
| **Clé privée** (.p8) | Fichier `AuthKey_XXXXXXXXXX.p8` téléchargé à la création de la clé (une seule fois possible) | Secret `APP_STORE_CONNECT_PRIVATE_KEY` : **tout le contenu** du fichier, lignes `-----BEGIN PRIVATE KEY-----` et `-----END PRIVATE KEY-----` comprises |

La clé API doit avoir l'accès **Admin** : c'est ce qui permet à la CI de créer seule le certificat de distribution
et le profil (signature automatique). Ne jamais envoyer la clé .p8 par message ou e-mail : elle se dépose
uniquement dans GitHub (étape 3).

---

## 3. Déposer les secrets dans GitHub

1. Ouvrir le dépôt `airm5500/prestige_vente_app` sur github.com.
2. **Settings** › **Secrets and variables** › **Actions** › onglet **Secrets** › **New repository secret**.
3. Créer les quatre secrets, un par un (nom exact, puis valeur) :
   - `APP_STORE_CONNECT_KEY_ID`
   - `APP_STORE_CONNECT_ISSUER_ID`
   - `APP_STORE_CONNECT_PRIVATE_KEY` (ouvrir le .p8 avec un éditeur de texte, tout copier, tout coller)
   - `APPLE_TEAM_ID`
4. Facultatif, onglet **Variables** › **New repository variable** :
   - `TESTFLIGHT_GROUP` : nom d'un groupe de testeurs (ex. « Pharmacie ») pour y ajouter chaque nouvelle version ;
   - `ASC_APP_ID` : identifiant Apple de l'app (App Store Connect › l'app › Informations sur l'app › « Identifiant
     Apple », un nombre) ; sans lui, la CI retrouve l'app par son bundle ID.

GitHub masque les secrets dans les journaux ; la CI écrit la clé dans un fichier temporaire (droits 600), ne
l'affiche jamais et l'efface à la fin.

---

## 4. Créer l'application dans App Store Connect

À faire **avant** le premier envoi (sinon le job TestFlight s'arrête avec « aucune app … dans App Store Connect »).

1. [developer.apple.com/account/resources/identifiers](https://developer.apple.com/account/resources/identifiers)
   › **+** › **App IDs** › **App** › description « Prestige Mobile », **Bundle ID explicite** = la valeur retenue
   (par défaut `com.dici.prestigeventeapp`) › aucune capacité particulière › **Register**.
2. [appstoreconnect.apple.com](https://appstoreconnect.apple.com) › **Apps** › **+** › **Nouvelle app** :
   plateforme **iOS**, nom « Prestige Mobile » (ou un nom disponible), langue principale **Français**, bundle ID
   choisi dans la liste, SKU libre (ex. `prestige-mobile`), accès complet › **Créer**.

---

## 5. Ajouter les testeurs TestFlight

- **Testeurs internes** (membres de l'équipe App Store Connect, jusqu'à 100) : App Store Connect › l'app ›
  **TestFlight** › **Testeurs internes** › **+** › choisir les personnes. Ils reçoivent chaque version sans examen
  d'Apple.
- **Testeurs externes** (n'importe quelle adresse e-mail) : TestFlight › **+** à côté de « Testeurs externes » ›
  créer un groupe (ex. « Pharmacie ») › ajouter les e-mails. La **première** version envoyée à un groupe externe
  passe par l'examen bêta d'Apple (souvent moins d'un jour) : renseigner « Informations sur le test » (contact,
  et un compte de démonstration ou une note expliquant que l'app se connecte au serveur de la pharmacie).

Le nom du groupe peut être mis dans la variable `TESTFLIGHT_GROUP` (étape 3) pour que chaque version y soit
ajoutée automatiquement.

---

## 6. Installer sur l'iPhone / l'iPad

1. Installer **TestFlight** depuis l'App Store.
2. Ouvrir l'invitation (e-mail « Vous êtes invité à tester Prestige Mobile ») sur l'appareil, ou le lien public si
   un lien a été créé, puis **Accepter** › **Installer**.
3. Au premier lancement : accepter **Réseau local** (indispensable pour joindre le serveur) et **Appareil photo**.
4. Réglages de l'application : saisir l'adresse du serveur comme sur Android.

Chaque nouvelle version envoyée par la CI apparaît dans TestFlight (mise à jour automatique possible).

---

## 7. Comment la CI construit et envoie

- **Version** : `pubspec.yaml` (ex. `4.5.0+21`). Sur TestFlight, le numéro de build devient `21.<numéro du run>`
  (ex. `21.57`) pour que chaque envoi soit unique ; le numéro de version affiché reste `4.5.0`.
- **Signature** : `xcodebuild archive … -allowProvisioningUpdates -authenticationKeyPath … -authenticationKeyID …
  -authenticationKeyIssuerID …` (signature automatique gérée par Apple avec la clé API), puis export de l'IPA
  (`ios/ExportOptions.plist`, méthode `app-store-connect`). Pas de fastlane, pas de certificat à stocker.
- **Envoi** : outil open source **asc** ([rorkai/App-Store-Connect-CLI](https://github.com/rorkai/App-Store-Connect-CLI),
  licence MIT), version **5.14.3** figée, binaire vérifié par la somme de contrôle publiée avec la version :
  - `asc auth login --bypass-keychain --name prestige-ci --key-id … --issuer-id … --private-key …`
  - `asc builds upload --app <ID> --ipa <fichier> --wait`
  - si `TESTFLIGHT_GROUP` existe : `asc builds add-groups … --group <groupe>` et les notes « À tester »
    (`asc builds test-notes create --build-id … --locale fr-FR --whats-new …`, tirées de la note de version) —
    étape facultative, sans effet sur la réussite de l'envoi.
  - télémétrie de l'outil désactivée (`ASC_TELEMETRY_DISABLED=1`, `DO_NOT_TRACK=1`).
- Les jobs Android (`build-apk.yml`) ne changent pas.

---

## 8. Vérifier sur un appareil (première version)

Ce que les tests automatiques ne peuvent pas montrer : à essayer sur un vrai iPhone / iPad.

- Connexion au serveur de la pharmacie en HTTP (adresse IP locale), après l'autorisation « Réseau local ».
- Scan d'un code-barres et d'un DataMatrix ; photo d'étiquette (lecture lot / date) ; Photos produits.
- Pointage par badge avec la photo de contrôle (caméra avant).
- Un ticket de vente s'affiche à l'écran (pas d'imprimante Sunmi).
