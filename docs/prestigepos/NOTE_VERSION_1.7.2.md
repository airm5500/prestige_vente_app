# PrestigePOS 1.7.2 (versionCode 19)

Version de PrestigePOS construite avec Prestige Mobile **4.9.2+33** (code partagé) : étiquettes étendues refusées
comme le web, même lecture GS1 inactive (détail dans `docs/NOTE_VERSION_4.9.2.md`).

## Pour la borne PrestigePOS

- Une étiquette **étendue** d'Étiquetage Pro (DataMatrix+, QR+) scannée par le client est refusée, **quel que soit**
  le réglage `KEY_VENTE_LECTURE_GS1`, hors ligne compris. Elle est reconnue sur l'appareil, sans requête, avec la
  règle du web.
- Le client voit seulement « Ce produit ne peut pas être ajouté ici : présentez-le au comptoir ». Aucun détail
  (lot, marqueur, motif) n'est affiché, et le contenu scanné est effacé du champ de recherche.
- Les étiquettes GS1 normales, codes-barres et noms : comme en 1.7.1.

## Tests

`test/prestigepos/pos_e2e_test.dart` : DataMatrix+ et QR+ en lecture inactive ; message pour le client, aucun
détail, aucune requête `vente/gs1` ni recherche, rien ajouté.

## Non-régression

Job `prestige-mobile-identique` : la référence est **4.9.2+33** (commit 9c6c176, avant la fusion). Sur l'APK
Prestige Mobile, l'identité ne change que par le numéro de version ; les permissions sont identiques.
