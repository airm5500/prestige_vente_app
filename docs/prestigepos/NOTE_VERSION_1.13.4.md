# PrestigePOS 1.13.4 (versionCode 36)

Version de PrestigePOS construite avec **Prestige Mobile V3 5.0.1+50** (code partagé ; détail :
`docs/NOTE_VERSION_5.0.1.md`).

## Ce qui change

Prestige Mobile V3 5.0.1 : **icônes sans cadre, comme les anciennes** (PNG transparents, plus d'icône adaptative ni
d'icône ronde dans `src/main`), version de l'APK lue directement dans `pubspec.yaml` par Gradle (build depuis Android
Studio) et APK de Mobile nommé `PrestigeMobileV3-release-<version>.apk`.

**Rien ne change pour PrestigePOS** :

- Identifiant **`com.dici.prestigepos`**, nom **« PrestigePOS »**, activité `com.dici.prestigepos.PosActivity`.
- Icône : fichiers de `android/app/src/pos/res` identiques (empreintes MD5 de la 1.13.2) : PrestigePOS garde son
  icône adaptative (fond blanc), son icône ronde et sa couleur de fond, déclarées par son propre manifeste et ses
  propres ressources ; elle ne dépendait d'aucun fichier d'icône de `src/main`.
- Version : toujours lue dans `android/app/prestigepos-version.properties` (1.13.4+36) ; nom de l'APK inchangé
  (`PrestigePOS-release-1.13.4.apk`).
- Fonctionnement de la borne : identique à la 1.13.3.

## Contrôles

- `test/prestigepos/pos_identite_v3_test.dart` : empreintes des icônes de `src/pos`, plus aucune ressource adaptative
  ni ronde dans `src/main`, icône adaptative et fond de PrestigePOS présents, référence de Prestige Mobile 5.0.1+50.
- CI (job `prestigepos`) : badging de l'APK (`com.dici.prestigepos`, 1.13.4+36, « PrestigePOS », `PosActivity`) et
  icône de l'APK = XML adaptatif de PrestigePOS (inchangée).
- CI (job `prestige-mobile-identique`) : Prestige Mobile V3 construite sur cette branche identique à la référence
  5.0.1+50 (`4080802`).
- `pos_version_test.dart` : 1.13.4+36.
