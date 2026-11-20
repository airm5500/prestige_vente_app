# Prestige Mobile V3 5.1.0+51 : retours du pharmacien du 20/11/2026

Même application (`com.dici.prestigemobile.v3`, « Prestige Mobile V3 »), même icône que la 5.0.1+50. Six retours
corrigés ; aucun changement de contrat avec le serveur (une demande 66 lui est transmise pour ses propres tickets).

## 1. Recherche produit de la vente : le texte tapé est repris dans la liste (régression)

Avant la nouvelle interface (ancienne fenêtre de `vente_tab.dart`, commit 72abd30), la liste des résultats s'ouvrait
avec le texte tapé dans « Filtrer dans la liste… », le curseur à la fin et le clavier ouvert : on continuait à taper
pour préciser. Depuis 963fcb6 (nouvelle fenêtre sans `FocusNode` ni curseur) et ca2c7dd (recherche par pages :
`initialQuery: ''` dans `_searchPaged`), le champ s'ouvrait **vide et sans focus**.

5.1.0 (`lib/ventes/common/product_list_modal.dart`, `vente_product_search.dart`, `product_lookup.dart`) :

- le texte tapé est repris, le champ a le focus, le curseur est à la fin, le clavier reste ouvert (Entrée ne le ferme
  pas) ;
- tant que ce texte n'est pas modifié, **aucun filtre local** : les résultats du serveur restent tous affichés (un
  EAN-13 tapé dont le produit est trouvé par son CIP7, une recherche « Contient » sur plusieurs mots) ;
- le filtre cherche **chaque mot** dans le nom ou le CIP (« DOLI 1000 » trouve « DOLIPRANE 1000MG ») ;
- liste incomplète (« 50 sur 252 ») et texte qui prolonge la recherche : **nouvelle recherche sur le serveur** 400 ms
  après la dernière frappe (la précédente est abandonnée), indicateur dans le champ, filtre local des produits déjà
  chargés en attendant ; retour au texte d'origine : la liste d'origine revient sans requête.

Ventes Dépôt et Proforma : même fenêtre (filtre par mots, recherche sur le serveur), champ vide comme avant.

## 2. Fenêtre de quantité

- Nom du produit plus petit (15 px, semi-gras) suivi du CIP dans le même texte, en gris plus petit :
  « NOM · CIP 3400930000001 », deux lignes au plus. La pastille CIP est retirée (prix et stock gardés).
- Clavier ouvert : présentation compacte (ni raccourcis 1/2/3/5/10 ni aide « 1 à 9999 »), marges réduites, fenêtre
  défilante, marge au-dessus du champ : l'étiquette « Quantité » n'est plus coupée et « Total ligne » reste visible
  avec les boutons, sur un téléphone de 360 dp (Sunmi V2s 720×1440). Sans clavier : comme avant.

## 3. Premier ticket non imprimé sur le terminal Sunmi

Le toast « Sunmi Printer Service Connected » (du paquet `sunmi_printer_plus`) apparaissait, rien ne sortait.
Cause : rien ne liait le service d'impression au démarrage ; le paquet répond `true` à la liaison dès qu'elle est
**demandée**, avant la connexion réelle. Au premier ticket, la largeur était lue avant la connexion (« NOT FOUND »),
mémorisée « aucune imprimante intégrée » pour toute la session (« Réimprimer » échouait aussi), et les commandes du
ticket local partaient vers un service pas encore connecté (perdues).

5.1.0 (`lib/services/imprimante_sunmi.dart`, `impression_ticket.dart`, `receipt_service.dart`, `largeur_ticket.dart`,
`main.dart`, Réglages › ticket d'essai) :

- sur un terminal Sunmi (fabricant « SUNMI »), liaison demandée **une fois au démarrage**, sans attendre ;
- avant toute impression (ticket du serveur, gabarit local, borne, ticket d'essai) et avant de lire la largeur :
  attente de la **connexion réelle** (version de l'imprimante lisible), 3 s au plus ; sinon « imprimante intégrée pas
  encore prête… Réessayez » et « Réimprimer » ;
- une largeur lue sans connexion n'est **jamais mémorisée** ;
- autres appareils (tablette, téléphone) : aucun changement (aucune attente).

Le toast vient du paquet : il reste affiché à la première connexion.

## 4. « En attente du serveur » au moment d'imprimer

Aucun texte « En attente du serveur » n'existe dans Prestige Mobile ni dans PrestigePOS (code Dart, ressources
Android, paquet d'impression). Le plus proche est « Envoi au serveur… », la bande d'état de la vente pendant
l'enregistrement et la clôture. Ensuite, pendant que le serveur dessine le ticket (`GET v1/vente/ticket/…/image`,
jusqu'à 20 s), rien ne s'affichait. 5.1.0 : bandeau **« Préparation du ticket… »** avec un indicateur, au-dessus de
l'écran, dès 300 ms d'attente, retiré à la réponse (ou à l'erreur).

## 5. Taux des organismes : 100 % au plus, comme le web

Client à deux organismes 80 % et 30 % : le ticket local imprimait 80 % et 30 %. Comme le web (ticket du serveur,
`CreditLigne.tauxAffiches`) : taux affiché = min(taux, 100 − taux déjà affichés), jamais négatif, et le dernier
organisme à 1 ou 2 points de 100 % affiche le reste exact. 80 % + 30 % → **80 % + 20 %**.

Appliqué au ticket local d'assurance / carnet et aux récapitulatifs de la vente (répartition et carte client de
l'Assurance, pied et carte client du Carnet). Les écrans de choix du client et de la couverture gardent le taux du
contrat ; les taux envoyés au serveur et les parts ne changent pas.

Serveur (intégration 5f0ab46f) : l'image du ticket de vente assurance est déjà plafonnée ; le ticket de prévente
(`TicketPrevente`) et le ticket client combiné (`TicketCombine`) impriment encore le taux brut : **demande 66**
(`docs/serveur/TRANSMISSION_SERVEUR_2026-10-15.md`).

## 6. Analyse article lente

Dès la liste affichée, un « lot » `GET /info?search=<texte tapé>` lisait les détails de jusqu'à 30 produits ; au
clic, le détail **attendait toute cette réponse**. 5.1.0 (`lib/accueil/fiche_produit_screen.dart`) :

- au clic : le lot sert seulement s'il est **déjà arrivé** ; sinon `GET /info?search=<CIP>` est envoyé tout de suite ;
- lot limité aux listes de **5 produits** au plus (30 avant) ;
- détail ou fiche fermés avant la réponse : la requête est **annulée** (une réouverture en envoie une nouvelle).

Même règle pour la recherche de l'accueil (fiche produit).

## Non traité dans cette version

Menus « Metro », centre de support et empreintes : explications seulement, aucun changement.

## Contrôles

- `test/retours_2011_test.dart` (unitaires et écrans), `test/retours_2011_e2e_test.dart` (application entière),
  `test/retours_2011_ergonomie_test.dart` (fenêtre de quantité, Sunmi V2s, clavier ouvert).
- Tests mis à jour : `ventes_common`, `ventes_assurance_ui` (80 % + 30 %), `lenteur_detail_432`,
  `recherche_rapide_info`, `reseau/serveur_lent`, `scan_fiche_analyse`, `retours_video`, `retours_accueil`,
  `v3_identite` (version).

Version **5.1.0+51** (`pubspec.yaml`) ; voir `docs/VERSIONS_SUNMI.md`.
