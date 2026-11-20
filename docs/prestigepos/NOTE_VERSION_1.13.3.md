# PrestigePOS 1.13.3 (versionCode 35)

Version de PrestigePOS construite avec **Prestige Mobile V3 5.0.0+49** (code partagé ; détail :
`docs/NOTE_VERSION_5.0.0.md`).

## Ce qui change

Prestige Mobile est devenue **Prestige Mobile V3**, une nouvelle application Android (`com.dici.prestigemobile.v3`,
nom « Prestige Mobile V3 », icône avec le badge « V3 »). **PrestigePOS ne fait pas partie de la V3** : rien ne change
pour la borne.

- Identifiant : **`com.dici.prestigepos`** (inchangé) ; nom : **« PrestigePOS »** (inchangé) ; activité
  `com.dici.prestigepos.PosActivity` (inchangée).
- Icônes : fichiers de `android/app/src/pos/res` identiques à la 1.13.2 ; chaque nouvelle ressource d'icône de
  Prestige Mobile V3 (`src/main/res` : icône ronde, avant-plan adaptatif, fond) a son remplaçant PrestigePOS du même
  nom : l'APK PrestigePOS garde son icône.
- Le bandeau « Ancienne application installée » et la visibilité de l'ancienne Prestige Mobile sont propres à la saveur
  `mobile` (`src/mobile/AndroidManifest.xml`) : PrestigePOS n'en reçoit rien. Ses écrans n'affichent aucun nom de
  Prestige Mobile V3.
- Fonctionnement de la borne : identique à la 1.13.2 (Prestige Mobile V3 = 4.15.2+48 pour le code, seule l'identité
  de Mobile change).

## Contrôles

- `test/prestigepos/pos_identite_v3_test.dart` : identifiant, nom, activité, empreintes MD5 des icônes, remplaçants
  des ressources d'icône de Mobile V3, aucune requête de l'ancienne application, aucun nom V3 dans les écrans.
- CI (job `prestigepos`) : badging de l'APK (`com.dici.prestigepos`, version 1.13.3+35, « PrestigePOS »,
  `PosActivity`, aucune identité de Prestige Mobile V3).
- CI (job `prestige-mobile-identique`) : Prestige Mobile V3 construite sur cette branche identique à la référence
  5.0.0+49 (`8f7b7d1`).
- `pos_version_test.dart` : 1.13.3+35.
