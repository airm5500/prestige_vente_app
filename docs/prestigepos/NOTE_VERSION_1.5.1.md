# PrestigePOS 1.5.1 (versionCode 15)

Version de PrestigePOS construite avec Prestige Mobile **4.7.1+29** (code partagé ; détail dans
`docs/NOTE_VERSION_4.7.1.md`).

## Venu de Prestige Mobile 4.7.1

- Journal de la console sans secret : jamais de mot de passe (utilisateur borne), de cookie, de jeton, de clé
  `X-Client-Ref`, de corps ni de paramètre.
- Nom de cet appareil **obligatoire** ; gardé sur l'appareil, conservé lors des mises à jour.

## Pour la borne PrestigePOS

- **Assistant de configuration** : à la fin (« Démarrer »), l'étape « Nom de cet appareil » s'impose avant d'ouvrir la
  borne. Le retour est bloqué et un nom vide est refusé.
- **Administration** : tant qu'aucun nom n'est enregistré, la carte « Nom de cet appareil (obligatoire) » est en tête.
  « Reprendre la borne », « Revenir à Android » et « Fermer PrestigePOS » sont refusés : « Saisissez le nom de cet
  appareil avant de quitter l'administration. ». La page « Nom de cet appareil » ne se quitte pas non plus sans nom.
- **Jamais montré aux clients** : pas d'étape à l'ouverture de la borne. Une PrestigePOS 1.5.0 sans nom continue de
  vendre ; le nom est demandé à la prochaine entrée dans l'administration.
- La **reprise automatique de la borne** après 3 minutes d'administration inactive reste en place : la borne ne doit
  jamais rester sur l'administration. Sans nom, il sera demandé à l'entrée suivante.
- Rien d'autre ne change : écran, mobile money, imprimantes, démarrage automatique.

## Tests

`test/prestigepos/pos_e2e_test.dart` :
- premier lancement : étape obligatoire à la fin de l'assistant, retour bloqué ;
- administration sans nom : carte obligatoire, sortie refusée, nom vide refusé, puis reprise ;
- aucune étape sur l'écran de la borne.

## Non-régression

Job `prestige-mobile-identique` : la référence est **4.7.1+29** (commit dda7f00, avant la fusion). Sur l'APK
Prestige Mobile, l'identité ne change que par le numéro de version ; les permissions sont identiques.
