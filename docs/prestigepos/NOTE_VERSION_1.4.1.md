# PrestigePOS 1.4.1 (versionCode 12)

Version de PrestigePOS construite avec Prestige Mobile **4.6.1+26** (code partagé) : suite du serveur du 19/10/2026
(détail dans `docs/NOTE_VERSION_4.6.1.md`).

## Venu de Prestige Mobile 4.6.1

- Fiche client : mesure envoyée avec `X-Client-Ref` (pas de doublon après une réponse perdue, sur un serveur à jour).
- Retour fournisseur : le retour vise le BL choisi (`blId`) quand deux grossistes ont le même numéro de BL.

## Pour la borne PrestigePOS

**Rien ne change.** La borne n'utilise ni la fiche client, ni le retour fournisseur. L'écran, le paiement mobile money,
les imprimantes, le démarrage automatique et « Revenir à Android » sont inchangés.

## Non-régression

Job `prestige-mobile-identique` : la référence est **4.6.1+26** (commit e75a014, avant la fusion). Sur l'APK
Prestige Mobile, l'identité ne change que par le numéro de version ; les permissions sont identiques.
