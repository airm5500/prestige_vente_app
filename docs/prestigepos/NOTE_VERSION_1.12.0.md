# PrestigePOS 1.12.0 (versionCode 31)

Version de PrestigePOS construite avec Prestige Mobile **4.14.0+45** (code partagé ; détail :
`docs/NOTE_VERSION_4.14.0.md`).

## Demande du pharmacien du 19/11/2026

« Ticket assurance désordonné et mal présenté : le prix passe sur 2 lignes et trop d'écart avec le nom du produit ;
est-il possible d'utiliser la même présentation que le serveur ? Ajouter remise sur les ventes (comptant, assurance,
carnet). Je ne veux pas de régression. »

## Caisse (écrans de vente de Prestige Mobile)

- Tickets de vente comptant, différé, assurance et carnet mis en page comme le serveur : désignation, puis
  « quantité x prix » et montant sur une ligne, traits à la largeur exacte, montants jamais coupés, ligne de remise.
- Largeur de l'imprimante intégrée (Sunmi) imposée ; tablette : 58 ou 80 mm, page de test.
- Ticket dessiné par le serveur (`GET v1/vente/ticket/{type}/{id}/image`) dès que le serveur l'aura (absent au 19/11 :
  gabarit local, sans régression).
- Remise sur les ventes comptant, assurance et carnet : liste du serveur (mêmes choix que le poste), appliquée après
  la réponse du serveur, montants relus, retrait possible ; comptes qui peuvent terminer une vente (aucun droit
  dédié côté serveur, demande 63).

## Borne

- **Aucune remise proposée au client** (garde-fou : `test/prestigepos/pos_ticket_serveur_test.dart`).
- Ticket de prévente : largeur de l'imprimante intégrée imposée ; imprimante Bluetooth / USB / réseau : ticket de
  prévente dessiné par le serveur, envoyé en raster ESC/POS (`GS v 0`) à la largeur choisie (58 mm = 384 points,
  80 mm = 576), coupe entre deux tickets, quand la route existe ; sinon (route absente, image illisible ou trop
  large, ticket payé par mobile money, « ticket discret ») : ticket de la borne inchangé, octet pour octet.

## Tests

`test/prestigepos/pos_ticket_serveur_test.dart` (raster 58 / 80 mm, repli sur le gabarit, borne sans remise) ;
tests de Prestige Mobile 4.14.0 (ticket, remise) dans la suite de la CI ; référence CI de Prestige Mobile :
4.14.0+45 (d42d992) ; `pos_version_test` : 1.12.0+31.
