# PrestigePOS 1.7.4 (versionCode 21)

Version de PrestigePOS construite avec Prestige Mobile **4.9.4+35** (code partagé) : à la vente Dépôt de Prestige
Mobile, une étiquette étendue ne donne aucun produit, exactement comme le web (détail dans
`docs/NOTE_VERSION_4.9.4.md`).

## Pour la borne PrestigePOS

- **Rien ne change.** La borne n'utilise pas la vente Dépôt. L'étiquette étendue y reste refusée (1.7.2), avec le
  message générique pour le client. Les tests de la borne le confirment (`test/prestigepos/pos_e2e_test.dart`,
  `test/borne_test.dart`).

## Non-régression

Job `prestige-mobile-identique` : la référence est **4.9.4+35** (commit 520a83e, avant la fusion). Sur l'APK
Prestige Mobile, l'identité ne change que par le numéro de version ; les permissions sont identiques.
