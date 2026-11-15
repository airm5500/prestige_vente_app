# PrestigePOS 1.11.1 (versionCode 30)

Version de PrestigePOS construite avec Prestige Mobile **4.13.1+44** (code partagé de la borne ; détail :
`docs/NOTE_VERSION_4.13.1.md`).

## Bogue corrigé (retour du pharmacien du 15/11/2026)

« Sur la borne je n'avais toujours pas la possibilité de valider par mobile money, j'avais toujours un ticket pour la
caisse alors que l'option autoriser validation par mobile money était active. »

- **Cause** : l'option est « Proposer le paiement mobile money » (Administration › Paiement mobile money). La borne
  ne proposait pourtant le mobile money qu'à un utilisateur borne qui a le droit de **terminer une vente**
  (P_SM_CLOTURER_CAISSE, P_SM_DEPOT_EXTENSION ou P_BT_MODIFICATION_DE_VENTE), car elle demandait la clôture
  automatique (`cloturer:true`). Un compte borne au **profil prévente** n'a pas ce droit : bouton masqué. Le serveur
  n'a aucun droit ni paramètre dédié ; il n'exige ce droit que pour `cloturer:true`.
- **Correction** : « PAYER PAR MOBILE MONEY » proposé dès que l'option est active et que le serveur a un compte de
  paiement. Sans le droit : paiement créé avec `cloturer:false` ; une fois payé, ticket « VENTE BORNE - PAYEE »,
  « PAYE PAR WAVE », « Payé : présentez ce ticket à la caisse, qui termine la vente ». Avec le droit : clôture
  automatique comme avant.
- Administration et assistant : « Proposé au client : … Le compte de la borne « … » n'a pas le droit de terminer une
  vente : le paiement est confirmé, puis la caisse termine la vente payée… ».

## À faire côté serveur (demande 62)

Droit dédié pour que la borne clôture une vente payée par mobile money sans recevoir « Terminer une vente » ;
prévente déjà payée signalée au poste ; `clientId` de la clôture automatique. Voir
`docs/serveur/TRANSMISSION_SERVEUR_2026-10-15.md`, demande 62.

## Tests

- `test/prestigepos/pos_droits_test.dart` : **cas du pharmacien reproduit** (profil prévente + option active →
  bouton visible, `cloturer:false`, ticket PAYÉE imprimé) ; avec le droit : `cloturer:true` ; option désactivée.
- `test/prestigepos/pos_mobile_money_test.dart` : ligne d'état « proposé sans clôture automatique ».
- Job `prestige-mobile-identique` : référence **4.13.1+44** (commit `df95674`) ; `pos_version_test` : 1.11.1+30.
