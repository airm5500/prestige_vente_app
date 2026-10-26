# Prestige Mobile 4.10.0+36 — « Pointer » ouvre Prestige Pointage

Prestige Pointage est une borne de pointage sans compte (demande 57). Voir `docs/prestigepointage/README.md`.

## Ce qui change

- **Bouton « Pointer (Prestige Pointage) »** sur les écrans de connexion (nouvelle interface, « Qui êtes-vous ? »,
  interface d'origine).
- **Tuile « Pointer »** dans le groupe Équipe de l'accueil.
- Les deux ouvrent l'application Prestige Pointage installée sur le même terminal :
  - rien n'est transmis ;
  - la session de vente n'est pas touchée ;
  - aucune requête n'est faite.
- **Masqués** quand Prestige Pointage n'est pas installée. La présence est relue au lancement et au retour au premier
  plan.
  - Elle passe par le canal natif `prestige/pointage`, limité au paquet `com.dici.prestigepointage`.
  - `<queries>` est déclaré dans le manifeste (Android 11 et plus).
  - Si l'application a été désinstallée entre-temps, un message s'affiche et le bouton disparaît.
- La tuile ne fait pas partie des 23 menus d'origine : elle n'est ni organisable ni proposée en favori.

## Ce qui ne change pas

- Le **terminal de pointage** de Prestige Mobile (mode terminal, kiosque, confirmation de la file, titre) est
  inchangé. Les nouvelles options de `TerminalPointageScreen` ne servent qu'à Prestige Pointage et leurs valeurs par
  défaut gardent le comportement d'avant.
- **Identité de l'APK** : applicationId, nom, icône, permissions et version sont toujours lus dans `pubspec.yaml`.
  - Le job CI `prestige-mobile-identique` compare l'identité et les permissions de l'APK à celles de la 4.9.4+35.
  - Il ne s'agit que de la saveur Gradle `mobile`, choisie par défaut : `flutter build apk --release` construit
    Prestige Mobile comme avant.
- Le nom de l'APK est inchangé : « prestigepos-release-4.10.0.apk ».
- L'artefact de la CI est inchangé : `app-release.apk`.

## Tests

- `test/prestigepointage/mobile_pointer_e2e_test.dart`, sur l'application entière :
  - application installée : bouton avant la connexion, puis tuile après ; ouverture sans requête, session gardée ;
  - application absente : ni bouton ni tuile, 23 menus.
- `test/prestigepointage/prestigepointage_test.dart` :
  - bouton masqué, visible, canal absent, désinstallée entre-temps ;
  - tuile ajoutée au groupe Équipe seulement si l'application est installée.
- `test/prestigepointage/prestigepointage_garde_test.dart` : identité de Prestige Mobile et valeurs par défaut du
  terminal.
- Suite complète inchangée et verte.
