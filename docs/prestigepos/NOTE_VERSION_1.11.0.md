# PrestigePOS 1.11.0 (versionCode 29)

Version de PrestigePOS construite avec Prestige Mobile **4.13.0+43** (code partagé ; détail :
`docs/NOTE_VERSION_4.13.0.md`), plus la zone « Client » de la borne décidée par le pharmacien le 14/11/2026.

## Correctif repris de Prestige Mobile 4.13.0

L'application n'envoie plus le nom du mode de règlement comme client (`POST v1/vente/update/client` avant chaque
encaissement, `clientId` de la clôture). La borne crée des préventes (pas de clôture) et n'appelait pas cette route ;
le paiement mobile money de la borne est inchangé.

## Zone « Client » de la borne (nouveau, facultatif)

- Panier : bouton **« AJOUTER MON NOM (FACULTATIF) »** (gros bouton de la borne, ≥ 56 dp), **en ligne seulement**
  (borne indisponible → rien).
- Page « Votre nom (facultatif) » : recherche par nom ou numéro (`GET v1/client/lambda`, à partir de 3 caractères ou
  d'un numéro de 4 chiffres, clavier « nom »), grandes tuiles de résultats (nom, prénom, téléphone) ; **« JE SUIS UN
  NOUVEAU CLIENT »** : nom, prénom (clavier « nom »), téléphone (clavier téléphone) → `POST v1/client/add/lambda`
  (type 6 ; refus → message du serveur tel quel).
- Le choix ramène au panier : **la liste des résultats et le texte cherché disparaissent**. Le panier montre le nom
  et une croix : 1er appui → croix rouge « Touchez encore la croix pour retirer votre nom », 2e appui → retiré
  (pas de fenêtre).
- **Rattachement** : la prévente de la borne n'existe sur le serveur qu'au moment de payer. Le client est donc
  rattaché à la **création** de la prévente (`POST v1/vente/update/client {venteId, clientId}`, après le 1er article
  et avant de terminer la prévente). L'écran du ticket affiche « Votre nom est associé à la vente. » seulement après
  `success:true` ; sinon « Nom non associé : <message du serveur> » — la prévente reste valable, sans client
  (403 `interdit` : pas de déconnexion ; 409 : idem, rien d'enregistré pour le client).
- **Confidentialité (borne vue par les clients)** : le client, les résultats, le texte cherché et les erreurs sont
  effacés à chaque retour à l'accueil (« TERMINÉ », fin du délai du ticket, inactivité, borne indisponible) et dès
  la création de la prévente ; le nom n'est jamais affiché sur l'écran du ticket. Rien n'est écrit dans un journal.
- Sans client : requêtes identiques à 1.10.1 ; avec client : une requête de plus (`update/client`).

## Tests (données fictives)

- `test/prestigepos/pos_client_test.dart` — unitaires et écrans (état de la zone, `creerPrevente`, croix, claviers).
- `test/prestigepos/pos_client_e2e_test.dart` — application entière : client trouvé / créé / retiré, sans client,
  403, **zone vidée entre deux clients** (TERMINÉ, inactivité, serveur perdu), Sunmi V2s, seuils.
- `test/prestigepos/pos_client_reseau_test.dart` — vrai HTTP : ordre des requêtes, 403 / 409 / « Client inconnu »,
  lenteur, réponse illisible, coupure.
- `test/prestigepos/pos_client_ergonomie_test.dart` — tablette paysage / portrait, borne verticale, Sunmi V2s / V3,
  texte ×1,0 / ×1,3 (débordement, cibles, contraste).
- `test/prestigepos/pos_client_performance_test.dart` — requêtes (frappe rapide, choix, payer avec / sans client).
- `test/client_vente_garde_test.dart` (branche PrestigePOS) : la borne a sa propre zone, vidée à l'accueil et à la
  création.

## Non-régression

- Job `prestige-mobile-identique` : la référence est **4.13.0+43** (commit `43f21df`, avant la fusion).
- `test/prestigepos/pos_version_test.dart` : version 1.11.0+29.
