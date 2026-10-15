# Prestige Mobile 4.2.0+14 — retours des essais du 15/10/2026

## Nouvelle interface
- **Fenêtres à la charte** : code administrateur, déconnexion, « Prévente enregistrée », emplacement, photo de
  contrôle, et toutes les fenêtres, feuilles du bas, menus et messages (plus de lavande). La fenêtre du code
  administrateur défile quand le clavier est ouvert sur petit écran.
- **Hors ligne** : passage hors ligne seulement si le catalogue est présent sur le terminal ; sinon refus expliqué
  et bouton « Télécharger le catalogue ». Fraîcheur des données dans Réglages › Hors ligne.
- **Réserve** : onglets « Manuel » (à gauche, ouvert par défaut) et « Automatique » (à droite).
- **EAN fabricant** : confirmation avant enregistrement (produit, ancien → nouvel EAN) ; Entrée / OK du scanner
  valide ; clé de contrôle fausse = avertissement et « Enregistrer quand même ».
- **Pré-vente** : nouvelle icône (chariot avec flèche), différente d'« Encaisser ».
- **Carnet / Assurance** : ouverture directe sur la recherche du client, sans affichage furtif des étapes.

## Recherche rapide
- **Analyse article** : liste par la recherche rapide (`/vente/search`), puis détail du produit choisi par
  `/info` sur son CIP exact (plus aucun `/info` pendant la frappe). Délai réel de 30 s (le message disait 10 s).
- **État de Stock** : la recherche précédente est annulée à chaque frappe ; délai de 30 s.
- Demande serveur : `docs/serveur/DEMANDE_PERFORMANCE_INFO.md` (et n° 44 de `docs/serveur/TRANSMISSION_SERVEUR_2026-10-15.md`).

## Borne et terminal de pointage
- **Sortie fiable** : cadenas visible, appui long 2 s, confirmation, code administrateur. Pour la borne :
  désépinglage, mode borne désactivé sur l'appareil, retour à l'écran de connexion.
- **Terminal de pointage** : l'appui long sur le cadenas ne fonctionnait pas (capté par l'infobulle) : corrigé.
- **Borne sans données** : la cause s'affiche (utilisateur borne non configuré, mot de passe absent ou refusé,
  serveur injoignable) ; la borne reconnecte son utilisateur après expiration ; « Tester la borne » dans ses
  réglages. À activer sur l'appareil qui sert de borne, pas sur le terminal de caisse.
- Affichage : noms sur 3 lignes en Liste rapide, compte à rebours et « TERMINÉ » toujours visibles sur Sunmi,
  plus de coupure après « B/ » ou « FL/ », aides des réglages sur plusieurs lignes.

## Tests
Nouveaux : `retours_pharmacien_test.dart` (80 tests), `recherche_rapide_info_test.dart`, `sortie_borne_test.dart`.
Toute la liste CI verte ; `flutter analyze` sans nouvelle remarque.
