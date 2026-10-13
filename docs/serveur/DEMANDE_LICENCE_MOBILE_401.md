# Demande à la session serveur — les applications mobiles ne démarrent plus (licence en 401)

À transmettre à la session qui maintient `airm5500/prestige` (branche `claude/new-session-xm8ptu`).

## 1. Constat (terrain, serveur de l'officine)

Depuis la dernière mise à jour du serveur, **les trois applications mobiles** (Prestige Mobile / comptoir,
Prestige Pharmacien, Prestige Inventaire) restent bloquées à l'ouverture :

```
GET http://192.168.129.48:8080/prestige/api/v1/licence/find
→ 401 Unauthorized
```

Pourtant une licence valide existe en base (`date_end` = 2027-02-23).

## 2. Cause

Commit **`6919e280` « Sécurité : accès sans connexion fermés (audit du 12/10) »**, fichier
`src/main/java/filter/AuthenticationFilter.java` : la liste `SKIP_PATHS` a été réduite. Ont notamment été
retirés :

```
"v1/licence/find", "v1/licence/save/", "v1/info", "v1/modereglement", "v1/motifreglement",
"v1/ws/", "v1/ws/inventaires", "v1/ws/inventaires/rayons", "v1/ws/inventaires/details", …
```

Or **les trois applications lisent la licence AVANT la connexion de l'utilisateur** (écran de lancement :
« l'application est-elle activée pour cette officine ? »). Sans session, `licence/find` répond maintenant 401
→ les applications ne peuvent plus démarrer.

Les autres routes retirées (`v1/ws/inventaires*`, `v1/info`, `v1/modereglement`…) ne posent pas de problème :
les applications les appellent **après** la connexion, avec le cookie de session (aucune application
n'utilise les en-têtes `X-User-Info` / `X-Token-Exp`, désactivés par le même commit — vérifié dans les trois
dépôts).

## 3. Correction demandée (minimale, sans rouvrir ce que l'audit a fermé)

### 3.1 Indispensable : rouvrir la LECTURE de la licence

Dans `AuthenticationFilter.SKIP_PATHS`, ajouter :

```java
// Lecture de la licence par les applications mobiles AVANT connexion (écran de lancement :
// « l'application est-elle activée pour cette officine ? »). Lecture seule.
"v1/licence/find",
```

Recommandation sécurité (au choix de la session serveur) : comme la route devient publique, ne renvoyer que
ce dont les applications ont besoin — `date_start`, `date_end`, `type_licence` et un indicateur `valide` —
et **masquer la clé** (`id`) ou n'en renvoyer que les 4 derniers caractères. Les applications n'utilisent
pas la clé complète pour décider (elles lisent les dates et le type).

### 3.2 Ne PAS rouvrir `v1/licence/save/` tel quel

`GET /v1/licence/save/{clé}` **supprime la licence en place et enregistre n'importe quelle clé sans la
vérifier** (`LicenceRessource.save` → `LicenceService.save`). L'ouvrir sans connexion permettrait à n'importe
qui sur le réseau de désactiver l'officine. Par ailleurs l'ancienne exemption `"v1/licence/save/"` ne
fonctionnait déjà pas (`SKIP_PATHS.contains(path)` compare le chemin exact, la clé est dans le chemin).

Deux options :
- **(recommandée)** laisser `save` derrière la connexion : les applications activeront la licence **après**
  connexion d'un administrateur (adaptation côté applications, déjà prévue) ;
- ou une exemption contrôlée : `POST v1/licence/activer` (clé dans le corps), qui **vérifie la clé**
  (signature/format) avant de remplacer quoi que ce soit, avec limitation des essais.

### 3.3 Rappel pour la suite

Avant de fermer une route dans `SKIP_PATHS`, vérifier les appels **avant connexion** des applications
mobiles. Aujourd'hui, la seule route qu'elles appellent sans session est : `v1/licence/find`
(+ `v1/officine` et `v1/user/auth`, restées ouvertes).

## 4. Vérification après déploiement

```
curl -i http://<serveur>:8080/prestige/api/v1/licence/find      → 200 + JSON licence (sans session)
curl -i http://<serveur>:8080/prestige/api/v1/ws/inventaires     → 401 sans session (reste fermé)
curl -i http://<serveur>:8080/prestige/api/v1/licence/save/XYZ   → 401 sans session (reste fermé)
```

Puis ouvrir les trois applications : elles doivent passer l'écran de lancement.

## 5. Côté applications (proposition, en attente de validation du pharmacien)

Les applications peuvent aussi devenir tolérantes : si `licence/find` répond 401 (serveur qui exige une
session), elles afficheront l'écran de connexion et vérifieront la licence **juste après** la connexion, au
lieu de rester bloquées. Le correctif serveur 3.1 reste nécessaire pour retrouver le fonctionnement normal
(vérification de licence avant connexion).
