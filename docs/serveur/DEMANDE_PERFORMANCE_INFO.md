# Demande serveur : `GET v1/info` (et `GET v1/fichearticle/comparaison`) trop lents

| | |
|---|---|
| **Date** | 15/10/2026 |
| **Destinataire** | la session qui maintient le serveur Prestige : dépôt `airm5500/prestige`, branche `claude/new-session-xm8ptu` |
| **Émetteur** | Prestige Mobile (`prestige_vente_app`), version 4.1.2, après les retours du pharmacien (vidéo + captures) |
| **Priorité** | P1 (écrans Analyse article, fiche produit et État de Stock inutilisables sur un gros catalogue) |
| **Code lu** | `origin/claude/new-session-xm8ptu` (dernier commit `d1c9b114`), en lecture seule |

## 1. Ce qui a été constaté

- Dans **Analyse article** et dans la **fiche produit**, taper « doli » ou « ibex » faisait tourner l'écran, puis
  affichait « Délai dépassé : pas de réponse du serveur en 10 s (GET /info) ».
- **État de Stock** tournait aussi longtemps.
- La recherche de l'accueil (`GET v1/vente/search`) répond vite pour la même saisie.

## 2. Pourquoi c'est lent (lecture du code serveur)

### 2.1 `GET v1/info?search=<saisie>` — `InfoArticleRessource` → `InfoArticleServiceImpl.fetchInfoArticles`

Seuls paramètres : `search` (« commence par », sur `int_CIP` **ou** `str_NAME`) et `dtStart` (6 mois par défaut).
**Aucun paramètre ne limite le nombre de lignes, ni le calcul au(x) produit(s) demandé(s).**

1. **Ventes de 6 mois de TOUT le catalogue à chaque appel.** La requête native joint `t_famille` à une table dérivée
   `vAgg` :

   ```sql
   LEFT JOIN (
     SELECT produitId, SUM(...) AS quantiteVendue, ..., GROUP_CONCAT(...) AS quantite_mois, ...
     FROM ( SELECT d.lg_FAMILLE_ID AS produitId, SUM(d.int_QUANTITY) AS qte, MONTH(v.dt_UPDATED) AS mois
            FROM t_preenregistrement_detail d JOIN t_preenregistrement v ON ...
            WHERE v.b_IS_CANCEL = 0 AND v.str_STATUT = 'is_Closed' AND v.int_PRICE > 0
              AND v.dt_UPDATED >= ?1 AND v.dt_UPDATED < DATE_ADD(CURDATE(), INTERVAL 1 DAY)
            GROUP BY d.lg_FAMILLE_ID, MONTH(v.dt_UPDATED) ) x
     GROUP BY produitId
   ) vAgg ON vAgg.produitId = p.lg_FAMILLE_ID
   WHERE p.str_STATUT = 'enable' AND (p.int_CIP LIKE ?2 OR p.str_NAME LIKE ?3)
   ```

   La table dérivée n'a **aucun filtre produit** : MySQL agrège **toutes les lignes de vente des 6 derniers mois
   de toute l'officine** (des centaines de milliers de lignes de `t_preenregistrement_detail`), puis ne garde que les
   produits qui commencent par la saisie. Le coût est le même pour « doli » que pour un CIP exact.
2. **Extras ligne par ligne, groupés mais sans borne de date.** `ProduitExtraInfoServiceImpl.getExtraInfos` (grâce au
   travail du 13/10, en requêtes groupées `IN (:ids)`) cherche pour chaque produit trouvé :
   - `REQ_VENTES` : `MAX(v.dt_UPDATED)` sur **tout l'historique** des ventes du produit (par emplacement), puis une
     sous-requête corrélée par produit pour la quantité du jour ; « doli » ramène des dizaines de produits très vendus ;
   - `REQ_ACHATS`, `REQ_INVENTAIRES` : idem sur tout l'historique des bons de livraison et des inventaires ;
   - `REQ_FAMILLES`, `REQ_RESERVES`.
3. **Recherche « commence par » sur le nom ET le CIP avec `OR`** : `p.int_CIP LIKE 'doli%' OR p.str_NAME LIKE 'doli%'`
   empêche souvent l'usage d'un index ; la réponse est triée par nom (`ORDER BY p.str_NAME`).
4. **Une ligne par emplacement** (`JOIN t_famille_stock`) : plusieurs lignes par produit sur une installation
   multi-emplacements.

### 2.2 `GET v1/fichearticle/comparaison` (État de Stock) — `FicheArticleServiceImpl.comparaisonStock`

La route JSON appelle `comparaisonStock(..., all=false)` qui passe `enrichir=true` : pour **chaque ligne** de la
page (20 lignes demandées par l'appli), quatre lectures unitaires — `getDateBonLivraison`, `getDateEntreeStock`,
`getDateInventaire`, `getDateDerniereVente` — soit **80 requêtes** par page, plus le comptage. La variante
`comparaisonStockSansEnrichissement` existe déjà (édition PDF de la réserve, « 327 secondes » évitées) mais n'est pas
accessible à la route JSON.

## 3. Ce que l'appli fait déjà (4.1.2, sans attendre le serveur)

| Écran | Avant | Depuis la 4.1.2 |
|---|---|---|
| Analyse article — liste | `GET /info?search=<saisie>` à chaque frappe (après 350 ms) | `GET /vente/search` (recherche rapide de l'accueil : anti-rebond, une seule requête en vol, classement par début de code) ; **aucun `GET /info` pendant la frappe** |
| Analyse article — détail | ligne déjà chargée | `GET /info?search=<CIP exact>` pour **le seul produit choisi** (ligne du même identifiant / CIP), indicateur, Réessayer |
| Fiche produit | (inchangé) affichage immédiat, bloc `/info` en arrière-plan | idem, délai réel 30 s |
| Tous les `GET /info` | abandon par le client au bout de **10 s** (délai du client HTTP partagé), message « … en 10 s » alors que l'appli annonçait 30 s | délai de réception **30 s** (`ApiService.delaiInfo`), message « … en 30 s » |
| État de Stock | chaque frappe laissait sa requête aller au bout ; abandon à 10 s | requête précédente **annulée** ; délai 30 s ; **même route, mêmes chiffres** |

L'appli ne peut pas aller plus loin seule : même pour un CIP exact, `GET /info` paie l'agrégat des 6 mois de tout le
catalogue (§ 2.1, point 1), et État de Stock n'a pas d'autre route qui donne les mêmes chiffres (stock rayon,
seuils, réappro) sans l'enrichissement.

## 4. Ce qui est demandé

### 4.1 `GET v1/info` limité au(x) produit(s) demandé(s) — P1

1. **Filtrer l'agrégat des ventes par les produits retenus** : appliquer le filtre produit **dans** la table dérivée
   (ou calculer d'abord la liste des `lg_FAMILLE_ID` qui correspondent, puis agréger seulement ceux-là) :

   ```sql
   -- d'abord les produits (bornés)
   SELECT p.lg_FAMILLE_ID FROM t_famille p
    WHERE p.str_STATUT = 'enable' AND (p.int_CIP LIKE ? OR p.str_NAME LIKE ?)
    ORDER BY p.str_NAME LIMIT ?
   -- puis les ventes de CES produits seulement
   ... FROM t_preenregistrement_detail d JOIN t_preenregistrement v ON ...
    WHERE d.lg_FAMILLE_ID IN (:ids) AND v.dt_UPDATED >= ? AND ...
   GROUP BY d.lg_FAMILLE_ID, MONTH(v.dt_UPDATED)
   ```

2. **Nouveaux paramètres facultatifs** (anciens appels inchangés) :
   - `exact=true` : `int_CIP = :search` (et/ou `lg_FAMILLE_ID = :produitId` via un paramètre `produitId`), **une
     seule ligne** par produit et par emplacement de l'utilisateur ; c'est l'usage de l'appli (détail d'un produit
     choisi, fiche produit, Recherche Article, Évaluation Vente) ;
   - `limit` (défaut raisonnable, ex. 50) et `start` pour une recherche texte ;
   - `extras=false` pour ne pas calculer dernière vente / achat / inventaire quand l'écran ne les affiche pas.
3. **Borner les extras dans le temps** quand c'est possible (`REQ_VENTES`, `REQ_ACHATS`, `REQ_INVENTAIRES` : `MAX` sur
   tout l'historique) : par ex. chercher d'abord sur 12 mois, puis sur tout l'historique seulement si rien n'est
   trouvé ; ou tenir la date de dernière vente / entrée à jour dans une table (mise à jour à la clôture de la vente,
   à la réception du BL, à la clôture de l'inventaire).
4. **Restreindre à l'emplacement de l'utilisateur** connecté (`t_famille_stock.lg_EMPLACEMENT_ID`), comme
   `comparaisonStock`, pour ne plus renvoyer une ligne par emplacement.

### 4.2 Index — P1 (à vérifier avec `EXPLAIN` sur la base de l'officine)

| Table | Index proposé | Pour |
|---|---|---|
| `t_preenregistrement` | `(str_STATUT, b_IS_CANCEL, dt_UPDATED)` | agrégat des 6 mois, dernière vente |
| `t_preenregistrement_detail` | `(lg_FAMILLE_ID, lg_PREENREGISTREMENT_ID)` | ventes d'un produit |
| `t_bon_livraison_detail` | `(lg_FAMILLE_ID, lg_BON_LIVRAISON_ID)` | dernier achat |
| `t_inventaire_famille` | `(lg_FAMILLE_ID, bool_INVENTAIRE, dt_UPDATED)` | dernier inventaire |
| `t_famille` | `(int_CIP)`, `(str_NAME)` | « commence par » ; préférer deux requêtes (`UNION`) à `OR` |

### 4.3 `GET v1/fichearticle/comparaison` sans enrichissement — P2

Paramètre facultatif `details=false` (défaut : `true`, compatibilité) qui appelle
`comparaisonStockSansEnrichissement` paginé, et une route de détail d'**une** ligne
(`GET v1/fichearticle/comparaison/{id}` ou `?id=`) qui renvoie les quatre dates. L'appli afficherait alors la liste
tout de suite et les dates à l'ouverture du détail d'un article, **avec les mêmes chiffres**.

## 5. Compatibilité

- Tous les paramètres proposés sont **facultatifs** : sans eux, les réponses restent identiques (Prestige Web,
  versions précédentes de l'appli).
- L'appli 4.1.2 fonctionne avec le serveur actuel (détail par CIP + choix de la bonne ligne, délai 30 s). Dès que
  `exact=true` / `details=false` existeront, elle pourra les envoyer (à détecter par la route `v1/app/info` ou par
  la présence d'un champ dans la réponse, comme pour H4).

## 6. Vérification

```bash
B=http://<serveur>:8080/prestige/api/v1
curl -s -c cj -H 'Content-Type: application/json' -d '{"login":"<compte>","password":"…"}' $B/user/auth
# Avant / après : temps de réponse
time curl -s -b cj "$B/info?search=doli" -o /dev/null
time curl -s -b cj "$B/info?search=3595583" -o /dev/null
time curl -s -b cj "$B/info?search=3595583&exact=true" | jq 'length'          # attendu : 1
time curl -s -b cj "$B/fichearticle/comparaison?query=doli&start=0&limit=20&details=false" -o /dev/null
# Objectif : < 1 s pour un CIP exact, < 2 s pour « doli » (catalogue de l'officine), sans changer les chiffres :
diff <(curl -s -b cj "$B/info?search=3595583" | jq -S '.[] | select(.codeCip=="3595583")') \
     <(curl -s -b cj "$B/info?search=3595583&exact=true" | jq -S '.[0]')
```

## 7. Référence

- Appli : `lib/providers/article_analysis_provider.dart`, `lib/screens/analysis/article_analysis_screen.dart`,
  `lib/api/api_service.dart` (`optionsInfo`, `delaiInfo`, `getStockReport`), `lib/providers/stock_report_provider.dart` ;
  tests `test/recherche_rapide_info_test.dart`.
- Serveur : `src/main/java/rest/InfoArticleRessource.java`, `rest/service/impl/InfoArticleServiceImpl.java`,
  `rest/service/impl/ProduitExtraInfoServiceImpl.java`, `rest/FicheArticleRessource.java` (`comparaison`),
  `rest/service/impl/FicheArticleServiceImpl.java` (`comparaisonStock`, `comparaisonStockSansEnrichissement`).
