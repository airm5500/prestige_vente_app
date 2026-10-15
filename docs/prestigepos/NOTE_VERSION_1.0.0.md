# PrestigePOS 1.0.0 (versionCode 1)

Première version de **PrestigePOS**, application Android de vente libre-service, distincte de Prestige Mobile
(`com.dici.prestigepos`), construite depuis le même projet (saveur Android `pos`, `lib/main_pos.dart`).

## Contenu

- **Borne libre-service de Prestige Mobile, partagée** (`lib/borne/`) : recherche, catégories en images, produits
  mis en avant, fiche produit, panier local plafonné, vérification des prix et du stock avant validation (écarts
  montrés au client), prévente comptant créée sur le serveur, ticket avec QR de la référence, retour automatique
  à l'accueil, présentations Vitrine / Liste rapide / Guidée.
- **Plein écran dès le lancement** : barres système masquées, écran épinglé (kiosque), bouton Retour neutralisé.
  Sortie : cadenas, appui long 2 s, confirmation, code administrateur → Administration (reprise automatique de la
  borne après 3 min sans action).
- **Assistant de premier lancement** protégé par le code administrateur : serveur (http/https, vérifié),
  utilisateur borne (mot de passe en stockage sécurisé, « Tester la borne »), présentation, taille d'écran,
  mobile money, imprimante.
- **Paiement** : « Payer en caisse » (ticket de prévente, paiement en espèces à la caisse) ; mobile money proposé
  seulement si le serveur annonce le module (GET /paiements-mobile/capacites).
- **Imprimantes de ticket**, papier 58 ou 80 mm : Sunmi intégrée (détectée), Bluetooth (recherche, ajout,
  mémorisation), USB (OTG), réseau (IP:9100), en ESC/POS ; test d'impression ; QR natif ou en image ; accents en
  option ; coupe du papier. En cas d'échec : cause en clair et ticket affiché à l'écran.
- **Serveur injoignable** : « Borne momentanément indisponible — adressez-vous au comptoir », reprise automatique.
  **Session de l'utilisateur borne expirée** : reconnexion silencieuse.
- **Licence** Prestige vérifiée au démarrage (absente / expirée : borne fermée, administration par code).

## Prestige Mobile

Inchangé : même applicationId, même nom, même version (4.2.0+14), mêmes permissions (vérifié par la CI contre
4.2.0+14), même commande de construction (`flutter build apk --release`). Changements partagés dans la borne (profitent
aussi à Prestige Mobile, sans effet visible tant que l'imprimante Sunmi est utilisée) : imprimante de la borne
injectable, message d'échec d'impression affiché si l'imprimante sait l'expliquer.

## Limites connues

- Pas de démarrage automatique au démarrage de l'appareil ni d'application « lanceur » (HOME) : à prévoir avec un
  MDM si la borne doit redémarrer seule après une coupure de courant.
- Journal des préventes de la borne en mémoire (pas de base SQLite dans PrestigePOS) ; les préventes restent
  tracées sur le serveur.
- Imprimantes Bluetooth Low Energy (BLE) seules non prises en charge (Bluetooth classique SPP uniquement).
