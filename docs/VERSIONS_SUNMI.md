# Versions publiées sur le magasin Sunmi — Prestige Mobile

Ce fichier est **lu par le test** `test/version_sunmi_test.dart` : la ligne `minimum_sunmi:` ci-dessous est la
dernière version publiée sur le magasin Sunmi. Garder son format exact (`minimum_sunmi: X.Y.Z+N`).

minimum_sunmi: 3.3.1+7

## Dernières versions publiées sur Sunmi

| Version | versionCode | Date de publication | Remarque |
|---|---|---|---|
| 3.3.1 | 7 | à compléter | dernière version publiée connue |

Version en préparation (pas encore publiée) : **4.6.0+25** (`pubspec.yaml`) : 4.0.0+8 (refonte, voir
`docs/NOTE_VERSION_4.0.0.md`) + réglage « Taille de l'écran » (4.0.1+9, voir `docs/NOTE_VERSION_4.0.1.md`) +
corrections ANO-08 et ANO-02 (4.0.2+10, voir `docs/NOTE_VERSION_4.0.2.md`) + Configuration d'origine sans
débordement et recherche par début de CIP (4.0.3+11, voir `docs/NOTE_VERSION_4.0.3.md`) + HTTPS pour l'accès au
serveur par Internet (4.1.0+12, voir `docs/NOTE_VERSION_4.1.0.md`) + réglage « Afficher les produits sur le ticket de
prévente » et noms longs sur deux lignes (4.1.1+13, voir `docs/NOTE_VERSION_4.1.1.md`) + retours d'essais du 15/10 (4.2.0+14, voir
`docs/NOTE_VERSION_4.2.0.md`) + tests de performance et réseau, indicateur de la vente sur serveur lent, douchette
de l'accueil (4.2.1+15, voir `docs/NOTE_VERSION_4.2.1.md`) + EAN fabricant sans contrôle, lectures en double de la
connexion supprimées (ANO-09), intégrations de la réponse du serveur du 15/10 avec repli, message « Ajouté » de la
borne en haut de l'écran (4.3.0+16, voir `docs/NOTE_VERSION_4.3.0.md`) + boîte déjà scannée refusée à la réception
(D18, 4.3.1+17, voir `docs/NOTE_VERSION_4.3.1.md`) + Analyse article et fiche produit de nouveau rapides (mode
hybride, détail immédiat), mise en page compacte de l'Analyse article, « Serveur indisponible, veuillez réessayer »
pendant un redéploiement (4.3.2+18, voir `docs/NOTE_VERSION_4.3.2.md`) + deux messages distincts « Serveur
injoignable » / « Serveur indisponible » partout, replis « serveur ancien » vérifiés par `/officine` (4.3.3+19, voir
`docs/NOTE_VERSION_4.3.3.md`) + retours du pharmacien du 16/10 : bouton de déconnexion rouge, fiche client,
filtre de l'État de Stock, scan de la péremption, menu « Photos produits », pointage (« Mon pointage » lié au
compte, photo du badge prête, droits, réglages mémorisés), empreintes partagées entre terminaux (4.4.0+20, voir
`docs/NOTE_VERSION_4.4.0.md`) ; 4.4.1+22 : contenu identique à la 4.4.0, iOS retiré (versionCode 21 déjà utilisé
par la 4.5.0 retirée, voir `docs/NOTE_VERSION_4.4.1.md`) + Google Play, piste « Test interne » (4.5.0+23, voir
`docs/NOTE_VERSION_4.5.0.md` ; APK Sunmi inchangé : même signature, targetSdk 35) + sécurité des ventes : droits de
vente lus à chaque connexion, boutons de clôture masqués sans le droit, 403 sans déconnexion, un compte par session,
en-tête X-Prestige-Utilisateur, borne (4.5.1+24, voir `docs/NOTE_VERSION_4.5.1.md`) + réponse du serveur du 19/10 :
BL refusé avec la liste des produits, droit de scan des BL, motif différent du retour, « Mon pointage » sous la
session, terminal avec P_RH_POINTER (4.6.0+25, voir `docs/NOTE_VERSION_4.6.0.md`).

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
