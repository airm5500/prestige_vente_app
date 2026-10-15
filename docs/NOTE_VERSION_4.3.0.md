# Prestige Mobile 4.3.0+16 — EAN sans contrôle, connexion allégée, réponse du serveur du 15/10/2026

Toutes les nouveautés liées au serveur ont un **repli** : avec un serveur qui n'a pas encore la branche
`claude/new-session-xm8ptu` (routes absentes : 404 / 405), l'application fonctionne exactement comme en 4.2.1.

## Décisions du pharmacien appliquées

- **EAN fabricant** (nouvelle et ancienne interface : écran commun) : on enregistre la valeur lue, **sans aucun
  contrôle** (chiffres, longueur et clé de contrôle supprimés, plus d'avertissement « Enregistrer quand même »).
  Une confirmation est toujours demandée : produit, ancien → nouvel EAN, **Oui / Non**. « Oui » est le bouton par
  défaut (Entrée / OK de la douchette). « Non » ferme la fenêtre et **remet le curseur dans le champ**, valeur gardée
  (sélectionnée : un nouveau scan la remplace). Champ vide : rien n'est envoyé.
- **ANO-09** (lectures en double à la connexion) : **24 requêtes au lieu de 26** (dont `GET /posos/droits`, nouveau) :
  - supprimés : la 2e lecture de l'officine par l'accueil (déjà lue par la connexion qui l'ouvre, une seule fois),
    les préventes et les BL du jour lus par la connexion puis relus aussitôt par le nouvel accueil (lus désormais
    seulement par l'accueil) ;
  - gardés exprès : `GET /officine` du test « serveur joignable » de l'accueil (état à l'instant de l'affichage) et
    `GET /modereglement/all` de la copie hors ligne (autre usage, autre moment) — détail dans `test/README.md`.
  - Accueil d'origine (ancienne interface) : chargements inchangés.

## Réponse du serveur du 15/10/2026 (docs/serveur/REPONSE_SERVEUR_2026-10-15.md)

- **Droits** : `GET v1/reserve/droits` décide du menu Réserve quand il répond (demande 4) ; `GET v1/posos/droits`
  masque l'Analyse posologie si `analyser` est faux (demande 5). Un refus de droit (HTTP 403 `interdit:true`) affiche
  le message du serveur (« Droit manquant : … »), jamais une déconnexion ; hors ligne, la ligne est refusée avec ce
  message au lieu de « session expirée ».
- **Pointage par badge avec photo de contrôle** (demande 31) : le pointage part avec l'identifiant du terminal (`id`)
  et son contrôle (`controle`) ; la photo est ensuite envoyée au serveur (multipart, < 100 Ko). Même `id` renvoyé →
  « déjà enregistré ». Serveur sans la route photo : une seule tentative par session, la photo reste sur le terminal.
- **Réception et retour hors ligne** (demande 18) : en-tête `X-Client-Ref` (clé de la ligne) sur `add-lot` et
  `retourfournisseur/add-item` : un serveur à jour n'enregistre la ligne qu'une fois.
- **Licence** (demande 11, option A) : « Activez la licence après connexion d'un administrateur » quand le serveur
  exige une session ; un administrateur qui se connecte sur un appareil sans licence garde sa session pour la
  seule activation (déconnecté ensuite) ; un autre compte est déconnecté comme avant.
- **Rôle** (demande 10) : le libellé de `role` renvoyé par `user/auth` est affiché sur « Qui êtes-vous ? ».
- **Réserve** (demande 28) : suggestion annulée ouverte en consultation seule, suggestion d'un autre emplacement
  « introuvable » (déjà géré, désormais testé).
- Réponses aux questions du serveur, décisions du pharmacien et nouvelles demandes des trois applications : un seul
  fichier à transmettre, `docs/serveur/TRANSMISSION_SERVEUR_2026-10-15.md`.

## Borne

- Message **« Ajouté : NOM » en haut de l'écran** (même durée, 2 s) : il ne cache plus le bouton panier ni le bas de
  l'écran et ne recouvre rien (bandeau au-dessus du contenu). Commun avec PrestigePOS.
- **ANO-11 corrigée** : cartes produits de la borne qui débordaient en tablette avec un texte agrandi (×1,3) ;
  rendu inchangé à la taille normale du texte.

## Tests

`test/reponse_serveur_test.dart` (droits, 403, rôle, X-Client-Ref, licence e2e, réserve, Posos e2e),
`test/pointage_photo_integration_test.dart` (serveur ancien / à jour), EAN (`retours_pharmacien`,
`presentation_delivery_ean`), `performance/demarrage` (24 requêtes, lectures en double contrôlées), `borne_test`
(message en haut, 3 tailles × 2 échelles de texte). Voir `test/README.md`.
