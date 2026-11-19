# PrestigePOS 1.13.0 (versionCode 32)

Version de PrestigePOS construite avec Prestige Mobile **4.15.0+46** (code partagé ; détail :
`docs/NOTE_VERSION_4.15.0.md`).

## Demande 62 (serveur `correctif/demande62-1911`, fb0a3cc2, pas encore fusionné)

Chaque nouveauté ne s'active que si le serveur la fournit. Avec le serveur d'aujourd'hui, PrestigePOS se comporte
comme en 1.12.0, sauf la remise des comptes de prévente à la caisse.

### Borne

- Compte de la borne avec le droit **`P_BORNE_PAIEMENT_MOBILE`** : paiement mobile money avec clôture automatique
  (`cloturer:true`), sans recevoir « Terminer une vente ».
- Ticket « vente terminée » seulement si le serveur confirme la clôture. Sinon, par exemple sans caisse ouverte pour
  le compte de la borne : « **PAYÉE, présentez ce ticket à la caisse** ». Imprimante externe : texte sans accents,
  comme les autres tickets ESC/POS.
- 403 sur `cloturer:true` alors que le droit avait été lu : une seule nouvelle demande `cloturer:false`.
  Le serveur refuse avant de créer quoi que ce soit.
- Client de la borne : le serveur le garde désormais à la clôture automatique (point 3c), rien à changer ici.
- Toujours aucune remise à la borne.

### Caisse (écrans de vente de Prestige Mobile)

- Prévente payée à la borne :
  - « Payée Wave … » dans la liste ;
  - bandeau « Déjà payée par … » ;
  - mode de l'opérateur imposé, montant payé non modifiable ;
  - « TERMINER LA VENTE » sans redemander l'argent ;
  - complément dans un autre mode si le net a augmenté ;
  - refus du serveur affiché tel quel.
- Remise proposée aussi aux comptes de prévente, comme le web.

## Une fois la demande 62 déployée

1. Donner `P_BORNE_PAIEMENT_MOBILE` au rôle du compte de la borne, puis reconnecter la borne.
2. Pour la clôture automatique, ouvrir une caisse pour le compte de la borne.

## Tests

- `test/prestigepos/pos_droits_test.dart` :
  - cas du pharmacien (droit de la borne et caisse ouverte) ;
  - caisse fermée (ticket PAYÉE) ;
  - droit retiré (403, puis `cloturer:false`) ;
  - le faux module confirme la clôture comme le serveur.
- Tests de Prestige Mobile 4.15.0 (demande 62) dans la suite de la CI.
- Référence CI de Prestige Mobile : 4.15.0+46 (0ac0f1e).
- `pos_version_test` : 1.13.0+32.
