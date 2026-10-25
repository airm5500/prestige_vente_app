# Prestige Mobile 4.8.0+30 — nom de l'appareil retrouvé après une réinstallation (demande 56)

Réponse du serveur du 25/10/2026 (commit 2967314). Vérifié dans son code (`rest.AppareilRessource`,
`filter.AuthenticationFilter`, `util.ContexteRequete`) :

| Route | Session | Réponses |
|---|---|---|
| `GET v1/appareil/nom?empreinte=<64 hex>` | non (route publique) | 200 `{success:true, nom:"…"}` ou `{success:true, nom:null}` ; 400 `{code:"INVALIDE"}` ; 429 `{code:"TROP_DE_DEMANDES"}` au-delà de 30 lectures par minute et par adresse |
| `PUT v1/appareil/nom` `{empreinte, nom}` | oui (401 `{code:"SESSION"}`) | 200 `{success:true, nom: tel qu'enregistré}` (nettoyé comme `X-Poste`) ; 400 nom vide ou empreinte invalide ; remplace le nom existant |

Le serveur journalise l'utilisateur, le nom et les 8 premiers caractères de l'empreinte. Le journal des
connexions prend maintenant `X-Poste` (`UserServiceImpl.getHostName` → `ContexteRequete.poste`, demande 53).

## Empreinte de l'appareil

`SHA-256(ANDROID_ID + ":" + nom du paquet)`, en hexadécimal minuscule (64 caractères).
- Elle est calculée par le **code natif** (`SunmiFingerprintBridge.empreinteAppareil`, canal existant, aucune
  permission). ANDROID_ID ne sort jamais du code natif : Flutter ne reçoit que l'empreinte.
- L'empreinte n'est ni journalisée ni gardée. Elle ne part que dans le champ `empreinte` des deux routes.
- Prestige Mobile et PrestigePOS ont deux empreintes différentes, puisque le paquet diffère : chacune garde son nom.
- ANDROID_ID change à la remise à zéro d'usine : le nom est alors redemandé.

## Ce qui change

- **Premier lancement sans nom sur l'appareil** (réinstallation) : avant l'étape obligatoire, l'application lit le nom
  gardé par le serveur, en 3 secondes au plus.
  - Nom trouvé : il est gardé sur l'appareil et l'étape est sautée. Il reste modifiable dans les réglages.
  - Sinon (`nom:null`, 404/405 d'un serveur ancien, 429, réseau, délai) : étape comme en 4.7.1, pré-remplie avec la
    marque et le modèle.
- **Envoi** (`PUT`) quand l'utilisateur enregistre un nom, si une session est ouverte, et après chaque connexion tant
  que **ce** serveur n'a pas confirmé ce nom. La préférence `nom_appareil_serveur_v1` garde, par adresse de serveur,
  le nom confirmé.
  - Le nom **renvoyé** par le serveur est celui que garde l'application (il peut différer après nettoyage).
  - Échec (réseau, 500, session) : nouvel essai à la connexion suivante.
  - 404/405 (serveur sans la demande 56) : plus d'essai pour ce serveur.
- **Borne** : rien n'est montré aux clients (règle de la 4.7.1 inchangée).
- **`X-Poste` sur la connexion et la déconnexion** : confirmé par un test (`/user/auth`, `/user/logout`).

## Tests

- `test/nom_appareil_serveur_e2e_test.dart` (application entière) :
  - « Caisse mobile 1 » saisi : `PUT` après la connexion, une seule fois, et `X-Poste` à la connexion et à la
    déconnexion ;
  - réinstallation simulée (préférences effacées, même empreinte) : nom rendu par le serveur, aucune étape, vente
    suivante avec `X-Poste` « Caisse mobile 1 » ;
  - 429, 404 et délai dépassé : étape comme avant ;
  - nom renvoyé différent : gardé ;
  - `PUT` 404 : plus d'essai ;
  - `PUT` 500 : nouvel essai à la connexion suivante ;
  - l'empreinte ne part que dans son champ et n'apparaît jamais dans le journal.
- `test/reseau/nom_appareil_serveur_reseau_test.dart` (vrai HTTP) :
  - lecture sans cookie de session ;
  - trouvé, inconnu, 429, 404, 405, empreinte invalide (rien n'est envoyé) ;
  - délai : repli en moins de 4,5 s ;
  - envoi avec la session, nom renvoyé gardé ; aucun envoi sans session.
- `test/nom_appareil_garde_test.dart` : ANDROID_ID n'apparaît que dans le code natif, haché, jamais journalisé ;
  aucune ligne de journal Dart ne mentionne l'empreinte.
