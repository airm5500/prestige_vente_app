# PrestigePOS 1.14.0 (versionCode 37)

Version de PrestigePOS construite avec **Prestige Mobile V3 5.1.0+51** (code partagé ; détail :
`docs/NOTE_VERSION_5.1.0.md`).

## Ce qui change (code partagé avec Prestige Mobile V3 5.1.0)

- Caisse : la liste des résultats de la recherche reprend le texte tapé (focus, clavier ouvert), filtre mot par mot,
  nouvelle recherche sur le serveur quand le texte est précisé ; fenêtre de quantité « NOM · CIP », lisible clavier
  ouvert.
- Impression : « Préparation du ticket… » pendant que le serveur dessine le ticket ; taux des organismes plafonnés à
  100 % au total (80 % + 30 % → 80 % + 20 %) sur le ticket local et les récapitulatifs, comme le web (demande 66 au
  serveur pour son ticket de prévente et son ticket combiné).
- Analyse article : le détail n'attend plus le lot de la saisie (CIP exact demandé tout de suite).

## Premier ticket sur Sunmi : chemins propres à PrestigePOS

- `lib/main_pos.dart` : sur un terminal Sunmi, le service d'impression est lié **dès le lancement** (sans attendre),
  comme Prestige Mobile V3.
- Borne (`ImprimantePos`, type « Automatique » ou « Sunmi ») : l'imprimante intégrée est reconnue au **fabricant
  Sunmi**, sans dépendre de la liaison (le paquet `sunmi_printer_plus` répond « liée » dès qu'elle est demandée).
  L'impression (ticket du serveur ou gabarit de la borne) attend la **connexion réelle** du service (3 s au plus) :
  plus de commandes perdues au premier ticket. Autres appareils : détection comme avant.
- Imprimantes externes (Bluetooth, USB, réseau) : inchangées.

## Rien ne change pour l'identité de PrestigePOS

Identifiant `com.dici.prestigepos`, nom « PrestigePOS », activité `PosActivity`, icône adaptative de `src/pos`
(empreintes inchangées), version dans `android/app/prestigepos-version.properties` (1.14.0+37), APK
`PrestigePOS-release-1.14.0.apk`.

## Contrôles

- `test/prestigepos/pos_imprimante_sunmi_test.dart` : détection Sunmi, ticket de la borne après la connexion réelle
  (canal simulé), autres appareils comme avant, liaison dans `main_pos`.
- `test/prestigepos/pos_identite_v3_test.dart` : identité et icône inchangées, référence de Prestige Mobile 5.1.0+51.
- CI (job `prestige-mobile-identique`) : Prestige Mobile V3 construite sur cette branche identique à la référence
  5.1.0+51.
- `pos_version_test.dart` : 1.14.0+37.
