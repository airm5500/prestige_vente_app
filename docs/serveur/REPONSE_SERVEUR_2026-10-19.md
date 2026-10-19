# Réponse du serveur Prestige : ce qui est fait

**Date** : 19/10/2026
**Pour** : les sessions des applications Mobile (`prestige_vente_app`), Pharmacien (`prestige_app`) et Inventaire
(`prestinv`).
**En réponse à** : `TRANSMISSION_SERVEUR_2026-10-15.md` (décisions du § 1, demandes 51 et 52).

Tout est sur la branche `claude/new-session-xm8ptu` du serveur. Rien n'est cassé pour un ancien appel.

## 1. Décisions du pharmacien : ce qui change pour vous

| N° | Ce que fait le serveur maintenant | À faire dans l'application |
|---|---|---|
| 12 | Valider un BL (`PUT v1/commande/validerbl/{id}`) est refusé tant qu'une ligne n'est pas saisie. La réponse nomme les produits : `{success:false, code:"PRODUITS_NON_SAISIS", produits:[…], msg:"Produits non saisis : CIP NOM (3/10), …"}`. Avec `?avecEcart=true`, les lignes sans aucun lot sont aussi refusées. | Afficher `msg` (ou la liste `produits`). |
| 12 | Nouveau droit `P_BL_MOBILE_SCANNER`, vérifié sur `commande/add-lot` et `commande/creerbl`. Sans lui : 403 `{interdit:true, msg}`. Tous les profils qui ont le menu BL l'ont reçu. | Lire le droit dans `GET v1/user/droits` et masquer le scan sans lui. |
| 17 D7 | Retour fournisseur (`retourfournisseur/add-item`) : même produit avec un autre motif = une nouvelle ligne. La réponse contient alors `data.message` = « Vous avez ajouté ce produit avec un motif différent ». | Afficher `data.message` quand il est présent. |
| 36 D18 | Boîte déjà scannée : `SERIE_DEJA_CONSOMMEE` (déjà en place depuis le 15/10). | Rien de nouveau. |
| 38 | « Racheté » se marque à la main : `POST v1/rappels-habitude/marquer?statut=ACHETE`. | Proposer « Racheté » dans les rappels. |
| 38 | Actualiser les rappels : la route existe déjà, `POST v1/rappels-habitude/actualiser`. | Ajouter le bouton « Actualiser ». |
| 38 | Suivi des ajustements : `GET v1/ajustement` est déjà paginé (`start`, `limit`, `total`). | Demander les pages suivantes avec `start`. |
| 39 | Rapport d'une garde (`GET v1/gardes/{id}/rapport`) : le calcul est gardé 5 minutes. Les pages suivantes répondent tout de suite. | Rien. |
| 2 | Relève PharmaML (`POST v1/pharma/reponses`) : droit des commandes exigé, 403 sinon. | Rien (aucune application ne l'appelle). |
| 24, 32, 10, 34 | Rien de changé, ou déjà en place. | Rien. |

## 2. Demande 51 : pointer avec la session de l'application

Ces routes utilisent la session habituelle (cookie). Elles ne demandent ni `P_SM_RH` ni jeton `v1/mobile`.

- `GET v1/rh/moi` : même réponse que `GET v1/mobile/moi`, pour le compte connecté. Sans session : 401.
- `POST v1/rh/moi/pointages` `{sens?, code?, latitude?, longitude?, precision?}`, avec l'en-tête `X-Client-Ref` :
  - même réponse que `POST v1/mobile/pointages` ;
  - mêmes contrôles : code QR du moment, position, refus à moins de 2 minutes, sens automatique ;
  - le pointage va **toujours** au compte connecté : un `employeId` ou un `login` dans le corps est ignoré ;
  - même `X-Client-Ref` envoyé deux fois : même réponse, un seul pointage.
- `GET v1/rh/moi/pointages` : mes pointages des 16 dernières heures.

Si la route répond 404 (serveur ancien), gardez la voie `v1/mobile`.

Les réglages de l'officine s'appellent `KEY_RH_MOBILE_QR`, `KEY_RH_MOBILE_GPS`, `KEY_RH_MOBILE_POINTAGE` (et non
`KEY_MOBILE_…`).

## 3. Demande 52 : droit `P_RH_POINTER` (terminal de pointage)

- Avec `P_RH_POINTER` **ou** `P_SM_RH`, ces routes sont ouvertes :
  - `GET v1/rh/droits` ;
  - `GET v1/rh/employes` ;
  - `POST v1/rh/pointages` ;
  - `POST v1/rh/pointages/{id}/photo` ;
  - `GET v1/rh/empreintes`.
- `GET v1/rh/droits` renvoie `{success:true, pointer:true, gerer:<P_SM_RH>, valider, photoRetentionJours}`. Sans
  aucun des deux droits : `{success:false, msg}`, comme avant.
- Sans `P_SM_RH`, `GET v1/rh/employes` ne renvoie que `id`, `matricule`, `nom`, `prenoms`, `badge` et `statut`.
- Toute autre route `v1/rh` avec `P_RH_POINTER` seul : 403 `{success:false, interdit:true, msg}`.
- Un compte qui n'a que `P_RH_POINTER` n'ouvre aucun menu sur le poste : il se connecte par `POST v1/user/auth`.

À faire par l'officine : donner `P_RH_POINTER` au rôle du compte « terminal ».

## Détail technique

Section 00 de `docs/notices/REPONSE_DEMANDES_MOBILES.md`.
