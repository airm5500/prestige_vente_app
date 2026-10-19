# Prestige Mobile 4.5.1+24 — sécurité des ventes (demande du serveur du 19/10/2026)

Demande du serveur : `docs/serveur/DEMANDE_SERVEUR_DROITS_VENTE_2026-10-19.md`. Le cas qui l'a déclenchée : un
stagiaire au profil « Pre-vente » avait pu terminer une vente depuis l'application. Le serveur refuse désormais ces
actions sans le droit ; l'application suit. Réponse au serveur : `docs/serveur/TRANSMISSION_SERVEUR_2026-10-15.md`,
§ 2.

## Ce qui change

| Sujet | Ce qui change |
|---|---|
| Droits de vente | Après chaque connexion (mot de passe, « Rester connecté », reconnexion automatique, utilisateur borne) et à chaque retour de l'application au premier plan : `GET v1/user/droits`. Liste gardée **en mémoire seulement**, oubliée à la déconnexion et au changement de compte. Serveur sans cette route : comportement d'avant (tout affiché, le serveur reste juge). |
| Boutons masqués | Sans `P_SM_CLOTURER_CAISSE`, `P_SM_DEPOT_EXTENSION` ou `P_BT_MODIFICATION_DE_VENTE`, les boutons de clôture sont masqués et le message « Encaissement réservé aux comptes autorisés : terminez en prévente » s'affiche à la place. Concernés : « ENCAISSER » (comptant, en ligne et espèces hors ligne), « ENCAISSER / VALIDER (0 F) » (assurance), « VALIDER » (carnet), « Valider l'encaissement » d'une prévente, préventes à encaisser de l'accueil. Le profil prévente ne voit que « PRÉVENTE ». Ancienne interface : onglet VENTE et boutons « Vente » de l'assurance et du carnet. Vente en dépôt : « CLÔTURER » masqué sans `P_SM_VENTEDEPOT`, `P_SM_DEPOT_EXTENSION` ou `P_SM_CLOTURER_CAISSE`. Annulation (`P_BT_ANNULER_VENTE`) : aucun écran de l'application n'annule une vente. |
| Refus du serveur (403 `interdit`) | Le message du serveur s'affiche et la vente reste telle quelle (toujours en cours). Aucun nouvel essai, **jamais de déconnexion** (seul 401 = session absente). Appels concernés : clôture comptant, assurance, carnet, dépôt, paiement mobile money (nouvelle et ancienne interface). |
| Hors ligne | Une vente terminée hors ligne (espèces) par un compte sans le droit est bloquée à la source, d'après les droits de la dernière lecture : la prévente provisoire reste possible. À l'envoi, un 403 laisse la vente « à vérifier » avec le motif lisible, sans boucle. Une vente hors ligne n'est envoyée que **sous la session du compte qui l'a saisie** (affichage « vente(s) saisie(s) par un autre compte »). |
| Changement d'utilisateur | Déconnexion : `POST v1/user/logout`, cookies vidés, panier (ancienne interface, vente en dépôt), vente à reprendre de chaque menu, vendeur choisi et droits effacés. Connexion d'un AUTRE compte (après une déconnexion, une expiration…) : même effacement. La vente à reprendre porte son compte et n'est jamais proposée à un autre. Les files hors ligne sont gardées. |
| `X-Prestige-Utilisateur` | `str_USER_ID` de la connexion envoyé sur toutes les requêtes de la session (client partagé, Réserve / Posos / Fiche client, synchronisation, stock hors ligne, images, ordonnances, support, RH, borne, « Tester la borne »). Sur 409 `sessionChangee` : message du serveur, compte (`GET v1/user/account`) et droits relus, retour à l'accueil sans exécuter l'action, données hors ligne en attente gardées. |
| Borne | Correction du pharmacien : la borne termine une vente par mobile money (`cloturer:true`). Les droits de l'utilisateur borne sont lus à sa connexion et au retour au premier plan. **Sans droit de clôture**, « PAYER PAR MOBILE MONEY » n'est pas proposé : seul le ticket pour la caisse reste. Un 403 pendant la demande de paiement affiche « Paiement mobile indisponible, rendez-vous à la caisse avec votre ticket » et imprime le ticket de prévente ; vente gardée, aucune nouvelle tentative, borne toujours connectée. Le serveur contrôle le droit **avant** de créer le paiement : rien n'est débité. « Tester la borne » signale « Utilisateur borne sans droit de clôture : paiement mobile désactivé ». |

## Réglage à faire dans Prestige (officine)

Un utilisateur borne qui doit accepter le mobile money doit avoir `P_SM_CLOTURER_CAISSE`, `P_SM_DEPOT_EXTENSION`
ou `P_BT_MODIFICATION_DE_VENTE`. Sinon la borne ne propose que le ticket pour la caisse.

## Tests

- `test/droits_vente_test.dart` (unitaires) : règles des droits et repli, lecture et dernière lecture gardée,
  aucune écriture sur l'appareil, 403 / 409, passerelle des ventes et ancienne interface, paiement mobile refusé,
  en-tête, 409 traité une fois par rafale, vente à reprendre liée à son compte, ventes hors ligne par compte.
- `test/droits_vente_e2e_test.dart` (e2e, application entière) :
  - compte « Pre-vente » sans « ENCAISSER » (nouvelle et ancienne interface, hors ligne), « PRÉVENTE » permise ;
  - appel forcé → message, vente en cours, utilisateur toujours connecté, une seule tentative ;
  - changement de compte → panier et vente à reprendre effacés ;
  - 409 → message, compte et droits relus, accueil.
- `test/borne_droits_test.dart` : mobile money masqué sans le droit, droits relus en cours de route, 403 pendant le
  paiement (message, ticket, aucune relance), « Tester la borne », borne dans l'application (droits lus avec
  l'en-tête de l'utilisateur borne).
- `test/reseau/droits_vente_reseau_test.dart` : 403 à l'envoi hors ligne sans boucle, 409 à l'envoi (vente en
  attente), vente d'un autre compte jamais envoyée, lecture des droits lente bornée, coupure.
- Plafond de requêtes « connexion + accueil » porté de 24 à 25 (`GET /user/droits`), justifié dans `test/README.md`.
