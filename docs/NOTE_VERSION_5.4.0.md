# Prestige Mobile V3 5.4.0+54 : 2e ticket des ventes à crédit, réédition des ventes, contraste d'impression

Même application (`com.dici.prestigemobile.v3`, « Prestige Mobile V3 »), même icône que la 5.3.0+53. Aucune nouvelle
permission, aucune bibliothèque ajoutée. Serveur : routes déjà déployées en officine (76aa5fc1), rien de nouveau
demandé pour fonctionner. Prestige Pointage inchangée (1.1.0+2, son code n'est pas touché).

Retours du pharmacien du 20/11 au soir (SUNMI V3).

## 1. Vente à crédit : le 2e ticket ne sortait plus

**Constat** : vente assurance / tiers payant, « nombre de tickets = 2 » avant la validation ; le 1er ticket sort, la
question pour le 2e n'apparaît plus, le 2e ne sort jamais.

**Cause** (régression de la 4.14.0, devenue visible le 19/11 avec le déploiement du serveur 76aa5fc1 en officine) :
depuis la 4.14.0, quand le serveur dessine le ticket (route `GET v1/vente/ticket/{vno|vo}/{id}/image`), l'application
arrêtait la série de copies après la 1ʳᵉ (« le serveur décide du nombre d'exemplaires »). Or cette route est la
**réimpression du poste** : elle rend UN exemplaire de la vente (« la reimpression sort le ticket de cette vente en un
exemplaire », `GenerateTicketServiceImpl.lunchPrinterForTicketVo(id)`). Tant que le serveur de l'officine n'avait pas
la route, le ticket venait du gabarit local et la pause « Ticket suivant (2/2) » de la 4.10.3 fonctionnait ; avec le
serveur déployé, elle a disparu. Les changements de la 5.1.0 (attente de la connexion Sunmi, « Préparation du
ticket… ») n'en sont pas la cause (vérifié par les tests, Sunmi lent compris).

**Correction** : comportement d'avant la régression, pour toutes les ventes (comptant, assurance, carnet, ancienne
interface) : 1er ticket ; puis, avant CHAQUE ticket suivant, « Ticket suivant (i/N) — Coupez le ticket, puis
imprimez le suivant. » [Arrêter] [Imprimer] ; le nombre de tickets choisi (1, 2, n) est respecté ; chaque copie
redemande le ticket au serveur (même rendu). Écran fermé pendant la préparation : ni question ni ticket suivant.

## 2. Réédition des ventes

Nouveau menu **« Réédition des ventes »** (accueil, famille Ventes ; bouton imprimante de la Caisse) :

- ventes terminées du jour (« Aujourd'hui », « Hier », « Autre jour ») ; par défaut **celles de ce terminal** ;
  « Tous les postes » : toutes celles que le compte peut voir (droits du serveur inchangés : sans « Afficher les
  ventes de tous les utilisateurs », seulement les siennes) ;
- filtre Toutes / Comptant / Assurance / Carnet, recherche par **n° de ticket** ;
- **Réimprimer** : choix du nombre d'exemplaires, même rendu que le ticket d'origine (ticket dessiné par le serveur ;
  gabarit local reconstruit si le serveur n'a pas la route), pause « Ticket suivant » entre deux exemplaires.

« Ce terminal » : l'application note, quand le serveur ACCEPTE une clôture (comptant, assurance, carnet, dépôt,
file hors ligne), l'identifiant de la vente, son type (vno / vo) et la date — rien d'autre (ni client, ni montant,
ni produit), 45 jours au plus (`ventes_terminal_v1`). Une vente est aussi « de ce terminal » si le serveur a noté le
nom de cet appareil comme poste de saisie ou d'encaissement (en-tête `X-Poste`).

Route lue : `GET v1/ventestats` (« Ventes terminées » du web, `SalesStatsRessource.getAlls`, déployée). Aucune route
ne manque : la demande 69 n'est pas émise. Mention « DUPLICATA » : ni le serveur ni l'application ne la gèrent
aujourd'hui ; rien n'est ajouté.

## 3. Ticket imprimé : textes fins et pâles

**Constat** : sur le ticket assurance imprimé depuis l'image du serveur, les libellés de gauche (« Matricule
assuré », « Bénéficiaire », « Bon N° », « Part du client », organismes, « 1 ligne · 1 article », « Total ») sont fins
et pâles, comme tramés ; les gras passent bien.

**Cause** (mesurée sur un ticket fictif dessiné par le code du serveur) : tout est dessiné en noir, mais en « Arial
Narrow » de 8 points en 58 mm, lissé : à 203 dpi un trait vertical fait environ 1,5 point d'imprimante. Après la
conversion en noir et blanc (seuil 128, 4.15.1), 74 % des traits verticaux de ces textes n'ont plus qu'UN point de
large : une colonne d'un seul point chauffe mal sur la tête thermique (trait pâle, pointillé). En 80 mm, 6 % seulement.

**Correction** — réglage **« Contraste d'impression »** (Réglages › Impression : Normal / **Renforcé**, par défaut) :

- ticket du serveur (vente, prévente, borne, réédition ; PrestigePOS : imprimantes externes) : seuil 160 puis tout
  trait vertical d'un seul point doublé d'un point à droite (jamais si deux lettres se toucheraient) ; image à la
  largeur exacte de la tête (384 / 576 points), aucun redimensionnement, aucun gris ni tramage ; barres du
  code-barres et modules du QR inchangés (relus après conversion : Code 128 et QR décodés) ;
- gabarit local et borne (police de l'imprimante) : tout le texte en gras de l'imprimante (même largeur) ;
- Normal : rendu de la 5.3.0.

Le vrai remède est aussi côté serveur : demande 70 (textes d'au moins 2 points d'imprimante dans l'image 58 mm).

## Tests

`contraste_impression` (unitaires), `deuxieme_ticket` (écrans : ticket du serveur lent, Sunmi connecté en retard,
« Préparation du ticket… », écran fermé, Arrêter, mode test, ancienne interface, gabarit local), `ventes_assurance_ui`
(écran Assurance, ticket du serveur + Sunmi, 2 tickets), `reedition_ventes` (écrans), `reedition_ventes_e2e`
(application entière : 2 tickets puis réédition), `reedition_ventes_ergonomie` (320 / 360 dp, tablette, ×1,0 / ×1,3) ;
`remise_ticket_vo` mis à jour (il vérifiait l'ancienne règle « aucune copie ajoutée »). Outils hors CI :
`outils/captures_contraste_540`, `outils/captures_reedition_540`.
