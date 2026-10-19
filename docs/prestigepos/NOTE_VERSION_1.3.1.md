# PrestigePOS 1.3.1 (versionCode 10)

Version de PrestigePOS construite avec Prestige Mobile **4.5.1+24** (code partagé) : **sécurité des ventes**,
demande du serveur du 19/10/2026 (`docs/serveur/DEMANDE_SERVEUR_DROITS_VENTE_2026-10-19.md`). Détail :
`docs/NOTE_VERSION_4.5.1.md`.

## Pour la borne PrestigePOS

Le paiement mobile money de la borne termine la vente (`cloturer:true` sous la session de l'utilisateur borne).
L'espèce donne un ticket de prévente pour la caisse.

- **Droits de l'utilisateur borne.** Ils sont lus (`GET v1/user/droits`) à la connexion de la borne, à sa
  reconnexion automatique et au retour au premier plan, en mémoire seulement. L'en-tête `X-Prestige-Utilisateur`
  part sur toutes ses requêtes.
- **Sans droit de clôture** (`P_SM_CLOTURER_CAISSE`, `P_SM_DEPOT_EXTENSION` ou `P_BT_MODIFICATION_DE_VENTE`) :
  - « PAYER PAR MOBILE MONEY » n'est pas proposé au client, seul le ticket pour la caisse reste ;
  - « Tester la borne » affiche « Utilisateur borne sans droit de clôture : paiement mobile désactivé ».
- **Refus du serveur** (403 `interdit`) pendant un paiement mobile money : le client voit « Paiement mobile
  indisponible, rendez-vous à la caisse avec votre ticket » et le ticket de prévente s'imprime.
  - La vente est gardée, sans nouvelle tentative ni déconnexion de la borne.
  - Le serveur contrôle le droit **avant** de créer le paiement : rien n'est débité.
- **409 « session changée »** : PrestigePOS redémarre et la borne reconnecte son utilisateur.

Réglage d'officine : pour accepter le mobile money à la borne, l'utilisateur borne doit avoir l'un des trois droits
de clôture.

Le reste de PrestigePOS (borne, imprimantes, démarrage automatique, « Revenir à Android ») est inchangé.

## Non-régression

- Job `prestige-mobile-identique` : sa référence est désormais **4.5.1+24** (commit d10d67f, avant la fusion).
- Sur l'APK Prestige Mobile, l'identité ne change que par le numéro de version (changement voulu) ; les permissions
  sont identiques.
- Nouveau test `test/prestigepos/pos_droits_test.dart`, sur l'application entière :
  - droits de l'utilisateur borne lus avec son en-tête ;
  - mobile money masqué sans droit de clôture ;
  - 403 pendant le paiement : message, ticket imprimé, une seule demande, borne connectée ;
  - 409 branché.
