# Prestige Mobile — note de version 4.0.0 (versionCode 8)

Dernière version publiée sur le magasin Sunmi : 3.3.1 (versionCode 7). La refonte compte comme une nouvelle
grande version : **4.0.0+8**. Les règles de numérotation sont dans `docs/VERSIONS_SUNMI.md`.

## Nouveautés

- **Connexion repensée** : nouvel écran de lancement (réglages, serveur, licence cochés au fur et à mesure) et
  nouvel écran de connexion, avec l'option « Qui êtes-vous ? » (derniers utilisateurs du terminal) ; mot de passe
  mémorisé chiffré ; bouton « Appeler l'assistance ». Si la session expire, l'application se reconnecte seule
  (« Rester connecté ») ou revient à la connexion avec un message clair.
- **Réserve** (administrateur) : réapprovisionnements manuels et suggestions automatiques, de la suggestion au
  traitement.
- **Analyse posologie** : écran autonome, et depuis la vente en cours.
- **Fiche client** : onglet dans les Ordonnances des clients, consultation et saisie selon les droits.
- **Photo de pointage** : au pointage par badge, une photo de contrôle (caméra frontale) évite le pointage pour un
  collègue ; pointage présence avec boutons Arrivée / Départ.
- **Version visible** : « Version X.Y.Z+N » en bas de l'écran de connexion et dans les Réglages (ancienne et
  nouvelle interface), lue dans l'application installée.
- **Tests** : socle complet (unitaires, écrans, intégration contre un faux serveur Prestige, application entière,
  ergonomie sur 4 tailles d'écran, non-régression), lancé à chaque envoi par la CI. Un test vérifie désormais que la
  version est au-dessus de celle publiée sur Sunmi.

## Numéro de version

- Une seule source : `pubspec.yaml` (`version: 4.0.0+8`) ; Gradle la reprend (`flutter.versionCode`,
  `flutter.versionName`), plus aucun numéro en dur (l'ancien Gradle forçait `versionCode = 8`,
  `versionName = "3.4.1"` alors que `pubspec.yaml` disait 1.2.0).
- Le centre de support et le banc d'essai des ordonnances envoient / notent la version réelle installée (même
  format X.Y.Z qu'avant) au lieu d'une constante recopiée.
