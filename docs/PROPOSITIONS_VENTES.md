# Refonte des 3 ventes : Pré-vente / Vente, Pré-vente Assurance, Vente Carnet

> Statut : **propositions validées, à implémenter par étapes** — aucun code écrit à ce stade.
> Maquettes visuelles : `docs/maquettes/ventes_maquettes.html` (à ouvrir dans un navigateur).

## 0. Principes non négociables

| Principe | Ce que ça veut dire concrètement |
|---|---|
| **Aucune régression** | Mêmes appels serveur, mêmes paramètres, mêmes calculs (montants, remises, net, parts TP). On change l'affichage et on ajoute des protections. |
| **Retour arrière possible** | Balises git avant chaque étape + **interrupteur dans Réglages** pour revenir à l'ancienne version des ventes sans réinstaller (voir §6). |
| **Sécurisé** | Rien n'est présenté comme enregistré s'il ne l'est pas ; aucune donnée saisie perdue en silence. |
| **Idempotent** | Un double tap, un double scan ou une coupure réseau ne crée jamais une 2ᵉ vente, une 2ᵉ ligne ou une 2ᵉ clôture (voir §5). |
| **Erreurs prévenues** | On bloque une saisie fausse avant l'envoi ; on affiche le vrai message du serveur ; une panne est annoncée comme une panne (« Réessayer »), jamais comme « introuvable ». |
| **Professionnel** | Présentations A / B / C au choix comme les autres menus, gros boutons libellés, lisible à 360 px. |

## 1. Réponses validées

| # | Question | Décision |
|---|---|---|
| 1 | Prévente ou vente ? | **Choix à la fin.** Le vendeur remplit le panier, puis choisit « Enregistrer en prévente » ou « Encaisser ». |
| 2 | Modification du prix dans le panier | **Reste libre** (bornes techniques seulement : pas de négatif, pas de valeur absurde). |
| 3 | Encaissement | **Une seule page** au lieu d'une suite de dialogues — à tester. |
| 4 | Net assurance / carnet | **Calculé automatiquement** à chaque changement (plus de bouton « Calculer »). |
| 5 | « Changer l'assurance » | **Fonctionnement actuel conservé** (met à jour la fiche client sur le serveur). |
| 6 | Ayant droit carnet | **Le client est son propre ayant droit par défaut**, mais on peut en choisir un autre ou en **créer** un nouveau. |
| 7 | Historique client | **Ajout de « Reprendre la prévente »** à côté de « Réimprimer ». |
| 8 | Ordre | Socle commun + corrections → Pré-vente → Assurance → Carnet ; une APK testable par étape. |

### Question 1 vérifiée sur le serveur Prestige

Lecture du code du serveur (`SalesRessource.addVente`, `SalesServiceImpl`) :

- À la création, `prevente = true` donne le statut **`pending`** ; `prevente = false` donne **`is_Process`**.
- `terminerprevente` passe la vente en `is_Process` (elle apparaît alors dans la liste des préventes à encaisser).
- `cloturer/vno` refuse seulement une vente **déjà clôturée** (`is_Closed`), avec un message dédié : le serveur protège déjà contre la double clôture.

**Proposition** : toute nouvelle vente du menu Pré-vente est créée comme prévente (`pending`), puis à la fin :

- **« Enregistrer en prévente »** → `terminerprevente` (comme aujourd'hui l'onglet PREVENTE) ;
- **« Encaisser »** → `cloturer/vno` directement (comme aujourd'hui l'onglet VENTE).

Avantage en plus : une vente en cours de saisie n'apparaît plus dans la liste des préventes des caissiers (aujourd'hui, une vente commencée dans l'onglet VENTE est en `is_Process` dès le 1ᵉʳ article et y apparaît).

> ⚠️ À confirmer sur le serveur de test **avant** l'étape 2 : clôture directe d'une vente `pending` (stock, ticket, caisse, statistiques). Si un écart apparaît, repli : la vente est créée en `is_Process` comme aujourd'hui et le choix final appelle le même enchaînement que les onglets actuels.

## 2. Défauts actuels à corriger (constatés dans le code)

### Argent et ventes
1. **Double vente** : deux scans rapides du 1ᵉʳ produit créent deux ventes (une orpheline). Les 3 menus.
2. **« ajouté (+1) » affiché avant la réponse du serveur** ; un échec d'ajout ne s'affiche pas.
3. **Ancien net envoyé à la clôture** si le recalcul du net échoue.
4. **Prix / quantité du panier sans contrôle** : 0 ou négatif acceptés.
5. **Type prévente/vente figé au 1ᵉʳ article** alors que les deux onglets partagent le panier.
6. **Ouvrir une prévente depuis LISTE écrase le panier en cours** sans confirmation (vente orpheline).
7. Annuler le dialogue « Combien en reste-t-il ? » **ajoute quand même 1 unité**.

### Assurance / carnet
8. **La vente assurance peut disparaître en pleine saisie** : elle est recréée à chaque notification de la session (`main.dart`, `AssuranceSaleProvider` non conservé).
9. **Réimpression depuis l'historique : ticket sans référence** (code-barres / QR vides), nombre de copies ignoré.
10. **Assurance à 100 % imprimée « PRÉ-VENTE CARNET »**.
11. **Client sans ayant droit accepté** : chaque ajout de produit échoue ensuite.
12. **Nom / prénom inversés** entre la création d'un client et celle d'un ayant droit.
13. Carnet : suppression d'une ligne **sans confirmation** ; choisir un carnet **valide la création du client sans relecture**.

### Erreurs réseau
14. Une panne s'affiche « Produit introuvable » / « Ce client est introuvable » **avec le bouton Créer** → clients en double.
15. **Messages du serveur perdus** (plafond, bon déjà utilisé…) remplacés par « Erreur lors de l'ajout ».
16. **Panier qui paraît vide** si sa relecture échoue (la vente existe pourtant).
17. **Liste des préventes : toutes datées du jour** (format de date mal lu).
18. Dialogue « Mode de règlement » **vide sans explication** si aucun mode n'est activé dans les réglages.

### Ergonomie
19. Actions principales = **icônes rondes sans libellé** ; icônes de 20 px dans le panier.
20. **Retour arrière en pleine vente sans confirmation** (Pré-vente).
21. Jusqu'à **6 dialogues à la suite** pour encaisser une vente assurance.
22. Bouton « Calculer le Net » obligatoire et caché après chaque changement.

## 3. Socle commun (étape 1)

Les 3 menus sont aujourd'hui des copies (≈ 2 000 lignes identiques : recherche, scan, quantité, panier, encaissement, impression). Un défaut existe donc 3 fois.

On crée **un seul moteur de vente** :

| Brique commune | Rôle |
|---|---|
| `SaleSession` | Une vente en cours : file d'opérations (une à la fois), verrou de création, état « enregistré / en cours d'envoi / non enregistré ». |
| Barre de recherche + scan | Douchette, caméra, saisie ; mode scan rapide mémorisé ; erreurs réseau distinguées. |
| Fenêtre de quantité | 1 à 9 999, confirmation au-delà de 50 et au-delà du stock (règles actuelles). |
| Panier | Cartes / lignes A-B-C, Modifier, Supprimer (avec confirmation), prix libre borné. |
| Page d'encaissement | Tuiles de modes de paiement, espèces avec monnaie rendue, QR, impression cochée. |
| Bandeau d'état | « Enregistré ✓ », « Envoi… », « Non enregistré — Réessayer ». |

Chaque menu garde **ses règles propres** (client, tiers payants, bons, carnet) et **ses appels serveur actuels**.

## 4. Écrans proposés (voir les maquettes)

### 4.1 Pré-vente / Vente

```
┌──────────────────────────────┐
│ ←  Vente            ⚡ ⋮      │  en-tête bleu (A)
│ Réf. PV-000123 · 3 articles  │
│ ┌──────────────────────────┐ │
│ │ 🔍 Scanner ou rechercher  │ │  champ de scan géant
│ └──────────────────────────┘ │
├──────────────────────────────┤
│ DOLIPRANE 1000MG CP B/8      │
│ 2 × 1 500        3 000 F  ✎ 🗑│  cartes du panier
│ EFFERALGAN 500MG             │
│ 1 × 1 200        1 200 F  ✎ 🗑│
├──────────────────────────────┤
│ Total à payer      4 200 F   │  pied fixe
│ [ ENREGISTRER EN PRÉVENTE ]  │  bouton contour
│ [       ENCAISSER         ]  │  bouton plein
└──────────────────────────────┘
```

- **Plus d'onglets PREVENTE / VENTE** : un seul panier, le choix se fait en bas.
- Onglet / bouton **« Préventes à encaisser »** (liste) : vraie date, recherche par référence **ou client**, confirmation si un panier est en cours.
- Retour arrière avec panier non vide → « La vente reste en prévente, retrouvez-la dans la liste ».

### 4.2 Encaissement (une page)

```
┌──────────────────────────────┐
│ ←  Encaissement              │
│      Total  4 200 F          │
├──────────────────────────────┤
│ [ 💵 Espèces ] [ 📱 Wave   ] │  tuiles des modes activés
│ [ 📱 Orange  ] [ 💳 Carte  ] │
├──────────────────────────────┤
│ Montant reçu   [  5 000   ]  │
│ [Exact] [5 000] [10 000]     │  touches rapides
│ Monnaie à rendre     800 F   │
│ ☑ Imprimer le ticket         │
├──────────────────────────────┤
│ [   VALIDER L'ENCAISSEMENT  ]│
└──────────────────────────────┘
```

- Mode mobile money : **QR affiché sur la même page**.
- Aucun mode activé → message clair + raccourci vers Réglages (au lieu d'un dialogue vide).
- Caisse fermée → message du serveur + « Ouvrir la caisse » (comportement actuel).

### 4.3 Pré-vente Assurance

Barre d'étapes : **Client → Couverture → Produits → Encaissement** (retour possible à chaque étape).

```
┌──────────────────────────────┐
│ ←  Vente assurance           │
│ ① Client ② Couverture ③ Produits ④ Encaisser
├──────────────────────────────┤
│ KOUASSI Awa · Mat. 12345     │  carte client permanente
│ Ayant droit : KOUASSI Junior │
│ MCI 80 % · Bon 45879         │
│ ASCOMA 20 % · Bon 1122       │
├──────────────────────────────┤
│  … panier …                  │
├──────────────────────────────┤
│ Total           10 000 F     │
│ Part MCI (80 %)  8 000 F     │  répartition toujours visible
│ Part client      2 000 F     │  (net recalculé automatiquement)
│ [ ENREGISTRER EN PRÉVENTE ]  │
│ [   ENCAISSER 2 000 F     ]  │  « VALIDER (part client 0 F) » si 0
└──────────────────────────────┘
```

- **Couverture** : ayant droit (choisir / créer), tiers payants (cocher, taux 0-100, changer l'assurance comme aujourd'hui), n° de bon par TP.
- Net **recalculé tout seul** ; tant qu'il n'est pas à jour : « Calcul… » et Encaisser désactivé (jamais d'ancien net envoyé).
- Historique du client : **Reprendre** / **Réimprimer** (avec la vraie référence).

### 4.4 Vente Carnet

Barre d'étapes : **Client → Bon & ayant droit → Produits → Valider**.

- Ayant droit = **le client par défaut** ; liste pour en choisir un autre ; « + Nouvel ayant droit ».
- Création de client carnet : le carnet choisi est **affiché pour relecture**, validation par un bouton.
- Pied : Total / Part carnet / Part client ; « Enregistrer en prévente » ou « Valider ».

### 4.5 Les trois présentations

| | A — Tableau de bord (défaut) | B — Compact | C — Guidé |
|---|---|---|---|
| En-tête | Bleu arrondi, référence + chiffres (articles, total) | Barre blanche sobre | Bleu droit + barre d'étapes |
| Panier | Cartes | Lignes denses (plus d'articles visibles) | Cartes avec bande de couleur |
| Action principale | Bleu | Bleu | Ambre |
| Pour qui | Usage général | Grosses ordonnances, petits écrans | Nouveaux vendeurs |

## 5. Fiabilité et idempotence

| Risque | Protection |
|---|---|
| Double scan du 1ᵉʳ produit → 2 ventes | **Verrou de création** : tant que la vente n'a pas son identifiant, les ajouts suivants attendent dans la file. |
| Double tap sur Ajouter / Modifier / Supprimer | **File d'opérations** : une seule à la fois par vente ; boutons désactivés pendant l'envoi. |
| Réponse perdue (délai dépassé) | **On relit le panier avant de renvoyer** : si la ligne est déjà là, on ne la renvoie pas. |
| Double clôture | Bouton verrouillé + le serveur refuse déjà une vente `is_Closed` ; en cas de délai dépassé, on relit le statut avant de proposer « Réessayer ». |
| Net périmé | Le net est invalidé à chaque changement ; Encaisser exige un net calculé **après** la dernière modification. |
| Vente perdue (appli fermée, session) | La référence de la vente en cours est mémorisée ; à la réouverture : « Reprendre la vente PV-000123 ? ». |
| Erreur inattendue (bug) | Gestionnaire global : écran « Une erreur est survenue — vos données sont conservées », journal local consultable dans Réglages, au lieu d'un plantage. |

### Contrôles de saisie

- Quantité : chiffres seuls, 1 à 9 999 ; > 50 et > stock : confirmation (règles actuelles).
- Prix (libre) : chiffres seuls, 0 à 999 999 999 ; 0 F → confirmation.
- N° de bon : obligatoire, espaces retirés, 30 caractères max, pas de doublon dans la même vente.
- Taux TP : 0 à 100 (1 à 100 à la création, comme aujourd'hui).
- Client / ayant droit : nom obligatoire, nom et prénom envoyés dans le bon ordre.
- Recherche : 60 caractères max, caractères parasites retirés ; ≥ 3 caractères (règle serveur actuelle), indiquée à l'écran.

## 6. Balises de retour arrière

1. **Balise git avant chaque étape** :
   - `ventes-v0-avant-refonte` (état actuel, déjà validé sur le terrain)
   - `ventes-v1-socle`, `ventes-v2-prevente`, `ventes-v3-assurance`, `ventes-v4-carnet`
   - Retour en arrière = reconstruire l'APK à partir de la balise voulue (quelques minutes).
2. **Interrupteur dans Réglages** : « Ventes : nouvelle version / ancienne version ». Les anciens écrans restent dans l'application pendant la période d'essai ; si un problème survient en boutique, on bascule **sans réinstaller**. On le retire seulement quand vous validez.
3. **APK conservée par étape** (artefact CI) pour réinstaller une version précise.
4. **Tests automatiques** à chaque étape : parcours complet de chaque vente (A/B/C, 360 px), double scan, double tap, panne réseau, délai dépassé, réponse perdue, serveur qui refuse (plafond, bon utilisé, caisse fermée).
5. **Essai sur le serveur de test** (Payara + MariaDB) des parcours réels avant chaque APK.

## 7. Plan

| Étape | Contenu | Livrable |
|---|---|---|
| 1 | Socle commun + corrections 1-22 + interrupteur ancienne/nouvelle version + balise `ventes-v0` | APK « ventes v1 » (écrans encore classiques mais fiabilisés) |
| 2 | Pré-vente / Vente : nouvel écran A/B/C, choix final prévente/vente, encaissement 1 page | APK « ventes v2 » |
| 3 | Assurance : étapes, carte client, net automatique, reprise de prévente | APK « ventes v3 » |
| 4 | Carnet : étapes, ayant droit choisir/créer, relecture carnet | APK « ventes v4 » |

Vous testez chaque APK avant qu'on passe à l'étape suivante.
