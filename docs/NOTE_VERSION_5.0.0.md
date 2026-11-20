# Prestige Mobile V3 5.0.0+49 : nouvelle application (nouvel identifiant, nouveau nom, nouvelle icône)

Décision du pharmacien (20/11/2026). **Prestige Mobile V3 est une NOUVELLE application Android**, publiée sur une
**nouvelle fiche** du magasin Sunmi (et, le moment venu, une nouvelle application dans la Play Console). Elle
s'installe **à côté** de l'ancienne « Prestige Mobile » : les deux cohabitent sur le même terminal jusqu'à ce que
toutes les officines soient passées à la V3.

Seule l'identité change. **Le fonctionnement est identique à la 4.15.2+48** (mêmes écrans, mêmes règles, mêmes
échanges avec le serveur, mêmes permissions).

| | Ancienne application | Prestige Mobile V3 |
|---|---|---|
| Identifiant Android (applicationId) | `com.dici.prestige_vente_app` | **`com.dici.prestigemobile.v3`** |
| Nom sous l'icône | Prestige Mobile | **Prestige Mobile V3** |
| Icône | panier (ancienne) | panier bleu avec le badge vert **« V3 »** (icône adaptative, fond blanc) |
| Version | dernière version déjà en ligne sur sa fiche | **5.0.0+49** |
| Fiche Sunmi | **gardée telle quelle** (voir ci-dessous) | nouvelle fiche |

## 1. L'ancienne fiche Sunmi reste telle qu'elle est

Certaines officines ont encore d'anciens serveurs Prestige. La fiche de l'ancienne Prestige Mobile
(`com.dici.prestige_vente_app`) sur le magasin Sunmi **garde la version déjà en ligne** : rien n'y est republié. Les
terminaux de ces officines continuent avec l'ancienne application, sans changement.

Pour information seulement (aucune nouvelle publication de l'ancienne fiche n'est prévue) : dernier commit construit
avec l'ancien identifiant `com.dici.prestige_vente_app` :
**`48528e8647bc3819f9e461933e210e630579b465`** (Prestige Mobile 4.15.2+48, branche `pres-/tender-thompson-ang0ls`).

## 2. Passer un terminal à la V3

Android donne à chaque application **son propre espace de données**. La V3 **ne peut rien lire** de l'ancienne
application, et ce n'est pas un défaut : c'est la règle d'Android. Au premier lancement, la V3 est donc **vide**,
comme une installation neuve :

1. **Avant tout : synchroniser les ventes hors ligne de l'ancienne application.** Ouvrir l'ancienne Prestige Mobile,
   serveur joignable, et vérifier qu'aucune vente hors ligne n'attend (bandeau hors ligne, Réglages › Hors ligne ›
   « Ventes hors ligne » : 0 en attente). **Une vente hors ligne restée dans l'ancienne application n'est pas reprise
   par la V3** ; si l'ancienne application est désinstallée avant, ces ventes sont perdues.
2. Installer Prestige Mobile V3 depuis sa nouvelle fiche Sunmi (l'ancienne reste installée).
3. **Reconfigurer** la V3 sur chaque terminal (chaque appareil est à reconfigurer), comme une première installation :
   - nom de cet appareil (étape obligatoire au premier lancement, pré-rempli avec la marque et le modèle) ;
   - « Configuration » (code administrateur : le code par défaut 1234 doit être changé à la première utilisation) :
     adresse du serveur (local, distant, port, nom de l'application) ;
   - réglages propres au terminal : modes de paiement proposés à l'encaissement (une installation neuve coche Wave,
     Orange, MTN, Moov et carte bancaire, comme avant), imprimante et nombre de copies du ticket, taille de l'écran,
     borne, connexion rapide, etc. ;
   - connexion de chaque utilisateur (« Rester connecté », PIN personnel : à refaire).
   - Le nom de l'appareil n'est pas retrouvé automatiquement par le serveur (demande 56) : l'empreinte de l'appareil
     dépend de l'identifiant de l'application ; il suffit de le saisir à l'étape obligatoire.
4. Vérifier une vente, puis, quand tout va bien et que l'ancienne application n'a plus de vente hors ligne,
   désinstaller l'ancienne application si l'officine n'en a plus besoin.

**Bandeau de la V3.** Si l'ancienne application est encore installée sur le terminal, l'écran de connexion de la V3
affiche une fois : « Ancienne application installée : synchronisez ses ventes hors ligne avant de la désinstaller. »
(bouton « Compris » : plus jamais affiché sur ce terminal). La V3 sait seulement que l'ancienne application est
installée (visibilité du paquet déclarée dans `android/app/src/mobile/AndroidManifest.xml`) : elle ne lit aucune de
ses données et ne l'ouvre jamais.

## 3. Ce qui change dans le projet

- `android/app/build.gradle.kts` : `applicationId = "com.dici.prestigemobile.v3"` (saveur `mobile`, par défaut). Le
  `namespace` reste `com.dici.prestige_vente_app` : paquet Kotlin de `MainActivity` et des ponts natifs, classe `R`,
  activité retirée par PrestigePOS (`com.dici.prestige_vente_app.MainActivity`). Les canaux natifs
  (`prestige/pointage`, empreinte Sunmi, NFC, kiosque) ne dépendent pas de l'identifiant. Aucun FileProvider, aucun
  lien profond, aucune configuration Firebase / google-services, aucune chaîne de notification ni WorkManager.
  Signature : inchangée (clé debug pour les APK Sunmi, clé d'envoi pour Google Play).
- `android/app/src/main/AndroidManifest.xml` : `android:label="Prestige Mobile V3"`, `android:roundIcon`.
- `android/app/src/mobile/AndroidManifest.xml` (nouveau) : `<queries>` de l'ancienne application (saveur `mobile`
  seulement). `MainActivity.kt` : canal `prestige/pointage`, méthode `estInstallee` acceptée aussi pour
  `com.dici.prestige_vente_app` (jamais `ouvrir`).
- Icônes : `android/app/src/main/res/mipmap-*/launcher_icon.png` et `launcher_icon_round.png` (icône héritée),
  `launcher_icon_foreground.png` (avant-plan adaptatif, contenu dans la zone de sécurité de 66 dp : aucun masque
  — cercle, carré arrondi, « squircle », goutte — ne coupe le badge « V3 »), `mipmap-anydpi-v26/*.xml`, fond blanc
  (`values/couleurs_prestigemobile.xml`). Anciens `ic_launcher.png` inutilisés retirés. Logo des écrans de lancement
  et de connexion : `assets/icon/icon_v3.png`.
- Nom affiché : constante `nomAppli` (`lib/identite_appli.dart`) : lancement, connexion, « Qui êtes-vous ? »,
  accueil sans nom d'officine, ancienne interface, titre de la tâche Android, journal PDF, « Envoyé depuis … ». Le
  champ `application` envoyé au serveur du support reste « Prestige Mobile » (contrat du serveur).
- PrestigePOS et Prestige Pointage : **inchangés** (leurs saveurs ont leur propre identifiant, nom et icône).

## 4. CI et Google Play

- `build-apk.yml` : badging de l'APK contrôlé (`com.dici.prestigemobile.v3`, « Prestige Mobile V3 », version de
  `pubspec.yaml`, activité `com.dici.prestige_vente_app.MainActivity`) ; comparaison avec la 4.9.4+35 : permissions
  identiques, identité identique sauf l'identifiant et le nom.
- `play.yml` : paquet `com.dici.prestigemobile.v3`, nom « Prestige Mobile V3 ». L'AAB est toujours construit (contrôle
  sans secret, AAB signé si la clé d'envoi existe) ; l'envoi reste gardé (secrets + `android/DEMANDE_PLAY`). **Une
  nouvelle application Google Play exige un premier envoi À LA MAIN** de l'AAB dans la Play Console
  (`docs/android/README.md`, « Prestige Mobile V3 »).

## 5. Tests

- `test/v3_identite_test.dart` (non-régression) : identifiant, namespace, nom, icônes (tailles, zone de sécurité de
  l'avant-plan à chaque densité), visibilité de l'ancienne application, canal natif, CI, Play, note.
- `test/v3_premier_lancement_e2e_test.dart` (bout en bout) : installation neuve sans aucune donnée → nom de l'appareil
  → adresse par défaut injoignable → Configuration sous code (changement du code par défaut) → serveur → licence →
  connexion → vente terminée avec le nom saisi ; bandeau de l'ancienne application (affiché, « Compris », plus jamais ;
  absent sans elle ou si la détection échoue).
- Tests mis à jour (nom et identifiant attendus) : `widget_test`, `connexion_lancement_test`, `android_play_test`,
  `prestigepointage/prestigepointage_garde_test`, `outils/version_installee.dart`.
- Captures de magasin (hors CI) : `test/outils/captures_store_v3_test.dart`.
