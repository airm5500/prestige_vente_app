# PrestigePOS 1.2.2 (versionCode 8)

Version de PrestigePOS construite avec Prestige Mobile **4.4.1+22** (code partagé).

## Venu de Prestige Mobile 4.4.1

Décision du pharmacien : la version iPhone / iPad ne concerne pas Prestige Mobile. La 4.5.0+21 (et donc la
PrestigePOS 1.2.1+7 qui l'intégrait) est annulée par un commit de revert, sans réécrire l'historique : voir
`docs/NOTE_VERSION_4.4.1.md`.

- **Contenu identique à la 1.2.0** (commit ef11608) : `lib/` identique, `android/` identique hors numéro de
  version (`android/app/prestigepos-version.properties`).
- versionCode **8** : le 7 a existé (1.2.1), il ne doit jamais redescendre.
- Prestige Mobile reste identique à sa version de référence (job `prestige-mobile-identique`, référence 4.4.1+22,
  commit 10ff4a2).
