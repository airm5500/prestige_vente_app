# B3 — Paiements mobile money par agrégateur (serveur Prestige)

Patch : `docs/serveur/B3_paiements_mobile.patch` (s'applique seul sur la branche serveur actuelle
`claude/new-session-xm8ptu`, 315a40b7, indépendamment de H4/H5 : `git am docs/serveur/B3_paiements_mobile.patch`).

**Désactivé par défaut** : sans configuration, aucune route ne crée de paiement et
`GET v1/paiements-mobile/capacites` annonce une liste d'opérateurs vide (l'application garde alors « espèces »
et les QR statiques des modes, comme avant).

## Ce que le patch ajoute

| Élément | Rôle |
|---|---|
| `util/paiements/*` | Logique sans base ni réseau : statuts et transitions, signatures HMAC, configuration, adaptateurs **simulateur**, **CinetPay**, **Wave Business** |
| `rest/service/paiements/PaiementsMobileService` | Table `paiement_mobile`, création, confirmation, clôture, expiration automatique (chaque minute) |
| `rest/PaiementsMobileRessource` | Routes `v1/paiements-mobile/...` |
| `filter/AuthenticationFilter` | 4 chemins publics ajoutés à `SKIP_PATHS` (webhooks + page de retour), comme les webhooks WhatsApp |
| `V6.9.129.20__paiement_mobile.sql` | `CREATE TABLE IF NOT EXISTS paiement_mobile` (aucune table existante modifiée) |
| `PaiementsMobileTest` | 7 tests : signatures (simulateur, CinetPay, Wave + rejeu), revérification, transitions, idempotence, configuration |

Le préfixe `v1/mobile/` n'est **pas** utilisé (réservé à l'API mobile à jeton Bearer) : les routes suivent la
session cookie habituelle, comme les ventes.

## Routes

| Méthode | Chemin | Accès | Effet |
|---|---|---|---|
| GET | `v1/paiements-mobile/capacites` | session | `{paiementsMobile:[orange,mtn,moov,wave], fournisseur, expirationMin}` (aucun secret) |
| POST | `v1/paiements-mobile` | session | `{venteId, operateur, part?, cloturer}` + en-tête facultatif `X-Client-Ref` → paiement (montant, lien/QR) |
| GET | `v1/paiements-mobile/{id}` | session | statut, **revérifié chez le fournisseur** (au plus toutes les 3 s) |
| POST | `v1/paiements-mobile/{id}/annuler` | session | annulation tant que le paiement est en attente |
| GET | `v1/paiements-mobile?date=AAAA-MM-JJ` | session | historique du jour |
| POST | `v1/paiements-mobile/{id}/simuler?payer=true` | session | **simulateur seulement** : le « client » paie / refuse |
| POST | `v1/paiements-mobile/notification/{cinetpay\|wave\|simulateur}` | **public** | webhook du fournisseur |
| GET | `v1/paiements-mobile/retour` | public | page « Merci, retournez au comptoir » (navigateur du client) |

## Règles de sécurité

- **Clés secrètes uniquement côté serveur**, en variables d'environnement (ou `-D` du domaine) ; jamais en base,
  jamais renvoyées, jamais journalisées (`ConfigPaiements.toString()` les masque).
- **Montant fixé par le serveur** : net de la vente comptant (`shownetpayVno`), ou part client pour une vente
  assurance ; un montant envoyé par le téléphone est ignoré ; seule une **part** inférieure ou égale au net est
  acceptée pour un paiement en deux modes (sans clôture automatique : c'est le comptoir qui clôture avec les 2 règlements).
- **Webhook** : signature HMAC du fournisseur vérifiée (comparaison à temps constant), PUIS statut relu auprès de
  l'API du fournisseur ; montant **et** devise contrôlés ; ligne verrouillée (`SELECT … FOR UPDATE`) : des
  notifications répétées ou simultanées ne font qu'une transition et une clôture.
- **Jamais deux encaissements** : la clôture passe par `updateVenteClotureComptant` (qui refuse une vente déjà
  clôturée) ; un paiement reçu après annulation / expiration, ou un second paiement de la même vente, passe en
  `paye_apres_annulation` (« à régulariser ») et ne clôture rien.
- **Idempotence** de la création par `X-Client-Ref` (clé unique en base).
- **Expiration** : `PRESTIGE_PAIEMENTS_EXPIRATION_MIN` (10 min par défaut) ; dernière vérification chez le
  fournisseur avant de marquer « expiré ».

## Clôture automatique

À la confirmation d'un paiement `cloturer=true` (borne, encaissement complet), le serveur clôture la vente
comptant avec le mode de l'opérateur : **7 Orange, 8 Moov, 9 MTN, 10 Wave**, au nom de l'utilisateur qui a créé le
paiement. Condition : **sa caisse doit être ouverte** (règle existante de la clôture) ; sinon le paiement reste
« payé, clôture à faire au comptoir » (message visible dans l'historique) et la clôture est retentée à chaque
interrogation du statut. Ventes assurance : pas de clôture automatique (le comptoir clôture).

## Configuration

```
PRESTIGE_PAIEMENTS_FOURNISSEUR=cinetpay        # simulateur | cinetpay | wave ; vide = désactivé
PRESTIGE_PAIEMENTS_URL_PUBLIQUE=https://pharmacie.exemple.ci/prestige/api/v1
PRESTIGE_PAIEMENTS_EXPIRATION_MIN=10
# CinetPay
CINETPAY_APIKEY=…   CINETPAY_SITE_ID=…   CINETPAY_SECRET_KEY=…
# Wave Business
WAVE_API_KEY=…      WAVE_WEBHOOK_SECRET=…
# Simulateur (démonstration, formation, tests)
PRESTIGE_PAIEMENTS_SIMULATEUR_SECRET=…
```

Payara : **variables d'environnement du service** (recommandé pour les clés). Les options `-D…`
(`asadmin create-jvm-options`) fonctionnent aussi, mais Payara recopie la ligne de lancement de la JVM dans
`server.log` au démarrage : ne les utiliser que pour le simulateur. La configuration est lue au premier appel
(redémarrage du domaine après un changement).

## Adaptateurs

- **Simulateur** : complet (lien `simulateur://…`, notification signée `X-Simulateur-Signature`, revérification),
  pour les tests et la démonstration ; aucun argent ne circule.
- **CinetPay** (Orange Money, MTN, Moov, Wave, cartes) : API Checkout v2 (`/v2/payment`, `/v2/payment/check`),
  notification avec en-tête `x-token` (HMAC-SHA256 des champs `cpm_*` dans l'ordre documenté).
  **À valider avec la documentation du compte marchand** (documentation en ligne non accessible lors du développement).
- **Wave Business** (Wave seul) : `POST /v1/checkout/sessions`, `GET /v1/checkout/sessions/{id}`, webhook
  `Wave-Signature: t=…,v1=…` (HMAC de horodatage + corps, rejet au-delà de 5 min). **À valider également.**

## Ce que la pharmacie doit fournir

1. Le **choix de l'agrégateur** et un **compte marchand** (CinetPay recommandé : tous les opérateurs de Côte d'Ivoire).
2. Les **clés** du compte (API key, site id, secret de signature / secret du webhook), à poser dans la configuration
   du serveur (jamais dans l'application).
3. Une **adresse publique HTTPS** du serveur Prestige (nom de domaine + certificat, redirection du port) pour
   recevoir les notifications, et un **accès internet sortant** du serveur vers l'agrégateur.
4. L'**URL de notification** à déclarer chez l'agrégateur :
   `https://<adresse>/prestige/api/v1/paiements-mobile/notification/<cinetpay|wave>`.
5. Pour la borne : un **utilisateur borne avec une caisse ouverte** (clôture automatique des ventes payées).

## Vérification (serveur de test, simulateur)

```bash
B=http://localhost:8080/prestige/api/v1
curl -c cj -H 'Content-Type: application/json' -d '{"login":"admin","password":"…"}' $B/user/auth
curl -b cj $B/paiements-mobile/capacites
curl -b cj -H 'Content-Type: application/json' -H 'X-Client-Ref: test-1' \
     -d '{"venteId":"<prévente>","operateur":"wave","cloturer":true}' $B/paiements-mobile
curl -b cj -X POST "$B/paiements-mobile/<id>/simuler?payer=true"
curl -b cj $B/paiements-mobile/<id>           # statut paye, cloture true
curl -X POST -d '{}' $B/paiements-mobile/notification/simulateur   # 401 (signature absente)
```

## Vérification faite sur le serveur de test (11/10/2026, simulateur)

WAR = o5-lecture-avancee + B3 (branche locale `b3-test`), options `-D` du simulateur posées le temps du test :
capacités `[orange, moov, mtn, wave]` ; part supérieure au net refusée ; montant envoyé ignoré (1 115 F = net de la vente) ;
même `X-Client-Ref` = même paiement ; webhook sans signature ou mal signé → 401 ; webhook signé rejoué → 200 sans effet tant
que le fournisseur ne confirme pas ; paiement simulé → `paye`, vente `is_Closed` avec règlement **10 (Wave) 1 115 F** ;
annulation puis paiement tardif → `paye_apres_annulation`, vente restée en prévente ; historique du jour OK ; routes H4/H5/O4/O5
inchangées. Nettoyage : vente annulée (stock rétabli), prévente supprimée, `paiement_mobile` vidée, options `-D` retirées
(paiements de nouveau désactivés : capacités vides, webhook 404).
