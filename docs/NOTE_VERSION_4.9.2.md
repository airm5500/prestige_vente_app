# Prestige Mobile 4.9.2+33 — étiquettes étendues refusées comme le web, même lecture GS1 inactive

Décision du pharmacien : les étiquettes **étendues** d'Étiquetage Pro (DataMatrix+, QR+) sont refusées à la vente
comme sur le web, **même quand `KEY_VENTE_LECTURE_GS1` est inactif ou absent**.

## Ce que fait le web (vérifié, dépôt du serveur en lecture seule)

- **Où :**
  - `VenteCtr` (vente au comptant, assurance, carnet) ;
  - `DevisCtr` (proforma) ;
  - `VenteEnDepotCtr` (vente dans un dépôt d'extension : écran absent de Prestige Mobile).
  - `DepotCtr` (vente à un dépôt, `add/depot`) **ne les refuse pas**.
- **Comment :** reconnaissance **locale**, sans requête, avant toute lecture GS1 (`estEtiquetteEtendue`) :
  - le préfixe de lecteur `]d2`, `]Q3`, `]Q1`, `]C1` ou `]e0` est retiré ;
  - puis le contenu est étendu s'il commence par `EP1|` (QR+, sans tenir compte de la casse),
  - ou s'il contient le champ 91 `EPLUS1` après un séparateur (caractère GS, `<GS>`, `^]`, `~1`, `|`),
  - ou s'il contient `(91)EPLUS1`, ou commence par `91EPLUS1` (DataMatrix+).
  - Le serveur (`ContenuEtendu`) suit la même règle : marqueur `EPLUS1` dans le champ 91, préfixe `EP1|`.
- **Message :** « Cette étiquette (DataMatrix+ ou QR+) est réservée à la commande, à la réception et à l'inventaire :
  elle ne passe pas à la vente. Scannez le code de la boîte ou l'étiquette standard du produit. »

## Ce qui change

- **Reconnaissance sur l'appareil**, portage exact de la règle du web (`Gs1Vente.estEtiquetteEtendue`) : aucune
  requête, donc aussi hors ligne et sur un serveur ancien.
- **Refus, quel que soit le réglage GS1**, avec le message du web ; rien n'est ajouté, aucune recherche de produit :
  - vente au comptant (nouvelle interface ; la reconnaissance se fait sur le contenu reçu, avant le nettoyage du
    champ) ;
  - ancienne interface des ventes (comptant, assurance, carnet) ;
  - Proforma.
- **Borne :** « Ce produit ne peut pas être ajouté ici : présentez-le au comptoir », sans détail.
- **Dépôt :** comme le web (`DepotCtr`), pas de refus local.
  - Lecture inactive : comportement d'avant.
  - Lecture active : le verdict du serveur (4.9.1) refuse l'étiquette étendue, comme avant cette version.
- **Seul changement en lecture inactive :** l'étiquette étendue. Les étiquettes GS1 normales (DataMatrix, QR), les
  codes-barres 1D, le CIP et la recherche par nom se comportent exactement comme avant ; les suites de la lecture
  inactive des versions 4.9.0 et 4.9.1 passent sans modification.

## À savoir

Les champs de recherche de l'application retirent depuis toujours les caractères de contrôle. Si la douchette
transmet le séparateur GS comme caractère de contrôle **dans un champ**, il disparaît avant la reconnaissance. Le
DataMatrix+ n'est alors reconnu que sous ses autres formes (`<GS>`, `^]`, `~1`, `|`, parenthèses), exactement comme
le web, qui exige lui aussi un séparateur devant `91EPLUS1`. Le QR+ (`EP1|…`) est toujours reconnu. Le contenu reçu
par la douchette hors du champ (saisie rapide) ou par la caméra garde ses séparateurs.

## Sécurité

Le contenu scanné n'est jamais journalisé. Les tests n'utilisent que des données fictives.

## Tests

- `test/gs1_etendue_test.dart` (unitaires) :
  - toutes les formes reconnues par le web ;
  - jamais une étiquette normale, un code-barres, un CIP, un nom, un champ 91 de fabricant, ni sans séparateur ;
  - refus local en lecture active, inactive et hors ligne, sans requête ;
  - message exact ;
  - Dépôt et autres menus comme avant.
- `test/gs1_etendue_e2e_test.dart` (application entière) :
  - comptant avec lecture 0, réglage absent et lecture 1, sans requête ;
  - hors ligne ;
  - ancienne interface ;
  - Proforma ;
  - Dépôt comme avant ;
  - étiquette normale, code-barres et nom en lecture inactive comme avant ;
  - journal.
- `test/reseau/gs1_etendue_reseau_test.dart` (vrai HTTP) : refus sans aucune requête (inactif, 404, actif), serveur
  coupé, étiquette normale en lecture inactive comme avant.
- `test/performance/gs1_etendue_perf_test.dart` : 50 000 reconnaissances en moins de 500 ms.
- `test/borne_test.dart` : DataMatrix+ et QR+ en lecture inactive, message pour le client.
