# Prestige Mobile 4.5.0+23 — Google Play (piste « Test interne »)

## Numéro de version

**4.5.0+23** : 4.5.0 = nouvelle diffusion ; **23** car le build 21 a existé (4.5.0+21, version iPhone / iPad retirée)
et le 22 est la 4.4.1. Rien de publié sur Sunmi (`docs/VERSIONS_SUNMI.md`). Identifiant Android inchangé :
`com.dici.prestige_vente_app`.

## Ce qui change

Prestige Mobile peut être diffusé par **Google Play, piste « Test interne »** (jusqu'à 100 testeurs, sans examen).
Mode d'emploi pour le pharmacien : **`docs/android/README.md`** (copie adaptée du guide commun aux quatre applications
Prestige : ce dépôt a **deux applications** dans la Play Console, Prestige Mobile et PrestigePOS, avec les **mêmes
secrets**).

### Signature (`android/app/build.gradle.kts`)

- La version release était signée avec la clé **debug** : Google Play refuse ce type de paquet.
- Nouvelle configuration « release » : **clé d'envoi** lue dans les variables d'environnement (`ANDROID_KEYSTORE_PATH`,
  `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` — CI) puis dans `android/key.properties`
  (poste de travail ; jamais commité, déjà ignoré par `android/.gitignore`).
- **Sans clé : repli sur la clé debug, comme avant**, avec un avertissement dans le journal. Les APK des terminaux
  Sunmi construits sur le PC du pharmacien et l'APK de la CI **ne changent pas de signature**.

### targetSdk 36 pour la version Play seulement (terminaux Sunmi inchangés)

Google Play exige **targetSdk 36 (Android 16)** depuis le 31/08/2026. Étude de l'impact (détail : guide, section 10) :
sous Android 16, une application qui cible 36 perd l'orientation imposée et le non-redimensionnement sur grand écran
(≥ 600 dp : capture guidée en portrait, borne), passe au **retour prédictif** (`onBackPressed` / `KEYCODE_BACK` plus
transmis : borne, kiosque, écrans protégés contre le retour) ; l'affichage bord à bord est déjà en place depuis la
cible 35. Risque réel pour les terminaux Sunmi en kiosque / borne s'ils passaient à Android 16, donc :

- **targetSdk / compileSdk 36 uniquement pour le bundle Play** : propriété Gradle `playStore` passée par
  `play.yml` (`--android-project-arg=playStore=true`) ; sans elle (PC du pharmacien, `build-apk.yml`) : valeurs de
  Flutter 3.32.8, **35**, comme avant ; aucune plateforme Android 16 à installer sur le PC.
  `android.suppressUnsupportedCompileSdk=36` (AGP 8.7.3) dans `android/gradle.properties`.
- Manifeste, neutre en cible 35 (APK Sunmi sans changement de comportement) et protecteur en cible 36 :
  `android:enableOnBackInvokedCallback="false"` (retour comme aujourd'hui) et
  `PROPERTY_COMPAT_ALLOW_RESTRICTED_RESIZABILITY` (orientation respectée sur grand écran ; dérogation temporaire
  d'Android 16, à revoir pour targetSdk 37).
- Permissions **inchangées** ; aucune ne demande de déclaration Play (pas de position en arrière-plan, pas de
  QUERY_ALL_PACKAGES) ; HTTP vers le serveur local (`network_security_config.xml`) accepté par Google Play.

### CI et envoi (`.github/workflows/play.yml`, même fichier sur les branches Prestige Mobile et prestigepos)

- **controle**, à chaque envoi et **sans secret** : construit la version Play (AAB et APK, repli debug) et vérifie le
  paquet, la version, **targetSdk 36** et les bibliothèques natives 64 bits alignées sur **16 Ko** (exigence Play).
- **aab** : si les quatre secrets de la clé existent (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
  `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`), forme contrôlée sans rien afficher, keystore dans `$RUNNER_TEMP`
  (droits 600, supprimé), App Bundle signé contrôlé (pas de clé debug), artefact **`prestige-mobile-aab`**.
- **Envoi en Test interne** seulement quand `android/DEMANDE_PLAY` est modifié (1re ligne = `4.5.0+23`) et que le
  secret **`PLAY_SERVICE_ACCOUNT_JSON`** existe : `r0adkll/upload-google-play` v1.1.5 épinglée par SHA, paquet
  `com.dici.prestige_vente_app`, piste `internal`, statut **completed**, repli **draft** si l'application est encore
  en brouillon côté Play. Le **premier** AAB se dépose à la main (guide, étape 6). `android/DEMANDE_PLAY` n'est pas
  créé : écrit seulement sur demande du pharmacien.
- L'APK de `build-apk.yml` est produit comme avant (sans `playStore`).

### Attention : Play et APK installés à la main

Une version installée depuis Play est signée par Google (Play App Signing) : elle ne peut pas être mise à jour par un
APK construit sur le PC (clé debug), ni l'inverse. Les terminaux Sunmi gardent les APK du PC.

## Tests

- `test/android_play_test.dart` (non-régression) : signature (environnement puis `key.properties`, repli debug avec
  avertissement, aucun mot de passe en clair, fichiers de clé ignorés), targetSdk 36 **seulement** avec `playStore`,
  APK de la CI sans `playStore`, manifeste (retour, grand écran, pas de retrait du bord à bord), permissions,
  workflow (deux applications par branche, secrets, déclencheur, action épinglée, internal, completed / draft,
  contrôle targetSdk 36 et 16 Ko, nettoyage, aucun secret affiché).
- Workflows validés par actionlint 1.7.7 avec shellcheck 0.10.0.
- Toutes les catégories lancées comme `build-apk.yml` avant l'envoi du code ; la construction réelle (APK de la CI et
  version Play targetSdk 36) est faite par la CI.
