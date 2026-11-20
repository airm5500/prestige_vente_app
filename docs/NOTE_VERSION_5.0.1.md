# Prestige Mobile V3 5.0.1+50 : icônes sans cadre, comme les anciennes ; version lue dans pubspec.yaml

Retour du pharmacien (photo du lanceur d'un terminal Sunmi) après la 5.0.0+49. Même application
(`com.dici.prestigemobile.v3`, « Prestige Mobile V3 »), même fonctionnement que la 5.0.0+49 : **seules l'icône du
lanceur, la lecture de la version par Gradle et le nom du fichier APK changent**.

## 1. Icônes sans cadre, comme les anciennes

En 5.0.0, l'icône était une **icône adaptative** (Android 8 et plus) : fond blanc et dessin réduit dans la zone de
sécurité. Sur le lanceur Sunmi, le panier « V3 » apparaissait donc **plus petit, dans un carré blanc arrondi**.
L'ancienne Prestige Mobile (4.15.2, commit 48528e8) n'avait que des **PNG transparents** : le dessin directement sur
le fond d'écran, grand, sans cadre. Le pharmacien préfère l'ancienne présentation.

5.0.1 : **icônes sans cadre, comme les anciennes.**

- Plus d'icône adaptative : `android/app/src/main/res/mipmap-anydpi-v26/launcher_icon.xml` et
  `launcher_icon_round.xml` retirés, ainsi que le fond blanc (`values/couleurs_prestigemobile.xml`) et les
  `launcher_icon_foreground.png`.
- Plus d'icône ronde : `android:roundIcon` retiré du manifeste (l'ancienne application n'en avait pas),
  `launcher_icon_round.png` retirés.
- `mipmap-{m,h,xh,xxh,xxxh}dpi/launcher_icon.png` (48, 72, 96, 144, 192 px) : **fond transparent**, dessin (panier
  bleu et badge vert « V3 ») **pleine toile, centré**, à la taille des anciennes icônes : moyenne largeur / hauteur
  du dessin = 0,95 de la toile (ancienne : 0,90 × 1,00, soit 0,95). Coins transparents, bords sans liseré blanc
  (couleur des pixels semi-transparents reprise du dessin voisin), badge « V3 » lisible dès 48 px (mdpi).
- Rien d'autre ne change : ni le logo des écrans (`assets/icon/icon_v3.png`), ni les icônes du magasin.
- **PrestigePOS** et **Prestige Pointage** ont leurs propres icônes (`src/pos`, `src/pointage`) : inchangées.

Aperçu (anciennes, 5.0.0 et 5.0.1 sur fond sombre et orange) : `apercu_lanceur.png` (captures du magasin V3).

Sur un lanceur Android récent qui impose une forme à toutes les icônes (Pixel, par exemple), une icône sans version
adaptative est montrée réduite dans un cercle blanc : c'était déjà le cas de l'ancienne Prestige Mobile. Le lanceur
Sunmi montre l'icône telle quelle.

## 2. Version de l'APK lue directement dans pubspec.yaml (build depuis Android Studio)

Un APK construit dans **Android Studio**, sans commande `flutter` avant, sortait en **4.10.0+36** (fichier
« prestigepos-release-4.10.0.apk ») : Gradle prenait `flutter.versionName` / `flutter.versionCode` dans
`android/local.properties`, réécrit seulement par une commande `flutter` (pub get, build), donc périmé.

5.0.1 : `android/app/build.gradle.kts` lit la version **directement dans `pubspec.yaml`** (`version: X.Y.Z+N` →
versionName X.Y.Z, versionCode N), quel que soit l'outil qui lance le build. Les valeurs de Flutter ne servent plus
qu'en repli (pubspec.yaml absent ou sans `version: X.Y.Z+N`). Toujours aucun numéro en dur. Prestige Pointage garde
sa propre version (`prestigepointage-version.properties`).

**Nom du fichier APK** : `PrestigeMobileV3-release-5.0.1.apk` (Android Studio :
`build/app/outputs/apk/mobile/release/`). La commande `flutter build apk` copie toujours aussi l'APK sous
`build/app/outputs/flutter-apk/app-mobile-release.apk` (utilisé par la CI, qui le renomme `app-release.apk`).

Conseil au pharmacien : avant un build dans Android Studio, un `flutter pub get` reste utile (dépendances), mais la
version de l'APK ne dépend plus de lui.

## 3. Contrôles

- `test/v3_identite_test.dart` : plus de `mipmap-anydpi-v26` ni de fond adaptatif, plus de `roundIcon` ni de
  `launcher_icon_round` / `launcher_icon_foreground` ; chaque `launcher_icon.png` : taille exacte, coins
  transparents, cadre du dessin proche de celui de l'ancienne icône, badge « V3 » présent (vert, en haut à droite),
  aucun liseré blanc.
- `test/v501_version_gradle_test.dart` : l'expression de `build.gradle.kts` appliquée à `pubspec.yaml` donne la
  version de l'APK ; repli sur Flutter ; nom du fichier APK.
- `test/version_sunmi_test.dart` : Gradle reprend pubspec.yaml (lecture directe, repli Flutter), aucun numéro en dur.
- CI (`build-apk.yml`) : badging de l'APK (identifiant, nom, version) et icône de l'application = PNG (jamais un XML
  adaptatif) ; fichier `PrestigeMobileV3-release-<version>.apk` produit.

Version **5.0.1+50** (`pubspec.yaml`) ; voir `docs/VERSIONS_SUNMI.md`.
