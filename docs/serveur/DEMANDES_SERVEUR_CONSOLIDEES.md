# Demandes consolidées à la session serveur Prestige

| | |
|---|---|
| **Date** | 14/10/2026 |
| **Destinataire** | la session qui maintient le serveur Prestige : dépôt `airm5500/prestige`, branche `claude/new-session-xm8ptu` (Java EE / Payara, API REST sous `/prestige/api/v1`) |
| **Émetteur** | le pharmacien, pour les trois applications mobiles : **Mobile** (Prestige Mobile, comptoir, dépôt `prestige_vente_app`), **Pharmacien** (Prestige Pharmacien, dépôt `prestige_app`), **Inventaire** (Prestige Inventaire, dépôt `prestinv`) |
| **Objet** | regrouper en un seul document toutes les demandes faites au serveur par les trois applications, sans doublon |

## Comment utiliser ce document

1. Le **tableau récapitulatif** ci-dessous donne, pour chaque demande, son numéro, les applications concernées,
   sa priorité et son statut. Traitez les demandes **P1** d'abord.
2. Chaque demande a ensuite sa propre section, avec toujours les mêmes rubriques :
   - **Pourquoi** : ce qui a été constaté et ce que cela change pour la pharmacie ;
   - **Quoi** : le changement attendu (route, paramètres, réponse, règle) ;
   - **Compatibilité** : si le changement casse quelque chose, et ce que font les applications en attendant ;
   - **Vérification** : comment tester (exemples `curl`) ;
   - **Référence** : le document d'origine, avec son dépôt, pour le détail complet.
3. Les demandes sont **regroupées par thème** : sécurité et droits, intégrité et anti-doublon, écritures cachées
   dans des lectures, données manquantes et nouvelles routes, performance, patchs prêts à appliquer.
4. En fin de document : ce qui est **déjà fait** par le serveur (pour mémoire), les **contradictions** relevées
   entre les documents d'origine, et les **règles communes** de réponse.
5. Les numéros de ligne Java cités viennent des documents d'origine (branche lue entre le 10 et le 14/10). Le code
   a pu bouger depuis : ils servent de repère, pas de vérité.

**Statuts vérifiés** (lecture seule, sans rien modifier) dans une copie locale de la branche serveur
(`origin/claude/new-session-xm8ptu`, dernier commit `d1c9b114` du 13/10/2026 à 23:05). Une demande peut avoir été
traitée depuis : merci de le signaler.

### Exemples `curl` : préparation commune

```bash
B=http://<serveur>:8080/prestige/api/v1
# Ouvrir une session (le cookie JSESSIONID est gardé dans le fichier cj)
curl -s -c cj -H 'Content-Type: application/json' -d '{"login":"<compte>","password":"…"}' $B/user/auth
# Ensuite, chaque appel avec la session : curl -s -b cj …
```

Prévoir **deux comptes de test** : un administrateur (ou pharmacien) et un compte simple (caissier) **sans** le
droit testé. Faire les essais d'écriture sur une **copie de la base**, jamais sur la base de production.

### Légende des priorités

| Priorité | Sens | Exemples |
|---|---|---|
| **P1** | **Sécurité ou intégrité des données** : un compte peut faire ce qu'il ne devrait pas, ou le stock / la caisse peuvent être faussés | droit non vérifié, stock corrigé deux fois |
| **P2** | **Fonctionnel bloquant ou incohérence** : une fonction ne marche pas, ou deux chiffres ne concordent pas | erreur 500, filtre ignoré, écart entre deux totaux |
| **P3** | **Confort ou performance** : l'application fonctionne déjà, mais plus lentement ou avec moins d'informations | route de comptage légère, historique |

---

## Tableau récapitulatif

| N° | Titre | Applications | Prio | Statut |
|---|---|---|---|---|
| **A. Sécurité et droits** |||||
| 1 | Ajustement de stock : droits vérifiés par le serveur | Pharmacien | **P1** | à faire |
| 2 | Commande PharmaML depuis une suggestion : droit, état, anti-doublon | Pharmacien | **P1** | à faire |
| 3 | Retour fournisseur : droits de préparation et de validation, stock jamais négatif | Pharmacien, Mobile | **P1** | à faire |
| 4 | Réserve : privilège dédié et route `reserve/droits` | Mobile | **P1** | à faire |
| 5 | Analyse posologie (Posos) : droit `P_SM_POSOS` vérifié et exposé | Mobile | **P1** | à faire |
| 6 | Annulation de vente : route POST au lieu d'un GET, sans doublon | Pharmacien | **P1** | à faire |
| 7 | Gardes et inventaires créés depuis les menus « mouchards » : droits | Pharmacien | **P1** | à faire |
| 8 | Saisie d'inventaire : refus sur inventaire clôturé, ligne inconnue, journal | Inventaire | **P1** | à faire (session exigée : fait) |
| 9 | Route « mes droits » unique | Pharmacien, Mobile, Inventaire | P2 | à faire |
| 10 | Rôle explicite à la connexion et création d'inventaire réservée côté serveur | Inventaire (Pharmacien) | P2 | à faire |
| 11 | Activation de la licence sans poste Prestige, sécurisée | Inventaire (toutes) | P2 | à faire |
| 12 | Réception BL mobile : nouveaux privilèges | Mobile | P2 | à faire |
| **B. Intégrité et anti-doublon** |||||
| 13 | Ajustement : empêcher la double clôture | Pharmacien | **P1** | à faire |
| 14 | Ajustement : interdire l'annulation d'un ajustement clôturé | Pharmacien | **P1** | à faire |
| 15 | Réserve : création de suggestion et mouvements sans doublon | Mobile | **P1** | à faire |
| 16 | Réception BL : défauts qui faussent le stock (D1, D3, D4) | Mobile | **P1** | à faire |
| 17 | Réception BL et retour : autres défauts (D2, D6, D7, D8) | Mobile | P2 | à faire |
| 18 | Réception BL et retour : envoi hors ligne sans doublon (D17) | Mobile | P2 | à faire |
| 19 | Fiche client : mesures et enregistrement sans doublon | Mobile | P2 | à faire |
| 20 | Création d'inventaire : erreur 500, identifiant créé, inventaire partiel | Inventaire | P2 | à faire |
| 21 | Une lecture en échec ne doit jamais rendre une liste vide | Inventaire | P2 | à faire |
| **C. Écritures cachées dans des lectures** |||||
| 22 | `GET /avis-clients/avis/{id}` marque l'avis « lu » | Pharmacien | P2 | à faire (droit de lecture : fait) |
| 23 | Prévisions : les lectures réécrivent « en cours de commande » | Pharmacien | P3 | à faire |
| 24 | Pilotage : `GET /pilotage/controler` écrit en base | Pharmacien | P3 | constat, à décider |
| **D. Données manquantes et nouvelles routes** |||||
| 25 | Détail Mobile Money par opérateur dans `/ca-all` | Pharmacien | P2 | à faire |
| 26 | Visualisation BL : filtres groupe et utilisateur ignorés | Pharmacien | P2 | partiel (`groupeId` lu ; `userId` ignoré) |
| 27 | Inventaire : auteur et heure de chaque saisie | Inventaire | P2 | à faire |
| 28 | Réserve : listes filtrées par emplacement, suggestion annulée close | Mobile | P2 | à faire |
| 29 | Routes de comptage légères pour l'accueil | Pharmacien | P3 | à faire |
| 30 | Inventaire : état de tous les rayons en une requête | Inventaire | P3 | à faire |
| 31 | Photo de contrôle du pointage par badge | Mobile | P3 | à faire |
| 32 | Choix multiples (« id1,id2 ») sur d'autres routes | Pharmacien | P3 | à faire (fait pour CA emplacement / famille) |
| 33 | Réserve : ajouter un produit à une suggestion, PDF en REST | Mobile | P3 | à faire |
| 34 | Fiche client : route agrégée, modification de l'identité, réponses JSON | Mobile | P3 | à faire |
| 35 | Posos : historique et routes unitaires | Mobile | P3 | à faire |
| 36 | Réception BL mobile : fonctions à ajouter (D10 à D16, D18) | Mobile | P3 | à faire |
| 37 | Inventaire : versement de collecte en lot | Inventaire | P3 | à faire (optionnel) |
| 38 | Questions ouvertes : pagination, rappels « Racheté », actualisation | Pharmacien | P3 | à confirmer par le pharmacien |
| **E. Performance** |||||
| 39 | Analyse de garde et péremptions : calculs complets répétés | Pharmacien | P3 | constat |
| **F. Patchs prêts (dépôt `prestige_vente_app`)** |||||
| 40 | O4 : apprentissages des ordonnances partagés | Mobile | P3 | patch à appliquer |
| 41 | O5 : lecture avancée des ordonnances | Mobile | P3 | patch à appliquer + clé |
| 42 | B3 : paiements Mobile Money par agrégateur | Mobile | P3 | patch à appliquer (désactivé par défaut) |
| **G. Nouvelles demandes (15/10/2026)** |||||
| 43 | Empreintes des employés partagées entre terminaux de pointage | Mobile | P2 | à faire (désactivé par défaut) |
| 44 | Performance de `GET /info` (Analyse article, fiche produit) | Mobile, Pharmacien | P2 | à faire |
| **Fait, pour mémoire** (détail en fin de document) |||||
| F1 | `licence/find` lisible avant connexion (clé masquée) | toutes | — | **fait** |
| F2 | Session renouvelée à chaque connexion | toutes | — | **fait** |
| F3 | Expiration des sessions après 12 h d'inactivité | toutes | — | **fait** |
| F4 | `GET /info` rapide, avec `stockReserve` et les seuils | Mobile, Pharmacien | — | **fait** |
| F5 | H4 : clé anti-doublon `X-Client-Ref` (ventes, retours) | Mobile | — | **fait** (intégré à la branche) |
| F6 | H5 : mise à jour différentielle du catalogue | Mobile | — | **fait** (intégré à la branche) |
| F7 | Fin des accès sans session (`ws/inventaires*`, en-têtes `X-User-Info`) | Inventaire | — | **fait** (audit du 12/10) |
| F8 | Fichier Journal paginé (`start`, `limit`, `total`) | Pharmacien | — | **existait déjà** |
| F9 | CA emplacement / famille : plusieurs identifiants séparés par des virgules | Pharmacien | — | **fait** (13/10) |

**Total : 42 demandes à traiter** : **12 en P1**, **14 en P2**, **16 en P3**. Plus 9 points faits, pour mémoire.

---

## Règles communes de réponse (à appliquer à toutes les demandes)

Ces conventions sont déjà utilisées ailleurs dans l'API. Les trois applications les comprennent.

| Cas | Réponse attendue |
|---|---|
| Session absente ou expirée | HTTP **401**, ou `{success:false, msg:"Veuillez vous connecter"}` |
| Droit manquant | HTTP **403** ou `{success:false, interdit:true, msg:"…"}`. **Jamais 401** : l'application déconnecterait l'utilisateur |
| Opération refusée par l'état de l'objet (déjà clôturé, déjà annulé…) | `{success:false, code:"ETAT", msg:"…"}` (HTTP 409 accepté) |
| Rejeu d'une opération déjà faite (même `X-Client-Ref`) | **la même réponse** que la première fois, sans rien refaire |
| Route absente | 404 ou 405 : les applications en déduisent « fonction absente sur ce serveur » et gardent leur ancien fonctionnement. **Ne pas utiliser 404 / 405 pour un refus métier** sur les nouvelles routes (préférer 409, 410, 422 ou `200 {success:false}`) |
| Panne | 5xx avec `{success:false, message:"…"}`. **Jamais une liste vide** |
| Évolutions | **Ajouter, ne jamais renommer** : nouveaux champs et nouvelles routes seulement ; mêmes formats de date ; messages en français avec un `code` stable |

Références : `prestige_app/docs/serveur/DEMANDE_ECRITURES_SENSIBLES.md` (introduction),
`prestinv/docs/DEMANDE_SERVEUR_COMPTAGE.md` § 3.

---

# A. Sécurité et droits

Constat commun : sur la plupart des routes d'écriture, le serveur ne vérifie **que la session**
(`AuthenticationFilter`, `SessionObligatoireFilter`). Le poste web cache les boutons selon les droits, mais une
application mobile, un script ou un simple rejeu d'adresse n'est pas arrêté. **Masquer un menu dans l'application
n'est pas une sécurité** : seul le serveur peut garantir qu'une opération est faite par un compte autorisé.

## 1. Ajustement de stock : droits vérifiés par le serveur — P1

**Applications** : Pharmacien.

**Pourquoi.** Un ajustement modifie directement le stock. Aujourd'hui, n'importe quel compte connecté peut créer,
modifier, clôturer ou annuler un ajustement en appelant la route, même si le poste web lui cache le menu.

**Quoi.** Dans `rest/AjustementRessource.java` (service `MvtProduitServiceImpl`, l. 585-870 et 1116) :

- création (`POST /ajustement/creeation`), ajout de ligne (`add/item`), modification et suppression de ligne
  (`item/{id}` en PUT et DELETE), clôture (`PUT /ajustement/{id}`) : vérifier le **droit de faire un ajustement**
  (celui qui donne accès au menu « Ajustement ») ;
- annulation (`DELETE /ajustement/{id}`) : vérifier `ACTIONDELETEAJUSTEMENT` (030920172). Aujourd'hui il n'est lu
  que pour l'affichage (`AjustementRessource` l. 194-195, `canCancel`) ;
- refus : 403 ou `interdit:true` ;
- dans la réponse de clôture, indiquer **l'emplacement** dont le stock a été ajusté (aujourd'hui celui du
  **créateur**, pas de celui qui clôture : `cloreAjustement`, `ajustement.getLgUSERID().getLgEMPLACEMENTID()`).

Voir aussi les demandes 13 (double clôture) et 14 (annulation d'un ajustement clôturé), et l'anti-doublon
`X-Client-Ref` sur `POST /ajustement/creeation` et `PUT /ajustement/{id}` (même mécanisme que la demande F5).

**Compatibilité.** Le poste web garde son fonctionnement pour les comptes qui ont le droit. L'application
Pharmacien **ne propose aucune écriture d'ajustement** tant que les demandes 1, 13 et 14 ne sont pas livrées.

**Vérification.**

```bash
# Compte sans le droit d'ajustement : refus attendu (403 ou interdit:true), rien de créé
curl -s -b cj_caissier -H 'Content-Type: application/json' -d '{…}' $B/ajustement/creeation
# Compte sans ACTIONDELETEAJUSTEMENT : refus attendu
curl -s -b cj_caissier -X DELETE $B/ajustement/<id>
```

**Référence.** `prestige_app/docs/serveur/DEMANDE_ECRITURES_SENSIBLES.md` § 1 (points 3 et 5).

## 2. Commande PharmaML depuis une suggestion : droit, état, anti-doublon — P1

**Applications** : Pharmacien.

**Pourquoi.** `POST /suggestion-pharmaml/{id}/envoi` (et la variante `POST /suggestion-pharmaml/{id}`) crée au
besoin une commande (`creerCommandeDepuisSuggestion`) et **envoie vraiment** la commande au grossiste. C'est un
**engagement financier**. Seule la session est vérifiée. Les protections actuelles (`attenteEnCours`,
`dejaRepondue`, reprise de la commande créée) évitent un double envoi, mais pas un envoi par un compte non autorisé.

**Quoi.** Dans `rest/SuggestionPharmaMlRessource.java` (`PharmaMlServiceImpl` l. 138) :

1. vérifier le **droit de passer commande** (celui du menu commandes / PharmaML) sur l'aperçu
   (`GET /suggestion-pharmaml/{id}`), les deux variantes d'envoi et la récupération des réponses
   (`POST /pharma/reponses`) ; refus 403 ou `interdit:true` ;
2. refuser l'envoi d'une suggestion déjà « commandée » avec `code:"ETAT"`, **dans tous les cas** (aujourd'hui
   `dejaRepondue` ne le couvre que dans certains cas) ;
3. accepter l'en-tête `X-Client-Ref` sur l'envoi : même référence, même jeton renvoyé, rien de refait.

**Compatibilité.** Ajouts et contrôles seulement. L'application n'ouvrira l'envoi qu'après livraison.

**Vérification.** Compte sans le droit → refus, aucun message envoyé au grossiste. Deuxième envoi d'une suggestion
déjà commandée → `code:"ETAT"`. Deux envois avec le même `X-Client-Ref` → même réponse, une seule commande.

**Référence.** `prestige_app/docs/serveur/DEMANDE_ECRITURES_SENSIBLES.md` § 2.

## 3. Retour fournisseur : droits de préparation et de validation, stock jamais négatif — P1

**Applications** : Pharmacien, Mobile (réception et retour mobiles, « étape D »).

**Pourquoi.** La validation d'un retour (`POST /produit/validerretourfour`,
`MvtProduitServiceImpl.validerRetourFournisseur` l. 1136) **sort le stock**. Aucun droit n'est vérifié, ni sur la
validation, ni sur la préparation (`POST /retourfournisseur/new`, `add-item`, `update-item`, `remove-item`,
`PUT /retourfournisseur/full-bl/{id}`). Une ligne peut aussi rendre le stock **négatif**. Les lignes déjà validées
sont bien exclues (un double appel ne sort pas deux fois le stock), mais le second appel renvoie un succès vide.

**Quoi.**

1. Deux privilèges, créés par migration Flyway (modèle : `V6.5.8__privilege_entree_en_stock.sql`) :
   `P_RETOUR_FRS_PREPARER` (création / modification du retour : `new`, `add-item`, `update-item`, `remove-item`,
   `full-bl`) et `P_RETOUR_FRS_VALIDER` (validation). Refus 403 ou `interdit:true` ;
2. refuser une ligne qui ferait passer le stock **sous zéro** ;
3. refuser la validation d'un retour déjà validé avec `code:"ETAT"` (au lieu d'un succès vide) ;
4. accepter `X-Client-Ref` sur la validation (la création l'accepte déjà, demande F5) ;
5. lire l'utilisateur avec `sessionHelperService.getCurrentUser()` et non `HttpSession`, pour tous les modes de
   connexion.

**Compatibilité.** Les postes qui ont les droits ne voient aucun changement. Pour l'application Mobile, les droits
seront aussi renvoyés à la connexion (demande 9). Le Mobile vérifie déjà la quantité reçue et le stock avant
d'envoyer ; le serveur doit le garantir pour tous les postes.

**Vérification.** Compte sans `P_RETOUR_FRS_VALIDER` → refus, stock inchangé. Retour dont une ligne dépasse le
stock → refus lisible. Deuxième validation → `code:"ETAT"`.

**Référence.** `prestige_app/docs/serveur/DEMANDE_ECRITURES_SENSIBLES.md` § 3 ;
`prestige_vente_app/docs/ETAPE_D_SERVEUR_RECEPTION_RETOUR.md` D5 et D9.

## 4. Réserve : privilège dédié et route `reserve/droits` — P1

**Applications** : Mobile.

**Pourquoi.** Aucun contrôle de privilège sur `v1/reserve/*` (`assort`, `reassort`, traitements par lot) ni sur
`v1/suggestion-reserve/*` (`creer`, `quantite`, `traiter`, `reessayer`). Ces routes **déplacent le stock** entre
rayon et réserve. Il n'existe aucun privilège « traiter la réserve » : le seul lié à la réserve est
`P_ANNULER_MOUVEMENT_RESERVE` (annulation). Le privilège du sous-menu web `reservemanager` n'est dans aucune
migration lisible (il est dans des données plus anciennes de la base).

**Quoi.**

1. créer un privilège dédié, par exemple `P_TRAITER_RESERVE`, vérifié sur toutes ces routes ;
2. l'exposer par `GET v1/reserve/droits` → `{success:true, traiter:true|false}` ;
3. documenter le privilège du sous-menu `reservemanager`, ou le remplacer par celui du point 1.

**Compatibilité.** L'application appelle déjà `GET v1/reserve/droits` (aujourd'hui 404, ignoré). **En attendant,
le menu Réserve est réservé aux administrateurs** (`GET v1/roles/est-admin`). Dès que la route répond, les comptes
qui ont le droit verront le menu, sans mise à jour de l'application.

**Vérification.**

```bash
curl -s -b cj_admin    $B/reserve/droits   # {"success":true,"traiter":true}
curl -s -b cj_caissier $B/reserve/droits   # {"success":true,"traiter":false}
curl -s -b cj_caissier -X PUT $B/suggestion-reserve/<id>/traiter   # refus 403 ou interdit:true, stock inchangé
```

**Référence.** `prestige_vente_app/docs/serveur/API_RESERVE_POSOS_FICHE_CLIENT.md` § 2.3 et § 5, points 1 et 6.

## 5. Analyse posologie (Posos) : droit `P_SM_POSOS` vérifié et exposé — P1

**Applications** : Mobile.

**Pourquoi.** `P_SM_POSOS` n'est pas vérifié sur `v1/posos/*`, et aucune route ne l'expose. Le menu mobile est donc
ouvert à tous les comptes connectés, alors que **chaque analyse consomme l'API Posos** (service payant).

**Quoi.** Vérifier `P_SM_POSOS` sur `v1/posos/*` (refus 403 ou `interdit:true`) et l'exposer, par exemple par
`GET v1/posos/droits` → `{success:true, analyser:true|false}` (nom de champ à fixer par le serveur).

**Compatibilité.** Aujourd'hui le menu est visible pour tout compte connecté (question ouverte au pharmacien :
le réserver aux administrateurs et pharmaciens en attendant). L'application lira la route dès qu'elle existe.

**Vérification.** Compte sans `P_SM_POSOS` : `POST $B/posos/analyse` → refus, aucun appel à Posos.

**Référence.** `prestige_vente_app/docs/serveur/API_RESERVE_POSOS_FICHE_CLIENT.md` § 5, point 8 ; § 7, question 3.

## 6. Annulation de vente : route POST au lieu d'un GET, sans doublon — P1

**Applications** : Pharmacien.

**Pourquoi.** `GET /vente/annulation/{id}` (`rest/SalesRessource.java`, `deleteVente`, vers la l. 337) **annule
réellement une vente** : opération irréversible (stock, caisse, crédit). Un GET peut être **rejoué ou préchargé
sans intention** (cache, proxy, historique, nouvelle tentative automatique d'une bibliothèque HTTP, lien partagé).
Rien ne garantit qu'un second appel sur une vente déjà annulée soit refusé proprement. Le droit
`P_BT_ANNULER_VENTE` est bien vérifié, mais le refus arrive en HTTP 200 (`success:false`).

**Quoi.**

```
POST /api/v1/vente/{id}/annuler        (en-tête X-Client-Ref: <identifiant unique par opération>)
→ {"success": true, "annulee": true, "dtAnnulation": "14/10/2026 10:12"}
```

1. route **POST** ; garder le GET pour le poste web le temps de la migration, puis le retirer ou le refuser hors
   poste ; droit `P_BT_ANNULER_VENTE`, refus 403 ou `interdit:true` (jamais 401) ;
2. vente déjà annulée → `{success:false, code:"ETAT", msg:"Vente déjà annulée"}` sans rien refaire ; même
   `X-Client-Ref` rejoué → la même réponse que la première fois ;
3. journaliser l'annulation (utilisateur, poste ou « mobile », date) dans le Fichier Journal, comme sur le poste.

**Compatibilité.** Rétrocompatible si le GET reste pendant la transition. En attendant, l'application (3.6.0+34)
garde le GET mais : affiche le détail avant toute action, demande une confirmation renforcée (saisie de la
référence ou de « ANNULER »), le code administrateur pour les comptes ni administrateur ni pharmacien, bloque le
double appui, relit la vente avant (déjà annulée → aucun envoi) et après, et **ne renvoie jamais automatiquement**.

**Vérification.**

```bash
curl -s -b cj -X POST -H 'X-Client-Ref: TEST-ANN-1' $B/vente/<id>/annuler   # annulee:true
curl -s -b cj -X POST -H 'X-Client-Ref: TEST-ANN-1' $B/vente/<id>/annuler   # même réponse, rien refait
curl -s -b cj -X POST -H 'X-Client-Ref: TEST-ANN-2' $B/vente/<id>/annuler   # code:"ETAT"
curl -s -b cj_sans_droit -X POST $B/vente/<id2>/annuler                      # 403 ou interdit:true
```

**Référence.** `prestige_app/docs/serveur/DEMANDE_ECRITURES_SENSIBLES.md` § 9 ; `prestige_app/docs/NOTE_VERSION_3.6.0.md`.

## 7. Gardes et inventaires créés depuis les menus « mouchards » : droits — P1

**Applications** : Pharmacien.

**Pourquoi.** Ces routes enregistrent des gardes ou **créent des inventaires et des suggestions** sans aucun
contrôle de droit. Les lectures de ces menus montrent l'activité des employés (données de type « mouchard ») et
ne vérifient pas non plus le droit du menu.

**Quoi.** Vérifier côté serveur (refus 403 ou `interdit:true`) :

| Route | Effet | Droit à vérifier (menu actuel) |
|---|---|---|
| `POST /gardes`, `DELETE /gardes/{id}`, `POST /gardes/supprimer` | gardes enregistrées | `P_SM_GESTION_GARDES` |
| `POST /gardes/{id}/inventaire`, `POST /gardes/{id}/suggestion` | crée un inventaire / une suggestion | `P_SM_GESTION_GARDES` (+ droit inventaire / suggestion) |
| `POST /ca-zone-geo/detail/inventaire` | crée un inventaire réserve | `P_SM_CA_ZONE_GEO` (+ droit inventaire) |
| `POST /vente-suppressions/create-inventaire` | crée un inventaire | `P_SM_SUPPRESSIONS_VENTE` (+ droit inventaire) |
| `POST /ventes-modifiees/create-inventaire` | crée un inventaire | `P_SM_VENTES_MODIFIEES` (+ droit inventaire) |

Souhaité aussi : vérifier le droit du menu sur les **lectures** (`/gardes/*` en GET, `/ca-zone-geo`,
`/vente-suppressions`, `/ventes-modifiees`).

**Compatibilité.** L'application réserve déjà ces menus à l'administrateur et au pharmacien (profil
`xtypeuser = "dashboard"` de `/user/auth`) et affiche « Droit manquant : … » **sans déconnecter** si le serveur refuse.

**Vérification.** Avec un compte caissier, chaque route du tableau → refus, rien de créé.

**Référence.** `prestige_app/docs/serveur/DEMANDE_ECRITURES_SENSIBLES.md` § 4 ; `prestige_app/docs/NOTE_VERSION_VAGUE1.md`.

## 8. Saisie d'inventaire : refus sur inventaire clôturé, ligne inconnue, journal — P1

**Applications** : Inventaire.

**Pourquoi.** `PUT /v1/ws/inventaires/details` (`InventaireServiceImpl.updateDetailQuantity`, l. 718-722) :

- ne vérifie pas que l'inventaire est **ouvert** : une quantité peut être modifiée **après la clôture**, ce qui
  fausse le stock valorisé ;
- une ligne inconnue provoque une `NullPointerException`, donc une erreur **500** ;
- la quantité n'est pas contrôlée (nulle ou négative).

`POST /v1/inventaire/ligne/quantite` (`updateQuantiteLigne`, l. 436-463) n'a pas non plus de contrôle « inventaire
clôturé ».

Note : la **session est désormais exigée** sur ce PUT (le chemin a été retiré de `SKIP_PATHS` par l'audit du 12/10,
voir F7). Le point C2 de la demande d'origine est donc fait ; le reste (C1) ne l'est pas.

**Quoi** (C1 de la demande d'origine).

1. ligne inconnue → **404** lisible : `{"success":0,"code":"LIGNE_INCONNUE","message":"Cette ligne d'inventaire n'existe plus."}` ;
2. inventaire clôturé (`t_inventaire.str_STATUT <> 'enable'`, ou ligne `str_STATUT = 'is_Closed'`) → **409**, rien
   d'écrit : `{"success":0,"code":"INVENTAIRE_CLOTURE","message":"Inventaire « … » clôturé le … : la quantité n'a pas été enregistrée."}`.
   Même contrôle dans `POST ligne/quantite`, mais avec la forme de cette route : **200**
   `{"success":0,"errors":"Inventaire … clôturé …"}` (sur cette route, 404 / 405 veut dire « route absente » pour
   l'application) ;
3. quantité nulle ou négative → 400 `{"code":"QUANTITE_INVALIDE"}`, comme `ligne/quantite` ;
4. le journal des PUT anonymes prévu pour la transition n'a plus d'objet si la session est bien exigée (à
   confirmer, voir « Contradictions »).

**Compatibilité.** Toutes les versions de l'application traitent déjà un refus 4xx comme un échec (4.8.5 : message ;
4.9 et plus : saisie gardée « refusée » avec son motif dans « À envoyer »). L'application contrôle déjà elle-même
l'inventaire clôturé avant d'envoyer, en attendant.

**Vérification.**

```bash
curl -s -b cj -X PUT -H 'Content-Type: application/json' -d '{"id":999999999,"quantite":1}' $B/ws/inventaires/details  # 404 + message, plus de 500
# Sur une ligne d'un inventaire clôturé : 409, int_NUMBER et dt_UPDATED inchangés en base
```

**Référence.** `prestinv/docs/DEMANDE_SERVEUR_COMPTAGE.md` § 0, § C ; `prestinv/docs/ANALYSE_PRESTINV.md` (S2).

## 9. Route « mes droits » unique — P2

**Applications** : Pharmacien, Mobile, Inventaire.

**Pourquoi.** Il n'existe que des routes de droits **par module** (`/avis-clients/droits`, `/pharma/droits`,
`/rh/droits`, `/ordonnance-client/droits`, `/fichearticle/privileges-boutons`…). `POST /user/auth` ne renvoie que
`privileges:[canUpdatePrice, showStock]` et `xtypeuser` ; la liste complète reste en session
(`AccountResource`, `USER_LIST_PRIVILEGE`). Pour savoir quels menus afficher, chaque application doit appeler
plusieurs routes et interpréter les refus : plus d'appels, et des menus qui échouent à l'ouverture.

**Quoi.**

```
GET /api/v1/user/droits
→ {"success": true, "profil": "dashboard", "droits": ["P_SM_POINTAGE_BL", "P_SM_PILOTAGE", "ACTIONDELETEAJUSTEMENT", …]}
```

- privilèges de la **session** (`USER_LIST_PRIVILEGE`, déjà chargés à la connexion), sous leur nom technique ;
  `profil` = la valeur `xtypeuser` de la connexion ;
- lecture seule, légère (tout est en session), 401 si la session a expiré ;
- **sous la session cookie habituelle**, pas sous `v1/mobile/` (préfixe réservé au jeton Bearer, voir
  « Contradictions ») ;
- y inclure les nouveaux privilèges des demandes 3, 4, 5 et 12.

Chaque application l'appellera une fois après la connexion et masquera les menus et boutons non autorisés ; **le
serveur reste juge** à chaque appel.

**Compatibilité.** Route nouvelle. Les routes par module restent.

**Vérification.** `curl -s -b cj $B/user/droits` avec un administrateur puis un caissier : listes différentes ;
sans session : 401.

**Référence.** `prestige_app/docs/serveur/DEMANDE_ECRITURES_SENSIBLES.md` § 5 ;
`prestige_vente_app/docs/serveur/API_RESERVE_POSOS_FICHE_CLIENT.md` § 2.1 et § 5 point 13 ;
`prestige_vente_app/docs/ETAPE_D_SERVEUR_RECEPTION_RETOUR.md` D9 (exposition dans `user/auth`).

## 10. Rôle explicite à la connexion et création d'inventaire réservée côté serveur — P2

**Applications** : Inventaire (utile aussi au Pharmacien, qui lit le même `xtypeuser`).

**Pourquoi.** Le pharmacien a décidé que **la création d'un inventaire depuis le terminal est réservée à
l'administrateur et au pharmacien**. `POST /v1/user/auth` ne renvoie pas le rôle, seulement `xtypeuser`
(`"dashboard"` pour l'utilisateur système `00`, le pharmacien, le super-administrateur et l'administrateur ;
`"mainmenumanager"` sinon). C'est un détail d'affichage du web détourné de son usage ; sur un serveur plus ancien
l'administrateur pouvait recevoir `"mainmenumanager"`. Et le serveur ne refuse pas la création à un caissier.

**Quoi** (ajout, rétrocompatible).

```json
{ "success": true, "str_LOGIN": "…",
  "role":   { "code": "PHARMACIEN", "libelle": "Pharmacien" },
  "droits": { "creerInventaire": true } }
```

- `role.code` : `SYSTEME`, `SUPER_ADMINISTRATEUR`, `ADMINISTRATEUR`, `PHARMACIEN` ou `AUTRE` (valeur stable) ;
  `role.libelle` : nom affichable ;
- `droits.creerInventaire` : idéalement calculé à partir des privilèges du rôle (`TPrivilege`), pour que l'officine
  puisse l'accorder à un autre profil sans modifier l'application ;
- le serveur refuse aussi `POST /v1/inventaire/creation` pour un compte non autorisé (403
  `{"success":0,"message":"Création réservée…"}`) ;
- **ne rien retirer** : `xtypeuser` reste.

**Compatibilité.** L'application 4.13 lit dans l'ordre `droits.creerInventaire`, puis `role.code`, puis
`xtypeuser`, sinon « profil inconnu » (code administrateur du terminal). Le réglage « Autoriser la création
d'inventaire aux autres comptes » reste prioritaire.

**Vérification.** Connexions pharmacien, administrateur, super-administrateur, caissier : `role.code` et
`droits.creerInventaire` attendus, `xtypeuser` inchangé ; `POST $B/inventaire/creation` par un caissier → 403, rien
de créé.

**Référence.** `prestinv/docs/DEMANDE_SERVEUR_COMPTAGE.md` § G ; `prestinv/docs/NOTE_VERSION_4.13.md` § 8.

## 11. Activation de la licence sans poste Prestige, sécurisée — P2

**Applications** : Inventaire (concerne les trois applications).

**Pourquoi.** L'écran d'activation s'affiche **avant** la connexion. Or `GET /v1/licence/save/{clé}` exige une
session (l'ancienne exemption `"v1/licence/save/"` ne marchait pas : `SKIP_PATHS.contains(path)` compare le chemin
exact) et n'accepte que GET (l'application Inventaire envoie un POST → 405). Surtout,
`LicenceServiceImpl.save` (l. 73-82) **supprime la licence existante puis enregistre n'importe quelle chaîne**,
sans contrôle : l'ouvrir sans connexion permettrait à n'importe qui sur le réseau de désactiver l'officine. La clé
passe aussi dans l'adresse, donc dans les journaux d'accès.

**Quoi.** Deux options, au choix du serveur :

- **Option A (recommandée par la demande « licence 401 »)** : laisser l'enregistrement derrière la connexion ; les
  applications activeront la licence **après** la connexion d'un administrateur. À documenter ;
- **Option B (demandée par Inventaire)** : nouvelle route `POST /api/v1/licence/activation`, corps `{"cle":"…"}`,
  exemptée de session (chemin exact dans `SKIP_PATHS`) avec garde-fous :
  1. sans session, acceptée **seulement si aucune licence MOBILE valide** n'existe ; sinon session administrateur
     exigée (sinon 403 `{"code":"LICENCE_DEJA_ACTIVE"}`) ;
  2. **clé vérifiée avant de toucher à l'existant** (40 caractères hexadécimaux, empreinte attendue par
     `generateLicence` ; si la date de fin n'est pas déductible : `{"cle":"…","dateFin":"2027-12-31"}`). Clé
     refusée → 422 `{"code":"CLE_INVALIDE"}`, licence existante **intacte** ;
  3. 5 essais par minute et par adresse IP au plus (429), chaque activation journalisée ;
  4. réponse 200 : même forme que `GET /v1/licence/find`.

Dans les deux cas, `GET /v1/licence/save/{clé}` reste **inchangé** (session exigée) : Prestige Mobile l'utilise.

**Compatibilité.** L'application Inventaire essaie la nouvelle route ; 404 / 405 → elle affiche « Activez la licence
depuis le poste Prestige (Paramètres → Licence), puis touchez Réessayer ».

**Vérification.** Sans session et sans licence : clé valide acceptée, clé invalide → 422 et rien d'écrit ; licence
valide existante → 403 et licence inchangée ; 6ᵉ essai dans la minute → 429 ; `GET licence/save/{clé}` avec session
inchangé.

**Référence.** `prestinv/docs/DEMANDE_SERVEUR_COMPTAGE.md` § E ;
`prestige_vente_app/docs/serveur/DEMANDE_LICENCE_MOBILE_401.md` § 3.2 ; `prestinv/docs/NOTE_VERSION_FIABILITE.md` § 3.

## 12. Réception BL mobile : nouveaux privilèges — P2

**Applications** : Mobile.

**Pourquoi.** La réception des bons de livraison (BL) sur mobile n'a pas de droits propres : seule l'entrée en stock
(`P_ENTREE_EN_STOCK`) est vérifiée.

**Quoi.** Créer par migration Flyway (par exemple `V6.9.113__privileges_mobile_reception.sql`, à renuméroter
au-dessus de la dernière migration) et vérifier :

| Privilège | Rôle | Vérifié par |
|---|---|---|
| `P_BL_MOBILE_SCANNER` | ouvrir la réception BL sur mobile, ajouter des lots | `add-lot`, `creerbl` (appel mobile) |
| `P_BL_MOBILE_CORRIGER` | effacer des lots, corriger la saisie d'un autre | `remove-lots`, demande 36 (D11) |
| `P_BL_MOBILE_ACCEPTER_PEREMPTION_COURTE` | accepter un lot en péremption courte | demande 36 (D12) |
| `P_BL_MOBILE_VALIDER_AVEC_ECART` | valider malgré des lignes non saisies | `validerbl` avec `avecEcart=true` |
| `P_ENTREE_EN_STOCK` (existant) | valider l'entrée en stock | `validerbl` (déjà en place) |

Les privilèges des retours (`P_RETOUR_FRS_PREPARER`, `P_RETOUR_FRS_VALIDER`) sont dans la demande 3. Les exposer
par la demande 9 (ou dans `user/auth`, voir « Contradictions »).

**Compatibilité.** Ajouts. Le Mobile masquera les actions non autorisées ; le serveur reste juge.

**Vérification.** Chaque droit retiré à un compte de test → la route correspondante refuse.

**Référence.** `prestige_vente_app/docs/ETAPE_D_SERVEUR_RECEPTION_RETOUR.md` D9 et § 7, critère 6.

---

# B. Intégrité et anti-doublon

Constat commun : sur un téléphone (réseau instable, renvois automatiques, double appui, application reprise),
certaines écritures peuvent être **appliquées deux fois**. L'application ajoute ses verrous, mais **seul le serveur
peut garantir** qu'une opération n'est faite qu'une fois. Le mécanisme existe déjà : l'en-tête `X-Client-Ref` et le
service `MobileClientRefService` (demande F5, table `mobile_client_ref`). Il est recommandé de **réutiliser ce même
mécanisme** partout.

## 13. Ajustement : empêcher la double clôture — P1

**Applications** : Pharmacien.

**Pourquoi.** `PUT /ajustement/{id}` (clôture, qui écrit le stock) : `cloreAjustement` ne vérifie pas le statut
(vérifié : toujours vrai sur la branche du 13/10). Un second appel (double appui, renvoi réseau) recalcule le
« stock après » à partir du stock courant et **ré-applique l'ajustement : le stock est corrigé deux fois**.

**Quoi.**

1. refuser si le statut n'est pas « en cours » : `{success:false, code:"ETAT", msg:"Ajustement déjà clôturé"}` ;
2. contrôle du statut et passage à « clôturé » dans **la même transaction**, avec verrou sur la ligne
   (`SELECT … FOR UPDATE` ou version optimiste), pour que deux clôtures simultanées ne passent pas toutes les deux ;
3. accepter `X-Client-Ref` sur `PUT /ajustement/{id}` et `POST /ajustement/creeation`.

**Compatibilité.** Le poste web ne clôture qu'une fois : rien ne change pour lui.

**Vérification.** Clôturer, puis rejouer la même requête : `code:"ETAT"`, stock inchangé. Deux clôtures lancées en
même temps (deux terminaux `curl` simultanés) : une seule appliquée.

**Référence.** `prestige_app/docs/serveur/DEMANDE_ECRITURES_SENSIBLES.md` § 1, points 1 et 4.

## 14. Ajustement : interdire l'annulation d'un ajustement clôturé — P1

**Applications** : Pharmacien.

**Pourquoi.** `DELETE /ajustement/{id}` (`annulerAjustement`, l. 1116) supprime l'ajustement et ses lignes **même
s'il est déjà clôturé**, sans restaurer le stock : **l'historique est perdu alors que le stock reste modifié**.

**Quoi.** Refuser l'annulation d'un ajustement clôturé (`code:"ETAT"`, solution préférée). À défaut, la transformer
en **contre-ajustement** qui restaure le stock et garde l'historique (mouvements inverses tracés).

**Compatibilité.** Ne change rien pour un ajustement en cours.

**Vérification.** Clôturer un ajustement puis `curl -s -b cj -X DELETE $B/ajustement/<id>` → refus ; l'ajustement et
ses lignes sont toujours en base.

**Référence.** `prestige_app/docs/serveur/DEMANDE_ECRITURES_SENSIBLES.md` § 1, point 2.

## 15. Réserve : création de suggestion et mouvements sans doublon — P1

**Applications** : Mobile.

**Pourquoi.** `POST v1/suggestion-reserve/creer` et `creer-depuis-recherche` ne sont pas idempotents, pas plus que
`assort` et `reassort` : deux envois créent **deux suggestions ou deux mouvements de stock**.

**Quoi.** Accepter l'en-tête `X-Client-Ref` (ou un champ `requestId`) sur ces routes, avec relecture par clé, comme
pour les ventes (demande F5).

**Compatibilité.** Sans en-tête : comportement actuel. En attendant, l'application bloque le bouton pendant l'envoi,
propose de reprendre une suggestion manuelle du même sens déjà en attente (et demande confirmation pour en créer une
autre), et signale un délai dépassé après l'envoi comme « résultat incertain » **sans jamais renvoyer** (la liste en
attente est relue). L'application n'utilise pas `assort` / `reassort` (décision du pharmacien).

**Vérification.** Deux `POST $B/suggestion-reserve/creer` avec le même `X-Client-Ref` → une seule suggestion, même
réponse.

**Référence.** `prestige_vente_app/docs/serveur/API_RESERVE_POSOS_FICHE_CLIENT.md` § 4.1 et § 5, point 2.

## 16. Réception BL : défauts qui faussent le stock (D1, D3, D4) — P1

**Applications** : Mobile.

**Pourquoi et quoi.**

- **D1. Effacement d'un lot sur tous les BL** (`OrderServiceImpl.removeLot`, appelé par `PUT v1/commande/remove-lots` ;
  vérifié : inchangé sur la branche du 13/10). Avec `removeLot = true`, `getLotByIdProduitAndNumLot` cherche le lot
  par **numéro de lot + produit seulement** : le même lot est supprimé **sur tous les BL**, y compris ceux déjà
  entrés en stock. `getWSByIdProduitAndRefBon` compare `TWarehouse.strREFLIVRAISON` au **numéro de lot** au lieu du
  n° de BL. Correction : toujours restreindre au BL (`strREFLIVRAISON = refBon AND lgFAMILLEID = idProduit`, plus
  `AND intNUMLOT = numLot` si `removeLot`), supprimer les `TWarehouse` sur `strREFLIVRAISON = refBon`, recalculer la
  ligne (D3), refuser si le BL est `is_Closed`.
- **D3. Quantité reçue non fiable.** `addNewLot` n'ajoute que les unités gratuites (UG) à `intQTERECUE` ;
  `cloturerBonLivraison` ne met `intQTERECUE = intQTECMDE` que pour les lignes sans lot. Règle unique demandée :
  *quantité reçue = somme des lots du produit sur ce BL (UG comprises), ou quantité commandée si la ligne est entrée
  sans lot*, recalculée à chaque ajout ou suppression de lot et à l'entrée en stock.
- **D4. Contrôles de quantité du retour incomplets** (`newItem`, `updateItem`, `addItem` : seul
  `quantité ≤ intQTERECUE` est vérifié). Refuser au-delà de : quantité reçue (D3) moins les quantités déjà retournées
  (`intQTERETURN`) et celles des autres retours encore `is_Process` sur la même ligne ; et du stock disponible
  (`TFamilleStock.intNUMBERAVAILABLE`).

**Compatibilité.** Le Mobile n'utilise aujourd'hui que `removeLot = false` (correct) ; il passera à l'effacement
d'un seul lot après D1. Il vérifie déjà quantité reçue et stock avant un retour.

**Vérification.** Deux BL avec le même produit et le même n° de lot : effacer le lot sur le BL 2 ne touche pas au
BL 1. Après chaque ajout ou suppression de lot, quantité reçue = somme des lots. Un retour ne dépasse jamais la
quantité reçue moins les retours déjà faits, ni le stock.

**Référence.** `prestige_vente_app/docs/ETAPE_D_SERVEUR_RECEPTION_RETOUR.md` D1, D3, D4 et § 7.

## 17. Réception BL et retour : autres défauts (D2, D6, D7, D8) — P2

**Applications** : Mobile.

**Pourquoi et quoi.**

- **D2.** Retour d'un produit absent du BL (`RetourFournisseurServiceImpl.newItem` →
  `getTBonLivraisonDetailLast(...).getSingleResult()`) : `NoResultException`, donc **500**. Utiliser
  `getResultList()` et répondre `{success:false, msg:"Ce produit n'est pas sur le BL <n°>"}`.
- **D6.** `creerbl` (`OrderServiceImpl.creerBonLivraison` → `createBL(..., int intMHT, int intTVA)`) : montant HT ou
  TVA absent → erreur. Remplacer `null` par 0 ; valider `ref` (obligatoire, 20 caractères au plus) et `dtStart`.
- **D7.** `addItem` cumule la quantité sur la ligne existante du produit et **garde le premier motif** : le motif
  envoyé est ignoré sans le dire. Option 1 (recommandée) : une ligne par (produit, motif, lot). Option 2 : refuser un
  motif différent avec un message.
- **D8.** `retourfournisseur/new` reçoit dans `lgBONLIVRAISONID` le **n° de BL**, et le serveur prend le plus récent
  des BL portant ce numéro ; deux grossistes peuvent avoir le même n°. Accepter aussi l'identifiant du BL (`blId`,
  prioritaire), à défaut le couple (n° de BL, grossiste). Les anciens appels restent valides.

**Compatibilité.** Corrections et ajouts ; le Mobile prévient déjà l'opérateur avant un cumul de motifs.

**Vérification.** Retour d'un produit absent du BL → message clair, plus de 500 ; `creerbl` sans montant → accepté
avec 0 ; deux BL de même numéro chez deux grossistes → le retour vise le bon.

**Référence.** `prestige_vente_app/docs/ETAPE_D_SERVEUR_RECEPTION_RETOUR.md` D2, D6, D7, D8.

## 18. Réception BL et retour : envoi hors ligne sans doublon (D17) — P2

**Applications** : Mobile.

**Pourquoi.** Pour garder les saisies de réception sans réseau et les renvoyer sans risque, chaque envoi doit être
reconnu s'il a déjà été reçu.

**Quoi.** La demande d'origine propose un identifiant `clientEventId` (UUID du téléphone) sur `add-lot`,
`retourfournisseur/new` et `add-item`, enregistré dans une table `t_mobile_evenement` à index unique ; un événement
déjà reçu renvoie le résultat d'origine sans rien enregistrer. **Recommandation de consolidation** : utiliser le
mécanisme déjà en place, l'en-tête `X-Client-Ref` et la table `mobile_client_ref` (demande F5), qui couvre déjà
`retourfournisseur/new`, plutôt qu'une seconde table. À trancher par le serveur.

**Compatibilité.** Sans en-tête : comportement actuel.

**Vérification.** Même clé envoyée deux fois sur `add-lot` → un seul lot enregistré, même réponse.

**Référence.** `prestige_vente_app/docs/ETAPE_D_SERVEUR_RECEPTION_RETOUR.md` D17 et § 7, critère 9.

## 19. Fiche client : mesures et enregistrement sans doublon — P2

**Applications** : Mobile.

**Pourquoi.** `POST v1/ordonnance-client/client/{id}/mesures` n'est pas idempotent, pas plus que `POST enregistrer` :
un double envoi crée un **doublon** dans le dossier patient (glycémie, tension…).

**Quoi.** Une clé d'idempotence (`X-Client-Ref`), ou le refus d'une mesure identique (même paramètre, même valeur,
même minute) sur une courte fenêtre.

**Compatibilité.** En attendant, l'application n'envoie qu'une fois par saisie ; un délai dépassé après l'envoi
indique que la mesure a peut-être été enregistrée et invite à vérifier l'historique avant de ressaisir.

**Vérification.** Deux envois identiques avec la même clé → une seule mesure dans `…/mesures?parametreId=`.

**Référence.** `prestige_vente_app/docs/serveur/API_RESERVE_POSOS_FICHE_CLIENT.md` § 4.3 et § 5, point 10.

## 20. Création d'inventaire : erreur 500, identifiant créé, inventaire partiel — P2

**Applications** : Inventaire.

**Pourquoi.** Sur le serveur de test, `POST /v1/inventaire/creation` répond **500** : `NullPointerException` dans
`toolkits.utils.jdom.LoadRessource` (fichier de configuration chiffré `config_laborex_v1.xml` absent), levée par
`new dataManager()` **avant** le `try` de `InventaireRessource.creerInventaire` : le `catch` ne la rattrape pas.
Chez le client le fichier existe probablement (le poste crée des inventaires) : **à vérifier**. De plus, la réponse
ne contient pas l'identifiant créé : l'application retrouve l'inventaire par son libellé (fragile si deux
inventaires ont le même nom). Enfin, une création interrompue peut laisser un inventaire partiel ouvert
(`InventaireManager` l. 63 : « Inventaire incomplet non supprime »).

**Quoi.**

1. **D1** : mettre `new dataManager()` / `initEntityManager()` **dans** le `try` (réponse `incident(...)` lisible) ;
   idéalement passer la création par la couche JPA (`InventaireService`, comme `create(...)` /
   `createReserveInventaireDetaille(...)`) ; **atomicité** : rien de partiel en cas de coupure ;
2. **D2** : renvoyer l'identifiant : `{"success":1,"lignes":1794,"nombre":"…","lgInventaireId":"…","libelle":"…"}` ;
3. **D3** : inventaire partiel par rayons : confirmer le contrat `str_TYPE_TRANSACTION = "Emplacement"` +
   `valeurs = [lg_ZONE_GEO_ID…]` (identifiants de `GET /v1/common/rayons`) ; refuser une valeur inconnue
   (`"Rayon inconnu : …"`) au lieu de l'ignorer ; renvoyer `rayons` (nombre de rayons retenus).

**Compatibilité.** Ajouts. Détection par la présence de `lgInventaireId`. Le choix « Rayons choisis » n'est proposé
par l'application que lorsque la création fonctionne.

**Vérification.**

```bash
curl -s -b cj -H 'Content-Type: application/json' \
  -d '{"str_NAME":"Test partiel","str_TYPE_TRANSACTION":"Emplacement","valeurs":["<lg_ZONE_GEO_ID>"]}' \
  $B/inventaire/creation      # success:1, lgInventaireId présent, rayons:1 ; jamais 500
```

**Référence.** `prestinv/docs/DEMANDE_SERVEUR_COMPTAGE.md` § D.

## 21. Une lecture en échec ne doit jamais rendre une liste vide — P2

**Applications** : Inventaire (règle utile à toutes).

**Pourquoi.** Les lectures d'inventaire de `InventaireServiceImpl` (toutes les `fetch*`) renvoient `List.of()` en cas
d'exception. L'application ne peut pas distinguer « aucun produit » d'une **panne** : un rayon peut sembler terminé
alors que la base ne répond pas.

**Quoi.** En cas d'échec : HTTP 500 avec `{"success":0,"message":"…"}`, jamais `[]`.

**Compatibilité.** Les applications traitent déjà un 5xx comme une erreur avec « Réessayer ».

**Vérification.** Panne simulée de la base pendant `GET $B/ws/inventaires/details…` → 500, pas `[]`.

**Référence.** `prestinv/docs/DEMANDE_SERVEUR_COMPTAGE.md` § 0 (dernière ligne du tableau) et § 3, règle 2.

---

# C. Écritures cachées dans des lectures

Une lecture (GET) ne devrait rien modifier : sur un téléphone, une prévisualisation, un rechargement ou un
préchargement peuvent l'appeler sans intention. L'annulation de vente en GET est traitée en demande 6.

## 22. `GET /avis-clients/avis/{id}` marque l'avis « lu » — P2

**Applications** : Pharmacien.

**Pourquoi.** Lire un avis le fait passer de NOUVEAU à LU pour toute l'équipe. Sur mobile, un simple aperçu ou un
rechargement marquerait des avis comme lus sans que personne ne les ait lus. Vérifié sur la branche du 13/10 :
le service sait déjà ne pas marquer (`AvisClientService.detail(id, marquerLu)`), mais la route l'appelle toujours
avec `true` (`AvisClientRessource` l. 166-175). Le droit de lecture (`refus(LIRE)`) est, lui, vérifié.

**Quoi.** Paramètre `marquerLu`, `true` par défaut (le poste web ne change pas) :
`GET /avis-clients/avis/{id}?marquerLu=false` rend l'avis sans changer son statut. Le mobile marquera « lu » par un
appel explicite (`POST /avis-clients/avis/{id}/traiter` avec `{statut:"LU"}`, ou une route dédiée).

**Compatibilité.** Rétrocompatible. En attendant, l'application n'ouvre le détail d'un avis que sur un toucher
explicite (jamais depuis la liste ou l'analyse).

**Vérification.** `curl -s -b cj "$B/avis-clients/avis/<id>?marquerLu=false"` sur un avis NOUVEAU → il reste NOUVEAU.

**Référence.** `prestige_app/docs/serveur/DEMANDE_ECRITURES_SENSIBLES.md` § 6 ; `prestige_app/docs/NOTE_VERSION_3.4.0.md` (question 3).

## 23. Prévisions : les lectures réécrivent « en cours de commande » — P3

**Applications** : Pharmacien (et poste web).

**Pourquoi.** `PrevisionCommandeServiceImpl.rafraichirEnCours(emplacement)` est appelé au début de `tableau()`
(`GET /analyse-commande/tableau`), `previsions()` (`GET /analyse-commande/previsions`, donc **à chaque page
« Afficher plus »**), `toutes()` (exports), `produit()` (`GET /analyse-commande/produit/{id}`) et `analyser()`
(`GET /analyse-commande/analyse`). À chaque appel : relecture de toutes les commandes en cours, lecture de toutes
les lignes de prévision, puis un `UPDATE t_prevision_produit` par produit dont l'en-cours a changé. L'application
ne peut pas l'éviter (elle évite déjà les appels inutiles).

**Quoi.**

- mémoriser par emplacement l'heure du dernier rafraîchissement (en mémoire du service, ou colonne `dt_EN_COURS`
  dans `t_prevision_calcul`) et **ne rien refaire s'il date de moins de X minutes** (paramètre
  `KEY_PREVISION_EN_COURS_MINUTES`, 15 par défaut, 0 = comportement actuel) ;
- le refaire de toute façon après une création, réception ou suppression de commande (remettre l'heure à zéro) ;
- exposer l'heure dans `GET /analyse-commande/tableau` : `"enCoursAJour": "14/10/2026 09:42"` ;
- éventuellement `?rafraichir=1` pour forcer (bouton ⟳).

**Compatibilité.** Aucun changement de format nécessaire : rétrocompatible.

**Vérification.** Deux `GET $B/analyse-commande/previsions` à une minute d'intervalle : un seul rafraîchissement
(journal ou nombre d'`UPDATE`) ; après une réception de commande, rafraîchissement refait.

**Référence.** `prestige_app/docs/serveur/DEMANDE_ECRITURES_SENSIBLES.md` § 8 ; `prestige_app/docs/NOTE_VERSION_3.2.1.md` § 2.3.

## 24. Pilotage : `GET /pilotage/controler` écrit en base — P3 (constat)

**Applications** : Pharmacien.

**Pourquoi.** `GET /pilotage/controler` relit ventes et chiffre d'affaires des mois affichés et **recalcule en base**
ceux qui ont changé. Le web l'appelle à l'ouverture du menu et sur « Actualiser » (`PilotageCtr.actualiserEtControler`,
délai 120 s). Le mobile ne l'appelle **que** sur le bouton « Contrôler les chiffres », après confirmation, une fois
par appui. Aucune demande formelle n'a été faite : le constat est signalé pour cohérence avec la règle « un GET
n'écrit pas ».

**Quoi (à décider par le serveur).** Si la règle est retenue : une variante POST de la même opération, le GET
restant pour le web le temps de la transition. Ne rien changer est acceptable : le mobile est déjà protégé.

**Compatibilité.** Aucune obligation.

**Vérification.** —

**Référence.** `prestige_app/docs/NOTE_VERSION_3.2.0.md` § 2. (Voir aussi la question sur le passage automatique
« en cours » à l'ouverture d'une suggestion, `prestige_app/docs/NOTE_VERSION_3.3.0.md`, question 5.)

---

# D. Données manquantes et nouvelles routes

## 25. Détail Mobile Money par opérateur dans `/ca-all` — P2

**Applications** : Pharmacien (module « Détail CA »).

**Pourquoi.** Le pharmacien veut déplier la ligne « Mobile Money » et voir chaque opérateur (Orange, Wave, MTN,
Moov, Djamo…). `GET /ca-all` (`ErpRessource` → `ErpServiceImpl.caAll`, DTO `ErpCaComptant`) ne renvoie que le total
`totMobile` par jour. Le détail est **déjà calculé** par la requête des encaissements (`GROUP BY m.mvtdate,
v.type_regelement`) puis **perdu** dans le `switch` qui additionne les codes mobiles (7, 8, 9, 10, 19, 70, 80 et les
modes `str_CATEGORIE='MOBILE_MONEY'` reconnus par `MobileMoney.est`). En attendant, l'application appelle
`GET /stats-recette-caisse/modes`, qui calcule autrement (date du règlement, statut `is_Closed`, autres exclusions,
emplacement de l'utilisateur) : la somme des opérateurs peut **différer** de `totMobile` et l'écran affiche une
ligne « Autres / écart ». Ce n'est pas satisfaisant, et cela coûte une requête de plus.

**Quoi (solution recommandée, rétrocompatible).**

1. ajouter à `ErpCaComptant` un champ `detailMobile` : liste de `{modeId, libelle, montant}` par jour (`modeId` =
   `v.type_regelement` en texte ; `libelle` = `t_type_reglement.str_NAME` ; `montant` = la même somme
   `montant_attentu` que celle ajoutée à `totMobile`) ;
2. requête des encaissements : `JOIN t_type_reglement r ON r.lg_TYPE_REGLEMENT_ID = v.type_regelement`, `r.str_NAME`
   au `SELECT` et au `GROUP BY` ;
3. dans **chaque branche mobile** du `switch`, en plus de `setTotMobile(...)`, ajouter la ligne à `detailMobile` :
   ainsi Σ `detailMobile.montant` = `totMobile` **par construction** ;
4. jour sans Mobile Money : `detailMobile: []` (ou champ absent).

Variante (si le DTO ne doit pas changer) : `GET /ca-all/mobile?dtStart=&dtEnd=` avec **exactement** les filtres de
la requête de `caAll`, réponse `{totMobile, operateurs:[{modeId, libelle, montant}]}` triée par montant.

**Compatibilité.** Les anciennes versions ignorent le champ. L'application 3.2.1+30 **le prend déjà en charge** : dès
que chaque jour avec Mobile Money porte `detailMobile`, elle n'appelle plus `/stats-recette-caisse/modes` et
n'affiche plus de ligne d'écart.

**Vérification.** `curl -s -b cj "$B/ca-all?dtStart=2026-10-01&dtEnd=2026-10-13"` : pour chaque jour,
Σ `detailMobile[].montant` = `totMobile`.

**Référence.** `prestige_app/docs/serveur/DEMANDE_DETAIL_MOBILE_MONEY.md` ; `prestige_app/docs/NOTE_VERSION_3.2.1.md`.

## 26. Visualisation BL : filtres groupe et utilisateur ignorés — P2

**Applications** : Pharmacien.

**Pourquoi.** Les écrans (ancien et nouveau) de Visualisation BL envoient `groupeId`, `userId` et `checked` à
`GET /etat-control-bon/list`, qui ne lisait que `search`, `grossisteId`, les dates, `statutControle` et `ecart` : le
pharmacien filtre, mais **la liste ne change pas**. Vérifié sur la branche du 13/10 : `groupeId` est désormais lu
(`grossisteId = cible(grossisteId, groupeId)`, `EtatControlBonResource` l. 51-59) ; `userId` et `checked` ne le
sont toujours pas.

**Quoi.** Prendre en compte `userId` (BL de l'utilisateur choisi) ; pour `checked`, soit le lire, soit confirmer que
l'application doit passer au filtre de statut du serveur (`statutControle`), question posée au pharmacien.

**Compatibilité.** Paramètres déjà envoyés : aucun changement côté application si le serveur les lit.

**Vérification.** `curl -s -b cj "$B/etat-control-bon/list?dtStart=…&dtEnd=…&userId=<id>"` → seuls les BL de cet
utilisateur ; avec `groupeId` → seuls ceux du groupe.

**Référence.** `prestige_app/docs/NOTE_VERSION_3.3.0.md`, questions pour le pharmacien, point 1.

## 27. Inventaire : auteur et heure de chaque saisie — P2

**Applications** : Inventaire.

**Pourquoi.** Pour contrôler un écart et faire recompter (« qui a compté l'AUGMENTIN ? »), le pharmacien doit
connaître l'auteur et l'heure de la dernière saisie. La colonne `t_inventaire_famille.str_UPDATED_ID` existe mais
reste **vide** sur le chemin d'écriture le plus utilisé (`PUT /ws/inventaires/details` ; 24 lignes sur 24 sans
auteur dans la base de test ; toujours vrai sur la branche du 13/10). Les lectures ne renvoient pas l'auteur.

**Quoi.**

1. **Écriture** : dans `InventaireServiceImpl.updateDetailQuantity`, comme dans `updateQuantiteLigne` :
   `TUser auteur = sessionHelperService.getCurrentUser(); if (auteur != null) ligne.setStrUPDATEDID(auteur.getLgUSERID());`
   (ne jamais effacer un auteur existant) ;
2. **Lecture** : ajouter à `DetailInventaireDTO` (donc à `ws/inventaires/details`, `detailsAll`,
   `detailsTouchedRayon`, `detailsUntouchedRayon`, `detailsAllTouched`, `detailsAllUntouched`, `detailsAllEcarts`) :
   `auteurId` (`null` si vide), `auteurLogin` (`t_user.str_LOGIN`), `auteurNom` (prénom + nom). JPQL :
   `LEFT JOIN TUser u ON u.lgUSERID = o.strUPDATEDID`, constructeur supplémentaire (les existants restent).

**Compatibilité.** Champs ajoutés, ignorés par les anciennes versions. Les versions récentes envoient déjà le cookie
de session sur ce PUT : l'auteur sera renseigné **dès le déploiement, sans mise à jour de l'application**.

**Vérification.** PUT avec session → `str_UPDATED_ID` = l'utilisateur ; les 7 routes de lecture renvoient
`auteurId/auteurLogin/auteurNom` ; mêmes champs, valeurs, tri et nombre de lignes qu'avant.

**Référence.** `prestinv/docs/DEMANDE_SERVEUR_COMPTAGE.md` § B.

## 28. Réserve : listes filtrées par emplacement, suggestion annulée close — P2

**Applications** : Mobile.

**Pourquoi.** `GET v1/suggestion-reserve/liste` et `GET …/{id}` ne filtrent pas par emplacement : un mobile
multi-sites verrait les suggestions des autres sites. `PUT …/{id}/ouvrir` ne traite pas une suggestion `ANNULEE`
comme close et prend un verrou inutile.

**Quoi.** Ajouter le filtre d'emplacement de l'utilisateur à `liste`, `{id}` et `ouvrir` ; traiter `ANNULEE` comme
close dans `ouvrir`.

**Compatibilité.** L'application utilise `en-attente` (qui filtre déjà) à la place de `liste`.

**Vérification.** Utilisateur de l'emplacement A : `GET $B/suggestion-reserve/liste` ne renvoie aucune suggestion de
B ; `PUT $B/suggestion-reserve/<id annulée>/ouvrir` → refus, aucun verrou.

**Référence.** `prestige_vente_app/docs/serveur/API_RESERVE_POSOS_FICHE_CLIENT.md` § 5, points 3 et 5.

## 29. Routes de comptage légères pour l'accueil — P3

**Applications** : Pharmacien.

**Pourquoi.** L'accueil affiche le nombre de chaque alerte **à la demande** (bouton ⟳). Pour le contrôle des BL,
l'application télécharge aujourd'hui **la liste complète** (`etat-control-bon/list-annuelle … limit=9999`, montants
et totaux) pour n'en garder qu'un entier.

**Quoi.** Des routes qui ne renvoient qu'un nombre, avec **les mêmes filtres et la même session** que la route de
liste, un `SELECT COUNT(*)` sans totaux, les mêmes réponses d'erreur :

```
GET /api/v1/etat-control-bon/nombre?dtStart=2026-10-14&dtEnd=2026-10-14&groupeId=   → {"success":true,"nombre":7}
GET /api/v1/fichearticle/perimes/nombre?query=&nbreMois=&codeRayon=&codeGrossiste=&dtStart=&dtEnd=  → {"success":true,"nombre":3}
GET /api/v1/avis-clients/nombre?statut=NOUVEAU
GET /api/v1/pointage-bl/nombre?etat=NON_POINTES&du=&au=
```

Le nombre doit être celui que montre l'écran du module à l'ouverture. `perimes/nombre` n'est utile que si l'écran
Suivi Péremption garde sa propre définition (depuis la vague 1, `GET /tableau-bord/alertes` compte les péremptions).
`GET /rappels-habitude/compteur` existe déjà (même principe).

**Compatibilité.** Routes nouvelles. Une fois livrées, l'application remplacera les appels de
`AlertesAccueil._appel` (comportement visible inchangé).

**Vérification.** `etat-control-bon/nombre` = `metaData.totalNbreBon` de `list-annuelle` pour les mêmes filtres.

**Référence.** `prestige_app/docs/serveur/ROUTES_DE_COMPTAGE.md` ; `prestige_app/docs/serveur/DEMANDE_ECRITURES_SENSIBLES.md` § 7.

## 30. Inventaire : état de tous les rayons en une requête — P3

**Applications** : Inventaire.

**Pourquoi.** Pour afficher « ANTIBIOTIQUES : 38 / 52 comptés », l'application fait **2 requêtes par rayon**
(`detailsTouchedRayon`, puis `detailsUntouchedRayon`) qui renvoient **toutes les lignes** (40 rayons = 80 requêtes),
alors qu'il ne faut qu'un compte. Sur les terminaux Sunmi (2 Go de mémoire, Wi-Fi chargé), cela prend plusieurs
secondes, et charge le serveur quand plusieurs terminaux comptent en même temps.

**Quoi.** `GET /api/v1/ws/inventaires/{idInventaire}/rayons/etat` (dans `ErpRessource`), **session exigée**,
paramètre facultatif `avecAuteurs=1`. Réponse : tableau trié comme `ws/inventaires/rayons` :
`{rayonId, code, libelle, totalProduits, comptes, restants, derniereSaisie, auteurs?}` ; `totalProduits` = lignes
`bool_INVENTAIRE = 1`, `comptes` = parmi elles `dt_UPDATED IS NOT NULL`, `derniereSaisie` = `MAX(dt_UPDATED)` ;
même ensemble de rayons que `ws/inventaires/rayons`. Inventaire inexistant → **410**
`{"success":0,"code":"INVENTAIRE_INCONNU"}` (pas 404) ; panne → 500 (jamais `[]`). La requête SQL de référence
(un accès par l'index `lg_INVENTAIRE_ID`) et les tests sont dans le document d'origine ; un produit présent chez deux
grossistes doit être compté **une** fois. Objectif : moins de 300 ms pour environ 1 800 produits.

**Compatibilité.** Route nouvelle. 404 / 405 → l'application garde son calcul actuel (2 requêtes par rayon, à la
demande).

**Vérification.** Pour chaque rayon : `comptes` = nombre de lignes de `detailsTouchedRayon`, `restants` = celui de
`detailsUntouchedRayon`.

**Référence.** `prestinv/docs/DEMANDE_SERVEUR_COMPTAGE.md` § A ; `prestinv/docs/NOTE_VERSION_REFONTE.md`.

## 31. Photo de contrôle du pointage par badge — P3

**Applications** : Mobile (terminal de pointage).

**Pourquoi.** Le pharmacien veut empêcher qu'un employé pointe avec le badge d'un collègue. L'application prend déjà
une photo (caméra frontale, JPEG 640 px, moins de 100 Ko) à chaque pointage par badge, mais **le serveur ne peut
pas la recevoir** : `POST v1/rh/pointages` (`RhRessource.saisirPointage`) ne renvoie pas l'identifiant du pointage, et
`t_pointage` n'a pas de colonne photo. La photo reste donc sur le terminal (stockage privé, 30 jours par défaut).

**Quoi.**

1. `POST v1/rh/pointages` : champ facultatif `id` (UUID du terminal, utilisé comme `t_pointage.id`, toujours renvoyé
   dans la réponse ; même `id` renvoyé → réponse « pointage déjà existant ») et `controle` (`{photo:true}` ou
   `{photo:false, motif:"PERMISSION_REFUSEE"|"CAMERA_ABSENTE"|…}`) rangé dans deux colonnes `photo_statut` (`AVEC`,
   `SANS`, `ATTENDUE`) et `photo_motif` ;
2. `POST v1/rh/pointages/{id}/photo` (multipart, champ `photo` JPEG, `prise` facultatif ; droit `P_SM_RH`) :
   150 Ko au plus, JPEG vérifié sur les octets (`FF D8 FF`), 1024 px au plus, pointage `MANUEL` avec un motif
   commençant par « Badge terminal », une seule photo par pointage (remplacement idempotent) ; table
   `t_pointage_photo` (schéma dans le document d'origine) ;
3. `GET v1/rh/pointages/{id}/photo` (`image/jpeg`, `P_SM_RH`, `Cache-Control: no-store`) ; champs `photo` et
   `photoMotif` dans `GET v1/rh/presence` ;
4. conservation : `KEY_RH_PHOTO_RETENTION_JOURS` (30 par défaut, de 7 à 90), purge quotidienne de la photo seule,
   suppression en cascade avec le pointage ; durée renvoyée dans `GET rh/droits` ;
5. confidentialité (loi ivoirienne n° 2013-450, ARTCI) : finalité unique, accès `P_SM_RH` tracé, aucune photo dans
   les journaux ni les exports, HTTPS en production.

**Compatibilité.** Un serveur ancien ignore `id` et `controle`. 404 sur la route photo → l'application reste en mode
local, sans erreur pour l'employé.

**Vérification.** Pointage avec `id` → même `id` dans la réponse ; envoi d'une photo de 200 Ko → refus ; d'un fichier
non JPEG → refus ; `GET …/photo` sans `P_SM_RH` → refus.

**Référence.** `prestige_vente_app/docs/serveur/DEMANDE_PHOTO_POINTAGE.md`.

## 32. Choix multiples (« id1,id2 ») sur d'autres routes — P3

**Applications** : Pharmacien.

**Pourquoi.** Le pharmacien pourrait vouloir plusieurs emplacements, grossistes ou fournisseurs à la fois dans
d'autres écrans (Visualisation BL, achats…). Ces routes n'acceptent qu'un identifiant.

**Quoi.** Accepter des identifiants séparés par des virgules, comme `ca-zone-geo` le fait depuis le 13/10
(`util.FiltreListe`, `zoneId`, `familleId`, `grossisteId`). À confirmer par le pharmacien, écran par écran.

**Compatibilité.** Un seul identifiant reste valable.

**Vérification.** `grossisteId=G1,G2` → lignes des deux grossistes.

**Référence.** `prestige_app/docs/NOTE_VERSION_3.3.0.md`, question 2 ; `prestige_app/docs/NOTE_VERSION_3.2.1.md` § 2.4.

## 33. Réserve : ajouter un produit à une suggestion, PDF en REST — P3

**Applications** : Mobile.

**Pourquoi et quoi.** Il n'existe **aucune route pour ajouter un produit** à une suggestion existante : il faut en
recréer une (demande : une route d'ajout de ligne). L'impression d'une suggestion passe par une JSP
(`ws_generate_pdf_suggestion.jsp`) : une route REST `v1/suggestion-reserve/{id}/pdf` serait plus propre (non utilisée
par l'application aujourd'hui).

**Compatibilité.** Routes nouvelles.

**Vérification.** Ajout d'un produit à une suggestion `A_TRAITER` → ligne visible dans `ouvrir`.

**Référence.** `prestige_vente_app/docs/serveur/API_RESERVE_POSOS_FICHE_CLIENT.md` § 5, points 4 et 7.

## 34. Fiche client : route agrégée, modification de l'identité, réponses JSON — P3

**Applications** : Mobile.

**Pourquoi et quoi.**

- une route agrégée pour l'identité, les tiers payants et les ayants droit, sous `P_ORDONNANCE_CLIENT` (lecture) /
  `P_ORDONNANCE_CLIENT_MAJ` (écriture) ;
- la modification de l'identité sous `P_ORDONNANCE_CLIENT_MAJ` ;
- les dépôts de fichiers (pièces, scans) répondent en `text/html` : une variante `application/json` est souhaitée.

**Compatibilité.** Ajouts. L'identité est en lecture seule dans l'application en attendant.

**Vérification.** —

**Référence.** `prestige_vente_app/docs/serveur/API_RESERVE_POSOS_FICHE_CLIENT.md` § 5, points 11 et 12.

## 35. Posos : historique et routes unitaires — P3

**Applications** : Mobile.

**Pourquoi et quoi.** Il n'existe ni historique ni trace des analyses, ni route unitaire (posologie usuelle d'un
produit, interaction entre deux produits). Souhaités, sans format imposé.

**Compatibilité.** Ajouts.

**Référence.** `prestige_vente_app/docs/serveur/API_RESERVE_POSOS_FICHE_CLIENT.md` § 5, point 9.

## 36. Réception BL mobile : fonctions à ajouter (D10 à D16, D18) — P3

**Applications** : Mobile.

**Pourquoi.** La réception BL et le retour fournisseur fonctionnent sur mobile avec les routes existantes. Ces ajouts
apportent traçabilité, rapports et travail à plusieurs.

**Quoi** (détail complet dans le document d'origine) :

| Point | Contenu |
|---|---|
| D10 | `GET v1/reception/parametres` → `{peremptionObligatoire, moisPeremptionCourte, motifObligatoirePeremptionCourte, scansRepetesActifs}` (nouvelle clé `KEY_RECEPTION_MOIS_PEREMPTION_COURTE`, 6 par défaut) |
| D11 | `GET v1/commande/bon/items/{detailId}/lots` (lots avec auteur et heure) ; `DELETE v1/commande/bon/lots/{lotId}` (droit `P_BL_MOBILE_CORRIGER`, BL non clôturé, recalcul D3) |
| D12 | journal et rapport des péremptions courtes acceptées ou refusées (table `t_reception_peremption_courte`, `POST`/`GET v1/reception/peremptions-courtes`, export) |
| D13 | anomalies de réception (table `t_reception_anomalie`, types `PRODUIT_NON_PREVU`, `ECART_QUANTITE`, `LOT_PERIME_REFUSE`, `PRODUIT_DIFFERENT_DATAMATRIX`, `SERIE_DEJA_CONSOMMEE` ; `POST`/`GET v1/reception/anomalies`) |
| D14 | lot retourné : `num_lot` dans `t_retour_fournisseur_detail`, `RetourDetailsDTO.numLot`, décrément de `TLot.currentStock` |
| D15 | `GET v1/retourfournisseur/en-preparation?blId=&utilisateur=` (reprendre un retour en préparation) |
| D16 | présence et verrou temporaire sur un BL (table `t_reception_session`, `POST`/`GET v1/reception/{blId}/presence`, verrou de 2 min sur ligne + lot) |
| D18 | numéro de série DataMatrix (table `t_serie_consommee`, index unique GTIN + série ; champ `serie` sur `add-lot` ; « Boîte déjà scannée ») |

Ordre proposé : lot 2 (D9 + D10), lot 3 (D11, D15, D14, D7, D8), lot 4 (D12, D13), lot 5 (D16, D17, D18).

**Compatibilité.** Routes et tables nouvelles. Choix à faire sur le préfixe (voir « Contradictions » : la demande
d'origine propose `v1/mobile/reception/…` avec jeton Bearer).

**Vérification.** Critères d'acceptation 7 et 8 du document d'origine ; tests de bout en bout dans `src/test/e2e/`.

**Référence.** `prestige_vente_app/docs/ETAPE_D_SERVEUR_RECEPTION_RETOUR.md` D10 à D16, D18, § 5 et § 6.

## 37. Inventaire : versement de collecte en lot — P3 (optionnel)

**Applications** : Inventaire.

**Pourquoi.** Verser une collecte hors ligne fait, par produit, une recherche « déjà compté » puis une écriture :
300 produits = 600 requêtes, avec un risque d'écraser la saisie d'un collègue entre la lecture et l'écriture.

**Quoi.** `POST /api/v1/inventaire/{idInventaire}/versement` (session exigée), corps
`{cle, mode:"ajouter"|"remplacer", lignes:[{code, quantite}]}` (500 lignes au plus, 413 au-delà) ; `ajouter` fait
`int_NUMBER = int_NUMBER + ?` **dans la même transaction** ; `code` = CIP, EAN ou code grossiste (correspondance
exacte) ; rapport par ligne (`ok`, `inconnu`, `ambigu` avec `lignesPossibles`, `refuse`) ; auteur et `dt_UPDATED`
renseignés. **Idempotence** par `cle` : même clé → même rapport avec `dejaTraite:true` (table
`t_inventaire_versement`, purge à 30 jours) ; même clé, contenu différent → 409 `CLE_REUTILISEE`. Erreurs : 401, 409
`INVENTAIRE_CLOTURE`, 410, 413, 400.

**Compatibilité.** Route nouvelle ; 404 / 405 → versement actuel ligne par ligne.

**Vérification.** `ajouter` deux fois avec la même clé → une seule addition ; deux terminaux en même temps → somme
exacte.

**Référence.** `prestinv/docs/DEMANDE_SERVEUR_COMPTAGE.md` § F ; `prestinv/docs/ANALYSE_PRESTINV.md` § 3.3.

## 38. Questions ouvertes : pagination, rappels « Racheté », actualisation — P3 (à confirmer)

**Applications** : Pharmacien.

Points posés au pharmacien ; ils ne deviennent des demandes que s'il les valide :

- **Suivi Ajustements limité à 100** ajustements par période (comme l'écran d'origine) : faut-il une pagination
  (« Afficher plus ») côté serveur ?
- **« Racheté » à la main** : la route `marquer` des rappels n'accepte que À préparer, Préparé, Écarté ; « Racheté »
  n'est posé que par l'actualisation. Faut-il l'accepter ?
- **Actualisation des rappels** : sans « Actualiser » sur le mobile, la liste dépend du calcul du web (ou de la nuit).
  Faut-il une actualisation programmée côté serveur ?

(Le Fichier Journal, lui, est déjà paginé par le serveur : voir F8.)

**Référence.** `prestige_app/docs/NOTE_VERSION_3.3.0.md` (question 3) ; `prestige_app/docs/NOTE_VERSION_3.4.0.md`
(questions 1 et 2).

---

# E. Performance

Les demandes de performance sont surtout dans les demandes 23 (prévisions), 29 (comptages), 30 (état des rayons),
37 (versement en lot) et F6 (catalogue différentiel, fait).

## 39. Analyse de garde et péremptions : calculs complets répétés — P3 (constat)

**Applications** : Pharmacien.

**Pourquoi.** Deux constats, sans demande formelle :

- l'analyse d'une garde est **recalculée entièrement à chaque page** demandée (calcul complet puis découpe
  `start` / `limit`). L'application demande désormais les produits par 100 (au lieu de 25) et garde ce qui est
  chargé ;
- `GET /fichearticle/perimes` calcule aussi `metaData` (totaux quantités / valeurs) **sur tous les lots**, même pour
  20 lignes demandées.

**Quoi (suggestion).** Si le serveur le juge utile : garder le résultat du calcul d'une garde quelques minutes pour
servir les pages suivantes. Sinon, rien à faire.

**Référence.** `prestige_app/docs/NOTE_VERSION_3.2.1.md` § 2.2 ; `prestige_app/docs/serveur/ROUTES_DE_COMPTAGE.md` (tableau).

---

# F. Patchs prêts à appliquer (dépôt `prestige_vente_app`, dossier `docs/serveur/`)

Cinq patchs ont été préparés par la session de l'application Mobile, dans l'ordre **H4 → H5 → O4 → O5 → B3**, sur la
branche `b9e03367` (11/10/2026), compilés (`mvn -o compile`, JDK 11), routes sous le préfixe `v1/app-vente/…`
(session cookie habituelle, **sans modifier** `AuthenticationFilter`), sauf B3 (`v1/paiements-mobile/…`).
Application : `git am <patch>` puis `mvn -DskipTests package` et
`asadmin redeploy --name prestige --contextroot prestige target/prestige.war`.

**État constaté sur la branche du 13/10** : **H4 et H5 sont déjà intégrés** (voir F5, F6). O4, O5 et B3 ne le sont pas.
Les patchs O4 et O5 ont été construits **au-dessus** de H4 + H5 tels que patchés : ils modifient
`MobileCapacitesRessource.java` (créé par H4) ; un `git am` sur la branche actuelle peut donc demander un petit
rebasage si l'intégration de H4 / H5 diffère du patch.

## 40. O4 : apprentissages des ordonnances partagés entre terminaux — P3

**Applications** : Mobile.

**Pourquoi.** Quand le pharmacien valide ou corrige le produit lu sur une ordonnance manuscrite, le téléphone retient
« ce qui a été lu → le bon produit ». O4 partage ces apprentissages entre les terminaux de la pharmacie.

**Quoi (résumé du patch).** `POST v1/app-vente/ordonnances/corrections` (lot de 500 au plus,
`{corrections:[{cle, segment, produitId, cip, nom, at}]}`, idempotent par `cle`, contrôles : segment de 3 à 60
caractères, produit existant) ; `GET …/corrections?depuis=&jusqua=&start=&limit=` (lecture différentielle à
l'horloge du serveur) ; capacité `ordonnanceCorrections:true` dans `GET v1/app-vente/capacites`. Nouvelle table
`mobile_ordonnance_correction` (migration `V6.9.132.3`), aucune table existante modifiée. **Données de santé** : le
téléphone n'envoie que le « segment médicament » normalisé (jamais nom, date, téléphone, posologie).

**Compatibilité.** Sans O4 : apprentissage sur le téléphone seulement. Partage désactivable sur chaque téléphone.

**Vérification.** Voir § 6 du document : `enregistres:1`, puis `dejaConnus:1` au renvoi ; segment « Jean Dupont 06 12
34 56 78 » rejeté ; 401 sans session.

**Référence.** `prestige_vente_app/docs/serveur/O4_CORRECTIONS.md` ; patch `prestige_vente_app/docs/serveur/O4_corrections_ordonnances.patch`.

## 41. O5 : lecture avancée des ordonnances (service en ligne) — P3

**Applications** : Mobile.

**Pourquoi.** Quand la lecture sur le téléphone échoue, le pharmacien peut, **avec consentement**, faire lire la
seule zone des médicaments par un service en ligne (décision du client : « oui, sans envoyer les informations du
patient »).

**Quoi (résumé du patch).** `POST v1/app-vente/ordonnances/lecture-avancee` (corps : image JPEG de la zone des
médicaments, 4 Mo au plus) → `{lignes:[{nom, dosage, forme, posologie, quantite, confiance}], fournisseur, modele,
coutEstime, quotaRestant}`. Fournisseurs : Claude (par défaut `claude-haiku-5-5`) ou Google Cloud Vision. Garde-fous :
une lecture à la fois, délai de 30 s, aucune relance automatique, quota par jour (50 par défaut). **L'image n'est
jamais enregistrée** ; réponse filtrée (lignes « Dr / Mme / Patient / date / téléphone » retirées) ; journal sans
image ni texte (table `mobile_lecture_avancee_journal`, migration `V6.9.132.4`). **Clé d'API** uniquement côté
serveur : variable d'environnement, propriété système, ou fichier `lecture-avancee.properties` dans le dossier de
configuration (`D:\prestige\config` sous Windows). Sans clé : capacité `lectureAvancee:false`, rien ne change.

**Compatibilité.** Sans O5 ou sans clé : le bouton n'apparaît pas.

**Vérification.** Voir § 5 du document (503 sans configuration, 400 si pas un JPEG, 429 sur deux envois simultanés).

**Référence.** `prestige_vente_app/docs/serveur/O5_LECTURE_AVANCEE.md` ; patch `prestige_vente_app/docs/serveur/O5_lecture_avancee.patch`.

## 42. B3 : paiements Mobile Money par agrégateur — P3

**Applications** : Mobile (comptoir et borne).

**Pourquoi.** Encaisser par Orange, MTN, Moov ou Wave avec confirmation automatique (lien ou QR), sans saisie
manuelle. L'agrégateur n'est pas encore choisi (décision reportée par le client).

**Quoi (résumé du patch).** Routes `v1/paiements-mobile/…` (session) : `capacites`, création
(`{venteId, operateur, part?, cloturer}` + `X-Client-Ref`), statut revérifié chez le fournisseur, annulation,
historique du jour, simulateur ; **webhooks publics** `v1/paiements-mobile/notification/{cinetpay|wave|simulateur}`
et page `retour` (B3 est le seul patch qui ajoute des chemins à `SKIP_PATHS`). Montant **fixé par le serveur**,
signature HMAC vérifiée puis statut relu chez le fournisseur, ligne verrouillée, **jamais deux encaissements**
(paiement tardif → `paye_apres_annulation`). Clôture automatique de la vente (modes 7 Orange, 8 Moov, 9 MTN,
10 Wave) si la caisse est ouverte. Table `paiement_mobile` (migration `V6.9.129.20`). **Désactivé par défaut.**

**Ce que la pharmacie doit fournir** : un compte marchand (CinetPay recommandé) et ses clés (variables
d'environnement du service, jamais dans l'application), une **adresse publique HTTPS** du serveur (voir la notice
`HTTPS_SERVEUR_WINDOWS.md`), l'URL de notification à déclarer
(`https://<adresse>/prestige/api/v1/paiements-mobile/notification/<cinetpay|wave>`), un utilisateur borne avec une
caisse ouverte. Les adaptateurs CinetPay et Wave sont **à valider** avec la documentation du compte marchand.

**Compatibilité.** Sans configuration : capacités vides, l'application garde « espèces » et les QR statiques.

**Vérification.** Voir le document (simulateur : même `X-Client-Ref` = même paiement ; webhook non signé → 401 ;
paiement simulé → vente clôturée avec règlement 10 Wave).

**Référence.** `prestige_vente_app/docs/serveur/B3_PAIEMENTS.md` ; patch `prestige_vente_app/docs/serveur/B3_paiements_mobile.patch`.

---

## 43. Empreintes des employés partagées entre terminaux de pointage — P2

**Applications** : Mobile (terminal de pointage, Sunmi V3H avec lecteur d'empreinte Aratek A400).

**Pourquoi.** Aujourd'hui l'empreinte d'un employé est enregistrée (enrôlement : consentement, 3 captures, test)
et stockée **uniquement sur le terminal** où elle a été prise (stockage chiffré Android). Avec plusieurs terminaux
de pointage, il faut enrôler chaque employé sur chacun. Le pharmacien demande d'enregistrer l'empreinte une fois,
de la conserver sur le serveur, et qu'elle soit reconnue sur tous les terminaux. Le serveur n'a aujourd'hui aucune
table ni route pour cela (`RhRessource` `v1/rh` : employés, pointages… ; `t_employe` n'a que `badge`).

**Quoi.**
- Table `t_employe_empreinte` : `id`, `employe_id`, `modele` (octets du gabarit, **chiffré au repos**, clé hors
  base), `format` (ex. `SUNMI_A400_RAW`), `capteur` (numéro/firmware de l'appareil d'enrôlement), `doigt`,
  `consentement_le`, `consentement_par`, `dt_creation`, `dt_suppression`.
- `POST v1/rh/employes/{id}/empreintes` `{modeles:[base64], format, capteur, doigt, consentement:{le, par}}` (droit RH) ;
  `X-Client-Ref` pour l'idempotence.
- `GET v1/rh/empreintes?depuis=<horodatage>&format=<format>` : modèles des employés **actifs** + suppressions
  depuis la date (mise à jour incrémentale des terminaux) ; droit RH ou terminal de pointage enregistré.
- `DELETE v1/rh/employes/{id}/empreintes` ; purge automatique quand un employé devient inactif.
- Journal d'audit des lectures/écritures ; jamais de modèle dans les journaux ni les exports ; HTTPS recommandé.
- Paramètre d'activation (désactivé par défaut).

**Compatibilité.** Sans ces routes, l'application continue de stocker les empreintes sur le terminal (comportement
actuel). Les modèles sont propres au capteur : un terminal ne charge que ceux de son format.

**Obligations (ARTCI, loi 2013-450).** Donnée biométrique sensible : déclaration/autorisation ARTCI de l'officine,
consentement écrit de chaque employé (le texte de l'application sera modifié : aujourd'hui il indique « jamais
envoyé au serveur »), alternative badge, durée de conservation limitée, droit d'effacement.

**Vérification.** Enrôler un employé sur un V3H, vérifier `GET v1/rh/empreintes` sur un second V3H, pointer par
empreinte sur le second ; désactiver l'employé → plus de modèle renvoyé.

**Référence.** Analyse du 15/10/2026 (`lib/rh/empreintes_screen.dart`, `lib/rh/identification.dart`,
`SunmiFingerprintBridge.kt`).

---

## 44. Performance de `GET /info` (Analyse article, fiche produit) — P2

**Applications** : Mobile, Pharmacien.

**Pourquoi.** Sur le serveur de l'officine, `GET v1/info?search=doli` (ou `ibex`) ne répond pas en 10 s alors que
`GET v1/vente/search` répond immédiatement. L'application a été adaptée (liste via `/vente/search`, puis `/info`
pour le seul produit choisi), mais `/info` reste lent même pour un produit.

**Quoi.** Voir `prestige_vente_app/docs/serveur/DEMANDE_PERFORMANCE_INFO.md` (rédigée avec l'analyse du code) :
limiter les calculs au(x) produit(s) demandé(s) (pas d'agrégat des ventes de tout le catalogue), index adaptés,
et rétablir la tolérance aux erreurs par produit (une ligne en erreur ne doit pas vider toute la réponse).

**Vérification.** `GET v1/info?search=<CIP exact>` < 1 s ; `GET v1/info?search=doli` < 3 s.

---

# Fait par le serveur, pour mémoire

Ces points ont été demandés puis réalisés ; ils sont rappelés pour ne pas être refaits, ni défaits.

| N° | Point | Où c'est visible (branche du 13/10) | Effet pour les applications |
|---|---|---|---|
| F1 | **`licence/find` lisible avant connexion**, clé masquée sans session | `AuthenticationFilter.SKIP_PATHS` contient `"v1/licence/find"` ; `v1/licence/save` reste derrière la connexion | les trois applications démarrent de nouveau (elles lisent la licence avant la connexion). Rappel : avant de fermer une route de `SKIP_PATHS`, vérifier les appels des applications **avant connexion** (aujourd'hui : `licence/find`, `officine`, `user/auth`) |
| F2 | **Session renouvelée** à chaque connexion | `AccountResource` l. 73 : `request.changeSessionId()` | les applications repartent d'un cookie vide avant `POST /user/auth` et gardent le JSESSIONID de la réponse |
| F3 | **Expiration des sessions** après 12 h sans requête | `KEY_DUREE_SESSION_MINUTES` = 720 (`V6.9.137__duree_session.sql`, `DureeSessionListener`) ; 0 = jamais | sur 401, reconnexion silencieuse (« Rester connecté ») puis requête rejouée une fois, sinon retour à l'écran de connexion |
| F4 | **`GET /info` rapide**, avec `stockReserve`, `seuilReserve`, `seuilMiniRayon` (aussi `GET /checkproduit`) | serveur `2e4615e` | Analyse article et fiche produit affichent rayon, réserve, seuils et total |
| F5 | **H4 : clé anti-doublon `X-Client-Ref`** sur `vente/add/vno`, `add/assurance`, `add/depot`, `retourfournisseur/new` ; `GET v1/app-vente/client-ref/{ref}` ; `GET v1/app-vente/capacites` | `MobileClientRefService`, `MobileClientRefRessource`, `MobileClientRefPurgeScheduler` | ventes et retours saisis hors ligne renvoyés sans doublon |
| F6 | **H5 : catalogue différentiel** `GET v1/app-vente/catalogue/changements` | `MobileCatalogueRessource` | mise à jour du stock toutes les 5 min au lieu d'une copie complète toutes les 30 min |
| F7 | **Fin des accès sans session** : `v1/ws/inventaires*` (lecture et PUT) et en-têtes `X-User-Info` / `X-Token-Exp` | audit du 12/10 (commit `6919e280`) ; en-têtes acceptés seulement si `KEY_ENTETES_X_USER_INFO = 1` | Inventaire envoie déjà son cookie sur toutes ses requêtes ; aucune application n'utilise `X-User-Info` |
| F8 | **Fichier Journal paginé** | `CommonRessource.logs` (`GET /common/logs`) lit `start` / `limit` et renvoie `total` | « Afficher plus » par 50 dans Pharmacien 3.6.1, sans demande |
| F9 | **CA emplacement / famille** : plusieurs identifiants séparés par des virgules | `util.FiltreListe` (13/10) | cases à cocher dans Pharmacien 3.2.1 |

Pour mémoire aussi (non demandé à ce stade) : le **paiement en 3 modes** demanderait de réécrire
`SalesServiceImpl.addReglement` (2 règlements au plus) ; le client a choisi de stabiliser à 2 modes
(`prestige_vente_app/docs/PLAN_EVOLUTION_MOBILE.md` § 5 et § 7).

---

# Contradictions et points à trancher entre les documents d'origine

1. **H4 / H5 « non poussés » mais présents sur la branche.** Les notices H4 et H5 disent « Rien n'a été poussé sur le
   dépôt » et « appliqués chez aucun client ». La branche du 13/10 contient pourtant `MobileClientRefService`,
   `v1/app-vente/client-ref`, `v1/app-vente/capacites` et `v1/app-vente/catalogue`. La demande « écritures
   sensibles » cite d'ailleurs `MobileClientRefService` sur `retourfournisseur/new` comme existant. → H4 et H5 sont
   marqués **faits** ; O4, O5 et B3 restent à appliquer, avec un rebasage possible.
2. **En-têtes `X-User-Info` / `X-Token-Exp`.** Les notices H4–O5 et la demande Inventaire (§ B2, § 3 règle 5) les
   disent acceptés. Depuis l'audit du 12/10, ils ne valent connexion que si `KEY_ENTETES_X_USER_INFO = 1`. Sans
   conséquence pour les applications (aucune ne les utilise), mais les documents d'origine sont à lire en ce sens.
3. **PUT `ws/inventaires/details` sans session.** La demande Inventaire (§ 0, § C2) le décrit exempté de session et
   propose une transition (journal, puis 401 après deux mois). La demande « licence 401 » et la branche actuelle
   montrent que l'exemption a été **supprimée d'un coup** par l'audit. Le plan de transition est donc dépassé : les
   versions d'Inventaire **antérieures à 4.9** (sans file de saisies persistante) peuvent perdre une saisie sur un
   401. À vérifier sur le parc de terminaux.
4. **Activation de licence.** Inventaire demande `POST /api/v1/licence/activation` exempté de session ; la demande
   « licence 401 » recommande de **laisser l'enregistrement derrière la connexion**, ou nomme l'alternative
   `POST v1/licence/activer`. Un seul choix, et un seul nom, à fixer (demande 11).
5. **Route « mes droits ».** Quatre formes proposées : `GET /user/droits` (Pharmacien) ; `GET v1/mobile/droits` ou
   `v1/user/privileges` (Mobile) ; `role` + `droits` dans la réponse de `user/auth` (Inventaire) ; liste
   `privileges:[{name, value}]` dans `user/auth` (étape D). Or **`v1/mobile/` est réservé au jeton Bearer** (filtre
   L13) : `v1/mobile/droits` ne marcherait pas avec la session cookie des applications. Recommandation : `GET
   /user/droits` (demande 9) **et** `role` dans `user/auth` (demande 10).
6. **Nom de la clé anti-doublon.** `X-Client-Ref` (H4, B3, Pharmacien, réserve), `requestId` (réserve, variante),
   `clientEventId` + table `t_mobile_evenement` (étape D, D17), `cle` dans le corps (versement Inventaire, O4).
   Recommandation : `X-Client-Ref` + `mobile_client_ref` pour toute nouvelle écriture ; les clés dans le corps des
   routes en lot (O4, versement) restent cohérentes avec leur format.
7. **Préfixe des nouvelles routes mobiles.** L'étape D (§ 5) propose `v1/mobile/reception/…` avec jeton Bearer ;
   H4–O5 et B3 ont choisi la session cookie (`v1/app-vente/…`, `v1/paiements-mobile/…`), justement parce que
   `v1/mobile/` est réservé au jeton. À trancher avant la demande 36.
8. **Visualisation BL.** La note Pharmacien 3.3.0 dit `groupeId` ignoré ; la branche du 13/10 le lit désormais. Seuls
   `userId` et `checked` restent ignorés (demande 26, statut « partiel »).
9. **Forme des refus.** `ROUTES_DE_COMPTAGE.md` demande 403 pour un droit manquant et la clé `message` ;
   `DEMANDE_ECRITURES_SENSIBLES.md` accepte 403 **ou** `interdit:true` et la clé `msg` ; l'application Mobile lit un
   HTTP 200 `success:false` comme un refus métier. Les trois formes sont comprises ; il est souhaitable d'en garder
   une seule pour les nouvelles routes.
10. **Numéros de migration.** B3 utilise `V6.9.129.20`, O4 / O5 `V6.9.132.3` / `.4`, alors que la branche est passée
    à `6.9.137` : ces migrations s'exécutent « dans le désordre » (Flyway `outOfOrder(true)`, documenté dans H4).
    Les renuméroter au-dessus de la dernière migration au moment de l'application serait plus lisible. L'étape D
    cite `V6.9.113` : à renuméroter aussi.
11. **Numéros de ligne.** Plusieurs documents citent des lignes (ex. `creerInventaire` l. 408, `deleteVente` ~l. 319)
    qui ont bougé sur la branche actuelle (ex. `deleteVente` vers la l. 337). Se fier aux noms de méthodes.
12. **Comptage des péremptions.** `ROUTES_DE_COMPTAGE.md` demande `fichearticle/perimes/nombre` ; la demande
    « écritures sensibles » § 7 précise que, depuis la vague 1, `GET /tableau-bord/alertes` le remplace : la route
    n'est utile que si l'écran Suivi Péremption garde sa propre définition (demande 29).

---

# Sources lues

| Dépôt | Fichiers |
|---|---|
| `prestige_vente_app` | `docs/serveur/API_RESERVE_POSOS_FICHE_CLIENT.md`, `B3_PAIEMENTS.md` (+ `.patch`), `DEMANDE_LICENCE_MOBILE_401.md`, `DEMANDE_PHOTO_POINTAGE.md`, `H4_CLIENT_REF.md` (+ `.patch`), `H5_CATALOGUE_DELTA.md` (+ `.patch`), `O4_CORRECTIONS.md` (+ `.patch`), `O5_LECTURE_AVANCEE.md` (+ `.patch`) ; `docs/ETAPE_D_SERVEUR_RECEPTION_RETOUR.md`, `docs/PLAN_EVOLUTION_MOBILE.md`, `docs/NOTE_VERSION_4.0.*.md` |
| `prestige_app` | `docs/serveur/DEMANDE_ECRITURES_SENSIBLES.md`, `DEMANDE_DETAIL_MOBILE_MONEY.md`, `ROUTES_DE_COMPTAGE.md` ; `docs/NOTE_VERSION_*.md` (3.1.0 à 3.7.0, VAGUE1, REFONTE…), `docs/HTTPS_ET_TRAFIC_EN_CLAIR.md`, `docs/ANALYSE_PRESTIGE_APP.md` |
| `prestinv` | `docs/DEMANDE_SERVEUR_COMPTAGE.md` (dont § G), `docs/ANALYSE_PRESTINV.md`, `docs/NOTE_VERSION_*.md` |
| serveur (lecture seule) | copie locale de `origin/claude/new-session-xm8ptu` (`d1c9b114`, 13/10/2026) pour les statuts |
