# PrestigePOS 1.6.0 (versionCode 16)

Version de PrestigePOS construite avec Prestige Mobile **4.8.0+30** (code partagé) : nom de l'appareil gardé par le
serveur et retrouvé après une réinstallation (demande 56, détail dans `docs/NOTE_VERSION_4.8.0.md`).

## Pour la borne PrestigePOS

- **Empreinte de l'appareil** : SHA-256 de `ANDROID_ID` et du paquet `com.dici.prestigepos`, différente de celle de
  Prestige Mobile sur le même appareil. Calculée par le code natif ; ANDROID_ID n'en sort jamais.
- **Réinstallation** : à l'ouverture de l'administration, ou à la fin de l'assistant, sans nom sur l'appareil, le nom
  est d'abord cherché sur le serveur (3 s au plus). Trouvé, il est gardé et la carte ou l'étape obligatoire est levée ;
  sinon, comportement de la 1.5.1.
- **Envoi** : le nom est envoyé au serveur après la connexion de l'utilisateur borne, tant que ce serveur ne l'a pas
  confirmé. Le nom renvoyé par le serveur est gardé.
- **Rien n'est montré aux clients** sur l'écran de la borne.
- **Corrigé** : le canal natif « prestige/fingerprint » n'était pas branché dans PrestigePOS (`PosActivity`). Depuis
  la 1.5.0, la marque et le modèle n'étaient donc pas lus : le nom par défaut restait vide, et le champ obligatoire
  n'était pas pré-rempli. Le canal est maintenant branché pour deux lectures seulement, `hardwareInfo` et
  `empreinteAppareil` ; le service d'empreinte Sunmi n'est jamais sollicité.

## Tests

`test/prestigepos/pos_e2e_test.dart` : réinstallation simulée (préférences sans nom, même empreinte).
- Le nom revient dans l'administration et la carte obligatoire est levée.
- La prévente suivante part avec `X-Poste` « Borne entrée ».

## Non-régression

Job `prestige-mobile-identique` : la référence est **4.8.0+30** (commit 409ec8a, avant la fusion). Sur l'APK
Prestige Mobile, l'identité ne change que par le numéro de version ; les permissions sont identiques.
