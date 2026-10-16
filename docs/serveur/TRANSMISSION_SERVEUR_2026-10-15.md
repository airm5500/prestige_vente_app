# Transmission au serveur Prestige — 15/10/2026

**De** : le pharmacien et les trois applications mobiles (Prestige Mobile / PrestigePOS, Prestige Pharmacien,
Prestige Inventaire).
**Pour** : la session qui maintient `airm5500/prestige` (branche `claude/new-session-xm8ptu`).
**En réponse à** : `REPONSE_DEMANDES_MOBILES.md` du serveur (15/10/2026).

**C'est le seul fichier à lire.** Il regroupe, une section par destinataire, les décisions du pharmacien, les
réponses des applications aux questions du serveur et les nouvelles demandes. `DEMANDES_SERVEUR_CONSOLIDEES.md`
(déjà en cours de traitement) n'est pas modifié ; les nouvelles demandes sont numérotées à la suite (43 et
suivantes).

Règles communes inchangées : session habituelle (cookie), 401 sans session, 403 `{interdit:true, msg}` pour un
droit manquant, `X-Client-Ref` pour l'anti-doublon, ajouts rétrocompatibles (les applications gardent un repli
sur un serveur qui n'a pas encore la nouveauté).

## Sommaire

1. Décisions du pharmacien (questions de la partie 3)
2. Prestige Mobile et PrestigePOS : réponses et demandes 43, 44, 51, 52 (pointage, 16/10)
3. Prestige Pharmacien : réponses et demande 45
4. Prestige Inventaire : réponses et demandes 46 à 50
5. Récapitulatif des nouvelles demandes

---

## 1. Décisions du pharmacien

| N° | Question du serveur | Décision |
|---|---|---|
| 12 | `P_BL_MOBILE_VALIDER_AVEC_ECART` : que fait `validerbl?avecEcart=true` ? | **Refuser** la validation tant que des lignes ne sont pas saisies, avec un message qui **nomme les produits manquants** (« Produits non saisis : … »). |
| 12 | `P_BL_MOBILE_SCANNER` sur `add-lot` / `creerbl` (routes partagées avec l'écran web) | Donner ce droit **à tous les profils qui ont le menu BL** (rien ne doit être bloqué au poste). Aucun en-tête d'application n'est donc nécessaire. |
| 17 D7 | Motif différent sur un produit déjà dans le retour | Normalement un produit n'a qu'un motif sur un même BL. Si cela arrive : **option 1** (une ligne par produit, motif et lot), **avec un message** : « Vous avez ajouté ce produit avec un motif différent ». |
| 36 D18 | Refuser une boîte dont le numéro de série a déjà été scanné | **Oui** : `SERIE_DEJA_CONSOMMEE` « Boîte déjà scannée » ; l'application Mobile enverra `serie` et `gtin`. |
| 24 | `GET pilotage/controler` écrit en base | **Laisser tel quel.** |
| 32 | Écrans / paramètres « id1,id2 » (choix multiples) | **CA par emplacement** (plusieurs emplacements à la fois). |
| 38 | Pagination du Suivi des ajustements | **Oui, paginer.** |
| 38 | « Racheté » dans les rappels | **Marqué à la main.** |
| 38 | Actualisation des rappels | **À la demande, avec un bouton** (pas d'actualisation programmée). |
| 39 | Garder quelques minutes le calcul d'une garde pour les pages suivantes | **Oui.** |
| 34 | Lecture de colonnes nominatives (fiche client agrégée) | **Accord donné** pour les essais (aucune donnée de patient dans les journaux ni dans les tests versionnés). La route agrégée n'est toutefois plus nécessaire (voir § 2, n° 34). |
| 2 | Droit de `POST pharma/reponses` | Avis des applications (aucune ne l'appelle) : **droit des commandes** (`P_SM_COMMANDE_PROCESS` ou celui déjà vérifié sur l'envoi), pas une lecture libre. |
| 10 | `droits.creerInventaire` | Quand le serveur le donne, **c'est lui qui décide** qui peut créer un inventaire (le réglage du terminal ne sert plus qu'avec un ancien serveur). |

---

## 2. Prestige Mobile et PrestigePOS (`prestige_vente_app`, 4.3.0+16 ; PrestigePOS 1.1.0+2)

### Réponses aux questions

**N° 12 — reconnaître un appel mobile.** Possible partout (`X-App: prestige-mobile/<version>`,
`X-App: prestigepos/<version>`), mais **plus nécessaire** puisque le droit est donné à tous les profils BL. Ce
n'est qu'un aiguillage (un en-tête se recopie), et les versions installées ne l'enverraient pas.

**N° 33 — Réserve : ajout d'une ligne.** La forme proposée convient :
`POST v1/suggestion-reserve/{id}/lignes {produitId, quantite}` + `X-Client-Ref`, suggestion `A_TRAITER` ou
`EN_COURS`, verrou détenu.
- `produitId` = `lg_FAMILLE_ID` (déjà utilisé à la création : `items:[{lg_FAMILLE_ID, int_QTE}]`) ;
- produit déjà présent : refus `code:"DEJA_PRESENT"` (l'application proposera de modifier la quantité par
  `PUT …/ligne/{detailId}/quantite`) ;
- réponse : la ligne créée, au format des lignes de `PUT {id}/ouvrir` ;
- autre emplacement ou suggestion annulée : même refus que `ouvrir`.

**PDF REST : plus voulu**, la demande est retirée.

**N° 34 — fiche client agrégée : plus nécessaire.** Les écrans n'affichent ni tiers payants ni ayants droit,
l'identité est en lecture seule et déjà fournie par `GET ordonnance-client/client/{id}/dossier`, et aucun
fichier n'est déposé. Demande retirée (au plus : `adresse` dans `…/dossier`, si le pharmacien veut l'afficher).

**N° 35 — posologie usuelle : demande retirée** (aucun écran). `posos/historique` et `posos/interaction` seront
utilisés dans une version suivante.

### Ce que l'application utilise (avec repli sur un serveur ancien)

| N° | Utilisation |
|---|---|
| 4, 5 | `reserve/droits` décide du menu Réserve ; `posos/droits` masque l'Analyse posologie si `analyser` est faux |
| 10, 11 | `role.libelle` affiché ; message « Activez la licence après connexion d'un administrateur » |
| 18 | `X-Client-Ref` sur `add-lot` et `retourfournisseur/add-item` envoyés hors ligne |
| 28 | suggestion annulée en lecture seule, d'un autre emplacement « introuvable » |
| 31 | `id` et `controle` dans `POST rh/pointages`, photo par `POST rh/pointages/{id}/photo` |
| 403 | `{interdit:true, msg}` affiché, jamais une déconnexion |
| 6, 37 | sans objet (pas d'annulation de vente clôturée, pas de versement d'inventaire dans cette application) |
| 36 | écrans D10–D16 à construire dans une version suivante ; **D18 fait en 4.3.1** : `serie` (AI 21) et `gtin` (AI 01) envoyés sur `commande/add-lot` quand la boîte scannée est un DataMatrix GS1 qui les porte (en ligne et file hors ligne) ; `SERIE_DEJA_CONSOMMEE` → « Boîte déjà scannée », rien d'ajouté, ligne refusée à la synchro sans renvoi ; serveur `dev` : champs inconnus ignorés (JSON-B), et un éventuel 400 renvoie le même lot sans série |

### Demande 43 — Empreintes des employés partagées entre terminaux de pointage (P2)

**Pourquoi.** L'empreinte d'un employé (Sunmi V3H, lecteur Aratek A400) est stockée **uniquement sur le
terminal** où elle a été prise. Avec plusieurs terminaux, il faut enrôler chaque employé sur chacun. Le
pharmacien veut l'enregistrer une fois, la conserver sur le serveur et la faire reconnaître partout.

**Quoi.**
- Table `t_employe_empreinte` : `id`, `employe_id`, `modele` (octets du gabarit, **chiffré au repos**, clé hors
  base), `format` (ex. `SUNMI_A400_RAW`), `capteur`, `doigt`, `consentement_le`, `consentement_par`,
  `dt_creation`, `dt_suppression`.
- `POST v1/rh/employes/{id}/empreintes` `{modeles:[base64], format, capteur, doigt, consentement:{le, par}}`
  (droit RH, `X-Client-Ref`).
- `GET v1/rh/empreintes?depuis=<horodatage>&format=<format>` : modèles des employés actifs + suppressions
  depuis la date (droit RH ou terminal de pointage enregistré).
- `DELETE v1/rh/employes/{id}/empreintes` ; purge quand un employé devient inactif.
- Journal d'audit ; jamais de modèle dans les journaux ni les exports ; HTTPS recommandé ; paramètre
  d'activation désactivé par défaut.

**Obligations (ARTCI, loi 2013-450).** Donnée biométrique : déclaration ARTCI, consentement écrit (déjà
recueilli pour la pointeuse existante de la pharmacie), alternative badge, conservation limitée, droit
d'effacement.

**Vérification.** Enrôler sur un V3H, lire `GET v1/rh/empreintes` sur un second, y pointer par empreinte ;
employé désactivé → plus de modèle renvoyé.

### Demande 44 — Performance de `GET /info` (P2, Mobile et Pharmacien)

`GET v1/info?search=doli` ne répond pas en 10 s alors que `GET v1/vente/search` répond immédiatement ; même
pour un seul produit, `/info` reste lent. Détail : `DEMANDE_PERFORMANCE_INFO.md`. Limiter les calculs au(x)
produit(s) demandé(s) (pas d'agrégat des ventes de tout le catalogue), index adaptés, et une ligne en erreur ne
doit pas vider toute la réponse.

**Vérification.** `GET v1/info?search=<CIP exact>` < 1 s ; `GET v1/info?search=doli` < 3 s.

### Pointage présence — décisions du pharmacien du 16/10/2026 (Prestige Mobile 4.4.0)

Constat sur le terrain (captures du pharmacien) : un téléphone gardait le jeton `v1/mobile` du compte « NEMA »
alors que l'application était ouverte par « EMMANUEL » : le pointage partait au nom de NEMA (un bandeau le
signalait seulement). Décisions, déjà appliquées dans l'application 4.4.0 :
- **a) jeton `v1/mobile` lié au compte de l'application** : jeton d'un autre compte effacé à l'ouverture ;
  connexion `v1/mobile` automatique si le mot de passe de CE compte est mémorisé (« Rester connecté »), sinon
  mot de passe seul, identifiant pré-rempli non modifiable ; aucune connexion acceptée pour un autre identifiant ;
  chaque appel revérifie le lien. Aucun changement serveur nécessaire pour a).
- Photo du badge : caméra avant ouverte dès l'arrivée sur le terminal et gardée prête, délai 10 s, attente de la
  libération du scanner arrière, motif détaillé dans l'écran Photos (application seulement).
- Présences, Photos de contrôle et Empreintes (enrôlement) : réservés à l'administrateur de l'application
  (compte « admin » ou `GET v1/roles/est-admin` → `authorize`). Terminal toujours ouvert aux comptes `P_SM_RH`.
- Intervalle entre deux pointages : **2 minutes, inchangé**.

Deux demandes en découlent.

### Demande 51 — Pointer avec la session de l'application (P2)

**Pourquoi.** La voie `v1/mobile` exige une seconde connexion (jeton Bearer de 12 h par téléphone) alors que
l'employé est déjà connecté à l'application : c'est la source de la confusion NEMA / EMMANUEL. Avec la session
de l'application, le pointage va **toujours** au compte connecté, sans second mot de passe.

**Quoi** (mêmes contrôles que `v1/mobile`, mais sur la session habituelle — cookie — **sans `P_SM_RH`**) :
- `GET v1/rh/moi` → même corps que `GET v1/mobile/moi` : `{success, utilisateur:{id, login, nom},
  employe:{id, matricule, nom}|null, droits:{pointage, photos}, pointage:{qr, gps}}` pour l'utilisateur DE LA
  SESSION (jamais un `id` reçu en paramètre).
- `POST v1/rh/moi/pointages` `{sens?, code?, latitude?, longitude?, precision?}` (+ `X-Client-Ref`) → même
  réponse que `POST v1/mobile/pointages` `{success, sens, heure, message}` ; source `MOBILE` (ou `APPLI`),
  appareil = nom du terminal si connu. **Mêmes contrôles** : QR du moment (`KEY_MOBILE_QR`), position
  (`KEY_MOBILE_GPS`, rayon), refus « moins de 2 minutes », sens automatique (inverse du dernier pointage sur
  16 h), heure du serveur, employé actif rattaché au compte, module activé (`KEY_MOBILE_ACTIF`).
- `GET v1/rh/moi/pointages` → mes pointages des 16 dernières heures (comme `GET v1/mobile/pointages`).
- 401 sans session ; `{success:false, message}` pour un refus métier ; 403 `{interdit:true, msg}` si le
  pointage par téléphone est refusé à ce compte.

**Côté application** (version suivant la livraison de la route) : « Mon pointage » utilisera la session, sans
jeton ni seconde connexion ; route absente (404 Payara vérifié par `/officine`) → voie `v1/mobile` liée au
compte (a), comme en 4.4.0.

**Sécurité / vérification.**
- Le compte pointé est TOUJOURS celui de la session : aucun paramètre ne permet de pointer pour un autre
  employé (test : envoyer `employeId` ou `login` d'un autre compte dans le corps → ignoré, pointage au nom de la
  session).
- Deux sessions (NEMA puis EMMANUEL) sur le même appareil → chaque pointage au nom de sa session.
- Refus < 2 min identique à `v1/mobile` ; QR expiré refusé ; position hors rayon refusée si exigée.

### Demande 52 — Droit distinct « P_RH_POINTER » pour le terminal de pointage (P2)

**Pourquoi.** Aujourd'hui, tout le terminal (`v1/rh/...`) exige `P_SM_RH`, qui ouvre aussi la gestion RH
(planning, absences, tableaux, import, suppression de pointages). Le pharmacien veut qu'un compte « terminal »
puisse seulement pointer.

**Quoi.**
- Nouveau privilège `P_RH_POINTER` (libellé « Pointer au terminal de pointage »), attribuable à un rôle.
- Routes accessibles avec `P_RH_POINTER` **ou** `P_SM_RH` : `GET v1/rh/droits`, `GET v1/rh/employes` (lecture
  seule : id, matricule, nom, prénoms, badge, statut — rien d'autre), `POST v1/rh/pointages` (saisie terminal,
  mêmes contrôles), `POST v1/rh/pointages/{id}/photo`, `GET v1/rh/empreintes` (demande 43, si le partage est
  activé). Toutes les autres routes `v1/rh` restent réservées à `P_SM_RH`.
- `GET v1/rh/droits` → `{success:true, pointer:true, gerer:<P_SM_RH>, valider, photoRetentionJours}` ;
  sans aucun des deux droits : `{success:false, message}` comme aujourd'hui.

**Côté application** (4.4.0, déjà prêt) : `success:true` ouvre le terminal, avec ou sans `pointer`/`gerer`
(un serveur sans `P_RH_POINTER` répond comme avant : repli `P_SM_RH`) ; le message de refus cite les deux droits.
Présences, photos et empreintes restent à l'administrateur de l'application, quel que soit `gerer`.

**Vérification.** Compte avec seulement `P_RH_POINTER` : `GET v1/rh/employes` et `POST v1/rh/pointages` → OK ;
`GET v1/rh/presence`, `GET v1/rh/tableau`, `POST v1/rh/planning`, `DELETE v1/rh/pointages/{id}` → 403.
Compte sans aucun des deux : `GET v1/rh/droits` → `success:false`.

---

## 3. Prestige Pharmacien (`prestige_app`, 3.10.1+42)

### Réponses aux questions

**N° 2 — `POST pharma/reponses`.** L'application n'utilise aucune route `pharma/…` (aucune commande PharmaML
depuis le mobile). Avis : droit des commandes (voir § 1).

**N° 26 — `checked` de Visualisation BL : rien à faire côté serveur.**
- L'ancienne interface envoie `checked` = `TERMINE`, `NON_TRAITE` ou `EN_COURS` (texte, statut du contrôle du BL).
- La nouvelle interface envoie `checked` vide et utilise `statutControle=CONTROLE|NON_CONTROLE`, ce qui est exactement le
  filtre attendu (`TERMINE` ↔ `CONTROLE`, `NON_TRAITE` + `EN_COURS` ↔ `NON_CONTROLE`).
- `userId` est utilisé (filtre « Utilisateur » remis, seulement sur un serveur récent).

### Ce que l'application utilise (avec repli)

| N° | Utilisation |
|---|---|
| 9 | `user/droits` non utilisée : le `role` reçu à la connexion suffit |
| 22 | `?marquerLu=false` : bouton « Actualiser » du détail d'un avis |
| 23 | « Commandes en cours à jour le … » dans Prévisions |
| 25 | `detailMobile` : Mobile Money par opérateur dans le CA Global et le Détail CA |
| 26 | `userId`, `groupeId` sur `etat-control-bon/list` |
| 29 | routes `/nombre` non utilisées (aucun écran ne charge une liste pour compter) |

**Annulation.** L'ancienne idée « Pointage BL : tous les grossistes » (`tous=true`) est **annulée** ; elle
n'avait pas été transmise. Le pharmacien raisonne par grossiste ou par groupe de grossistes.

### Demande 45 — Pointage BL : grossiste sur chaque pièce et montant de chaque grossiste d'un groupe (P2)

**Pourquoi.** `GET /pointage-bl?groupe=<id>` fonctionne déjà (`PointageBLRessource.criteres`,
`PointageBLService.grossistesDuGroupe`, groupes par `GET /common/groupefournisseurs`). Mais les pièces ne disent
pas à quel grossiste elles appartiennent, et la réponse ne donne que le total du groupe. Le pharmacien doit
refaire la recherche grossiste par grossiste.

**A. Sur chaque pièce** (recherche par grossiste ou par groupe) : `grossisteId` (`t_grossiste.lg_GROSSISTE_ID`)
et `grossiste` (`str_LIBELLE`). Le grossiste est connu dans la boucle
`for (String g : grossistes) toutes.addAll(pieces(g, …))` de `PointageBLService.liste`.

**B. Recherche par groupe seulement** (`groupe` sans `grossiste`) : tableau `parGrossiste`, un élément par
grossiste du groupe ayant au moins une pièce sur la période, trié par libellé :

```json
"parGrossiste": [
  {"grossisteId": "G1", "libelle": "COPHARMED", "totalBl": 1250000, "totalAvoirs": -35000, "net": 1215000,
   "pieces": 14, "pointes": 9, "nonPointes": 5}
]
```

Règles :
- mêmes règles que les totaux actuels : montants HT entiers, avoirs en négatif, `net = totalBl + totalAvoirs` ;
- pièces `RECEPTION` comptées dans les montants et dans `pieces`, pas dans `pointes` / `nonPointes` ;
- calcul sur toutes les pièces de la période **quel que soit `etat`** ;
- les sommes égalent les totaux du groupe ;
- recherche par grossiste : pas de `parGrossiste`.

**C. Facultatif** : dans `GET /pointage-bl/pdf` d'un groupe, une colonne « Grossiste » et un sous-total par
grossiste.

**Compatibilité.** L'application 3.10.0 et suivantes est déjà prête : elle affiche « Par grossiste du groupe »
si `parGrossiste` est présent. Sinon, elle le calcule à partir de `grossisteId`. Sinon, elle indique que ce
serveur ne le fournit pas encore.

**Vérification.**
```
curl -s -b cj "$B/pointage-bl?groupe=<groupe de 2 grossistes>&du=2026-10-01&au=2026-10-15&etat=TOUS"
curl -s -b cj "$B/pointage-bl?groupe=<même groupe>&du=2026-10-01&au=2026-10-15&etat=NON_POINTES"
curl -s -b cj "$B/pointage-bl?grossiste=<un grossiste du groupe>&du=2026-10-01&au=2026-10-15&etat=TOUS"
```

Résultats attendus :
- chaque pièce a son grossiste ;
- les sommes de `parGrossiste` égalent les totaux ;
- `parGrossiste` est identique entre `TOUS` et `NON_POINTES` ;
- la recherche par grossiste n'a pas de `parGrossiste`, et ses montants égalent l'élément du même grossiste.

---

## 4. Prestige Inventaire (`prestinv`, 4.15.0+14)

### Ce que l'application utilise (avec repli)

| N° | Utilisation |
|---|---|
| 10 | `droits.creerInventaire` décide qui crée ; 403 `interdit` → « Droit manquant : Créer un inventaire » |
| 20 | `lgInventaireId` utilisé directement |
| 21 | 500 → « Erreur du serveur », jamais une liste vide |
| 30 | `rayons/etat` : emplacements et état de tous les rayons en une requête |
| 37 | versement en lots de 200 avec `cle` gardée sur le terminal ; `inconnu` / `ambigu` repris produit par produit |
| 8 | 404 / 409 / 400 / 403 de `PUT ws/inventaires/details` : refus lisible, jamais renvoyé en boucle |

**Contradiction 3 (PUT details exige une session) : vérifié.**
- Depuis la 4.9, une quantité est écrite sur le terminal avant l'envoi, et un 401 la garde en attente jusqu'à la reconnexion.
- Les terminaux antérieurs à la 4.9 doivent être mis à jour.

**Inventaire créé depuis une collecte (décision du pharmacien).** « 4 produits de 4 emplacements → comme
Prestige : emplacement = tous, l'inventaire des 4 produits, et à l'ouverture seulement leurs emplacements. »
L'application reprend la méthode de l'**inventaire unitaire** de Prestige :
1. recherche de chaque code (`GET v1/produit-search/fiche`) ;
2. création sur les emplacements de ces produits, toutes les lignes non retenues ;
3. `POST v1/inventaire/lignes/retenue` des seuls produits collectés.

Sur un serveur sans `lignes/retenue`, l'application **refuse la création** (décision du pharmacien).

### Demande 46 — Créer un inventaire limité à une liste de produits, en une requête atomique (P1)

**Constat.**
- La méthode actuelle demande 3 requêtes et n'est pas atomique : une coupure entre la création et la retenue laisse un inventaire vide.
- Elle insère aussi tous les produits des emplacements concernés : des milliers de lignes inutiles pour 4 produits.

**Demande.** Champ facultatif `produits` dans `POST v1/inventaire/creation` :

```json
POST /api/v1/inventaire/creation
{"str_NAME":"Collecte du 15-10-2026 09.30","str_TYPE_TRANSACTION":"Emplacement",
 "produits":["<lg_FAMILLE_ID>","3400930000001","8050457"]}
→ {"success":1,"lignes":2,"lgInventaireId":"…","libelle":"…","inconnus":["8050457"]}
```

- `produits` non vide : l'inventaire ne contient que ces produits.
  - une ligne par produit, à l'emplacement de stock de l'utilisateur, stock théorique repris ;
  - les lignes sont retenues dans la même transaction ;
  - chaque élément est un `lg_FAMILLE_ID` ou un code tel que scanné, avec les mêmes règles que le versement (37).
- `inconnus` liste les éléments non retrouvés ou ambigus. S'ils sont tous inconnus : refus, aucun inventaire.
- `produits` absent : comportement actuel. `valeurs` reste possible en plus (intersection).
- Limite de 500 produits (413 au-delà). Droit `P_CREER_INVENTAIRE`.
- Détection par l'application : la réponse contient `inconnus`, même vide.

### Demande 47 — `ws/inventaires/rayons` et `inventaire/criteres` : seulement les rayons à compter (P2)

**Constat.** `fetchRayon` et `criteresInventaire` groupent toutes les lignes, retenues ou non. Un inventaire
unitaire fait dans Prestige montre donc tous les emplacements de l'officine, presque tous vides.

**Demande.**
- Ajouter `AND o.boolINVENTAIRE = true` à `fetchRayon`.
- Pour `rayons/etat` : `HAVING totalProduits > 0`, ou un paramètre `aCompter=1`.

Sans effet sur les inventaires ordinaires.

### Demande 48 — `POST v1/inventaire/lignes/retenue` : droit et session (P1, sécurité)

**Constat.**
- La route ne vérifie aucun droit : toute session peut retenir ou écarter des lignes de n'importe quel inventaire ouvert, et donc changer ce qui sera clôturé.
- Sans session, elle répond 200 au lieu de 401.

**Demande.**
- Droit `P_CREER_INVENTAIRE`, ou celui du menu « Travaux d'inventaire » → 403 `{interdit:true, msg}`.
- Inventaire clôturé → 409 `INVENTAIRE_CLOTURE`.
- Sans session → 401.

L'application gère déjà ces trois réponses.

### Demande 49 — Versement en lot (37) : autres formes du code (P3, facultatif)

Avant de répondre `inconnu`, essayer aussi l'EAN-13 tiré d'un GTIN-14 (`0` + EAN-13), et le CIP7 tiré d'un
EAN-13 `34009 + CIP7 + clé`.

Exemple : `3400935955838` d'un produit au CIP7 `3595583` → `ok`.

### Demande 50 — Rappel de la demande 27 : lecture de l'auteur des saisies (P2)

Toujours attendu : `auteurId`, `auteurLogin`, `auteurNom` dans les 7 routes `ws/inventaires/details*`
(l'écriture est faite). L'application les affichera dans l'historique et les écarts.

### Tests serveur suggérés (Inventaire)

1. **46** :
   - listes `produits` de 1, 4 (sur 4 emplacements) et 500 éléments → exactement ces lignes, retenues ;
   - `rayons` → leurs emplacements seulement ;
   - coupure au milieu → aucun inventaire ;
   - 501 éléments → 413.
2. **47** :
   - inventaire unitaire avec 3 lignes retenues sur 2 emplacements → `rayons` = ces 2 emplacements ;
   - inventaire ordinaire → inchangé.
3. **48** : sans le droit → 403 ; inventaire clôturé → 409 ; sans session → 401.
4. **49** : `3400935955838` → `ok`.

---

## 5. Récapitulatif des nouvelles demandes

| N° | Demande | Application(s) | Priorité |
|---|---|---|---|
| 43 | Empreintes partagées entre terminaux de pointage | Mobile | P2 |
| 44 | Performance de `GET /info` | Mobile, Pharmacien | P2 |
| 45 | Pointage BL : grossiste par pièce, `parGrossiste` d'un groupe | Pharmacien | P2 |
| 46 | Création d'inventaire limitée à des produits, atomique | Inventaire | P1 |
| 47 | Rayons limités aux lignes retenues | Inventaire | P2 |
| 48 | `lignes/retenue` : droit, 409, 401 | Inventaire | P1 (sécurité) |
| 49 | Versement : GTIN-14 et EAN-13 `34009…` | Inventaire | P3 |
| 50 | Auteur des saisies en lecture (rappel 27) | Inventaire | P2 |
| 51 | Pointer avec la session de l'application (`GET v1/rh/moi`, `POST v1/rh/moi/pointages`, sans `P_SM_RH`) | Mobile | P2 |
| 52 | Droit distinct `P_RH_POINTER` (terminal : lecture des employés + pointage) | Mobile | P2 |

Plus les décisions du § 1, qui débloquent : 12 (deux points), 17 D7, 24, 32, 38, 39, 36 D18.
