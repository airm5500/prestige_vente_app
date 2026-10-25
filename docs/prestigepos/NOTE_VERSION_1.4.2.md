# PrestigePOS 1.4.2 (versionCode 13)

Version de PrestigePOS construite avec Prestige Mobile **4.6.2+27** (code partagé) : badges RH imprimés en QR
reconnus par le terminal de pointage (détail dans `docs/NOTE_VERSION_4.6.2.md`).

## Venu de Prestige Mobile 4.6.2

- Terminal de pointage (et ancien kiosque) : QR `PRESTIGE-BADGE|1|numéro|login|secret` lu, numéro seul utilisé ;
  douchette en QWERTY sur AZERTY prise en charge ; secret et login jamais affichés, journalisés ni envoyés.

## Pour la borne PrestigePOS

**Rien ne change.** La borne n'utilise pas le pointage. L'écran, le paiement mobile money, les imprimantes, le
démarrage automatique et « Revenir à Android » sont inchangés.

## Non-régression

Job `prestige-mobile-identique` : la référence est **4.6.2+27** (commit 29fbad9, avant la fusion). Sur l'APK
Prestige Mobile, l'identité ne change que par le numéro de version ; les permissions sont identiques.
