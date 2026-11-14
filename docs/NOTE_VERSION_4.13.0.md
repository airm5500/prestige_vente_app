# Prestige Mobile 4.13.0+43 : client d'une vente comptant

Demande du 13/11/2026 (plan du 12/11, point 8), validée par le pharmacien. Routes du serveur déjà en place (branche
`integration/recette-2026-10-29`), aucune modification côté Prestige.

## Bogue corrigé : le nom du mode de règlement envoyé comme client

Jusqu'en 4.12.1, l'application envoyait avant chaque encaissement `POST v1/vente/update/client` avec
`clientId = nom du mode de règlement` (« especes », « wave »…), puis le même nom dans le `clientId` de la clôture :

| Endroit | 4.12.1 | 4.13.0 |
|---|---|---|
| Vente (nouvelle interface) `lib/ventes/prevente/vente_controller.dart` | update/client « mode » puis clôture `clientId: mode` | plus d'update/client ; clôture `clientId` = client rattaché, sinon `null` |
| Ancienne interface `lib/providers/sale_provider.dart` | idem | plus d'update/client ; clôture `clientId: null` |
| Synchronisation hors ligne `lib/horsligne/ventes_sync.dart` | idem (espèces provisoires) | plus d'update/client ; clôture `clientId: null` (le client d'une vente commencée en ligne reste celui du serveur) |

Vérifié dans le code du serveur (lecture seule) :

- `SalesServiceImpl.updateclient` : un identifiant inconnu répond `success:true`, « Client inconnu : le client de la
  vente est inchangé. » — le nom du mode n'y avait **aucun effet** (gardé exprès pour ne pas bloquer l'ancienne app) ;
- `updateVenteClotureComptant` (`POST v1/vente/cloturer/vno`) : `findClientById(clientId)` / `findByClientId` ne
  trouvent rien pour un nom de mode ou `null` → client de la vente inchangé, aucun compte client, aucun différé
  touché ; le mode de règlement passe par `typeRegleId` et `reglements` de la clôture (inchangés) ;
- le poste (`VenteCtr.js`) envoie à la clôture `clientId` = client choisi ou `null` : l'application fait de même.

Une vente **sans** client est donc identique côté serveur (même stock, même caisse, aucune ligne de tiers payant) ;
une requête de moins à l'encaissement (4 au lieu de 5).

## Zone « Client » (vente comptant, nouvelle interface)

- Visible dès que la vente existe sur le serveur (1er article), **en ligne seulement** ; jamais pour une vente hors
  ligne ; masquée clavier ouvert (place pour le panier), comme les bandeaux d'information. Ancienne interface,
  assurance, carnet : inchangés.
- « Client (facultatif) » → page « Client de la vente » :
  - recherche `GET v1/client/lambda?query=` à partir de **3 caractères** ou d'un **numéro de 4 chiffres** (espaces,
    points, tirets ignorés), anti-rebond (une seule requête pour une frappe rapide) ; résultats : nom, prénom,
    téléphone (`strADRESSE`) ; une réponse illisible est une erreur, jamais « aucun client » ;
  - « Nouveau client » : nom, prénom, téléphone → `POST v1/client/add/lambda {strFIRSTNAME, strLASTNAME, strADRESSE,
    lgTYPECLIENTID:"6"}` (type « client standard », comme le formulaire du poste : sans lui, le serveur crée un
    client sans type que sa recherche ne trouve pas) ; refus → `msg` tel quel ; client créé mais rattachement refusé
    → « Associer le client créé » (jamais recréé) ; réponse perdue → la recherche du nom est relancée ;
- choisir ou créer → `POST v1/vente/update/client {venteId, clientId}` **tout de suite** ; le nom n'est affiché qu'après
  `success:true` ; refus → `msg`, client précédent gardé ; « Client inconnu » (success:true) traité comme un refus ;
  réponse perdue → client relu sur la vente ;
- client choisi : nom, téléphone, croix ; 1er appui → croix **rouge** et « Touchez encore la croix pour retirer le
  client » (rien n'est envoyé, retour au gris au bout de 4 s) ; 2e appui → `clientId:null` ; pas de fenêtre ;
- reprise d'une vente (vente mémorisée, prévente de la liste, ordonnance) : client lu avec la vente
  (`GET v1/ventestats/{id}`, champ `client`, comme le poste) ; relecture impossible → « Réessayer » ;
- droits : 403 `interdit` → `msg`, pas de déconnexion ; 409 `sessionChangee` → retour à l'accueil (règle commune).

## Confidentialité

Ni le nom, ni le téléphone, ni le texte cherché ne sont écrits dans un journal : rien dans la console (le journal HTTP
de débogage n'écrit que le chemin sans paramètres), routes client absentes du journal du terminal, fil d'Ariane du
support sans paramètres, `ClientVente.toString()` sans donnée. Vérifié par un parcours complet
(`test/client_vente_garde_test.dart`).

## PrestigePOS

La borne n'utilise pas l'écran de vente : correctif du bogue repris par la fusion.

## Tests (données fictives)

- **Unitaires** `test/client_vente_regles_test.dart` : seuils, lecture du client, « Client inconnu », contrôleur
  (choix, refus, changement, retrait, réponse perdue, reprise, hors ligne), encaissement un mode / plusieurs modes.
- **Écrans** `test/client_vente_test.dart` : zone, recherche, nom après confirmation, croix rouge, nouveau client,
  reprise, 403, passerelle sans capacité (écran d'avant).
- **Intégration** `test/client_vente_integration_test.dart` (vrai HTTP) : corps des trois routes, refus, clôture.
- **Bout en bout** `test/client_vente_e2e_test.dart` : chaque cas « Pour vérifier » de la demande (trouvé, créé,
  retiré, changé, sans client, vente terminée, espèces puis WAVE, bilan), reprise, 403, 409, tablette.
- **Réseau** `test/reseau/client_vente_reseau_test.dart` : lenteur, réponses incomplètes, coupure, 401 / 403 / 409.
- **Ergonomie** `test/client_vente_ergonomie_test.dart` : V2s, V3, 360 × 800 dp, tablette, texte ×1,0 / ×1,3.
- **Performance** `test/performance/client_vente_perf_test.dart` : requêtes (encaissement, frappe, choix), lecture.
- **Non-régression** `test/client_vente_garde_test.dart` : plus de nom de mode en `clientId`, journaux.
- Mis à jour : `ventes_prevente`, `horsligne_ventes`, `paiement_multiple`, `performance/requetes`.
