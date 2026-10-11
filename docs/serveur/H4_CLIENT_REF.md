# H4 — Clé client anti-doublon (`X-Client-Ref`) : patch serveur Prestige

> Pour le développeur Prestige. Patch : `docs/serveur/H4_client_ref.patch` (un commit, à appliquer avec `git am`
> **en premier**, ordre H4 → H5 → O4 → O5 → B3). Construit sur `origin/claude/new-session-xm8ptu` à jour (`b9e03367`,
> « Étiquettes : types par produit… ») ; compilé sur cette base (`mvn -o compile`, JDK 11).
> **Rien n'a été poussé sur le dépôt `airm5500/prestige`.** Voir § 0 pour les changements du 11/10 (préfixe, migrations).

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
| En-tête HTTP facultatif | `X-Client-Ref: <clé>` (64 caractères au plus) sur la **création** : `POST v1/vente/add/vno` (comptant / prévente), `POST v1/vente/add/assurance` (assurance **et** carnet), `POST v1/vente/add/depot`, `POST v1/retourfournisseur/new`. |
| Même clé renvoyée | La création **n'est pas refaite** : le serveur renvoie la réponse de la création initiale (même `lgPREENREGISTREMENTID` / `strREF` pour une vente — texte JSON identique ; même `lgRETOURFRSID` / `strREFRETOURFRS` pour un retour, relu en base). |
| Relecture | `GET v1/app-vente/client-ref/{ref}` → `200 {success, ref, type: "VENTE"\|"RETOUR_FRS", id, reference, statut, existe}` ou `404 {success:false, msg:"Clé client inconnue."}` (création jamais faite : le téléphone peut renvoyer sans risque). |
| Capacité | `GET v1/app-vente/capacites` → `{success:true, clientRef:true, clientRefVersion:1}` (`clientRef:false` si la table manque). L'application n'utilise H4 que si cette route répond `clientRef:true`. |
| Stockage | Table dédiée `mobile_client_ref(ref PK, type, entity_id, reference, reponse, created_at)` — **aucune table existante n'est modifiée**. |

Fichiers du patch :

- `src/main/java/rest/service/mobile/MobileClientRefService.java` (nouveau, EJB `@Stateless`) — toute la logique ;
- `src/main/java/rest/MobileClientRefRessource.java`, `src/main/java/rest/MobileCapacitesRessource.java` (nouveaux) ;
- `src/main/java/rest/SalesRessource.java` (`add/vno`, `add/assurance`, `add/depot` : paramètre `@HeaderParam("X-Client-Ref")`,
  la création passe par `creerVente(...)`, inchangée sans en-tête) ;
- `src/main/java/rest/RetourFournisseurRessource.java` (`new`) ;
- **`filter/AuthenticationFilter.java` n'est pas modifié** : `v1/app-vente/client-ref/…` et `v1/app-vente/capacites`
  suivent le contrôle de **session habituel** (cookie, comme les routes de vente) ;
- `SalesRessource` : sur la branche à jour, l'amont a ajouté le suivi des tickets lents (`SuiviImpressionTicket`,
  méthode `login()`) au même endroit ; le patch ajoute son injection `MobileClientRefService` **à côté**, sans rien
  retirer (seul conflit rencontré lors du rebasage, résolu en gardant les deux) ;
- `src/main/resources/db/migration/V6.9.132.1__mobile_client_ref.sql` (Flyway, rejouable).

## 2. Pourquoi

Prestige Mobile envoie au retour du serveur les ventes saisies hors ligne (H2) et les retours fournisseurs saisis
hors ligne (H3). Si la réponse d'une **création** est perdue (coupure Wi-Fi, délai dépassé, téléphone redémarré
pendant l'appel), l'application ne peut pas savoir si la vente / le retour existe :

- vente : elle signalait une anomalie « vérifiez dans les préventes du serveur… » ;
- retour : `/produit/retours-data` ne liste que les retours **validés** ; un retour « en préparation » est introuvable
  par l'API → anomalie « vérifiez sur Prestige (commentaire [HL:…]) ». Renvoyer créait un doublon (constaté).

Avec H4, la clé de l'opération (identifiant local stable : `HL2-<id>` pour une vente, `HL3-…` pour un retour)
accompagne la création : le serveur garantit **une seule création par clé**, et l'application relit la création
par sa clé au lieu de deviner. Résultat : plus d'anomalie « vérifiez sur Prestige » pour une réponse perdue,
et jamais de doublon, même si deux envois partent en même temps.

## 3. Fonctionnement (garanties)

`MobileClientRefService.executer(...)` :

1. pas d'en-tête (ou table absente) → **appel d'origine, rien d'autre** ;
2. clé déjà enregistrée → réponse initiale renvoyée, rien n'est créé (clé d'un autre type → refus
   « Clé client déjà utilisée pour une autre opération ») ;
3. sinon, **dans une seule transaction JTA** : `INSERT` de la clé (clé primaire) **puis** la création d'origine
   (`SalesServiceImpl.createPreVente` / `createPreVenteVo`, `RetourFournisseurServiceImpl.createRetour`, qui rejoignent
   la transaction), puis enregistrement de l'identifiant / de la référence / de la réponse ;
4. création refusée (`success:false`, ou `null` pour un retour) → `setRollbackOnly()` : ni la clé ni une création
   partielle ne sont gardées, un nouvel envoi pourra réessayer ;
5. **course** (deux envois simultanés de la même clé) : le second `INSERT` attend la fin du premier (verrou InnoDB
   sur la clé primaire), échoue sur la clé, sa transaction est annulée (rien de créé) ; le service relit alors la
   clé et renvoie la réponse du premier.

## 4. Script SQL de migration (idempotent)

Joué automatiquement par Flyway au démarrage (`V6.9.132.1__mobile_client_ref.sql`, anciennement `6.9.129.1`, voir
§ 0). Le numéro `6.9.132.1` suit la dernière migration amont `6.9.132` (Flyway est de plus configuré avec
`outOfOrder(true)`). À rejouer à la main sans risque si besoin :

```sql
CREATE TABLE IF NOT EXISTS mobile_client_ref (
    ref        VARCHAR(64)  NOT NULL,
    type       VARCHAR(20)  NOT NULL,
    entity_id  VARCHAR(40)  NULL,
    reference  VARCHAR(40)  NULL,
    reponse    MEDIUMTEXT   NULL,
    created_at DATETIME     NOT NULL,
    PRIMARY KEY (ref),
    KEY idx_mobile_client_ref_entity (type, entity_id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8;
```

Purge facultative (les clés ne servent qu'aux reprises d'envoi, quelques jours suffisent) :

```sql
DELETE FROM mobile_client_ref WHERE created_at < NOW() - INTERVAL 90 DAY;
```

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

Au démarrage, le journal contient « Flyway migration completed » et la table `mobile_client_ref` existe.
Si `git am` signale un conflit (branche ayant beaucoup bougé), les seuls points touchés dans des fichiers existants
sont : les champs injectés et les trois méthodes `add/*` de `SalesRessource`, et `create` de
`RetourFournisseurRessource` (le filtre n'est pas touché).

## 6. Tester (curl)

```bash
B=http://localhost:8080/prestige/api/v1
curl -s -c cj -H 'Content-Type: application/json' -d '{"login":"admin","password":"…"}' $B/user/auth
curl -s -b cj $B/app-vente/capacites                                  # {"clientRef":true,…}
D='{"typeVenteId":"1","natureVenteId":"1","produitId":"<lgFAMILLEID>","itemPu":1090,"qte":1,"qteServie":1,"devis":false,"venteId":null,"prevente":true,"remiseId":null,"userVendeurId":null}'
curl -s -b cj -H 'Content-Type: application/json' -H 'X-Client-Ref: TEST-1' -d "$D" $B/vente/add/vno
curl -s -b cj -H 'Content-Type: application/json' -H 'X-Client-Ref: TEST-1' -d "$D" $B/vente/add/vno   # même id
curl -s -b cj $B/app-vente/client-ref/TEST-1                          # {type:"VENTE", id, reference, statut}
curl -s -b cj $B/app-vente/client-ref/INCONNUE                        # 404
```

Contrôle en base : `SELECT * FROM mobile_client_ref;` et une seule ligne `t_preenregistrement` pour l'id renvoyé.

**Vérifié sur le serveur de test** (10/10/2026, avec les anciennes routes `v1/mobile/…` ; la logique est inchangée,
seuls les chemins ont bougé ; les routes `v1/app-vente/` sont couvertes par les tests de l'application avec un
serveur local, la vérification sur le serveur de test se fait au prochain déploiement avec `curl` comme ci-dessus) :

| Cas | Résultat |
|---|---|
| `add/vno` deux fois avec la même clé | même `lgPREENREGISTREMENTID` / `strREF`, **1 vente** en base |
| `add/vno` **6 envois simultanés** même clé | 6 réponses identiques, **1 vente** en base (5 annulées sur la clé, journal « creation simultanee ») |
| `add/vno` sans clé, deux fois | 2 ventes (comportement d'origine inchangé) |
| `add/assurance` deux fois même clé | même vente, 1 vente en base |
| `add/assurance` refusée (quantité 0) avec clé | refus d'origine (« La quantité doit être au moins égale à 1. »), clé **non** gardée (relecture : 404) |
| `retourfournisseur/new` **4 envois simultanés** + 1 de plus, même clé | même `lgRETOURFRSID` / `strREFRETOURFRS`, **1 retour** en base |
| `retourfournisseur/new` sans clé | nouveau retour (inchangé) |
| clé d'une vente réutilisée pour un retour | refus « Clé client déjà utilisée pour une autre opération (VENTE). » |
| `GET app-vente/client-ref/{ref}` | vente : `statut` `pending` puis `is_Process` après « terminer prévente » ; retour : `is_Process` ; inconnue : 404 |
| `GET app-vente/capacites` sans session | 401 « Veuillez vous connecter » (comme les autres routes) |
| Application (test d'intégration `test/horsligne_h4_test.dart`) | vente « envoyée avec clé », réponse jamais reçue → relue par sa clé, envoi terminé, **aucune anomalie**, une seule vente |

Les données de test ont été supprimées de la base du serveur de test.

## 7. Rétrocompatibilité

- **Ancien téléphone / autre client (ExtJS…) → serveur patché** : sans en-tête, chaque route appelle exactement le
  code d'origine (`creerVente` / `create` court-circuitent tout si l'en-tête est absent).
- **Téléphone à jour → serveur non patché** : un en-tête inconnu est ignoré par JAX-RS (le corps JSON est inchangé,
  Jackson n'est pas concerné) ; `GET v1/app-vente/capacites` répond 404 (puis l'ancien
  `v1/mobile/capacites`, essayé en repli, répond 401 `{"expire":true}` : chemin protégé par jeton) → l'application considère que H4 est absent et garde **exactement** son fonctionnement d'origine
  (anomalie « vérifiez sur Prestige » si une réponse de création est perdue).
- **Migration non passée** (table absente) : l'en-tête est ignoré (vérification au plus une fois par minute) et
  `capacites` répond `clientRef:false`.
- Aucune colonne ajoutée aux tables `t_preenregistrement` / `t_retour_fournisseur` ; aucun changement de réponse JSON.
- `VenteRessource` (`v2/vente`, écran web) n'est pas modifiée : l'application mobile ne l'utilise pas.
