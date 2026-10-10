# H4 — Clé client anti-doublon (`X-Client-Ref`) : patch serveur Prestige

> Pour le développeur Prestige. Patch : `docs/serveur/H4_client_ref.patch` (un commit, à appliquer avec `git am`).
> Construit sur `origin/claude/new-session-xm8ptu` (`88a2a4b`, « Lot B (d) : envoi PharmaML en arrière-plan… ») ;
> compilé sur cette base (`mvn compile`), vérifié sur le serveur de test (Payara 5 + MariaDB).
> **Rien n'a été poussé sur le dépôt `airm5500/prestige`.**

## 1. Quoi

| Élément | Détail |
|---|---|
| En-tête HTTP facultatif | `X-Client-Ref: <clé>` (64 caractères au plus) sur la **création** : `POST v1/vente/add/vno` (comptant / prévente), `POST v1/vente/add/assurance` (assurance **et** carnet), `POST v1/vente/add/depot`, `POST v1/retourfournisseur/new`. |
| Même clé renvoyée | La création **n'est pas refaite** : le serveur renvoie la réponse de la création initiale (même `lgPREENREGISTREMENTID` / `strREF` pour une vente — texte JSON identique ; même `lgRETOURFRSID` / `strREFRETOURFRS` pour un retour, relu en base). |
| Relecture | `GET v1/mobile/client-ref/{ref}` → `200 {success, ref, type: "VENTE"\|"RETOUR_FRS", id, reference, statut, existe}` ou `404 {success:false, msg:"Clé client inconnue."}` (création jamais faite : le téléphone peut renvoyer sans risque). |
| Capacité | `GET v1/mobile/capacites` → `{success:true, clientRef:true, clientRefVersion:1}` (`clientRef:false` si la table manque). L'application n'utilise H4 que si cette route répond `clientRef:true`. |
| Stockage | Table dédiée `mobile_client_ref(ref PK, type, entity_id, reference, reponse, created_at)` — **aucune table existante n'est modifiée**. |

Fichiers du patch :

- `src/main/java/rest/service/mobile/MobileClientRefService.java` (nouveau, EJB `@Stateless`) — toute la logique ;
- `src/main/java/rest/MobileClientRefRessource.java`, `src/main/java/rest/MobileCapacitesRessource.java` (nouveaux) ;
- `src/main/java/rest/SalesRessource.java` (`add/vno`, `add/assurance`, `add/depot` : paramètre `@HeaderParam("X-Client-Ref")`,
  la création passe par `creerVente(...)`, inchangée sans en-tête) ;
- `src/main/java/rest/RetourFournisseurRessource.java` (`new`) ;
- `src/main/java/filter/AuthenticationFilter.java` : `v1/mobile/client-ref/…` et `v1/mobile/capacites` suivent le
  contrôle de **session habituel** (cookie, comme les routes de vente) et non celui du jeton Bearer des autres
  chemins `v1/mobile/` (L13) — l'application de vente n'utilise pas ce jeton ;
- `src/main/resources/db/migration/V6.9.129.1__mobile_client_ref.sql` (Flyway, rejouable).

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

Joué automatiquement par Flyway au démarrage (`V6.9.129.1__mobile_client_ref.sql`). Le numéro `6.9.129.1` est
intercalé après `6.9.129` pour ne jamais entrer en collision avec la suite `6.9.130, 6.9.131…` (Flyway est configuré
avec `outOfOrder(true)` : il est appliqué même si des versions plus récentes le sont déjà). À rejouer à la main sans
risque si besoin :

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
git checkout claude/new-session-xm8ptu        # ou la branche de travail
git am /chemin/vers/docs/serveur/H4_client_ref.patch
mvn -DskipTests package                       # JDK 11
asadmin redeploy --name prestige --contextroot prestige target/prestige.war
```

Au démarrage, le journal contient « Flyway migration completed » et la table `mobile_client_ref` existe.
Si `git am` signale un conflit (branche ayant beaucoup bougé), les seuls points touchés dans des fichiers existants
sont : les trois méthodes `add/*` de `SalesRessource`, `create` de `RetourFournisseurRessource` et la condition
`path.startsWith(CHEMIN_MOBILE)` du filtre.

## 6. Tester (curl)

```bash
B=http://localhost:8080/prestige/api/v1
curl -s -c cj -H 'Content-Type: application/json' -d '{"login":"admin","password":"…"}' $B/user/auth
curl -s -b cj $B/mobile/capacites                                  # {"clientRef":true,…}
D='{"typeVenteId":"1","natureVenteId":"1","produitId":"<lgFAMILLEID>","itemPu":1090,"qte":1,"qteServie":1,"devis":false,"venteId":null,"prevente":true,"remiseId":null,"userVendeurId":null}'
curl -s -b cj -H 'Content-Type: application/json' -H 'X-Client-Ref: TEST-1' -d "$D" $B/vente/add/vno
curl -s -b cj -H 'Content-Type: application/json' -H 'X-Client-Ref: TEST-1' -d "$D" $B/vente/add/vno   # même id
curl -s -b cj $B/mobile/client-ref/TEST-1                          # {type:"VENTE", id, reference, statut}
curl -s -b cj $B/mobile/client-ref/INCONNUE                        # 404
```

Contrôle en base : `SELECT * FROM mobile_client_ref;` et une seule ligne `t_preenregistrement` pour l'id renvoyé.

**Vérifié sur le serveur de test** (10/10/2026) :

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
| `GET mobile/client-ref/{ref}` | vente : `statut` `pending` puis `is_Process` après « terminer prévente » ; retour : `is_Process` ; inconnue : 404 |
| `GET mobile/capacites` sans session | 401 « Veuillez vous connecter » (comme les autres routes) |
| Application (test d'intégration `test/horsligne_h4_test.dart`) | vente « envoyée avec clé », réponse jamais reçue → relue par sa clé, envoi terminé, **aucune anomalie**, une seule vente |

Les données de test ont été supprimées de la base du serveur de test.

## 7. Rétrocompatibilité

- **Ancien téléphone / autre client (ExtJS…) → serveur patché** : sans en-tête, chaque route appelle exactement le
  code d'origine (`creerVente` / `create` court-circuitent tout si l'en-tête est absent).
- **Téléphone à jour → serveur non patché** : un en-tête inconnu est ignoré par JAX-RS (le corps JSON est inchangé,
  Jackson n'est pas concerné) ; `GET v1/mobile/capacites` répond 401 `{"expire":true}` (chemin `v1/mobile/` protégé
  par jeton) ou 404 → l'application considère que H4 est absent et garde **exactement** son fonctionnement d'origine
  (anomalie « vérifiez sur Prestige » si une réponse de création est perdue).
- **Migration non passée** (table absente) : l'en-tête est ignoré (vérification au plus une fois par minute) et
  `capacites` répond `clientRef:false`.
- Aucune colonne ajoutée aux tables `t_preenregistrement` / `t_retour_fournisseur` ; aucun changement de réponse JSON.
- `VenteRessource` (`v2/vente`, écran web) n'est pas modifiée : l'application mobile ne l'utilise pas.
