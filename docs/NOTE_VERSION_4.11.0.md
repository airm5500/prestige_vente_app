# Prestige Mobile 4.11.0+40 : plan du pharmacien du 08/11

Trois chantiers :
1. la réception des BL ;
2. la saisie manuelle de la réserve ;
3. la taille des icônes.

Les changements serveur nécessaires sont décrits dans les demandes 59 et 60
(`docs/serveur/TRANSMISSION_SERVEUR_2026-10-15.md`). En attendant, l'application garde un repli : rien ne bloque cette
version.

## 1. Réception BL (nouvelle interface)

- **Nombre de lignes des commandes.** La liste affichait « N produit(s) » avec `int_NBRE_PRODUIT`. Dans le code du
  serveur, ce champ est la **quantité totale** (boîtes). L'application affiche maintenant le **nombre de lignes** :
  - `int_LINE`, déjà envoyé par `GET v1/commande/list` et `list/passees` ;
  - partout où la commande apparaît (présentations A, B, C et page « Créer le BL ») ;
  - sur un serveur sans `int_LINE`, « boîtes », jamais « produits ».
  
  La liste des BL affichait déjà les lignes et les boîtes.
- **Passage au champ suivant.** Entrée, la touche « Suivant » du clavier ou la douchette font avancer :
  - lot → péremption (ou directement la quantité si la date est déjà connue) ;
  - péremption → quantité ;
  - quantité → enregistrement de la ligne.
- **Péremption sans barres.** La règle de « Mise à jour péremption » est maintenant partagée par les deux écrans
  (`lib/services/saisie_peremption.dart`), sans copie :
  - **0128 = 01/01/2028** ;
  - **010128 = 01/01/2028** ;
  - 01012028 ;
  - JJ/MM/AAAA ;
  - MM/AAAA, le 1er du mois.
  
  Une date impossible est refusée et un message s'affiche sous le champ. L'aide « Sans barres : 0128 = 01/01/2028,
  010128 = 01/01/2028 » est affichée sous le champ.
  
  **Changement** : « 08/2028 » donne maintenant le **01/08/2028**, comme dans « Mise à jour péremption ». Avant, il
  donnait le 31/08/2028.
- **Quantité pré-sélectionnée.** Quand le champ Quantité prend le focus, la quantité attendue est sélectionnée. La
  frappe la remplace.
- **DataMatrix et photo** : même chemin que « Mise à jour péremption » (`lib/screens/common/lecture_lot_date.dart`).
  On ne reprend que le lot et la date.
  - **Caméra** : analyse en haute définition (1280×720 au lieu de 640×480), zoom automatique et bouton « Zoom ×2 ».
    La lecture est continue : pas de photo à prendre. Un code-barres sans lot ni date est signalé sur l'image et la
    lecture continue.
  - **Photo** : capture guidée. L'écran affiche un cadre, contrôle la netteté, la lumière et la stabilité, propose la
    lampe, et prend la photo tout seul quand l'image est bonne : l'appareil ne bouge plus au moment du déclic.
    - Si un DataMatrix est lu sur la photo, lot et date sont repris tels quels.
    - Sinon, le texte lu est **confirmé** par l'opérateur (« Vérifiez avec la boîte »).
- **BL incomplet.** Le bilan affiche toujours les **écarts reçu / BL**, ligne par ligne : reçu, commandé, manquant.
  - Code du serveur vérifié : `PUT v1/commande/validerbl` refuse une ligne commencée et incomplète. Il entre aussi une
    ligne **sans lot** à la **quantité commandée**. `avecEcart=true` est plus strict, pas plus souple.
  - **Demande 59** : « Entrer le reçu ». Seules les boîtes saisies entrent en stock et l'écart va au rapport. Ce bouton
    n'apparaît que si le serveur l'annonce (`clotureRecu` dans `GET v1/reception/parametres`).
  - Sur le serveur actuel, le BL incomplet reste ouvert : rien n'est entré par ce chemin.
  - Le retour fournisseur « en attente » des manquants attend la réponse à la question de la demande 59. Un retour
    classique sortirait du stock des boîtes jamais entrées.

## 2. Réserve

- **Saisie manuelle des sorties.** Dans le panier d'un sens (Réserve → Rayon **ou** Rayon → Réserve, jamais les deux
  à la fois), un champ « Saisir un produit » est toujours prêt :
  - douchette (DataMatrix ou code-barres), CIP ou début du nom ;
  - les produits suivis en réserve sont cherchés (`GET v1/reserve/articles`) ;
  - un seul produit trouvé : la quantité est demandée tout de suite ; plusieurs : on choisit dans la liste ;
  - après validation, le curseur revient dans le champ pour le produit suivant.
- **Confirmation du sens avant la création.** Le message affiché :
  - Réserve → Rayon : « Vous allez créer une demande (suggestion) de sortie de la réserve, vous confirmez le sens ? » ;
  - Rayon → Réserve : « … de rangement en réserve … ».
  
  Le message affiche aussi le sens, le nombre de produits et le nombre de boîtes. La création se fait par la route
  existante `POST v1/suggestion-reserve/creer`, avec la catégorie du sens.
- **Droit « Voir les suggestions de réserve » (demande 60).** Le serveur l'annonce par `voirSuggestions` dans
  `GET v1/reserve/droits`. Quand il vaut `false` :
  - onglet « Automatique » masqué ;
  - aucune lecture des suggestions ;
  - une demande créée n'est pas ouverte ; le message est « Demande … créée : elle sera traitée par une personne
    habilitée ».
  
  Champ absent (serveur actuel) : comportement d'avant.
- ANO-07 corrigée : la pastille du sens passe à la ligne au lieu de déborder (texte agrandi, 360 dp).

## 3. Icônes

**Avant**, audit avec `test/outils/captures_icones_test.dart`, en dp réels :
- les icônes sans taille explicite (barres du haut, boutons-icônes, listes, barre du bas) faisaient **24 dp** sur
  tous les écrans ;
- sur les terminaux Sunmi, « Automatique » applique Compact (×0,9) : il restait **21,6 dp** ;
- sur une tablette 10″, 24 dp, ce qui paraît minuscule.

**Correction**, d'un seul endroit (`lib/ui/icones.dart`, appliqué par le thème) :

| Écran | Facteur | Icône par défaut |
|---|---|---|
| Tablette (côté court ≥ 600 dp) | ×1,33 | 24 → 32 dp |
| Terminal (petit écran) | ×1,25 | 24 → 27 dp réels en Compact |
| Téléphone courant | ×1,0 | inchangé |

Les tuiles de l'accueil et les grandes actions suivent le même facteur. Les boîtes de couleur et la hauteur des
lignes ne changent pas : aucune entrée n'est repoussée hors de l'écran.

**Médianes mesurées (avant → après)** :

| Écran | Accueil | Réception | Vente |
|---|---|---|---|
| Sunmi V2s / V3 | 27 → 33,8 dp | 21,6 → 27 dp | 21,6 → 27 dp |
| Tablette 10″ | 30 → 39,9 dp | 24 → 31,9 dp | 24 → 31,9 dp |
| Téléphone 360 × 800 dp | inchangé | inchangé | inchangé |

Les petites marques (cadenas, pastilles du sens) gardent leur taille.

**Exclus** :
- **écran CLIENT de la borne** (`SansEchelleIcones`) : sa mise en page a été réglée en 1.8.1 et ses pictogrammes
  sont déjà grands ;
- **PrestigePOS** : son application ne passe pas par ce thème.

**Contrôles** : aucune erreur de rendu ; cibles d'au moins 48 dp ; ergonomie de tous les écrans (`ergonomie_test`)
inchangée.

## Tests (catégories de la CI)

- **Unitaires** — `test/saisie_peremption_test.dart` : règle de la péremption, `int_LINE`, écarts, droit, facteurs
  d'icônes.
- **Écrans** — `test/reception_bl_test.dart` :
  - champs enchaînés, « 0128 », « 010128 », date illisible ;
  - quantité pré-sélectionnée ;
  - DataMatrix de la photo, DataMatrix par la caméra ;
  - BL incomplet avec et sans `clotureRecu` ;
  - lignes des commandes en A, B, C.
- **Intégration et écrans** — `test/reserve_test.dart` :
  - saisie rapide (CIP, nom, DataMatrix, inconnu) ;
  - confirmation des deux sens ;
  - droit faux : création sans ouverture, aucun onglet Automatique.
- **E2E** — `test/plan_0811_e2e_test.dart`, application entière :
  - réception de bout en bout, avec et sans `clotureRecu` ;
  - réserve de bout en bout, avec et sans le droit.
- **Réseau** — `test/reseau/plan_0811_reseau_test.dart`, vrai HTTP :
  - capacité `clotureRecu` : vraie, absente, 404, serveur coupé ;
  - `?mode=RECU` et clôture classique sans paramètre ;
  - `int_LINE` ;
  - `voirSuggestions` : vrai, faux, absent, avec la session ;
  - recherche et création de la réserve.
- **Ergonomie** — `test/plan_0811_ergonomie_test.dart` : V2s, V3, 360 × 800 dp et tablette, texte ×1 et ×1,3 :
  - icônes et cibles ;
  - aide et erreur de la péremption ;
  - écarts et « Entrer le reçu » ;
  - saisie rapide et confirmation du sens.
- **Performance** — `test/performance/plan_0811_perf_test.dart` :
  - 100 000 dates lues en moins de 1 s ;
  - une requête par produit saisi, aucune relecture des suggestions ;
  - thème des icônes.
- **Non-régression** — `test/plan_0811_garde_test.dart` :
  - règle et chemin lot / date partagés, sans copie ;
  - clôture classique inchangée ;
  - borne et PrestigePOS exclus ;
  - droit absent = comme avant.
- **Référence 360 × 800 dp** (`responsive_test`) : seuls les libellés des commandes de la réception changent
  (« 3 lignes » au lieu de « 3 produit(s) »).
- **Captures avant / après** : `test/outils/captures_icones_test.dart` (hors CI, `APERCUS=1`).
