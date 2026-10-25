# Prestige Mobile 4.9.4+35 — Dépôt : étiquette étendue sans produit, exactement comme le web

Décision du pharmacien : à la vente **Dépôt**, garder le comportement du web pour une étiquette étendue
(DataMatrix+, QR+) : **aucun produit, rien de particulier**.

## Le web (rappel, vérifié dans `DepotCtr`)

- Il ne reconnaît pas l'étiquette étendue et n'appelle pas `vente/gs1`.
- `GET v1/vente/findone/<contenu brut>` cherche un CIP, un EAN-13 ou un code article commençant par ce contenu : il
  ne trouve rien.
- Le champ reprend le focus, sans message.

## Ce qui change (Dépôt seulement)

- **Avant (4.9.3) :** l'étiquette étendue suivait la recherche d'avant. Le DataMatrix+ était trouvé par son GTIN ; le
  QR+ ne trouvait rien.
- **Maintenant :** une étiquette étendue, reconnue sur l'appareil par la règle du web (4.9.2), ne donne **aucun
  produit**, lecture GS1 active ou inactive. Concrètement :
  - aucune requête (ni `vente/gs1` ni recherche de produit), et pas de lecture du GTIN ;
  - aucun message (ni refus ni « introuvable »), aucune fenêtre ;
  - le champ de recherche est vidé, prêt pour le scan suivant.
- **Inchangés au Dépôt** (4.9.1) : étiquette GS1 normale (verdict du serveur, boîte périmée refusée, mode C refusé,
  avertissement A / B, sans produit, périmée hors ligne refusée, aucun `lotScanne`), codes-barres, CIP, nom.
- **Inchangés ailleurs :**
  - refus de l'étiquette étendue au comptant, à la Proforma et à la borne (4.9.2) ;
  - tous les autres menus de recherche ;
  - la limite du séparateur GS retiré par les champs. Un DataMatrix+ dont le séparateur a disparu n'est pas
    reconnu comme étendu et suit la recherche d'avant, comme le web, qui exige lui aussi un séparateur.

## Tests

- `test/gs1_etendue_test.dart` :
  - Dépôt, lecture active et inactive : DataMatrix+ (GS, `|`, `<GS>`) et QR+ (avec ou sans `]Q3`) → aucun produit,
    rien d'annoncé, aucune recherche ni requête `vente/gs1` ;
  - une recherche suivante remet l'état à zéro ;
  - autres menus et étiquette normale inchangés.
- `test/gs1_etendue_e2e_test.dart` (application entière) : Dépôt avec lecture 0 et 1, pour DataMatrix+ et QR+ :
  aucune fenêtre, aucun bandeau, aucune recherche, rien ajouté ; l'étiquette normale suivante est trouvée.
- `test/reseau/gs1_etendue_reseau_test.dart` (vrai HTTP) : aucune requête pour l'étiquette étendue ; étiquette normale
  avec verdict et ligne sans `lotScanne`.
- `test/performance/gs1_depot_proforma_perf_test.dart` : 2 000 étiquettes étendues, aucune requête, pas plus lent.
- Non-régression : suites du Dépôt et de la Proforma (4.9.1), refus du comptant, de la Proforma et de la borne
  (4.9.2), inchangées.
