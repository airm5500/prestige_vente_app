# Réserve, Analyse posologie et Fiche client : routes utilisées, choix et demandes au serveur

Ce document porte sur trois fonctions ajoutées à Prestige Mobile :

- le menu **Réserve** ;
- l'**Analyse posologie** (Posos) ;
- l'onglet **Fiche client** du menu « Ordonnances des clients ».

Il s'appuie sur le serveur `airm5500/prestige`, branche `claude/new-session-xm8ptu`, lu sans aucune modification. La **section 5** liste les demandes à transmettre à la session serveur.

## 1. Règles communes de l'application

- **Session** : l'application utilise le même cookie `JSESSIONID` que le reste de l'appli (pot à cookies partagé de `DioClient`). Ces routes n'acceptent pas le jeton Bearer.
- **Client HTTP dédié** : `lib/serveur/client_prestige.dart`.
  - Il n'a **aucun journal** (pas de `LogInterceptor`), car les fiches clients contiennent des données de santé.
  - Délai de connexion : 8 s. Délai de réponse : 25 s.
- **Types d'erreur** : l'écran affiche un message différent pour chaque cause.

  | Erreur | Cause |
  |---|---|
  | `ServeurInjoignable` | Réseau ou délai dépassé |
  | `SessionExpiree` | HTTP 401, ou HTTP 200 avec le message « Veuillez vous connecter » |
  | `RefusMetier` | HTTP 200 avec `success:false` ; le message du serveur est affiché tel quel, et le `code` est conservé |
  | `ErreurHttp` | 404 (fonction absente de ce serveur) ou 5xx |
  | `ReponseIllisible` | Page HTML ou JSON tronqué |

- **Session expirée** : l'écran propose « Se reconnecter », c'est-à-dire le même parcours que « Se déconnecter » de l'accueil. Le crochet statique `ClientPrestige.surSessionExpiree` est appelé à chaque 401, pour être branché sur l'intercepteur 401 global de l'application lors de la fusion.
- **Écrans** : aucun chargement sans fin. Chaque erreur a un bouton « Réessayer » ou « Se reconnecter ».
- **Lecture tolérante** (`lib/serveur/json_tolerant.dart`) : un champ absent, nul ou d'un type inattendu (nombre en texte, booléen en 0/1) ne fait jamais planter l'écran.
- **Données patient** :
  - elles restent en mémoire le temps de l'écran ;
  - elles ne sont jamais journalisées ni écrites sur le disque ;
  - les tests n'utilisent que des données fictives.

## 2. Droits : comment l'application les détermine

### 2.1 Ce que renvoie le serveur

`POST /user/auth` ne renvoie **pas** la liste des privilèges. Il renvoie seulement `privileges:[canUpdatePrice, showStock]` et `xtypeuser`. La liste complète reste en session (`AccountResource.java:127`).

### 2.2 Ce que fait l'écran web

Le menu web affiche les sous-menus selon `t_sous_menu.P_KEY`, lu par la vue SQL `v_getallsousmenubyconnecteduser`. Celle-ci n'est exposée que par la JSP `general/home/view/sousmenus.jsp`, qui renvoie du HTML et attend un identifiant de menu. Elle n'est donc pas utilisable par l'application.

Le privilège du sous-menu `reservemanager` ne figure dans aucune migration lisible : il est dans les données plus anciennes de la base.

### 2.3 Règles appliquées par l'application

| Menu | Règle | Source |
|---|---|---|
| **Réserve** | Administrateur **ou** droit dédié (décision du pharmacien) | Voir ci-dessous |
| **Ordonnances des clients** (Fiche client) | Visible avec `consulter` (`P_ORDONNANCE_CLIENT`). Saisie (allergies, terrains, mesures) seulement avec `modifier` (`P_ORDONNANCE_CLIENT_MAJ`) | `GET v1/ordonnance-client/droits` → `{success, consulter, modifier}`. Le serveur revérifie chaque route |
| **Analyse posologie** | Visible dès qu'un utilisateur est identifié (tous les comptes connectés) | Le serveur ne vérifie pas `P_SM_POSOS`, et aucune route ne l'expose |

**Détail de la règle Réserve**

- Administrateur signifie :
  - le compte `admin` de l'application (`AuthProvider.isAdmin`) ;
  - **ou** un profil administrateur ou super-administrateur côté serveur, lu par `GET v1/roles/est-admin` → `{authorize}` (`RoleServiceImpl.isAdmin`).
- Droit dédié : **aucun privilège « traiter la réserve » n'existe côté serveur**. Le seul privilège lié à la réserve est `P_ANNULER_MOUVEMENT_RESERVE`, réservé à l'annulation. L'application interroge donc `GET v1/reserve/droits` → `{success, traiter}`, une route **demandée au serveur** (section 5). Aujourd'hui elle répond 404, ce qui est ignoré.
- Conséquence : **tant que cette route n'existe pas, le menu Réserve est réservé aux administrateurs.**

**Lecture et affichage des droits**

- Les droits sont lus par `lib/droits/droits_modules.dart` (`DroitsModules`) :
  - à l'ouverture et à l'actualisation de l'accueil, au plus toutes les 5 minutes ;
  - ils sont oubliés à chaque changement d'utilisateur ;
  - si le serveur est injoignable, l'application garde les droits déjà connus du même utilisateur.
- Les trois nouveaux menus sont dans une liste séparée (`menusSousDroits`), ajoutée après les 23 menus d'origine. Le catalogue d'origine (`accueilMenus`, `accueilMenuById`) est inchangé.
- Un menu non autorisé (`AccueilMenu.autorise`) n'apparaît ni dans l'accueil ni dans la recherche de menus.
- Les menus soumis à un droit ne sont pas proposés dans « Organiser l'accueil » (ni ordre, ni masquage, ni favoris). Quand le compte y a droit, ils s'affichent à la fin de leur famille.

## 3. Routes utilisées

### 3.1 Réserve (`lib/reserve/`)

| Route | Usage |
|---|---|
| `GET v1/reserve/articles?search_value=&str_TYPE_TRANSACTION=&start=&limit=` | Stocks rayon et réserve d'un produit choisi par la recherche ou le scan de l'appli (correspondance exacte par `lg_FAMILLE_ID`) ; « Produits proposés » (`REAPPRO` / `REASSORT_RAYON`) |
| `GET v1/suggestion-reserve/motifs?categorie=` | Motifs (tableau nu). Le motif est obligatoire |
| `GET v1/suggestion-reserve/en-attente?limit=200` | Suggestions `A_TRAITER` et `EN_COURS` **de l'emplacement de l'utilisateur**. Utilisée à la place de `liste`, qui ne filtre pas l'emplacement. Le tri par catégorie et par origine se fait côté application |
| `POST v1/suggestion-reserve/creer` | Création du réappro manuel. **Non idempotente** |
| `PUT v1/suggestion-reserve/{id}/ouvrir` | Détail et verrou de 20 min. Relu juste avant « Traiter » |
| `PUT v1/suggestion-reserve/ligne/{detailId}/quantite` | Quantité retenue (> 0) ; aucun stock ne bouge |
| `DELETE v1/suggestion-reserve/ligne/{detailId}?motif=` | Retirer une ligne (motif « Retirée depuis le mobile ») |
| `PUT v1/suggestion-reserve/{id}/traiter` | **Déplace le stock**, après confirmation explicite. Renvoie le compte rendu |
| `PUT v1/suggestion-reserve/{id}/reessayer` | Rejoue les lignes en échec |
| `PUT v1/suggestion-reserve/{id}/liberer` | En quittant l'écran, si le verrou a été pris |
| `GET v1/roles/est-admin` | Droits (section 2) |

Routes **non utilisées**, par choix :

- `assort` et `reassort` (unitaires et par lot) : décision du pharmacien, aucun mouvement direct ;
- annulation, contrôle, inventaire, import de fichier, impression.

### 3.2 Analyse posologie (`lib/posos/`)

| Route | Usage |
|---|---|
| `GET v1/posos/status` | Détecte le mode démonstration (`mode` = `demonstration`, ou `configuree:false`) |
| `POST v1/posos/analyse` forme A `{produits:[{nom, cip, quantite, posologie}], contexte?}` | Écran autonome (menu « Analyse posologie ») : produits choisis par la recherche ou le scan de l'appli |
| `POST v1/posos/analyse` forme B `{venteId, contexte?}` | Mode « Vente ou ordonnance » de l'écran, comme le web : la référence de la vente en cours (affichée sur l'écran Vente), une prévente en cours choisie dans la liste (`GET ventestats/preventes`, déjà utilisé par l'appli) ou un N° d'ordonnance client. Le serveur relit les produits enregistrés. L'écran accepte aussi `PososScreen(venteId: …)` pour un futur bouton dans l'écran Vente |

### 3.3 Fiche client (`lib/fiche_client/`)

| Route | Usage |
|---|---|
| `GET v1/ordonnance-client/droits` | Consultation ou saisie |
| `GET v1/ordonnance-client/clients?query=&start=0&limit=30` | Recherche par nom ou téléphone (2 caractères au moins, après 400 ms sans frappe) |
| `GET v1/ordonnance-client/client/{id}/dossier` | Identité (lecture seule), terrains, allergies, derniers paramètres, IMC |
| `POST v1/ordonnance-client/client/{id}/dossier {allergies, terrains}` | Les terrains sont **remplacés** : l'appli renvoie la liste complète, y compris les terrains désactivés déjà présents |
| `GET v1/ordonnance-client/terrains`, `GET …/parametres` | Référentiels (actifs). Les bornes de saisie viennent du paramètre |
| `GET v1/ordonnance-client/client/{id}/mesures?parametreId=` | Historique d'un paramètre |
| `POST v1/ordonnance-client/client/{id}/mesures` | Nouvelle mesure. **Non idempotente** |
| `GET v1/ordonnance-client/client/{id}/consommation` | Consommation sur 12 mois, chargée à la demande |

## 4. Choix faits dans l'application

### 4.1 Réserve

- **Parcours « suggestion puis traiter »**, comme le web :
  1. préparer un panier ;
  2. choisir un motif ;
  3. créer la suggestion ;
  4. ouvrir l'écran de traitement ;
  5. ajuster les quantités ligne par ligne ;
  6. « Traiter », avec confirmation qui indique le sens, le nombre de boîtes et de lignes, et les lignes qui dépassent le stock actuel ;
  7. lire le compte rendu : lignes déplacées, refusées avec leur raison, non traitées ;
  8. « Réessayer les échecs » si besoin ;
  9. « Libérer » le verrou en quittant.
- **Vocabulaire** : l'écran n'affiche jamais RESERVE ou RAYON seuls. Il affiche le sens physique :
  - **Rayon → Réserve** pour la catégorie `RESERVE`, « Ranger en réserve » ;
  - **Réserve → Rayon** pour la catégorie `RAYON`, « Regarnir le rayon ».

  Chaque ligne montre le stock rayon et le stock réserve, et met en avant le stock source.
- **Création non idempotente**, trois protections :
  - bouton bloqué pendant l'envoi, donc un seul `POST` même en cas de double appui ;
  - les suggestions **manuelles** du même sens déjà en attente sur l'emplacement sont proposées à la reprise, et créer quand même demande une confirmation ;
  - un délai dépassé **après l'envoi** est signalé comme « résultat incertain » : jamais de renvoi automatique, la liste en attente est relue.
- **Pas d'ajout de produit** à une suggestion existante (le serveur n'a pas de route pour cela) : on la reprend telle quelle, ou on en crée une autre.
- **Verrou** :
  - « occupée par un autre » donne une consultation seule, avec le message du serveur et un bouton « Réessayer » ;
  - un `SUGGESTION_OCCUPEE` reçu pendant une écriture repasse l'écran en consultation ;
  - la suggestion est relue juste avant « Traiter ».
- **Quantités** :
  - entier strictement positif, chiffres seulement, au plus 99 999 ;
  - bornées par le stock **source** (rayon pour Rayon → Réserve, réserve pour Réserve → Rayon) ;
  - toute saisie invalide est refusée avec un message ;
  - pour mettre une ligne à 0, on utilise « Retirer la ligne », avec confirmation.
- **Produits non suivis en réserve** (`bool_RESERVE=0`) : refusés à l'ajout, avec un message. Le serveur les accepterait, puis les ferait échouer avec `CONFIG_STOCK_INCOMPLETE`.

### 4.2 Analyse posologie

- Les alertes sont classées de la plus grave à la moins grave :

  | Niveau | Couleur |
  |---|---|
  | Contre-indication | Rouge |
  | Majeure ou déconseillée | Orange |
  | À vérifier | Orange |
  | Précaution | Bleu |
  | À prendre en compte | Gris |
  | Information | Gris |

- Une gravité inconnue n'est **jamais minimisée** : elle est classée « À vérifier », ou « Majeure » si le serveur l'indique, comme `PososResultat.estMajeure`.
- **Mode démonstration** : un bandeau permanent affiche « Mode démonstration — résultats non réels », avec l'avertissement du serveur.
- **Avertissement permanent** : « Aide à la dispensation : ces alertes ne remplacent ni l'avis du pharmacien ni celui du prescripteur. »
- Les produits non reconnus sont listés.
- Le contexte du patient est facultatif : âge de 0 à 120 ans, poids de 1 à 300 kg (entier), sexe, grossesse et allaitement (masqués pour un homme), insuffisance rénale ou hépatique. Rien n'est conservé.

### 4.3 Fiche client

- L'identité est en lecture seule.
- **Contrôles de saisie** :
  - nombre lisible avec virgule ou point ;
  - pas plus de décimales que le paramètre ;
  - bornes : intersection des bornes Prestige et de bornes plausibles (glycémie de 0,2 à 6 g/L, tension de 40 à 260 mmHg, fréquence cardiaque de 20 à 250 bpm, poids de 0,5 à 350 kg, taille de 30 à 250 cm, température de 30 à 45 °C, SpO2 de 50 à 100 %) ;
  - l'unité et la plage s'affichent sous le champ ;
  - tension : au moins un bras, systolique **et** diastolique, diastolique inférieure à la systolique ;
  - date ni future ni antérieure à 2000 ;
  - commentaire de 200 caractères au plus, allergies de 2 000 au plus.
- **Mesure** : un seul envoi par saisie. Un délai dépassé après l'envoi signale que la mesure a peut-être été enregistrée et invite à vérifier l'historique avant de ressaisir.

## 5. Manques et risques côté serveur, à transmettre à la session serveur

**Réserve**

1. **Aucun contrôle de privilège** sur `v1/reserve/*` (`assort`, `reassort`, lots) ni sur `v1/suggestion-reserve/*` (`creer`, `quantite`, `traiter`, `reessayer`), seule la session est vérifiée. Le masquage du menu dans l'application n'est **pas** une sécurité : un compte connecté peut appeler ces routes directement.

   **Demande** : créer un privilège dédié, par exemple `P_TRAITER_RESERVE`, vérifié sur ces routes. L'exposer par `GET v1/reserve/droits` → `{success:true, traiter:bool}`, que l'application lit déjà ; aujourd'hui la réponse est 404.
2. **`creer` et `creer-depuis-recherche` ne sont pas idempotents**, pas plus que `assort` et `reassort` : deux envois créent deux suggestions ou deux mouvements.

   **Demande** : un en-tête `X-Client-Ref` ou un champ `requestId`, avec relecture par clé, comme H4 pour les ventes.
3. **`liste` et `GET {id}` ne filtrent pas par emplacement** : un mobile multi-sites verrait les suggestions des autres. L'application utilise `en-attente`, qui filtre.

   **Demande** : ajouter le filtre d'emplacement à `liste`, `{id}` et `ouvrir`.
4. **Aucune route pour ajouter un produit** à une suggestion existante : il faut en recréer une.
5. **`ouvrir` ne traite pas `ANNULEE` comme close** : il prend un verrou inutile.
6. **Le privilège du sous-menu `reservemanager`** n'est pas dans les migrations. Il faut le documenter, ou le remplacer par le privilège de la demande 1.
7. **L'impression d'une suggestion** passe par une JSP (`ws_generate_pdf_suggestion.jsp`) : une route REST `v1/suggestion-reserve/{id}/pdf` serait plus propre. Non utilisée par l'application.

**Posos**

8. **`P_SM_POSOS` n'est pas vérifié** sur `v1/posos/*`, et aucune route ne l'expose. Le menu mobile est donc ouvert à tous les comptes connectés, alors que chaque appel consomme l'API Posos.

   **Demande** : contrôler le privilège côté serveur et l'exposer, par exemple par `GET v1/posos/droits`.
9. Il n'existe ni historique ni trace des analyses, ni route unitaire (posologie usuelle, interaction entre deux produits).

**Fiche client**

10. **`POST client/{id}/mesures` n'est pas idempotent**, pas plus que `POST enregistrer` : un double envoi crée un doublon.

    **Demande** : une clé d'idempotence, ou un refus d'une mesure identique (même paramètre, même valeur, même minute) sur une courte fenêtre.
11. Il manque une route agrégée pour l'identité, les tiers payants et les ayants droit sous `P_ORDONNANCE_CLIENT(_MAJ)`. Il manque aussi la modification de l'identité sous `P_ORDONNANCE_CLIENT_MAJ`.
12. Les dépôts de fichiers (pièces, scans) répondent en `text/html` : une variante `application/json` est souhaitée.

**Général**

13. **La liste des privilèges de l'utilisateur n'est pas exposée.**

    **Demande** : une route `GET v1/mobile/droits` (ou `v1/user/privileges`) qui renvoie les codes utiles au mobile. Elle éviterait une route « droits » par module.

## 6. Notes de fusion (côté application)

**Fichiers existants modifiés**, au strict minimum :

- `lib/accueil/accueil_menus.dart` :
  - une liste séparée `menusSousDroits` de 3 menus : `posos` et `ordonnances_clients` dans la famille Ventes, `reserve` dans la famille Stock ;
  - un champ facultatif `autorise` ;
  - le filtre de `orderedMenus` et de `menusByFamille`. Les 23 menus d'origine ne changent pas.
- `lib/accueil/accueil_screen.dart` : l'écoute de `DroitsModules` et la relecture des droits dans `_actualiser`. Pas en test : `serverCheck` est fourni.
- `.github/workflows/build-apk.yml` : les 5 nouveaux fichiers de test.

**Lors de la fusion**

- Brancher `ClientPrestige.surSessionExpiree` sur l'intercepteur 401 global de l'application.
- L'**accueil d'origine** (`lib/screens/home/home_screen.dart`, interface « ancienne ») n'a pas reçu ces menus. Ils ne sont accessibles que depuis le nouvel accueil.
- **Écran Vente** : aucun bouton n'y a été ajouté. Un bouton dans la barre décale le rendu de référence à 360 px (`test/responsive_test.dart`). L'analyse d'une vente passe par le mode « Vente ou ordonnance » de l'écran Analyse posologie. Pour ajouter un accès direct depuis la vente, il faudra mettre à jour le rendu de référence, par exemple dans le cadre de la refonte, puis appeler `PososScreen(venteId: c.venteId, referenceVente: c.summary.reference, produitsInitiaux: …)`.
- Les nouveaux menus ne peuvent pas être mis en favori : `AccueilFavoris.nettoyer` et l'organisation utilisent `accueilMenuById`, limité aux 23 menus d'origine. Ce point est à revoir avec la session qui gère les favoris.
- **Remarque hors périmètre** : le client Dio global (`lib/api/dio_client.dart`) a un `LogInterceptor(responseBody: true)` qui journalise **tous** les corps de réponse des autres routes, y compris celles qui contiennent des noms de clients. Les nouveaux modules ne l'utilisent pas.

## 7. Questions ouvertes pour le pharmacien

1. **Menu Réserve** : faut-il, en attendant un privilège dédié côté serveur, l'ouvrir aussi aux comptes qui ont `P_ANNULER_MOUVEMENT_RESERVE` (lisible par `GET v1/reserve/peut-annuler`) ? Aujourd'hui, le menu est réservé aux administrateurs.
2. **Accès à l'analyse depuis l'écran Vente** : faut-il un bouton direct dans la barre de la vente ? Il modifie le rendu validé à 360 px. Aujourd'hui, on saisit ou on choisit la référence dans l'écran Analyse posologie.
3. **Analyse posologie** : le menu doit-il être réservé, par exemple aux administrateurs et pharmaciens, en attendant le contrôle `P_SM_POSOS` ? Aujourd'hui, il est ouvert à tous les comptes.
4. **Ordonnances des clients** : seul l'onglet « Fiche client » existe dans l'application. Faut-il ajouter les autres onglets du web (Historique, Analyse des ordonnances) ?
5. **Bornes plausibles** des mesures (section 4.3) : sont-elles à valider ou à ajuster, par exemple le poids des nourrissons ou la température ?
