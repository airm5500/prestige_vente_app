# Prestige Mobile 4.10.2+38 — date de naissance modifiable (demande 58) et état du Mobile Money

## 1. Fiche client : modifier ou effacer la date de naissance

Le serveur traite la demande 58 (commit b5020735, réponse bc091bc5). Son code a été vérifié :
- `POST v1/ordonnance-client/client/{id}/identite` accepte `{naissance, remplacer: true}` ;
  - une date la **remplace** : « Date de naissance modifiée. » ;
  - une valeur vide l'**efface** : « Date de naissance effacée. » ;
- la modification vaut pour tous les types de client ;
- les refus arrivent en HTTP 200 : date impossible, à venir, plus de 130 ans, client introuvable ;
- la capacité `naissanceModifiable` figure dans `GET droits` et dans l'objet `client` du dossier.

Dans la fiche client :
- **Date présente et `naissanceModifiable` vrai** (droit de saisie) :
  - **« Modifier »** ouvre la saisie JJ/MM/AAAA (ou le calendrier), pré-remplie avec la date actuelle. Contrôles locaux :
    date inexistante, à venir, avant 1900, plus de 130 ans ;
  - **« Effacer »** demande une confirmation.
- Après chaque réussite, le message du serveur s'affiche et la fiche est relue.
- **Capacité fausse ou absente** (serveur sans la demande 58) : ni « Modifier » ni « Effacer ».
- Le bouton **« Ajouter »** d'une date absente ne change pas (4.10.1).
- La date n'est jamais journalisée ni gardée sur le téléphone.

## 2. Mobile Money : ligne d'état sous l'option (accord du pharmacien)

Sous « Proposer le paiement par QR mobile money » (Réglages › Paiements), une ligne dit ce qui empêche le paiement
d'être proposé. Elle applique **les mêmes conditions que la borne et l'encaissement** :

| Situation | Message |
|---|---|
| Option décochée | aucune ligne |
| Serveur injoignable | « Serveur injoignable : impossible de vérifier. » |
| Serveur sans module (404) | « Serveur sans module Mobile Money (version ancienne). » |
| Aucun opérateur annoncé | « Mobile Money activé, mais le serveur Prestige n'a pas de compte de paiement configuré (agrégateur). Les modes Wave / Orange de la caisse ne suffisent pas : faites configurer le compte de paiement du serveur, puis redémarrez-le. » |
| Pas de droit de clôture | « Mobile Money activé, mais le compte (de la borne) « X » n'a pas le droit de clôturer : donnez-lui P_SM_CLOTURER_CAISSE (ou P_SM_DEPOT_EXTENSION, P_BT_MODIFICATION_DE_VENTE). » |
| Tout bon | « Proposé au client : Orange Money, Wave. » |

- Il y a **deux lignes** :
  - l'encaissement de cet appareil, avec le compte connecté ;
  - la borne libre-service, si elle est configurée. Pour la vérifier, une connexion d'essai de l'utilisateur borne se
    fait à part, sans toucher la session de l'appareil, puis est fermée.
- Si les deux obstacles existent à la fois, les deux sont dits.
- Les capacités sont relues à chaque ouverture, à chaque changement de l'option et par « Vérifier à nouveau ».
- **« Tester la borne »** gagne une étape « Module Mobile Money » avec le même message.
- **Jamais affiché aux clients** : l'écran de la borne et son parcours de vente ne changent pas.
- Aucun nom de variable du serveur dans les messages.

## 3. Serveur : routes modifiées depuis 31622a33

Les routes utilisées par Prestige Mobile, PrestigePOS et Prestige Pointage ont été comparées au code du serveur.
Aucun changement cassant (détail dans le rapport du 31/10) :
- **`etat-control-bon/list`** : la recherche devient « contient ». En ligne, plus de résultats ; la copie hors ligne
  garde « commence par ».
- **`client/tiers-payants/*`** : recherche « contient », les noms qui commencent par la saisie en tête.
- **Création de client** : un taux supérieur à 100 % est refusé, avec le message du serveur.
- **`ventestats/{id}`** : nouveau champ `differe`, sans effet sur l'application.

## Tests

| Fichier | Ce qu'il vérifie |
|---|---|
| `test/fiche_client_test.dart` | Unitaires et écran : modifier, effacer (confirmation, annulation), refus, capacité vraie, fausse ou absente, plus de 130 ans. |
| `test/fiche_naissance_e2e_test.dart` | Application entière : modifier puis effacer, refus du serveur, serveur sans la demande 58. |
| `test/reseau/fiche_naissance_reseau_test.dart` | Vrai HTTP : corps exacts, capacité, refus. |
| `test/mobile_money_etat_test.dart` | Chaque état et sa règle. |
| `test/mobile_money_etat_e2e_test.dart` | Application entière : chaque état, borne configurée, capacités relues, Sunmi V2s texte ×1,3. |
| `test/reseau/mobile_money_etat_reseau_test.dart` | Vrai HTTP : borne, étape de « Tester la borne », session d'essai fermée, coupure, mot de passe faux. |

La suite complète reste verte.
