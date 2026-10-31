# PrestigePOS 1.8.2 (versionCode 24)

Version de PrestigePOS construite avec Prestige Mobile **4.10.2+38** (code partagé). Suite des retours du pharmacien du
31/10 (détail : `docs/NOTE_VERSION_4.10.2.md`).

## Pour la borne PrestigePOS

- **Ligne d'état sous « Proposer le paiement par Mobile Money »** (messages validés par le pharmacien le 31/10).
  Elle est calculée avec les mêmes conditions que la borne, capacités du serveur relues à chaque vérification :

  | Situation | Message |
  |---|---|
  | Serveur sans module (404) | « Serveur sans module Mobile Money (version ancienne). » |
  | Aucun opérateur annoncé | « Mobile Money activé, mais le serveur Prestige n'a pas de compte de paiement configuré (agrégateur). Les modes Wave / Orange de la caisse ne suffisent pas : faites configurer le compte de paiement du serveur, puis redémarrez-le. » |
  | Utilisateur borne sans droit de clôture | « Mobile Money activé, mais le compte de la borne « X » n'a pas le droit de clôturer : donnez-lui P_SM_CLOTURER_CAISSE (ou P_SM_DEPOT_EXTENSION, P_BT_MODIFICATION_DE_VENTE). » |
  | Serveur injoignable | « Serveur injoignable : impossible de vérifier. » |
  | Tout est réuni | « Proposé au client : Orange Money, Wave… » |

  Où : assistant (étape « Présentation », revérifiée quand on coche l'option) ; Administration › « Paiement mobile
  money » (nouvelle entrée : option, ligne d'état, « Vérifier à nouveau ») ; « Tester la borne » (nouvelle étape
  « Module Mobile Money »). La vérification de la borne se fait avec une connexion d'essai de l'utilisateur borne,
  refermée aussitôt. Aucun nom de variable du serveur sur ces écrans.
- **Écran client inchangé** : aucun de ces messages ; « Payer en caisse » toujours, mobile money proposé seulement si
  tout est réuni (comme avant).
- Date de naissance modifiable / effaçable (demande 58, Prestige Mobile) : sans effet sur la borne.

## Non-régression

- Job `prestige-mobile-identique` : la référence est **4.10.2+38** (commit `4496c4e`, avant la fusion).
- `test/prestigepos/pos_mobile_money_test.dart` (nouveau) : chaque état dans l'administration, assistant, capacités
  relues, serveur coupé, option décochée enregistrée, rien sur l'écran client, Sunmi V2s texte ×1,3.
- `test/prestigepos/pos_version_test.dart` : version 1.8.2+24.
- Suites de PrestigePOS et de Prestige Mobile : complètes.
