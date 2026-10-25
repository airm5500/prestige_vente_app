# Prestige Mobile 4.9.1+32 — lecture GS1 dans les ventes Dépôt et Proforma

Décision du pharmacien : le contrôle GS1 de la vente (4.9.0) s'applique aussi aux ventes **Dépôt** et **Proforma**.

## Ce que fait le web, et ce que fait le serveur (vérifié, dépôt du serveur en lecture seule)

- **Web** : la lecture GS1 (`GET v1/vente/gs1`, réglage `KEY_VENTE_LECTURE_GS1`) n'existe que dans l'écran de vente
  (`VenteCtr`).
  - `DepotCtr` (vente à un dépôt, `add/depot`) : aucun traitement GS1.
  - `DevisCtr` (proforma, `vente/devis`) : refuse seulement les étiquettes étendues, quel que soit le réglage.
  - Il n'y a donc pas de règle propre au web pour ces deux ventes : les règles de la vente au comptant s'appliquent.
- **Serveur** : `add/depot` et `vente/devis` acceptent `lotScanne` (même `SalesParams`, `initVente` /
  `addPreenregistrementItem` le notent en mode B), mais ne s'en servent jamais.
  - La clôture d'un dépôt (`clotureVenteDepot` → `updateVenteStockDepot`) ne sort aucun lot.
  - Une proforma ne sort pas de stock, et sa copie en vente (`clone-devis`, constructeur de copie de la ligne) ne
    recopie pas les lots scannés.
  - `lotScanne` n'est donc **pas envoyé** : en mode B, l'application affiche seulement l'avertissement.

## Ce qui change (Dépôt et Proforma)

- **Lecture active** et étiquette GS1 : verdict du serveur avant le produit.
  - Mode C lot différent, boîte périmée, étiquette étendue, sans produit : refusés avec le même message qu'au
    comptant ; rien n'est ajouté.
  - Modes A et B lot différent : produit trouvé et ajouté comme avant ; avertissement au vendeur (6 s), neutre :
    « Lot différent : boîte scannée lot X - pér. Y (prévu : lot Z, péremption W). » (aucun lot n'est sorti par ces
    ventes : la phrase du comptant « la vente sortira ce lot » ne s'applique pas).
  - Aucun `lotScanne`, aucun lot mis en attente (il ne peut pas non plus passer dans une vente au comptant suivante).
- **Hors ligne**, lecture active : boîte périmée refusée par sa date.
- **Lecture inactive** (0, défaut), réglage absent, serveur ancien (404/405), panne, réponse illisible, délai de plus de
  2,5 s : exactement la recherche d'avant (`PagedProductSearch` : mêmes produits, même « Code … introuvable », même
  panne).
- **Inchangés** : code-barres 1D, CIP saisi, nom ; tous les autres menus qui cherchent un produit (ajustement,
  péremption, analyse article…) ; la vente au comptant (4.9.0).
- **Corrigé en passant** (Proforma, écran 360 dp) : le nom du type de devis choisi débordait de sa case (bande
  jaune et noire avec « VENTE AU COMPTANT ») : il est maintenant coupé proprement.

## Sécurité

- Le contenu scanné n'est jamais journalisé (le journal du mode débogage montre `GET …/vente/*` et le statut).
- Données fictives seulement dans les tests.

## Tests

- `test/gs1_depot_proforma_test.dart` (unitaires) : verdicts, aucun lot en attente, nouvelle recherche qui efface le
  message ; **non-régression** pour lecture inactive, 404, 405, 500, réseau coupé, réponse illisible, « pas une
  étiquette », délai : résultat identique à la recherche d'avant ; panne de la recherche ; jamais `vente/gs1` pour un
  code-barres, un CIP, un nom ou les autres menus ; hors ligne ; vente au comptant inchangée.
- `test/gs1_depot_proforma_e2e_test.dart` (application entière, Dépôt ET Proforma) : mode A, mode B (sans
  `lotScanne`), mode C, périmée, étendue, sans produit, lecture inactive, réglage absent, `vente/gs1` 404 et 500,
  code-barres sans `vente/gs1`, journal sans contenu scanné.
- `test/reseau/gs1_depot_proforma_reseau_test.dart` (vrai HTTP) : verdict avec la session, `add/depot` et `devis`
  sans `lotScanne`, périmée sans recherche, 404 / 500 / délai 6 s, serveur coupé.
- `test/performance/gs1_depot_proforma_perf_test.dart` : 2 000 recherches hors GS1 sans requête ni surcoût, une
  requête de plus pour une étiquette, délai respecté.
