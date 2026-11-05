# PrestigePOS 1.8.3 (versionCode 25)

Version de PrestigePOS construite avec Prestige Mobile **4.10.3+39** (code partagé). Retour du pharmacien sur
les copies du ticket de vente (détail : `docs/NOTE_VERSION_4.10.3.md`).

## Pour la borne PrestigePOS

- **Aucun changement.** La borne imprime un seul ticket de prévente, quel que soit le réglage « Nombre de tickets ».
  L'écran client n'affiche jamais le dialogue de caisse « Ticket suivant (i/N) ».
- La pause entre les copies concerne les ventes de la caisse de Prestige Mobile, dans la nouvelle interface :
  - comptant et différé ;
  - assurance ;
  - carnet ;
  - encaissement provisoire hors ligne.

## Non-régression

- Job `prestige-mobile-identique` : la référence est **4.10.3+39** (commit `7acbbe8`, avant la fusion).
- `test/prestigepos/pos_copies_ticket_test.dart` (nouveau) : une vente à la borne avec des réglages à 3 copies
  imprime un seul ticket, sans dialogue « Ticket suivant ».
- `test/prestigepos/pos_version_test.dart` : version 1.8.3+25.
- Suites de PrestigePOS et de Prestige Mobile : complètes.
