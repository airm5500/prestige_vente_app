# Tests de Prestige Mobile

Socle de tests exigé pour chaque application : **unitaires**, **intégration**, **e2e**, **ergonomie et cohérence
d'affichage**, **non-régression**. Tout s'exécute avec `flutter test` sur Linux (CI GitHub), **sans émulateur ni
téléphone**, contre des **données fictives** uniquement (aucun vrai patient, aucune vraie pharmacie).

## Lancer les tests

```bash
# Toute la suite de la CI (liste explicite, ligne 32 de .github/workflows/build-apk.yml)
flutter test $(sed -n 32p .github/workflows/build-apk.yml | sed 's/.*flutter test //')

# Un fichier, ou un test précis
flutter test test/e2e_parcours_test.dart
flutter test test/ergonomie_test.dart --plain-name "Sunmi V2s 720×1440, texte ×1.3"
```

La CI liste **explicitement** chaque fichier (ligne 32). `test/non_regression_test.dart` échoue si un fichier
`test/**/*_test.dart` n'y figure pas (seule exception déclarée : `test/outils/apercus_connexion_test.dart`, outil
manuel qui génère des aperçus PNG avec `APERCUS=1`).

## Catégories

| Catégorie | Ce qui est vérifié | Fichiers |
|---|---|---|
| **Unitaires** | règles et modèles sans écran : lecture DataMatrix / étiquettes / OCR, ordonnances (O1–O5), paiements, codes et identifiants sécurisés, droits, réserve, posologie, fiche client, journal, licence… | `datamatrix_parser`, `label_text_parser`, `ocr_rows`, `camera_scan_value`, `fingerprint_diagnostic`, `licence_lookup`, `pointage_analytics`, `ordonnances_*`, `paiement_multiple`, `modes_paiement_logo`, `securite_*`, `routes_app_vente`, `product_lookup`, parties « modèles / règles » de `reserve`, `posos`, `fiche_client`, `droits_modules`, `stock_reserve` (dont F2 : seuil réserve à 0 = non défini), `taille_ecran` (taille de l'écran : seuil petit écran, choix manuel prioritaire, persistance, impression et caméra non affectées), `recherche_debut_cip` (partie unitaire, 4.0.3 F3 : classement par début de code — exact, CIP, CIP13 / CIP7 / EAN —, choix de la ligne `/info` du même CIP, `PagedProductSearch`) |
| **Écrans (widgets)** | chaque écran isolé avec un faux service : présentations A / B / C, 360 px, tablette, messages d'erreur, anti double appui | `presentation_*`, `ventes_*`, `accueil_*`, `parametres`, `recherche_*`, `reception_bl`, `retour_frs`, `borne`, `connexion_lancement`, `scan_fiche_analyse`, `vente_clavier`, `retours_*`, `pointage_*`, `rh_pointage`, `horsligne_*`, `journal_terminal`, `support_centre`, `images_produits`, `paiements_mobile`, `version_affichee` (version X.Y.Z+N lue à l'exécution : connexion, Réglages), parties « écran » de `reserve`, `posos`, `fiche_client` |
| **Intégration** | vrais clients HTTP de l'application contre un serveur simulé (vrai HTTP local ou en mémoire) | `integration_services` (ApiService, licence, connexion, préventes, BL, analyse article, AuthProvider, passerelle de vente), `client_prestige`, `client_prestige_session`, `reserve`, `posos`, `fiche_client`, `droits_modules` (parties « serveur local »), `session_expiree`, `session_renouvelee`, `pointage_photo_integration`, `faux_serveur_prestige` (auto-contrôle du simulateur) |
| **E2E** | application ENTIÈRE (`MyApp`, vrais providers, vrai Dio, intercepteur de session, surveillance du serveur) reliée au faux serveur Prestige en mémoire | `e2e_parcours`, `widget_test` (démarrage), `recherche_debut_cip` (4.0.3 F3 : « 3595 » dans Recherche Article et Évaluation Vente en Début / Contient — liste et détails du produit choisi —, Analyse article, recherche de l'accueil, contre des réponses triées par nom comme le serveur) |
| **Ergonomie / cohérence d'affichage** | 18 écrans × 5 tailles × 2 échelles de texte : débordements, cibles ≥ 48 dp, contraste, charte, clavier (petits écrans en Compact automatique, 4.0.1) ; Sunmi V2s aux 3 tailles d'écran (Automatique / Compact / Très compact), vente clavier ouvert, douchette, autres appareils en Automatique, réglage dans les deux interfaces ; Configuration d'origine (4.0.3 F1) sans débordement aux 5 tailles × texte 1,0 / 1,3 | `ergonomie`, `ergonomie_taille_ecran`, `configuration_origine` (+ `responsive` : rendu à 360 px figé par `responsive_reference_360.json`) |
| **Non-régression** | garde-fou de la liste CI ; anomalies corrigées (ANO-01, 02, 04, 05, 08) ; versions alignées sur le magasin Sunmi (`docs/VERSIONS_SUNMI.md` : pubspec.yaml ≥ version publiée, +N > versionCode publié, aucun numéro en dur dans Gradle) ; ensemble de la suite verte | `non_regression`, `version_sunmi` + toute la liste CI |

## Parcours clés et couverture

| Parcours | Couverture |
|---|---|
| Lancement : réglages → serveur → licence | e2e (`Lancement et licence`), `connexion_lancement`, `widget_test` |
| Licence : serveur injoignable, 5xx, 401, 403 « Veuillez vous connecter » ≠ « aucune licence » ; licence absente / expirée | e2e, `integration_services`, `licence_lookup` |
| Connexion : identifiants, cookie JSESSIONID **renouvelé** (l'ancien n'est plus envoyé) | e2e (`Connexion`), `session_renouvelee`, `integration_services` |
| Accueil : présentations A / B / C, cloche, favoris, recherche globale | e2e, `accueil_test`, `accueil_connexion`, `responsive` |
| Recherche par début de CIP (Recherche Article, Évaluation Vente, Analyse article, accueil) : bon produit en tête, détails du bon produit | `recherche_debut_cip` |
| Configuration d'origine (appareil non configuré, interface d'origine) | `configuration_origine`, `non_regression` (ANO-08) |
| Menus principaux ouverts puis retour (touche retour Android) : Vente, Recherche article, Analyse article, Fiche produit (par code), Analyse posologie, Ordonnances des clients / Fiche client (selon droits), Réserve (administrateur seulement), Pointage présence, Réglages | e2e (`Accueil : chaque menu principal…`, droits) |
| Session expirée en cours de route : reconnexion silencieuse si « Rester connecté », sinon écran de connexion avec « Votre session a expiré, reconnectez-vous » | e2e (`Session expirée`), `session_expiree` |
| Serveur coupé : « Connexion au serveur perdue » puis « De nouveau en ligne » | e2e (`Réseau`), `horsligne_test`, `accueil_connexion` |
| Vente hors ligne (prévente provisoire) puis envoi au retour du serveur après confirmation | e2e (`Réseau`), `horsligne_ventes`, `horsligne_h4` |
| Ventes comptant / assurance / carnet / dépôt, encaissement, paiement multiple | `ventes_*`, `presentation_depot_sale`, `paiement_multiple` |
| Réception BL, contrôle livraison / réception, pointage BL, retours fournisseur | `reception_bl`, `presentation_*`, `retour_frs`, `sync_load_errors` |
| Stock, périmés, péremption, ajustement, emplacement, EAN, réserve | `presentation_*`, `stock_reserve`, `reserve`, `horsligne_stock` |
| Pointage (local, badge, NFC, présence, photo de contrôle) | `pointage_*`, `rh_pointage`, `pointage_photo*` |
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
barres jamais en lavande Material par défaut ; bleu nuit `Pal.navy` pour les écrans de la nouvelle interface),
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

Les écrans touchés restent contrôlés pour tous les autres critères et toutes les autres configurations : seul le
contrôle concerné est sauté, dans un test marqué « sauté : ANO-xx » (voir `anomaliesErgonomie` dans
`test/outils/ergonomie.dart`).
