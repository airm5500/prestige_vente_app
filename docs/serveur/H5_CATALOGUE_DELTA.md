# H5 — Mise à jour différentielle du catalogue (`/mobile/catalogue/changements`) : patch serveur Prestige

> Pour le développeur Prestige. Patch : `docs/serveur/H5_catalogue_delta.patch` (un commit, à appliquer avec `git am`
> **après** le patch H4 `docs/serveur/H4_client_ref.patch`, dont il complète la route `v1/mobile/capacites`).
> Construit sur `h4-client-ref-upstream` (= `origin/claude/new-session-xm8ptu` `88a2a4b` + H4) ; compilé sur cette base
> (`mvn compile`) ; H4 + H5 s'appliquent aussi sans conflit sur `9872b89` (dernier commit de la branche).
> Vérifié sur le serveur de test (Payara 5 + MariaDB 10.11). **Rien n'a été poussé sur le dépôt `airm5500/prestige`.**

## 1. Quoi

| Élément | Détail |
|---|---|
| Nouvelle route | `GET v1/mobile/catalogue/changements?depuis=<yyyy-MM-dd HH:mm:ss>[&jusqua=…]&start=0&limit=500` |
| Réponse | `{success, depuis, serveurMaintenant, total, start, limit, data:[…]}` ; chaque élément = **la ligne exacte de `v1/vente/search`** (mêmes champs, mêmes valeurs) + `statut:"actif"`, ou `{lgFAMILLEID, statut:"supprime"}` si le produit ne sortirait plus dans la recherche de vente (désactivé, supprimé, plus de stock pour l'emplacement…). Tri par identifiant ; `limit` 500 par défaut, 2 000 au plus. |
| Horloge | `serveurMaintenant` = `NOW()` de la base (celle qui date les modifications). Le téléphone repasse cette valeur en `jusqua` pour les pages suivantes (ensemble figé pendant la pagination), puis en `depuis` (moins 2 min de chevauchement) à la mise à jour suivante : **l'heure du téléphone n'intervient jamais**. |
| Erreurs | `depuis` absent / illisible → 400 `{success:false, msg}` ; sans session → 401 (comme les autres routes). |
| Capacité | `GET v1/mobile/capacites` → `{…, catalogueDelta:true, catalogueDeltaVersion:1, serveurMaintenant:"2026-10-10 23:20:01"}`. L'application n'utilise H5 que si `catalogueDelta:true`. |
| Authentification | Session habituelle de l'application (cookie), comme `v1/vente/search` ; `v1/mobile/catalogue/…` est exclu du contrôle par jeton Bearer des autres chemins `v1/mobile/` (même principe que H4). Emplacement = celui de l'utilisateur connecté (comme la recherche). |
| Migration | `V6.9.129.2__mobile_catalogue_delta.sql` : **uniquement des index** (aucune table, colonne ni donnée modifiée). |

Fichiers du patch :

- `src/main/java/rest/service/mobile/MobileCatalogueDeltaService.java` (nouveau, EJB `@Stateless`) — requête des
  changements, lignes au format de la recherche (même requête Criteria que `SalesServiceImpl.produits`, limitée aux
  identifiants de la page) ;
- `src/main/java/rest/MobileCatalogueRessource.java` (nouveau) ;
- `src/main/java/rest/MobileCapacitesRessource.java` : `catalogueDelta`, `catalogueDeltaVersion`, `serveurMaintenant` ;
- `src/main/java/filter/AuthenticationFilter.java` : exclusion `v1/mobile/catalogue/` (une condition) ;
- `src/main/resources/db/migration/V6.9.129.2__mobile_catalogue_delta.sql`.

## 2. Pourquoi

Demande client : « pourquoi ne pas récupérer uniquement les produits dont le stock a changé ? il y a des bases de
10 000 produits ». Prestige Mobile garde une copie du catalogue pour travailler hors ligne ; jusqu'ici il la
retéléchargeait **en entier** toutes les 30 min. Mesuré sur le serveur de test avec **10 758 produits** (copies
temporaires, supprimées ensuite) :

| Mise à jour | Requêtes | Volume | Durée (serveur de test) |
|---|---|---|---|
| Copie complète (`v1/vente/search`, pages de 500) | 22 | **3,2 Mio** | **7,1 à 9,6 s** |
| Changements, rien de modifié | 1 | 131 octets | 12 ms |
| Changements, 50 produits modifiés | 1 | 15,8 Kio | 64 à 74 ms |
| Changements, catalogue entier modifié (ex. recalcul de nuit) | 22 | 3,4 Mio | 5,8 s |
| Application (intégration réelle) : copie complète de toutes les catégories / changements après une vente | — | — | 8,6 s / 0,5 s |

Avec H5, l'application peut mettre à jour le stock **toutes les 5 minutes** au lieu de 30, pour une charge serveur
et réseau des centaines de fois plus faible.

## 3. Quels produits sont « modifiés » ? (vérifié)

Un produit est renvoyé si, dans l'intervalle `]depuis, jusqua]` :

1. `t_famille.dt_UPDATED` a changé ;
2. `t_famille_stock.dt_UPDATED` (emplacement de l'utilisateur) a changé ;
3. un mouvement `HMvtProduit.createdAt` existe pour cet emplacement (filet de sécurité) ;
4. un changement de prix est journalisé dans `t_mouvementprice.dt_CREATED` (filet de sécurité).

**Constat important** : la base Prestige contient les déclencheurs `t_famille_before_upd_tr` et
`t_famille_stock_before_upd_tr` qui posent `dt_UPDATED = NOW()` à **chaque** `UPDATE` (et `t_famille_before_ins_tr`
à la création) — quel que soit le chemin (JPA, SQL natif de la clôture d'inventaire, anciens écrans ExtJS). Les
critères 1 et 2 suffisent donc sur une base complète ; 3 et 4 couvrent une base où ces déclencheurs manqueraient.
Lecture du code sans les déclencheurs : la plupart des chemins posent `dt_UPDATED` eux-mêmes ; exceptions repérées :
retour dépôt (`MvtProduitServiceImpl.createTretourDetails`) → couvert par `HMvtProduit` ; prix modifié pendant la
réception d'un BL (`bonLivraisonManagement.updatePriceArticleByDuringCommand`, mouchard commenté) → couvert par
l'entrée en stock du BL qui suit ; suppression par l'ancien écran (`familleManagement.delete`) → couverte par la
vérification complète quotidienne du téléphone.

Vérifié sur le serveur de test (avant / après, horodatages relus en base) :

| Opération | `t_famille.dt_UPDATED` | `t_famille_stock.dt_UPDATED` | `HMvtProduit` | Dans les changements |
|---|---|---|---|---|
| Vente comptant **clôturée** (`vente/add/vno` + `vente/cloturer/vno`) | non | **oui** | oui | **oui**, stock −1, ligne identique à `vente/search` |
| Prévente non clôturée | non | non | non | non (stock inchangé, normal) |
| Ajustement validé (`ajustement/creeation` + `PUT ajustement/{id}`) | non | **oui** | oui | oui |
| Désactivation (`produit/disable-produit/{id}`) | **oui** | — | — | oui, `statut:"supprime"` |
| Réactivation (`produit/enable-desactives/{id}`) | **oui** | — | — | oui, `statut:"actif"` |
| Entrée de BL, inventaire, modification de fiche / prix | par code + déclencheurs (`setDtUPDATED`, `ClotureInventaireSql.STOCK_RAYON` pose `s.dt_UPDATED = NOW()`, `familleManagement.update` pose `dt_UPDATED`) | | | non rejoué sur le serveur de test (aurait modifié durablement ses données) |

Remarque : un traitement de nuit a touché 878 produits d'un coup le 07/10 à 02:30 (`dt_UPDATED`) ; la route le gère
(pagination), au prix d'un volume proche d'une copie complète ce jour-là.

## 4. Script SQL de migration (idempotent)

Joué automatiquement par Flyway (`V6.9.129.2__mobile_catalogue_delta.sql`). Numéro intercalé après `6.9.129.1` (H4) :
pas de collision avec la suite `6.9.130…` (`outOfOrder(true)`). Chaque index n'est créé que s'il manque
(`information_schema.STATISTICS` + `PREPARE`, comme `V6.9.14`) :

```sql
CREATE INDEX idx_famille_dt_updated        ON t_famille        (dt_UPDATED);
CREATE INDEX idx_famille_stock_dt_updated  ON t_famille_stock  (dt_UPDATED, lg_EMPLACEMENT_ID);
CREATE INDEX idx_hmvt_created_at           ON HMvtProduit      (createdAt, lg_EMPLACEMENT_ID);
CREATE INDEX idx_mouvementprice_dt_created ON t_mouvementprice (dt_CREATED);
```

Sur une très grosse table `HMvtProduit`, la création de l'index peut prendre quelques minutes au premier démarrage
(InnoDB la fait sans bloquer les écritures). Sans ces index la route fonctionne, mais balaie les tables à chaque appel.

## 5. Appliquer

```bash
git checkout claude/new-session-xm8ptu        # ou la branche de travail
git am /chemin/vers/docs/serveur/H4_client_ref.patch      # si pas déjà fait
git am /chemin/vers/docs/serveur/H5_catalogue_delta.patch
mvn -DskipTests package                       # JDK 11
asadmin redeploy --name prestige --contextroot prestige target/prestige.war
```

Au démarrage : « Flyway migration completed », version `6.9.129.2` dans `flyway_schema_history`, et
`SHOW INDEX FROM t_famille WHERE Key_name = 'idx_famille_dt_updated'` répond une ligne.
En cas de conflit `git am`, seuls points touchés dans des fichiers existants : la condition du filtre
(`path.startsWith(CHEMIN_MOBILE) …`) et la méthode `capacites()`.

## 6. Tester (curl)

```bash
B=http://localhost:8080/prestige/api/v1
curl -s -c cj -H 'Content-Type: application/json' -d '{"login":"admin","password":"…"}' $B/user/auth
curl -s -b cj $B/mobile/capacites                    # {…,"catalogueDelta":true,"serveurMaintenant":"2026-10-10 23:20:01"}
curl -s -b cj "$B/mobile/catalogue/changements?depuis=2026-10-10%2023:00:00&limit=5"
# → {"total":2,"serveurMaintenant":"…","data":[{"lgFAMILLEID":"…","intNUMBERAVAILABLE":10,…,"statut":"actif"},…]}
curl -s -b cj "$B/mobile/catalogue/changements?depuis=hier"    # 400
curl -s "$B/mobile/catalogue/changements?depuis=2026-10-10%2000:00:00"   # 401 (sans session)
```

**Vérifié sur le serveur de test** (10/10/2026), script `verif.py` + test d'intégration de l'application :

| Cas | Résultat |
|---|---|
| sans session / `depuis` illisible / absent | 401 / 400 / 400 |
| produit désactivé puis réactivé | `statut:"supprime"` puis `"actif"` |
| vente comptant clôturée | produit dans les changements, stock −1, ligne **identique** à `vente/search` |
| `depuis = serveurMaintenant` juste après | 0 changement |
| pagination par 100 avec `jusqua` figé | mêmes 1 794 identifiants, même ordre, qu'en une seule page |
| application (`test/horsligne_delta_test.dart`, intégration) | copie complète puis vente clôturée → changements : stock local à jour |

Les données de test (ventes, ajustement, produits simulés, journaux) ont été supprimées de la base du serveur de test.

## 7. Rétrocompatibilité

- **Ancien téléphone → serveur patché** : rien ne change (`v1/vente/search` inchangée ; la route est nouvelle ;
  `capacites` ne fait qu'ajouter des champs).
- **Téléphone à jour → serveur sans H5** (avec ou sans H4) : `capacites` répond sans `catalogueDelta` (ou 401
  « expire » / 404) → l'application garde **exactement** son fonctionnement d'origine (copie complète toutes les 30 min)
  et n'appelle jamais la route.
- **Migration non passée** : la route marche (sans index, plus lente).
- Aucune réponse JSON existante modifiée, aucune table modifiée ; aucune écriture en base par la route (lecture seule).
