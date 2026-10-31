# Prestige Mobile 4.10.1+37 — retours du pharmacien du 31/10

## 1. Borne : tuiles « Catégories » coupées par le bas (corrigé)

**Constat.** L'image du pharmacien n'est pas parvenue. Les écrans de la borne ont donc été rendus en PNG avec les
vraies polices, pour chacune des 3 présentations (Vitrine, Liste rapide, Guidée), sur :
- Sunmi V2s 720×1440 et V2 Pro ;
- D3 / T2 en paysage ;
- borne verticale K2.

Résultat :
- aux réglages d'usine (densité 2, texte ×1 ou ×1,3), rien n'est coupé ;
- quand la « Taille de l'affichage » d'Android est agrandie (densité 2,5 ou 2,75 sur un V2s), ou avec le texte ×1,3,
  le **pictogramme et le libellé des tuiles « Catégories »** de l'accueil sont coupés par le bas.

La hauteur de la tuile ne dépendait que de sa largeur (rapport 1,05). Quand l'écran logique rétrécit, elle devenait
plus petite que son contenu.

**Correctif.** La hauteur de la tuile est la plus grande de deux valeurs :
- la hauteur d'avant ;
- la hauteur du pictogramme et d'une ligne de libellé, à la taille de texte de l'appareil.

À la taille d'usine, la grille est identique, ce qu'un test vérifie. Le code étant partagé, PrestigePOS 1.8.1 reçoit
la même correction.

**Signalé, non modifié** (seulement aux extrêmes, texte ×1,5 à ×2 avec une densité de 2,75) : l'en-tête fixe de
l'accueil, le panier de la présentation Guidée et la page du QR mobile money dépassent l'écran.

## 2. Fiche client : ajouter la date de naissance

Un client sans date de naissance affiche **« Ajouter »** sur sa fiche, avec le droit de saisie
`P_ORDONNANCE_CLIENT_MAJ`. Ce bouton ouvre une saisie :
- format **JJ/MM/AAAA** : chiffres seulement, les « / » sont ajoutés ;
- calendrier en secours ;
- refusées avant tout envoi : une date inexistante, une date à venir, une date avant 1900.

L'enregistrement passe par `POST v1/ordonnance-client/client/{id}/identite` (serveur a2bb8cc8 du 13/10), qui
**complète une date absente sans jamais en écraser une** (« Déjà renseigné » sinon). Ensuite :
- la fiche est relue et affiche « 02/03/1985 · 41 ans » ;
- sur un serveur sans la route : « il doit être mis à jour ».

Une date déjà renseignée s'affiche désormais en JJ/MM/AAAA, sans bouton. La **modifier** ou l'**effacer** n'est pas
possible : le serveur n'a aucune route sûre pour cela. C'est l'objet de la **demande 58**
(`docs/serveur/TRANSMISSION_SERVEUR_2026-10-15.md`).

La date n'est jamais journalisée ni gardée sur le téléphone.

## 3. Mobile Money absent à la fin de la vente : diagnostic, rien de changé

Le choix n'apparaît que si quatre conditions sont réunies :
- le réglage est coché ;
- le serveur est en ligne ;
- le serveur annonce au moins un opérateur (`GET v1/paiements-mobile/capacites`), ce qui suppose un agrégateur
  configuré sur le serveur : `PRESTIGE_PAIEMENTS_FOURNISSEUR`, l'adresse publique HTTPS et les clés, puis un
  redémarrage. Les modes Wave / Orange de la caisse ne suffisent pas ;
- sur la borne, l'utilisateur borne a un droit de clôture (règle de la 4.5.1).

L'explication à l'écran est proposée et attend une décision.

## Tests

| Fichier | Ce qu'il vérifie |
|---|---|
| `test/borne_test.dart` | Tuiles entières sur V2s, densité 2 à 2,75, texte ×1 à ×1,5, trois présentations ; hauteur inchangée à la taille d'usine. |
| `test/fiche_client_test.dart` | Contrôles de la date ; saisie au clavier ; client HTTP (AAAA-MM-JJ, « Déjà renseigné », 404, date à venir sans appel) ; écran (Ajouter, refus, affichage, consultation seule). |
| `test/fiche_naissance_e2e_test.dart` | Application entière, faux serveur avec les règles du serveur ; date jamais journalisée. |
| `test/reseau/fiche_naissance_reseau_test.dart` | Vrai HTTP : JSON exact avec la session, pas d'écrasement, coupure puis reprise. |

La suite complète reste verte.
