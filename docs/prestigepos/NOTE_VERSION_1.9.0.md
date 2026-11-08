# PrestigePOS 1.9.0 (versionCode 26)

Version de PrestigePOS construite avec Prestige Mobile **4.11.0+40** (code partagé). Plan du pharmacien du 08/11
(détail : `docs/NOTE_VERSION_4.11.0.md`).

## Pour la borne PrestigePOS

- **Aucun changement visible.**
- **Icônes de Prestige Mobile agrandies** (tablette ×1,33, terminal ×1,25). PrestigePOS n'est pas concerné :
  - l'écran client de la borne garde la mise en page réglée en 1.8.1 (`SansEchelleIcones`) ; ses pictogrammes sont
    déjà grands ;
  - l'administration de PrestigePOS ne passe pas par ce thème.
- Ce qui change dans Prestige Mobile 4.11.0 est sans effet sur la borne :
  - réception des BL ;
  - saisie manuelle de la réserve et droit « Voir les suggestions » ;
  - saisie de la péremption.

## Non-régression

- Job `prestige-mobile-identique` : la référence est **4.11.0+40** (commit `09e1597`, avant la fusion).
- `test/prestigepos/pos_icones_test.dart` (nouveau) : borne et administration avec les tailles d'icônes d'origine,
  sur tablette et Sunmi V2s, sans erreur de rendu.
- `test/prestigepos/pos_version_test.dart` : version 1.9.0+26.
- Suites de PrestigePOS et de Prestige Mobile : complètes.
