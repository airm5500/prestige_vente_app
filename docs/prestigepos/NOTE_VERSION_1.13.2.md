# PrestigePOS 1.13.2 (versionCode 34)

Version de PrestigePOS construite avec Prestige Mobile **4.15.2+48** (code partagé ; détail :
`docs/NOTE_VERSION_4.15.2.md`).

## Réponse du serveur aux demandes 64 et 65

- Demande 64 : `correctif/demande64-1911` (d6cf51fa5).
- Demande 65 : `plan/support-1811` (f8ef5afa6).

Mise à jour du 19/11 (soir) : **fusionnées dans l'intégration (5f0ab46f), déploiement en officine non confirmé**
(officine confirmée : 76aa5fc1). Contrats vérifiés inchangés à 5f0ab46f : refus avant paiement, verrou et messages ;
l'image du ticket n'est jamais refusée faute d'imprimante (`sansImprimante` exclut `APERCU` et `PAPIER_IMAGE`).

Règle du pharmacien (19/11) : à la borne, le client paie par mobile money **et la vente est terminée**, ou il valide sa
prévente et paie à la caisse. Il n'y a jamais de prévente payée laissée à la caisse.

### Borne de PrestigePOS

- Toujours `cloturer:true`, une seule demande.
  - Après un 403, plus de nouvelle demande avec `cloturer:false` : ticket de prévente et « payez à la caisse ».
  - Le « proposé sans clôture automatique » de 1.11.1 est retiré.
- Sans droit de clôture (`P_BORNE_PAIEMENT_MOBILE` ou « Terminer une vente »), « PAYER PAR MOBILE MONEY » n'est plus
  proposé.
  - La page d'administration « Paiement mobile money » dit « non proposé » et nomme le droit à donner.
- Serveur avec la demande 64, caisse de la borne fermée :
  - refus du serveur avant tout paiement ;
  - aucun QR ; ticket de prévente imprimé ;
  - « Paiement mobile indisponible, rendez-vous à la caisse avec votre ticket. » ;
  - motif du serveur au journal.

### Caisse

Sur une prévente payée par mobile money, ou dont un paiement est en cours, le serveur verrouille le panier (ajout,
quantité, retrait, remise refusés) :
- le message du serveur est affiché tel quel, pendant 8 s ;
- le panier reste celui du serveur ;
- l'ancienne interface affiche aussi ces refus.

### Demande 65

Aucun changement : la route image du ticket est inchangée.

### Avec le serveur déployé (76aa5fc1) ; intégration 5f0ab46f : comportements « demande 64 » ci-dessus

Comme 1.13.1, sauf deux cas, qui suivent la règle du pharmacien :
- borne sans droit de clôture : mobile money non proposé (1.13.1 : paiement sans clôture) ;
- 403 à la borne : plus de nouvelle demande avec `cloturer:false`.

## Tests

- Prestige Mobile : 8 fichiers `demande64*` ajoutés à la CI.
- PrestigePOS, mis à jour :
  - `pos_droits_test` : borne sans droit, 403, et refus « caisse fermée » de la demande 64 ;
  - `pos_mobile_money_test` : « non proposé » ;
  - `pos_version_test` : 1.13.2+34.
