# Étape D — Évolutions du serveur Prestige pour la réception BL et le retour fournisseur mobiles

**Date :** 10 octobre 2026
**Statut :** à valider, puis à réaliser côté serveur (dépôt `airm5500/prestige`).
**Prérequis :** étapes A, B et C livrées dans l'application mobile (branche `pres-/tender-thompson-ang0ls`).

---

## 1. Contexte

Les étapes A, B et C fonctionnent **sans aucune modification du serveur**. Elles utilisent les fonctions existantes de Prestige, avec la session ouverte par `POST /api/v1/user/auth` (cookie `JSESSIONID`).

| Étape | Fonction mobile | Appels Prestige utilisés |
|---|---|---|
| A | Capture guidée LOT/EXP | aucun (traitement sur le téléphone) |
| B | Réception BL | `commande/list`, `commande/list/passees`, `commande/creerbl`, `commande/list-bons?statut=enable`, `commande/bon/items/{blId}?query=`, `commande/add-lot`, `commande/remove-lots`, `commande/bon/items/checked-quantities`, `commande/entree-stock/autorisation`, `commande/validerbl/{blId}` |
| C | Retour fournisseur | `commande/list-bons?statut=is_Closed`, `commande/bon/items/{blId}`, `common/motifs-retour`, `retourfournisseur/new`, `add-item`, `update-item`, `remove-item/{id}`, `retours-items` |

Ces appels ont été rejoués sur un serveur de test (Payara 5.2022.5, MariaDB, base du 08/10/2026). La création du BL, les lots, les refus, l'entrée en stock et la création du retour « en préparation » se comportent comme attendu.

L'étape D comble ce que le serveur ne permet pas encore. Elle se fait en trois blocs :

1. **corriger les défauts constatés** (D1 à D8) ;
2. **ajouter les droits** propres au mobile (D9) ;
3. **ajouter les données et fonctions manquantes** (D10 à D18).

---

## 2. Corrections de défauts constatés

### D1. Effacement d'un lot : suppression sur tous les BL — **priorité haute**

**Où :** `OrderServiceImpl.removeLot(DeleteLot)`, appelé par `PUT v1/commande/remove-lots`.

**Constat :**
- **Lots :** avec `removeLot = true`, `getLotByIdProduitAndNumLot` cherche `TLot` par **numéro de lot + produit** seulement. Le même numéro de lot du même produit est donc supprimé **sur tous les BL**, y compris ceux déjà entrés en stock.
- **Entrepôt :** `getWSByIdProduitAndRefBon` compare `TWarehouse.strREFLIVRAISON` à `deleteLot.getNumLot()` (le numéro de lot) au lieu du n° de BL. Les lignes d'entrepôt ne sont donc pas supprimées, ou les mauvaises le sont.
- **Quantités :** `intQTERECUE` et `intQTEUG` ne sont recalculés qu'avec les UG des lots supprimés.

**Correction attendue :**
- Restreindre **toujours** au BL : `strREFLIVRAISON = refBon AND lgFAMILLEID = idProduit`, plus `AND intNUMLOT = numLot` si `removeLot = true`.
- Supprimer les `TWarehouse` sur `strREFLIVRAISON = refBon` (et le lot si `removeLot`).
- Recalculer la ligne de BL à partir des lots restants (voir D3).
- Refuser si le BL est déjà `is_Closed`.

**Test :** deux BL avec le même produit et le même n° de lot. Effacer le lot sur le BL 2 ne doit pas toucher au BL 1.

> Le mobile n'utilise aujourd'hui que `removeLot = false` (tous les lots du produit sur ce BL), qui est correct. Il passera à l'effacement d'un seul lot après cette correction (voir D11).

### D2. Retour : produit absent du BL → erreur 500

**Où :** `RetourFournisseurServiceImpl.newItem` → `getTBonLivraisonDetailLast(...).getSingleResult()`.

**Constat :** `NoResultException`, donc HTTP 500 avec « Une erreur interne est survenue ».

**Correction :** `getResultList()` puis, si la liste est vide, réponse `{success:false, msg:"Ce produit n'est pas sur le BL <n°>"}`.

### D3. Quantité reçue d'une ligne de BL : valeur non fiable

**Constat :**
- **Contrôle du retour :** il porte sur `TBonLivraisonDetail.intQTERECUE`.
- **Mise à jour par `addNewLot` :** `updateTBonLivraisonDetailFromBonLivraison(detail, lot.getFreeQty(), lot.getFreeQty())` n'ajoute que les UG. La quantité payante du lot n'est pas ajoutée.
- **Mise à jour à l'entrée en stock :** `cloturerBonLivraison` ne met `intQTERECUE = intQTECMDE` que pour les lignes **sans** lot.
- **Valeur initiale :** à `creerbl`, `intQTERECUE` vaut la quantité livrée PharmaML ou `int_QTE_REP_GROSSISTE`.

**Correction :** définir une seule règle :

```text
quantité reçue d'une ligne = somme des lots du produit sur ce BL (intNUMBER, UG comprises)
                             ou quantité commandée si la ligne est entrée sans lot
```

Mettre à jour `intQTERECUE` et `intQTEUG` à chaque ajout ou suppression de lot, et à l'entrée en stock. Le contrôle des retours s'appuie ensuite sur cette valeur.

### D4. Retour : contrôles de quantité incomplets

**Où :** `newItem`, `updateItem`, `addItem`.

**Constat :** seul `quantité ≤ intQTERECUE` est vérifié.

**Correction :** refuser si la quantité dépasse l'un de ces plafonds, avec un message clair :
- la quantité reçue (D3) **moins** les quantités déjà retournées sur cette ligne de BL (`intQTERETURN`) **et** celles des autres retours encore `is_Process` sur la même ligne ;
- le stock disponible de l'emplacement (`TFamilleStock.intNUMBERAVAILABLE`).

> Le mobile vérifie déjà la quantité reçue et le stock. Le serveur doit le garantir pour tous les postes.

### D5. Validation du retour : stock négatif possible, aucun droit

**Où :** `MvtProduitServiceImpl.validerRetourFournisseur` (`POST v1/produit/validerretourfour`).

**Correction :**
- Refuser si une ligne ferait passer le stock sous zéro.
- Exiger le droit `P_RETOUR_FRS_VALIDER` (D9).
- Lire l'utilisateur avec `sessionHelperService.getCurrentUser()` au lieu de `HttpSession`, pour tous les modes d'authentification.

### D6. `creerbl` : montant HT ou TVA absent → erreur

**Où :** `OrderServiceImpl.creerBonLivraison` → `createBL(..., int intMHT, int intTVA)` avec `Params.getValue()` / `getValueTwo()` en `Integer`.

**Correction :** remplacer une valeur `null` par 0, et valider `ref` (obligatoire, 20 caractères au plus) et `dtStart`.

### D7. Retour : un seul motif par produit, sans le dire

**Constat :** `addItem` cumule la quantité sur la ligne existante du produit et garde **le premier motif**. Le motif envoyé est ignoré.

**Correction (au choix, à valider) :**
- **Option 1 (recommandée) :** une ligne par **(produit, motif, lot)**. Le cumul ne se fait que si les trois sont identiques.
- **Option 2 :** refuser un motif différent avec `{success:false, msg:"…déjà retourné avec le motif X"}`.

> Le mobile prévient déjà l'opérateur avant de cumuler.

### D8. Retour lié au n° de BL plutôt qu'à son identifiant

**Constat :**
- `retourfournisseur/new` reçoit dans `lgBONLIVRAISONID` le **n° de BL** (`strREFLIVRAISON`).
- `getTBonLivraison(ref)` et `getTBonLivraisonDetailLast(ref, produit)` prennent le **plus récent** des BL portant ce numéro.
- Deux grossistes peuvent avoir le même n° de BL.

**Correction :** accepter aussi l'identifiant du BL (`blId`, prioritaire s'il est fourni), et à défaut le couple (n° de BL, grossiste). Les anciens appels qui envoient le n° restent valides.

---

## 3. Droits (privilèges)

### D9. Nouveaux privilèges

Ils sont créés par migration Flyway (par exemple `V6.9.113__privileges_mobile_reception.sql`), sur le modèle de `V6.5.8__privilege_entree_en_stock.sql`.

| Privilège | Rôle | Vérifié par |
|---|---|---|
| `P_BL_MOBILE_SCANNER` | Ouvrir la réception BL sur mobile, ajouter des lots | `add-lot`, `creerbl` (appel mobile) |
| `P_BL_MOBILE_CORRIGER` | Effacer des lots, corriger une saisie d'un autre utilisateur | `remove-lots`, D11 |
| `P_BL_MOBILE_ACCEPTER_PEREMPTION_COURTE` | Accepter un lot en péremption courte | D12 |
| `P_ENTREE_EN_STOCK` (existant) | Valider l'entrée en stock | `validerbl` (déjà en place) |
| `P_BL_MOBILE_VALIDER_AVEC_ECART` | Valider malgré des lignes non saisies (entrée à la quantité commandée) | `validerbl` avec un paramètre `avecEcart=true` |
| `P_RETOUR_FRS_PREPARER` | Créer ou modifier un retour en préparation | `retourfournisseur/new`, `add-item`, `update-item`, `remove-item` |
| `P_RETOUR_FRS_VALIDER` | Valider un retour (sortie de stock) | `validerretourfour` (D5) |

**Exposition au mobile :** `POST v1/user/auth` renvoie déjà une liste `privileges: [{name, value}]` (par exemple `canUpdatePrice`). Il suffit d'y ajouter ces droits, par exemple `{"name":"retourFrsValider","value":true}`. Le mobile masquera les actions non autorisées. **Le serveur reste juge** : chaque fonction vérifie le droit.

---

## 4. Données et fonctions à ajouter

### D10. Paramètres servis au mobile

`GET v1/reception/parametres` → `{ peremptionObligatoire, moisPeremptionCourte, motifObligatoirePeremptionCourte, scansRepetesActifs }`

- `peremptionObligatoire` : `KEY_ACTIVATE_PEREMPTION_DATE`. Il est aujourd'hui déduit de `DISPLAYFILTER` dans `list-bons`.
- `moisPeremptionCourte` : nouvelle clé `KEY_RECEPTION_MOIS_PEREMPTION_COURTE`, 6 par défaut. Elle remplace le réglage local du téléphone.

### D11. Lots d'une ligne de BL, avec auteur et heure

`TLot` contient déjà `lgUSERID` et `dtCREATED`, mais `bon/items` ne renvoie que des chaînes agrégées (`"A1 | B2"`).

```text
GET    v1/commande/bon/items/{detailId}/lots
  -> [{ lotId, numLot, datePeremption, quantite, ug, utilisateur, creeLe }]
DELETE v1/commande/bon/lots/{lotId}        (droit P_BL_MOBILE_CORRIGER, BL non clôturé, recalcul D3)
```

**Gain mobile :**
- le message « DÉJÀ SAISI » indique *« par Awa à 10:42, lot AB25K012, 24 boîtes »* ;
- on peut effacer **un seul** lot au lieu de toute la ligne.

### D12. Journal des péremptions courtes acceptées et rapport

Nouvelle table `t_reception_peremption_courte`, avec les colonnes :
- identifiant, BL, ligne de BL, lot, produit et grossiste ;
- date de péremption, jours restants, quantité et valeur (PAF × quantité) ;
- utilisateur, date, motif et décision (ACCEPTE / REFUSE) ;
- statut de traitement.

```text
POST v1/reception/peremptions-courtes    (enregistré par le mobile à chaque acceptation ou refus)
GET  v1/reception/peremptions-courtes?du=&au=&grossiste=&statut=
GET  v1/reception/peremptions-courtes/export   (Excel / PDF)
```

Écran Prestige : « Rapport des péremptions courtes », avec un statut de traitement (à traiter, réclamé, avoir reçu).

### D13. Anomalies de réception

Nouvelle table `t_reception_anomalie` : BL, produit (ou code scanné inconnu), type, quantité, utilisateur, date, commentaire, statut.

**Types :**
- `PRODUIT_NON_PREVU` : scanné mais absent du BL ;
- `ECART_QUANTITE` ;
- `LOT_PERIME_REFUSE` ;
- `PRODUIT_DIFFERENT_DATAMATRIX` ;
- `SERIE_DEJA_CONSOMMEE`.

```text
POST v1/reception/anomalies
GET  v1/reception/anomalies?blId=
```

Le rapport de réception, à l'entrée en stock et sur Prestige, regroupe les lignes conformes, manquantes, excédentaires, non prévues et non reçues, les lots multiples et les écarts de prix.

### D14. Lot retourné

- **Base :** ajouter `num_lot` (et facultativement `lg_LOT_ID`) à `t_retour_fournisseur_detail`.
- **Mobile :** `RetourDetailsDTO.numLot` en entrée et en sortie. Le mobile le remplit à partir du DataMatrix scanné ou d'une liste des lots reçus sur la ligne (D11).
- **Validation :** décrémenter `TLot.currentStock` du lot concerné.

### D15. Reprendre un retour en préparation

```text
GET v1/retourfournisseur/en-preparation?blId=&utilisateur=
  -> [{ lgRETOURFRSID, strREFRETOURFRS, blRef, grossiste, nbLignes, creeLe, utilisateur }]
```

Le mobile propose alors *« Un retour est déjà en préparation sur ce BL : le reprendre ? »*.

### D16. Travail à plusieurs sur le même BL (présence et verrou temporaire)

Nouvelle table `t_reception_session` : BL, utilisateur, appareil, ligne en cours, dernier signal.

```text
POST v1/reception/{blId}/presence     { detailId? }   (toutes les 20 s depuis le mobile)
GET  v1/reception/{blId}/presence     -> [{ utilisateur, appareil, produitEnCours, depuis }]
```

- **Verrou :** il est posé sur la **ligne et le lot** en cours, expire après 2 minutes sans signal et ne bloque pas un **autre lot** du même produit.
- **Écran mobile :** il affiche « Awa traite DOLIPRANE » et la progression globale.

### D17. Saisie hors connexion et doublons

- Ajouter un identifiant d'événement `clientEventId` (UUID créé par le téléphone) à `add-lot`, `retourfournisseur/new` et `add-item`.
- Enregistrer cet identifiant dans une table `t_mobile_evenement`, avec un index unique.
- Un événement déjà reçu renvoie le résultat d'origine **sans** rien enregistrer de nouveau.

Le mobile peut ainsi garder les saisies sans réseau et les renvoyer sans risque de doublon.

### D18. Numéro de série du DataMatrix (AI 21)

Nouvelle table `t_serie_consommee`, avec les colonnes GTIN, série, ligne de BL, date, utilisateur, et un index unique sur (GTIN, série).

`add-lot` reçoit un champ `serie` facultatif. Une série déjà consommée est refusée par `{success:false, msg:"Boîte déjà scannée"}`.

---

## 5. Authentification des nouveaux appels

- **Aujourd'hui :** le mobile utilise le cookie de session de `POST v1/user/auth`. Tous les appels existants listés en §1 l'acceptent, y compris ceux qui lisent `HttpSession`.
- **Nouvelles fonctions :** le plan `docs/plans/PLAN_EVOLUTIONS_2026-10.md` (L13) prévoit que les nouvelles fonctions mobiles passent par `v1/mobile/*` avec le **jeton signé** (`Bearer`).
- **Proposition :** créer les nouvelles fonctions (D10 à D18) sous `v1/mobile/reception/...` et `v1/mobile/retours/...`, avec le jeton. Les fonctions existantes restent accessibles par cookie pendant la transition. Le mobile passera à `POST v1/mobile/connexion` dans une version ultérieure.
- **Lecture de l'utilisateur :** dans tout nouveau code, la lire avec `sessionHelperService.getCurrentUser()`, jamais avec `HttpSession` directement.

---

## 6. Ordre de réalisation proposé

| Lot | Contenu | Pourquoi d'abord |
|---|---|---|
| 1 | D1, D2, D3, D4, D5, D6 | Défauts qui peuvent fausser le stock ou bloquer l'utilisateur |
| 2 | D9 (droits) + D10 (paramètres) | Sécurité et réglages communs à tous les postes |
| 3 | D11 (lots avec auteur), D15 (reprise d'un retour), D14 (lot retourné), D7, D8 | Confort et traçabilité immédiats |
| 4 | D12 (péremptions courtes), D13 (anomalies) + rapports | Rapports demandés dans le cadrage |
| 5 | D16 (présence et verrou), D17 (hors connexion), D18 (séries) | Collaboration avancée |

---

## 7. Critères d'acceptation

1. Effacer un lot sur un BL ne modifie aucun autre BL (D1).
2. Un retour sur un produit absent du BL renvoie un message clair, sans erreur 500 (D2).
3. La quantité reçue d'une ligne est égale à la somme de ses lots après chaque ajout ou suppression (D3).
4. Un retour ne peut pas dépasser la quantité reçue moins les retours déjà faits, ni le stock (D4).
5. Un utilisateur sans `P_RETOUR_FRS_VALIDER` ne peut pas valider de retour, et la validation ne rend jamais le stock négatif (D5).
6. Chaque nouveau droit est vérifié par le serveur et renvoyé par `user/auth` (D9).
7. « Déjà saisi » affiche l'auteur et l'heure, et un lot seul peut être effacé (D11).
8. Chaque péremption courte acceptée apparaît dans le rapport, avec l'utilisateur et le motif (D12).
9. Un même `clientEventId` envoyé deux fois n'enregistre qu'une seule fois (D17).
10. Les migrations Flyway passent sur la base du 08/10/2026 (version 6.9.112 au moment des tests).

Des tests de bout en bout sont à ajouter dans `src/test/e2e/` (sur le modèle de `src/test/e2e/retours/`), en plus des tests unitaires des services.

---

## 8. Ce que fera l'application mobile une fois le serveur prêt

| Serveur | Mobile |
|---|---|
| D1 + D11 | Liste des lots de la ligne avec auteur et heure ; effacement d'un seul lot |
| D9 | Boutons affichés selon les droits (valider, corriger, accepter une péremption courte) |
| D10 | Seuil de péremption courte et caractère obligatoire de la date lus sur le serveur |
| D12, D13 | Envoi automatique des péremptions acceptées ou refusées et des anomalies (produit non prévu, lot périmé refusé…) |
| D14 | Choix du lot retourné (scan du DataMatrix ou liste des lots reçus) |
| D15 | « Reprendre le retour en préparation » à l'ouverture d'un BL |
| D16 | Participants et produit en cours affichés en haut de la réception |
| D17 | Saisie possible sans réseau, envoi automatique au retour de la connexion |
| D18 | Refus d'une boîte déjà scannée |

---

## 9. Environnement de test disponible

Un serveur de test monté avec la base du 08/10/2026 a servi à valider les étapes B et C :

- Payara 5.2022.5 (JDK 11) et MariaDB 10.11 ;
- base `laborex`, migrations Flyway jusqu'à 6.9.112 ;
- adresse `http://localhost:8080/prestige/api/v1/`.

Il pourra servir à vérifier chaque lot de l'étape D avant la mise en production.
