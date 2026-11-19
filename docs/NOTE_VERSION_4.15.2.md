# Prestige Mobile 4.15.2+48 : réponse du serveur aux demandes 64 (prévente payée, panier verrouillé) et 65 (image du ticket)

Réponse du serveur du 19/11 (`docs/notices/REPONSE_DEMANDES64_65_2026-11-19.md`) :
- demande 64 : branche `correctif/demande64-1911` (d6cf51fa5) ;
- demande 65 : branche `plan/support-1811` (f8ef5afa6).

**Mise à jour du 19/11 (soir) : les deux sont fusionnées dans l'intégration (5f0ab46f), déploiement en officine non
confirmé.** Fusions dans `integration/recette-2026-10-29` :
- demande 64 : 67efe9cd ;
- demande 65 : 5f0ab46f, avec un conflit résolu dans `GenerateTicketServiceImpl`.

Serveur de référence : 5f0ab46f. Vérifié à 5f0ab46f :
- demande 64 : fichiers identiques à d6cf51fa5 (refus avant paiement, verrou, messages). Seul ajout, venu de
  `plan/support-1811` : l'expiration des paiements ne tourne que sur le poste serveur ;
- demande 65 : `sansImprimante(ps) = ps == null && APERCU.get() == null && PAPIER_IMAGE.get() == null`.
  `documentsTicket` passe par `apercu` (APERCU posé) : l'image n'est jamais refusée faute d'imprimante. Le refus
  `imprimanteAbsente` reste limité à l'impression réelle ;
- la route image (`SalesRessource`) et `PaiementsMobileRessource` sont inchangées depuis 76aa5fc1.

Officine confirmée à ce jour : 76aa5fc1 (demandes 62 et 63).

**Règle du pharmacien (19/11)** : « à la borne, le client peut soit payer par mobile money, soit valider sa prévente et
aller à la caisse ; s'il paye par mobile money, la vente est validée ». Payer à la borne termine donc la vente. Il n'y a
ni avoir ni remboursement.

## Contrat vérifié dans le code du serveur (o/integ...o/d64)

| Point | Code | Écart avec le message |
|---|---|---|
| 1. refus avant paiement | `PaiementsMobileService.creer` : si `cloturer && comptant && (part absent ou = net)`, `salesService.controleClotureComptantPossible(user, venteId)` avant l'INSERT ; refus `echec(ClotureComptoir.refusPaiement(motif))` = HTTP 200 `{success:false, message:"Paiement mobile money impossible : <motif> Le client paie à la caisse."}` | conforme. Le 403 `interdit` (droit) reste contrôlé **avant**, dans `PaiementsMobileRessource`. La clé `X-Client-Ref` déjà connue est relue **avant** ce contrôle. Motifs : caisse fermée, vente plus en cours, sans produit, stock insuffisant pour <produit>, ordonnancier (médecin, client), montant à recalculer, avoir sans client. |
| 2. verrou | `controleModificationPanier` (vente modifiable, puis `controlePreventePayee`) : `paiement_mobile` non clôturé, `paye` ou `en_attente` non expiré, `paye` d'abord | conforme : add/item (v1, v2), update/item/vno, remise, addtp, removetp, updatetypevente, ligne au comptant. Retrait `remove/vno/item/{id}` : `VenteRessource` appelle maintenant `controleRetraitLigne` (avant : erreur 500 sur une vente terminée) et renvoie `Result` → `{success:false, msg, data:null, total, metaData}`. |
| 2. messages | `ClotureComptoir.refusModificationPanier(op, montant, paye)` | conformes au texte annoncé (libellé de l'opérateur, montant en F sans séparateur) |
| 2. net | `net/vno`, `net/assurance` non verrouillés | conforme |
| 3. reprise au comptoir | `ClotureComptoir` inchangé | conforme |
| 65 | `GenerateTicketServiceImpl.sansImprimante(ps) = ps == null && APERCU.get() == null` dans les 11 contrôles R1 | conforme. La route image (`SalesRessource.imageTicket`, demande 63) n'est que sur l'intégration ; `plan/support-1811` ne la contient pas. Le contrat de la route ne change pas. |

Autre changement de `plan/support-1811`, sans effet sur les applications : l'expiration des paiements en attente ne
tourne que sur le poste serveur (`appConfig.isServerMode()`).

L'application n'utilise ni `addtp` / `removetp`, ni `updatetypevente`, ni la ligne au comptant. Les tiers payants sont
envoyés avec chaque ajout et chaque calcul du net. Ces routes ne sont donc pas atteignables depuis l'application.

## Changements

### Borne (Prestige Mobile en mode borne, borne de PrestigePOS)

- **Toujours `cloturer:true`, une seule demande.**
  - Le repli de 4.15.0 est retiré : après un 403 `interdit`, l'application redemandait le paiement avec
    `cloturer:false`. Elle ne le fait plus.
  - Le « proposé sans clôture automatique » de 4.13.1 est retiré : il créait une prévente payée non terminée, ce que
    la règle du pharmacien interdit.
- **Sans droit de clôture**, « PAYER PAR MOBILE MONEY » n'est plus proposé.
  - Droits concernés : `P_BORNE_PAIEMENT_MOBILE`, `P_SM_CLOTURER_CAISSE`, `P_SM_DEPOT_EXTENSION` ou
    `P_BT_MODIFICATION_DE_VENTE`. Droits inconnus (serveur sans `user/droits`) : proposé comme avant.
  - La ligne d'état et « Tester la borne » disent « non proposé » et nomment le droit à donner.
- **Refus « Paiement mobile money impossible »** (serveur avec la demande 64, ex. caisse de la borne fermée) :
  - reconnu par le début du champ `message` ; c'est un refus, pas une panne réseau ;
  - aucun QR, aucun suivi du statut, aucune nouvelle demande ;
  - le ticket de **prévente** est imprimé : la prévente reste sur le serveur, panier compris ;
  - l'écran montre « Paiement mobile indisponible, rendez-vous à la caisse avec votre ticket. », le même texte que pour
    un 403 ;
  - le motif du serveur, destiné à l'équipe, va au journal du terminal.
- **Panne réseau à la création** : écran d'avant (« PAYER EN CAISSE » / « ABANDONNER »), sans repli.

### Comptoir (nouvelle et ancienne interface)

- Ajout, quantité, retrait et remise refusés sur une prévente verrouillée (payée, ou paiement en cours) :
  - le `msg` du serveur est affiché tel quel, dans un bandeau de 8 s (deux phrases à lire) ;
  - le panier affiché reste celui du serveur : l'application n'applique rien avant `success:true`.
- **Ancienne interface** (réglage « Ventes : ancienne version ») :
  - les refus étaient silencieux, et « ajouté (+1) » s'affichait même quand le serveur refusait ;
  - le message du serveur est maintenant affiché (pré-vente, assurance, carnet), et « ajouté » n'apparaît qu'après un
    succès.
- Le blocage de 4.15.0 « Remettez le panier au montant payé » est gardé comme filet pour un serveur sans la demande 64.

### Demande 65

Aucun changement. La route image et sa lecture sont inchangées : `{success:true, tickets}` lu comme en 4.15.1, et le
refus `{success:false, msg}` d'un serveur sans imprimante est gardé tel quel.

## Avec le serveur déployé (76aa5fc1) et avec l'intégration 5f0ab46f (demandes 64 et 65)

| Cas | Déployé (76aa5fc1) | Intégration 5f0ab46f |
|---|---|---|
| Borne avec droit, caisse ouverte | paiement, vente terminée (inchangé) | idem |
| Borne avec droit, caisse fermée | paiement, ticket « PAYÉE, présentez ce ticket à la caisse » (inchangé : le serveur encaisse) | refus avant paiement → ticket de prévente, « payez à la caisse » |
| Borne sans droit de clôture | **changé** : mobile money non proposé (4.15.1 : `cloturer:false`, prévente payée) | idem |
| Borne : droit retiré entre-temps (403) | **changé** : ticket de prévente (4.15.1 : nouvelle demande `cloturer:false`) | idem |
| Comptoir : modifier une prévente payée | accepté par le serveur, comme en 4.15.1 (filet 4.15.0 à l'encaissement) | refus, message tel quel |

Les deux changements avec le serveur déployé viennent de la règle du pharmacien : sans eux, la borne créait une
prévente payée non terminée.

## Tests

- 8 fichiers ajoutés à la CI :
  - `demande64` (unitaires) ;
  - `demande64_ecrans` (écrans) ;
  - `demande64_integration` (intégration) ;
  - `demande64_e2e` (bout en bout) ;
  - `reseau/demande64_reseau` (réseau) ;
  - `demande64_ergonomie` (ergonomie) ;
  - `performance/demande64_perf` (performance) ;
  - `demande64_garde` (non-régression).
- Faux serveur : `test/outils/demande64_fictive.dart`.
- Tests mis à jour pour la règle du pharmacien :
  - `demande62_test`, `demande62_ecrans_test`, `demande62_integration_test`, `reseau/demande62_reseau_test`,
    `demande62_garde_test` ;
  - `borne_droits_test` ;
  - `mobile_money_etat_test`, `mobile_money_etat_e2e_test`, `reseau/mobile_money_etat_reseau_test`.
- Captures (hors CI) : `test/outils/captures_demande64_test.dart`.
