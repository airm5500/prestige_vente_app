# PrestigePOS 1.7.0 (versionCode 17)

Version de PrestigePOS construite avec Prestige Mobile **4.9.0+31** (code partagé) : étiquettes GS1 à la vente
alignées sur le web (détail dans `docs/NOTE_VERSION_4.9.0.md`).

## Pour la borne PrestigePOS

- Le réglage `KEY_VENTE_LECTURE_GS1` est lu à la connexion de l'utilisateur borne. Lecture inactive (`0`, valeur
  par défaut), serveur ancien, panne ou délai : la borne fonctionne exactement comme en 1.6.0.
- **Le client ne voit jamais de détail de lot.** Boîte refusée (périmée, mode C lot différent, étiquette étendue,
  périmée hors ligne) → « Ce produit ne peut pas être ajouté ici : présentez-le au comptoir ». Rien n'est ajouté au
  panier.
- **Aucun avertissement A/B** à la borne : la fiche du produit s'ouvre comme avant.
- **Mode B, lot en stock** : le lot part avec la ligne de ce produit (`lotScanne`) à la création de la prévente ;
  les lots sont oubliés à chaque nouveau client. Le lot n'est pas imprimé sur le ticket.
- Le contenu scanné est effacé du champ de recherche dès qu'il est reconnu comme étiquette GS1, et n'est jamais
  journalisé.

## Tests

`test/prestigepos/pos_e2e_test.dart` (application entière) :
- boîte périmée, mode C lot différent et étiquette étendue : message pour le client, aucun détail (lot, date, motif),
  rien ajouté ;
- mode B lot en stock : fiche sans avertissement, `lotScanne` dans `POST v1/vente/add/vno`, pas de lot sur le ticket ;
- lecture inactive : `vente/gs1` jamais appelé, fiche du produit comme avant.

## Non-régression

Job `prestige-mobile-identique` : la référence est **4.9.0+31** (commit 5772d0e, avant la fusion). Sur l'APK
Prestige Mobile, l'identité ne change que par le numéro de version ; les permissions sont identiques.
