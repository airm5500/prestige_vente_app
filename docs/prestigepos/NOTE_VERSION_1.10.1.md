# PrestigePOS 1.10.1 (versionCode 28)

Version de PrestigePOS construite avec Prestige Mobile **4.12.1+42** (code partagé). Correction du retour des
manquants d'un BL après la réponse du serveur à la demande 61 (11/11) ; détail : `docs/NOTE_VERSION_4.12.1.md`.

## Pour la borne PrestigePOS

- **Aucun changement visible.**
- Ce qui change dans Prestige Mobile 4.12.1 est sans effet sur la borne, qui n'a pas la réception des BL :
  - un retour des manquants abandonné ne bloque plus la création d'un nouveau retour ;
  - texte selon le statut du retour (en attente, refusé, validé, abandonné) ; lignes et boîtes affichées si le
    serveur les donne ;
  - nouvelle clé `X-Client-Ref` pour une création après un abandon.

## Non-régression

- Job `prestige-mobile-identique` : la référence est **4.12.1+42** (commit `64e5f57`, avant la fusion).
- `test/prestigepos/pos_version_test.dart` : version 1.10.1+28.
- Suites de PrestigePOS et de Prestige Mobile : complètes (tests `manquants_bl_*` complétés).
