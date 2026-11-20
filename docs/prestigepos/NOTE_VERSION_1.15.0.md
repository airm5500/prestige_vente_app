# PrestigePOS 1.15.0 (versionCode 38)

Version de PrestigePOS construite avec **Prestige Mobile V3 5.2.0+52** (code partagé ; détail :
`docs/NOTE_VERSION_5.2.0.md`).

## Ce qui change (code partagé avec Prestige Mobile V3 5.2.0)

- Prestige Mobile V3 (saveur `mobile` construite sur cette branche) : présentation de l'accueil au choix dans
  Réglages › Apparence › Accueil : « Actuelle » (par défaut, inchangée), « Metro mosaïque », « Metro bandes »,
  enregistrée sur l'appareil et appliquée tout de suite.

## Rien ne change pour PrestigePOS

- L'accueil de PrestigePOS (`PrestigePosApp`, `lib/prestigepos/`) est propre à la caisse : il n'utilise ni l'accueil de
  Prestige Mobile (`AccueilScreen`) ni la rubrique Apparence ; il est inchangé (tests `test/prestigepos/` verts).
- Identité inchangée : identifiant `com.dici.prestigepos`, nom « PrestigePOS », activité `PosActivity`, icône
  adaptative de `src/pos` (empreintes inchangées), version dans `android/app/prestigepos-version.properties`
  (1.15.0+38), APK `PrestigePOS-release-1.15.0.apk`.

## Contrôles

- `test/prestigepos/pos_identite_v3_test.dart` : identité et icône inchangées, référence de Prestige Mobile 5.2.0+52.
- CI (job `prestige-mobile-identique`) : Prestige Mobile V3 construite sur cette branche identique à la référence
  5.2.0+52 (`REFERENCE_MOBILE`).
- `pos_version_test.dart` : 1.15.0+38.
- Suite partagée de Prestige Mobile (liste de la CI, dont les nouveaux tests `accueil_metro*`) et tests PrestigePOS.
