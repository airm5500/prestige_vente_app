# Prestige Mobile 4.10.3+39 : pause entre les copies du ticket de vente

## Retour du pharmacien

Dans la nouvelle interface des ventes, avec 2 tickets ou plus, les copies sortaient **à la suite**. Le caissier ne
pouvait pas couper le premier ticket avant l'impression du suivant.

L'ancienne interface (ventes assurance et carnet d'origine) faisait une pause avant chaque copie suivante :
« Réimpression — Voulez-vous réimprimer le ticket ? (2/2) ».

## Origine (historique git)

- **10/10, `67922ef`** (« Ventes étape 1 : Pré-vente Assurance nouvelle version ») : la demande était « un seul
  dialogue d'impression avec le nombre de copies », au lieu d'une question à chaque copie.
  - `assurance_print.dart` passe `confirmEachCopy: false` à `ReceiptService`.
  - Cela supprime la question répétée, mais aussi la **pause** qui permettait de couper le ticket.
- **10/10, `804693a`** (« Ventes étape 2 : Pré-vente / Vente… encaissement sur une page ») : la vente comptant
  imprime ses copies dans une boucle `for (i < done.copies)`, **sans pause** dès l'origine.
  - L'ancienne vente comptant n'imprimait qu'un seul ticket.
- La **vente carnet** de la nouvelle interface gardait l'ancien dialogue « Réimpression » (Oui / Non).

## Correction : une seule règle pour toutes les ventes de la nouvelle interface

Le choix « Imprimer le ticket ? » + nombre de copies ne change pas, là où il existe. Ensuite :

- La **copie 1** s'imprime tout de suite.
- **Avant chaque copie suivante**, un dialogue s'affiche :
  - titre « Ticket suivant (i/N) » ;
  - texte « Coupez le ticket, puis imprimez le suivant. » ;
  - boutons **[Arrêter]** et **[Imprimer]**.
- **[Imprimer]** a le focus par défaut.
- **[Arrêter]**, ou le retour Android, annule les copies restantes.
- Toucher à côté du dialogue ne le ferme pas.
- **Exactement un dialogue par copie suivante**, jamais avant la copie 1, aucun pour 1 copie.
- Code commun : `lib/ventes/common/copies_ticket.dart` (`imprimerCopiesAvecPause`). Chaque appel imprime une copie.

### Ventes concernées

| Vente | Copies | Avant | Maintenant |
|---|---|---|---|
| Comptant (espèces, différé, mobile money, plusieurs modes) | choisies sur la page d'encaissement | à la suite | pause |
| Encaissement provisoire hors ligne (espèces) | idem | à la suite | pause |
| Assurance : page d'encaissement | « Nombre de tickets (Assurance) » | à la suite | pause |
| Assurance : part client 0 F | choisies dans la confirmation | à la suite | pause |
| Carnet : vente validée | « Nombre de tickets (Assurance) » | « Réimpression » Oui / Non | pause (nouveau dialogue) |
| Préventes (comptant, assurance, carnet, provisoires) | toujours 1 | — | inchangé |
| Réimpression depuis l'historique ou la liste des préventes | toujours 1 | — | inchangé |
| Dépôt, proforma | pas de ticket de caisse (la proforma est un PDF A4 imprimé par le système) | — | inchangé |
| Ancienne interface (« Ventes : nouvelle version » désactivé) | — | « Réimpression » | inchangé |

La pause est la même dans l'**aperçu du mode test** : une fenêtre « Aperçu du Ticket » par copie, puis la pause.

### PrestigePOS (borne)

La borne imprime **un seul** ticket. L'écran client n'affiche jamais ce dialogue de caisse.

## Tests (catégories de la CI)

- **Unitaires** — `test/copies_ticket_test.dart` : 0 / 1 / 3 copies, Imprimer par défaut, Arrêter, retour Android,
  barrière non refermable.
- **Écrans** :
  - `test/ventes_assurance_ui_test.dart` : 1, 2 et 3 copies ; Arrêter à 2/3 et à 3/3 ; part client 0 F avec 2 copies ;
  - `test/ventes_carnet_ui_test.dart` : 1, 2 et 3 copies ; Arrêter ; prévente avec un seul ticket ; plus de
    « Réimpression ».
- **E2E** (application entière) — `test/ventes_copies_ticket_e2e_test.dart` :
  - comptant 1, 2 et 3 copies dans l'aperçu du mode test ;
  - Arrêter à 2/2, 2/3 et 3/3 ;
  - imprimante Sunmi (canal simulé) avec 1 et 3 copies ;
  - encaissement provisoire hors ligne avec 2 copies.
- **Réseau** — `test/reseau/ventes_copies_ticket_reseau_test.dart` :
  - clôture lente (5 s) : aucun ticket avant la réponse ;
  - serveur coupé pendant la pause : la copie 2 s'imprime quand même, une seule clôture.
- **Ergonomie** — `test/copies_ticket_ergonomie_test.dart` : dialogue sur Sunmi V2s, Sunmi V3, 360 dp et tablette,
  texte ×1,0 et ×1,3 :
  - aucun débordement ;
  - cibles d'au moins 48 dp ;
  - Imprimer à droite.
- **Non-régression** — `test/copies_ticket_garde_test.dart` :
  - aucune boucle de copies sans pause dans `lib/ventes` ;
  - une copie par appel ;
  - ancienne interface et borne inchangées.
