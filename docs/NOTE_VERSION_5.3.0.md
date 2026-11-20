# Prestige Mobile V3 5.3.0+53 : pointage sur un terminal sans reconnaissance d'empreinte Sunmi

Même application (`com.dici.prestigemobile.v3`, « Prestige Mobile V3 »), même icône que la 5.2.0+52. Aucune nouvelle
permission, aucune bibliothèque ajoutée, aucun changement de contrat avec le serveur : le pointage envoyé à Prestige
est exactement le même qu'avant. Prestige Pointage (`com.dici.prestigepointage`) passe en **1.1.0+2** : elle utilise
le même écran de pointage.

## Le problème

Le pointage par empreinte des employés repose sur le service Sunmi `com.sunmi.fingerprintservice` (SDK
`libsunmifingeprint_v1.0.0.aar`, identification 1:N : le doigt désigne l'employé). Ce service **n'existe pas** sur le
SUNMI V3 (Android 13) de l'officine : l'écran affichait un diagnostic technique (« service non installé »).

Sur ces terminaux, Android ne propose que BiometricPrompt : il répond seulement « une empreinte enregistrée sur ce
terminal a été reconnue / non ». Il ne dit pas QUI a posé le doigt et ne donne aucun modèle d'empreinte.

## Décision du pharmacien : pistes 1, 2 et 4

### 1. Badge et code personnel (terminal sans le service Sunmi)

Détection automatique à l'ouverture de l'écran de pointage. Sur un terminal Sunmi ou à lecteur d'empreinte sans le
service, un bandeau clair remplace le diagnostic :

> Ce terminal ne permet pas la reconnaissance par empreinte. Pointez avec votre badge ou votre code personnel.

- **Scanner mon badge** : QR ou code-barres du badge par l'appareil photo (comme l'icône caméra du champ).
- **Saisir mon code personnel** : clavier affiché ; numéro du badge ou matricule, puis Entrée.
- Le lecteur de badge intégré (douchette, scanner Sunmi) et le badge NFC fonctionnent comme avant.
- **Détails techniques** (lien discret) : le diagnostic du lecteur. Masqué en mode borne ; dans Prestige Pointage, il
  est dans Administration › « Lecteur d'empreinte : détails techniques ».
- Gestion des empreintes (administrateur) : même bandeau, aucun enrôlement possible et aucun modèle partagé recopié
  sur ce terminal (il ne saurait pas s'en servir) ; la suppression reste possible.
- Une tablette sans lecteur d'empreinte n'affiche aucun bandeau (rien à expliquer).

### 2. Confirmation par le doigt (option, désactivée par défaut)

Réglage **« Confirmer le pointage par empreinte »** :

- Prestige Mobile : Réglages › Équipe & pointage › « Pointage sur ce terminal (contrôle) » (rubrique protégée par le
  code administrateur, comme la photo de contrôle) ;
- Prestige Pointage : Administration de la borne (code administrateur), à côté de la photo de contrôle.

Texte du réglage : « Android accepte toute empreinte enregistrée sur ce terminal : cela décourage la fraude mais
n'identifie pas la personne. »

Quand il est activé, après l'identification par badge ou code personnel, la fenêtre d'empreinte d'Android s'ouvre
(« Confirmer le pointage — Prénom, posez un doigt enregistré sur ce terminal ») :

| Situation | Résultat |
|---|---|
| Empreinte reconnue | écran de confirmation habituel (sens, Corriger / Annuler / Valider), pointage enregistré |
| Annulation, délai sans doigt, trop d'essais ratés | **pointage non enregistré**, message clair, nouvel essai possible tout de suite |
| Aucune empreinte enregistrée dans Android, pas de lecteur, lecteur en panne | pointage enregistré quand même, avec la mention « Pointage sans confirmation par empreinte : … » |

La confirmation utilise le pont natif déjà présent (BiometricPrompt d'Android) : l'activité reste une
`FlutterActivity`, l'impression Sunmi, le scanner, le NFC et le mode borne ne changent pas.

### 4. Anciens terminaux Sunmi (service présent)

Rien ne change : identification 1:N par le doigt, enrôlement, synchronisation des modèles avec le serveur selon le
réglage du serveur (`KEY_EMPREINTES_PARTAGEES`) et le droit `P_SM_RH`. Le réglage de confirmation n'y a aucun effet.

## Sécurité

Aucun modèle d'empreinte, code de badge, code personnel ni nom d'employé dans le journal du terminal ou les traces :
le journal note seulement l'issue (« Confirmation par empreinte : annulée, pointage non enregistré »…). Android ne
transmet aucune donnée d'empreinte à l'application.

## Ce que le pharmacien fait sur le SUNMI V3

1. Installer Prestige Mobile V3 5.3.0 (et Prestige Pointage 1.1.0 si la borne est utilisée).
2. Ouvrir le terminal de pointage : le bandeau « badge ou code personnel » s'affiche ; vérifier un badge et un code.
3. Pour la confirmation par le doigt : enregistrer au moins une empreinte dans **Paramètres Android › Sécurité ›
   Empreinte** du terminal (Android exige un verrouillage d'écran), puis activer « Confirmer le pointage par empreinte »
   (code administrateur). Sans empreinte enregistrée, les pointages passent avec la mention.

## Tests

`confirmation_empreinte` (unitaires, canal natif simulé), `empreinte_absente` et `confirmation_empreinte_flux`
(écrans), `confirmation_empreinte_e2e` et `prestigepointage/confirmation_empreinte_pointage_e2e` (application entière),
`confirmation_empreinte_ergonomie` (320 / 360 dp, tablette, texte ×1,0 / ×1,3, borne), `confirmation_empreinte_garde`
(non-régression) ; captures : outil hors CI `test/outils/captures_pointage_530_test.dart`.
