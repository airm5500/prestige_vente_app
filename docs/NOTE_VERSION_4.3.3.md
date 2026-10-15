# Prestige Mobile 4.3.3+19 — « Serveur injoignable » ≠ « Serveur indisponible »

Demande du pharmacien : distinguer DEUX pannes, partout (deux interfaces, lancement, connexion, accueil, modules,
borne, terminal de pointage, téléphones de pointage).

| Situation | Exemples | Message |
|---|---|---|
| 1. Le serveur ne répond pas | délai dépassé, hôte inaccessible, réseau absent, connexion refusée (PC serveur éteint, Payara arrêté) | **« Serveur injoignable. Vérifiez le Wi-Fi et que le PC serveur est allumé. »** |
| 2. Le serveur répond, Prestige n'est pas déployé | 404 de Payara (page HTML ou vide), 502 / 503 / 504 | **« Serveur indisponible : Prestige est en cours de démarrage ou de redéploiement. Veuillez réessayer dans un instant. »** |

Mot de passe faux, erreur 500 et refus métier : **inchangés** (jamais confondus avec une panne).

## Ce qui change

- **Connexion** (nouvelle interface et interface d'origine) : le message suit la panne ; l'encadré, le point d'état
  du serveur et l'écran de lancement aussi (titre « Serveur injoignable » ou « Serveur indisponible » et la phrase
  correspondante). Licence : « Serveur injoignable » / « Serveur indisponible », jamais « aucune licence ».
- **Accueil** : la surveillance du serveur lit `/officine` ; un 404 (page de Payara) ou un 502/503/504 ne compte
  plus comme « serveur joignable » : pastille et bandeau « Serveur indisponible » (Prestige en démarrage ou
  redéploiement), sinon « Serveur injoignable ».
- **Borne** : « Tester la borne », le motif d'échec de connexion et l'écran « Borne momentanément indisponible »
  (ligne pour le personnel) donnent le bon message.
- **Pointage** : terminal RH (pointage gardé en file, bilan « envoi interrompu : serveur injoignable / indisponible »)
  et téléphones de pointage.
- **Modules** (Réserve, Posos, Fiche client, ventes, réception, retours, images, paiements, copie hors ligne) : même
  distinction.

## Replis « serveur ancien » : plus de fausse « route absente »

Un 404 de Payara a **le même corps HTML** que Prestige soit non déployé ou qu'une route manque sur un serveur ancien
(vérifié sur le serveur de test local : `GET /prestige/api/v1/n_existe_pas` et une application désactivée donnent
la même page « Error report »). Désormais, sur un 404 dont le corps n'est pas une réponse JSON de Prestige,
l'application vérifie `GET /officine` (route publique de tous les serveurs) :

- `/officine` répond → Prestige est déployé : le 404 est une vraie route absente, repli d'origine inchangé ;
- `/officine` répond 404 / 502 / 503 / 504, ou ne répond pas → **Prestige indisponible** : la réponse devient un 503
  « Prestige indisponible » ; aucun repli ne la prend pour une route absente, **rien n'est mémorisé** (droits Réserve
  et Posos, photo de pointage, `app-vente`, centre de support, images, paiements) : l'opération est à réessayer.

Aucune requête de plus en fonctionnement normal (vérification seulement sur un tel 404) ; une seule vérification
pour des 404 simultanés, résultat gardé 10 s ; même transport que la requête d'origine.

## Tests

`reseau/redeploiement` (connexion : 404 / 502 / 503 / 504 → indisponible, connexion refusée → injoignable, mot de
passe faux, 401, 500 ; licence ; écrans des deux interfaces et lancement ; borne ; pointage),
`reseau/indisponible_replis` (classement des pannes, vérification par `/officine` : aucune en fonctionnement normal,
une pour plusieurs 404, jamais pour un 404 JSON ; replis non mémorisés ; terminal RH ; support ; surveillance de
l'accueil en application entière) ; tests existants mis à jour (`licence_lookup`, `connexion_lancement`,
`integration_services`, `e2e_parcours`, `https_integration`, `support_centre`, `pointage_photo_integration`,
`sortie_borne`).
