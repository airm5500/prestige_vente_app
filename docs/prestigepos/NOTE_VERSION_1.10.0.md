# PrestigePOS 1.10.0 (versionCode 27)

Version de PrestigePOS construite avec Prestige Mobile **4.12.0+41** (code partagé). Demandes 59 et 60 livrées par
le serveur (détail : `docs/NOTE_VERSION_4.12.0.md`).

## Pour la borne PrestigePOS

- **Aucun changement visible.**
- Ce qui change dans Prestige Mobile 4.12.0 est sans effet sur la borne, qui n'a ni la réception des BL ni la
  réserve :
  - clôture « au reçu » d'un BL (`X-Client-Ref`, refus `AUCUN_RECU`) ;
  - retour en attente des manquants, sans sortie de stock ;
  - droit « Voir les suggestions de réserve » sur un refus 403.

## Non-régression

- Job `prestige-mobile-identique` : la référence est **4.12.0+41** (commit `7389d24`, avant la fusion).
- `test/prestigepos/pos_version_test.dart` : version 1.10.0+27.
- Suites de PrestigePOS et de Prestige Mobile : complètes (nouveaux tests `manquants_bl_*` compris).
