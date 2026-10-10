# Plan d'évolution — Prestige Mobile

> Statut : **propositions à valider** — aucun code écrit.
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
