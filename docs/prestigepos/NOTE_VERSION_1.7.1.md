# PrestigePOS 1.7.1 (versionCode 18)

Version de PrestigePOS construite avec Prestige Mobile **4.9.1+32** (code partagé) : lecture GS1 dans les ventes
Dépôt et Proforma de Prestige Mobile (détail dans `docs/NOTE_VERSION_4.9.1.md`).

## Pour la borne PrestigePOS

- **Rien ne change** : la borne n'utilise ni la vente Dépôt ni la Proforma. Sa lecture GS1 (1.7.0) est inchangée :
  le code partagé modifié (`PagedProductSearch`, option désactivée par défaut, et un paramètre facultatif du verdict
  GS1) garde le comportement de la 1.7.0 pour la borne, prouvé par les tests de la borne
  (`test/prestigepos/pos_e2e_test.dart`, `test/borne_test.dart`).

## Non-régression

Job `prestige-mobile-identique` : la référence est **4.9.1+32** (commit 5a36f7f, avant la fusion). Sur l'APK
Prestige Mobile, l'identité ne change que par le numéro de version ; les permissions sont identiques.
