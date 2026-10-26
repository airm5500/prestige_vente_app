# Prestige Pointage — borne de pointage sans compte

Application Android **séparée** de Prestige Mobile. Elle sert de borne : les employés y pointent avec leur badge, sans
compte. Le terminal est partagé et n'est jamais connecté à un compte.

- Identifiant : `com.dici.prestigepointage`.
- Nom affiché : « Prestige Pointage », avec sa propre icône.
- Elle s'installe **à côté** de Prestige Mobile sur le même terminal.
- Côté serveur, elle repose sur la **demande 57** (commit serveur `31622a33`).

Elle est construite depuis **ce dépôt**, comme une saveur Android `pointage` :

| | Prestige Mobile | Prestige Pointage |
|---|---|---|
| Saveur Gradle | `mobile` (par défaut) | `pointage` |
| Point d'entrée | `lib/main.dart` | `lib/main_pointage.dart` |
| Version | `pubspec.yaml` | `android/app/prestigepointage-version.properties` |
| Manifeste, nom, icône | `android/app/src/main` | `android/app/src/pointage` (fusionné pour cette saveur seulement) |
| Code propre | — | `lib/prestigepointage/` (le terminal `lib/rh` est réutilisé) |

## Construire l'APK sur un poste

Il faut Flutter 3.32 et le SDK Android (comme pour Prestige Mobile).

```
flutter pub get
flutter build apk --release --flavor pointage -t lib/main_pointage.dart
```

- APK produit : `build/app/outputs/flutter-apk/app-pointage-release.apk`.
- Sans `--flavor`, `flutter build apk --release` construit toujours **Prestige Mobile**, à l'identique, car
  `default-flavor: mobile` est défini dans `pubspec.yaml`.
- La signature est la même que celle de Prestige Mobile (`android/key.properties`, sinon la clé de débogage).
- Sur la CI, le job `prestigepointage` de `build-apk.yml` construit l'APK et le contrôle (identifiant, version, nom,
  caméra, NFC, pas de position). Il le publie dans l'artefact `prestigepointage-apk`.

## Google Play (facultatif)

Le workflow est `.github/workflows/play-pointage.yml`. Il suit les mêmes conventions que Prestige Mobile (secrets,
clé d'envoi) et vise la piste « Test interne ».

1. **Créer l'application** dans la Play Console, avec l'identifiant `com.dici.prestigepointage` et le nom « Prestige
   Pointage ». Remplir la fiche, la politique de confidentialité, la classification et la sécurité des données
   (caméra pour la photo de contrôle, NFC ; aucune position).
2. **Premier envoi, à la main.** Google l'exige pour une nouvelle application. À chaque modification de Prestige
   Pointage, la CI produit l'App Bundle signé, dans l'artefact `prestigepointage-aab`, si les secrets de la clé
   d'envoi existent. Il suffit de le déposer dans « Test interne ».
3. **Envois suivants.** Écrire la version (par exemple `1.0.0+1`) en première ligne de `android/DEMANDE_PLAY_POINTAGE`,
   puis pousser. Seule une modification de ce fichier déclenche un envoi ; il faut aussi que le secret
   `PLAY_SERVICE_ACCOUNT_JSON` existe. Ce fichier n'existe pas dans le dépôt : aucun envoi n'a été fait.

Sans Google Play, il suffit d'installer l'APK de l'artefact `prestigepointage-apk`, par exemple sur un Sunmi.

## Enrôlement (une seule fois, par un administrateur)

1. Ouvrir Prestige Pointage et saisir l'adresse du serveur Prestige, comme dans Prestige Mobile. Appuyer sur
   « Vérifier et continuer ».
2. Saisir le **code administrateur** de l'appareil, le même que dans Prestige Mobile.
3. Saisir le **compte d'un administrateur** : droit Ressources humaines `P_SM_RH` ou profil administrateur.
   - Il ne sert qu'à l'enrôlement et il est **déconnecté aussitôt**.
   - Le mot de passe n'est pas gardé.
4. Donner le **nom de l'appareil**, obligatoire (pré-rempli avec la marque et le modèle), par exemple « Borne entrée ».
5. La borne est prête. Elle ne se connecte plus jamais à un compte.
   - Chaque appel est signé avec sa clé : `v1/borne-pointage/*`, HMAC-SHA256.
   - La clé est gardée dans le stockage sécurisé d'Android (Keystore). Elle n'est jamais affichée ni journalisée, et
     elle est exclue des sauvegardes.

Ensuite :

- **Retirer une borne** : Prestige web › RH › Bornes de pointage › Retirer. La borne affiche alors « Appareil retiré :
  faites-le enrôler à nouveau ». Le même appareil réenrôlé remplace aussi l'ancienne borne.
- **Administration** : bouton en haut à droite, protégé par le code administrateur. On y trouve :
  - l'état de la borne ;
  - « Vérifier le serveur et envoyer les pointages » ;
  - la photo de contrôle ;
  - les empreintes ;
  - « Enrôler à nouveau » et « Retirer la borne de cet appareil » ;
  - « Fermer Prestige Pointage ».
- **Empreintes** :
  - Avec le partage activé sur le serveur (`KEY_EMPREINTES_PARTAGEES=1`), les modèles enrôlés ailleurs sont recopiés
    à l'ouverture, puis toutes les 15 min.
  - Sans le partage, l'enrôlement se fait sur la borne : Administration › Empreintes, avec un compte `P_SM_RH` connecté
    **temporairement** et déconnecté au retour.
  - Les modèles restent sur la borne, exactement comme en 4.4.0.

## Pointage

- **Badge** : QR imprimé `PRESTIGE-BADGE|1|…` ou code-barres 1D lus par la douchette ou la caméra, ou NFC (UID).
  - Le numéro du badge est cherché dans la copie des employés, avec les mêmes règles que la 4.6.2.
  - Le secret du QR n'est **jamais** envoyé, journalisé ni gardé.
- **Empreinte** : bouton « Pointer avec mon empreinte » si des modèles sont présents.
- **Confirmation** : « Bonjour Awa — ENTRÉE 08:02 ». Un même badge relu dans les 2 minutes est ignoré (« vous avez
  déjà pointé »). La photo de contrôle est prise si elle est activée.
- **Hors ligne** :
  - Le pointage est gardé sur la borne, dans une file SQLite, avec un identifiant obligatoire.
  - Il est envoyé **seul** au retour du serveur. Un renvoi du même pointage ne crée rien de plus (`deja`).
  - Avertissement à l'écran pour un pointage en attente depuis plus de 60 h, car le serveur le refuse au-delà de 72 h.
- **États signalés** par un bandeau :

  | État | Message |
  |---|---|
  | Borne retirée | « Appareil retiré : faites-le enrôler à nouveau » |
  | Hors du réseau de l'officine | « Borne utilisable seulement sur le réseau de l'officine » |
  | Serveur sans la demande 57 | « Serveur à mettre à jour » |
  | Horloge décalée de plus de 4 min (en-tête `Date` du serveur) | « Heure du terminal incorrecte », avec l'écart et l'heure du serveur |
  | Trop de demandes | La borne attend le délai `Retry-After` du serveur |

  Dans tous ces cas, les pointages restent en file.

## Sécurité

- Seuls `X-Borne`, `X-Borne-Date`, `X-Borne-Empreinte` et `X-Borne-Signature` circulent. La clé n'est que dans le
  stockage sécurisé.
- La signature porte sur les **octets exacts envoyés**.
- Le format est vérifié contre le code Java du serveur : `test/prestigepointage/signature_borne_test.dart`.
- L'empreinte de l'appareil (demande 56) ne sert qu'aux en-têtes et à l'enrôlement. ANDROID_ID ne quitte jamais le
  code natif.
- Aucune donnée d'employé n'est journalisée. La copie des employés ne contient que les champs réduits du serveur.
