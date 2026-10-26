# PrestigePOS 1.8.0 (versionCode 22)

Version de PrestigePOS construite avec Prestige Mobile **4.10.0+36** (code partagé). Celle-ci ajoute :

- le bouton « Pointer » et la tuile de l'accueil de Prestige Mobile, qui ouvrent l'application **Prestige Pointage** ;
- la saveur `pointage` (`com.dici.prestigepointage`, demande 57) du même projet.

Détails : `docs/NOTE_VERSION_4.10.0.md` et `docs/prestigepointage/NOTE_VERSION_1.0.0.md`.

## Pour la borne PrestigePOS

- **Aucun bouton « Pointer », ni sur la borne ni dans l'administration.** C'est un choix de sûreté :
  - la borne est tournée vers les clients ;
  - un bouton ouvrant une autre application permettrait de sortir du kiosque, ou laisserait un client arriver sur
    l'écran de pointage des employés ;
  - le personnel pointe sur la borne Prestige Pointage, ou depuis Prestige Mobile.
- PrestigePOS n'affiche d'ailleurs aucun écran de connexion ni d'accueil de Prestige Mobile, et son activité
  (`PosActivity`) n'a pas le canal natif `prestige/pointage`.
- En plus, `PosApp.installer()` tient Prestige Pointage pour absente : `LanceurPointage.detecteur` renvoie toujours
  faux.
- Borne, imprimantes, démarrage et administration : inchangés.

## Construction

- `android/app/build.gradle.kts` compte maintenant trois saveurs : `mobile` (par défaut), `pos` et `pointage`.
- Noms des APK : `prestigepos-…` (Mobile), `PrestigePOS-…` et `PrestigePointage-…`.
- La CI ajoute le job `prestigepointage` (APK de Prestige Pointage contrôlé).

## Non-régression

- Job `prestige-mobile-identique` : la référence est **4.10.0+36** (commit `e0fdc76`, avant la fusion). Le chemin de
  l'APK de référence est adapté aux saveurs (`app-mobile-release.apk`).
- `test/prestigepos/pos_version_test.dart` :
  - version 1.8.0+22 ;
  - trois saveurs ;
  - aucun `BoutonPointer` ni tuile « Pointer » dans `lib/prestigepos` et `lib/borne` ;
  - pas de canal `prestige/pointage` dans `PosActivity` ;
  - détecteur forcé à faux.
- Suites de PrestigePOS et de Prestige Mobile complètes.
