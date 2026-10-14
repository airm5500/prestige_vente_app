# Prestige Mobile — note de version 4.0.3 (versionCode 11)

Suite de la 4.0.2+10 (pas encore publiée sur le magasin Sunmi, dernière version publiée : 3.3.1 / 7).
Numérotation : `docs/VERSIONS_SUNMI.md` (+N augmenté de 1 : **4.0.3+11**).

Trois points autorisés par le pharmacien, sans autre changement.

## F1 — Configuration d'origine : la ligne « Type de code ticket » débordait

- **Symptôme** : dans la Configuration de l'interface d'origine (`lib/screens/auth/settings_screen.dart`), la ligne
  « Type de code ticket » (libellé + choix « QR Code / Code-barres » côte à côte, sans retour à la ligne possible)
  débordait d'environ 132 px **même sur tablette** (largeur de l'écran bornée à 500 dp). Sur un téléphone de
  360 dp et sur les Sunmi (Compact automatique), trois lignes voisines construites de la même façon débordaient aussi :
  « Largeur du ticket », « Mode test d'impression » et, texte agrandi, « Comparaison Stock BL ».
- **Correction (mise en page seulement)** : ces lignes utilisent `_LigneReglage` : libellé à gauche et choix à
  droite quand les deux tiennent (aspect d'origine), sinon **le choix passe sous le libellé** ; un choix plus large
  que tout l'écran (texte très agrandi) se réduit au lieu d'être coupé. Boutons, valeurs (`QR_CODE` / `BARCODE`,
  58 / 80 mm, `theorique` / `machine`) et enregistrement **inchangés**. Nouvelle interface non modifiée.

## F2 — Analyse article : seuil de réserve à 0

Confirmé par le pharmacien : un seuil de réserve à 0 veut dire « non défini » (pas de ligne « Seuil réserve », pas
d'alerte « À réapprovisionner » même avec une réserve vide). **Rien à changer** ; test explicite ajouté
(`test/stock_reserve_test.dart`, « F2 »).

## F3 — Recherche par début de CIP : le bon produit n'était pas en première ligne

- **Symptôme** : dans **Recherche Article** et **Évaluation Vente**, taper le début d'un CIP (ex. « 3595 ») ne
  remontait pas forcément le produit de ce CIP en première ligne ; après l'avoir choisi, la fiche pouvait même
  afficher le stock / les prix / les ventes d'un **autre** produit.
- **Cause** (côté appli, le serveur n'est pas modifié) :
  1. **Liste** (`GET /vente/search`) : le serveur cherche « commence par » (« Contient » : `%…`) à la fois sur le
     **nom**, le **CIP** et l'**EAN fabricant**, et renvoie les produits **triés par nom** (comme sa copie hors ligne,
     `ORDER BY nom`). L'application affichait cet ordre tel quel : pour « 3595 », « 3595 BABY LAIT… » (nom) et
     « ADVIL… » (EAN fabricant 3595…) passaient avant les DOLIPRANE dont le CIP commence par 3595. Et tous les
     EAN-13 / CIP13 français commencent par **34009** : « 3400… » ramène presque tout le catalogue, le bon produit
     peut alors n'être que sur une page suivante. Ni le mode Début / Contient ni la page de 50 produits n'en sont la
     cause : la requête envoyée est la bonne, c'est l'ordre affiché qui ne tenait pas compte du code.
  2. **Détails** : après le choix, `GET /info?search=<CIP>` et `GET /produit/stats/vente-annuelle?search=<CIP>`
     cherchent aussi « commence par » et trient par nom ; l'application prenait la **première ligne** — par exemple
     celle de « 3595583D » (déconditionné, nom trié avant) pour le CIP 3595583. La fiche produit de l'accueil
     choisissait déjà la bonne ligne (`articleDuProduit`), pas ces deux écrans.
- **Correction** (`lib/services/classement_code.dart`) : quand la saisie est **numérique**, les produits dont un
  code commence par la saisie passent en tête — **correspondance exacte d'abord** (CIP, CIP13 calculé
  « 34009 + CIP7 + clé », CIP7 d'un CIP13, EAN fabricant), puis CIP qui commence par la saisie, puis autre code
  (CIP13 / CIP7 / EAN) qui commence par la saisie — **le reste dans l'ordre du serveur**. Un nom n'est jamais
  réordonné. La liste entière reste classée quand la suite est chargée.
  - Recherche Article, Évaluation Vente : liste (`PagedProductSearch(classerCodes: true)`, y compris les candidats
    d'un code de 7 chiffres ou plus) ; détails : ligne du **même CIP** (`ApiService.ligneInfoDuCip`, ventes
    annuelles par `ligneDuCode`), sinon la mieux classée.
  - Même défaut, même fonction : recherche de l'accueil (liste) et Analyse article (liste de `GET /info`).
  - Autres menus (Proforma, Dépôt, Ajustement, Péremption…) : ordre du serveur inchangé. Requêtes envoyées
    inchangées (mêmes paramètres, même mode Début / Contient).

## Tests

- `test/configuration_origine_test.dart` (nouveau) : Configuration d'origine sans débordement sur toute sa hauteur
  aux tailles Sunmi V2s / V3 (Compact automatique), téléphone 360×640 dp, téléphone 360×800 dp, tablette, texte ×1,0
  et ×1,3 ; libellé et choix de « Type de code ticket » entièrement dans l'écran, côte à côte ou l'un sous l'autre ;
  choix non réduit au texte normal ; mêmes valeurs `QR_CODE` / `BARCODE`.
- Exception de débordement **retirée** : test « sans configuration » de l'interface d'origine
  (`non_regression_test`), ainsi que les tolérances devenues inutiles de `version_affichee_test` et
  `ergonomie_taille_ecran_test` (Configuration d'origine).
- `test/recherche_debut_cip_test.dart` (nouveau) : unitaires du classement (CIP13 ↔ CIP7, rangs, stabilité,
  choix de la ligne), `PagedProductSearch` (liste, suite chargée, candidats d'un code, autres menus inchangés) ;
  e2e contre le faux serveur Prestige (réponses `/vente/search`, `/info?search=` et ventes annuelles triées par nom,
  avec un nom qui commence par les chiffres, un EAN fabricant et un CIP qui les contiennent) : Recherche Article et
  Évaluation Vente en Début et Contient (liste **et** détails du produit choisi), Analyse article, recherche de
  l'accueil. Ces tests échouent sans la correction.
- `test/stock_reserve_test.dart` : F2 (seuil réserve à 0 = non défini).
- Non-régression : toute la suite de la CI verte, rendu de référence 360 px (`responsive_reference_360.json`)
  inchangé, `flutter analyze` sans nouvelle remarque.
