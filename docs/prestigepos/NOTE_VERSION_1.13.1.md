# PrestigePOS 1.13.1 (versionCode 33)

Version de PrestigePOS construite avec Prestige Mobile **4.15.1+47** (code partagé ; détail :
`docs/NOTE_VERSION_4.15.1.md`).

## Demande 63 (serveur `correctif/demande63-1911`, bb6b4604, pas encore fusionnée)

Chaque nouveauté ne s'active que si le serveur la fournit. Avec le serveur d'aujourd'hui, PrestigePOS se comporte
comme en 1.13.0.

### Ticket dessiné par le serveur

- Le serveur rend un PNG en **niveaux de gris** (texte lissé), pas en 1 bit. Conversion en 1 bit partagée avec
  Prestige Mobile (`lib/services/ticket_1bit.dart`, seuil 128, sans tramage), puis raster `GS v 0` :
  - imprimante externe (Bluetooth, USB, réseau) : `TicketEscPos.images` ;
  - imprimante intégrée Sunmi : même conversion (`ImpressionTicket.imprimerSunmi`).
- **Correction** : la lecture de la 1.12.0 (`getLuminanceNormalized`) rendait un PNG gris à un canal entièrement noir
  sur l'imprimante externe. Sans effet en officine jusqu'ici : la route n'existe pas encore sur le serveur.
- Borne : ticket de prévente du serveur quand la route existe, sinon gabarit de la borne (inchangé). La borne ne pose
  jamais de question.

### Caisse (écrans de vente de Prestige Mobile)

- Droit `P_REMISE_VENTE` : remise masquée seulement si les droits sont lus et que le serveur est prouvé.
- « Retirer » / « SANS REMISE » → `"0"` sur un serveur prouvé, `null` sinon.
- Net rendu par `vente/remise` (comptant) utilisé ; refus affichés tels quels.
- 200 `{success:false}` de la route image → message du serveur, « Réimprimer », « Ticket de l'application »,
  « Fermer ».

### Borne (demande 62)

Le pharmacien a confirmé le 19/11 le changement de la 1.13.0 (« vente terminée » seulement si `cloture:true`, sinon
« PAYÉE, présentez ce ticket à la caisse ») : inchangé.

## Tests

- `test/prestigepos/pos_ticket_serveur_test.dart` : PNG gris du serveur en 58 / 80 mm → raster de 384 / 576 points,
  fond blanc gardé, mêmes points que Prestige Mobile ; l'ancienne lecture (tout noir) est reproduite.
- Tests de Prestige Mobile 4.15.1 (demande 63) dans la suite de la CI.
- Référence CI de Prestige Mobile : 4.15.1+47 (66dd96a).
- `pos_version_test` : 1.13.1+33.
