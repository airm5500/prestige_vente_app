# O4 — Apprentissages des ordonnances partagés (`/app-vente/ordonnances/corrections`) : patch serveur Prestige

> Pour le développeur Prestige. Patch : `docs/serveur/O4_corrections_ordonnances.patch` (un commit, à appliquer avec
> `git am` **après** H4 et H5, dont il complète la route `v1/app-vente/capacites` ; ordre H4 → H5 → O4 → O5 → B3).
> Construit sur `h5u2` (= `origin/claude/new-session-xm8ptu` à jour `b9e03367` + H4 + H5) ; compilé (`mvn -o compile`,
> JDK 11). **Rien n'a été poussé sur le dépôt `airm5500/prestige`.** Voir § 0.

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
| Envoi | `POST v1/app-vente/ordonnances/corrections` corps `{corrections:[{cle, segment, produitId, cip, nom, at}]}` (500 au plus) → `{success, recus, enregistres, dejaConnus, rejetes:[{cle, motif}], serveurMaintenant}` |
| Idempotence | `cle` (générée par le téléphone : `O4-<terminal>-<horodatage>-<aléa>`) = clé primaire ; `INSERT IGNORE` : un renvoi du même lot (réponse perdue, réseau coupé) n'ajoute rien (`dejaConnus`). Deux envois simultanés de la même clé n'en gardent qu'une. |
| Contrôles | `segment` : 3 à 60 caractères, uniquement `a-z 0-9 espace % / . , -` et au moins 3 lettres de suite ; `produitId` doit exister dans `t_famille` ; `cip` ≤ 20, `nom` ≤ 100. Une correction refusée est listée dans `rejetes` (motif), les autres du lot sont gardées. |
| Lecture différentielle | `GET v1/app-vente/ordonnances/corrections?depuis=<yyyy-MM-dd HH:mm:ss>[&jusqua=…]&start=0&limit=500` → `{success, depuis, serveurMaintenant, total, start, limit, data:[{cle, segment, produitId, cip, nom, at, recuLe}]}` ; `depuis` absent = tout ; tri par date de réception puis clé ; `limit` 500 par défaut, 2 000 au plus. Même principe que H5 : **horloge du serveur** (`serveurMaintenant` repassé en `jusqua` pour les pages suivantes, puis en `depuis` moins 2 min la fois suivante ; le téléphone ignore les clés déjà appliquées et les siennes). |
| Erreurs | sans session → 401 ; corps illisible / lot > 500 / `depuis` illisible → 400 ; table absente (migration non passée) → 503. |
| Capacité | `GET v1/app-vente/capacites` → `{…, ordonnanceCorrections:true, ordonnanceCorrectionsVersion:1}` (faux si la table n'existe pas). L'application ne partage que si `ordonnanceCorrections:true`. |
| Authentification | Session habituelle de l'application (cookie) ; préfixe `v1/app-vente/`, aucune modification du filtre (voir § 0). L'utilisateur connecté est noté (`lg_USER_ID`). |
| Migration | `V6.9.132.3__mobile_ordonnance_corrections.sql` : nouvelle table `mobile_ordonnance_correction` (aucune table existante modifiée). |

Fichiers du patch :

- `src/main/java/rest/service/mobile/MobileOrdonnanceCorrectionService.java` (nouveau, EJB `@Stateless`) ;
- `src/main/java/rest/MobileOrdonnanceRessource.java` (nouveau) ;
- `src/main/java/rest/MobileCapacitesRessource.java` : `ordonnanceCorrections`, `ordonnanceCorrectionsVersion` ;
- `filter/AuthenticationFilter.java` : **non modifié** ;
- `src/main/resources/db/migration/V6.9.132.3__mobile_ordonnance_corrections.sql`.

## 2. Pourquoi

Prestige Mobile lit les ordonnances manuscrites (étapes O1–O3). Quand le pharmacien valide ou corrige le produit
proposé pour une ligne, le téléphone retient « ce qui a été lu → le bon produit » et le propose en priorité la fois
suivante (O4, « entraînement continu » adapté à la pharmacie). Ce patch permet que ce qui est appris sur un
terminal profite aux autres terminaux de la pharmacie.

## 3. Données de santé / RGPD

- Le téléphone **n'envoie jamais le texte lu de l'ordonnance** : seulement le « segment médicament » de la ligne
  validée (nom, dosage, forme ; ex. `bnstou 400mg`), normalisé en minuscules sans accents, borné (4 mots,
  40 caractères), **sans** posologie, quantité, numéro de ligne.
- Le filtrage est fait **par le téléphone** : une ligne contenant une date, un numéro de téléphone, un e-mail, un
  long nombre ou un mot comme `Dr`, `Mme`, `Patient`, `Nom`, `Né le`, `Tél`, `BP`, `Clinique`… n'est pas apprise
  du tout. De plus, seule une ligne pour laquelle le pharmacien a validé un **produit** est apprise.
- Le serveur **ne peut pas** reconnaître un nom de personne écrit seul (« Kouassi ») : il borne la longueur et les
  caractères acceptés, refuse un produit inconnu, et ne stocke rien d'autre que la ligne de la table ci-dessous.
- Le partage est désactivable sur chaque téléphone (Réglages › Ventes › Ordonnances) ; il n'est actif par défaut
  que si le serveur annonce la capacité.

## 4. Script SQL de migration (idempotent)

Joué automatiquement par Flyway (`V6.9.132.3`, anciennement `6.9.129.3` — voir § 0 —, après `6.9.132.2` (H5) et la
dernière migration amont `6.9.132`) :

```sql
CREATE TABLE IF NOT EXISTS mobile_ordonnance_correction (
    cle           VARCHAR(64)  NOT NULL,
    segment       VARCHAR(60)  NOT NULL,
    lg_FAMILLE_ID VARCHAR(40)  NOT NULL,
    cip           VARCHAR(20)  NULL,
    nom           VARCHAR(100) NULL,
    lg_USER_ID    VARCHAR(40)  NULL,
    valide_le     DATETIME     NULL,   -- heure de validation sur le téléphone (indicative)
    recu_le       DATETIME     NOT NULL, -- horloge du serveur (curseur de la lecture différentielle)
    PRIMARY KEY (cle),
    KEY idx_mobile_ordo_corr_recu (recu_le, cle),
    KEY idx_mobile_ordo_corr_segment (segment)
) ENGINE = InnoDB DEFAULT CHARSET = utf8;
```

Purge éventuelle (non automatique) : `DELETE FROM mobile_ordonnance_correction WHERE recu_le < NOW() - INTERVAL 2 YEAR;`
(un téléphone qui repart de zéro relit alors seulement ce qui reste).

## 5. Appliquer

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

Au démarrage : version `6.9.132.3` dans `flyway_schema_history` ; `GET v1/app-vente/capacites` contient
`"ordonnanceCorrections":true`. En cas de conflit `git am`, seuls points touchés dans des fichiers existants : la
méthode `capacites()` de `MobileCapacitesRessource` (fichier créé par H4).

## 6. Tester (curl)

```bash
B=http://localhost:8080/prestige/api/v1
curl -s -c cj -H 'Content-Type: application/json' -d '{"login":"admin","password":"…"}' $B/user/auth
curl -s -b cj $B/app-vente/capacites            # …"ordonnanceCorrections":true…
curl -s -b cj -H 'Content-Type: application/json' \
  -d '{"corrections":[{"cle":"O4-test-1","segment":"bnstou 400mg","produitId":"<lg_FAMILLE_ID>","at":"2026-10-11 01:00:00"}]}' \
  $B/app-vente/ordonnances/corrections          # enregistres:1 ; le même envoi à nouveau : dejaConnus:1
curl -s -b cj -G --data-urlencode 'depuis=2026-10-11 00:00:00' $B/app-vente/ordonnances/corrections
curl -s $B/app-vente/ordonnances/corrections    # 401 (sans session)
```

**Vérifié sur le serveur de test** (11/10/2026, script curl) :

| Cas | Résultat |
|---|---|
| migration | `6.9.132.3` appliquée, table créée |
| capacités | `ordonnanceCorrections:true`, `ordonnanceCorrectionsVersion:1` (H4 / H5 inchangés) |
| sans session (POST / GET) | 401 / 401 |
| lot de 3 : 1 correcte, 1 « nom + téléphone » (`Jean Dupont 06 12 34 56 78`), 1 produit inconnu | `enregistres:1`, 2 `rejetes` (segment invalide ; produit inconnu) |
| même lot renvoyé | `enregistres:0, dejaConnus:1` (idempotent) |
| corps invalide / `depuis=hier` | 400 / 400 |
| différentiel `depuis` = juste avant l'envoi | 1 correction, `recuLe` = horloge du serveur |
| `depuis = serveurMaintenant` renvoyé | 0 |
| pagination `limit=1` avec `jusqua` | même résultat, `total` exact |

Les lignes de test ont été supprimées de la base du serveur de test.

## 7. Rétrocompatibilité

- **Ancien téléphone → serveur patché** : rien ne change (routes nouvelles ; `capacites` ne fait qu'ajouter des champs).
- **Téléphone à jour → serveur sans O4** : `capacites` sans `ordonnanceCorrections` (ou 401 « expire » / 404) →
  apprentissage sur le téléphone seulement, aucune requête de partage, comportement identique sinon.
- **Migration non passée** : capacité fausse, routes en 503.
- Aucune réponse JSON existante modifiée, aucune table existante modifiée.

## 8. Existant vérifié sur la dernière branche (`origin/claude/new-session-xm8ptu` `315a40b7`)

- **Rien d'équivalent** : pas de table ni de route d'apprentissage / de corrections d'ordonnances. L'existant voisin
  est le **scan d'ordonnance** du poste (`v1/ordonnance-client/scans…`, table `t_ordonnance_scan`, lecture
  automatique Posos quand elle est configurée) : il garde l'image comme pièce justificative et crée une ordonnance
  client ; il ne retient pas « texte lu → produit » et n'est pas utilisable par le téléphone sans le privilège
  `P_ORDONNANCE_CLIENT_MAJ`. O4 ne le modifie pas.
- **Pas de collision de routes** : `MobileRessource` (`@Path("v1/mobile")`) expose `connexion`, `moi`, `pointages`,
  `produits`, `produits/{id}/images` (jeton Bearer) ; O4 ajoute la ressource racine `v1/app-vente/ordonnances`
  (session, hors du préfixe `v1/mobile/`, sans toucher au filtre), comme `v1/app-vente/capacites` (H4) et
  `v1/app-vente/catalogue` (H5).
- **Migrations** : la branche est passée à `6.9.132` (11/10) ; O4 utilise `6.9.132.3` (unique, au-dessus).
- **Application** (11/10) : les 4 patchs ont été refaits sur `b9e03367` ; H4 → H5 → O4 → O5 → B3 passent
  `git apply --check` à la suite, sans `--3way` ni conflit (le conflit H4 de `SalesRessource.java` avec le suivi des
  tickets lents de l'amont est résolu dans le patch lui-même, les deux modifications sont gardées).
