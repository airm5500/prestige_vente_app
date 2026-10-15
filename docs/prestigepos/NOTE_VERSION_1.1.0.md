# PrestigePOS 1.1.0 (versionCode 2)

Version de PrestigePOS construite avec Prestige Mobile **4.3.0+16** (code de la borne partagé).

## Nouveautés propres à PrestigePOS

- **Démarrage automatique avec l'appareil** (coupure de courant, redémarrage) : la borne se rouvre seule, en mode
  kiosque. Réglage **désactivé par défaut**, dans l'Administration (code administrateur) › « Démarrage
  automatique ». Moyens utilisés, fiables d'Android 7 à 14 et sur Sunmi :
  - PrestigePOS proposé comme **application d'accueil** (seulement quand le réglage est actif ; choisir
    « Toujours ») : Android ouvre lui-même la borne au démarrage ;
  - **propriétaire de l'appareil** (facultatif, une commande `adb`) : verrouillage de la borne **sans
    confirmation** ; annulable depuis PrestigePOS ;
  - récepteur du démarrage de l'appareil (`BOOT_COMPLETED`) : rouvre la borne sur Android 9 et moins et en
    propriétaire de l'appareil.
  - Mode d'emploi pas à pas : `docs/prestigepos/README.md` › « Démarrage automatique avec l'appareil ».
- **« Revenir à Android »** (Administration) : désactive le démarrage automatique, arrête le verrouillage, retire
  PrestigePOS de l'accueil et ouvre l'accueil d'Android — sortie fiable même si PrestigePOS était l'accueil.
- Sans licence Prestige valide, la borne ne travaille pas (inchangé) ; serveur pas encore joignable au démarrage :
  « momentanément indisponible » puis reprise seule (inchangé, testé).
- Permission ajoutée (saveur pos seulement) : `RECEIVE_BOOT_COMPLETED`. Prestige Mobile n'a rien de nouveau
  (job `prestige-mobile-identique`).

## Venu de Prestige Mobile 4.3.0 (code partagé de la borne)

- Message « Ajouté : NOM » **en haut de l'écran** (même durée, 2 s) : il ne cache plus le bouton panier ni le bas de
  l'écran.
- Cartes produits de la borne sans débordement sur tablette avec un texte agrandi (ANO-11).

## Tests

`test/prestigepos/pos_demarrage_test.dart` : unitaires (réglage, état selon Android, pannes du canal), intégration
(canal Android), construction (manifeste de la saveur pos seulement, alias d'accueil désactivé par défaut), e2e
(Administration, appareil redémarré, sans licence), réseau (serveur pas encore joignable au démarrage), ergonomie
(5 appareils × texte ×1,0 / ×1,3). `pos_version_test` : 1.1.0+2.
