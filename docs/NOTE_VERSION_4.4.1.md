# Prestige Mobile 4.4.1+22 — contenu identique à la 4.4.0, iOS retiré

Décision du pharmacien : la version iPhone / iPad (TestFlight) ne concerne pas Prestige Mobile. La 4.5.0+21
(commit 30f1a99) est annulée par un commit de revert, sans réécrire l'historique.

- **Contenu identique à la 4.4.0+20** (commit 2e59cd0) : `lib/`, `android/`, tests et documentation ; seuls le
  numéro de version (`pubspec.yaml`), cette note et `docs/VERSIONS_SUNMI.md` changent.
- Retirés avec la 4.5.0 : couche de capacités de la plateforme, dossier `ios/` adapté, workflow
  `build-ios.yml`, tests `test/ios` (et leur place dans la liste de la CI et `test/categories.json`).
- Numéro de build **22** : le 21 a existé (4.5.0), il ne doit jamais redescendre.

Nouveautés fonctionnelles : aucune ; voir `docs/NOTE_VERSION_4.4.0.md`.
