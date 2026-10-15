# Réponses de Prestige Mobile aux questions du serveur — 15/10/2026

Réponse aux questions de la partie 3 de `REPONSE_SERVEUR_2026-10-15.md` adressées à l'**application Mobile**
(n° 12, 33, 34, 35). Fondé sur le code de Prestige Mobile 4.3.0+16 (`prestige_vente_app`).

Les décisions du **pharmacien** sur les autres questions (12 « valider avec écart », 17 D7, 24, 32, 38, 39, accord
pour la 34) sont dans **`DECISIONS_PHARMACIEN_2026-10-15.md`**.

## N° 12 — Reconnaître un appel mobile sur `add-lot` et `creerbl`

- **Oui, l'application peut envoyer un en-tête partout.** Elle utilise un petit nombre de clients HTTP, tous dans
  son code : client principal (`lib/api/dio_client.dart`, ventes, réception, retours, stock), client JSON des
  modules (`lib/serveur/client_prestige.dart`), RH (`lib/rh/rh_api.dart`, `lib/rh/mobile_api.dart`), synchro et
  surveillance hors ligne (`lib/horsligne/horsligne.dart`, `lib/horsligne/stock/stock_horsligne.dart`), images,
  ordonnances O4 / O5, support, diagnostic de la borne. Un en-tête ajouté à chacun est un changement simple.
- **Proposition** : `X-App: prestige-mobile/<version>` (ex. `prestige-mobile/4.3.0+16`), envoyé sur **toutes** les
  requêtes. PrestigePOS (même code, saveur `pos`) enverrait `X-App: prestigepos/<version>`.
- **Limites à connaître** : un en-tête se recopie facilement (ce n'est pas une preuve d'identité, seulement un
  aiguillage) ; les versions déjà installées ne l'enverront pas.
- Le pharmacien a décidé (voir `DECISIONS_PHARMACIEN_2026-10-15.md`) de **donner `P_BL_MOBILE_SCANNER` à tous les
  profils qui ont le menu BL** : l'en-tête n'est donc **pas nécessaire** pour ce droit. L'application ne l'envoie pas
  encore (4.3.0) ; elle l'ajoutera dès que le serveur confirme le nom, si une autre règle en a besoin.

## N° 33 — Réserve : route d'ajout de ligne, PDF REST

- **Forme proposée : convient.** `POST v1/suggestion-reserve/{id}/lignes {produitId, quantite}` avec
  `X-Client-Ref`, sur une suggestion `A_TRAITER` ou `EN_COURS` dont l'utilisateur détient le verrou.
  Précisions utiles à l'application :
  - `produitId` = `lg_FAMILLE_ID` (identifiant que l'application utilise déjà pour créer une suggestion :
    `items:[{lg_FAMILLE_ID, int_QTE}]`) ;
  - produit déjà présent dans la suggestion : **refus lisible** (`code:"DEJA_PRESENT"`), l'application proposera
    alors de modifier la quantité (route existante `PUT …/ligne/{detailId}/quantite`) ;
  - réponse : la ligne créée, au format des lignes de `PUT {id}/ouvrir` (l'application l'affiche sans relire) ;
  - suggestion d'un autre emplacement ou annulée : même refus que `ouvrir` (« introuvable » / lecture seule).
  - L'écran Réserve de l'application **n'a pas encore** de bouton « Ajouter un produit » : il sera ajouté quand la
    route existera (aucun appel d'ici là).
- **PDF REST : plus voulu.** L'application n'imprime ni ne partage de PDF de suggestion ; la demande peut être
  retirée.

## N° 34 — Fiche client agrégée : champs selon les écrans réels

Écrans réels de l'application (menu « Ordonnances des clients », onglet Fiche client,
`lib/fiche_client/`) et routes utilisées aujourd'hui :

| Écran | Champs affichés | Route actuelle |
|---|---|---|
| Recherche du client | nom, prénoms, téléphone, type de client, date de naissance, sexe | `GET ordonnance-client/clients` |
| Identité (lecture seule) | nom, prénoms, téléphone, date de naissance, âge, sexe, type | `GET ordonnance-client/client/{id}/dossier` (`client`) |
| Terrains et allergies (saisie si `modifier`) | terrains, allergies | `GET/POST …/client/{id}/dossier` |
| Paramètres de suivi et IMC | paramètre, valeur, unité, date, état, analyse, norme ; IMC | `…/dossier`, `…/mesures` |
| Consommation | CIP, nom, dernier achat, nombre d'achats, quantité, fréquence, montant, habitude, stock | `…/consommation` |

- **Les tiers payants et les ayants droit ne sont affichés nulle part** dans la fiche client de l'application, et
  l'identité y est en lecture seule : l'identité nécessaire est **déjà** dans `…/dossier`.
- **Conclusion** : la route agrégée n'est **pas nécessaire** aux écrans actuels ; la demande peut être retirée,
  ou ramenée à : « `…/dossier` renvoie aussi `adresse` (texte) », si le pharmacien veut l'afficher.
- Modification de l'identité : **non demandée** par les écrans (à reprendre seulement si le pharmacien la veut).
- Dépôt de fichiers en JSON : l'application **ne dépose aucun fichier** depuis la fiche client ; sans objet.
- Accord du pharmacien pour lire des colonnes nominatives : donné pour les essais (voir
  `DECISIONS_PHARMACIEN_2026-10-15.md`) ; côté application, rien n'est journalisé ni gardé sur le disque.

## N° 35 — Posologie usuelle d'un produit

- L'application n'appelle que `POST v1/posos/analyse` (et `GET v1/posos/status`, `GET v1/posos/droits` depuis la
  4.3.0). **Aucun écran n'affiche la posologie usuelle d'un produit** et l'application ne vise aucune route Posos
  dédiée.
- **Demande retirée.** `GET v1/posos/historique` et `POST v1/posos/interaction` ne sont pas encore utilisés par
  l'application (pas d'écran) ; ils sont notés pour une version suivante.

## Ce que l'application a intégré (4.3.0, avec repli sur un serveur ancien)

| N° | Intégration |
|---|---|
| 4 | `GET v1/reserve/droits` : décide du menu Réserve quand il répond |
| 5 | `GET v1/posos/droits` : menu Analyse posologie masqué si `analyser` est faux |
| 6 | sans objet : l'application n'annule pas de vente clôturée (elle ne supprime qu'une vente non clôturée de dépôt / proforma par `ventestats/remove`) |
| 10 | `role.libelle` de `user/auth` affiché ; `user/droits` pas encore utilisé (les routes de droits des modules suffisent) |
| 11 | message « Activez la licence après connexion d'un administrateur » ; session d'un administrateur gardée pour l'activation |
| 18 | `X-Client-Ref` sur `add-lot` et `retourfournisseur/add-item` envoyés hors ligne (jamais `clientEventId` dans le corps) |
| 28 | suggestion annulée en lecture seule, d'un autre emplacement « introuvable » : déjà géré, testé |
| 31 | `id` et `controle` dans `POST rh/pointages`, photo envoyée par `POST rh/pointages/{id}/photo` |
| 36 | l'application n'a pas encore les écrans D10–D16 (paramètres de réception, lots avec auteur, péremptions courtes, anomalies, présence) ni l'envoi du n° de série (D18) : à construire dans une version suivante ; les refus du serveur (D2, D18 « Boîte déjà scannée ») sont déjà affichés tels quels |
| 37 | sans objet : Prestige Mobile ne verse pas de collecte d'inventaire (application Inventaire) |
| 403 | `{interdit:true, msg}` : message du serveur affiché, jamais une déconnexion |
