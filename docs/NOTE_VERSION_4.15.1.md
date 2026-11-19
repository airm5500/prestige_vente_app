# Prestige Mobile 4.15.1+47 : réponse du serveur à la demande 63 (ticket du serveur, droit de la remise, « sans remise »)

Réponse du serveur à la demande 63 : branche `correctif/demande63-1911` (bb6b4604), **fusionnée** avec la demande 62
(fb0a3cc2) dans `integration/recette-2026-10-29` à **76aa5fc1** et **déployée en officine le 19/11** (WAR
`prestige-officine-2026-11-19-76aa5fc1b`). Vérifié dans le code : la fusion ne change ni le contrat de la demande 63
(seul `Constant.java` garde les deux droits, `P_BORNE_PAIEMENT_MOBILE` et `P_REMISE_VENTE`) ni celui de la demande 62
(fichiers de la demande 62 identiques à fb0a3cc2, sauf les ajouts de la demande 63). Autre changement fusionné, sans
effet sur le contrat : CAISSE11 (`GenerateTicketServiceImpl` : échec d'impression rendu en `success:false` au lieu
d'une erreur 500, imprimante déclarée en secours) ; un refus de ce type reste un 200 `{success:false}` sur la route
image.

**Avec le serveur déployé (76aa5fc1)** : tickets comptant, assurance, crédit (carnet) et prévente imprimés depuis
l'image du serveur (chemin normal) ; remise selon `P_REMISE_VENTE` ; « sans remise » envoyé en `"0"` ; demande 62
active (droit de la borne, prévente payée terminée au comptoir). Vérifié par `test/demande63_integration_test.dart`
(groupe « Serveur déployé en officine le 19/11 »).

**Règle de non-régression** : une autre officine ou une sauvegarde restaurée peut tourner sur un serveur plus ancien.
Chaque nouveauté reste donc soumise à la détection du serveur. Avec un serveur sans les demandes 62 et 63, tout reste
comme en 4.15.0 (garde-fou : `test/demande63_garde_test.dart`).

**Gabarit local du ticket : retrait prévu, pas dans cette version.** Le serveur autorise son retrait mais demande de
garder le repli 404 / 405 tant qu'une officine peut avoir un serveur plus ancien. En 4.15.1, l'image du serveur est le
chemin normal et le gabarit local reste le repli d'une route absente (404 / 405). Retrait prévu dans une version
suivante, quand toutes les officines auront un serveur au moins égal à 76aa5fc1.

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
| 3. « 0 » sur un serveur ancien (intégration f0282bf0, avant le 19/11) | `RemiseServiceImpl.addRemise` : `lg_REMISE_ID` = valeur reçue, remise = `find("0")` = null, succès ; `net/assurance` et la clôture appliquent toujours la fiche | « 0 » **ne retire rien** et laisse « 0 » en base (`VenteDTO.remiseDepot` lu 0 au lieu de null) : l'application n'envoie « 0 » qu'à un serveur prouvé |
| 5. réponse | `SalesServiceImpl.addRemise` : vente terminée / annulée / inconnue, remise inconnue → `{success:false, msg}`, vente non touchée ; comptant : `data` de `shownetpayVno(vente)` | `data` vient de la variante « vente » de `shownetpayVno` (même calcul, mêmes montants que `net/vno`), sans `lgPREENREGISTREMENTID` ni `strREF` au premier niveau (l'application garde ceux qu'elle a) |
| relecture | `ventestats/{id}` : `lgREMISEID` = identifiant de la remise de la vente (aucune pour « 0 ») | une remise « 0 » se relit **vide** : l'application compare en conséquence |

## Prestige Mobile

### Ticket dessiné par le serveur

| Cas | Serveur ancien (sans 62 / 63) | Serveur avec la demande 63 (officine depuis le 19/11) |
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

| Cas | Serveur ancien (sans 62 / 63) | Serveur avec la demande 63 (officine depuis le 19/11) |
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
0ac0f1e) 209 fichiers, 2 978 tests, 2 947 réussis, 31 sautés, 0 échec ; après (4.15.1) 217 fichiers, 3 046 tests,
3 015 réussis, 31 sautés, 0 échec.
