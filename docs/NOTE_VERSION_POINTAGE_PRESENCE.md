# Note de version : Pointage présence (téléphone de l'employé)

Côté application uniquement. Le serveur Prestige n'a pas été modifié.

## Ce qui a changé

- **Menu** : l'entrée « Pointage RH (Prestige) » s'appelle maintenant **« Pointage présence »** (famille Équipe), dans
  le nouvel accueil comme dans l'accueil d'origine. L'identifiant interne `pointage_rh` ne change pas, donc les
  favoris, l'ordre et les menus masqués sont conservés. À l'intérieur, on trouve deux voies :
  - **« Mon pointage »** : l'employé pointe avec son propre téléphone ;
  - **« Terminal de pointage »** : un appareil commun lit le badge, le NFC ou l'empreinte.

  Le « Pointage BL » (contrôle des quantités en stock) garde son libellé et son icône. Le menu « Pointage » local
  (empreinte ou PIN) est devenu **« Pointage local (non envoyé à Prestige) »** et il est **masqué par défaut** :
  voir la section « Pourquoi mon pointage n'apparaît pas dans Prestige ? ».
- **Écran « Mon pointage »** : **deux gros boutons** remplacent l'ancien bouton unique et son lien « Pointer plutôt… ».
  Ils sont côte à côte, ou l'un sous l'autre si l'écran est trop étroit :
  - **Arrivée** (vert) envoie `ENTREE` et **Départ** (rouge doux) envoie `SORTIE` ;
  - un appui ouvre directement le scan du QR code si l'officine l'exige, sinon le pointage part tout de suite.
    Le pointage se fait donc en **deux gestes**, sans confirmation intermédiaire ;
  - le bouton qui correspond à l'inverse du dernier pointage porte une bordure et un badge « suggéré ». Ce n'est
    qu'une indication : l'autre bouton reste utilisable ;
  - on garde la saisie manuelle du code en secours (le code est saisi, puis on choisit Arrivée ou Départ), le
    résultat affiché en grand (vert : accepté, rouge : refus du serveur tel quel, orange : « Vous avez déjà pointé
    à HH:mm »), l'historique rechargé après chaque pointage, le nom et le matricule de l'employé en en-tête, et la
    déconnexion qui efface le jeton du téléphone.
- **Position** :
  - si l'officine **exige** le GPS, rien ne change : l'autorisation est demandée et les messages restent les mêmes ;
  - si le GPS **n'est pas exigé**, la position (latitude, longitude, précision) est envoyée **seulement si
    l'autorisation de localisation est déjà accordée**. L'application ne la demande jamais. La lecture est limitée
    à environ 5 s ; en cas d'échec, le pointage part sans position et n'est jamais bloqué.
  - Le contenu du QR code, la position et les réponses du serveur ne sont jamais écrits dans les journaux.

## Comment l'essayer

Prérequis côté Prestige (Paramètres généraux, sur un **serveur de test**) :

| Réglage | Valeur pour l'essai |
|---|---|
| `KEY_MOBILE_ACTIF` | 1 (les téléphones peuvent se connecter) |
| `KEY_RH_MOBILE_POINTAGE` | 1 (le pointage par téléphone est autorisé) |
| `KEY_RH_MOBILE_QR` | 1 pour exiger le QR code (0 : sans QR) |
| `KEY_RH_MOBILE_GPS` | 0 (position facultative) ou 1 (position exigée : renseigner aussi `KEY_RH_MOBILE_LATITUDE`, `KEY_RH_MOBILE_LONGITUDE` et `KEY_RH_MOBILE_RAYON_M`) |

- Le compte utilisé doit être **rattaché à un employé actif** (menu RH › Employés).
- Pour afficher le QR code, qui change chaque minute, ouvrir Prestige › menu RH › onglet **« Pointage mobile »** sur
  un écran de la pharmacie.

Dans l'application : Accueil › Équipe › **Pointage présence** › **Mon pointage**. Se connecter avec ses identifiants
Prestige, puis appuyer sur **Arrivée** et scanner le QR code. Le pointage apparaît dans Prestige (RH › Présence du
jour).

## Correspondance avec les tests du cahier (§ 6)

Fichier des tests automatiques : `test/rh_pointage_test.dart`. Il fait partie de la suite exécutée par
`.github/workflows/build-apk.yml`.

| § 6 | Cas | Test automatique | À faire à la main (serveur de test) |
|---|---|---|---|
| 1 | Mauvais mot de passe → message du serveur | **Oui, test d'intégration** « connexion avec un mauvais mot de passe » sur `http://localhost:8080/prestige/api/v1` (ou `PRESTIGE_TEST_URL`, compte `PRESTIGE_TEST_LOGIN`, `admin` par défaut). Il est **sauté** si le serveur est injoignable ou si l'API des téléphones est absente ou désactivée. Il ne crée aucune donnée. | Oui, si le test d'intégration a été sauté |
| 2 | Compte sans employé → pas d'écran de pointage | Oui (« compte sans employé : pas de pointage ») | Contrôle visuel |
| 3 | QR valable, GPS non exigé → « Entrée enregistrée » | Oui côté application, avec un faux serveur : sens envoyé, code brut, résultat en grand, historique rechargé, deux gestes | **Oui** : vérifier que le pointage apparaît dans Prestige (RH › Présence du jour) |
| 4 | Deuxième appui en moins de deux minutes → refus | Oui : le refus « moins de deux minutes » s'affiche en orange « Vous avez déjà pointé à HH:mm » | Oui (règle appliquée par le serveur) |
| 5 | QR de plus de deux minutes → « invalide ou expiré » | Oui : le refus du serveur est affiché tel quel ; un autre code scanné n'est pas envoyé | **Oui** (l'expiration est décidée par le serveur) |
| 6 | GPS exigé : localisation refusée → message ; trop loin → « Vous êtes à N m » ; sur place → accepté | Oui : localisation refusée → message et rien n'est envoyé ; position acceptée → envoyée ; tout refus du serveur est affiché tel quel. L'autorisation n'est demandée que si le GPS est exigé. | **Oui** : vraie distance, sur place et loin |
| 7 | Téléphone retiré dans Prestige → 401 → retour à la connexion | Oui (« 401 pendant le pointage → retour à la connexion », jeton effacé) | Oui (retirer le téléphone dans RH › Pointage mobile) |
| 8 | Jeton expiré → retour à la connexion | Oui (jeton expiré localement et 401 `expire`) | Oui (`KEY_MOBILE_JETON_HEURES = 1`, puis attendre) |
| 9 | Pointage BL Stock et autres écrans inchangés | Oui : toute la suite du workflow passe, dont `presentation_bl_control_test`, `accueil_test` et `responsive_test`. Les identifiants de menus sont inchangés. | Tour rapide des menus « Pointage BL » et « Pointage » |

Autres tests automatiques ajoutés : boutons Arrivée/Départ et sens envoyé, bouton suggéré non imposé, aucune boîte
de confirmation, position envoyée seulement si l'autorisation est déjà accordée (jamais demandée, délai de 5 s),
saisie manuelle du code, déconnexion qui efface le jeton, absence de QR, de position et de réponse dans les
journaux, mise en page à 360 px et sur tablette sans débordement.

## Pourquoi mon pointage n'apparaît pas dans Prestige ?

Retour client : « je me suis connecté en admin, j'ai créé un employé sur Prestige et je l'ai rattaché à mon compte ;
j'ai pointé mais je ne vois pas mon pointage dans Prestige ».

### Ce qui a été vérifié (serveur de test, scénario du client rejoué puis nettoyé)

- Employé créé dans Prestige et rattaché au compte `admin`, puis pointage par le **terminal** (`POST v1/rh/pointages`,
  enregistré `source = MANUEL`, motif « Badge terminal … ») et par le **téléphone** (`POST v1/mobile/pointages`,
  `source = MOBILE`, heure du serveur) : les deux lignes sont dans `t_pointage` **et** dans
  `GET v1/rh/presence?jour=<aujourd'hui>`, c'est-à-dire dans Prestige › RH › **Présence du jour**. Les deux voies
  fonctionnent donc. Le test automatique « Intégration : pointages visibles dans « Présence du jour » » rejoue ce
  scénario sur le serveur de test (il est sauté si le serveur ou la base sont injoignables) et supprime tout ensuite.
- **Cause la plus probable : le menu « Pointage » LOCAL.** Il était rangé dans la même famille « Équipe », juste
  avant « Pointage présence », avec l'icône d'empreinte et le simple libellé « Pointage ». Ce module (empreinte / PIN
  sur l'appareil) enregistre les pointages **dans l'appareil uniquement** (aucun envoi, aucune synchronisation :
  le champ « envoyé » n'est jamais rempli). Un pointage fait là n'arrive jamais dans Prestige.

### Ce qui change dans l'application

- **Pointage local** : libellé **« Pointage local (non envoyé à Prestige) »**, bandeau orange « Ces pointages restent
  sur cet appareil… » avec un bouton « Ouvrir « Pointage présence » », message après pointage « … (sur cet appareil,
  non envoyé à Prestige) ». Le menu est **masqué par défaut** ; un administrateur peut le réafficher dans
  Paramètres › Équipe (interrupteur « Afficher le menu « Pointage local » à l'accueil »). **Aucune donnée n'est
  supprimée** : employés et pointages locaux restent sur l'appareil, consultables dans Paramètres › Équipe ›
  Rapport et analyse, avec un nouvel **export CSV** (copié dans le presse-papiers, colonne « Envoyé à Prestige : non »)
  pour les ressaisir au besoin dans Prestige (RH › Présence du jour › Pointage manuel).

  Choix retenu : ne pas faire envoyer ces pointages à Prestige. Ce module a ses propres employés (sans lien sûr avec
  les employés Prestige), des types « début / fin de pause » que Prestige ne connaît pas, et le « Terminal de
  pointage » fait déjà la même chose (empreinte, badge, NFC) en envoyant à Prestige. Un pont risquait des doublons ou
  des pointages attribués au mauvais employé ; le renommer, le masquer et garder ses données est sans risque.
- **Pointage présence = capture uniquement pour l'employé** : « Mon pointage » et « Terminal de pointage ».
  « Présences du jour » et la gestion des empreintes ne sont proposées qu'au **gestionnaire** : compte `admin` de
  l'application ou compte ayant le droit RH `P_SM_RH`. Pour les autres, ces entrées n'apparaissent plus du tout.
- **Chaque pointage dit où il en est** :
  - terminal : « Envoyé à Prestige ✓ » (vert), « En attente d'envoi (hors ligne) » (orange, jamais présenté comme
    envoyé) ou « Refusé par Prestige : <message du serveur> » (rouge) ;
  - téléphone : sous le résultat, « Envoyé à Prestige ✓ » ou « Refusé par Prestige : ce pointage n'est pas
    enregistré ».
- **Session Prestige expirée sur le terminal** (réponse 401 « Veuillez vous connecter », par exemple après une nuit
  d'inactivité) : le pointage n'est plus refusé, il est **gardé en attente** et envoyé après reconnexion de
  l'application (avec la confirmation habituelle). L'envoi de la file s'arrête au premier 401 sans rien marquer
  « refusé ».
- **Badge inconnu en ligne** : le terminal relit la liste des employés de Prestige (au plus une fois par 30 s) avant
  de répondre « Badge non reconnu » : un employé créé ou un badge ajouté après l'ouverture du terminal est reconnu.
- **Téléphone connecté avec un autre compte** : si « Mon pointage » est connecté à un autre compte que celui de
  l'application (jeton de 12 h gardé sur le téléphone), un bandeau l'indique : les pointages iraient à cet autre
  employé. Bouton de déconnexion en haut à droite.

### Liste de contrôle pour le client

1. **Quel menu a servi ?** Le pointage doit être fait dans Accueil › Équipe › **Pointage présence** (« Mon
   pointage » ou « Terminal de pointage »). L'ancien menu « Pointage » (empreinte / PIN) n'envoie rien à Prestige ;
   ses pointages peuvent être exportés (Paramètres › Équipe › Rapport et analyse › Exporter) et ressaisis.
2. **Le message après le pointage** : « Envoyé à Prestige ✓ » = enregistré. « En attente d'envoi » = pas encore dans
   Prestige : rouvrir Pointage présence en ligne et confirmer l'envoi (« Envoyer la sélection » ; « Plus tard » laisse
   les pointages en attente). « Refusé par Prestige » = rien n'est enregistré, lire le message.
3. **Rafraîchir l'écran de Prestige** : l'onglet RH › « Présence du jour » ne se recharge pas tout seul. Changer de
   jour (◀ ▶) ou d'onglet puis revenir, ou recharger la page. Vérifier aussi la **date** affichée.
4. **Fiche de l'employé dans Prestige** (RH › Employés) : statut **ACTIF**, compte utilisateur **rattaché** (le bon
   login), **date d'entrée** vide ou antérieure à aujourd'hui (avec une date d'entrée future, l'employé n'apparaît
   pas dans « Présence du jour » même si ses pointages sont enregistrés), date de sortie vide ou future.
5. **Pointage par téléphone** (« Mon pointage ») : Paramètres généraux `KEY_MOBILE_ACTIF = 1` et
   `KEY_RH_MOBILE_POINTAGE = 1` ; l'en-tête de l'écran doit afficher **le nom et le matricule** de l'employé. Sinon :
   « rattaché à aucun employé actif » (point 4) ou « désactivé par l'officine » (paramètre à 0). Si le bandeau
   « connecté au compte « X » » s'affiche, déconnecter le téléphone et se reconnecter avec le bon compte.
6. **Terminal de pointage** : le compte connecté à l'application doit avoir le droit **`P_SM_RH`** (sinon l'entrée
   est grisée avec l'explication) ; l'employé doit avoir un **badge** dans sa fiche Prestige (ou une empreinte
   enregistrée sur le terminal) ; **l'heure du terminal** doit être juste : elle est envoyée telle quelle (un
   terminal en avance de plus de 5 min est refusé « dans le futur », un terminal à la mauvaise date enregistre le
   pointage un autre jour).
7. **Version du serveur** : si l'écran dit « n'existe pas sur cette version du serveur Prestige », le serveur de
   production n'a pas encore les routes `v1/rh` / `v1/mobile` (réponse 404) : le mettre à jour. L'application le dit
   clairement et ne propose pas la voie concernée.
8. **Double pointage** : moins de deux minutes après un pointage, le téléphone répond « Vous avez déjà pointé à
   HH:mm » et le terminal « vous avez déjà pointé » : c'est normal, le premier pointage est enregistré.
