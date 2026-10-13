# Demande au serveur Prestige : photo de contrôle du pointage par badge

Destinataire : la session qui travaille sur le serveur (dépôt `airm5500/prestige`). L'application n'a rien modifié côté
serveur.

## 1. Contexte

Le pharmacien veut empêcher qu'un employé pointe avec le badge d'un collègue (« buddy punching »). Sa décision :
**une photo de contrôle à chaque pointage par badge** sur le terminal de pointage (QR / code-barres lu au scanner
ou à la caméra, badge NFC). L'empreinte (Sunmi V3H) reste la méthode la plus sûre et ne prend pas de photo.

Côté application, c'est fait (Prestige Mobile, `lib/rh/photo_controle.dart`) :

- après la lecture du badge, la **caméra frontale** montre un aperçu avec un compte à rebours (environ 2 s), puis
  prend la photo sans autre geste ;
- photo compressée en **JPEG, 640 px au plus sur le grand côté, moins de 100 Ko** (en pratique 20 à 60 Ko) ;
- si la caméra est absente, refusée ou en panne, le pointage n'est **jamais bloqué**. Il est marqué
  « sans photo (motif) », noté dans le journal du terminal et signalé dans le rapport d'anomalies ;
- **en attendant le serveur**, la photo reste sur le terminal, dans le stockage privé de l'application (pas dans la
  galerie, exclue des sauvegardes Android). Elle est liée au pointage par l'identifiant local, seul l'administrateur
  la consulte (Paramètres › Équipe & pointage, ou Pointage présence › Photos de contrôle avec le code administrateur),
  et elle est effacée automatiquement après la durée de conservation (30 jours par défaut, de 7 à 90 jours au choix).

## 2. Ce que le serveur accepte aujourd'hui (vérifié dans le code, branche `claude/new-session-xm8ptu`)

- `POST v1/rh/pointages` (`RhRessource.saisirPointage` → `RhPointageServiceImpl.saisirPointage`) :
  `@Consumes(application/json)`, corps `{employeId, jour, heure, sens, motif}`. Insertion
  `INSERT IGNORE INTO t_pointage (id, employe_id, horodatage, sens, source='MANUEL', saisi_par, motif, created_at)`.
  L'`id` est un UUID tiré par le serveur et **n'est pas renvoyé** : la réponse est
  `{"success": true, "message": "Pointage manuel enregistré."}`.
- `t_pointage` n'a **aucune colonne photo**. Les migrations `V6.9.85__rh_pointage.sql` et
  `V6.9.88__mobile_jeton_pointage.sql` n'ajoutent que `latitude`, `longitude` et `precision_m`.
- La seule route photo existante, `MobileRessource` (`v1/mobile/.../photo`, multipart), sert aux **photos des
  produits** (`familleId`, droit `photos`). Elle ne concerne pas le pointage.

**Conclusion** : le serveur n'accepte pas de photo avec un pointage. L'application n'invente aucune route : elle
garde la photo sur le terminal (voir § 1) et envoie le pointage exactement comme avant.

## 3. Ce qui est proposé

### 3.1 Lier la photo au pointage : identifiant fourni par le terminal

Il faut ajouter à `POST v1/rh/pointages` un champ facultatif **`id`** : un UUID tiré par le terminal (celui que
l'application utilise déjà pour la file hors ligne). Le serveur s'en sert comme `t_pointage.id` s'il est fourni et
valide, et le renvoie toujours dans la réponse :

```json
// requête (champs actuels inchangés)
{ "id": "3f1c2a9e-…", "employeId": "E1", "jour": "2026-10-13", "heure": "08:02", "sens": "ENTREE",
  "motif": "Badge terminal Accueil",
  "controle": { "photo": true } }
// réponse
{ "success": true, "id": "3f1c2a9e-…", "message": "Pointage manuel enregistré." }
```

- L'envoi reste **idempotent**. Si le même `id` est renvoyé (file hors ligne rejouée), le serveur répond comme pour
  le doublon actuel : « Un pointage existe déjà… ».
- **`controle`** (facultatif) : `{ "photo": true }`, ou bien `{ "photo": false, "motif": "PERMISSION_REFUSEE" }`
  (`CAMERA_ABSENTE`, `ERREUR_CAMERA`, `DELAI_DEPASSE`, `PHOTO_ILLISIBLE`). On le range dans deux nouvelles colonnes de
  `t_pointage` : `photo_statut VARCHAR(16)` (`AVEC`, `SANS`, `ATTENDUE`) et `photo_motif VARCHAR(32)`. Le responsable
  RH voit ainsi dans Prestige les pointages faits **sans photo**, même si l'envoi de la photo échoue ensuite.

### 3.2 Envoi de la photo

Il faut une nouvelle route : `POST v1/rh/pointages/{id}/photo`. Elle passe par la session `/user/auth` (cookies),
exige le droit `P_SM_RH` et suit le même `controle()` que les autres routes `v1/rh`.

- `multipart/form-data` : un champ fichier **`photo`** (`image/jpeg`), et un champ facultatif `prise` (date et heure
  ISO de la prise, heure du terminal).
- Contrôles : taille **150 Ko au plus** (l'application envoie moins de 100 Ko). Type JPEG vérifié sur les octets
  (`FF D8 FF`), pas seulement sur l'en-tête. Image de 1024 px au plus sur chaque côté. Le pointage `{id}` doit exister,
  avoir la source `MANUEL` et un motif qui commence par « Badge terminal ». Une seule photo par pointage : un nouvel
  envoi remplace l'ancienne et reste idempotent.
- Réponses : `{"success": true}` ; refus : `{"success": false, "message": "…"}` (pointage inconnu, trop gros, pas un
  JPEG) ; **404** si la route n'existe pas (ancienne version du serveur : l'application reste alors en mode local).

Stockage proposé : une table à part, pour garder `t_pointage` légère.

```sql
CREATE TABLE t_pointage_photo (
  pointage_id  VARCHAR(40)  NOT NULL PRIMARY KEY,   -- t_pointage.id (ON DELETE CASCADE)
  employe_id   VARCHAR(40)  NOT NULL,
  prise_le     DATETIME     NOT NULL,
  taille       INT          NOT NULL,
  sha256       CHAR(64)     NOT NULL,
  contenu      MEDIUMBLOB   NOT NULL,               -- ou un chemin de fichier hors de la racine web
  recu_le      DATETIME     NOT NULL,
  recu_par     VARCHAR(40)  NULL,                   -- utilisateur de la session du terminal
  CONSTRAINT fk_pointage_photo FOREIGN KEY (pointage_id) REFERENCES t_pointage(id) ON DELETE CASCADE,
  INDEX idx_pointage_photo_prise (prise_le)
);
```

### 3.3 Consultation

- `GET v1/rh/pointages/{id}/photo` renvoie `image/jpeg` (droit `P_SM_RH`, en-tête `Cache-Control: no-store`), ou 404.
- Dans `GET v1/rh/presence`, chaque ligne de `pointages[]` reçoit `photo` (`AVEC`, `SANS` ou `ATTENDUE`) et
  `photoMotif`.
- Dans Prestige › RH › Présence du jour : une icône sur les pointages faits par badge (photo visible au clic, pour le
  responsable RH seulement) et un signal sur les pointages « sans photo ».

### 3.4 Conservation

- Nouveau paramètre général **`KEY_RH_PHOTO_RETENTION_JOURS`**, 30 par défaut (de 7 à 90).
- Purge quotidienne côté serveur : supprimer de `t_pointage_photo` les lignes dont `prise_le` est plus ancienne que
  la durée. **Le pointage lui-même est conservé** ; seule la photo est effacée.
- La suppression d'un pointage manuel (`DELETE v1/rh/pointages/{id}`) supprime sa photo (cascade).
- Idéalement, le serveur renvoie cette durée dans `GET rh/droits`, pour que les terminaux l'appliquent aussi à leur
  copie locale.

### 3.5 Confidentialité (données personnelles, loi ivoirienne n° 2013-450, ARTCI)

- **Finalité unique** : contrôler l'identité au pointage. Les photos ne servent à rien d'autre, ni reconnaissance
  faciale automatique ni profilage.
- **Information des employés** : l'application affiche sur le terminal « Une photo de contrôle est prise par la
  caméra avant à chaque pointage par badge » ; l'employé voit l'aperçu et le compte à rebours avant la photo. Il est
  conseillé de mettre à jour la note d'information du personnel et, si l'officine y est soumise, sa déclaration à
  l'ARTCI.
- **Accès restreint** : droit `P_SM_RH` seulement. Chaque consultation d'une photo est tracée (qui, quand, quel
  pointage).
- **Aucune photo ni chemin de fichier dans les journaux**, et aucune photo dans les exports Excel ou PDF du tableau
  de présence. HTTPS en production.
- Durée de conservation courte (§ 3.4) et suppression avec le pointage.

## 4. Ce que fera l'application quand le serveur sera prêt

1. Envoyer `id` et `controle` avec `POST v1/rh/pointages`. Un serveur ancien qui ignore ces champs continue de
   fonctionner comme aujourd'hui.
2. Une fois le pointage accepté, envoyer la photo (`POST …/{id}/photo`), y compris pour les pointages de la file hors
   ligne, après leur envoi. Si l'envoi réussit, effacer la copie locale ; s'il échoue, la garder (avec la même purge
   automatique) et réessayer à l'envoi suivant de la file.
3. Si la route répond 404, rester en mode local (comportement actuel) sans afficher d'erreur à l'employé.

## 5. Questions pour le pharmacien et le serveur

- Durée de conservation par défaut : 30 jours, est-ce suffisant pour les litiges de paie ?
- Le responsable RH doit-il aussi voir les photos dans Prestige web, ou seulement sur le terminal ?
- Faut-il aussi photographier les pointages de « Mon pointage » (téléphone de l'employé) ? Ce n'est pas prévu : le
  téléphone est personnel, et le QR code tournant ainsi que le GPS sont déjà des contrôles.
