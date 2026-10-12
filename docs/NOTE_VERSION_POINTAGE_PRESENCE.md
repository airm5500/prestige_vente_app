# Note de version : Pointage présence (téléphone de l'employé)

Côté application uniquement. Le serveur Prestige n'a pas été modifié.

## Ce qui a changé

- **Menu** : l'entrée « Pointage RH (Prestige) » s'appelle maintenant **« Pointage présence »** (famille Équipe), dans
  le nouvel accueil comme dans l'accueil d'origine. L'identifiant interne `pointage_rh` ne change pas, donc les
  favoris, l'ordre et les menus masqués sont conservés. À l'intérieur, on trouve deux voies :
  - **« Mon pointage »** : l'employé pointe avec son propre téléphone ;
  - **« Terminal de pointage »** : un appareil commun lit le badge, le NFC ou l'empreinte.

  Le « Pointage BL » (contrôle des quantités en stock) et le menu « Pointage » local (empreinte ou PIN) gardent
  leur libellé et leur icône.
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
