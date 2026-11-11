# Prestige Mobile 4.12.1+42 : retour des manquants abandonné (serveur du 11/11)

Correction de 4.12.0+41, après la réponse du serveur à la demande 61 (11/11). Le serveur a changé deux choses sur le
retour des manquants d'un BL (demande 59) :

1. un retour des manquants **abandonné** (`statut: "is_Abandoned"`) ne compte plus : `POST
   v1/reception/{blId}/retour-manquants` en crée alors un nouveau (`deja:false`). `GET v1/reception/{blId}/ecarts`
   renvoie dans `retourManquants` le retour **le plus récent**, qui peut donc être un abandonné. Refusé
   (`is_Refused`), en attente, validé : toujours `deja:true` ;
2. la réponse `deja:true` a la même forme que la création (`{success, deja, retourId, ref, statut, lignes,
   totalManquant, route, msg}`) ; `retourManquants` de la route des écarts porte aussi `lignes` et `totalManquant`.

## Bug corrigé

En 4.12.0, la fenêtre « Reçu entré en stock » masquait le bouton « Créer un retour en attente des manquants » dès
qu'un retour existait, **abandonné compris**, et affichait pour tout statut « … : à valider dans « Retour
fournisseur » sur Prestige » (faux pour un retour abandonné, refusé ou validé).

## Ce qui change (fenêtre « Reçu entré en stock », `lib/screens/reception_bl/bilan_recu_dialog.dart`)

| Retour des manquants relu | 4.12.0 | 4.12.1 |
|---|---|---|
| aucun | bouton | bouton (inchangé) |
| **abandonné** | pas de bouton, « à valider » | « Retour RF-… abandonné sur Prestige : il ne compte plus. » **et** le bouton |
| en attente / en saisie | pas de bouton, « à valider dans « Retour fournisseur » » | inchangé |
| refusé | pas de bouton, « à valider » | pas de bouton, « … (refusé) : à corriger dans « Retour fournisseur » sur Prestige ; rien ne sort du stock. » |
| validé | pas de bouton, « à valider » | pas de bouton, « … (validé) : traité dans « Retour fournisseur » sur Prestige ; rien n'est sorti du stock. » |
| statut inconnu | « à valider » | inchangé |

- Après la création, le **nouveau** retour remplace l'abandonné à l'affichage (« Retour RF-… créé, en attente de
  validation… »), et le bouton disparaît (un seul retour actif par BL).
- `lignes` et `totalManquant` sont lus **s'ils sont présents** (`RetourExistant`, `RetourManquants` dans
  `lib/reception/manquants_bl.dart`) : « Retour RF-… (refusé ; 2 ligne(s), 8 boîte(s)) ». Absents (serveur plus ancien) :
  affichage de 4.12.0, à l'identique.
- `deja:true` avec `lignes` : « Retour RF-… déjà créé (refusé ; 2 ligne(s), 8 boîte(s)). »

## Clé `X-Client-Ref`

- Toujours **la même** pour chaque essai d'une même tentative (délai dépassé puis nouvel essai : jamais deux retours).
- Une clé qui a obtenu une réponse du serveur est « usée » : une **nouvelle** création (après un abandon) prend une
  **nouvelle** clé, sinon le serveur rejouerait l'ancienne réponse.

## Repli sur un serveur plus ancien

- `lignes` / `totalManquant` absents : rien d'exigé, affichage de 4.12.0.
- Un serveur antérieur au 11/11 répond `deja:true` avec le retour abandonné : « Retour RF-… abandonné : aucun nouveau
  retour n'a été créé (serveur Prestige à mettre à jour). » (en rouge) ; le bouton reste proposé, avec une nouvelle clé.
- Sans la capacité `retourManquants` : fenêtre de 4.11.0 (inchangé). Hors ligne : rien envoyé (inchangé).

Aucun autre changement de comportement. Rien n'est journalisé (ni référence, ni quantité).

## Tests (ajoutés aux fichiers `manquants_bl_*` existants ; aucun fichier ajouté, liste de la CI et
`test/categories.json` inchangés)

- **Unitaires** — `test/manquants_bl_regles_test.dart` : abandonné relu avec lignes / total, champs absents ou
  illisibles (null), texte de chaque statut, `deja:true` de même forme, création après un abandon, `deja:true` d'un
  abandonné (serveur ancien).
- **Écrans** — `test/manquants_bl_test.dart` : abandonné (mention, bouton, remplacement), délai dépassé après un
  abandon (même clé), serveur ancien (nouvelle clé), en attente / en saisie / refusé / validé (pas de bouton, texte),
  `deja:true` refusé avec lignes.
- **Intégration** — `test/manquants_bl_integration_test.dart` : abandonné relu, nouveau retour, `deja:true` de même
  forme, rien dans la file d'envoi.
- **E2E** — `test/manquants_bl_e2e_test.dart` : application entière (V2s), retour précédent abandonné (nouveau retour
  créé, l'abandonné disparaît) et refusé (aucun POST).
- **Réseau** — `test/reseau/manquants_bl_reseau_test.dart` (vrai HTTP) : abandonné / refusé / validé sans lignes,
  nombres en texte, POST après abandon, `deja:true` nouvelle forme, abandonné d'un serveur ancien, clés transmises.
- **Ergonomie** — `test/manquants_bl_ergonomie_test.dart` : mention de l'abandon et bouton visibles ensemble, puis le
  nouveau retour (V2s, V3, 360 × 800 dp, tablette ; texte ×1,0 et ×1,3 ; cibles ≥ 48 dp).
- **Performance** — `test/performance/manquants_bl_perf_test.dart` : 100 000 retours lus et mis en texte < 1 s ;
  requêtes avec un retour abandonné (comme sans retour) ou refusé (aucune création).
- **Non-régression** — `test/manquants_bl_garde_test.dart` : seul `is_Abandoned` laisse le bouton, clé renouvelée à un
  seul endroit et seulement après une réponse obtenue, plus de texte « à valider » commun, rien de journalisé.
