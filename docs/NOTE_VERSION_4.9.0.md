# Prestige Mobile 4.9.0+31 — étiquettes GS1 à la vente, alignées sur le web

Vérifié dans le code du serveur (`rest.SalesRessource.lireGs1`, `GET v1/app-params/value/{clé}`) et du web
(lecture des étiquettes à la vente) :

| Route | Rôle |
|---|---|
| `GET v1/app-params/value/KEY_VENTE_LECTURE_GS1` | réglage de l'officine : `{success:true, data:"1"}` = lecture active ; autre valeur ou absent = inactive |
| `GET v1/vente/gs1?code=<contenu scanné>` (session) | verdict : `lot`, `peremption`, `perime`, `cip`, `controle` (CONFORME / DIFFERENT / INCONNU), `modeControle` (A / B / C, lu par le serveur dans `KEY_VENTE_CONTROLE_LOT_GS1`), `lotEnStock`, `lotPrevu`, `peremptionPrevue` ; `etendu`, `sansProduit` avec `msg` |
| `lotScanne` dans le corps de `add/vno`, `add/item`, `add/assurance` | lot de la boîte scannée ; le serveur ne le prend qu'en mode B |

L'application, comme le web, ne lit que `KEY_VENTE_LECTURE_GS1` : le mode de contrôle arrive dans la réponse de
`vente/gs1`. Le réglage est relu à chaque connexion et au retour de l'application au premier plan (avec les droits de
vente, en parallèle), et oublié à la déconnexion.

## Ce qui change

- **Lecture active** (`1`) et étiquette GS1 (DataMatrix, préfixes `]d2` `]Q3` `]C1`, forme lisible `(01)…(17)…(10)…`,
  lien GS1 Digital Link si son décodage est sans ambiguïté) : verdict du serveur avant le produit.
  - **Mode A**, lot différent : produit ajouté ; avertissement au vendeur avec la confirmation (6 s).
  - **Mode B**, lot en stock : produit ajouté ; `lotScanne` part avec la ligne de **ce** produit, une seule fois.
  - **Mode C**, lot différent : refusé, « Prenez une boîte du lot X, péremption Y : la boîte scannée (…) n'est pas
    ajoutée. »
  - **Boîte périmée** : refusée, « Boîte périmée (jj/mm/aaaa) : non ajoutée ».
  - **Étiquette étendue** et **sans produit** : refusées avec le message du serveur.
  - Le produit est ensuite cherché **par le chemin d'avant** (`ProductLookup.byCode`, avec le CIP rendu par le
    serveur).
- **Lecture inactive** (`0`, valeur par défaut), réglage absent, **serveur ancien** (404/405 sur `app-params` ou
  `vente/gs1`), panne, réponse illisible, délai de plus de **2,5 s** : exactement la recherche d'avant (décodage de
  l'appareil, mêmes codes essayés, même produit, aucun refus).
- **Hors ligne**, lecture active (dernier réglage lu) : boîte refusée si sa date de péremption (AI 17) est passée,
  « Boîte périmée (jj/mm/aaaa) : non ajoutée ». Le lot n'est pas contrôlé hors ligne. Lecture inactive : rien ne change.
- **Borne** : le client ne voit jamais de détail de lot. Boîte refusée (périmée, mode C lot différent, étiquette
  étendue, périmée hors ligne) → « Ce produit ne peut pas être ajouté ici : présentez-le au comptoir ». Aucun
  avertissement A/B. Mode B, lot en stock : `lotScanne` part à la création de la prévente avec la ligne du produit ;
  lots oubliés à chaque nouveau client.
- **Ancienne interface des ventes** (« nouvelle version des ventes » désactivée : vente comptant, assurance, carnet) :
  ses recherches passent par le même chemin GS1 ; l'étiquette 2D y est maintenant trouvée (avant : recherche texte
  du contenu brut, sans résultat), refus et avertissements affichés.
- **Inchangés** : code-barres 1D, CIP saisi, recherche par nom (jamais `vente/gs1`), dépôt, proforma.
- Le champ de recherche retire depuis toujours les caractères de contrôle (GS) : le serveur reçoit la forme du web
  (lot en dernier, sans ambiguïté).

## Sécurité

- Le contenu scanné (qui peut porter un numéro de série) n'est **jamais journalisé** : le journal du mode débogage
  ne montre que `GET …/vente/*` et le statut (test e2e).
- Aucune donnée réelle dans les tests (produits et lots fictifs).

## Tests

- `test/gs1_vente_test.dart` (unitaires) : reconnaissance (web, lien numérique, `]Q3`, parenthèses ; jamais un
  EAN-13, un CIP7 ou un nom), verdicts A / B / C, périmée, étendue, sans produit ; **non-régression** : pour lecture
  inactive, 404, 405, 500, réseau coupé, délai, réponse illisible, codes essayés et produit identiques à
  `ProductLookup.byCode` seul ; hors ligne.
- `test/gs1_vente_e2e_test.dart` (application entière) : mode A, mode B (`lotScanne` une fois), mode C, périmée,
  étendue, sans produit, lecture inactive, réglage absent (404), `vente/gs1` 404 et 500, code-barres et nom sans
  `vente/gs1`, hors ligne périmée refusée / valide ajoutée, ancienne interface (refus, produit trouvé lecture
  inactive), journal sans contenu scanné.
- `test/reseau/gs1_vente_reseau_test.dart` (vrai HTTP) : réglage avec la session (1, 0, 404, 405, 500, coupure),
  code en paramètre et `lotScanne` dans le corps, périmée sans recherche de produit, 404 / 405 / 500 / délai 6 s
  → comme avant en moins de 4 s.
- `test/performance/gs1_vente_perf_test.dart` : 20 000 reconnaissances en moins de 500 ms, aucune requête hors
  étiquette GS1, une seule requête de plus pour une étiquette, serveur lent → délai respecté.
- `test/borne_test.dart` (groupe « Étiquette GS1 ») : messages de la borne sans détail de lot, mode B à la création
  de la prévente, lecture inactive.
