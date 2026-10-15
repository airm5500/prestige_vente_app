# Prestige Mobile 4.3.2+18 — Analyse article et fiche produit de nouveau rapides

Retour du pharmacien (vidéo du 15/10/2026) : « Le menu Analyse article affichait les données et le graphe en un
temps record ; on a juste ajouté le stock réserve et il met tout ce temps à charger. » Même lenteur sur la fiche
produit ouverte depuis la recherche de l'accueil et depuis l'onglet Scanner.

## La cause, simplement

**Ce n'est pas le stock réserve.** Il arrive dans la même réponse que le reste (`GET /info`) : aucune requête de plus
côté application ; côté serveur, une petite lecture indexée par produit (1 ligne).

**C'est la façon d'ouvrir le détail, changée en 4.2.0** (livrée le même jour que la Réserve en onglets, d'où la
confusion) :

| | Avant (4.1.x) | 4.2.0 → 4.3.1 |
|---|---|---|
| Liste | `GET /info?search=<saisie>` (lent, mais une seule fois) | `GET /vente/search` (rapide) |
| Clic sur un produit | **aucune requête** : tout était déjà là | `GET /info?search=<CIP>` **après le clic**, en série |
| Fermer puis rouvrir | immédiat | requête abandonnée, puis **nouvelle attente complète** |

Or, sur le serveur, `GET /info` calcule **les ventes des 6 derniers mois de TOUT le catalogue** avant de garder le
produit demandé : il coûte presque autant pour un seul produit que pour une liste (demande serveur 44, déjà
transmise). Depuis la 4.2.0, ce calcul complet était donc attendu **à chaque clic**, ce qui se voit dans la vidéo :
ARTEFAN 20/120 cliqué à 25,5 s → graphe à 27,0 s ; ARTEFAN 40/240 cliqué à 31,0 s → graphe à 33,0 s ; fiche
FERCEFOL ouverte à 9,0 s → analyse à 11,0 s (`GET /info` ≈ 2 s chez l'officine, la liste `GET /vente/search`
≈ 0,5 à 1,5 s).

- **Part de l'application** : la lecture de l'analyse partait APRÈS le clic (en série) et était perdue si l'on
  fermait le détail avant la réponse.
- **Part du serveur** : la durée de `GET /info` elle-même (6 mois de ventes de tout le catalogue + 6 à 8 lectures
  par produit). Elle croît avec le volume de ventes : mesure SQL sur une copie de la base de test multipliée
  (requête principale, un seul CIP) : 0,04 s (6 512 lignes de vente) · 0,15 s (×10) · 0,45 s (×30) · 0,91 s (×60,
  390 720 lignes). Demande 44 inchangée (seul le serveur peut la supprimer).

## Ce qui change

1. **Mode hybride** (Analyse article et recherche de l'accueil) : la liste vient toujours de `GET /vente/search`
   (rapide) ; dès qu'elle est affichée, **un seul** `GET /info?search=<saisie>` est lu en arrière-plan (lot) si la
   liste compte 1 à 30 produits et la saisie 3 caractères ou plus. Au clic, le détail est pris dans ce lot : déjà
   arrivé → **immédiat** ; encore en route → on attend **ce** lot (jamais une 2ᵉ requête). Une saisie qui prolonge
   la précédente (« artefa » après « artef ») ne relance rien ; un lot devenu inutile est abandonné (sauf s'il est
   attendu). Liste trop longue ou saisie courte : comme avant, `GET /info` du CIP au clic. Sur le serveur, ce lot
   coûte à peine plus qu'une lecture d'un seul produit (le calcul des 6 mois domine).
2. **Tout ce qui est connu s'affiche tout de suite** : nom, CIP, stock, prix de vente, **prix d'achat** et
   **emplacement** (donnés par la recherche rapide) ; seuls le grossiste, les moyennes, le stock réserve et le
   graphe attendent `GET /info`.
3. **Détail fermé avant la réponse** : la requête continue et sa réponse est gardée (cache **en mémoire**, 2 min,
   jamais sur disque) : la réouverture est immédiate. Délai dépassé : la requête est oubliée et « Réessayer » en
   envoie une nouvelle.
4. Aucune lecture secondaire (images du produit) ne retarde l'analyse ; elles partent en parallèle.
5. Onglet **Scanner** : recherche par code puis `GET /info` du CIP (l'ordre est obligatoire : il faut d'abord
   trouver le produit) ; la fiche s'ouvre sans attendre, avec stock, prix, prix d'achat et emplacement.
6. Le journal des requêtes HTTP (corps des réponses) n'est plus écrit dans l'APK livré (mode débogage seulement).

## Mise en page de l'Analyse article

- Liste : « **Stock 30 · Prix de vente 830 F** » sur **une ligne** (cartes plus compactes).
- « Détails de l'Article » : informations **deux par ligne**, **Stock rayon et Stock réserve sur la même ligne** ;
  en-tête et bouton **Fermer fixes**, toujours visibles sans défiler (Sunmi V2s et 360×640, texte ×1 et ×1,3) ;
  sur la Sunmi V2s, texte ×1, tout le détail tient sans défiler.

## Redéploiement de Prestige : plus d'« erreur 404 »

Pendant un redéploiement, Payara répond 404 (page HTML), 502 / 503, ou refuse la connexion. La connexion affichait
« erreur 404 » (borne : « Connexion refusée … HTTP 404 »), ou « Login ou mot de passe incorrect » dans
l'interface d'origine. Désormais, **dans les deux interfaces** (et la borne) : **« Serveur indisponible, veuillez
réessayer »** ; un vrai mot de passe faux reste « incorrect ».

## Mesures

| Parcours | 4.3.1 | 4.3.2 |
|---|---|---|
| Analyse article, graphe après le clic (vidéo, délais de l'officine simulés : `/info` 2 s, `/vente/search` 0,5 s) | 2,56 s · 2,41 s | 0,56 s · 0,17 s (2ᵉ produit) |
| Fiche produit depuis la recherche de l'accueil, analyse après le clic (idem) | 2,20 s | 1,09 s |
| Requêtes `GET /info` pour « artef » + 2 détails | 2 (une par clic, après le clic) | 1 (la saisie, dès la liste) |
| Faux serveur lent (`/info` 4 s), graphe après un clic 1 s après la liste | ≥ 4,0 s | 2,95 s |

Serveur de test local (base `laborex`, 1 794 produits, 6 512 lignes de vente — **bien plus petite que celle de
l'officine**) : `GET /vente/search` 24-39 ms, `GET /info` d'un CIP 43-55 ms, `GET /info` d'une saisie 51-199 ms
(1 à 21 produits). La lenteur liée au volume de la base de l'officine ne s'y reproduit pas ; les vidéos ont donc été
faites aussi avec les délais mesurés sur la vidéo du pharmacien, ajoutés par un relais local.

## Tests

`lenteur_detail_432` (performance : nombre, ordre et temps des requêtes contre un faux serveur lent ; identité,
stock et prix immédiats ; graphe à la réponse ; images lentes sans effet ; unitaires du cache), `ergonomie_analyse_432`
(une ligne stock / prix, rayon et réserve sur une ligne, Fermer visible : 2 écrans × 2 tailles de texte),
`reseau/redeploiement` (404 de Payara, 502/503/504, connexion refusée, mot de passe faux, deux interfaces) ;
tests existants mis à jour (`recherche_rapide_info`, `retours_video`, `performance/requetes`, `reseau/serveur_lent`,
`recherche_debut_cip`, `scan_fiche_analyse`, `retours_accueil`, `connexion_lancement`, `integration_services`,
`licence_lookup`).
