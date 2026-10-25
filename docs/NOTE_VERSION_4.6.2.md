# Prestige Mobile 4.6.2+27 — badges RH imprimés en QR

Depuis le 16/10, Prestige imprime sur les badges RH un QR code qui contient
`PRESTIGE-BADGE|1|<numéro>|<login>|<secret>` (serveur : `util.BadgeQr.contenu`, `RhBadgeService` ; 3523ed9e : QR
stable jusqu'à l'expiration, régénération à part). Le terminal de pointage de Prestige Mobile ne connaissait pas ce
format : un badge QR lu par la caméra ou la douchette donnait « badge inconnu ».

## Ce qui change

| Sujet | Dans l'application |
|---|---|
| Lecture du QR | Terminal de pointage RH (`v1/rh`) et ancien kiosque de pointage : le **numéro** du badge est extrait du QR puis comparé au champ `badge` de l'employé, comme un code-barres. Lecture par la douchette, la caméra ou la saisie. |
| Douchette en QWERTY sur un appareil AZERTY | Mêmes tables que le serveur (0f909974, 81cc8c54) : « PRESTIGE)BQDGE… » (clavier américain) et « PRESTIGE°BQDGE… » (avec le verrouillage des majuscules) sont remis tels qu'imprimés. Préfixe en minuscules accepté. |
| Version, lecture déformée | Version autre que `1`, lecture incomplète (moins de 5 parties), préfixe déformé, numéro vide ou illisible : « QR du badge non reconnu (raison). Réessayez, ou saisissez le numéro imprimé sur le badge. » La raison ne reprend jamais le contenu lu. |
| Secret et login | **Jamais** gardés, affichés, journalisés ni envoyés. Le pointage du terminal n'en a pas besoin : il envoie l'employé, comme avant. Le champ de lecture passe en mode masqué dès que la lecture commence par « PRESTIGE », avant la fin de la rafale du lecteur. Un badge QR inconnu affiche son numéro seul. |
| Badges actuels | Codes-barres, matricules et badges NFC (UID) : inchangés. Une lecture NFC n'est jamais traitée comme un QR. |

## Vérifié sans objet côté serveur (965a4d1b..df7ba097)

- e7fd59cf (lignes d'un BL en une fois, `commande/bon/items`) : lecture plus rapide, réponses identiques ; rien à
  changer.
- Les autres commits touchent des routes que l'application n'appelle pas : WhatsApp, campagnes, menus et maquettes,
  activité des équipes et anomalies, tableau de bord, Étiquetage Pro, GS1 de la vente (`v1/vente/gs1`), tiers-payants
  (`v1/tierspayant`), connexion par badge (`user/auth-badge`, non utilisée par l'application), `rh/badges/{id}/regenerer`.
- 974976e0 : un corps illisible est refusé en 400 avec un message ; l'application n'envoie que du JSON valide, et le
  renvoi sans `blId` de la 4.6.1 sur un 400 reste sans risque (rien n'est écrit).
- d0c4092c / 1fea9a05 : vendeur non choisi à la vente ; l'application envoie toujours l'identifiant du compte.

## Tests

- `test/badge_qr_test.dart` (unitaires et écran) :
  - format exact, QWERTY, QWERTY + majuscules, minuscules, login contenant « | » ;
  - refus avec la raison seule ; codes-barres et UID NFC non pris pour des QR ;
  - terminal : employé reconnu, rien du secret ni du login dans les envois ni dans le journal du terminal ;
  - champ masqué pendant la rafale.
- `test/badge_qr_e2e_test.dart` (application entière, faux serveur) : badge QR lu par la douchette (QWERTY +
  majuscules) → « Bonjour Awa », pointage reçu pour l'employé ; badge code-barres ensuite inchangé ; aucune requête
  (chemin, paramètres, corps, en-têtes) ne contient le secret, le login ou le contenu du QR.
- `test/pointage_badge_test.dart` : ancien kiosque, QR reconnu et QR illisible.
