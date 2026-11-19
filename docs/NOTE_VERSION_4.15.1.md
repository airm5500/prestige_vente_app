# Prestige Mobile 4.15.1+47 : réponse du serveur à la demande 63 (ticket du serveur, droit de la remise, « sans remise »)

Réponse du serveur à la demande 63 : branche `correctif/demande63-1911` (bb6b4604), **pas encore fusionnée** dans
l'intégration (`integration/recette-2026-10-29`, f0282bf0, sans les demandes 62 et 63 : c'est ce que l'officine aura
d'abord). Date de déploiement de la route image en officine : pas encore fixée.

**Règle de non-régression** : chaque nouveauté ne s'active que si le serveur la fournit. Avec le serveur d'aujourd'hui,
tout reste comme en 4.15.0 (garde-fou : `test/demande63_garde_test.dart`).

**Borne (question en attente de la 4.15.0)** : le pharmacien a **confirmé** le 19/11 que le changement de la 4.15.0
reste actif (« vente terminée » seulement si `cloture:true` ; sinon ticket « PAYÉE, présentez ce ticket à la caisse »).
Aucun changement de code.

## Contrat vérifié dans le code du serveur (le code prime sur le message)

| Point | Code (o/d63) | Écart avec le message / la demande |
|---|---|---|
| 1. route image | `SalesRessource.imageTicket` : `GET v1/vente/ticket/{type}/{id}/image?largeur&dpi`, type `vno` / `vo` / `prevente` | conforme ; **pas de `vo-combine`** : `vo` rend tous les tickets dans l'ordre d'impression (l'application ne connaît plus `vo-combine`) |
| 1. réponse | `{success:true, largeur, dpi, tickets:[{modele, png, largeurPoints, hauteurPoints}]}` | `dpi` en plus (ignoré) ; largeur : 57 ou moins → 58, au-dessus → 80, absente → 80 ; `dpi` hors 100-600 → 203 |
| 1. image | `RenduTicket.imageImprimante` : `BufferedImage.TYPE_BYTE_GRAY`, fond blanc, texte **lissé** (`TEXT_ANTIALIAS_ON`) | **niveaux de gris, PAS 1 bit** comme le disait la demande : l'application convertit (ci-dessous) |
| 1. largeur | `pointsLargeur` = ⌈largeur imprimable (48 / 72 mm) × dpi / 25,4⌉ → 384 / 576 à 203 dpi | conforme |
| 1. bord | `BORD_IMAGE = 1` en unités du dessin (point typographique, 1/72 pouce), mis à l'échelle | ≈ **2,8 points d'imprimante** de chaque côté à 203 dpi, pas « 1 point » ; sans effet pour l'application (largeur totale exacte) |
| 1. refus | 401 sans session ; type inconnu → **400** `{success:false, msg}` ; aucun ticket → 200 `{success:false, msg:"Aucun ticket pour cette vente."}` ; exception → 200 `{success:false, msg:"Ticket introuvable : " + message de l'exception}` ; pas de 403 | conforme ; le message d'exception (vente inconnue / non terminée) est un texte technique de Java, affiché tel quel |
| 2. droit | `Droits.refus(…, P_REMISE_VENTE)` sur `v1/vente/remise` et `v2/vente/remise`, avant tout : 403 `{success:false, interdit:true, msg:"Droit manquant : Remise sur une vente"}` | conforme ; migration `V7.6.41.1912` : tous les rôles **existants** (une seule fois) ; un rôle créé plus tard ne l'a pas ; droits lus à la connexion (se reconnecter après un changement de rôle) |
| 2. user/droits | `AccountResource.droits` : seulement les droits **de la session** | l'absence du droit ne dit pas si le serveur le connaît (voir la règle ci-dessous) |
| 3. « sans remise » | `SalesNetComputingServiceImpl.remiseAppliquee` : remise de la vente, sinon fiche du client sauf `lg_REMISE_ID = "0"` ; même règle à la clôture | conforme ; `common/remises-client` inchangée (« SANS REMISE » : id null) |
| 3. « 0 » sur l'intégration d'aujourd'hui | `RemiseServiceImpl.addRemise` : `lg_REMISE_ID` = valeur reçue, remise = `find("0")` = null, succès ; `net/assurance` et la clôture appliquent toujours la fiche | « 0 » **ne retire rien** et laisse « 0 » en base (`VenteDTO.remiseDepot` lu 0 au lieu de null) : l'application n'envoie « 0 » qu'à un serveur prouvé |
| 5. réponse | `SalesServiceImpl.addRemise` : vente terminée / annulée / inconnue, remise inconnue → `{success:false, msg}`, vente non touchée ; comptant : `data` de `shownetpayVno(vente)` | `data` vient de la variante « vente » de `shownetpayVno` (même calcul, mêmes montants que `net/vno`), sans `lgPREENREGISTREMENTID` ni `strREF` au premier niveau (l'application garde ceux qu'elle a) |
| relecture | `ventestats/{id}` : `lgREMISEID` = identifiant de la remise de la vente (aucune pour « 0 ») | une remise « 0 » se relit **vide** : l'application compare en conséquence |

## Prestige Mobile

### Ticket dessiné par le serveur

| Cas | Serveur d'aujourd'hui | Serveur avec la demande 63 |
|---|---|---|
| route | 404 → gabarit local, comme 4.15.0 | tickets → convertis en **1 bit** puis imprimés dans l'ordre (coupe entre deux) |
| imprimante intégrée Sunmi | gabarit local | raster `GS v 0` (`printRawData`), bandes de 256 lignes, largeur 384 / 576 ; image plus large que le papier ou illisible → « Ticket non imprimé » + « Réimprimer » |
| 400 (type inconnu) | — | gabarit local, sans question (défaut de l'application ; le ticket local reste juste) |
| 200 `{success:false}` | — | **message du serveur tel quel**, « Réimprimer » (nouvel essai), « Ticket de l'application » (gabarit local, choisi par le vendeur), « Fermer » (aucun ticket) ; jamais de ticket local imprimé en silence pour une vente que le serveur dit inconnue ou non terminée ; aperçu (mode test) et borne : gabarit local |
| réseau coupé après une réponse JSON de la route | — | « Ticket non imprimé : réseau indisponible » + « Réimprimer » (pas de ticket recomposé) |

**Conversion en 1 bit** (`lib/services/ticket_1bit.dart`, partagée avec PrestigePOS) : **seuil** fixe (luminance
< 128 → point noir), pas de tramage. Le serveur ne dessine que du texte lissé, des traits et le QR / code-barres
(formes pleines) : le seuil garde des bords nets et des modules de QR pleins ; un tramage sème des points isolés autour
des lettres et dans le QR (mesuré : `test/demande63_test.dart`). Transparence posée sur du blanc ; PNG gris à un canal
lu sur sa seule valeur (la luminance de la bibliothèque `image` lisait vert et bleu à 0 sur un PNG gris et rendait
tout noir).

### Remise

| Cas | Serveur d'aujourd'hui | Serveur avec la demande 63 |
|---|---|---|
| zone Remise | règle de 4.15.0 : tout compte qui a un écran de vente ; un 403 la masque pour la session | droit `P_REMISE_VENTE` présent → proposée ; droits lus, serveur prouvé, droit absent → **masquée** ; serveur pas encore prouvé → règle de 4.15.0 (le serveur juge, un 403 la masque) |
| preuve « le serveur connaît le droit » | jamais (l'absence du droit n'est pas une preuve) | droit présent dans la liste d'un compte de ce serveur, 403 `interdit` sur la remise, réponse JSON de la route image, `data` dans la réponse de vente/remise ; gardée jusqu'au changement de serveur |
| « Retirer » | `remiseId: null` (comme 4.15.0) | `remiseId: "0"` : la remise de la fiche du client ne revient pas (assurance / carnet) |
| « SANS REMISE » dans la liste | non proposé (comme 4.15.0) | proposé, envoie `"0"` (« Sans remise pour cette vente. ») |
| net comptant après la remise | `net/vno` relu (comme 4.15.0) | `data` de la réponse utilisé : **une requête de moins** ; sans `data` → `net/vno` |
| assurance / carnet | `net/assurance` relu | `net/assurance` relu (pas de `data`) |
| refus | `{success:false, msg}` tel quel, remise non affichée | idem, et 403 « Droit manquant : Remise sur une vente » tel quel, zone masquée |
| réponse perdue | relue (`ventestats/{id}`) | relue ; « 0 » se relit vide |

Confidentialité : aucun texte de ticket, nom de client ou de patient, texte cherché ni téléphone dans les journaux
(garde-fou).

## Tests

8 fichiers ajoutés (CI, `test/categories.json`, `test/README.md`) et un faux serveur `test/outils/demande63_fictive.dart`
(règles de bb6b4604, ticket fictif en niveaux de gris : texte lissé, QR à modules de 2,8 points) :
`demande63` (unitaires), `demande63_ecrans`, `demande63_integration`, `demande63_e2e`, `reseau/demande63_reseau`,
`demande63_ergonomie`, `performance/demande63_perf`, `demande63_garde`. Outil hors CI : `outils/captures_demande63`
(tickets 58 / 80 mm gris du serveur puis imprimés en 1 bit).

Suite complète de la CI en local (Flutter 3.32.8, commande de `.github/workflows/build-apk.yml`) : avant (4.15.0,
0ac0f1e) 209 fichiers, 2 978 tests, 2 947 réussis, 31 sautés, 0 échec ; après (4.15.1) 217 fichiers, 3 043 tests,
3 012 réussis, 31 sautés, 0 échec.
