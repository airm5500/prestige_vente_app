# Demande à l'application mobile de vente : contrôle des droits sur les ventes

**Date** : 19/10/2026

## Le problème

Un stagiaire au profil « Pre-vente » a pu terminer une vente depuis l'application mobile. L'application lui laissait
tout faire.

Le serveur Prestige est corrigé : il refuse maintenant ces actions sans le droit. L'application doit suivre, sinon
l'utilisateur voit des boutons qui échouent.

## Ce que le serveur refuse désormais

Sans le droit, la réponse est **403** `{success:false, interdit:true, msg}` et rien n'est enregistré.

| Action | Droit nécessaire (l'un des trois) |
|---|---|
| Terminer une vente (comptant ou assurance) | `P_SM_CLOTURER_CAISSE`, `P_SM_DEPOT_EXTENSION`, `P_BT_MODIFICATION_DE_VENTE` |
| Paiement mobile money avec clôture (`cloturer:true`) | les mêmes |
| Terminer une vente en dépôt | `P_SM_VENTEDEPOT`, `P_SM_DEPOT_EXTENSION`, `P_SM_CLOTURER_CAISSE` |
| Annuler une vente (inchangé) | `P_BT_ANNULER_VENTE` |

« Terminer la prévente » reste permis aux profils prévente.

## À faire dans l'application

1. **Lire les droits** après chaque connexion (mot de passe ou badge) et à chaque retour de l'application au premier
   plan : `GET v1/user/droits`, qui renvoie la liste `droits`.
2. **Masquer les boutons** sans le droit : « Terminer la vente », clôture automatique du paiement mobile money, vente
   en dépôt, annulation. Un profil prévente ne voit que « Terminer la prévente ».
3. **Sur un 403 `interdit`** :
   - afficher `msg` ;
   - garder la vente telle quelle ;
   - ne pas réessayer ;
   - **ne pas déconnecter** : seul un 401 veut dire « session absente ».
4. **Changer d'utilisateur sur un téléphone partagé** :
   - appeler `POST v1/user/logout` ;
   - vider les cookies ;
   - effacer le panier, le vendeur choisi et les droits en mémoire ;
   - puis se reconnecter.

   Le panier d'un compte ne doit jamais passer sous la session d'un autre.
5. **Recommandé : envoyer l'en-tête `X-Prestige-Utilisateur`** sur chaque requête, avec la valeur `str_USER_ID` reçue
   à la connexion.
   - Si la session a changé de compte entre-temps, le serveur répond **409** `{sessionChangee:true, msg}` et
     n'exécute rien.
   - L'application affiche alors `msg`, relit `v1/user/account` et `v1/user/droits`, et revient à l'accueil.
   - Sans l'en-tête, rien ne change.

## Pour vérifier

Avec un compte au profil « Pre-vente » :

- le bouton « Terminer la vente » n'apparaît pas ;
- en forçant l'appel, le message de refus s'affiche, la vente reste en cours et l'utilisateur reste connecté.

Détail technique complet : section 0 de `docs/notices/REPONSE_DEMANDES_MOBILES.md`.