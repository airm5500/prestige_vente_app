# Demandes au serveur Prestige — complément du 15/10/2026

À transmettre à la session qui maintient `airm5500/prestige` (branche `claude/new-session-xm8ptu`).

Ce fichier **complète** `DEMANDES_SERVEUR_CONSOLIDEES.md` (déjà en cours de traitement, inchangé) : il ne contient
que les **nouvelles** demandes, numérotées à la suite (43, 44). Mêmes règles communes de réponse que le document
consolidé (session cookie, `success`/`message`, 401 sans session, droits vérifiés côté serveur, idempotence).

| N° | Demande | Application(s) | Priorité | Statut |
|---|---|---|---|---|
| 43 | Empreintes des employés partagées entre terminaux de pointage | Mobile | P2 | à faire (désactivé par défaut) |
| 44 | Performance de `GET /info` (Analyse article, fiche produit) | Mobile, Pharmacien | P2 | à faire |

---

## 43. Empreintes des employés partagées entre terminaux de pointage — P2

**Applications** : Mobile (terminal de pointage, Sunmi V3H avec lecteur d'empreinte Aratek A400).

**Pourquoi.** Aujourd'hui l'empreinte d'un employé est enregistrée (enrôlement : consentement, 3 captures, test)
et stockée **uniquement sur le terminal** où elle a été prise (stockage chiffré Android). Avec plusieurs terminaux
de pointage, il faut enrôler chaque employé sur chacun. Le pharmacien demande d'enregistrer l'empreinte une fois,
de la conserver sur le serveur, et qu'elle soit reconnue sur tous les terminaux. Le serveur n'a aujourd'hui aucune
table ni route pour cela (`RhRessource` `v1/rh` : employés, pointages… ; `t_employe` n'a que `badge`).

**Quoi.**
- Table `t_employe_empreinte` : `id`, `employe_id`, `modele` (octets du gabarit, **chiffré au repos**, clé hors
  base), `format` (ex. `SUNMI_A400_RAW`), `capteur` (numéro/firmware de l'appareil d'enrôlement), `doigt`,
  `consentement_le`, `consentement_par`, `dt_creation`, `dt_suppression`.
- `POST v1/rh/employes/{id}/empreintes` `{modeles:[base64], format, capteur, doigt, consentement:{le, par}}` (droit RH) ;
  `X-Client-Ref` pour l'idempotence.
- `GET v1/rh/empreintes?depuis=<horodatage>&format=<format>` : modèles des employés **actifs** + suppressions
  depuis la date (mise à jour incrémentale des terminaux) ; droit RH ou terminal de pointage enregistré.
- `DELETE v1/rh/employes/{id}/empreintes` ; purge automatique quand un employé devient inactif.
- Journal d'audit des lectures/écritures ; jamais de modèle dans les journaux ni les exports ; HTTPS recommandé.
- Paramètre d'activation (désactivé par défaut).

**Compatibilité.** Sans ces routes, l'application continue de stocker les empreintes sur le terminal (comportement
actuel). Les modèles sont propres au capteur : un terminal ne charge que ceux de son format.

**Obligations (ARTCI, loi 2013-450).** Donnée biométrique sensible : déclaration/autorisation ARTCI de l'officine,
consentement écrit de chaque employé (déjà recueilli par la pharmacie pour sa pointeuse à empreinte et
visage existante ; le texte de l'application sera mis à jour : aujourd'hui il indique « jamais envoyé au serveur »), alternative badge, durée de conservation limitée, droit d'effacement.

**Vérification.** Enrôler un employé sur un V3H, vérifier `GET v1/rh/empreintes` sur un second V3H, pointer par
empreinte sur le second ; désactiver l'employé → plus de modèle renvoyé.

**Référence.** Analyse du 15/10/2026 (`lib/rh/empreintes_screen.dart`, `lib/rh/identification.dart`,
`SunmiFingerprintBridge.kt`).

---

## 44. Performance de `GET /info` (Analyse article, fiche produit) — P2

**Applications** : Mobile, Pharmacien.

**Pourquoi.** Sur le serveur de l'officine, `GET v1/info?search=doli` (ou `ibex`) ne répond pas en 10 s alors que
`GET v1/vente/search` répond immédiatement. L'application a été adaptée (liste via `/vente/search`, puis `/info`
pour le seul produit choisi), mais `/info` reste lent même pour un produit.

**Quoi.** Voir `prestige_vente_app/docs/serveur/DEMANDE_PERFORMANCE_INFO.md` (rédigée avec l'analyse du code) :
limiter les calculs au(x) produit(s) demandé(s) (pas d'agrégat des ventes de tout le catalogue), index adaptés,
et rétablir la tolérance aux erreurs par produit (une ligne en erreur ne doit pas vider toute la réponse).

**Vérification.** `GET v1/info?search=<CIP exact>` < 1 s ; `GET v1/info?search=doli` < 3 s.

---

