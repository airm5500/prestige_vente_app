# Prestige Mobile 4.7.1+29 — réponses du pharmacien (25/10/2026)

## A. Sécurité : journal de la console sans secret

Le journal HTTP du mode débogage (`LogInterceptor` de `DioClient`, `kDebugMode`) recopiait le corps des requêtes,
dont le **mot de passe** de la connexion. Les APK livrés ne sont pas en mode débogage, mais beaucoup de `print` d'erreur
sortaient aussi dans le journal du téléphone en production.

- `LogInterceptor` remplacé par `JournalHttpDebug` (`lib/utils/journal_debug.dart`), en mode débogage seulement. Il
  écrit la méthode, le chemin, le statut et la durée. Il n'écrit jamais :
  - le corps de la requête ou de la réponse (mot de passe, ventes, clients, ordonnances) ;
  - les en-têtes (cookies, `Authorization`, jetons, `X-Client-Ref`, `X-Poste`) ;
  - les paramètres (recherche d'un client ou d'un produit).

  Dans le chemin, tout segment qui n'est pas un nom de route devient `*` : identifiant de vente, clé de licence, clé
  `X-Client-Ref`.
- 82 `print` / `debugPrint` qui recopiaient une erreur (`$e`) passent par `journalErreur`. Ils écrivent le contexte
  et le type de l'erreur ; pour une `DioException`, aussi son type, le statut, la méthode et le chemin sans valeur.
  Le message de l'erreur n'est jamais écrit : il peut recopier une réponse du serveur, une adresse avec ses paramètres
  ou un contenu lu (QR d'un badge). Les autres journaux ne recopiaient déjà aucune donnée :
  - message du serveur (tiers payant) ;
  - détail de la licence ;
  - date d'une commande ;
  - erreurs du journal du terminal et du centre de support.
- Plus aucun `print` dans `lib/` : `flutter analyze lib test` passe de 253 à 173 remarques (les `avoid_print`).
- Test de non-régression `test/journal_debug_test.dart` (mode débogage, vrai HTTP). Après une connexion, la
  recherche d'un client, une réponse illisible et une création avec `X-Client-Ref`, le journal ne contient ni le mot
  de passe, ni l'identifiant, ni le cookie de session, ni la clé, ni le nom du client, ni le corps. Un garde-fou sur
  le code refuse tout `LogInterceptor`, tout `print`, et toute erreur ou tout corps recopiés dans la console.

## B. Nom de cet appareil : obligatoire, gardé sur l'appareil

Décision du pharmacien : le nom est **obligatoire**.

- **Sans nom enregistré** (nouvelle installation, réinstallation, ou 4.7.0 avec « Plus tard ») :
  - au lancement, après la configuration du serveur, l'étape « Nom de cet appareil » s'ouvre ;
  - elle est pré-remplie avec la marque et le modèle : un appui sur « Enregistrer » suffit ;
  - le retour Android est bloqué : « Saisissez le nom de cet appareil pour continuer. » ;
  - un nom vide, ou sans aucun caractère permis, est refusé.

  La proposition « Plus tard » de la 4.7.0 est retirée.
- **Réglages** : tant qu'aucun nom n'est enregistré, la carte « Nom de cet appareil (obligatoire) » est en tête et les
  réglages ne se quittent pas : « Saisissez le nom de cet appareil avant de quitter les réglages. ». C'est le cas dans
  la nouvelle interface comme dans l'interface d'origine. Le champ indique : « Gardé sur cet appareil : conservé lors
  des mises à jour de l'application. Après une désinstallation, il faut le saisir de nouveau. »
- **Nom déjà enregistré** : rien ne change, ni la connexion ni les ventes. Il n'est plus jamais demandé ; une mise à
  jour garde les préférences, et la clé `nom_appareil_v1` est figée (test).
- **Borne libre-service active au démarrage** : pas d'étape, car l'écran est vu par les clients. Le nom se règle dans
  les réglages, protégés par le code administrateur.

### Après une désinstallation (recherche demandée)

| Moyen | Résultat |
|---|---|
| Préférences de l'application | Gardées à chaque mise à jour ; effacées à la désinstallation. |
| Sauvegarde Android (Auto Backup) | Déjà permise ; les préférences en font partie, seul le stockage sécurisé est exclu (test). Un nom restauré compte comme enregistré. Elle demande les services Google et un compte de sauvegarde, souvent absents des Sunmi : peu fiable. |
| Licence | Licence de l'officine (`GET v1/licence/find`), sans identifiant ni donnée de l'appareil : rien à réutiliser. |
| Fichier dans les dossiers partagés | Depuis Android 11 (Sunmi V2s), une application réinstallée ne peut pas relire le fichier écrit par l'installation précédente sans le sélecteur de fichiers, ou sans une permission spéciale (`MANAGE_EXTERNAL_STORAGE`) ou dangereuse : écarté. |
| `ANDROID_ID` | Stable sur un appareil pour une clé de signature (Android 8+), garde sa valeur à la réinstallation, change à la remise à zéro d'usine. C'est un identifiant, pas un stockage : il ne sert qu'avec une table sur le serveur. |

Seule solution fiable : garder le nom **sur le serveur**, rattaché à l'appareil. C'est un changement du serveur, **non
fait**, proposé au coordinateur :
- l'application envoie une empreinte de l'appareil, SHA-256 de `ANDROID_ID` et du nom du paquet, jamais
  l'identifiant en clair ;
- le serveur garde « empreinte → nom » ;
- à la première connexion après une réinstallation, l'application relit le nom et le propose pré-rempli.

Le nom ne contient aucun secret.

## C. Transmission au serveur

`docs/serveur/TRANSMISSION_SERVEUR_2026-10-15.md` : demandes facultatives 53 et 54 (`X-Poste` dans le journal des
connexions ; poste d'encaissement d'une clôture mobile money par la notification du fournisseur) et 55
(Pharmacien : `peutChangerStatut` dans la liste des péremptions courtes).

## Tests

- `test/journal_debug_test.dart` (non-régression, sécurité).
- `test/nom_appareil_test.dart` :
  - nom obligatoire : vide refusé, nom par défaut enregistré tel quel ;
  - mise à jour depuis la 4.7.0, avec ou sans nom ;
  - règles de sauvegarde Android.
- `test/nom_appareil_e2e_test.dart` :
  - nouvelle installation : étape pré-remplie, retour bloqué, « Enregistrer » suffit, vente avec ce nom ;
  - « Caisse mobile 1 » sur la création et la clôture ; nom vide refusé ;
  - nom déjà enregistré : aucune étape ;
  - mise à jour d'une 4.7.0 sans nom : demandé une fois, plus au lancement suivant ;
  - première configuration : réglages non quittables ;
  - ergonomie : téléphone ×1,3 et Sunmi V2s ×2.
- `test/parametres_test.dart` : carte obligatoire et mention de conservation (téléphone, Sunmi V2s, texte ×1 à ×2).
- `test/flutter_test_config.dart` : chaque test part d'un appareil déjà nommé, en mémoire ; les tests de l'étape
  repartent d'un appareil sans nom.
