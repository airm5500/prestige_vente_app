# Prestige Mobile — note de version 4.0.2 (versionCode 10)

Suite de la 4.0.1+9 (pas encore publiée sur le magasin Sunmi, dernière version publiée : 3.3.1 / 7).
Numérotation : `docs/VERSIONS_SUNMI.md` (+N augmenté de 1 : **4.0.2+10**).

Deux corrections autorisées par le pharmacien, sans autre changement.

## ANO-08 — Interface d'origine : « Serveur injoignable » au démarrage

- **Symptôme** : avec l'ancienne interface activée, la première vérification de la licence partait vers
  `http://localhost:8080` au lieu du serveur configuré, d'où « Serveur injoignable » à chaque démarrage ;
  « Réessayer » fonctionnait.
- **Cause** : l'`ApiService` est fourni par un `ProxyProvider` à partir des réglages. Il est créé dès la première
  image (le bandeau hors ligne `HorsLigneScope` le lit), **avant** la lecture des réglages : adresse vide, donc
  `localhost` par défaut (`SettingsProvider.baseUrl`), et le client HTTP partagé prend cette adresse.
  `AncienSplashScreen` lit ensuite les réglages puis fait `await Future.delayed(Duration.zero)` en pensant laisser
  le temps au framework de propager l'adresse ; mais ce délai nul ne laisse passer **aucune image**, et le
  `ProxyProvider` ne recrée l'`ApiService` qu'à l'image suivante. L'écran récupérait donc l'ancien `ApiService`
  (`localhost`). Au « Réessayer », des images étaient passées : l'adresse était bonne.
- **Correction** (`lib/screens/splash_screen.dart`, seulement cet ordre d'initialisation) : appareil configuré et
  adresse de l'`ApiService` différente de celle des réglages → attente de la fin de l'image suivante
  (`WidgetsBinding.instance.endOfFrame`) avant la vérification de la licence. Écran d'origine inchangé (aspect,
  attente de 2 s, messages, boutons), nouvelle interface non modifiée.
- **Sans configuration** : comportement d'origine conservé (aucune adresse → Configuration, aucune requête). À la
  toute première installation (réglages jamais enregistrés), l'adresse utilisée est celle des réglages par défaut
  (`192.168.1.50`), comme le « Réessayer » de l'écran d'origine, l'adresse affichée dans son message, et la nouvelle
  interface — plus jamais `localhost`.

## ANO-02 — Puce « Début / Contient » trop petite au toucher

- **Symptôme** : la puce de la recherche (Vente et Recherche article) n'avait que 32 dp de haut (< 48 dp).
- **Correction** (`lib/services/search_mode.dart`) : **zone tactile d'au moins 48 × 48 dp** autour de la puce
  (même principe que `MaterialTapTargetSize.padded`). **Aspect inchangé** : même fond, même bordure, 32 dp de haut,
  centrée dans la zone. Toucher juste au-dessus ou au-dessous de la puce la bascule aussi.
- **Mise en page** : la puce est dans le suffixe du champ de recherche, qui fait déjà 48 dp de haut : aucune
  hauteur ne change. Le rendu de référence à 360 px (`test/responsive_reference_360.json`) est **identique, non
  modifié**. Seule la largeur de la zone peut gagner quelques dp quand le libellé « Début » est plus étroit que
  48 dp ; la vente avec clavier ouvert (total, Prévente, Encaisser) reste entièrement visible et rien ne déborde aux
  tailles Sunmi (Compact automatique), téléphone et tablette (`ergonomie_test`, `ergonomie_taille_ecran_test`,
  `vente_clavier_test`, `responsive_test`).

## Tests

- `test/widget_test.dart` : démarrage avec l'interface d'origine **réactivé** (licence vérifiée une seule fois,
  pas de « Serveur injoignable », connexion d'origine).
- `test/non_regression_test.dart` (anomalies corrigées) :
  - ANO-08, interface d'origine **et** nouvelle interface : la **toute première requête** de l'application est la
    licence sur le serveur configuré, aucune requête vers un autre hôte ;
  - ANO-08, sans configuration (deux interfaces) : Configuration / « Première utilisation », aucune requête ;
  - ANO-08, première installation : même adresse au premier appel dans les deux interfaces et au « Réessayer » ;
  - ANO-02 : zone tactile ≥ 48 × 48 dp, puce visible toujours haute de 32 dp et centrée, bascule par le bord de la
    zone, règle Android des cibles tactiles.
- `test/ergonomie_test.dart` / `test/ergonomie_taille_ecran_test.dart` : contrôle « cibles » **réactivé** pour
  `vente` et `recherche_globale`.
- Outil : le faux serveur en mémoire note toutes les adresses demandées, y compris refusées
  (`FauxServeurPrestige.tentatives`).
