# Prestige Mobile 4.15.0+46 : demande 62 (borne et prévente payée), remise des comptes de prévente

Réponse du serveur à la demande 62 : branche `correctif/demande62-1911` (fb0a3cc2), **pas encore fusionnée** dans
l'intégration (`integration/recette-2026-10-29`). Décisions du pharmacien du 19/11 : remise ouverte aux comptes de
prévente comme le web ; remise de la fiche du client sur assurance / carnet : voulue, rien à changer ; ligne « * » du
ticket : gardée.

**Règle de non-régression** : l'officine tourne sur l'intégration, sans la demande 62. Chaque nouveauté ne s'active que
si le serveur la fournit (droit présent dans `GET v1/user/droits`, champ `paiementMobile` présent). Avec le serveur
d'aujourd'hui, tout reste comme en 4.14.0, sauf la remise ouverte aux comptes de prévente.

## Contrat vérifié dans le code du serveur (le code prime sur la notice)

| Point | Code (o/d62) | Écart avec la notice |
|---|---|---|
| 1. numéro cherché aussi dans `strADRESSE` | `ClientServiceImpl` : `sansSeparateurs(strADRESSE) like numero` | aucun ; rien à changer dans les applications |
| 2. type 6 par défaut | `typeClientRapide` : vide → `STANDART_CLIENT_ID` | aucun ; les applications envoient déjà `"6"` (`DioVenteGateway.creerClientVente`, client de la borne) |
| 3a. droit de la borne | `PRIVILEGES_CLOTURE_PAIEMENT_MOBILE` = droits de « Terminer une vente » + `P_BORNE_PAIEMENT_MOBILE` ; migration `V7.6.41.1911` (aucun rôle) ; `user/droits` liste tous les droits de la session | le droit est lu **à la connexion** : après l'avoir donné, reconnecter la borne |
| 3a. 403 | `Droits.refus` **avant** la lecture de `X-Client-Ref` et toute écriture | un nouvel essai `cloturer:false` est sans risque |
| 3a. caisse fermée | `PaiementsMobileService.cloturer` : refus → `cloture = 0`, message « Clôture refusée : … » ; le statut reste `paye` | réponse : `statut:"paye"`, `clotureAuto:true`, `cloture:false` |
| 3b. champs | `SalesStatsRessource.signalerPaiementsMobile` sur `ventestats/{id}` **et** `ventestats/preventes` : `paiementMobile` (+ `operateurLibelle`, `referenceFournisseur`) et `typeReglementAttente` (texte « 7 » à « 10 ») | aucun |
| 3b. garde-fou | `SalesRessource` (`v1/vente/cloturer/vno`) et `VenteRessource` (`v2`) : `ClotureComptoir.refus` → `{success:false, msg, codeError:0, paiementMobile:true}` ; somme des lignes du mode = montant payé ; sans détail : mode de la vente | `cloturer/assurance` n'est **pas** contrôlé (dit par la notice) |
| 3c. client | clôture automatique avec `tp.getClient()` au lieu du code de l'opérateur | aucun ; serveur seulement |

## Prestige Mobile

### Borne (code commun avec PrestigePOS)

| Compte de la borne | Serveur d'aujourd'hui | Serveur avec la demande 62 |
|---|---|---|
| droit de « Terminer une vente » | `cloturer:true`, comme avant | idem |
| **`P_BORNE_PAIEMENT_MOBILE` seul** (cas du pharmacien) | (droit inconnu) | `cloturer:true` ; **aucun** bouton « Terminer une vente » ordinaire |
| profil prévente sans droit | `cloturer:false`, ticket PAYÉE (4.13.1) | idem |

- Ticket : « vente terminée » seulement si le serveur confirme la clôture (`cloture:true`). Sinon (`cloturer:false`,
  ou clôture refusée faute de caisse ouverte pour le compte de la borne) : « **PAYÉE, présentez ce ticket à la
  caisse** » (ticket et écran).
- 403 `interdit` à `cloturer:true` avec le droit de la borne (droit retiré depuis la lecture) : **une** nouvelle demande
  `cloturer:false`, même clé `X-Client-Ref`. Sans ce droit (serveur d'aujourd'hui) : comme avant (ticket de prévente
  « Paiement mobile indisponible »).
- Lignes d'état (Réglages › Paiements, administration de PrestigePOS) et « Tester la borne » : droit de la borne
  reconnu, avec la condition de la caisse ouverte.
- La borne ne propose jamais de remise.

### Comptoir : prévente payée à la borne (seulement si le serveur envoie `paiementMobile`)

- « Préventes à encaisser » : « **Payée Wave 4 125 F** » à la place de « À encaisser » (colonne « Paiement mobile »
  du web).
- Reprise (liste, vente mémorisée, ordonnance : toutes passent par `GET ventestats/{id}`) : bandeau « **Déjà payée par
  Wave : 4 125 F · n° … · date** » sur l'écran de vente et l'encaissement.
- Encaissement : mode de l'opérateur **imposé** (même s'il n'est pas activé sur l'appareil), montant reçu = montant
  payé, non modifiable, aucun QR ; « **TERMINER LA VENTE** » termine avec ce règlement, sans demander d'argent.
- Net augmenté : l'opérateur porte le montant payé, complément dans un autre mode (espèces : montant reçu, monnaie).
  Net diminué sous le montant payé : bloqué avec le motif (le serveur n'a pas de chemin pour ce cas).
- Refus `{success:false, paiementMobile:true, msg}` : message du serveur tel quel, vente gardée, paiement relu.
- Assurance : bandeau seulement (le serveur ne contrôle pas cette clôture). Carnet : pas d'encaissement.
- Ancienne interface des ventes : le refus `paiementMobile` est affiché tel quel.

### Remise (décision du 19/11)

Proposée à tout compte qui a un écran de vente (comptant, assurance, carnet), comptes de prévente compris, comme le
web ; un 403 `interdit` la masque pour la session. Aucune autre règle de la 4.14.0 ne change.

## À faire par le pharmacien une fois la demande 62 déployée

1. Donner `P_BORNE_PAIEMENT_MOBILE` (« BORNE - Clôturer une vente payée par mobile money ») au rôle du compte de la
   borne (Gestion des rôles), puis reconnecter la borne.
2. Pour la clôture automatique : ouvrir une caisse pour le compte de la borne. Sans caisse ouverte, le client reçoit le
   ticket « PAYÉE » et le comptoir termine la vente avec le paiement reçu.

## Tests (données fictives)

`demande62` (unitaires), `demande62_ecrans` (borne : cas du pharmacien, caisse fermée, 403 → repli, serveur
d'aujourd'hui ; comptoir : mode imposé, complément, net diminué, refus, liste, assurance), `demande62_integration`,
`demande62_e2e` (Sunmi V2s et tablette), `reseau/demande62_reseau`, `demande62_ergonomie`,
`performance/demande62_perf`, `demande62_garde`. Mis à jour : `remise_vente` (compte de prévente : remise proposée),
`borne_droits` (le faux module confirme la clôture comme le serveur). Faux serveur : `test/outils/demande62_fictive.dart`.
Captures : `test/outils/captures_demande62_test.dart` (hors CI).
