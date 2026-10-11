# O5 — Lecture avancée des ordonnances (`/app-vente/ordonnances/lecture-avancee`) : patch serveur Prestige

> Pour le développeur Prestige. Patch : `docs/serveur/O5_lecture_avancee.patch` (un commit, à appliquer avec `git am`
> **après** H4, H5 et O4 ; ordre H4 → H5 → O4 → O5 → B3). Construit sur `o4u2` (= `origin/claude/new-session-xm8ptu`
> à jour `b9e03367` + H4 + H5 + O4) ; compilé (`mvn -o compile`, JDK 11). **Rien n'a été poussé sur le dépôt
> `airm5500/prestige`.** Voir § 0.

## 0. Mise à jour du 11/10/2026 : préfixe `v1/app-vente/`, filtre non modifié, migrations renumérotées

**Ce qui change par rapport à la version précédente de ce patch** (les 4 patchs H4, H5, O4, O5 ont été refaits ensemble) :

- **Routes déplacées** de `v1/mobile/…` vers le préfixe unique **`v1/app-vente/…`** :

  | Avant | Maintenant |
  |---|---|
  | `GET v1/mobile/capacites` | `GET v1/app-vente/capacites` |
  | `GET v1/mobile/client-ref/{ref}` (H4) | `GET v1/app-vente/client-ref/{ref}` |
  | `GET v1/mobile/catalogue/changements` (H5) | `GET v1/app-vente/catalogue/changements` |
  | `POST/GET v1/mobile/ordonnances/corrections` (O4) | `POST/GET v1/app-vente/ordonnances/corrections` |
  | `POST v1/mobile/ordonnances/lecture-avancee` (O5) | `POST v1/app-vente/ordonnances/lecture-avancee` |

  L'en-tête `X-Client-Ref` (H4) sur `v1/vente/add/*` et `v1/retourfournisseur/new` ne change pas.
- **`filter/AuthenticationFilter.java` n'est plus modifié** par aucun des 4 patchs. Sur la branche à jour, le préfixe
  `v1/mobile/` est réservé à l'API mobile à jeton Bearer (`AuthenticationFilter`, `MobileRessource`) ; les anciennes
  versions devaient y ajouter des exceptions. Les routes `v1/app-vente/` suivent simplement le contrôle de **session
  habituel** (cookie, ou `X-User-Info`/`X-Token-Exp`), comme le reste de l'application (`v1/vente/…`). Sans session : 401.
- **Pas de collision** : aucune ressource existante ne commence par `v1/app-vente` (la plus proche est
  `v1/app-params`, chemin distinct) et le préfixe n'est pas dans `SKIP_PATHS` (aucun accès public).
- **Migrations renumérotées** au-dessus de la dernière migration amont (`V6.9.132__types_etiquette_par_produit.sql`) :
  `6.9.129.1 → 6.9.132.1` (H4), `6.9.129.2 → 6.9.132.2` (H5), `6.9.129.3 → 6.9.132.3` (O4), `6.9.129.4 → 6.9.132.4` (O5).
  **Ces patchs n'ont encore été appliqués chez aucun client : aucune migration à défaire.** (Sur un serveur de test qui
  aurait déjà joué les anciens numéros, les nouveaux scripts sont rejouables — `CREATE TABLE IF NOT EXISTS`, index
  créés s'ils manquent — et Flyway est configuré avec `ignoreMissingMigrations(true)` : rien à faire.)
- **Ordre d'application** (chaque patch s'applique sur le précédent) : **H4 → H5 → O4 → O5 → B3**, sur
  `origin/claude/new-session-xm8ptu` à jour (`b9e03367`). `git apply --check` vérifié pour chacun, dans cet ordre,
  sur `b9e03367` : H4 OK, H5 OK, O4 OK, O5 OK, puis `B3_paiements_mobile.patch` OK (B3 utilise ses propres routes
  `v1/paiements-mobile/…`, indépendantes). Résultat identique, fichier pour fichier, aux branches locales de
  vérification ; chaque étape compile (`mvn -o compile`, JDK 11). Branches locales (non poussées) :
  `h4u2` `20e2ef0b`, `h5u2` `fc56cb7e`, `o4u2` `820ce988`, `o5u2` `35ce0172`.
- **Application** : Prestige Mobile appelle d'abord `v1/app-vente/capacites`, puis, en repli, l'ancien
  `v1/mobile/capacites` (serveur portant encore les anciens patchs) ; il utilise ensuite le préfixe de la route qui a
  répondu. Si aucune ne répond (serveur non patché : 404, ou 401 « expire » de l'API à jeton), les fonctions restent
  désactivées comme avant.

## 1. Quoi

| Élément | Détail |
|---|---|
| Route | `POST v1/app-vente/ordonnances/lecture-avancee`, corps = **image JPEG** (`Content-Type: image/jpeg`) de la seule **zone des médicaments**, recadrée, masquée et sans métadonnées par le téléphone ; 4 Mo au plus. |
| Réponse | `{success, lignes:[{nom, dosage, forme, posologie, quantite, confiance}], fournisseur, modele, coutEstime, quotaRestant}` |
| Erreurs | sans session 401 ; non configurée / migration absente 503 ; pas un JPEG 400 ; trop grande 413 ; quota du jour atteint ou lecture déjà en cours 429 ; erreur ou refus du fournisseur 502 ; délai dépassé 504. Aucun message ne recopie la réponse du fournisseur. |
| Capacité | `GET v1/app-vente/capacites` → `lectureAvancee:true, lectureAvanceeVersion:1` **seulement si un fournisseur est configuré** (clé présente) et la migration passée. Sinon `false` : le téléphone n'affiche pas le bouton. |
| Fournisseurs | interface `FournisseurLecture` : **Claude** (Messages API, par défaut, modèle `claude-haiku-5-5` pour le coût, `claude-opus-5-5` possible) ; **Google Cloud Vision** (`images:annotate`, `DOCUMENT_TEXT_DETECTION`) ; d'autres s'ajoutent en implémentant l'interface (ex. Posos, voir § 8). |
| Garde-fous | une seule lecture à la fois (sémaphore ; une 2ᵉ demande attend 2 s puis 429) ; délai maximal (30 s par défaut) ; **aucune relance automatique** ; quota par jour pour toute l'officine (50 par défaut). |
| Données | l'image **n'est jamais enregistrée** (ni disque, ni base, ni journal) : elle n'existe qu'en mémoire pendant l'appel. Le fournisseur reçoit une consigne : seulement les médicaments, jamais nom, date, adresse, téléphone. Le serveur filtre encore la réponse (`LignesLues` : lignes « Dr / Mme / Patient / Nom / date / téléphone / e-mail » retirées, longueurs bornées, 30 lignes au plus). |
| Journal | table `mobile_lecture_avancee_journal` (date, utilisateur, taille, fournisseur, modèle, résultat `ok / echec / delai / quota / occupe`, nombre de lignes, jetons d'entrée / sortie, **coût estimé**, durée) + une ligne `INFO` dans `server.log` ; **ni image ni texte lu**. Sert aussi au quota. |
| Authentification | session habituelle de l'application (cookie) ; préfixe `v1/app-vente/`, aucune modification du filtre (voir § 0). |
| Migration | `V6.9.132.4__mobile_lecture_avancee.sql` : table du journal (aucune table existante modifiée). |

Fichiers du patch : `rest/service/mobile/MobileLectureAvanceeService.java`, `rest/service/mobile/lecture/`
(`LectureAvanceeConfiguration`, `FournisseurLecture`, `FournisseurClaude`, `FournisseurGoogleVision`, `LignesLues`),
`rest/MobileOrdonnanceRessource.java` (route), `rest/MobileCapacitesRessource.java` (capacité), migration.

## 2. Configurer la vraie clé (aucune clé dans l'application ni dans Git)

Même règle que la passerelle Posos : lue dans l'ordre **variable d'environnement** du serveur, **propriété système**
de la JVM (même nom), puis fichier **`lecture-avancee.properties`** dans le dossier de configuration de Prestige (celui
de `dicisms.properties` : `D:\prestige\config` sous Windows ; `LECTURE_AVANCEE_CONFIG_FILE` pour un autre chemin).
Relue à chaque lecture : pas de redémarrage nécessaire.

```properties
# lecture-avancee.properties (droits de lecture réservés au compte du serveur)
LECTURE_AVANCEE_FOURNISSEUR=claude          # claude | google | aucun
LECTURE_AVANCEE_CLE=sk-ant-...              # clé d'API Anthropic (console.anthropic.com), jamais renvoyée
LECTURE_AVANCEE_MODELE=claude-haiku-5-5     # défaut (coût) ; claude-opus-5-5 pour la meilleure lecture
LECTURE_AVANCEE_QUOTA_JOUR=50               # lectures par jour, toute l'officine
LECTURE_AVANCEE_DELAI_MS=30000              # délai maximal d'une lecture
# LECTURE_AVANCEE_PRIX_ENTREE=0.10          # $ / million de jetons (coût estimé journalisé ; défaut : tarif du modèle)
# LECTURE_AVANCEE_PRIX_SORTIE=0.50
# LECTURE_AVANCEE_URL=...                   # autre adresse (essais : faux fournisseur local http://127.0.0.1:9099/v1/messages)
```

Google Cloud Vision : `LECTURE_AVANCEE_FOURNISSEUR=google`, `LECTURE_AVANCEE_CLE=<clé d'API Google>` (API Cloud
Vision activée sur le projet). Vision rend le texte de la zone (pas des médicaments structurés) : le téléphone le
découpe et le rapproche du catalogue comme une lecture ML Kit.

Sans clé (et sans adresse locale de faux service), `lectureAvancee` reste `false` : rien ne change.

**Appel Claude** (HTTP direct `java.net.http`, le SDK Java officiel n'étant pas une dépendance de Prestige) :
`POST https://api.anthropic.com/v1/messages`, en-têtes `x-api-key`, `anthropic-version: 2023-06-01` ; corps :
consigne en `system`, message utilisateur `[image base64 image/jpeg, texte]`, `output_config: {effort: "low",
format: {type: "json_schema", schema: {lignes: [...]}}}` (sortie JSON garantie conforme au schéma), `max_tokens`
4000. `stop_reason: "refusal"` → 502 « lecture refusée par le service » (pas de relance) ; `usage.input_tokens` /
`output_tokens` → coût estimé (Claude Haiku 5.5 : 0,10 $ / 0,50 $ par million de jetons ; ≈ 0,0002 $ par lecture
d'une zone de 1 100 × 600 px dans l'essai).

## 3. Protection des données (rappel du parcours complet)

- **Téléphone** : désactivée par défaut ; activation dans Réglages › Ventes (code administrateur) après un écran de
  consentement (données de santé, service externe, coût) ; à chaque ordonnance : zone des médicaments **obligatoire**
  (page entière refusée), bandes haut (18 %) / bas (12 %) de la page masquées automatiquement, masques à la main,
  image réduite (1 600 px), JPEG **sans EXIF**, **aperçu de l'image exacte** et confirmation « Envoyer cette zone
  pour lecture avancée ? » ; hors ligne : bouton désactivé « disponible en ligne uniquement » ; journal du terminal
  (date, utilisateur, taille, résultat ; pas d'image).
- **Serveur** : clé jamais exposée, image jamais stockée, consigne « médicaments seulement », filtrage de la
  réponse, journal sans image ni texte, quota.
- **Fournisseur** : n'est appelé qu'avec la zone masquée ; vérifier les conditions de conservation des données du
  fournisseur choisi (contrat de l'officine).

## 4. Appliquer

```bash
git checkout claude/new-session-xm8ptu        # à jour (b9e03367) ou la branche de travail
git am docs/serveur/H4_client_ref.patch \
       docs/serveur/H5_catalogue_delta.patch \
       docs/serveur/O4_corrections_ordonnances.patch \
       docs/serveur/O5_lecture_avancee.patch \
       docs/serveur/B3_paiements_mobile.patch          # dans cet ordre ; s'arrêter au patch voulu
mvn -DskipTests package                       # JDK 11
asadmin redeploy --name prestige --contextroot prestige target/prestige.war
```

Au démarrage : version `6.9.132.4` dans `flyway_schema_history`. Puis déposer `lecture-avancee.properties`.

## 5. Tester (curl)

```bash
B=http://localhost:8080/prestige/api/v1
curl -s -b cj $B/app-vente/capacites                       # …"lectureAvancee":true…
curl -s -b cj -H 'Content-Type: image/jpeg' --data-binary @zone.jpg $B/app-vente/ordonnances/lecture-avancee
```

**Vérifié sur le serveur de test** (11/10/2026), faux fournisseur local imitant la Messages API (script
`mock_claude.py`, modes ok / lent / erreur / refus / patient ; il ne garde que la taille et la présence des
en-têtes), image **synthétique** (texte imprimé imitant une ordonnance, aucune personne réelle) :

| Cas | Résultat |
|---|---|
| sans configuration | `lectureAvancee:false` ; POST → 503 |
| faux fournisseur configuré (fichier) | `lectureAvancee:true`, sans redémarrage |
| sans session | 401 |
| corps non JPEG | 400 |
| lecture | 200, 2 lignes (Curam 1 g cp, Brustan 400 mg cp), `modele: claude-haiku-5-5`, `coutEstime: 0.000195`, `quotaRestant` ; reçu par le fournisseur : `anthropic-version: 2023-06-01`, `output_config.format: json_schema`, JPEG de 47 944 octets **sans EXIF** |
| le fournisseur renvoie une ligne « Patient : … » | retirée par le serveur |
| fournisseur lent (> délai 3 s) | 504 « délai dépassé » (aucune relance) |
| 2 envois simultanés | le 2ᵉ : 429 « déjà en cours » |
| fournisseur en erreur 500 / refus | 502 / 502 « lecture refusée » |
| quota (6) atteint | 429 « Quota … atteint (6) » |
| journal | 9 lignes (ok, delai, occupe, echec, quota…) avec taille, jetons, coût, durée ; colonnes sans image ni texte |
| image non stockée | aucun fichier JPEG créé (domaine Payara, `/root/prestige`, `/tmp`) ; `server.log` ne contient pas l'image (base64) |

Le journal de test a été vidé et la configuration retirée du serveur de test.

## 6. Rétrocompatibilité

- Ancien téléphone → serveur patché : rien ne change (route nouvelle, `capacites` ajoute des champs).
- Téléphone à jour → serveur sans O5 ou non configuré : `lectureAvancee` absent / `false` → bouton absent.

## 7. Ce qui existait déjà (branche `315a40b7`)

- **Posos** (`rest/service/posos/…`, `v1/posos/…`, `v1/ordonnance-client/scans/{id}/lire`) : lecture d'une ordonnance
  scannée au poste via le service Posos quand il est configuré (`posos.properties`, même dossier) ; le scan est
  **gardé** comme pièce justificative d'une ordonnance client (`t_ordonnance_scan`) et la route demande le privilège
  `P_ORDONNANCE_CLIENT_MAJ`. O5 n'enregistre rien et sert le téléphone : il **réutilise la même règle de
  configuration** (environnement → propriété système → fichier du dossier de configuration via
  `util.StockageDisque`), sans dépendre de Posos.
- Pas de route `v1/app-vente/ordonnances/lecture-avancee` ni de table de journal équivalente ; pas de collision avec
  `MobileRessource` (`connexion`, `moi`, `pointages`, `produits`).

## 8. Évolutions possibles

- Fournisseur **Posos** pour O5 : implémenter `FournisseurLecture` en appelant `PososService` (lecture d'image) sur
  une branche qui contient Posos, puis `LECTURE_AVANCEE_FOURNISSEUR=posos`.
- Si le SDK Java d'Anthropic peut être ajouté aux dépendances (`com.anthropic:anthropic-java`), `FournisseurClaude`
  peut l'utiliser à la place de l'appel HTTP direct (même requête).
