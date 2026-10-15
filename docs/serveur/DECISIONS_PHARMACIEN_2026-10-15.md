# Décisions du pharmacien sur les questions du serveur — 15/10/2026

Réponse aux questions de la partie 3 de `REPONSE_SERVEUR_2026-10-15.md` (« Il me faut une réponse »,
colonne « pharmacien »). Les questions adressées aux applications ont leurs propres fichiers
(`REPONSES_APP_MOBILE_2026-10-15.md`, et côté Pharmacien `REPONSES_APP_PHARMACIEN_2026-10-15.md`).

| N° | Question | Décision |
|---|---|---|
| 12 | `P_BL_MOBILE_VALIDER_AVEC_ECART` : que fait `validerbl?avecEcart=true` ? | **Refuser** la validation tant que des lignes ne sont pas saisies, avec un message qui **nomme les produits manquants** (« Produits non saisis : … »). |
| 12 | `P_BL_MOBILE_SCANNER` sur `add-lot` / `creerbl` (routes partagées avec l'écran web) | Donner ce droit **à tous les profils qui ont le menu BL** (rien ne doit être bloqué au poste). |
| 17 D7 | Motif différent sur un produit déjà dans le retour | Normalement, sur un même BL, un produit n'a qu'un motif. Si cela arrive : **option 1** (une ligne par produit, motif et lot), **avec un message** : « Vous avez ajouté ce produit avec un motif différent ». |
| 24 | `GET pilotage/controler` écrit en base | **Laisser tel quel.** |
| 32 | Écrans / paramètres « id1,id2 » (choix multiples) | **CA par emplacement** (plusieurs emplacements à la fois). |
| 38 | Pagination du Suivi des ajustements | **Oui, paginer.** |
| 38 | « Racheté » dans les rappels | **Marqué à la main.** |
| 38 | Actualisation des rappels | **À la demande, avec un bouton** (pas d'actualisation programmée). |
| 39 | Garder quelques minutes le calcul d'une garde pour les pages suivantes | **Oui.** |
| 34 | Lecture de colonnes nominatives (fiche client agrégée) | **Accord donné** pour les essais (dans le respect des règles habituelles : aucune donnée de patient dans les journaux ni dans les tests versionnés). |
