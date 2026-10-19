# Prestige Mobile 4.6.0+25 — réponse du serveur du 19/10/2026

Réponse du serveur : `docs/serveur/REPONSE_SERVEUR_2026-10-19.md` (détail : section 00 de
`docs/notices/REPONSE_DEMANDES_MOBILES.md` du serveur, branche `claude/new-session-xm8ptu`). Tout garde un repli sur
un serveur ancien.

## Ce qui change

| N° | Ce qui change |
|---|---|
| 12 — validation du BL | `PUT commande/validerbl/{id}` refusé avec `code:"PRODUITS_NON_SAISIS"` : fenêtre « Entrée en stock refusée » qui liste les produits à saisir (« CIP NOM (3/10) »), une ligne par produit, liste défilable à hauteur bornée (lisible sur Sunmi V2s). Liste absente : produits lus dans le message. Autre refus : message comme avant. |
| 12 — droit `P_BL_MOBILE_SCANNER` | Réception BL : sans ce droit, le champ de scan est remplacé par « Réception par scan réservée… », la saisie des lots est bloquée et les boutons « Créer le BL » sont désactivés. **Repli** : un serveur ancien ne connaît pas ce droit (il n'est dans la liste de personne), son absence ne suffit donc pas. Le scan n'est masqué que si le serveur **contrôle** le droit : un 403 `interdit` déjà reçu sur `add-lot` / `creerbl` (en ligne ou à l'envoi hors ligne), ou la capacité `droitScannerBl` annoncée par `GET v1/app-vente/capacites` (demandée au serveur, TRANSMISSION § 2). Sinon : comportement actuel. |
| 12 — 403 sur add-lot / creerbl | Le message du serveur s'affiche, sans déconnexion ni nouvel essai. |
| 17 D7 | `retourfournisseur/add-item` : `data.message` (« Vous avez ajouté ce produit avec un motif différent ») affiché sous l'ajout, bandeau ambre. Hors ligne : gardé sur la ligne envoyée. |
| 38 | Prestige Mobile n'a pas le « Suivi des ajustements » (seulement la saisie d'un ajustement) ni les rappels d'habitude : **rien à changer**. |
| 51 — « Mon pointage » | Serveur avec `GET v1/rh/moi` : la **session de l'application** suffit. Pas de seconde connexion, pas de jeton v1/mobile (un jeton gardé est effacé), pas de bouton « Déconnecter ce téléphone ». Routes utilisées : `GET v1/rh/moi`, `GET v1/rh/moi/pointages`, `POST v1/rh/moi/pointages` avec une clé `X-Client-Ref` par pointage. Le pointage va toujours au compte de la session. Serveur sans ces routes (404) : voie v1/mobile actuelle, avec la liaison au compte de la 4.4.0. Les réglages de l'officine sont `KEY_RH_MOBILE_QR`, `KEY_RH_MOBILE_GPS`, `KEY_RH_MOBILE_POINTAGE` : l'application ne les lisait pas par leur nom (seulement des commentaires, et `KEY_MOBILE_ACTIF` pour la connexion à jeton, qui est bien son nom). `TRANSMISSION_SERVEUR_2026-10-15.md` est corrigé. |
| 52 — terminal de pointage | Ouvert avec `P_RH_POINTER` **ou** `P_SM_RH` (`GET v1/rh/droits` → `pointer`). La **gestion** (présences du jour, photos de contrôle, enrôlement des empreintes) exige `gerer:true` **et** l'administrateur de l'application. Serveur qui n'envoie pas `gerer` : règle de la 4.4.0. Sans `gerer`, le terminal ne lit plus la présence du jour (route de gestion, 403) : il s'appuie sur ses propres pointages du jour pour « vous avez déjà pointé ». Liste des employés réduite (`id`, `matricule`, `nom`, `prenoms`, `badge`, `statut`) : vérifiée, rien ne casse (poste vide). |

## Réglages à faire dans Prestige (officine)

- Donner `P_RH_POINTER` au rôle du compte « terminal » de pointage.
- `P_BL_MOBILE_SCANNER` a été donné par le serveur à tous les profils qui ont un menu BL.

## Tests

- `test/reponse_serveur_1910_test.dart` (unitaires) :
  - lecture de `PRODUITS_NON_SAISIS` ;
  - règle `P_BL_MOBILE_SCANNER` (serveur ancien, contrôle constaté, capacité annoncée) ;
  - 403 sur add-lot / creerbl et écran de saisie sans scan ;
  - fenêtre des produits non saisis sur Sunmi V2s (30 produits, défilement, aucun débordement) ;
  - `data.message` du retour ;
  - « Mon pointage » par la session (aucun appel v1/mobile, jeton effacé, une clé par pointage, repli sur 404 et 401) ;
  - gestion RH avec `gerer` ; employés aux champs réduits.
- `test/reponse_serveur_1910_e2e_test.dart` (e2e, application entière) :
  - BL refusé avec la liste des produits (Sunmi V2s) ;
  - « Mon pointage » sans seconde connexion (ancien jeton effacé, pointage reçu pour le compte de la session) ;
  - compte avec `P_RH_POINTER` seul : terminal ouvert, aucune gestion, même pour l'administrateur ;
  - témoin `gerer:true`.
- `test/reseau/pointage_session_reseau_test.dart` (réseau) :
  - cookie et `X-Client-Ref` envoyés, même clé = un seul pointage ;
  - coupure puis reprise ;
  - serveur sans `v1/rh/moi` → v1/mobile.
