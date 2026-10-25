# Prestige Mobile 4.9.3+34 — Dépôt : étiquette étendue jamais refusée, comme le web

Décision du pharmacien : à la vente **Dépôt**, faire comme le web : l'étiquette étendue (DataMatrix+, QR+) n'est pas
refusée, **même lecture GS1 active**.

## Ce que fait le web (vérifié, dépôt du serveur en lecture seule)

Le web, dans `DepotCtr` (vente à un dépôt) :
- n'appelle ni `estEtiquetteEtendue` ni `vente/gs1` ;
- à la touche Entrée, cherche le produit dans la liste de recherche, puis appelle `GET v1/vente/findone/<contenu>`
  (`findOneproduit`, qui cherche les CIP, EAN-13 et codes article commençant par le contenu).
  - Le contenu brut d'un DataMatrix+ ou d'un QR+ n'y commence par aucun code : aucun produit, le champ reprend le
    focus, sans message.

## Ce qui change (Dépôt seulement)

- **Avant (depuis la 4.9.1) :** lecture active, l'étiquette étendue partait à `vente/gs1`, dont le verdict `etendu`
  la refusait.
- **Maintenant :** une étiquette étendue reconnue sur l'appareil (règle du web, 4.9.2) ne passe plus par
  `vente/gs1` au Dépôt, lecture active comme inactive. Elle n'est pas refusée et suit la recherche d'avant (4.9.0,
  celle de la lecture inactive) :
  - DataMatrix+ : produit trouvé par son GTIN, ajouté comme avant, sans `lotScanne` ;
  - QR+ : aucun produit, comme au web.
  - Le verdict du serveur n'est pas utilisé : il n'apporte rien de plus pour ce contenu, et refuserait.
- **Inchangées au Dépôt** (4.9.1) : boîte périmée refusée, mode C lot différent refusé, avertissement A / B,
  message « sans produit », périmée hors ligne refusée, aucun `lotScanne`.
- **Inchangés ailleurs** : refus de l'étiquette étendue au comptant (nouvelle et ancienne interface), à la Proforma et
  à la borne (4.9.2).
- La limite du séparateur GS retiré par les champs reste la même (comme le web, voir la note 4.9.2).

## Écart avec le web

Pour un DataMatrix+, le web ne trouve pas de produit (`findone` sur le contenu brut), alors que l'application le
trouve par son GTIN. Elle le faisait déjà avant cette version (lecture inactive), comme pour toute étiquette 2D au Dépôt. Garder la recherche
d'avant évite de changer ce que la lecture inactive faisait déjà.

## Tests

- `test/gs1_etendue_test.dart` :
  - Dépôt, lecture active : DataMatrix+ (GS, `|`, `<GS>`) et QR+ (avec ou sans `]Q3`) sans refus, sans `vente/gs1`,
    résultat identique à la recherche d'avant ;
  - étiquette normale au Dépôt : verdict du serveur comme en 4.9.1 ;
  - Proforma et vente : refus toujours.
- `test/gs1_etendue_e2e_test.dart` (application entière) : Dépôt avec lecture 0 et 1, pour DataMatrix+ (trouvé,
  ajouté sans `lotScanne`) et QR+ (aucun produit) : jamais refusés, aucun appel `vente/gs1`.
- `test/reseau/gs1_etendue_reseau_test.dart` (vrai HTTP) : Dépôt, lecture active, aucune requête `vente/gs1`, ligne
  sans `lotScanne`.
- `test/performance/gs1_depot_proforma_perf_test.dart` : 2 000 étiquettes étendues au Dépôt, aucune requête, temps
  comme avant.
- Non-régression : `test/gs1_depot_proforma_test.dart`, `test/gs1_depot_proforma_e2e_test.dart` et les tests de la
  4.9.2 (comptant, Proforma, borne) passent sans modification.
