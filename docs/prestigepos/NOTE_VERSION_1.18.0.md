# PrestigePOS 1.18.0 (versionCode 41)

Version de PrestigePOS construite avec **Prestige Mobile V3 5.5.0+55** (code partagé ; détail :
`docs/NOTE_VERSION_5.5.0.md`).

## Ce qui change (code partagé avec Prestige Mobile V3 5.5.0)

Transmission du serveur du 24/11 (`plan/24112026`) : quand l'heure du serveur est fausse, Prestige refuse toute
écriture (HTTP 423 `horlogeBloquee`).

- Borne : la prévente n'est pas créée ; le client voit le **message du serveur tel quel** (jamais « serveur
  injoignable »), aucune relance automatique ; après la correction, la commande suivante est créée normalement.
- Comptoir (saveur `mobile`), réceptions, paiements mobile money, pointage : message du serveur ; ventes, stock et
  pointages en file gardés puis envoyés une fois après la correction (même `X-Client-Ref`).
- Journal du terminal : « Heure du serveur fausse (HTTP 423 horlogeBloquee) », jamais le message ni la requête.
- Aucune requête de plus en fonctionnement normal (`GET v1/horloge/public` lu seulement après un refus 423).

## Propre à PrestigePOS

- Aucun code propre à PrestigePOS ne change (ses chemins passent par les clients partagés). Identité inchangée :
  `com.dici.prestigepos`, « PrestigePOS », `PosActivity`, icône de `src/pos`, version 1.18.0+41
  (`android/app/prestigepos-version.properties`), APK `PrestigePOS-release-1.18.0.apk`.

## Contrôles

- `test/prestigepos/pos_horloge_test.dart` : prévente de la borne refusée en 423 (message, une requête, journal par
  catégorie), puis créée après la correction.
- `test/prestigepos/pos_identite_v3_test.dart` : identité et icône inchangées, référence de Prestige Mobile 5.5.0+55.
- CI (job `prestige-mobile-identique`) : Prestige Mobile V3 construite sur cette branche identique à la référence
  5.5.0+55 (`REFERENCE_MOBILE`).
- `pos_version_test.dart` : 1.18.0+41.
