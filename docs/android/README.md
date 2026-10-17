# Prestige Mobile et PrestigePOS sur Google Play — piste « Test interne »

Ce guide est pour le pharmacien. La piste **Test interne** de Google Play est l'équivalent de TestFlight : jusqu'à
100 testeurs choisis par e-mail, version disponible en quelques minutes, **sans examen** de Google ni fiche publique.

Il reprend le guide commun aux **quatre** applications Prestige (Prestige Pharmacien, Prestige Mobile, PrestigePOS,
Prestige Inventaire) : mêmes étapes, mêmes noms de secrets, même fichier de demande. **Une seule clé d'envoi peut
servir aux quatre** : la créer une fois (étape 3) et déposer les **mêmes** secrets dans chaque dépôt GitHub
(`prestige_app`, `prestige_vente_app`, `prestinv`).

> **Ce dépôt (`prestige_vente_app`) contient DEUX applications** : Prestige Mobile et PrestigePOS. Il faut donc
> **deux applications dans la Play Console** (étape 2, à faire deux fois), mais **un seul jeu de secrets** dans ce
> dépôt (étapes 4 et 8) : ils servent aux deux.

> **Sécurité.** La clé d'envoi (fichier `.jks`), ses mots de passe et la clé JSON du compte de service ne doivent
> jamais être envoyés par e-mail, messagerie ou conversation : vous les déposez vous-même dans GitHub (étapes 4 et 8).

| Élément | Prestige Mobile | PrestigePOS |
|---|---|---|
| Nom du paquet (package name, ne peut plus jamais changer sur Play) | **`com.dici.prestige_vente_app`** | **`com.dici.prestigepos`** |
| Branche GitHub | `pres-/tender-thompson-ang0ls` | `prestigepos` |
| Version | `pubspec.yaml` (ex. `4.5.0+23`) | `android/app/prestigepos-version.properties` (ex. `1.3.0+9`) |
| Artefact de la CI | `prestige-mobile-aab` | `prestigepos-aab` |
| Piste | Test interne (`internal`) | Test interne (`internal`) |
| Format envoyé | App Bundle `.aab`, signé par **votre** clé d'envoi, re-signé par Google (Play App Signing) | idem |
| Android minimum / cible (version Play) | Android 5.0 (API 21) / Android 16 (API 36) | idem |

## 1. Compte Google Play Console

<https://play.google.com/console/signup> : compte **organisation** (la pharmacie) ou personnel, frais uniques de
**25 $**. Google vérifie l'identité (pièce d'identité, et pour une organisation le numéro D-U-N-S) : compter quelques
jours. Un compte **personnel créé récemment** doit faire un test fermé (12 testeurs pendant 14 jours) avant de
pouvoir publier en production ; la piste **Test interne**, elle, est disponible tout de suite.

## 2. Créer les DEUX applications

Play Console › **Créer une application**, **deux fois** :

| | 1re application | 2e application |
|---|---|---|
| Nom | « Prestige Mobile » | « PrestigePOS » |
| Langue par défaut | Français (France) – fr-FR | Français (France) – fr-FR |
| Type / prix | Application, Gratuite | Application, Gratuite |

Cocher les déclarations (règles du programme, lois américaines sur l'exportation). Le nom du paquet n'est pas
demandé ici : il est fixé par le **premier App Bundle** envoyé dans chaque application (étape 6). **Attention à ne
pas inverser** : le bundle `prestige-mobile-aab` va dans « Prestige Mobile », `prestigepos-aab` dans « PrestigePOS ».

## 3. Créer la clé d'envoi (une fois pour les 4 applications)

**Avec Android Studio** : ouvrir n'importe quel projet Flutter / Android › **Build** › **Generate Signed App Bundle
or APK** › **Android App Bundle** › **Create new…** :
- Key store path : par exemple `D:\Cles\prestige-envoi.jks` ;
- Password : un mot de passe solide (c'est `ANDROID_KEYSTORE_PASSWORD`) ;
- Alias : `prestige` (c'est `ANDROID_KEY_ALIAS`) ;
- Password de la clé : un mot de passe solide (c'est `ANDROID_KEY_PASSWORD` ; peut être le même) ;
- Validity : **25 ans** au moins ; First and Last Name : nom de la pharmacie ; Country Code : code du pays sur deux lettres (ex. `CI`, `SN`, `FR`) ;
- **OK**, puis **Cancel** (inutile d'aller plus loin : seul le fichier `.jks` compte).

**Ou avec keytool** (PowerShell, dans le dossier `bin` du JDK, ex. `C:\Program Files\Android\Android
Studio\jbr\bin`) :

```powershell
.\keytool.exe -genkeypair -v -keystore D:\Cles\prestige-envoi.jks -alias prestige -keyalg RSA -keysize 2048 -validity 10000
```

> **SAUVEGARDER la clé : fichier `.jks` + mots de passe + alias**, en au moins **deux copies** hors du PC (clé USB au
> coffre, coffre-fort de mots de passe). Avec Play App Signing (étape 5), une clé d'envoi perdue peut être remplacée
> en écrivant au support Google (quelques jours de blocage des mises à jour) ; sans sauvegarde ni Play App Signing,
> plus aucune mise à jour n'est possible. Ne JAMAIS utiliser la clé « debug » d'Android Studio : Google la refuse.

## 4. Déposer les quatre secrets de la clé dans GitHub

Convertir le fichier en texte (base64), dans **PowerShell** :

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("D:\Cles\prestige-envoi.jks")) | Set-Clipboard
```

(le texte est copié dans le presse-papiers ; il ne s'affiche pas.)

Dépôt GitHub `prestige_vente_app` › **Settings** › **Secrets and variables** › **Actions** › onglet **Secrets** ›
**New repository secret**, quatre fois :

| Secret | Contenu |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | le texte copié par la commande ci-dessus (coller) |
| `ANDROID_KEYSTORE_PASSWORD` | mot de passe du fichier `.jks` |
| `ANDROID_KEY_ALIAS` | alias (ex. `prestige`) |
| `ANDROID_KEY_PASSWORD` | mot de passe de la clé |

Une seule fois pour ce dépôt : ces secrets servent à **Prestige Mobile et à PrestigePOS**. À refaire, identique, dans
les dépôts des autres applications Prestige.

Dès ces quatre secrets déposés, chaque envoi de code produit l'App Bundle signé de l'application de la branche :
**Actions** › **Google Play (test interne)** › le dernier run de la branche › artefact **`prestige-mobile-aab`**
(branche `pres-/tender-thompson-ang0ls`) ou **`prestigepos-aab`** (branche `prestigepos`), fichier zip contenant
`prestige-mobile-<version>.aab` ou `prestigepos-<version>.aab`. Un secret mal formé est signalé clairement (base64
invalide, mot de passe faux, alias absent, clé debug), sans jamais être affiché.

## 5. Play App Signing

Activé d'office pour une nouvelle application : Google garde la **clé de signature** de l'application et vous
signez les envois avec votre **clé d'envoi**. Au premier envoi (étape 6), accepter « Laisser Google gérer et protéger
votre clé de signature d'application » (dans chacune des deux applications).

## 6. Premier envoi : À LA MAIN (exigence de Google), pour chaque application

Google exige que le **premier** App Bundle d'une nouvelle application soit envoyé à la main dans la Play Console
(c'est lui qui fixe le nom du paquet) :

1. GitHub › **Actions** › **Google Play (test interne)** › dernier run réussi de la branche › télécharger l'artefact
   (**`prestige-mobile-aab`** pour Prestige Mobile, **`prestigepos-aab`** pour PrestigePOS), le décompresser ;
2. Play Console › l'application correspondante › **Tester et publier** › **Tests** › **Test interne** › **Créer une
   version** ;
3. accepter Play App Signing (étape 5) ;
4. **Importer** le fichier `.aab` ; nom de la version : par ex. « 4.5.0 » ou « 1.3.0 » ; notes de version en
   français ;
5. **Suivant** › **Enregistrer et publier**.

Tant que la configuration de l'application n'est pas terminée (tableau de bord de l'application : « Configurer votre
application »), Google peut garder la version en **brouillon** ; le terminer au fur et à mesure.

## 7. Les testeurs

Play Console › l'application › **Test interne** › onglet **Testeurs** :
- **Créer une liste d'adresses e-mail** (ex. « Officine ») : jusqu'à 100 comptes Google (Gmail) ; la même liste peut
  être cochée dans les deux applications ;
- cocher la liste, **Enregistrer** ;
- **Copier le lien** d'adhésion et l'envoyer aux testeurs : chacun l'ouvre **sur son téléphone**, connecté au compte
  Google de la liste, **accepte**, puis installe depuis le Play Store (un lien par application).

> Un appareil qui a déjà Prestige Mobile ou PrestigePOS installé **hors Play** (APK, terminaux Sunmi construits sur
> le PC) ne peut pas recevoir la version Play par-dessus (signature différente) : désinstaller d'abord, puis ressaisir
> l'adresse du serveur et les réglages. Les APK construits sur le PC (clé debug locale) restent utilisables comme
> avant sur les appareils qui ne passent pas par Play — c'est le cas conseillé pour les **terminaux Sunmi**.

## 8. Envois automatiques : compte de service Google Cloud

Pour que GitHub envoie lui-même les versions suivantes en Test interne :

1. <https://console.cloud.google.com> › créer un **projet** (ex. « Prestige Play ») ;
2. **API et services** › **Bibliothèque** › **Google Play Android Developer API** › **Activer** ;
3. **IAM et administration** › **Comptes de service** › **Créer un compte de service** (ex. « github-play ») ›
   **Créer et continuer** › (aucun rôle Cloud) › **OK** ;
4. ouvrir le compte de service › **Clés** › **Ajouter une clé** › **JSON** : un fichier `.json` est téléchargé (le
   garder en lieu sûr ; il ne se retélécharge pas) ;
5. Play Console › **Utilisateurs et autorisations** › **Inviter de nouveaux utilisateurs** › l'adresse e-mail du
   compte de service (`…@….iam.gserviceaccount.com`) › onglet **Autorisations des applications** › ajouter
   **Prestige Mobile ET PrestigePOS** (et les autres applications Prestige) › cocher **Publier en test** (« Release
   to testing tracks ») et **Voir les informations de l'application** › **Inviter** ;
6. GitHub › dépôt `prestige_vente_app` › **Settings** › **Secrets and variables** › **Actions** › **New repository
   secret** : **`PLAY_SERVICE_ACCOUNT_JSON`** = **tout** le contenu du fichier `.json` (ouvert avec le Bloc-notes).

Un même compte de service sert aux deux applications de ce dépôt et aux autres applications Prestige.

## 9. Lancer un envoi en Test interne

Demander « envoie Prestige Mobile (ou PrestigePOS) sur Google Play » : l'équipe écrit la version en cours en
première ligne du fichier **`android/DEMANDE_PLAY`** de **la branche de l'application** :

| Application | Branche | 1re ligne de `android/DEMANDE_PLAY` |
|---|---|---|
| Prestige Mobile | `pres-/tender-thompson-ang0ls` | version de `pubspec.yaml` (ex. `4.5.0+23`) |
| PrestigePOS | `prestigepos` | `nomVersion+codeVersion` de `android/app/prestigepos-version.properties` (ex. `1.3.0+9`) |

Le workflow **Google Play (test interne)** vérifie que la demande correspond à la version, construit l'App Bundle
signé et l'envoie sur la piste **internal** du bon paquet, avec des notes en français, statut **« completed »**
(disponible pour les testeurs après traitement par Google, quelques minutes). Si l'application est encore en
brouillon dans la Play Console, il renvoie en **« draft »** et l'explique : publier alors la version à la main (Test
interne › Modifier la version › Publier). Deux envois distincts, un par application : demander l'un n'envoie pas
l'autre (une demande de Prestige Mobile arrivée sur `prestigepos` par fusion est ignorée avec un message).

Chaque envoi exige un **numéro de version plus grand** (le `+N`) : une version déjà envoyée est refusée par Google.

## 10. Android 16 et terminaux Sunmi (pourquoi deux réglages)

Google Play exige **targetSdk 36 (Android 16)** depuis le 31/08/2026. Pour une application qui cible Android 16, un
appareil **sous Android 16** change plusieurs comportements :

| Changement d'Android 16 (targetSdk 36) | Effet possible pour Prestige Mobile / PrestigePOS |
|---|---|
| Sur grand écran (≥ 600 dp : tablettes, Sunmi D2 / D3 / T2…), orientation imposée, `resizeableActivity` et rapport d'aspect **ignorés** | capture guidée forcée en portrait, borne plein écran : l'écran pourrait tourner ou être redimensionné |
| **Retour prédictif** par défaut : `onBackPressed` plus appelé, `KEYCODE_BACK` plus transmis | borne / kiosque et écrans protégés contre le retour (PopScope) : comportement différent |
| Affichage bord à bord sans possibilité de retrait | déjà en place depuis targetSdk 35 : aucun changement |
| Bluetooth (perte d'appairage), diffusions ordonnées, ordonnanceur de tâches | imprimantes Bluetooth de PrestigePOS : à surveiller |

Choix retenu (aucun risque pour les terminaux Sunmi) :

- **targetSdk / compileSdk 36 seulement pour la version Play** : propriété Gradle `playStore`, passée par
  `.github/workflows/play.yml` (`--android-project-arg=playStore=true`). Les **APK construits sur le PC du
  pharmacien** (terminaux Sunmi) et l'**APK de la CI** gardent les valeurs de Flutter 3.32.8 (**35**) et la **même
  signature** (clé debug) : rien ne change pour eux, aucune plateforme Android 16 à installer sur le PC.
- Dans le manifeste (neutre en targetSdk 35, donc sans effet sur les APK Sunmi) : `enableOnBackInvokedCallback="false"`
  (retour comme aujourd'hui) et `PROPERTY_COMPAT_ALLOW_RESTRICTED_RESIZABILITY` (orientation respectée sur grand
  écran ; dérogation temporaire d'Android 16, à revoir au passage à targetSdk 37).
- Le contrôle de la CI (job `controle`) vérifie la version Play : bon paquet, version, **targetSdk 36**,
  bibliothèques natives compatibles **pages de 16 Ko** (autre exigence de Google Play).
- Les terminaux Sunmi actuels (Android 7 à 14) ne sont de toute façon pas sous Android 16 ; la version Play vise les
  téléphones et tablettes ordinaires.

## 11. PrestigePOS : règles de Google Play à connaître

PrestigePOS est une borne : il utilise des fonctions qu'il faut savoir expliquer à Google (rien à **déclarer** pour
le test interne ; à reprendre dans « Contenu de l'application » avant une piste fermée, ouverte ou la production).

| Fonction | Ce que fait PrestigePOS | Règle Google Play |
|---|---|---|
| Propriétaire de l'appareil (device owner) / administrateur | récepteur d'administrateur **sans aucune politique** (`<uses-policies />`), actif seulement si l'installateur rend PrestigePOS propriétaire par `adb` ; sert uniquement au verrouillage de la borne sans confirmation | autorisé ; aucune déclaration ; l'application ne bloque pas sa désinstallation. Un appareil installé depuis Play n'est **pas** propriétaire : la borne utilise alors l'épinglage standard d'Android (confirmation à l'écran) |
| Tâche verrouillée (lock task, `lockTaskMode="if_whitelisted"`) | borne épinglée ; « Revenir à Android » en sort | autorisé, pas de déclaration |
| Application d'accueil (HOME) | alias **désactivé par défaut**, activé seulement par le réglage « Démarrer automatiquement avec l'appareil » | autorisé (catégorie lanceur), pas de déclaration |
| `RECEIVE_BOOT_COMPLETED` | rouvre la borne au démarrage si le réglage est actif | permission normale, pas de déclaration |
| Bluetooth (`BLUETOOTH_SCAN` avec `neverForLocation`, `BLUETOOTH_CONNECT` ; `BLUETOOTH` / `BLUETOOTH_ADMIN` jusqu'à Android 11) | imprimantes de tickets Bluetooth | « Appareils à proximité », pas de déclaration ; jamais utilisé pour localiser |
| USB hôte (`android.hardware.usb.host`, facultatif) | imprimantes USB (câble OTG) | pas de permission, pas de déclaration |
| Caméra, micro (ajouté par le module caméra, jamais utilisé), position au premier plan seulement | scan, photos, pointage | à indiquer dans « Sécurité des données » (piste fermée et au-delà) ; pas de position en arrière-plan, donc pas de déclaration |

Prestige Mobile utilise les mêmes permissions de base (Internet, caméra, empreinte, NFC, position au premier plan),
sans propriétaire de l'appareil, HOME ni Bluetooth.

## 12. Au-delà du test interne

Les pistes **fermée**, **ouverte** et la **production** demandent en plus, dans la Play Console : politique de
confidentialité (adresse web), **sécurité des données** (données collectées : identifiants de connexion au serveur
de l'officine, photos de contrôle du pointage envoyées au serveur de l'officine, rien n'est envoyé à des tiers),
**classification du contenu** (questionnaire), public cible, fiche du Store (description, captures, icône 512 × 512,
image 1024 × 500) et examen par Google. Inutile pour le test interne.

## Pour les développeurs

- Signature : `android/app/build.gradle.kts` lit `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`,
  `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` (environnement) ou `storeFile`, `storePassword`, `keyAlias`,
  `keyPassword` (`android/key.properties`, ignoré par git) ; sinon **repli sur la clé debug** avec un avertissement
  (builds locaux et APK de la CI inchangés).
- `targetSdk` / `compileSdk` **36 seulement si `-PplayStore=true`** (`flutter build appbundle
  --android-project-arg=playStore=true`), sinon les valeurs de Flutter (35). `android.suppressUnsupportedCompileSdk=36`
  dans `android/gradle.properties` (AGP 8.7.3 testé jusqu'à 35 : avertissement seulement).
- Workflow : `.github/workflows/play.yml`, le même fichier sur les deux branches : application choisie par le nom de
  la branche (`prestigepos` → `com.dici.prestigepos`, `--flavor pos -t lib/main_pos.dart` ; sinon
  `com.dici.prestige_vente_app`) ; job `controle` sans secret à chaque envoi ; AAB en artefact si la clé existe ; envoi
  seulement si `android/DEMANDE_PLAY` change et si `PLAY_SERVICE_ACCOUNT_JSON` existe (action
  `r0adkll/upload-google-play` v1.1.5 épinglée par SHA). L'APK reste construit par `build-apk.yml`, sans `playStore`.
- `android/DEMANDE_PLAY` : sur `prestigepos`, il contient la version de PrestigePOS ; en cas de conflit à la fusion de
  la branche Prestige Mobile, garder la ligne de PrestigePOS.
- Réseau : `network_security_config.xml` autorise le HTTP (serveur local par adresse IP) ; accepté par Google Play.
- Tests : `test/android_play_test.dart` (signature, targetSdk Play seulement, manifeste, workflow) ;
  sur `prestigepos`, `test/prestigepos/pos_play_test.dart` (saveur pos, règles ci-dessus).
