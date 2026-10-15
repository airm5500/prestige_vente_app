# Versions publiées sur le magasin Sunmi — Prestige Mobile

Ce fichier est **lu par le test** `test/version_sunmi_test.dart` : la ligne `minimum_sunmi:` ci-dessous est la
dernière version publiée sur le magasin Sunmi. Garder son format exact (`minimum_sunmi: X.Y.Z+N`).

minimum_sunmi: 3.3.1+7

## Dernières versions publiées sur Sunmi

| Version | versionCode | Date de publication | Remarque |
|---|---|---|---|
| 3.3.1 | 7 | à compléter | dernière version publiée connue |

Version en préparation (pas encore publiée) : **4.2.0+14** (`pubspec.yaml`) : 4.0.0+8 (refonte, voir
`docs/NOTE_VERSION_4.0.0.md`) + réglage « Taille de l'écran » (4.0.1+9, voir `docs/NOTE_VERSION_4.0.1.md`) +
corrections ANO-08 et ANO-02 (4.0.2+10, voir `docs/NOTE_VERSION_4.0.2.md`) + Configuration d'origine sans
débordement et recherche par début de CIP (4.0.3+11, voir `docs/NOTE_VERSION_4.0.3.md`) + HTTPS pour l'accès au
serveur par Internet (4.1.0+12, voir `docs/NOTE_VERSION_4.1.0.md`) + réglage « Afficher les produits sur le ticket de
prévente » et noms longs sur deux lignes (4.1.1+13, voir `docs/NOTE_VERSION_4.1.1.md`) + retours d'essais du 15/10 (4.2.0+14, voir
`docs/NOTE_VERSION_4.2.0.md`).

## Les 3 règles (permanentes)

1. **Une seule source : `pubspec.yaml`** (`version: X.Y.Z+N`). Gradle la reprend
   (`versionCode = flutter.versionCode`, `versionName = flutter.versionName` dans `android/app/build.gradle.kts`),
   **aucun numéro en dur** (ni dans Gradle, ni dans le code : l'application lit sa version à l'exécution avec
   `package_info_plus`, voir `lib/version_app.dart`).
2. **X.Y.Z jamais inférieur** (comparaison nombre par nombre : 3.10.0 > 3.9.9) à la dernière version publiée sur
   Sunmi ; **+N strictement supérieur** au versionCode publié (sinon le magasin refuse la mise à jour).
3. **Chaque livraison augmente +N d'au moins 1** (même pour un APK de test remis à une pharmacie).

## Marche à suivre à chaque publication sur Sunmi

1. Avant de construire : augmenter `version:` dans `pubspec.yaml` (au moins +1 sur N ; X.Y.Z selon les nouveautés).
2. Construire l'APK (`flutter build apk --release`, ou télécharger l'artefact de la CI) et vérifier la version
   affichée en bas de l'écran de connexion et dans les Réglages (« Version X.Y.Z+N »).
3. Après la publication sur le magasin Sunmi : **mettre à jour ce fichier** — ajouter la ligne en haut du tableau
   (version, versionCode, date) et remplacer `minimum_sunmi:` par la version publiée.
4. Lancer `flutter test test/version_sunmi_test.dart` : il échoue si `pubspec.yaml` n'est pas au-dessus de
   `minimum_sunmi`, si N n'est pas strictement supérieur, si le format `X.Y.Z+N` manque ou si Gradle contient un
   `versionCode` / `versionName` en dur. La livraison suivante devra donc d'abord augmenter N.
