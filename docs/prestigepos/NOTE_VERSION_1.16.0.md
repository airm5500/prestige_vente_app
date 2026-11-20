# PrestigePOS 1.16.0 (versionCode 39)

Version de PrestigePOS construite avec **Prestige Mobile V3 5.3.0+53** (code partagé ; détail :
`docs/NOTE_VERSION_5.3.0.md`).

## Ce qui change (code partagé avec Prestige Mobile V3 5.3.0)

- Prestige Mobile V3 et Prestige Pointage (saveurs `mobile` et `pointage` construites sur cette branche) : pointage sur
  un terminal sans le service d'empreinte Sunmi (SUNMI V3, Android 13) : bandeau « Ce terminal ne permet pas la
  reconnaissance par empreinte. Pointez avec votre badge ou votre code personnel. », réglage « Confirmer le pointage
  par empreinte » (désactivé par défaut) ; anciens terminaux Sunmi inchangés.

## Rien ne change pour PrestigePOS

- PrestigePOS n'a aucun pointage (borne tournée vers les clients) : ni terminal de pointage, ni bouton « Pointer », ni
  réglage de confirmation. `PosActivity` reste une `FlutterActivity` (aucune bibliothèque ajoutée) ; le canal
  `prestige/fingerprint` n'y sert qu'à la marque / au modèle et à l'empreinte de l'appareil.
- Identité inchangée : identifiant `com.dici.prestigepos`, nom « PrestigePOS », activité `PosActivity`, icône de
  `src/pos`, version dans `android/app/prestigepos-version.properties` (1.16.0+39), APK `PrestigePOS-release-1.16.0.apk`.

## Contrôles

- `test/prestigepos/pos_pointage_empreinte_test.dart` : `PosActivity` inchangée, aucun écran de pointage ni
  confirmation par empreinte dans PrestigePOS.
- `test/prestigepos/pos_identite_v3_test.dart` : identité et icône inchangées, référence de Prestige Mobile 5.3.0+53.
- CI (job `prestige-mobile-identique`) : Prestige Mobile V3 construite sur cette branche identique à la référence
  5.3.0+53 (`REFERENCE_MOBILE`).
- `pos_version_test.dart` : 1.16.0+39.
