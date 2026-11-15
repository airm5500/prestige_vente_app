# Prestige Mobile 4.13.1+44 : paiement mobile money de la borne avec un utilisateur borne au profil prévente

Retour du pharmacien du 15/11/2026 : « sur la borne je n'avais toujours pas la possibilité de valider par mobile
money, j'avais toujours un ticket pour la caisse alors que l'option autoriser validation par mobile money était
active ». Concerne la borne libre-service (code commun : PrestigePOS et le mode borne de Prestige Mobile).

## Cause

- L'option active est « Proposer le paiement mobile money » (PrestigePOS : Administration › Paiement mobile money ;
  Prestige Mobile : Réglages › Paiements). Le serveur n'a **aucune autre option** de ce nom : ni privilège dédié, ni
  paramètre `t_parameters` (code lu en lecture seule : branches `integration/recette-2026-10-29`, `plan0911`, `main`).
- Depuis 4.5.1, la borne ne proposait le mobile money qu'à un utilisateur borne qui a le droit de **terminer une
  vente** (P_SM_CLOTURER_CAISSE, P_SM_DEPOT_EXTENSION ou P_BT_MODIFICATION_DE_VENTE, lus par `GET v1/user/droits`),
  parce que la borne demande la clôture automatique (`cloturer:true`). Un compte borne au profil **prévente** n'a pas
  ce droit : le bouton était masqué, seul « Payer en caisse » restait — le cas du pharmacien.
- Dans le serveur (`PaiementsMobileRessource.creer`), ce droit n'est exigé **que pour `cloturer:true`** ; un paiement
  sans clôture automatique (`cloturer:false`) est accepté pour tout utilisateur connecté (la vente est alors terminée
  au comptoir, `PaiementsMobileService.creer`).
- Autres conditions vérifiées, sans défaut : option et opérateurs (`PaiementsMobile.operateurs`, vide si l'option est
  décochée, hors ligne ou sans compte de paiement), `_opsMobile` vidé hors ligne puis relu au retour du serveur,
  `paiementsMobile` toujours transmis par `BorneLauncher`.

## Correction

| Utilisateur borne | 4.13.0 | 4.13.1 |
|---|---|---|
| avec le droit de terminer une vente | mobile money proposé, `cloturer:true` | inchangé |
| **profil prévente** (sans le droit) | **pas de mobile money** | mobile money **proposé**, `cloturer:false` : paiement confirmé, ticket « VENTE BORNE - PAYEE » « Payé : présentez ce ticket à la caisse, qui termine la vente » |
| droits inconnus (serveur ancien) | proposé, `cloturer:true` | inchangé |
| option décochée / serveur sans compte de paiement | « Payer en caisse » seul | inchangé |

- Lignes d'état (administration, Réglages › Paiements, « Tester la borne ») : « Proposé au client : … Le compte de la
  borne « … » n'a pas le droit de terminer une vente : le paiement est confirmé, puis la caisse termine la vente
  payée. Pour la clôture automatique, donnez-lui P_SM_CLOTURER_CAISSE… ».
- Encaissement de l'application (écran de vente) : **inchangé** — il termine la vente, le droit reste exigé, comme
  le serveur.
- Un 403 `interdit` reste traité comme avant (ticket de prévente, aucune nouvelle tentative).

## À savoir (demande 62 au serveur)

La vente payée sans clôture automatique reste une **prévente payée** : la caisse la termine (mode de l'opérateur).
Le serveur ne permet pas aujourd'hui de clôturer automatiquement pour un compte borne sans « Terminer une vente », et
l'application ne sait pas si le poste signale qu'une prévente est déjà payée par mobile money : voir la demande 62.

## Tests (données fictives)

- `test/borne_droits_test.dart` : **cas du pharmacien reproduit** (profil prévente + option active → bouton visible,
  paiement `cloturer:false`, ticket « PAYÉE » à terminer en caisse) ; avec le droit : `cloturer:true` inchangé ;
  option désactivée ; droits relus en cours de route ; 403 ; « Tester la borne » ; e2e application entière.
- `test/mobile_money_etat_test.dart`, `test/mobile_money_etat_e2e_test.dart`,
  `test/reseau/mobile_money_etat_reseau_test.dart` : nouvel état « proposé sans clôture automatique » (borne), état
  « droit manquant » inchangé pour le compte de l'appareil.
