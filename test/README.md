# Tests de Prestige Mobile

Socle de tests exigé pour chaque application et à chaque livraison : **unitaires**, **écrans**, **intégration**,
**e2e**, **non-régression**, **ergonomie et cohérence d'affichage**, **performance** et **réseau** (4.2.1). Tout
s'exécute avec `flutter test` sur Linux (CI GitHub), **sans émulateur ni téléphone**, contre des **données
fictives** uniquement (aucun vrai patient, aucune vraie pharmacie). Chaque livraison est accompagnée d'un
**rapport de tests** (voir « Rapport de tests de livraison »).

## Lancer les tests

```bash
# Toute la suite de la CI (liste explicite, ligne 32 de .github/workflows/build-apk.yml), résultats JSON compris
flutter test $(sed -n 32p .github/workflows/build-apk.yml | sed 's/.*flutter test //')
# Rapport de tests de livraison (Markdown) à partir de ces résultats
dart run tool/rapport_tests.dart build/rapport_tests

# Un fichier, ou un test précis
flutter test test/e2e_parcours_test.dart
flutter test test/ergonomie_test.dart --plain-name "Sunmi V2s 720×1440, texte ×1.3"
flutter test test/performance test/reseau        # performance et réseau seulement
```

La CI liste **explicitement** chaque fichier (ligne 32). `test/non_regression_test.dart` échoue si un fichier
`test/**/*_test.dart` n'y figure pas (exceptions déclarées : `test/outils/apercus_connexion_test.dart` et
`test/outils/captures_borne_test.dart`, outils manuels qui génèrent des aperçus PNG avec `APERCUS=1` — captures de la
borne dans `docs/maquettes/captures_borne/`), si un fichier de la ligne 32 n'a pas de catégorie dans
**`test/categories.json`** (ou y figure sans être dans la CI, ou avec une catégorie inconnue), si l'une des huit
catégories est vide, ou si la CI ne produit plus le rapport.

## Rapport de tests de livraison

La ligne 32 écrit les résultats de toute la suite au format `flutter test --machine` (JSON, option
`--file-reporter json:build/rapport_tests/tests.json`). L'étape « Rapport de tests de livraison » lance ensuite
`tool/rapport_tests.dart` (même script que Prestige Inventaire, étendu à la table des catégories) qui écrit, dans le
**résumé du job GitHub** (`$GITHUB_STEP_SUMMARY`) et dans l'artefact **`rapport-tests`** (à côté de l'APK
`prestige-vente-apk`) :
- par catégorie (table versionnée `test/categories.json` : catégorie principale de chaque fichier) : nombre de
  fichiers, tests, réussis, sautés, échecs, durée cumulée ; durée réelle de la suite ;
- toutes les **mesures de performance et de requêtes** avec leur seuil et la part du seuil utilisée (⚠️ au-delà de
  80 % d'un seuil de temps, ❌ au-delà du seuil — le test échoue alors) ;
- les tests en échec et les tests sautés (anomalies connues « sauté : ANO-xx »).

Le rapport est produit même si des tests échouent (l'APK n'est alors pas construit). Fichiers de l'artefact :
`rapport.md`, `resume.json` (chiffres pour un tableau de bord), `tests.json` (résultats bruts).

## Catégories

| Catégorie | Ce qui est vérifié | Fichiers |
|---|---|---|
| **Unitaires** | règles et modèles sans écran : lecture DataMatrix / étiquettes / OCR, ordonnances (O1–O5), paiements, codes et identifiants sécurisés, droits, réserve, posologie, fiche client, journal, licence… | `datamatrix_parser`, `label_text_parser`, `ocr_rows`, `camera_scan_value`, `fingerprint_diagnostic`, `licence_lookup`, `pointage_analytics`, `ordonnances_*`, `paiement_multiple`, `modes_paiement_logo`, `securite_*`, `routes_app_vente`, `product_lookup`, parties « modèles / règles » de `reserve`, `posos`, `fiche_client`, `droits_modules`, `stock_reserve` (dont F2 : seuil réserve à 0 = non défini), `taille_ecran` (taille de l'écran : seuil petit écran, choix manuel prioritaire, persistance, impression et caméra non affectées), `recherche_debut_cip` (partie unitaire, 4.0.3 F3 : classement par début de code — exact, CIP, CIP13 / CIP7 / EAN —, choix de la ligne `/info` du même CIP, `PagedProductSearch`), `https_adresse` (4.1.0 : adresse http / https, ports 8080 / 443, port écrit prioritaire, anciens réglages = même adresse, échecs TLS), `ticket_prevente` (partie unitaire, 4.1.1 : nom de produit sur deux lignes sans couper un mot, lignes produits du ticket de prévente présentes / absentes selon le réglage, totaux identiques, borne et ticket discret), `sortie_borne` (partie unitaire, 4.1.2 : cadenas de sortie, cause du blocage du terminal — l'infobulle captait l'appui long —, « Tester la borne » contre le faux serveur) |
| **Écrans (widgets)** | chaque écran isolé avec un faux service : présentations A / B / C, 360 px, tablette, messages d'erreur, anti double appui | `presentation_*`, `ventes_*`, `accueil_*`, `parametres`, `recherche_*`, `reception_bl`, `retour_frs`, `borne`, `connexion_lancement`, `scan_fiche_analyse`, `vente_clavier`, `retours_*`, `pointage_*`, `rh_pointage`, `horsligne_*`, `journal_terminal`, `support_centre`, `images_produits`, `paiements_mobile`, `version_affichee` (version X.Y.Z+N lue à l'exécution : connexion, Réglages), parties « écran » de `reserve`, `posos`, `fiche_client`, `https_configuration` (4.1.0 : choix http / https dans les deux interfaces), `ticket_prevente` (4.1.1 : réglage « Afficher les produits sur le ticket de prévente » dans Réglages › Impression et la Configuration d'origine) |
| **Intégration** | vrais clients HTTP de l'application contre un serveur simulé (vrai HTTP local ou en mémoire) | `reponse_serveur` (4.3.0 : réponse du serveur du 15/10, repli), `integration_services` (ApiService, licence, connexion, préventes, BL, analyse article, AuthProvider, passerelle de vente), `client_prestige`, `client_prestige_session`, `reserve`, `posos`, `fiche_client`, `droits_modules` (parties « serveur local »), `session_expiree`, `session_renouvelee`, `pointage_photo_integration`, `faux_serveur_prestige` (auto-contrôle du simulateur), `https_integration` (4.1.0 : faux serveur en HTTPS, `bindSecure` + certificat de test : même adresse https et cookie renouvelé pour tous les clients, session expirée, certificat refusé ≠ injoignable ≠ licence) |
| **E2E** | application ENTIÈRE (`MyApp`, vrais providers, vrai Dio, intercepteur de session, surveillance du serveur) reliée au faux serveur Prestige en mémoire | `e2e_parcours`, `widget_test` (démarrage), `recherche_rapide_info` (4.1.2 : Analyse article, fiche produit et État de Stock contre un serveur lent), `sortie_borne` (4.1.2 : borne activée puis quittée, borne sans données, session de l'utilisateur borne expirée), `recherche_debut_cip` (4.0.3 F3 : « 3595 » dans Recherche Article et Évaluation Vente en Début / Contient — liste et détails du produit choisi —, Analyse article, recherche de l'accueil, contre des réponses triées par nom comme le serveur), `https_configuration` (4.1.0 : application configurée en https, toutes les requêtes vers la même adresse) |
| **Ergonomie / cohérence d'affichage** | 21 écrans et fenêtres × 5 tailles × 2 échelles de texte : débordements, cibles ≥ 48 dp, contraste, charte, clavier (petits écrans en Compact automatique, 4.0.1) ; Sunmi V2s aux 3 tailles d'écran (Automatique / Compact / Très compact), vente clavier ouvert, douchette, autres appareils en Automatique, réglage dans les deux interfaces ; Configuration d'origine (4.0.3 F1) sans débordement aux 5 tailles × texte 1,0 / 1,3 | `ergonomie`, `ergonomie_taille_ecran`, `configuration_origine` (+ `responsive` : rendu à 360 px figé par `responsive_reference_360.json`) |
| **Performance** (4.2.1, `test/performance/`) | temps réels mesurés et **seuils** (voir « Seuils de performance ») : démarrage → écran de connexion, connexion → accueil A / B / C ; défilement de longues listes (Recherche Article 500 produits, 200 préventes à encaisser, Réserve 300 lignes, journal 1 000 actions) ; 50 lignes ajoutées au panier ; **nombre de requêtes** des parcours clés (recherche tapée vite → 1 requête après l'anti-rebond, Analyse article, fiche produit, État de Stock, encaissement, synchro hors ligne) ; traitements locaux (classement par code de 5 000 produits, 100 tickets) | `demarrage`, `listes_longues`, `requetes`, `traitement_local` |
| **Réseau** (4.2.1, `test/reseau/`) | serveur lent qui répond (2 / 5 / 8 s ; 25 s pour `GET /info`) sur la vente, l'encaissement, la recherche, l'Analyse article : indicateur, écran utilisable, pas de double envoi, pas d'erreur avant le délai ; réponses tronquées et JSON invalide ; coupure puis retour (reprise de la file hors ligne, coupure pendant l'envoi) ; local ↔ distant (deux serveurs) ; certificat HTTPS refusé (application entière ; le vrai TLS est dans `https_integration`) | `serveur_lent`, `reponses_tronquees`, `coupures_reprise`, `adresse_serveur`, `https` ; 4.3.0 : photo de pointage sur serveur lent ou coupé (`reponse_serveur`) |
| **Non-régression** | garde-fou de la liste CI et des catégories (`test/categories.json`) ; anomalies corrigées (ANO-01, 02, 04, 05, 08) ; versions alignées sur le magasin Sunmi (`docs/VERSIONS_SUNMI.md` : pubspec.yaml ≥ version publiée, +N > versionCode publié, aucun numéro en dur dans Gradle) ; ensemble de la suite verte | `non_regression`, `version_sunmi`, `ticket_prevente` (4.1.1 : réglages par défaut → tickets identiques, appel par appel à l'imprimante Sunmi simulée et ligne par ligne à l'aperçu, à ceux de la 4.1.0 : `test/ticket_prevente_reference.json`) + toute la liste CI |

Un fichier peut toucher plusieurs catégories (tableau ci-dessus) ; le rapport de livraison le compte dans sa
catégorie **principale**, celle de `test/categories.json`.

## Parcours clés et couverture

| Parcours | Couverture |
|---|---|
| Lancement : réglages → serveur → licence | e2e (`Lancement et licence`), `connexion_lancement`, `widget_test` |
| Licence : serveur injoignable, 5xx, 401, 403 « Veuillez vous connecter » ≠ « aucune licence » ; licence absente / expirée | e2e, `integration_services`, `licence_lookup` |
| Connexion : identifiants, cookie JSESSIONID **renouvelé** (l'ancien n'est plus envoyé) | e2e (`Connexion`), `session_renouvelee`, `integration_services`, `https_integration` (en https) |
| Serveur en HTTPS (accès Internet, 4.1.0) : réglage http / https, certificat refusé ≠ injoignable ≠ licence, http inchangé | `https_adresse`, `https_integration`, `https_configuration` |
| Accueil : présentations A / B / C, cloche, favoris, recherche globale | e2e, `accueil_test`, `accueil_connexion`, `responsive` |
| Recherche par début de CIP (Recherche Article, Évaluation Vente, Analyse article, accueil) : bon produit en tête, détails du bon produit | `recherche_debut_cip` |
| Ticket de prévente (comptoir, borne) : produits selon le réglage Impression, ticket discret de la borne, noms longs sur deux lignes, tickets par défaut inchangés | `ticket_prevente` |
| Retours des essais du pharmacien : fenêtres de la nouvelle interface à la charte (dialogues, feuilles du bas, messages : plus de lavande Material ; code administrateur, déconnexion, « Prévente enregistrée », emplacement, photo de contrôle), hors ligne seulement avec des données sur le terminal (refus expliqué, « Télécharger le catalogue », fraîcheur), Réserve en onglets Manuel / Automatique, confirmation de l'EAN fabricant (Entrée de la douchette, clé de contrôle), icône de la Pré-vente, vente carnet / assurance sans « flash » des étapes | `retours_pharmacien` (unitaires, écrans, application entière ; V2s Compact auto, 360 × 800 dp, tablette ; texte × 1,0 / 1,3), `ergonomie` (écrans `reserve_automatique`, `deconnexion`, `code_administrateur`) |
| Recherche rapide (4.1.2) : Analyse article = liste `GET /vente/search` puis détail `GET /info` par CIP exact (aucun `/info` pendant la frappe), fiche produit sans attente, État de Stock (requête précédente annulée), délai `/info` de 30 s réel (plus d'abandon à 10 s) — faux serveur lent | `recherche_rapide_info` (e2e), `retours_video`, `scan_fiche_analyse`, `recherche_debut_cip` |
| Lenteur Analyse article / fiche produit (4.3.2) : mode hybride — liste `GET /vente/search`, puis UN `GET /info` de la saisie (lot, 1 à 30 produits, 3 caractères et plus) réutilisé au clic (aucune 2ᵉ requête) ; identité, stock, prix de vente, prix d'achat et emplacement immédiats, graphe à la réponse ; détail fermé avant la réponse : requête gardée (réouverture immédiate) ; délai dépassé : Réessayer relance ; images lentes sans effet ; onglet Scanner : recherche par code puis `GET /info` du CIP — nombre, ordre et temps des requêtes contre un faux serveur lent | `lenteur_detail_432` (performance, e2e, unitaires `FicheInfoCache`), `performance/requetes`, `reseau/serveur_lent`, `recherche_rapide_info` |
| Analyse article, mise en page (4.3.2) : stock et prix sur une ligne dans la liste ; détail : stock rayon et stock réserve sur une ligne, « Fermer » toujours visible sans défiler (Sunmi V2s et 360×640 dp, texte ×1 et ×1,3) | `ergonomie_analyse_432` |
| Deux pannes du serveur (4.3.3) : **injoignable** (aucune réponse : PC serveur éteint, Payara arrêté, délai, réseau) → « Serveur injoignable. Vérifiez le Wi-Fi et que le PC serveur est allumé. » ; **indisponible** (Prestige non déployé : 404 de Payara, 502 / 503 / 504) → « Serveur indisponible : Prestige est en cours de démarrage ou de redéploiement… » — connexion (deux interfaces), lancement, licence, accueil (surveillance du serveur), borne (« Tester la borne »), pointage (terminal RH, téléphones), modules ; mot de passe faux, 500, refus métier inchangés | `reseau/redeploiement`, `connexion_lancement`, `integration_services`, `licence_lookup`, `sortie_borne` |
| Replis « serveur ancien » (4.3.3) : un 404 HTML n'est « route absente » qu'après vérification de `/officine` (aucune requête de plus en fonctionnement normal, une vérification pour plusieurs 404) ; Prestige non déployé : rien de mémorisé (droits Réserve / Posos, photo de pointage, app-vente, support), à réessayer | `reseau/indisponible_replis`, `support_centre`, `pointage_photo_integration` |
| Sortie des modes borne (4.1.2) : cadenas, appui long 2 s, confirmation, code administrateur ; borne « activer puis quitter » (désépinglage, mode borne désactivé, écran de connexion) ; cause d'une borne sans données (utilisateur non configuré, mot de passe absent, connexion refusée, serveur injoignable) et « Tester la borne » ; reconnexion de l'utilisateur borne après expiration de sa session ; terminal de pointage « entrer puis quitter » | `sortie_borne` (e2e), `borne` (affichage : ticket Sunmi, Liste rapide, « B/ », réglages à 360 px) |
| Réponse du serveur du 15/10/2026 (4.3.0), toujours avec repli sur un serveur ancien : droits Réserve / Posos (`reserve/droits`, `posos/droits`), refus 403 « Droit manquant », rôle de `user/auth`, `X-Client-Ref` hors ligne sur `add-lot` / `add-item`, licence « après connexion d'un administrateur » (e2e administrateur / autre compte), suggestion annulée ou d'un autre emplacement ; pointage avec `id`, `controle` et photo envoyée (serveur ancien : 1 essai) | `reponse_serveur`, `pointage_photo_integration`, `performance/demarrage` |
| EAN fabricant (4.3.0) : aucun contrôle de forme, confirmation Oui / Non, « Non » remet le curseur dans le champ (valeur gardée), champ vide = rien | `retours_pharmacien` (3 tailles × 2 échelles de texte), `presentation_delivery_ean` |
| Réception BL, D18 (4.3.1) : numéro de série (AI 21) et GTIN du DataMatrix envoyés avec le lot ; boîte déjà scannée → « Boîte déjà scannée », rien d'ajouté, boîte suivante acceptée ; hors ligne : ligne refusée à la synchro, jamais renvoyée ; ancien serveur (champs ignorés, ou 400 → renvoi sans série) ; délai dépassé ; aucun numéro de série dans le journal | `reception_bl` (écran, 360×640 dp texte ×1,3), `reponse_serveur` (unitaires, intégration, réseau, hors ligne) |
| Déconnexion (4.4.0) : même bouton que l'en-tête de Prestige (web) — pastille rouge #e74c3c, icône marche / arrêt blanche — accueil (A / B / C), ancienne interface, Réglages | `accueil_connexion` |
| Fiche client (4.4.0) : curseur dans la recherche à l'ouverture ; « Changer » : curseur revenu, texte présélectionné ; lignes de résultats (initiales, nom, téléphone, type, âge, sexe) ; consommation (synthèse, montants alignés à droite, rythme « tous les N j », dernier achat, habitude, stock) — Sunmi V2s et 360 dp ×1,3 | `fiche_client` |
| État de Stock (4.4.0) : bouton Filtres en entonnoir (contour au repos ; plein sur pastille ambre + nombre de filtres actifs), panneau repliable avec résumé, « Vider » — présentations A / B / C | `presentation_stock_report` |
| Mise à jour péremption (4.4.0) : scan caméra en haute définition (1280×720 + zoom auto + Zoom ×2), formats des boîtes (UPC-A, ITF, Code 39…), « Scanner lot / date » : EAN refusé avec un message au lieu d'être ignoré ; « Photo étiquette » : DataMatrix du cadre lu sur la photo (lot et date GS1, sans confirmation) ; autres écrans inchangés | `scan_peremption`, `expiration_update_datamatrix` |
| Photos produits (4.4.0) : douchette / appareil photo / recherche → photo actuelle signalée → capture → aperçu → OK (ajout de photo existant) → produit suivant, curseur prêt ; Reprendre / Annuler ; droits de la fiche produit (photoAdmin, photo terminal, droit du serveur) ; 3 tailles | `photos_produits` |
| Pointage — réglages (4.4.0) : « Photo de contrôle » gardée après sortie du menu et redémarrage (application entière) ; filtre « Seulement les pointages sans photo » mémorisé ; motif détaillé d'un pointage sans photo | `pointage_reglages_e2e`, `pointage_photo` |
| Pointage — « Mon pointage » lié au compte de l'application (4.4.0, scénario NEMA / EMMANUEL) : jeton d'un autre compte effacé, connexion automatique (mot de passe mémorisé) ou mot de passe seul (identifiant non modifiable), pointage reçu pour le bon compte ; sécurité : aucune connexion / aucun appel pour un autre compte | `pointage_compte_lie_e2e`, `rh_pointage` |
| Pointage — photo du badge (4.4.0) : caméra avant ouverte dès l'arrivée et gardée prête, rendue pour le scanner arrière puis reprise, délai 10 s, réouverture si la caméra prête a été reprise | `pointage_photo` |
| Pointage — droits (4.4.0) : présences, photos, empreintes = administrateur de l'application ; terminal = P_SM_RH ou « P_RH_POINTER » (demande 52, accepté dès qu'il existe) | `rh_pointage` |
| Empreintes partagées (4.4.0, demande 43) : enrôlement → envoi (X-Client-Ref), autre terminal → synchronisation incrémentale et reconnaissance, suppression partout, partage désactivé / serveur sans routes → local, consentement adapté, statut dans les réglages, jamais de gabarit dans les journaux ; coupures pendant envoi / lecture / suppression et reprise sans doublon ; 50 employés × 3 gabarits | `empreintes_partagees`, `reseau/empreintes_reseau`, `performance/empreintes` |
| Google Play (4.5.0) : signature par la clé d'envoi (environnement puis `android/key.properties`) avec repli debug et avertissement, aucun mot de passe en clair ; targetSdk / compileSdk 36 **seulement** pour la version Play (propriété `playStore`), APK de la CI et du PC en 35 ; manifeste (retour prédictif désactivé, orientation sur grand écran, pas de retrait du bord à bord) ; permissions ; `play.yml` (une application par branche, secrets communs, `android/DEMANDE_PLAY`, action épinglée, internal / draft, contrôle targetSdk 36 et 16 Ko, aucun secret affiché) | `android_play` |
| Sécurité des ventes (4.5.1, demande du serveur du 19/10/2026) : droits lus à chaque connexion et au premier plan (mémoire seulement, repli sans la route) ; compte « Pre-vente » sans « ENCAISSER » (nouvelle et ancienne interface, hors ligne), « PRÉVENTE » permise ; 403 interdit → message, vente en cours, toujours connecté, une seule tentative ; changement de compte → logout, cookies, panier et vente à reprendre effacés ; 409 sessionChangee → message, compte et droits relus, accueil ; en-tête X-Prestige-Utilisateur ; envoi hors ligne (403 sans boucle, 409 en attente, ventes d'un autre compte gardées) ; borne : mobile money masqué sans droit de clôture, 403 pendant le paiement → ticket pour la caisse, « Tester la borne » | `droits_vente`, `droits_vente_e2e`, `borne_droits`, `reseau/droits_vente_reseau` |
| Réponse du serveur du 19/10/2026 (4.6.0) : BL refusé `PRODUITS_NON_SAISIS` (liste défilable sur Sunmi V2s) ; `P_BL_MOBILE_SCANNER` masqué seulement quand le serveur le contrôle (403 constaté ou capacité `droitScannerBl`), jamais sur un serveur ancien ; 403 add-lot / creerbl → message ; `data.message` du retour fournisseur ; « Mon pointage » par `v1/rh/moi` (aucune connexion v1/mobile, jeton effacé, `X-Client-Ref`, même clé = un pointage, coupure, repli v1/mobile sur 404) ; terminal avec `P_RH_POINTER` seul (aucune gestion, employés aux champs réduits) | `reponse_serveur_1910`, `reponse_serveur_1910_e2e`, `reseau/pointage_session_reseau` |
| Suite du serveur du 19/10/2026 (4.6.1) : `X-Client-Ref` sur la mesure de la fiche client (même saisie renvoyée après une réponse perdue = même clé, saisie modifiée = nouvelle clé, sans clé = comme avant) ; `blId` sur `retourfournisseur/new` en ligne et hors ligne (absent si le BL n'est pas retrouvé, 400 → renvoyé une fois sans `blId`, même `X-Client-Ref`) ; refus lisibles de `commande/creerbl` (D6) | `fiche_client`, `reponse_serveur_1910`, `horsligne_h4`, `retour_frs` |
| Badges RH en QR (4.6.2) : contenu `PRESTIGE-BADGE\|1\|numéro\|login\|secret` (exact, douchette QWERTY sur AZERTY avec ou sans verrouillage des majuscules, minuscules, version inconnue, lecture incomplète ou déformée, numéro vide) ; codes-barres et UID NFC inchangés ; terminal RH et ancien kiosque : numéro → employé, champ masqué dès « PRESTIGE », secret et login jamais affichés, journalisés ni envoyés (e2e : aucune requête ne les porte) | `badge_qr`, `badge_qr_e2e`, `pointage_badge` |
| Nom de cet appareil (4.7.0, en-tête `X-Poste`) : nettoyage identique au serveur (accents, caractères retirés, espaces de bord, 60 caractères, recoupé avec le code Java), encodage URL ; en-tête sur TOUTES les requêtes (connexion, création et clôture de la vente, vérification du déploiement, coupure et reprise), nom par défaut « marque modèle », aucun en-tête sans nom ; proposition à la première connexion (« Caisse mobile 1 », « Plus tard ») ; champ des réglages (téléphone, Sunmi V2s, texte ×1,3 et ×2) ; garde-fou : tout Dio de lib/ reçoit l'intercepteur ; 20 000 requêtes < 400 ms | `nom_appareil`, `nom_appareil_e2e`, `nom_appareil_garde`, `reseau/nom_appareil_reseau`, `performance/nom_appareil_perf`, `parametres` |
| Réponses du pharmacien (4.7.1) : journal de la console du mode débogage sans mot de passe, cookie, jeton, clé X-Client-Ref, corps ni paramètre (connexion, recherche d'un client, réponse illisible ; garde-fou : aucun LogInterceptor, aucun print, aucune erreur recopiée) ; nom de l'appareil OBLIGATOIRE (étape au lancement pré-remplie, retour bloqué, nom vide refusé, réglages non quittables, nom déjà enregistré ou gardé par une mise à jour : plus demandé ; règles de sauvegarde Android) | `journal_debug`, `nom_appareil`, `nom_appareil_e2e`, `parametres` |
| Nom de l'appareil gardé par le serveur (4.8.0, demande 56) : `GET v1/appareil/nom` sans session au premier lancement (trouvé → pas d'étape ; inconnu, 429, 404, délai > 3 s → étape), `PUT` avec la session après la connexion (une fois par serveur, nom renvoyé gardé, 404 → plus d'essai, échec → nouvel essai) ; réinstallation simulée ; X-Poste sur connexion et déconnexion ; empreinte seulement dans son champ, jamais journalisée ; ANDROID_ID jamais hors du code natif | `nom_appareil_serveur_e2e`, `reseau/nom_appareil_serveur_reseau`, `nom_appareil_garde` |
| Étiquettes GS1 à la vente alignées sur le web (4.9.0) : réglage `KEY_VENTE_LECTURE_GS1` lu à la connexion ; verdict `GET v1/vente/gs1` (mode A avertissement, mode B `lotScanne` avec la ligne une seule fois, mode C « Prenez une boîte du lot… », périmée, étiquette étendue, sans produit : refusées) ; lecture inactive, serveur ancien (404/405), panne, délai > 2,5 s → exactement la recherche d'avant (mêmes codes essayés, même produit) ; code-barres 1D, CIP saisi, nom : jamais `vente/gs1` ; hors ligne : boîte périmée refusée par sa date ; borne : « présentez-le au comptoir » sans détail de lot, aucun avertissement A/B ; ancienne interface des ventes ; lien numérique GS1, `]Q3`, forme `(01)…(17)…` ; contenu scanné jamais journalisé ; 20 000 reconnaissances < 500 ms | `gs1_vente`, `gs1_vente_e2e`, `reseau/gs1_vente_reseau`, `performance/gs1_vente_perf`, `borne_test` |
| Lecture GS1 dans les ventes Dépôt et Proforma (4.9.1) : mêmes règles que la vente au comptant (mode C, périmée, étendue, sans produit refusées ; A et B : avertissement neutre) SANS `lotScanne` (routes `add/depot` et `devis` qui ne s'en servent pas) ; lecture inactive, 404, 405, 500, coupure, délai, réponse illisible → produits, « introuvable » et codes essayés identiques à la recherche d'avant ; code-barres, CIP, nom et autres menus : jamais `vente/gs1` ; hors ligne : périmée refusée ; contenu scanné jamais journalisé ; 2 000 recherches sans surcoût | `gs1_depot_proforma`, `gs1_depot_proforma_e2e`, `reseau/gs1_depot_proforma_reseau`, `performance/gs1_depot_proforma_perf` |
| Étiquettes étendues refusées comme le web (4.9.2) : DataMatrix+ et QR+ reconnus sur l'appareil (portage exact de `estEtiquetteEtendue` du web : préfixes de lecteur, `EP1|`, champ 91 `EPLUS1` après GS / `<GS>` / `^]` / `~1` / `|`, entre parenthèses ou en tête ; jamais une étiquette normale, un code-barres, un CIP, un nom), refusés avec le message du web même lecture GS1 inactive, réglage absent ou hors ligne, sans aucune requête : vente au comptant (nouvelle et ancienne interface), Proforma ; borne : « présentez-le au comptoir » ; Dépôt : comme avant (le web ne la refuse pas) ; étiquette normale, code-barres, nom en lecture inactive : comme avant ; contenu jamais journalisé ; 50 000 reconnaissances < 500 ms | `gs1_etendue`, `gs1_etendue_e2e`, `reseau/gs1_etendue_reseau`, `performance/gs1_etendue_perf`, `borne_test` |
| Dépôt comme le web (4.9.3) : étiquette étendue (DataMatrix+, QR+) jamais refusée ni envoyée à `vente/gs1`, lecture GS1 active ou inactive ; recherche d'avant (DataMatrix+ trouvé par son GTIN, QR+ sans produit), ligne sans `lotScanne` ; autres règles GS1 du Dépôt (4.9.1) et refus du comptant, de la Proforma et de la borne inchangés | `gs1_etendue`, `gs1_etendue_e2e`, `reseau/gs1_etendue_reseau`, `performance/gs1_depot_proforma_perf`, `gs1_depot_proforma`, `gs1_depot_proforma_e2e` |
| Dépôt exactement comme le web (4.9.4) : étiquette étendue (DataMatrix+, QR+) → aucun produit, rien d'affiché, aucune requête (ni `vente/gs1`, ni recherche, pas de lecture du GTIN), lecture active ou inactive ; étiquette GS1 normale et autres règles du Dépôt inchangées ; autres menus inchangés | `gs1_etendue`, `gs1_etendue_e2e`, `reseau/gs1_etendue_reseau`, `performance/gs1_depot_proforma_perf` |
| Prestige Pointage 1.0.0 (demande 57) et « Pointer » de Prestige Mobile 4.10.0 : signature HMAC épinglée sur les vecteurs du code Java du serveur ; enrôlement (code administrateur, compte administrateur temporaire, nom de l'appareil obligatoire, déconnexion immédiate, plus jamais de connexion) ; appels signés contre un faux serveur appliquant les règles du vrai (ordre du filtre, ±300 s, rejeu, REVOQUEE, RESEAU, 429 + Retry-After, serveur ancien) ; pointage QR (secret jamais envoyé, journalisé ni gardé), 1D, NFC, empreinte partagée ; file hors ligne puis envoi automatique et renvoi idempotent ; horloge décalée ; empreintes DESACTIVE par connexion RH temporaire ; vrai HTTP (paramètres encodés, JSON accentué, multipart) ; Sunmi V2s, téléphones, tablette, texte ×1 / ×1,3 / ×2 ; 2 000 signatures, 2 000 employés ; garde-fous (version propre, saveurs, manifeste, CI, Google Play par son seul fichier de demande, secret lu seulement pour signer, terminal de Prestige Mobile inchangé) ; bouton et tuile « Pointer » seulement si l'application est installée | `prestigepointage/signature_borne`, `prestigepointage/prestigepointage`, `prestigepointage/client_borne`, `prestigepointage/pointage_e2e`, `prestigepointage/mobile_pointer_e2e`, `prestigepointage/pointage_ergonomie`, `prestigepointage/prestigepointage_garde`, `reseau/prestigepointage_reseau`, `performance/prestigepointage_perf` |
| Retours du pharmacien du 31/10 (4.10.1) : tuiles « Catégories » de la borne entières (pictogramme et libellé) sur Sunmi V2s avec « Taille de l'affichage » agrandie (densité 2 à 2,75) et texte ×1 à ×1,5, grille inchangée à la taille d'usine ; fiche client : date de naissance ABSENTE ajoutée (« Ajouter », JJ/MM/AAAA ou calendrier, date à venir / avant 1900 / inexistante refusées sans requête, `POST client/{id}/identite` en AAAA-MM-JJ, « Déjà renseigné », serveur ancien → « mis à jour », coupure), date présente affichée JJ/MM/AAAA sans bouton, consultation seule sans bouton, date jamais journalisée | `borne_test`, `fiche_client`, `fiche_naissance_e2e`, `reseau/fiche_naissance_reseau` |
| 4.10.2 : date de naissance modifiée ou effacée (demande 58 : `remplacer:true`, capacité `naissanceModifiable` du dossier ; fausse ou absente → ni « Modifier » ni « Effacer », « Ajouter » inchangé ; confirmation de l'effacement ; message du serveur ; refus « Client introuvable », « plus de 130 ans » ; date jamais journalisée) ; ligne d'état Mobile Money sous l'option (Réglages › Paiements : encaissement de l'appareil et borne) et étape « Module Mobile Money » de « Tester la borne » : option décochée, serveur injoignable, serveur sans module (404), aucun compte de paiement (liste vide), compte sans droit de clôture (compte nommé), proposé ; capacités relues à chaque vérification ; session d'essai de la borne fermée ; V2s texte ×1,3 | `fiche_client`, `fiche_naissance_e2e`, `reseau/fiche_naissance_reseau`, `mobile_money_etat`, `mobile_money_etat_e2e`, `reseau/mobile_money_etat_reseau` |
| Borne : « Ajouté : NOM » en haut de l'écran, ne recouvre ni la recherche ni le panier, 2 s | `borne_test` |
| Configuration d'origine (appareil non configuré, interface d'origine) | `configuration_origine`, `non_regression` (ANO-08) |
| Menus principaux ouverts puis retour (touche retour Android) : Vente, Recherche article, Analyse article, Fiche produit (par code), Analyse posologie, Ordonnances des clients / Fiche client (selon droits), Réserve (administrateur seulement), Pointage présence, Réglages | e2e (`Accueil : chaque menu principal…`, droits) |
| Session expirée en cours de route : reconnexion silencieuse si « Rester connecté », sinon écran de connexion avec « Votre session a expiré, reconnectez-vous » | e2e (`Session expirée`), `session_expiree` |
| Serveur coupé : « Connexion au serveur perdue » puis « De nouveau en ligne » | e2e (`Réseau`), `horsligne_test`, `accueil_connexion` |
| Vente hors ligne (prévente provisoire) puis envoi au retour du serveur après confirmation | e2e (`Réseau`), `horsligne_ventes`, `horsligne_h4` |
| Ventes comptant / assurance / carnet / dépôt, encaissement, paiement multiple | `ventes_*`, `presentation_depot_sale`, `paiement_multiple` |
| Réception BL, contrôle livraison / réception, pointage BL, retours fournisseur | `reception_bl`, `presentation_*`, `retour_frs`, `sync_load_errors` |
| Stock, périmés, péremption, ajustement, emplacement, EAN, réserve | `presentation_*`, `stock_reserve`, `reserve`, `horsligne_stock` |
| Pointage (local, badge, NFC, présence, photo de contrôle) | `pointage_*`, `rh_pointage`, `pointage_photo*` |
| Performance des parcours (4.2.1) : démarrage, accueil A / B / C, longues listes, panier de 50 lignes, requêtes par parcours, traitements locaux | `performance/*` |
| Réseau (4.2.1) : serveur lent, réponses tronquées / JSON invalide, coupures et reprise de la file hors ligne, local ↔ distant, certificat refusé | `reseau/*`, `https_integration` |
| Ordonnances (vérification, OCR, apprentissage, lecture avancée) | `prescription_check`, `ordonnances_*` |

## Outils communs (`test/outils/`)

### Faux serveur Prestige — `faux_serveur_prestige.dart`

Étend `ServeurJsonLocal` (`serveur_json_local.dart`, interface d'origine inchangée pour ses utilisateurs).

```dart
final s = FauxServeurPrestige();          // comptes fictifs : DonneesFictives.login / .admin
await s.demarrer();                         // vrai HTTP sur 127.0.0.1 (tests `test()`, dans avecVraiHttp)
s.installerEnMemoire();                     // OU client HTTP en mémoire (tests de widgets, temps simulé)

s.routes['GET /info'] = (r) => FauxServeurPrestige.ok([...]);    // route scriptée (prioritaire)
s.routes['POST /vente/add/vno'] = (_) => FauxServeurPrestige.refus('Stock insuffisant'); // 200 success:false
s.licence = FauxServeurPrestige.nonConnecte403;  // 401 / 403 « Veuillez vous connecter »
s.routes['GET /x'] = (_) => FauxServeurPrestige.erreurServeur(503);  // 5xx (page HTML)
s.routes['GET /y'] = (_) => FauxServeurPrestige.lent(corps, const Duration(seconds: 30)); // délai
s.latence = const Duration(seconds: 2);    // délai sur toutes les réponses
await s.couper(); await s.retablir();      // coupure réseau (connexion refusée)
s.tentatives;                               // en mémoire : toutes les adresses demandées, refusées comprises (ANO-08)
s.expirerSessions();                       // durée de session dépassée côté serveur
s.refusEn403 = true;                       // le filtre répond 403 au lieu de 401
s.activerModules();                        // Réserve, Posos, Fiche client avec données fictives
```

- **Sessions** comme le vrai serveur : `POST /user/auth` délivre un **nouveau** `JSESSIONID` ; sans cookie valide,
  les routes non publiques répondent 401 « Veuillez vous connecter » **sans exécuter** la requête
  (`exigerSession = false` pour désactiver). Contrôle : `recues`, `recuesSur('/suffixe')`, `r.jsessionid`,
  `connexions`, `refusSession`, `derniereSession`.
- **Ventes comptant simulées** (création au 1er article, panier, net, prévente, statut) : `ventes`, `statutVentes`.
- Données : `DonneesFictives` (produit, licence, utilisateur, réserve, dossier client fictif).
- **HTTPS** (4.1.0) : `s.contexteTls = cert.contexteServeur` avant `demarrer()` → `HttpServer.bindSecure`, `base` en
  `https://`. Certificat de test (`certificat_tls.dart`, `CertificatTest.creer()`) : auto-signé, créé à la volée
  par `openssl` (aucune clé dans le dépôt). `avecConfianceTest(cert, …)` l'approuve **dans le test seulement**
  (HttpOverrides) ; avec `avecVraiHttp` il est refusé, comme sur un téléphone. Le code de l'application ne
  contourne jamais la vérification.

Tests réseau (4.2.1) :

```dart
FauxServeurPrestige.jsonInvalide('[{"id":1,"lib');        // 200, annoncé JSON, illisible
FauxServeurPrestige.coupeeEnCours(corps, part: 0.5);        // connexion fermée au milieu du corps
s.certificatRefuse = true;                                  // en mémoire : poignée de main TLS refusée (https)
FauxServeurPrestige(hoteEnMemoire: 'distant.test');         // 2e serveur en mémoire (local ↔ distant)
```

### Performance — `performance.dart`

`Seuils` (tous les seuils, documentés ci-dessous), `mesurer(nom, valeur, seuil:, unite:, detail:)` (compare au seuil
et imprime `PRESTIGE_MESURE {json}` pour le rapport), `ChronoImages` (chaque `pump` chronométré en temps réel :
max, p90, moyenne), `defilerJusquEnBas`, `plusGrandeListe`, `remonter`, `meilleurDe(n, …)` (meilleur de n passages),
`compterRequetes(serveur, action)` et `detailRequetes` (« GET /vente/search ×1, … »).

### Parcours de vente — `parcours_vente.dart`

`CatalogueFictif(serveur, nombre:, preventes:)` : N produits fictifs servis par pages par `GET /vente/search`
(« commence par », comme le serveur), modes de règlement, clôture comptée (`clotures`), délais réglables
(`delaiRecherche`, `delaiCloture`), N préventes à encaisser. Gestes : `ajouterAuPanier`, `validerEncaissementEspeces`.

### Tickets imprimés — `ticket_capture.dart`

`ImprimanteSimulee` répond sur le canal `sunmi_printer_plus` (imprimante présente) et enregistre chaque appel
(`appels`) et chaque ligne imprimée (`textes`) ; `apercu(tester, …)` rend les lignes du dialogue « Aperçu du Ticket »
(mode test d'impression) ; dates remplacées par `<DATE>`. `tousLesTicketsParDefaut` imprime tous les tickets avec
les réglages par défaut : sa sortie est comparée à `test/ticket_prevente_reference.json`, produite avec le code
4.1.0. Données fictives : `officineFictive`, `articlesFictifs` (dont le nom de la capture de la borne)…

### Banc e2e — `app_e2e.dart`

`AppE2E` prépare l'appareil comme `lib/main.dart` (préférences, stockage sûr simulé, stockages en mémoire au lieu de
SQLite), relie le faux serveur en mémoire et monte `MyApp`. Gestes : `lancer`, `seConnecter`, `ouvrirMenu(style, id)`,
`menuPresent`, `defilerJusqua`, `retour` (touche retour Android), `attendre`, `attendreQue`, `fermer`.
Tailles : `TailleEcran.sunmiV2s` (720×1440, densité 2), `.sunmiV3` (1080×1920, 2,625), `.telephone` (360×640 dp),
`.telephone360x800` (1080×2400, densité 3 : 360×800 dp, ajouté en 4.0.1), `.tablette` (1920×1200, 1,5).
`preparer` lit aussi le réglage « Taille de l'écran » (`TailleEcranReglage.charger()`, clé `taille_ecran_v1`) comme
`main()` : **sur les petits écrans (V2s, V3, 360×640 dp), Automatique applique Compact** — l'interface voit 400 dp de
large (voir `docs/TAILLE_ECRAN.md`). Le `TailleEcran` des tests (appareil simulé) n'est pas l'énumération
`TailleEcran` de `lib/ui/taille_ecran.dart` : importer celle-ci avec un préfixe (`as ecran`).

### Contrôles d'ergonomie — `ergonomie.dart`

`verifierEcran` : rendu sans exception, cibles tactiles (`androidTapTargetGuideline` à la taille normale ; interface
réduite — Compact automatique des petits écrans, Compact, Très compact — : 48 dp **de l'interface**, soit 48 × facteur
dp réels, `ciblesTactiles(facteurEcran(t))`), `textContrastGuideline` (aussi contrôlé à 0,9 et 0,8), charte (en-têtes et
barres jamais en lavande Material par défaut ; bleu nuit `Pal.navy` pour les écrans de la nouvelle interface ;
fenêtres ouvertes — dialogues, feuilles du bas, messages — sur fond blanc, sans surface, texte ni icône lavande :
`verifierFenetresCharte`),
champ de saisie visible au-dessus du clavier (`viewInsets` à 40 % de la hauteur). Aucune capture de référence
(golden) : seulement des règles mesurables.

## Ajouter les tests d'un nouvel écran

1. **Unitaires** : règles de saisie et lecture tolérante du JSON dans un fichier `test/<module>_test.dart`.
2. **Intégration** : le client du module contre `FauxServeurPrestige` (`demarrer()` + `avecVraiHttp`) : 200,
   `success:false`, 401, 403, 5xx, délai, coupure ; ajouter ses routes fictives à `activerModules()` si l'écran est
   ouvert depuis l'accueil.
3. **E2E** : si l'écran est un menu, l'ajouter à `principaux` dans `e2e_parcours_test.dart` (ouverture puis retour
   dans les trois présentations) ; droits éventuels dans le groupe « droits ».
4. **Ergonomie** : ajouter un `EcranControle` à la liste `ecransErgonomie` de `test/outils/ecrans_ergonomie.dart`
   (contrôlée par `ergonomie_test.dart` et, aux trois tailles d'écran sur V2s, par `ergonomie_taille_ecran_test.dart`) (`ouvrir`, `champ` et
   `avantSaisie` pour un écran de saisie, `charte: true` pour un écran de la nouvelle interface).
5. **CI** : ajouter le fichier à la ligne 32 de `.github/workflows/build-apk.yml` (le garde-fou le rappelle).
6. Données **fictives** seulement ; pas de golden ; vérifier `flutter analyze lib test`.

## Seuils de performance

Seuils dans `Seuils` (`test/outils/performance.dart`) ; une mesure au-delà fait échouer la CI. Temps : temps
**réels** du test en mode test (JIT, assertions), suite complète en parallèle (un fichier par cœur) — ce sont des
seuils de **non-régression**, pas des temps du terminal. Marge ≈ ×3 sur la valeur la plus lente mesurée (PC Linux
4 cœurs, suite complète en parallèle, et CI GitHub : voir le rapport `rapport-tests` de chaque run). Requêtes :
plafond = fonctionnement voulu, **sans marge**. Un seuil ne se relève qu'avec une justification écrite ici.

| Mesure | Seuil | Mesuré (suite en parallèle) |
|---|---:|---:|
| Démarrage → écran de connexion, à froid | 6 000 ms | 1,5 – 2,0 s |
| Démarrage : requêtes (licence + test du serveur) | 2 | 2 |
| Connexion → accueil A / B / C | 3 500 ms | 0,6 – 2,0 s |
| Accueil : pire image en parcourant la page (2e passage) | 250 ms | 17 – 117 ms |
| Connexion + accueil : requêtes (4.3.0 : ANO-09 traitée, 2 doubles gardés exprès, + droit Posos ; 4.5.1 : + GET /user/droits, droits de vente lus à chaque connexion — demande de sécurité du serveur du 19/10/2026) | 25 | 25 |
| Longue liste : pire image, 1er passage (à froid) | 500 ms | 25 – 96 ms |
| Longue liste : pire image, 2e passage | 150 ms | 21 – 48 ms |
| Longue liste : 90 % des images, 2e passage | 80 ms | 6 – 23 ms |
| Ouverture d'une longue liste / 1re page de résultats | 3 000 ms | 0,15 – 0,4 s |
| Recherche Article 500 produits : requêtes (pages de 50) | 10 | 10 |
| Préventes à encaisser (200) : requêtes à l'ouverture | 1 | 1 |
| Vente : ajout d'une ligne (moyenne sur 50) | 600 ms | 200 – 240 ms |
| Vente : pire image pendant l'ajout de 50 lignes | 900 ms | 120 – 306 ms |
| Vente : requêtes par ligne (recherche, ajout, lignes, net) | 4 (200 pour 50) | 4 |
| Recherche tapée vite (Vente, accueil, Recherche Article, Analyse article, État de Stock) | 1 | 1 |
| Analyse article : ouverture / détail du produit choisi | 0 / 1 | 0 / 1 |
| Fiche produit : ouverture (`/info` + images) / réouverture < 60 s | 2 / 0 | 2 / 0 |
| État de Stock : ouverture (rayons, grossistes) | 2 | 2 |
| Encaissement d'une vente (modes, QR, client, clôture, préventes) | 5, dont 1 clôture | 5 |
| Synchro hors ligne : par prévente d'une ligne | 5 (15 pour 3) | 5 |
| Classement par code de 5 000 produits (20 saisies), meilleur de 3 | 400 ms | 70 – 83 ms |
| 100 tickets de vente (Sunmi simulée), meilleur de 3 | 2 500 ms | 0,6 – 1,0 s |
| 100 tickets de la borne, meilleur de 3 | 100 ms | 4 – 7 ms |
| Empreintes : 1re synchronisation, 50 employés × 3 gabarits (4.4.0), meilleur de 3 | 500 ms | 3 – 10 ms |
| Empreintes : synchronisation sans changement (1 requête) | 100 ms | 0 – 2 ms |
| Empreintes : identification 1:N sur 150 modèles (lecteur simulé) | 100 ms | 0 – 2 ms |
| Prestige Pointage : 2 000 requêtes signées + 20 photos de 60 Ko (1.0.0), meilleur de 3 | 1 500 ms | 70 ms |
| Prestige Pointage : copie de 2 000 employés par la route signée | 1 500 ms | 120 ms |
| Prestige Pointage : 2 000 badges lus (numéro et QR ; recherche linéaire de la 4.6.2), aucune requête | 2 000 ms | 630 ms |

## Ajouter les tests de performance et réseau d'un nouvel écran

1. **Temps d'affichage et défilement** : dans `test/performance/listes_longues_test.dart` (ou un nouveau fichier
   `test/performance/<module>_test.dart`), ouvrir l'écran avec une longue liste fictive (application entière via
   `AppE2E` + `CatalogueFictif`, ou l'écran seul avec `FauxServeurPrestige(exigerSession: false)..installerEnMemoire()`),
   puis `mesurerDefilement(t, 'Nom')` : deux passages, seuils `imageFroideMs` / `imageDefilementMs` / `imageCouranteMs`.
2. **Requêtes** : dans `requetes_test.dart`, entourer l'ouverture et chaque action de `compterRequetes(...)` et
   `mesurer('Requêtes — …', n, seuil: <nombre voulu>, unite: 'requêtes', detail: detailRequetes(rs))`. Plafond =
   fonctionnement voulu **sans marge** ; justifier chaque requête dans un commentaire (ex. « rayons (1) + grossistes (1) »).
3. **Serveur lent** : dans `test/reseau/serveur_lent_test.dart`, ralentir la route (`ralentir(serveur, 'GET /x', d)`)
   pour 2 / 5 / 8 s et appeler `attendreServeurLent(t, d, 'Écran', attendu: <indicateur>, pendant: <second toucher>)` :
   indicateur visible et aucune erreur à chaque pas de 250 ms, puis vérifier le résultat et l'absence de double envoi
   (compter les requêtes d'écriture).
4. **Réponses illisibles** : ajouter l'écran à `reponses_tronquees_test.dart` (boucle `pannes` : JSON partiel et
   connexion coupée) : message d'erreur + « Réessayer », jamais une liste vide ; puis la réponse correcte.
5. **Catégorie** : ajouter le fichier à la ligne 32 de la CI **et** à `test/categories.json` (le garde-fou le rappelle).
6. Seuil nouveau : le calibrer sur la CI (valeur du rapport `rapport-tests`), marge ≈ ×3 pour un temps, et l'écrire
   dans `Seuils` et dans le tableau « Seuils de performance » ci-dessous.

## Anomalies

| Id | Description | État |
|---|---|---|
| ANO-01 | Surveillance du serveur : au lancement, le ping de 30 s ne démarrait pas (la surveillance démarre avant d'être reliée au serveur) ; la perte du serveur n'était détectée qu'au premier échec d'une opération. | **Corrigée** (`ServerMonitor.pingBranche`, appelé par `HorsLigne.bind`) — `non_regression_test` |
| ANO-02 | Puce « Début / Contient » (`lib/services/search_mode.dart`) haute de 32 dp (< 48) dans la vente et la recherche globale. | **Corrigée** (4.0.2 : zone tactile ≥ 48 × 48 dp autour de la puce, aspect inchangé ; rendu 360 px `responsive_reference_360.json` identique) — `non_regression_test`, contrôle « cibles » réactivé pour `vente` et `recherche_globale` (`ergonomie_test`, `ergonomie_taille_ecran_test`) |
| ANO-03 | Onglet unique « Fiche client » (`SegmentedPills`, widget partagé des présentations) haut de 40 dp (< 48). | Signalée — contrôle « cibles » sauté pour `ordonnances_clients` et `fiche_client` |
| ANO-04 | Réserve : boutons « Préparer » / « Voir les suggestions » hauts de 44 dp. | **Corrigée** (48 dp) — `non_regression_test`, `ergonomie_test` |
| ANO-05 | Réserve : texte du bandeau du sens (« Réserve → Rayon : … ») au contraste 4,47:1 (< 4,5). | **Corrigée** (texte assombri de 20 %) — `non_regression_test`, `ergonomie_test` |
| ANO-06 | Vente : pied affiché au-dessus du clavier (`vente-pied-clavier`) déborde de 27 px à droite sur 360 dp de large avec un texte agrandi à 130 %. | Signalée — **4.0.1 : n'apparaît plus sur Sunmi V2s / V3 ni 360×640 dp** (Compact automatique : 400 dp) ; reste sur les téléphones de 360 dp à la taille normale : contrôle « clavier » sauté sur Téléphone 1080×2400 (360×800 dp), texte ×1,3 |
| ANO-07 | Réserve : pastille du sens (`SensBadge`) déborde de 35 px dans la saisie de quantité sur 360 dp de large avec un texte à 130 %. Widget aussi utilisé dans des lignes sans largeur bornée : correction à faire avec prudence. | Signalée — **4.0.1 : n'apparaît plus sur Sunmi V2s / V3 ni 360×640 dp** (Compact automatique) ; contrôle « clavier » sauté sur Téléphone 1080×2400 (360×800 dp), texte ×1,3 |
| ANO-08 | Interface d'origine (`AncienSplashScreen`) : la 1re vérification de licence partait vers `http://localhost:8080` (ApiService créé à la 1re image avant la lecture des réglages, recréé par le ProxyProvider seulement à l'image suivante ; `Future.delayed(Duration.zero)` ne laisse passer aucune image) → « Serveur injoignable » au démarrage ; « Réessayer » fonctionnait. | **Corrigée** (4.0.2 : attente de la fin de l'image suivante si l'adresse n'est pas encore celle des réglages ; écran d'origine et nouvelle interface inchangés) — `non_regression_test` (1re requête = serveur configuré dans les deux interfaces ; sans configuration : aucune requête), démarrage « interface d'origine » réactivé dans `widget_test` |
| F1 | Configuration d'origine (`lib/screens/auth/settings_screen.dart`) : ligne « Type de code ticket » débordant d'environ 132 px même sur tablette (et, sur 360 dp / Sunmi, « Largeur du ticket », « Mode test d'impression », « Comparaison Stock BL » texte ×1,3). | **Corrigée** (4.0.3 : choix sous le libellé quand ils ne tiennent pas côte à côte, mêmes valeurs) — `configuration_origine`, exception retirée de `non_regression_test` (« sans configuration »), `version_affichee_test`, `ergonomie_taille_ecran_test` |
| F3 | Recherche Article / Évaluation Vente : début de CIP pas en première ligne (serveur : nom, CIP et EAN « commence par », trié par nom ; appli : ordre affiché tel quel, 1re ligne de `/info?search=CIP` prise pour les détails). | **Corrigée** (4.0.3 : `lib/services/classement_code.dart`, aussi recherche de l'accueil et Analyse article) — `recherche_debut_cip` |

| ANO-09 | Connexion → accueil : lectures EN DOUBLE (même route, mêmes paramètres) : `GET /officine` ×3, `GET /ventestats/preventes` ×2, `GET /commande/list-bons` (BL du jour) ×2, `GET /modereglement/all` ×2 — chargements après la connexion puis de l'accueil (26 requêtes au lieu de 21). Sans effet visible, du trafic en plus sur un réseau lent. | **Traitée** (4.3.0) — **supprimés** : officine relue par l'accueil (déjà lue par la connexion qui l'ouvre : marque à usage unique, tout autre accueil relit), préventes et BL du jour lus par la connexion puis relus aussitôt par le nouvel accueil (lus par l'accueil seulement ; accueil d'origine inchangé). **Gardés exprès** : `GET /officine` du test « serveur joignable » de l'accueil (état à l'instant de l'affichage, résultat différent : joignable ou non) et `GET /modereglement/all` de la copie hors ligne (copie complète du catalogue, autre client HTTP, autre moment ; la lecture de la connexion sert la session et le hors ligne de l'ancienne vente). Plafond 24 (26 − 3 + `GET /posos/droits`) ; test « aucune lecture en double sauf les 2 gardées » actif (`performance/demarrage`) |
| ANO-12 | Réception BL : texte de progression « n/N lignes · x/y boîtes » débordant de 62 px sur 360 dp avec un texte agrandi ×1,3 (constaté par le test d'ergonomie de D18). | **Corrigée** (4.3.1 : texte borné, points de suspension ; rendu inchangé quand il tient, `responsive_reference_360.json` identique) — `reception_bl` (« D18 ergonomie ») |
| ANO-11 | Borne, présentation grille, tablette 1280×800 avec texte agrandi ×1,3 : cartes produits trop basses (débordement de 60 px) et ligne prix / bouton trop étroite. | **Corrigée** (4.3.0 : hauteur des cartes et nombre de colonnes adaptés au texte agrandi, rendu à la taille normale inchangé) — `borne_test` (« Message Ajouté… » aux 3 tailles × 2 échelles) |
| ANO-10 | Vente : pendant la création de la vente (1er article, `POST /vente/add/vno`), aucun indicateur : sur un serveur lent (2 à 8 s), le panier restait « vide » sans rien afficher. | **Corrigée** (4.2.1 : bandeau « Envoi au serveur… » dès le 1er article en ligne ; aucune vente en double) — `reseau/serveur_lent` |
| Instable | `retours_accueil_test` « douchette sur l'accueil : EAN-13 → fiche » échouait parfois en lancement groupé : l'accueil mesurait l'écart entre deux touches de la douchette à l'heure **réelle** (`DateTime.now()`, 400 ms au plus) ; une machine chargée qui suspend le processus plus de 400 ms au milieu du code tronquait le code (reproduit en suspendant le test 450 ms). | **Corrigée** (4.2.1 : `clock.now()` — heure réelle sur le terminal, temps simulé en test ; cache des fiches vidé entre les tests) — `retours_accueil_test` (« machine chargée », « règle conservée ») |

Les écrans touchés restent contrôlés pour tous les autres critères et toutes les autres configurations : seul le
contrôle concerné est sauté, dans un test marqué « sauté : ANO-xx » (voir `anomaliesErgonomie` dans
`test/outils/ergonomie.dart`).
