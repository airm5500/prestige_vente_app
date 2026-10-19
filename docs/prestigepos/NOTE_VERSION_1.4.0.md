# PrestigePOS 1.4.0 (versionCode 11)

Version de PrestigePOS construite avec Prestige Mobile **4.6.0+25** (code partagé) : réponse du serveur du 19/10/2026
(`docs/serveur/REPONSE_SERVEUR_2026-10-19.md`, détail dans `docs/NOTE_VERSION_4.6.0.md`).

## Venu de Prestige Mobile 4.6.0

- Réception BL : produits non saisis listés au refus de l'entrée en stock ; scan réservé au droit
  `P_BL_MOBILE_SCANNER` quand le serveur le contrôle.
- Retour fournisseur : message « motif différent ».
- « Mon pointage » sous la session de l'application ; terminal de pointage avec `P_RH_POINTER`.

## Pour la borne PrestigePOS

**Rien ne change.** La borne n'utilise ni la réception BL, ni le retour fournisseur, ni le pointage. Sont
inchangés : l'écran, le paiement mobile money (avec la règle des droits de la 1.3.1), les imprimantes, le démarrage
automatique et « Revenir à Android ».

## Non-régression

Job `prestige-mobile-identique` : la référence est **4.6.0+25** (commit c6b3440, avant la fusion). Sur l'APK
Prestige Mobile, l'identité ne change que par le numéro de version ; les permissions sont identiques.
