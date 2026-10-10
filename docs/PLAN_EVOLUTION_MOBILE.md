# Plan d'évolution — Prestige Mobile

> Statut : **validé** (réponses du client en §7) — réalisation par étapes.
> Maquettes : `docs/maquettes/evolution_maquettes.html` (+ aperçus PNG dans `docs/maquettes/apercus/`).
> Même règles que pour la refonte : aucune régression, interrupteur de retour arrière pour chaque nouveauté,
> point de retour noté avant chaque étape, tests automatiques, essai sur le serveur de test (Payara + MariaDB).

## Vérifications faites sur le serveur de test (avant de proposer)

| Question | Résultat |
|---|---|
| Une vente peut-elle avoir plusieurs règlements ? | **Oui, 2 au maximum.** Le serveur enregistre une ligne par mode dans `vente_reglement` (ex. Espèces 1 000 + Wave 1 950). |
| 3 modes (Espèces + Orange + Wave) ? | **Refusé** : « Nombre de modes de règlement non supporté : 3 (maximum 2) ». Il faut une évolution du serveur. |
| Le serveur vérifie-t-il que la somme = net à payer ? | **Non** : une somme de 3 450 F a été acceptée pour un net de 2 950 F. **L'application doit donc contrôler la somme elle-même.** |
| Modes de paiement disponibles | Espèces (1), Chèques (2), Carte bancaire (3), Différé (4), Virement (6), Orange (7), Moov (8), MTN (9), Wave (10), Djamo (19). |
| Images des produits dans Prestige ? | **Aucune** (pas de champ image sur les produits). Il faut prévoir où les stocker. |
| Double clôture | Déjà protégée par le serveur (vérifié lors de l'étape 1 des ventes). |

---

## 1. Coupures (électricité, réseau, serveur) : continuer à travailler

### 1.1 Ce qui se passe aujourd'hui
- Le serveur Prestige est dans la pharmacie. Pendant une coupure, **le serveur et souvent le routeur Wi-Fi s'arrêtent** ; les téléphones (sur batterie) restent allumés mais ne joignent plus rien.
- L'application affiche maintenant clairement la panne (« Serveur injoignable — Réessayer ») mais **ne peut rien enregistrer** : il faut attendre.

### 1.2 Les options

| Option | Principe | Avantages | Limites |
|---|---|---|---|
| **A. Onduleur (UPS) pour le serveur + routeur** | Matériel, pas de code | La solution la plus efficace et la moins chère : tout continue normalement 30 min à plusieurs heures | Coût matériel ; ne couvre pas une panne longue |
| **B. Mini-base locale sur chaque téléphone** (recommandé) | L'appli garde une copie des données utiles (produits, prix, clients…) et une **file des ventes saisies hors ligne**, envoyées automatiquement au retour du serveur | Fonctionne **sans aucun réseau** ; aucune infrastructure à ajouter | Le stock affiché peut être un peu ancien ; les plafonds d'assurance et la validité des bons ne sont vérifiables qu'au retour du serveur |
| **C. Copie en ligne (cloud)** | Un service internet garde une copie des données et reçoit les ventes | Utile si plusieurs pharmacies / accès à distance | Nécessite internet (données mobiles), un serveur à héberger et sécuriser, données patients hors de la pharmacie ; ne marche pas sans internet |

**Recommandation : A + B.** L'onduleur évite la plupart des coupures ; la mini-base locale prend le relais quand le serveur est vraiment injoignable. Le cloud (C) n'est utile que plus tard (multi-sites).

### 1.3 Mode hors ligne proposé (option B)

**Données gardées sur le téléphone** (base SQLite chiffrée, mise à jour automatique quand le serveur répond) :

| Donnée | Usage hors ligne | Mise à jour |
|---|---|---|
| Produits (CIP, EAN, nom, prix, dernier stock connu, emplacement) | Recherche, scan, panier | Complète chaque nuit + changements toutes les 15 min |
| Clients assurance / carnet + tiers payants + ayants droit | Préventes assurance/carnet | À chaque utilisation + chaque nuit |
| Modes de paiement, QR | Encaissement | À la connexion |
| Utilisateur connecté (session) | Rester connecté | Déjà le cas |

**Ce qu'on peut faire hors ligne** (à valider, question 1) :
1. **Préventes** (comptant, assurance, carnet) : saisies normalement, marquées « EN ATTENTE D'ENVOI » ; ticket « PRÉVENTE PROVISOIRE » avec un numéro local (ex. `HL-0007`).
2. **Encaissement espèces** (option, désactivée par défaut) : le client paie, l'appli imprime un **ticket provisoire**, la vente est clôturée sur le serveur au retour. Risque : écart de caisse si la vente est ensuite refusée (stock, prix modifié) → à décider.
3. **Pas** de mobile money hors ligne (la confirmation du paiement exige le réseau), **pas** de création de client définitive (créé localement, envoyé au retour).

**Synchronisation au retour du serveur** :
- Envoi automatique, **une vente à la fois, dans l'ordre**, avec les mêmes appels qu'aujourd'hui (création, articles, net, terminer prévente / clôture).
- **Idempotence** : chaque vente locale a un identifiant unique ; dès que le serveur renvoie le numéro de vente, il est enregistré sur le téléphone. En cas de coupure au milieu, l'appli **relit la vente sur le serveur** avant de renvoyer (comme déjà fait dans l'étape 1) : jamais de vente en double.
- **Conflits** affichés dans un écran « Ventes à vérifier » : prix changé, stock insuffisant, bon refusé, plafond atteint → le vendeur corrige puis renvoie ; rien n'est perdu.
- Bandeau permanent : « Hors ligne — 3 ventes en attente d'envoi » / « Envoi 2/3… » / « Tout est envoyé ✓ ».

**Amélioration serveur recommandée (étape D)** : accepter un identifiant client unique sur la création de vente (`clientRef`) et refuser un doublon → idempotence garantie côté serveur, même si le téléphone est perdu pendant l'envoi.

### 1.4 Étapes
| Étape | Contenu |
|---|---|
| H1 | Base locale (produits, clients, modes) + recherche/scan hors ligne + bandeau d'état |
| H2 | Préventes hors ligne + file d'envoi + écran « Ventes à vérifier » |
| H3 | (option) Encaissement espèces hors ligne avec ticket provisoire |
| H4 | (serveur) `clientRef` anti-doublon |

### 1.5 H3 — Stock hors ligne (réception BL, pointages, péremptions, retours) : réalisé

**Code** : `lib/horsligne/stock/` (nouveau dossier) ; points d'accroche minimes dans `local_store.dart` (migrations
NOMMÉES `withMigration`), `catalogue_sync.dart` (`CatalogueExtension`), `horsligne_ui.dart` (bandeau stock),
`rapports_hl_screen.dart` (anomalies stock dans l'écran commun), Réglages › Hors ligne, et les écrans/providers concernés
(branche « hors ligne » seulement : en ligne, le code d'origine est appelé tel quel).

**Copie étendue** (téléchargée À LA SUITE du catalogue, mêmes déclencheurs, une transaction) — routes des écrans :

| Catégorie | Route | Serveur de test |
|---|---|---|
| BL à entrer en stock | `/commande/list-bons?statut=enable` | 1 |
| BL entrés en stock (**3 j**, voir §1.6) | `/commande/list-bons?statut=is_Closed` (3 jours + jour, pour les périodes hors ligne) | 50 (sur 30 j) |
| Lignes de BL | `/commande/bon/items/{id}?filtre=ALL` (BL des deux listes) | 751 |
| Contrôle réception (**3 j**) | `/etat-control-bon/list` (lignes incluses ; `dtUPDATED` = date d'entrée en stock) | 46 |
| Commandes en cours / passées | `/commande/list`, `/commande/list/passees` | 5 |
| Lignes de commandes | `/commande/commande-en-cours-items` | 8 |
| Grossistes, motifs de retour, rayons | `/common/grossiste`, `/common/motifs-retour`, `/common/rayons` | 12 / 13 / 38 |
| Périmés en cours (du jour) | `/gestionperime/saisie-encours` | 0 |

Réglages › Hors ligne affiche le nombre d'éléments et la date par catégorie. « Vider la copie locale » efface aussi cette
copie, **jamais** les opérations en attente.

**Actions hors ligne** (file persistante SQLite `stock_ops`, une opération par BL / commande / saisie, clé `HL3-…`) :

| Écran | Hors ligne | Envoi (mêmes routes qu'en ligne) |
|---|---|---|
| Réception BL | saisie des lots (qté, UG, lot, péremption) ; contrôle « reçu ≤ commandé » conservé ; effacer = lots saisis hors ligne seulement | `/commande/add-lot` puis pointage `/commande/bon/items/checked-quantities` |
| Pointage BL, Contrôle réception | quantités contrôlées | `/commande/bon/items/checked-quantities` |
| Contrôle livraison (commande) | quantités contrôlées | `/commande/item/checked-quantities` |
| Mise à jour péremption | lot + date + quantité | `/fichearticle/add-lot` |
| Périmés (saisie) | ajout / retrait des saisies hors ligne | `/gestionperime/add` |
| Retour fournisseur | création (BL, motif, produits, commentaire) | `/retourfournisseur/new` puis `add-item` |
| Emplacement | changement de rayon | `/fichearticle/produit/update-lite-info` |
| Désactivés (« Disponible en ligne uniquement ») | création de BL, entrée en stock, recherche/historique/validation des périmés, EAN, modification d'un retour déjà sur Prestige | — |

Sans copie locale : message « … absents de cet appareil, mettez à jour la copie (Réglages › Hors ligne) » — jamais de
liste vide trompeuse ni d'erreur réseau brute.

**Envoi** : jamais automatique. Au retour du serveur, la confirmation s'ouvre (après celle des ventes H2, même principe) :
opérations en attente (type, BL / grossiste, heure, nb de lignes), cochées par défaut ; décochée = « Non envoyée —
ressaisie sur le serveur » (gardée dans l'historique) ; « Plus tard » n'envoie rien. Aussi : bandeau « N opération(s) de
stock en attente » et bouton « Envoyer maintenant » (écran « Opérations hors ligne (stock) », Réglages › Hors ligne).
Une opération à la fois, dans l'ordre ; panne réseau / session expirée → envoi interrompu, rien de perdu.

**Idempotence** : chaque ligne est marquée « envoi commencé » (sur le téléphone) avant l'appel, avec la valeur relue sur
le serveur ; si la réponse est perdue, l'envoi suivant relit le serveur (lignes du BL, `/lot/listlot`, saisie en cours des
périmés, `retours-items`) et marque « déjà appliqué » au lieu de renvoyer. Pointages et emplacements posent une valeur
(renvoi sans risque) ; même quantité déjà pointée → « déjà appliqué ».

**Anomalies** (refus du serveur, motif conservé, état traité / non traité) dans l'écran commun « Anomalies de
synchronisation » (ventes H2 + opérations de stock, impression ticket / PDF) : BL déjà clôturé (entré en stock), ligne déjà
pointée sur le serveur avec une autre quantité, commande déjà transformée en BL, ligne absente, produit inconnu,
quantité refusée, réponse perdue à la création d'un retour.

**Vérifié sur le serveur de test** (Payara + MariaDB, admin) :
- formats réels de toutes les routes ci-dessus ; copie stock complète en ~8 s (1 BL à entrer, 50 BL entrés, 751 lignes) ;
- lot sur BL « enable » avec coupure simulée après `/commande/add-lot` → 2ᵉ envoi : « déjà appliqué », 1 seul lot créé ;
- lot sur un BL clôturé → anomalie « BL déjà clôturé » SANS appel d'écriture (le serveur, lui, accepterait le lot :
  `OrderServiceImpl.addLot` ne vérifie pas le statut du BL) ;
- pointage même quantité → « déjà appliqué » ; quantité différente d'une ligne déjà pointée → anomalie ;
- péremption (`/fichearticle/add-lot`) et périmés (`/gestionperime/add`) coupés après l'appel → retrouvés, pas de doublon ;
- **limite trouvée** : `/produit/retours-data` ne liste que les retours VALIDÉS (statut `enable`) ; un retour « en
  préparation » (`is_Process`) est introuvable par l'API. Si la réponse de la création est perdue, l'appli ne renvoie
  PAS (risque de doublon, constaté) : anomalie « vérifiez sur Prestige (commentaire [HL:…]) ». Les produits ajoutés
  ensuite sont, eux, relus dans `retours-items`. Données de test nettoyées.

**Ne ralentit jamais l'appli** : une mise à jour automatique (connexion, 30 min) se met en pause avant chaque requête tant
qu'une requête de l'appli est en cours ou date de moins de 2 s (`ActiviteApp`, intercepteur sur le Dio de l'appli : ventes,
réception, pointage… sans toucher aux écrans) et reprend ensuite ; main rendue entre deux pages ; lignes converties en
SQLite par paquets de 200 ; réponses JSON décodées hors du thread UI (`BackgroundTransformer`) ; jamais deux mises à jour à
la fois ; la mise à jour manuelle est immédiate (elle lève la pause d'une mise à jour automatique en cours).
Mesuré sur le serveur de test (catalogue 1 793 produits + clients + modes + copie stock, SQLite) : **durée totale ≈ 9,7 s**,
**blocage max de la boucle d'événements 12 ms** (28 ms au premier lancement, compilation à la volée).

**Limites** : pas de création de BL ni d'entrée en stock hors ligne ; BL entrés en stock limités aux 3 derniers jours (§1.6) ;
saisie des périmés en cours : copie du jour seulement ; un pointage fait EN LIGNE après la dernière mise à jour de la copie
puis modifié hors ligne est signalé en anomalie (prudence) ; détection « retour déjà créé » impossible côté serveur
(voir ci-dessus — évolution serveur souhaitable : clé client sur `/retourfournisseur/new`, comme `clientRef` H4).

**API pour l'écran commun d'anomalies** : `Anomalie` {id, source, date, type, reference, motif, traitee, operationId,
details} et `AnomalieSource` {`anomalies()`, `setTraitee(id, bool)`} (`stock_models.dart`) ; `StockQueue` les implémente ;
`lignesAnomaliesGeneriques()` pour ticket / PDF.

### 1.6 Période par défaut, journal du terminal, anti double encaissement, attentes visibles : réalisé

**Période par défaut** (demande client) :
- la copie locale des **BL entrés en stock** et du **contrôle réception** couvre les **3 DERNIERS JOURS** (aujourd'hui
  compris ; `StockRefSync.jours = 3`, deux lectures : 3 jours + jour) au lieu de 30 ;
- les écrans hors ligne s'ouvrent sur **le jour** : Pointage BL, Contrôle réception, Retours fournisseurs (déjà « aujourd'hui »
  par défaut ; une période plus longue choisie hors ligne montre les 3 jours copiés), « Ventes hors ligne » (filtre en haut :
  Aujourd'hui / 3 jours / Tout ; les ventes à envoyer ou en anomalie sont TOUJOURS affichées), historique des
  « Opérations hors ligne (stock) » (interrupteur « Tout l'historique conservé »), « Journal du terminal » ;
- historique **conservé au moins 90 jours** (terminaux 64 Go / 4 Go RAM : la place ne manque pas) : journal, ventes hors ligne
  et opérations de stock TERMINÉES (envoyées, traitées, ressaisies) ; **purge automatique** au-delà à chaque connexion ;
  durée réglable dans Réglages › Hors ligne (90, 180, 365 ou 730 jours, jamais moins de 90). Ce qui est en attente ou en
  anomalie n'est jamais purgé.

**Journal des actions du terminal** (`lib/horsligne/journal/`) — traçabilité « pour retracer en cas de souci » :
- table SQLite dédiée `journal`, ajoutée au fichier du catalogue par la migration nommée `journal_terminal_v1`
  (`withMigration`) ; **append-only** (aucune modification, seulement la purge au-delà de la conservation) ; « Vider la copie
  locale » n'y touche pas ;
- chaque entrée : horodatage, utilisateur, terminal (identifiant `T-XXXXXX` créé une fois sur l'appareil + modèle), type,
  action, référence locale (HL-…, HL3-…) et serveur (vente, BL, retour…), montant et montants par mode, quantités par produit,
  source (en ligne / hors ligne / envoi file HL), résultat (OK / refusé + motif / échec réseau / déjà appliqué / doublon
  bloqué / info) ;
- **en ligne : point unique** = intercepteur `JournalInterceptor` posé sur le Dio de l'appli (`HorsLigne.bind`), routes
  d'écriture connues : création / ajout / modification / suppression de ligne, clôture-encaissement (comptant, assurance,
  dépôt ; montants par mode lus dans `reglements`), prévente, annulation, ouverture / clôture de caisse, réception (BL,
  lots, entrée en stock), pointages, péremptions, périmés, retours fournisseurs, ajustements, emplacement, connexion /
  déconnexion. Les écrans ne changent pas. Les requêtes de la file des ventes hors ligne sont marquées « envoi file HL »
  (avec l'en-tête `X-Client-Ref` H4 s'il est présent) et ne sont **jamais recomptées** dans les encaissements ;
- **hors ligne : appels explicites d'une ligne** aux points clés des files : vente hors ligne (création avec espèces
  encaissées et produits, envoi, anomalie, interruption, ressaisie, renvoi, traitée, suppression), panier hors ligne
  (ajout / modification / suppression de ligne), opérations de stock (réception lot, pointage, péremption, périmés, retour,
  emplacement ; envoi OK / refus / déjà appliqué / interruption ; ressaisie), confirmations d'envoi (qui, cochées /
  décochées, « Plus tard »), passages en / hors ligne ;
- **aucune donnée sensible** : seuls des champs choisis du corps sont lus (jamais le mot de passe, jeton ou cookie ; motifs
  nettoyés) ;
- écran **« Journal du terminal »** (Réglages › Hors ligne › Traçabilité, et icône de l'écran « Ventes hors ligne ») :
  filtre période (aujourd'hui par défaut, 3 / 7 / 30 jours, tout, période…), type, utilisateur, recherche par référence ;
  résumé (actions, refus, échecs, doublons bloqués, encaissé par mode, quantités par produit) ; **export PDF** (en-tête
  officine, terminal, utilisateur, période, tableau des actions, totaux encaissés par mode, totaux de quantités par produit)
  et **ticket résumé** imprimé (réglages d'impression de l'appareil).

**Anti double encaissement / double mouvement de stock** (vérifié et renforcé) :
- vente en ligne : déjà protégée (une opération à la fois, panier figé à l'encaissement, relecture du statut si réponse
  perdue) ; **en plus**, l'intercepteur **bloque une requête « unique » identique encore en cours** (clôture / encaissement,
  prévente, annulation, caisse, création de BL, entrée en stock, clôture des périmés, création de retour, clôture
  d'ajustement) : elle échoue tout de suite sans partir vers le serveur (« Opération déjà en cours : double envoi bloqué »),
  notée « doublon bloqué » ;
- **une seule confirmation d'envoi** des ventes hors ligne à la fois (bandeau, écran, retour du serveur, double appui) ; un
  double appui sur « Envoyer la sélection » / « Plus tard » ne ferme pas l'écran de dessous ; jamais de confirmation pendant
  un envoi ;
- file stock : le verrou d'envoi est pris AVANT toute attente (deux envois simultanés → un seul) ; bouton « Envoyer »
  verrouillé dès l'appui (confirmation comprise) ;
- une seule synchro de la copie à la fois (existant, testé) ; boutons d'impression / PDF désactivés pendant l'opération.

**Attentes visibles** (barres et indicateurs animés ; actions concernées bloquées) :
- mise à jour de la copie : Réglages › Hors ligne affiche « Mise à jour 1/7 », une barre globale déterminée et l'étape
  « Produits : page 3/20 (200 / 2000) » ; bandeau global : barre fine déterminée ; bouton « Mise à jour en cours… » désactivé ;
- envoi : « Envoi 2/5 » avec barre (écran Ventes hors ligne, bandeau, écran d'envoi stock) ;
- chargement des écrans hors ligne (ventes, opérations stock, journal) : barre animée pendant la lecture seulement ;
- génération PDF / impression : bouton remplacé par un indicateur animé et désactivé (pas d'animation quand l'aperçu est
  ouvert par-dessus : les tests `pumpAndSettle` ne bloquent pas ; les barres permanentes sont déterminées).

**Tests** : `test/journal_terminal_test.dart` (ajouté à la CI) — 3 jours / jour par défaut, journalisation en ligne (faux
Dio) et hors ligne, SQLite (migration, purge), totaux et PDF non vide, anti double-clic (doublon bloqué, une seule
confirmation, un seul envoi stock, une seule synchro), progression « page 3/20 » et « Envoi 1/2 », purge > 90 jours.

**Limites** : la suppression d'une ligne en ligne n'indique que l'identifiant de ligne (quantité non retranchée des totaux par
produit) ; les noms de modes viennent de la copie locale (sinon l'identifiant du mode est affiché) ; le journal est propre à
chaque terminal (pas de consolidation multi-terminaux sans évolution serveur).

---

## 2. Paiement en plusieurs modes (espèces + mobile money, Wave + OM…)

### 2.1 Règles
- **La somme des montants doit être exactement égale au net à payer** (contrôlé par l'appli : le serveur ne le vérifie pas).
- Seules les **espèces** peuvent dépasser leur part (le client donne plus) : la **monnaie à rendre** est calculée sur la part espèces uniquement.
- Le dernier mode ajouté reçoit **automatiquement le reste** ; modifier un montant recalcule le reste.
- Un même mode ne peut apparaître qu'une fois.
- **2 modes maximum** tant que le serveur n'est pas modifié ; **3 modes** après l'évolution serveur (cas 3 : espèces + OM + Wave).
- **Idempotent** : la clôture part en **une seule requête** avec la liste des règlements → soit tout est enregistré, soit rien ; double appui bloqué (comme aujourd'hui).
- Mobile money : pour chaque ligne mobile, le QR s'affiche (ou paiement via agrégateur, §3.5) ; le bouton Valider n'est actif que lorsque **chaque ligne mobile est confirmée** (case « Reçu » ou confirmation automatique de l'agrégateur).

### 2.2 Écran (sur la page d'encaissement actuelle)
```
Total à payer                      12 500 F
──────────────────────────────────────────
[💵 Espèces ]  5 000 F   (reçu 10 000 → rendre 5 000)
[📱 Wave    ]  7 500 F   ✓ reçu            ← reste auto
[ + Ajouter un mode ]        (désactivé si 2 modes / reste = 0)
──────────────────────────────────────────
Reste à payer                          0 F ✓
[        VALIDER L'ENCAISSEMENT        ]
```
- Raccourcis : « Tout en espèces », « Tout en Wave », « Partager 50/50 ».
- Ticket : détail par mode (Espèces 5 000, Wave 7 500, rendu 5 000).

### 2.3 Étapes
| Étape | Contenu |
|---|---|
| P1 | 2 modes (comptant, assurance part client, dépôt) — fonctionne avec le serveur actuel |
| P2 | (serveur) 3 modes ; l'appli passe à 3 automatiquement si le serveur l'accepte |

---

## 3. Borne de vente libre-service avec images (désactivée par défaut)

### 3.1 Parcours client
1. **Accueil de la borne** (attrayant, moderne) : « Trouvez vos produits en toute discrétion », grand champ de recherche, catégories en images (Douleur, Rhume, Hygiène, Bébé, Intime…), produits mis en avant.
2. **Recherche dynamique** dès 2-3 lettres : résultats en cartes (image, nom, prix, code) — recherche fiable par pages (déjà faite).
3. **Fiche produit** : grande image, nom, prix bien visible, forme/contenance, « Ajouter au panier » (quantité − / +), « Retour ».
4. **Panier** : modifier les quantités, retirer, total ; « Continuer mes achats » / « Payer ».
5. **Paiement** :
   - **Espèces** → impression d'un **ticket de prévente** (numéro + code-barres/QR, sans nom de produit sensible si l'option « discrétion » est activée) à présenter à la caisse.
   - **Mobile money** → choix Wave / OM / MTN / Moov → **QR dynamique du montant exact** → confirmation automatique (agrégateur) → ticket « PAYÉ » à présenter au comptoir pour la remise des produits.
6. **Retour automatique à l'accueil** après le ticket, et après 60 s sans action (le panier est vidé : confidentialité).

### 3.2 Contrôles
- Recherche : nettoyée, longueur limitée, rien d'envoyé sous 2 caractères.
- Quantité : 1 à 10 par produit (borne : pas de gros volumes), panier limité (ex. 15 articles).
- Produits sur ordonnance, stupéfiants, produits non disponibles : **non proposés** à la borne (liste/catégories à configurer).
- Prix et disponibilité revérifiés au moment du paiement.
- Aucun accès au reste de l'application : **mode kiosque Android** (épinglage d'écran), sortie par code administrateur.
- Paiement : montant fixé par le serveur, jamais saisi par le client.

### 3.3 Images des produits
Prestige ne contient pas d'images. Propositions :
1. **Photo prise par la pharmacie** depuis l'appli (Recherche article → « Photo du produit ») avec la capture guidée déjà développée, **stockée sur le serveur Prestige** (évolution serveur : table + 2 routes) — recommandé.
2. En attendant : **pictogramme par forme** (comprimé, sirop, crème, collyre…) et couleur par catégorie — la borne reste présentable sans photo.
3. (Plus tard) banque d'images externe par EAN si un fournisseur fiable existe pour la Côte d'Ivoire.

### 3.4 Présentations au choix (maquettes)
| | **Vitrine** | **Liste rapide** | **Guidée** |
|---|---|---|---|
| Idée | Grandes cartes avec images, style boutique | Liste dense : nom, prix, code, petite image | Étapes 1-2-3 avec gros boutons, pour les personnes peu à l'aise |
| Pour | Tablette, borne verticale | Terminal Sunmi, petit écran | Tous publics |

Responsive : 1 colonne (téléphone/terminal), 2-3 colonnes (tablette portrait), 4 colonnes + panier latéral (tablette paysage / borne).

### 3.5 Agrégateurs de paiement (notifications visibles directement)
- Agrégateurs disponibles en Côte d'Ivoire : **CinetPay** (OM, MTN, Moov, Wave, cartes), **PayDunya**, **Wave Business (API Checkout)**, **Orange Money Web Payment**, **MTN MoMo API**.
- **Architecture obligatoire** : les **clés secrètes ne doivent jamais être dans l'application**. Il faut un petit module côté serveur (dans Prestige ou un service à part) qui :
  1. crée le paiement (montant, référence de la vente) et renvoie le QR / lien ;
  2. reçoit la **notification** de l'agrégateur (webhook) et marque la vente « payée » ;
  3. l'appli/borne interroge ce statut (ou reçoit une notification) → affichage « Paiement reçu ✓ » et clôture automatique avec le bon mode.
- Bénéfices : fin du « reçu ? » vérifié à l'œil, montants exacts, rapprochement automatique, historique des paiements visible dans l'appli (écran « Paiements mobile money » : reçus, en attente, échoués).
- Prérequis : contrat avec un agrégateur, accès internet du serveur, URL publique (HTTPS) pour les notifications.

### 3.6 Étapes
| Étape | Contenu |
|---|---|
| B1 | Borne : accueil, recherche, fiche, panier, ticket espèces ; 3 présentations ; désactivée par défaut ; mode kiosque |
| B2 | Images : pictogrammes, puis photo produit (avec évolution serveur) |
| B3 | Mobile money via agrégateur (module serveur + notifications) — sert aussi aux ventes du comptoir et au paiement multiple |

---

## 4. Ordonnances manuscrites : lecture renforcée

### 4.1 Analyse des 17 ordonnances fournies
- **Types** : 2 imprimées (texte net, ex. Les Bleuets : DICLOCED, DIAMOX, KALEORID, MONOPROST, CARTEOL) ; **15 manuscrites**, stylo bleu ou vert, souvent cursives, abréviations (« cp », « sp », « 1 dose 3kg x 3/j », « 01 bte », « pdt 5 jrs »).
- **Structure récurrente** : lignes **numérotées** (1. 2. ou ① ②), nom du médicament souligné, **posologie sur la ligne suivante**, quantité à droite (« 01 bte », « → 02 bts »).
- **Bruit** : en-têtes de clinique, tampons et signatures qui chevauchent le texte, photos de travers, pliures, ombres.
- **Exemples difficiles** : « Debridat sp », « Efferalgan pédiatrique », « Curam 1g », « Brustan B/20 », « Tramadol », « Flagyl cp », « Prédni 20 mg », « Doliprane plus », « Eludril pro solution ».

### 4.2 Pourquoi la lecture actuelle échoue
- La reconnaissance actuelle (ML Kit, sur le téléphone) est faite pour le **texte imprimé** : sur l'écriture cursive elle donne des mots déformés (« Curam » → « Ceuram », « Brustan » → « Bnstou »…).
- « Entraîner » un modèle d'écriture manuscrite **sur le téléphone** demande des **milliers** d'exemples annotés et beaucoup de puissance : **impossible avec 17 ordonnances**. En revanche, on peut rendre l'ensemble beaucoup plus intelligent **sans régression**.

### 4.3 Proposition en couches (chacune améliore sans remplacer)
1. **Banc d'essai d'abord (anti-régression)** : les 17 ordonnances deviennent un **jeu de test** avec la bonne réponse attendue (médicaments, dosage, quantité) ; chaque amélioration est mesurée (« 9/17 bien lues → 13/17 ») et **rien n'est livré si le score baisse**. On ajoute vos nouvelles ordonnances au fil du temps.
2. **Meilleure photo** : capture guidée (déjà développée pour les étiquettes) adaptée à la page A5/A4 : cadre, netteté, redressement, contraste, suppression des ombres ; option « zone des médicaments » (l'utilisateur recadre la partie utile, sans en-tête ni tampon).
3. **Découpage par lignes numérotées** : détecter « 1. / ① / - » pour séparer chaque médicament et rattacher la posologie et la quantité à la bonne ligne.
4. **Correspondance avec VOTRE catalogue** (le vrai « entraînement ») : au lieu de lire des mots libres, l'appli cherche le **produit le plus proche dans votre stock** (ressemblance des lettres, phonétique, abréviations médicales : « cp », « sp », « susp », « pdt »…), en privilégiant les produits **réellement vendus** chez vous. « Ceuram 1g » → **CURAM 1G**.
5. **Apprentissage par correction** : chaque fois que le pharmacien corrige un produit proposé, l'appli **retient** « ce que la machine a lu → le bon produit » (sur le téléphone, puis partagé via le serveur). Les ordonnances suivantes d'un même médecin/clinique sont mieux lues. C'est l'entraînement continu adapté à votre pharmacie.
6. **Option « lecture avancée » (internet)** : envoi de la **seule zone des médicaments** (sans nom du patient, recadrée) à un service de reconnaissance d'écriture manuscrite plus puissant (ex. Google Cloud Vision, ou un modèle d'IA de lecture d'images). Bien meilleur sur la cursive, mais nécessite internet, un coût par ordonnance et **votre accord explicite** (données de santé) ; **désactivée par défaut**, avec consentement affiché.
7. **Toujours validé par le pharmacien** : l'appli propose, le pharmacien confirme (comme aujourd'hui) ; les lignes peu sûres sont marquées « à vérifier ».

### 4.4 Étapes
| Étape | Contenu |
|---|---|
| O1 | Banc d'essai des 17 ordonnances + mesure de la lecture actuelle (référence) |
| O2 | Capture guidée page + découpage par lignes numérotées |
| O3 | Correspondance catalogue améliorée (abréviations, phonétique, produits vendus) |
| O4 | Apprentissage par correction |
| O5 | (option) Lecture avancée en ligne, avec consentement |

---

## 5. Ordre proposé
1. **Paiement 2 modes (P1)** — rapide, le serveur le permet déjà.
2. **Ordonnances O1 → O4** — banc d'essai d'abord, puis améliorations mesurées.
3. **Hors ligne H1 → H2** (+ onduleur conseillé tout de suite).
4. **Borne B1 → B2**, puis **agrégateur B3** (qui sert aussi au paiement multiple et au comptoir).
5. Évolutions serveur à prévoir (étape D, côté développeur Prestige) : 3 modes de paiement, `clientRef` anti-doublon, images produits, module agrégateur + notifications.

## 6. Questions pour valider
1. **Hors ligne** : préventes seulement, ou aussi **encaissement espèces** avec ticket provisoire ?
2. **Hors ligne** : jusqu'à combien de temps une vente hors ligne peut-elle attendre (ex. 24 h) avant d'être signalée ?
3. **Paiement multiple** : on commence à **2 modes** (serveur actuel) ? Qui fait l'évolution serveur pour 3 modes ?
4. **Paiement multiple** : pour quelles ventes ? (comptant, part client assurance, dépôt, carnet ?)
5. **Borne** : quel matériel (tablette, borne verticale, terminal Sunmi) ? Une imprimante dédiée à la borne ?
6. **Borne** : quels produits/catégories exclure ? Ticket « discret » (sans nom des produits) ?
7. **Borne** : quel agrégateur (CinetPay, PayDunya, Wave Business…) — avez-vous déjà un compte ?
8. **Images** : d'accord pour des photos prises par la pharmacie et stockées sur le serveur Prestige ?
9. **Ordonnances** : d'accord pour commencer par le banc d'essai (mesure) avant toute modification ? Pouvez-vous fournir plus d'ordonnances (30 à 50, avec la liste des produits réellement délivrés) ?
10. **Ordonnances** : la « lecture avancée en ligne » vous intéresse-t-elle (internet + coût + consentement) ?

## 7. Réponses du client et vérifications complémentaires

| # | Décision |
|---|---|
| 1 | Hors ligne : **préventes ET ventes**, et aussi **réception BL, pointage BL, mise à jour péremption** et toutes les actions existantes quand c'est possible. |
| 2 | Une vente hors ligne attend **tant que le serveur n'est pas revenu** (pas de délai limite). |
| 3 | Paiement multiple : **commencer et stabiliser à 2 modes**. |
| 4 | Paiement multiple pour : **comptant** et **part client assurance**. |
| 5 | Matériel : **tablette Sunmi, borne avec ticket, terminal Sunmi** ; imprimante réseau plus tard si besoin. |
| 6 | Borne : **aucun produit exclu**, mais **mettre en avant les produits avec image** ; le ticket **imprime les produits**. |
| 7 | Agrégateur de paiement : **reporté** (choix à venir). |
| 8 | Images : **viendront du serveur** ; l'ajout de photos depuis le terminal sera demandé plus tard. |
| 9 | Ordonnances : **commencer par le banc d'essai** ; le client fournira la liste des délivrances réelles. |
| 10 | Lecture avancée en ligne : **oui, à prévoir, sans envoyer les informations du patient**. |

### Paiement multiple — code du serveur (branche `claude/new-session-xm8ptu` du dépôt prestige)
- `SalesServiceImpl.addReglement` : **2 règlements maximum** (« seuls deux règlements sont persistés (first/last) : au-delà, un règlement serait silencieusement perdu »). La répartition UG / hors CA est calculée entre le 1ᵉʳ et le dernier règlement : passer à 3 demande de réécrire cette répartition côté serveur.
- `VenteReglementDTO.equals` compare le **mode** : deux lignes du même mode seraient fusionnées → l'appli interdit deux fois le même mode.

### Recherche « commence par » / « contient » (vérifié sur le serveur de test)
- Le serveur cherche « commence par » (`LIKE 'texte%'`) et **accepte le joker `%`** : `%1000MG` trouve 26 produits contenant « 1000MG », `DOLI% 1000` trouve « DOLIPRANE 1000MG… », en 0,03 s.
- Vrai pour les **produits**, les **clients** (assurance et carnet) et les **tiers payants**.
- ⇒ L'option « Contient » est possible **sans modifier le serveur** : l'appli ajoute `%` devant et entre les mots. En « Commence par », les caractères `%` et `_` tapés par l'utilisateur sont neutralisés.
