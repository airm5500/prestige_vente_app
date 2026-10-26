# Prestige Pointage 1.0.0+1 — première version

Demande du pharmacien :

> « je veux une application spéciale qui n'a pas besoin de compte pour qu'on pointe ; […] on doit pouvoir pointer,
> scanner un badge pour pointer »

Elle repose sur la demande 57 du serveur, commit `31622a33`. Mode d'emploi : `docs/prestigepointage/README.md`.

## Contenu

- **Application séparée.** Elle est construite depuis le dépôt de Prestige Mobile, comme saveur `pointage`.
  - Identifiant `com.dici.prestigepointage`, nom « Prestige Pointage », icône propre.
  - Point d'entrée `lib/main_pointage.dart`, version propre `android/app/prestigepointage-version.properties`.
  - La borne ne demande pas la position.
- **Enrôlement unique** : serveur → code administrateur → compte administrateur → nom de l'appareil obligatoire.
  - Le compte administrateur est temporaire (`P_SM_RH` ou admin) ; le nom de l'appareil est pré-rempli.
  - Ensuite `POST v1/rh/bornes`, avec l'empreinte de la demande 56.
  - Identité et clé sont gardées dans le stockage sécurisé, puis la session est fermée aussitôt.
  - Plus aucune connexion ensuite.
- **Client signé `v1/borne-pointage/*`** : `moi`, `employes`, `empreintes`, `pointages`, `pointages/{id}/photo`.
  - HMAC-SHA256 sur les octets exacts envoyés.
  - Date en millisecondes, strictement croissante, pour éviter qu'une requête soit prise pour un rejeu.
- **Terminal de pointage** (`lib/rh`, réutilisé) :
  - badge QR / 1D / NFC, empreinte, confirmation « Bonjour <prénom> — ENTRÉE hh:mm » ;
  - relecture de moins de 2 min ignorée, photo de contrôle ;
  - mode borne dès l'ouverture ;
  - texte plafonné à ×1,3 sur l'écran de la borne seulement.
- **Copie des employés** relue toutes les 15 min.
- **Empreintes** : synchronisation toutes les 15 min si le partage est actif. Avec DESACTIVE, enrôlement local par un
  compte RH temporaire.
- **File hors ligne** :
  - envoi automatique sans confirmation dès que le serveur répond ;
  - vérification toutes les minutes tant qu'il ne répond pas ;
  - renvoi idempotent (`deja`) ;
  - avertissement au-delà de 60 h, avant le refus du serveur à 72 h.
- **États** : borne retirée, hors réseau, serveur ancien, horloge décalée (en-tête `Date`), 429 avec `Retry-After`.
  Chaque état a son message, et le pointage reste en file.
- **CI** :
  - l'APK est construit et contrôlé (job `prestigepointage`, artefact `prestigepointage-apk`) ;
  - l'App Bundle Google Play est produit par `play-pointage.yml` ;
  - l'envoi ne part que par `android/DEMANDE_PLAY_POINTAGE`, qui n'est pas créé.

## Écarts entre la réponse écrite du serveur et son code (on suit le CODE)

1. **Ordre du filtre** :
   1. blocage de l'adresse (429) ;
   2. réseau (403 `RESEAU`) ;
   3. borne, empreinte, date à ±300 s et signature (401 `BORNE`) ;
   4. rejeu sur 10 min (401 `BORNE`) ;
   5. borne retirée (401 `REVOQUEE`) ;
   6. débit, 120 appels par minute (429 + `Retry-After: 60`).
2. **Refus du pointage** (futur de plus de 2 min, plus de 72 h, doublon, id invalide) : ils arrivent en **HTTP 200**
   `{success:false, msg}`, pas en 4xx. L'application les traite comme des refus du serveur, qui ne sont pas renvoyés.
3. **Sens** : si l'application ne l'envoie pas, le serveur enregistre `INCONNU` ; il ne le déduit pas. L'application
   l'envoie donc toujours.
4. **Serveur ancien** : le filtre n'est pas `@PreMatching`. Un serveur sans la demande 57 répond **404** ; un 401 sans
   code est aussi traité comme un serveur ancien.
5. **En-tête `X-Borne` sur une autre route**, par exemple `v1/officine` : 401 `BORNE`. La borne n'appelle donc aucune
   autre route avec ses en-têtes.

## Tests

| Catégorie | Fichier | Ce qu'il vérifie |
|---|---|---|
| Unitaires | `prestigepointage/signature_borne` | vecteurs calculés par le code Java du serveur |
| Unitaires | `prestigepointage/prestigepointage` | identité, coffre, messages, multipart, en-têtes, 60/72 h, « Pointer » |
| Intégration | `prestigepointage/client_borne` | faux serveur appliquant les règles réelles |
| E2E | `prestigepointage/pointage_e2e` | voir la liste ci-dessous |
| Réseau | `reseau/prestigepointage_reseau` | vrai HTTP : paramètres encodés, JSON accentué, multipart, coupure, refus |
| Ergonomie | `prestigepointage/pointage_ergonomie` | Sunmi V2s, téléphones, tablette, texte ×1 / ×1,3 / ×2 |
| Performance | `performance/prestigepointage_perf` | 2 000 signatures, 2 000 employés, 2 000 badges |
| Non-régression | `prestigepointage/prestigepointage_garde` | version, saveurs, manifestes, CI, Play, secret lu seulement pour signer, terminal de Prestige Mobile inchangé |

Le test e2e couvre :

- l'enrôlement, avec l'étape du nom obligatoire et la déconnexion ;
- le compte sans le droit ;
- le pointage par QR (secret absent du réseau, du journal et de la file), par code 1D et par NFC ;
- la file hors ligne puis l'envoi automatique, et le renvoi idempotent ;
- la borne retirée puis réenrôlée, la file partant ensuite ;
- RESEAU, serveur ancien, horloge décalée ;
- les empreintes partagées, et DESACTIVE avec une connexion RH temporaire.
