# Prestige Mobile 4.6.1+26 — suite du serveur du 19/10/2026

Commits du serveur (branche `claude/new-session-xm8ptu`) postérieurs à la réponse du 19/10, relus un par un, avec
le diff des ressources REST entre l'époque de la 4.6.0 (982eab91) et la tête (965a4d1b). Tout garde un repli sur un
serveur ancien. Aucune donnée de patient ou de client dans les journaux, les caches ou les tests.

## Ce qui change

| Commit serveur | Point | Dans l'application |
|---|---|---|
| aa4e2390 | 19 — fiche client sans doublon | `POST v1/ordonnance-client/client/{id}/mesures` porte l'en-tête `X-Client-Ref` (clé `FM-<uuid>`). La clé est gardée tant que la saisie envoyée est la même : après une réponse perdue (« La mesure a peut-être été enregistrée »), un nouvel appui sur « Enregistrer » renvoie la même clé, et un serveur à jour n'enregistre qu'une mesure. Saisie modifiée = nouvelle clé. Serveur ancien : en-tête ignoré, comme avant (le message invitant à vérifier l'historique reste). |
| ce2c6c4c | 17 D8 — retour sur le bon BL | `retourfournisseur/new` envoie `blId` (identifiant du BL choisi) en plus du numéro. Deux grossistes avec le même numéro de BL : le retour vise le bon. En ligne et hors ligne (identifiant gardé dans l'opération) ; BL non retrouvé hors ligne : numéro seul, comme avant. Serveur ancien : champ inconnu ignoré (JSON-B) ; un serveur qui le refuserait (400, rien d'écrit) reçoit le même retour une fois sans `blId`, avec la même clé `X-Client-Ref`. Pas de `lgGROSSISTEID` : l'identifiant suffit. |
| ce2c6c4c | 17 D6 — création de BL | Déjà compatible : l'application exige déjà la référence (20 caractères au plus), envoie la date au format AAAA-MM-JJ et les montants HT et TVA. Un refus du serveur s'affiche tel quel (test ajouté). |

## Sans objet pour Prestige Mobile

| Commit serveur | Pourquoi |
|---|---|
| 0f86de59 — refus `code:"ETAT"` d'une suggestion déjà commandée | Prestige Mobile n'envoie ni suggestion PharmaML ni commande (`v1/suggestion-pharmaml` n'est pas utilisé ; la Réserve utilise `v1/suggestion-reserve`). Un refus avec `code` est de toute façon affiché avec son message. |
| aa4e2390 — `POST v1/ordonnance-client/enregistrer` | L'application ne crée ni ne modifie d'ordonnance. |
| 99a13f57 — écran « Péremptions courtes », exports Excel / PDF | Écran de Prestige (web). L'application n'a pas d'écran des péremptions courtes (D12) et n'appelle pas `v1/reception/…`. |
| 74e9232f, ad79533f, ea2ba1b5, 965a4d1b — lenteurs, Pilotage | Routes de statistiques et de Pilotage non utilisées par Prestige Mobile ; réponses identiques. |

## Tests

- `test/fiche_client_test.dart` : en-tête envoyé, absent sans clé ; écran : réponse perdue puis renvoi = même clé,
  saisie suivante = nouvelle clé.
- `test/reponse_serveur_1910_test.dart` : corps de `retourfournisseur/new` (`blId` présent, absent s'il est vide ou
  égal au numéro) ; en ligne : `blId` envoyé, 400 → un seul renvoi sans `blId`, refus « BL introuvable. » affiché
  sans nouvel essai ; D6 : refus du serveur affiché, date et montants envoyés.
- `test/horsligne_h4_test.dart` : hors ligne : `blId` de l'opération envoyé, absent si le BL n'a pas été retrouvé ;
  400 → renvoyé une fois sans `blId`, même clé, un seul retour.
- `test/retour_frs_test.dart` : l'écran de retour transmet l'identifiant du BL choisi.
