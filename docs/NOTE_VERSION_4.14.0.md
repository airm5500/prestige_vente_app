# Prestige Mobile 4.14.0+45 : ticket comme le serveur, remise sur les ventes

Demande du pharmacien du 19/11/2026 : « 1- ticket assurance désordonné et mal présenté : le prix passe sur 2 lignes et
trop d'écart avec le nom du produit ; est-il possible d'utiliser la même présentation que le serveur ? 2- ajouter
remise sur les ventes (comptant, assurance, carnet) ; je ne veux pas de régression ». Précisions du 19/11 : la même
chose pour les tickets de crédit (carnet) et le comptant ; demande de la session principale « ticket 58 mm (terminal)
et 80 mm (tablette), identique au web » (le serveur dessine, le mobile imprime l'image).

## 1. Ticket

### Cause du ticket désordonné

Ticket « VENTE CARNET » imprimé par un terminal Sunmi à imprimante intégrée de **58 mm** (32 caractères par ligne)
dont le réglage « Largeur du ticket » était **80 mm**. Le ticket était alors composé pour 48 caractères (colonnes
26 + 10 + 10) et l'imprimante coupait chaque ligne au 32ᵉ caractère :

- en-tête : « Article…Qte*P. » puis « U Total » à la ligne ;
- article : 26 espaces + « 1*1 500 » → « 1*1 50 » tout à droite, puis « 0 » et « 1 500 » à la ligne suivante ;
- traits de 48 caractères sur deux lignes.

Reproduit dans `test/ticket_vente_serveur_test.dart` (lignes exactes de l'ancien code, données fictives).

### Correction

| Point | 4.13.1 | 4.14.0 |
|---|---|---|
| Largeur sur un terminal à imprimante intégrée | réglage de l'appareil (58 ou 80) | **largeur lue sur l'imprimante (58 mm), imposée** ; Réglages › Impression : « 58 mm, imposé par l'imprimante intégrée » |
| Largeur sur une tablette | réglage | réglage 58 / 80 mm (règle du serveur : 58 ou moins → 58, sinon 80), appliqué au ticket suivant |
| Mise en page (comptant, différé, assurance, carnet) | colonnes fixes « Article / Qte*P.U / Total » | **celle du serveur** (`ConversionTicket`, `RenduTicket`) : désignation (coupée aux espaces, jamais tronquée), puis « quantité x prix » à gauche et montant à droite **sur une ligne** |
| Ordre des blocs | en-tête, client, articles, totaux, date, vendeur | officine, pharmacien, titre, vendeur, client (matricule, bénéficiaire, bon, part du client, organisme [taux]), articles, « n lignes - n articles », Total, `*` remise, « Pris sur le carnet » / « Vente à terme », NET (en grand), règlement, date, code, référence |
| Traits | parfois plus longs que la ligne | **exactement** 32 / 48 caractères |
| Caractères | espace insécable des milliers (intl), « × » | une colonne par caractère (« 1 500 », « x ») |
| Police | par défaut de l'imprimante | posée à chaque ligne (24 points ; 36 points pour l'officine et le NET) |
| Remise | absente | « Total » puis « * - 4 070 F » comme le serveur |

Exemple (58 mm, données fictives, `test/references/tickets/carnet_remise_58.txt`) :

```
PHARMACIE FICTIVE DU
        TEST
         Dr TEST Fictif
--------------------------------
          VENTE CARNET
Vendeur : Vendeur Fictif
--------------------------------
Client : CLIENT FICTIF Test
Matricule assuré :  MAT-FICT-001
Bénéficiaire : BENEFICIAIRE
FICTIF
Bon N° :             BON-FICT-12
Part du client :             0 F
CARNET FICTIF [100%] :  39 630 F
--------------------------------
PRODUIT FICTIF A 500MG CPR B/20
1 x 1 500                  1 500
...
--------------------------------
3 lignes - 6 articles
Total                   43 700 F
*                      - 4 070 F
Pris sur le carnet      39 630 F
NET           0 F CFA
Règlement                 CARNET
--------------------------------
         19/11/26 10:42
[QR]
         20261119000047
```

### Ticket dessiné par le serveur

Les tickets de vente et de prévente demandent d'abord `GET v1/vente/ticket/{type}/{id}/image?largeur=58|80&dpi=203`
(`vno`, `vo`, `prevente`) :

- **route absente (404 / 405)** — le cas de tous les serveurs au 19/11, la route n'existe sur aucune branche : ticket
  local ci-dessus (pas de régression) ; nouvel essai au bout de 30 minutes ;
- route présente : chaque PNG imprimé tel quel (384 / 576 points), coupe entre deux tickets, exemplaires décidés par le
  serveur (les copies du mobile ne s'ajoutent pas) ; mode test d'impression : aperçu des images ;
- échec de l'imprimante (papier, capot, Bluetooth) : motif affiché, vente intacte, « Réimprimer » rappelle la route ;
- réseau coupé alors que le serveur a déjà dessiné un ticket : « Ticket non imprimé : réseau indisponible » et
  « Réimprimer » (pas de ticket recomposé) ; serveur jamais vu dessiner : ticket local comme avant ;
- vente hors ligne (numéro provisoire) : ticket local « PROVISOIRE » (aucun identifiant serveur) ;
- le mobile n'appelle jamais `POST v1/vente/ticket/vno` / `ticket/vo` (imprimante du serveur) : vérifié, aucun appel.

**Retrait du gabarit local** (une seule mise en page, demandé par la session principale) : prévu dès que la route
sera confirmée déployée en officine (demande 63) ; il est gardé d'ici là (règle de non-régression).

Borne : largeur imposée de la même façon ; prévente à payer, hors « ticket discret » : image du serveur si la route
existe, sinon ticket de la borne inchangé.

Page de test : Réglages › Impression › « Page de test de la largeur » (règle 1234567890… et traits de bord à bord).

## 2. Remise sur les ventes comptant, assurance et carnet

Contrat du web, lu dans le code du serveur (`integration/recette-2026-10-29`, f0282bf0) :

| Étape | Route | Effet |
|---|---|---|
| Liste | `GET v1/common/remises-client` | mêmes choix que la liste « REMISE » du web ; « SANS REMISE » = « Retirer » |
| Appliquer / retirer | `POST v1/vente/remise {venteId, remiseId}` (null = retirer) | `{success, msg}` ; rien affiché avant `success:true` |
| Montants comptant | `POST v1/vente/net/vno {venteId, remiseId, checkUg:false}` | remise par produit (grille VNO), net arrondi à 5 F ; **sans `remiseId` le serveur efface la remise** : chaque calcul du net l'envoie |
| Montants assurance / carnet | `POST v1/vente/net/assurance` | remise de la vente, **à défaut celle de la fiche du client** (remise automatique du client) ; sur la part du client (assurance) ou le montant (carnet) |
| Reprise | `GET v1/ventestats/{id}` (`lgREMISEID`) | remise relue avant le net |

- Zone « Remise » sous la zone « Client » (comptant) et au-dessus du panier (assurance, carnet) : « Remise / Aucune
  remise » → liste → « REMISE … − 402 F (calcul du serveur) » et une croix pour la retirer ; « Remise du client »
  quand le serveur applique celle de la fiche.
- Droits : le serveur n'a **aucun droit** pour la remise (route contrôlée par la session seulement). Repli prudent :
  proposée aux comptes qui peuvent terminer une vente (ou au droit `P_REMISE_VENTE` s'il apparaît dans
  `GET v1/user/droits`, demande 63) ; un 403 `interdit` la masque pour la session, sans déconnexion.
- Hors ligne : pas de route → jamais proposée.
- Ticket : ligne « * - montant » (gabarit local) ; dans l'image du serveur quand la route existe.
- PrestigePOS : la borne ne propose jamais de remise ; la caisse a la remise par la fusion.

## Demande au serveur

Demande 63 (`docs/serveur/TRANSMISSION_SERVEUR_2026-10-15.md`) : créer la route de l'image du ticket et dire sa date
de déploiement ; droit `P_REMISE_VENTE` ; retrait d'une remise quand la fiche du client en a une ; réponses de
`vente/remise`.

## Tests

`ticket_vente_serveur` (cause reproduite, références en 32 et 48 colonnes : comptant, différé, assurance, carnet,
route image), `remise_vente`, `remise_ticket_vo`, `remise_ticket_integration`, `remise_ticket_e2e` (Sunmi V2s et
tablette), `reseau/remise_ticket_reseau`, `remise_ticket_ergonomie`, `performance/remise_ticket_perf`,
`remise_ticket_garde` ; mis à jour : `ticket_prevente` (référence 4.1.0 gardée pour les préventes), `horsligne_ventes`.
Données fictives uniquement ; aucun texte de ticket ni nom dans les journaux.
