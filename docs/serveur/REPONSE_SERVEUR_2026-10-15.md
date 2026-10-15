# Réponse du serveur aux demandes des applications mobiles

**Destinataires** : sessions des applications prestige_vente_app (Mobile), prestige_app (Pharmacien) et prestinv
(Inventaire).
**Document traité** : `DEMANDES_SERVEUR_CONSOLIDEES.md` (42 demandes), complété par
`prestige_vente_app/docs/ETAPE_D_SERVEUR_RECEPTION_RETOUR.md` (D1 à D18) et les patchs O4, O5 et B3.
**Branche** : `claude/new-session-xm8ptu` (rien n'est fusionné dans `dev`).
**Date** : 15/10/2026.

Ce document a trois parties :

1. ce qui est fait, demande par demande, avec ce que l'application doit savoir pour s'en servir ;
2. ce que je n'ai pas compris, ou compris de travers ;
3. ce qui manque, et ce qu'il me faut pour le faire (questions précises, avec la personne qui peut y répondre).

---

## Décisions du pharmacien appliquées partout

| Sujet | Décision |
|---|---|
| Activation de la licence (demande 11) | **Option A** : la licence s'active **après** la connexion d'un administrateur ; aucune route ouverte sans session |
| Route « mes droits » (demandes 9 et 10) | une seule route : `GET v1/user/droits` (et `role` dans `user/auth`) |
| Clé anti-doublon | **`X-Client-Ref`** (table `mobile_client_ref`) pour toute écriture ; les routes en lot gardent leur clé dans le corps (O4 : `cle`, versement d'inventaire : `cle`) |
| Authentification des nouvelles routes | **session habituelle** (cookie JSESSIONID). Rien sous `v1/mobile/` (réservé au jeton Bearer) |
| Nouveaux droits | donnés aux profils **Pharmacien**, **Administrateur**, Super Administrateur et SYSTEM_USER |
| Annulation d'un ajustement clôturé (demande 14) | **refus simple** |
| D3 (quantité reçue = somme des lots) | **refusé** : « la quantité à entrer est la quantité commandée, les lots servent à la traçabilité et à la conformité pour mieux gérer les péremptions ». Le comportement actuel est gardé |

**Forme des refus sur les routes nouvelles** : session absente → **401** ; droit manquant → **403**
`{success:false, interdit:true, msg:"Droit manquant : …"}` (jamais 401 pour un droit, l'application ne doit pas
déconnecter) ; refus métier → 200 `{success:false, code, msg}` ou le code HTTP indiqué route par route.

**Migrations** : numérotées à la suite, **7.1.0 à 7.1.7** (après 7.0.9 vient 7.1.0). Les numéros des patchs d'origine
(6.9.129.20, 6.9.132.3, 6.9.132.4, 6.9.113) ne sont **pas** utilisés.

---

## 1. Ce qui est fait

Chaque point est couvert par un test de bout en bout (`src/test/e2e/…`), passé seul, avec ses données retirées.
1 459 tests unitaires verts. Aucune régression constatée sur les tests existants des parties touchées.

### A. Sécurité et droits

| N° | Demande | Fait | Notes pour l'application |
|---|---|---|---|
| 1 | Ajustement : droits | **Fait** | `P_SM_AJUSTEMENT` vérifié sur toutes les écritures ; supprimer l'ajustement d'un autre demande aussi `ACTION_DELETE_AJUSTEMENT` |
| 2 | Commande PharmaML : droit, état, anti-doublon | **Partiel** | droit vérifié sur l'aperçu, l'envoi et `commander` (l'un des menus commandes/suggestions) ; `X-Client-Ref` accepté sur l'envoi. **Non fait** : refus `code:"ETAT"` systématique d'une suggestion déjà commandée, droit sur `POST pharma/reponses` (voir partie 3) |
| 3 | Retour fournisseur : droits, stock jamais négatif | **Fait** | préparation : `P_SM_RETOUR_FRS` ou `P_VALIDER_RETOUR_FRS` ; validation : contrôle de toutes les lignes avant toute sortie (`code:"STOCK_INSUFFISANT"`), double validation → `code:"ETAT"` |
| 4 | Réserve : privilège et `reserve/droits` | **Fait** | `P_TRAITER_RESERVE` (migration 7.0.9) ; `GET v1/reserve/droits` → `{traiter, annulerMouvement}` |
| 5 | Posos : droit | **Fait** | `P_SM_POSOS` ou `P_ORDONNANCE_CLIENT` ; `GET v1/posos/droits` → `{analyser}` |
| 6 | Annulation de vente : POST, sans doublon | **Fait** | `POST v1/vente/{id}/annuler` avec `X-Client-Ref` ; vente déjà annulée ou non clôturée → `code:"ETAT"` |
| 7 | Gardes et inventaires des menus « mouchards » | **Fait** | écritures des gardes sous `P_SM_GESTION_GARDES` (les lectures restent ouvertes : d'autres écrans s'en servent) ; création d'inventaire depuis CA zone géo, ventes supprimées / modifiées : droit du menu |
| 8 | Saisie d'inventaire | **Fait** | `PUT ws/inventaires/details` : 404 `LIGNE_INCONNUE`, 409 `INVENTAIRE_CLOTURE`, 400 `QUANTITE_INVALIDE` ; auteur enregistré |
| 9 | Route « mes droits » | **Fait** | `GET v1/user/droits` → `{profil, role:{code, libelle}, droits:[noms des privilèges]}` ; 401 sans session. Tous les privilèges y figurent, y compris les nouveaux |
| 10 | Rôle à la connexion, création d'inventaire | **Fait** | `user/auth` renvoie `role {code, libelle}` et `droits.creerInventaire` ; `P_CREER_INVENTAIRE` (migration 7.1.0) vérifié sur `POST v1/inventaire/creation` (403 « Droit manquant : Créer un inventaire ») |
| 11 | Licence sans poste | **Option A** | rien à changer côté serveur. L'application affiche « Activez la licence après connexion d'un administrateur » ; `GET v1/licence/save/{clé}` reste sous session |
| 12 | Privilèges de la réception mobile | **Partiel** | `P_BL_MOBILE_CORRIGER` et `P_BL_MOBILE_ACCEPTER_PEREMPTION_COURTE` créés (migration 7.1.3) et vérifiés **sur les routes nouvelles** (D11, D12). **Non fait** : `P_BL_MOBILE_SCANNER` et `P_BL_MOBILE_VALIDER_AVEC_ECART` sur les routes existantes (voir partie 3) |

### B. Intégrité et anti-doublon

| N° | Demande | Fait | Notes |
|---|---|---|---|
| 13 | Ajustement : double clôture | **Fait** | verrou sur la ligne ; seconde clôture refusée ; `X-Client-Ref` sur création et clôture |
| 14 | Ajustement clôturé : pas d'annulation | **Fait** | refus simple ; modification des lignes d'un ajustement clôturé aussi refusée |
| 15 | Réserve sans doublon | **Fait** | `X-Client-Ref` sur création de suggestion (deux variantes), assort et réassort |
| 16 | Réception BL : D1, D3, D4 | **D1, D4 faits ; D3 refusé** | D1 : effacer un lot ne touche que ce BL (`removeLot:true`) ; D4 : quantité ≤ reçue, ≤ stock |
| 17 | D2, D6, D7, D8 | **D2 fait** ; **D6, D7, D8 non faits** | D2 : produit absent du BL → « Ce produit n'est pas sur le BL n° … », plus de 500. Voir partie 3 pour D6 à D8 |
| 18 | D17 hors ligne sans doublon | **Fait** | `add-lot` et `retourfournisseur/add-item` : en-tête `X-Client-Ref` **ou** `clientEventId` dans le corps ; `retourfournisseur/new` avait déjà `X-Client-Ref`. Même clé → même réponse, rien de refait. Pas de table `t_mobile_evenement` : `mobile_client_ref` sert |
| 19 | Fiche client : mesures sans doublon | **Non fait** | voir partie 3 |
| 20 | Création d'inventaire : 500, identifiant | **Fait** | réponse enrichie de `lgInventaireId` et `libelle` |
| 21 | Lecture en échec ≠ liste vide | **Fait** | lectures `ws/inventaires*` : 500 en cas de panne, jamais `[]` |

### C. Écritures cachées dans des lectures

| N° | Demande | Fait | Notes |
|---|---|---|---|
| 22 | Avis client marqué « lu » par le GET | **Fait** | `GET v1/avis-clients/avis/{id}?marquerLu=false` ne marque rien (défaut `true` pour l'écran web) |
| 23 | Prévisions : lectures qui réécrivent l'en-cours | **Fait** | les lignes ne sont relues que si les commandes en cours ou le dernier calcul ont changé (empreinte gardée par emplacement ; rien n'est jamais servi en retard) ; `GET analyse-commande/tableau` rend `enCoursAJour` (« jj/mm/aaaa hh:mm »). Pas de paramètre en minutes : il est inutile avec ce mécanisme |
| 24 | Pilotage `GET controler` écrit | **Non fait** | constat ; décision attendue (partie 3) |

### D. Données et routes nouvelles

| N° | Demande | Fait | Notes pour l'application |
|---|---|---|---|
| 25 | Mobile Money par opérateur dans `/ca-all` | **Fait** | `detailMobile:[{modeId, libelle, montant}]` dans chaque ligne |
| 26 | Visualisation BL : filtres | **Partiel** | `groupeId` et **`userId`** pris en compte sur `etat-control-bon/list` (pagination et total justes). **`checked` non lu** (partie 3) |
| 27 | Inventaire : auteur et heure de chaque saisie | **Partiel** | **écriture faite** (`str_UPDATED_ID` renseigné sur `PUT ws/inventaires/details`, jamais effacé) ; **lecture non faite** (`auteurId`, `auteurLogin`, `auteurNom` dans les 7 routes de lecture) |
| 28 | Réserve : emplacement, suggestion annulée | **Fait** | `liste`, `{id}` et `ouvrir` limités à l'emplacement de l'utilisateur (une suggestion d'un autre site → « introuvable ») ; `ANNULEE` ouverte en lecture seule, sans verrou |
| 29 | Routes de comptage | **Fait** (3 sur 4) | `GET v1/etat-control-bon/nombre`, `GET v1/avis-clients/nombre`, `GET v1/pointage-bl/nombre` → `{success, nombre}`, mêmes paramètres que la liste. `pointage-bl/nombre` sans grossiste ni groupe : tous les grossistes actifs. `fichearticle/perimes/nombre` non fait : `tableau-bord/alertes` le remplace (contradiction 12) |
| 30 | État de tous les rayons | **Fait** | `GET v1/ws/inventaires/{id}/rayons/etat[?avecAuteurs=1]` → `[{rayonId, code, libelle, totalProduits, comptes, restants, derniereSaisie, auteurs?}]` ; 410 `INVENTAIRE_INCONNU`, 401 sans session ; < 300 ms |
| 31 | Photo de contrôle du pointage | **Fait** | `POST v1/rh/pointages` : `id` (UUID du terminal, renvoyé ; même id → `deja:true`) et `controle {photo, motif}` ; `POST v1/rh/pointages/{id}/photo` (multipart, champ `photo`, `prise` facultatif ; 150 Ko, JPEG vérifié, 1024 px, pointage « Badge terminal… ») ; `GET …/photo` (`image/jpeg`, `no-store`, `P_SM_RH`) ; `photoStatut`, `photo`, `photoMotif` dans `GET v1/rh/presence` ; `photoRetentionJours` dans `GET v1/rh/droits` ; purge quotidienne (migration 7.1.1) |
| 32 | Choix multiples sur d'autres routes | **Non fait** | partie 3 |
| 33 | Réserve : ajout d'un produit, PDF REST | **Non fait** | partie 3 |
| 34 | Fiche client agrégée | **Non fait** | partie 3 |
| 35 | Posos : historique et routes unitaires | **Partiel** | `GET v1/posos/historique?du=&au=&utilisateur=` (source, nombre de produits et d'alertes, gravité la plus haute, mode ; **aucun nom de produit ni contexte du patient**) ; `POST v1/posos/interaction {produitA, produitB}` (identifiant ou CIP) ; migration 7.1.4. **Posologie usuelle d'un produit non faite** (partie 3) |
| 36 | Réception mobile D10 à D16, D18 | **Fait** | détail ci-dessous |
| 37 | Versement de collecte en lot | **Fait** | `POST v1/inventaire/{id}/versement {cle, mode:"ajouter"/"remplacer", lignes:[{code, quantite}]}` ; code = CIP, EAN, EAN fabricant ou code article grossiste ; rapport par ligne (`ok`, `inconnu`, `ambigu` + `lignesPossibles`, `refuse`) ; « ajouter » part de 0 sur une ligne jamais comptée ; même clé → `dejaTraite:true` ; autre contenu → 409 `CLE_REUTILISEE` ; 401, 409 `INVENTAIRE_CLOTURE`, 410, 413 (> 500 lignes), 400 ; deux terminaux simultanés : somme exacte (migration 7.1.2) |
| 38 | Questions ouvertes | **Non traité** | réponses du pharmacien attendues (partie 3) |
| 39 | Garde et péremptions recalculées | **Non fait** | constat (partie 3) |

### Détail de la demande 36 (étape D)

Routes sous session, à côté des routes existantes (aucune n'a changé de comportement).

| Point | Route | Réponse / règle |
|---|---|---|
| D10 | `GET v1/reception/parametres` | `{peremptionObligatoire, moisPeremptionCourte, motifObligatoirePeremptionCourte, scansRepetesActifs}` ; clés `KEY_ACTIVATE_PEREMPTION_DATE`, `KEY_RECEPTION_MOIS_PEREMPTION_COURTE` (6), `KEY_RECEPTION_MOTIF_PEREMPTION_COURTE` (1), `KEY_RECEPTION_SCANS_REPETES` (1) |
| D11 | `GET v1/commande/bon/items/{detailId}/lots` | `{data:[{lotId, numLot, datePeremption, quantite, ug, utilisateur, login, creeLe}]}` |
| D11 | `DELETE v1/commande/bon/lots/{lotId}` | `P_BL_MOBILE_CORRIGER` ; BL entré en stock → 409 `BL_CLOTURE` ; les autres lots restent. Pas de recalcul D3 (refusé) |
| D12 | `POST v1/reception/peremptions-courtes` | `{detailId, lotId?, numLot?, datePeremption, quantite, decision:"ACCEPTE"/"REFUSE", motif?}` ; accepter demande `P_BL_MOBILE_ACCEPTER_PEREMPTION_COURTE` et un motif (si le paramètre l'exige) |
| D12 | `GET v1/reception/peremptions-courtes?du=&au=&grossiste=&statut=` | rapport, valeur = PAF × quantité ; `PUT …/{id}/statut?statut=A_TRAITER|RECLAME|AVOIR_RECU`. **Export Excel/PDF non fait** |
| D13 | `POST v1/reception/anomalies`, `GET …?blId=` | types `PRODUIT_NON_PREVU`, `ECART_QUANTITE`, `LOT_PERIME_REFUSE`, `PRODUIT_DIFFERENT_DATAMATRIX`, `SERIE_DEJA_CONSOMMEE` ; `produitId` ou `code` |
| D14 | `retourfournisseur/new`, `add-item` | `numLot` ou `lotId` par ligne ; lot non reçu sur ce BL → refus lisible ; à la validation, le lot perd les boîtes retournées ; `numLot` et `lotId` rendus dans les lignes |
| D15 | `GET v1/retourfournisseur/en-preparation?blId=&utilisateur=` | `[{lgRETOURFRSID, strREFRETOURFRS, blId, blRef, grossiste, nbLignes, creeLe, utilisateur, utilisateurId}]` |
| D16 | `POST v1/reception/{blId}/presence {appareil, detailId?, numLot?}` (toutes les 20 s), `GET …/presence` | verrou sur ligne + lot ; pris par un autre → `verrou:false, verrouPar` ; autre lot du même produit libre ; abandonné après 2 min sans signal |
| D17 | voir demande 18 | |
| D18 | `commande/add-lot` : `serie` et `gtin` facultatifs | boîte déjà scannée → `{success:false, code:"SERIE_DEJA_CONSOMMEE", msg:"Boîte déjà scannée"}`, aucun lot ajouté ; sans `gtin`, l'EAN ou le CIP du produit |

### F. Patchs appliqués

| N° | Patch | Fait | Différences avec le patch d'origine |
|---|---|---|---|
| 40 | O4 apprentissages des ordonnances | **Fait** (migration 7.1.5) | ajout : un segment de plus de 6 chiffres (téléphone, date) est **refusé**, même en minuscules (« jean dupont 06 12 34 56 78 » passait le contrôle d'origine) |
| 41 | O5 lecture avancée | **Fait** (migration 7.1.6) | **aucun identifiant de modèle dans le code** (règle du dépôt) : `LECTURE_AVANCEE_MODELE` est **obligatoire** pour le fournisseur Claude, sans lui `lectureAvancee:false` ; coût estimé selon `LECTURE_AVANCEE_PRIX_ENTREE` / `_SORTIE` (0 par défaut) |
| 42 | B3 paiements Mobile Money | **Fait** (migration 7.1.7), **désactivé** | chemins publics ajoutés à la liste actuelle du filtre (resserrée par l'audit du 12/10) ; testé avec le simulateur puis configuration retirée |

---

## 2. Ce que je n'ai pas compris, ou compris de travers

1. **Document de l'étape D.** J'ai d'abord écrit que le détail de D10 à D18 était « indisponible ». C'était faux : il
   est dans `prestige_vente_app/docs/ETAPE_D_SERVEUR_RECEPTION_RETOUR.md`, que j'ai ensuite lu et suivi.
2. **Numéros de migration.** J'avais créé une 7.0.10 ; la règle de l'officine est 7.0.9 → 7.1.0. Corrigé
   (7.1.0 à 7.1.7).
3. **D3.** J'avais retenu « quantité reçue = somme des lots ». Le pharmacien l'a refusé ; rien n'a été changé.
4. **`checked` (demande 26).** Je ne sais pas ce que l'application y envoie (booléen ? `TERMINE` ? « contrôlé par
   l'application » ?), ni à quel filtre du serveur il correspond (`statutControle=CONTROLE|NON_CONTROLE` existe déjà).
5. **« Valider avec écart » (demande 12, `P_BL_MOBILE_VALIDER_AVEC_ECART`).** Avec D3 refusé (quantité entrée =
   quantité commandée), je ne sais pas ce que « valider malgré des lignes non saisies » doit changer à l'entrée en
   stock.
6. **« Posologie usuelle d'un produit » (demande 35).** L'intégration Posos du serveur n'a pas cette fonction ; je ne
   sais pas quelle route Posos l'application vise, ni ce qu'elle attend en réponse.
7. **« Choix multiples » (demande 32).** La liste des écrans et des paramètres concernés n'est pas donnée.

---

## 3. Ce qui manque, et ce qu'il me faut

### Peut être fait sans réponse (je le fais à la prochaine session si l'on me le demande)

| N° | Ce qui manque |
|---|---|
| 2 | refus `code:"ETAT"` de tout envoi d'une suggestion déjà commandée |
| 17 D6 | `creerbl` : HT/TVA absents → 0 ; `ref` obligatoire (20 caractères) et `dtStart` validés |
| 17 D8 | `retourfournisseur/new` : accepter `blId` (prioritaire), à défaut (n° de BL, grossiste) |
| 19 | `X-Client-Ref` sur `ordonnance-client/client/{id}/mesures` et `enregistrer` |
| 27 | lecture de l'auteur (`auteurId`, `auteurLogin`, `auteurNom`) dans les 7 routes `ws/inventaires/details*` |
| 36 D12 | export Excel / PDF du rapport des péremptions courtes ; écran Prestige « Rapport des péremptions courtes » |

### Il me faut une réponse

| N° | Question | À qui |
|---|---|---|
| 2 | `POST pharma/reponses` (relève des réponses des grossistes) : quel droit ? celui des commandes (`P_SM_COMMANDE_PROCESS`…) ou aucun (lecture) ? | application Pharmacien |
| 12 | `P_BL_MOBILE_SCANNER` sur `add-lot` et `creerbl` : ces routes servent aussi l'écran web de saisie des BL. Comment reconnaître un appel mobile (en-tête `X-App: mobile` ? route dédiée ?) — sinon, faut-il donner ce droit à tous les profils qui ont le menu BL pour ne rien bloquer au poste ? | application Mobile + pharmacien |
| 12 | `P_BL_MOBILE_VALIDER_AVEC_ECART` : que doit faire `validerbl?avecEcart=true` maintenant que la quantité entrée est la quantité commandée ? | pharmacien |
| 17 D7 | motif différent sur un produit déjà dans le retour : **option 1** (une ligne par produit, motif et lot) ou **option 2** (refus avec message) ? | pharmacien |
| 24 | `GET pilotage/controler` écrit en base : ajouter une variante POST, ou laisser tel quel (le mobile est déjà protégé) ? | pharmacien |
| 26 | valeurs envoyées dans `checked` et filtre attendu | application Pharmacien |
| 32 | liste des écrans et paramètres qui doivent accepter « id1,id2 » | pharmacien |
| 33 | route d'ajout de ligne : je propose `POST v1/suggestion-reserve/{id}/lignes {produitId, quantite}` (suggestion `A_TRAITER` ou `EN_COURS`, verrou détenu, `X-Client-Ref`). La forme convient-elle ? Le PDF REST est-il encore voulu ? | application Mobile |
| 34 | champs exacts de la route agrégée (identité, tiers payants, ayants droit), champs modifiables de l'identité, routes de dépôt de fichiers à passer en JSON. **Lecture de colonnes nominatives** : accord du pharmacien nécessaire avant tout test sur données réelles | application Mobile + pharmacien |
| 35 | route Posos de la posologie usuelle (nom, format de réponse) ; sinon, retirer la demande | application Mobile |
| 38 | pagination du Suivi des ajustements ? « Racheté » à la main dans les rappels ? actualisation programmée des rappels ? | pharmacien |
| 39 | garder quelques minutes le calcul d'une garde pour les pages suivantes : oui ou non ? | pharmacien |

### À fournir par l'officine pour activer O5 et B3

- **O5** (fichier `lecture-avancee.properties` du dossier de configuration de Prestige, jamais dans Git) :
  `LECTURE_AVANCEE_FOURNISSEUR` (`claude` ou `google`), `LECTURE_AVANCEE_CLE`, **`LECTURE_AVANCEE_MODELE`**
  (obligatoire pour Claude), et si l'on veut un coût estimé : `LECTURE_AVANCEE_PRIX_ENTREE`, `_SORTIE` (dollars par
  million de jetons). Facultatif : `LECTURE_AVANCEE_QUOTA_JOUR` (50), `LECTURE_AVANCEE_DELAI_MS` (30 000).
- **B3** (variables d'environnement ou propriétés système du serveur, jamais dans Git) : compte marchand (CinetPay
  recommandé) et ses clés, adresse publique HTTPS du serveur (`PRESTIGE_PAIEMENTS_URL_PUBLIQUE`), choix du
  fournisseur (`PRESTIGE_PAIEMENTS_FOURNISSEUR`), utilisateur borne avec caisse ouverte. Les adaptateurs CinetPay et
  Wave restent **à valider** avec la documentation du compte marchand.

### À vérifier par l'application Inventaire

- Contradiction 3 : `PUT ws/inventaires/details` exige une session depuis l'audit du 12/10. Les versions
  d'Inventaire **antérieures à 4.9** (sans file de saisies) peuvent perdre une saisie sur un 401 : à vérifier sur le
  parc de terminaux.

---

## Tests de bout en bout ajoutés (pour mémoire)

`src/test/e2e/retours/` : `test-reception-mobile.js` (D10 à D18, 26 contrôles), `test-pointage-photo.js`,
`test-inventaire-etat-rayons.js`, `test-inventaire-versement.js`, `test-routes-nombre.js`,
`test-controle-bl-utilisateur.js`, `test-reserve-emplacement.js`, `test-previsions-en-cours-relecture.js`,
`test-posos-historique.js`, `test-o4-corrections.js`, `test-o5-lecture-avancee.js` (faux service local, aucun appel
extérieur), `test-b3-paiements-mobile.js` (simulateur), `test-lot3-avis-mobilemoney.js` ;
`src/test/e2e/securite/test-droits-serveur.js` (droits des demandes 1 à 10).
