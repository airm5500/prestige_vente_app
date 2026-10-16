# Prestige Mobile 4.4.0+20 — retours du pharmacien du 16/10/2026

Plan : `plan_mobile_corrections.md`, section 1 (Prestige Vente App). Captures avant / après :
`docs/captures/4.4.0/` (données fictives).

## Corrections et améliorations

| Demande | Ce qui change |
|---|---|
| Bouton de déconnexion « comme celui du header de Prestige, rouge » | Même bouton que l'en-tête web (`.hdr-logout`) : pastille rouge `#e74c3c`, icône marche / arrêt blanche, ombre rouge — accueil (nouvelle interface), ancienne interface, ligne « Se déconnecter » des Réglages, entrée du menu ⋮. Comportement inchangé (confirmation puis déconnexion). |
| Fiche client : curseur à l'ouverture | Curseur automatique dans « Nom ou téléphone du client ». |
| Fiche client : « Changer » | Retour à la recherche avec le curseur dans le champ et le texte précédent **présélectionné** (une frappe le remplace). |
| Fiche client : lignes de résultats | Carte par client : initiales (couleur selon le sexe), nom en gras, téléphone, pastilles type / âge (calculé depuis la naissance) / sexe, nombre de clients trouvés. |
| Fiche client : consommation | Synthèse (produits, achats, boîtes, montant total), puis une ligne par produit : nom et **montant aligné à droite**, « N achats · N boîtes », rythme « tous les N j », « dernier le JJ/MM/AAAA », habitude en pastille colorée (mensuel / bimensuel / ponctuel / dormant), stock (vert / rouge). |
| État de Stock : « le bouton du filtre ne montre pas un filtre » | Le balai est remplacé par un **entonnoir** : contour au repos ; plein, sur pastille ambre, avec le **nombre de filtres actifs** quand un filtre (niveau de stock, emplacement, grossiste) est posé. Il replie / rouvre le panneau des filtres (résumé « Stock < 5 · RÉSERVE » quand il est replié). « Vider » dans le panneau. |
| Mise à jour péremption : « le code-barres n'est pas lu même dans le cadre » | Causes trouvées (comparaison avec la recherche de l'accueil et le choix de produit, où le scan fonctionne) : (1) analyse caméra en **640×480** (défaut Android) : un DataMatrix de boîte n'a que 2 à 3 pixels par module, lisible seulement à 5-6 cm, sous la distance de mise au point ; (2) « Scanner lot / date » ne lisait **que** les DataMatrix : l'EAN visé était ignoré **sans message** ; (3) le scan du produit n'acceptait ni UPC-A (EAN-13 commençant par 0), ni ITF, ni Code 39 ; (4) « Photo étiquette » ne lisait que le texte, jamais le code du cadre. Correctifs : haute définition **1280×720** + zoom automatique de ML Kit + bouton **Zoom ×2** ; tous les formats des boîtes ; un code sans lot ni date affiche « Visez le DataMatrix (petit carré) » et la lecture continue ; la photo de l'étiquette lit aussi le DataMatrix (lot et date GS1 repris sans confirmation). Les autres écrans de scan sont inchangés. |
| Menu spécial d'ajout de photo | Nouveau menu **« Photos produits »** (famille Stock) : douchette (curseur toujours prêt) / appareil photo / recherche → produit avec sa photo actuelle (« A déjà une photo » / « Sans photo ») → « Prendre la photo » (capture guidée) → aperçu → **OK, enregistrer** → produit suivant ; Reprendre / Annuler ; compteur de la séance. Aucune nouvelle route : ajout de photo existant (`POST /produit-images/{f}`), mêmes droits (administrateur avec « photoAdmin », ou réglage « photo terminal » ; droit du serveur). |

## Pointage présence (décisions du pharmacien du 16/10)

- **« Mon pointage » lié au compte de l'application** (scénario NEMA / EMMANUEL de la capture) : le jeton
  `v1/mobile` d'un autre compte est effacé dès l'ouverture (« Ce téléphone était connecté au compte … :
  déconnecté ») ; connexion `v1/mobile` automatique si le mot de passe de CE compte est mémorisé (« Rester
  connecté ») ; sinon mot de passe seul, identifiant pré-rempli **non modifiable**. Aucune connexion acceptée pour un
  autre identifiant, session d'un autre compte jamais gardée, chaque appel revérifie le lien : aucun pointage au
  nom d'un autre compte.
- **Photo du badge** : caméra avant ouverte dès l'arrivée sur le terminal et **gardée prête** (photo sans attente
  d'ouverture) ; rendue avant le scan du badge à la caméra arrière puis reprise ; attente de la libération du
  scanner arrière (nouvel essai toutes les 0,5 s) ; délai d'ouverture **10 s** (6 s auparavant) ; réouverture si la
  caméra prête a été reprise ; **motif détaillé** dans l'écran Photos de contrôle (code de la caméra, délai, scanner
  arrière…).
- **Droits** : Présences, Photos de contrôle et Empreintes (enrôlement) réservés à l'**administrateur de
  l'application** (compte « admin », ou profil administrateur du serveur) ; terminal toujours ouvert aux comptes
  `P_SM_RH` ; le droit distinct `P_RH_POINTER` (demande 52) est accepté dès que le serveur l'expose (repli
  `P_SM_RH`).
- **Intervalle** : 2 minutes, inchangé.
- **« Photo de contrôle »** (Paramètres › Équipe & pointage) : non reproduit (le réglage est bien enregistré) ;
  verrouillé par un test de l'application entière (sortie du menu, retour, redémarrage). Le filtre « Seulement
  les pointages sans photo » est désormais **mémorisé**. Texte « Prestige ne reçoit pas encore les photos » corrigé.
- Demandes serveur ajoutées à `docs/serveur/TRANSMISSION_SERVEUR_2026-10-15.md` : **51** (pointer avec la session
  de l'application : `GET v1/rh/moi`, `POST v1/rh/moi/pointages`, sans `P_SM_RH`, mêmes contrôles) et **52**
  (`P_RH_POINTER`).

## Empreintes partagées entre terminaux (demande 43, serveur du 16/10)

- Enrôlement sur un V3H (consentement + 3 captures + test) : modèles gardés chiffrés sur le terminal **et** envoyés
  au serveur (`POST v1/rh/employes/{id}/empreintes`, `X-Client-Ref`) ; réseau coupé → envoi refait à la
  synchronisation suivante avec la même référence (pas de doublon).
- Chaque terminal V3H télécharge les modèles de son format (`SUNMI_A400_RAW`) à l'ouverture du terminal puis toutes
  les 15 min, de façon **incrémentale** (`depuis` = horodatage du serveur, avancé seulement après une
  synchronisation complète), applique les suppressions, et identifie sur cette base.
- Suppression dans l'application → `DELETE` au serveur (refaite plus tard si le réseau est coupé) ; ré-enrôlement :
  anciens modèles retirés du serveur puis nouveaux envoyés.
- Consentement : « Le modèle d'empreinte est conservé chiffré sur le serveur de la pharmacie et reconnu sur tous
  ses terminaux de pointage » quand le partage est actif ; texte d'avant (« reste sur ce terminal ») sinon. Seuls
  les modèles consentis avec le texte du partage partent au serveur.
- État dans Paramètres › Équipe & pointage et dans l'écran des empreintes : « Empreintes : N employés, dernière
  synchronisation le … » / « partage désactivé sur le serveur » / « serveur sans partage des empreintes ».
- Repli : serveur sans les routes (404) ou `KEY_EMPREINTES_PARTAGEES` = 0 → fonctionnement d'avant (local), sans
  erreur. Jamais de gabarit dans les journaux, les messages ou les préférences ; tests avec des gabarits factices.

### Procédure pour le pharmacien

1. Dans Prestige (web), Paramètres : passer **`KEY_EMPREINTES_PARTAGEES` à 1**.
2. Sur un premier V3H (compte administrateur de l'application ayant le droit RH) : Pointage présence › Terminal ›
   « Empreintes des employés » ; l'état doit indiquer « dernière synchronisation le … ». Enrôler l'employé une
   fois (le texte du consentement parle du serveur de la pharmacie).
3. Sur le second V3H : ouvrir le Terminal de pointage (synchronisation à l'ouverture, puis toutes les 15 min) ;
   Paramètres › Équipe & pointage doit indiquer « Empreintes : 1 employé, dernière synchronisation … ». L'employé
   pointe par empreinte sans nouvel enrôlement.
4. Supprimer ses empreintes sur un terminal : elles disparaissent des autres à leur synchronisation suivante.

## Captures (`docs/captures/4.4.0/`, rendu des tests, données fictives, 360 dp)

| Fichier | Avant / après |
|---|---|
| `1_accueil_deconnexion_*` | en-tête de l'accueil : icône de sortie → pastille rouge marche / arrêt |
| `2_fiche_client_ouverture_*`, `3_fiche_client_resultats_*`, `4_fiche_client_consommation_*` | curseur, lignes de résultats, consommation |
| `5_etat_stock_filtre_*` | balai → entonnoir actif (pastille ambre, nombre), panneau « Filtres (1 actif) » |
| `6_…`, `7_…`, `8_photos_produits_*_apres` | nouveau menu (le rendu de test affiche certains libellés de boutons en pavés : police de test, pas l'application) |
| `9_mon_pointage_compte_lie_apres` | jeton de « nema.demo » effacé, pointage pour « emmanuel.demo » (avant : capture du pharmacien, bandeau seulement) |
| `10_photos_controle_filtre_motif_apres` | filtre mémorisé et motif détaillé |

Le scan de la péremption (caméra) ne se rend pas dans les tests : les réglages de la caméra sont vérifiés par
`scan_peremption`.

## Tests

Nouveaux : `scan_peremption`, `photos_produits`, `empreintes_partagees`, `pointage_reglages_e2e` (e2e « Photo de
contrôle » et filtre), `pointage_compte_lie_e2e` (e2e NEMA / EMMANUEL + sécurité), `reseau/empreintes_reseau`
(coupures pendant envoi / lecture / suppression, reprise, HTTP réel, synchronisation du terminal),
`performance/empreintes` (50 employés × 3 gabarits). Complétés : `fiche_client`, `presentation_stock_report`,
`expiration_update_datamatrix`, `pointage_photo`, `rh_pointage`, `accueil_connexion`. Faux serveur Prestige :
module `v1/mobile` (comptes et employés fictifs). CI, `test/categories.json`, `test/README.md` à jour.
