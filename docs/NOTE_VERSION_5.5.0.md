# Prestige Mobile V3 5.5.0+55 : heure du serveur fausse (transmission du serveur du 24/11)

Même application (`com.dici.prestigemobile.v3`, « Prestige Mobile V3 »), même icône que la 5.4.0+54. Aucune nouvelle
permission, aucune bibliothèque ajoutée. Prestige Pointage passe en **1.2.0+3** (même écran de pointage, `lib/rh`) :
voir `docs/prestigepointage/NOTE_VERSION_1.2.0.md`.

Serveur : branche `plan/24112026`. Quand l'heure du PC serveur est fausse, Prestige refuse toute écriture (ventes,
encaissements, pointages, photos, réceptions…) par HTTP 423 avec un message ; les lectures restent permises ; seuls
l'administrateur ou la tâche Windows du serveur remettent l'heure. L'application fonctionne aussi avec un serveur sans
ce contrôle (rien ne change).

## Ce que voit l'utilisateur

- **Le message du serveur, tel quel** (par exemple « Opération refusée : l'heure du serveur est fausse. … »), à la
  place de « Serveur injoignable », « Erreur du serveur (code 423) » ou « erreur inconnue ». Modules (Réserve, Fiche
  client…) : titre « Heure du serveur fausse ». Aucune proposition de contournement, aucune relance automatique.
- **Ventes, encaissements, paiements mobile money, réceptions, photos des produits** : refus affiché avec ce message ;
  le panier reste tel quel.
- **Ventes et opérations de stock saisies hors ligne** : elles **restent dans la file** (jamais « à vérifier » ni
  « refusées ») ; « Envoyer » s'arrête sur le message du serveur. Quand l'heure est corrigée, l'envoi est de nouveau
  proposé (même confirmation qu'au retour du serveur) et chaque opération part une seule fois (même clé
  `X-Client-Ref`).
- **Pointage du terminal** : le pointage est gardé sur le terminal, avec « En attente d'envoi (heure du serveur à
  corriger) », le message du serveur puis « Pointage gardé sur le terminal (08:02) : envoyé à Prestige quand l'heure du
  serveur sera corrigée. » ; l'heure de lecture est conservée. Envoi de la file : « … envoi interrompu : <message du
  serveur> Les pointages restent en attente ». Photos de contrôle et empreintes partagées : gardées, envoyées ensuite.
- **Mon pointage (téléphone)** : connexion et pointage refusés avec le message du serveur (pas de pointage hors ligne
  sur le téléphone, comme avant).
- **Écran de connexion** : après un refus 423 constaté (déconnexion, session expirée), l'écran lit `GET
  v1/horloge/public` et, s'il répond BLOQUE, affiche le bandeau
  « Heure du serveur fausse — L'heure du serveur Prestige est fausse (serveur : 24/11/2026 20:52) : ventes,
  encaissements, pointages et réceptions sont refusés tant que l'administrateur ne l'a pas corrigée. » La connexion
  reste possible. OK ou REGULARISATION : rien. Aucune requête de plus au démarrage en fonctionnement normal (budget
  de requêtes du démarrage inchangé : 2).
- **Suppression d'une vente dépôt / proforma vide** (`v1/ventestats/remove`) : si le serveur refuse (vente en saisie
  sur un poste, heure fausse), son message s'affiche au lieu de « La vente vide n'a pas pu être supprimée sur le
  serveur. » ; rien n'est supprimé.

## Fonctionnement

- `lib/serveur/horloge_serveur.dart` : lecture du refus (`horlogeBloqueeDe`), état « bloqué » de l'application,
  `GET v1/horloge/public`, intercepteur posé sur **chaque** client HTTP avec celui du déploiement (`avecDeploiement`).
- Déblocage : première écriture acceptée, ou `GET v1/horloge/public` = OK / REGULARISATION, lu **seulement après un
  423** à la cadence existante de la surveillance (30 s) ; aucune écriture n'est rejouée sans l'accord de l'utilisateur.
- Journal du terminal : « Heure du serveur fausse (HTTP 423 horlogeBloquee) » (catégorie seulement, jamais le message
  ni la requête).
- Points 2 et 3 de la transmission : `vente/update-created-date`, `reglement/reglementdiffere(-all)`,
  `vente/rappel/{id}` et `ventestats/update/{id}/is_Trash` ne sont pas utilisées par l'application ;
  `ventestats/remove/{id}` l'est (message affiché). Aucune nouvelle route (`vente-saisie/signal` non implémentée).

## Tests

`horloge_serveur` (unitaires), `horloge_serveur_ecrans` (écran de connexion, messages), `horloge_serveur_integration`
(réception, modules, mobile money, suppression), `prestigepointage/horloge_borne` (borne signée), `horloge_serveur_e2e`
(heure fausse → files gardées → correction → confirmation → un seul envoi), `horloge_serveur_garde` (non-régression),
`horloge_serveur_ergonomie`, `horloge_serveur_performance`, `reseau/horloge_serveur_reseau` (vrai HTTP : connexion,
pointages, vente et encaissement en file, même X-Client-Ref, aucune boucle), `pointage_photo_integration` (photo 423).
Faux serveur : mode `horlogeBloquee` et `GET v1/horloge/public` (données fictives).

## Vérification sur le terminal

1. Serveur de test avec `plan/24112026`, heure du PC serveur volontairement fausse : se connecter (permis), ouvrir une
   vente, ajouter un produit → message du serveur, rien d'autre.
2. Hors ligne : encaisser une vente ; repasser en ligne, « Envoyer » → message du serveur, la vente reste en attente.
3. Terminal de pointage : badge → « En attente d'envoi (heure du serveur à corriger) ».
4. Remettre l'heure : dans les 30 s, la confirmation d'envoi s'ouvre ; envoyer → une seule vente, un seul pointage.
