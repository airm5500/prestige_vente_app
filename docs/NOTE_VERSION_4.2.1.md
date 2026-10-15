# Prestige Mobile 4.2.1+15 — tests de performance et réseau, rapport de tests de livraison

Exigence du pharmacien pour chaque livraison (les 3 applications) : tests unitaires, non-régression, e2e,
**performance**, **réseau** et ergonomie, avec un **rapport de tests** joint à l'APK.

## Corrections révélées par les nouveaux tests
- **Vente sur serveur lent (ANO-10)** : pendant la création de la vente (1er article, `POST /vente/add/vno`), le
  panier restait « vide » sans aucun indicateur pendant toute l'attente (2 à 8 s sur un réseau lent) ; le bandeau
  « Envoi au serveur… » s'affiche désormais dès le 1er article (en ligne). Aucune vente en double (contrôlé).
- **Douchette de l'accueil** : l'écart entre deux caractères d'un code lu par la douchette (400 ms au plus) se mesure
  avec `clock.now()` (paquet `clock`, déjà présent) au lieu de `DateTime.now()` : **même heure réelle sur le
  terminal**, temps simulé dans les tests. Un test (EAN-13 → fiche) échouait de temps en temps quand la machine de
  test était chargée (processus suspendu plus de 400 ms au milieu du code) : il est désormais déterministe.

## Tests ajoutés (voir test/README.md)
- `test/performance/` : démarrage → connexion, connexion → accueil A / B / C, longues listes (Recherche Article
  500 produits, 200 préventes à encaisser, Réserve 300 lignes, journal 1 000 actions), 50 lignes au panier,
  nombre de requêtes des parcours clés (recherche tapée vite, Analyse article, fiche produit, État de Stock,
  encaissement, synchro hors ligne), classement de 5 000 produits, 100 tickets ; seuils documentés.
- `test/reseau/` : serveur lent (2 / 5 / 8 s, 25 s pour `/info`), réponses tronquées et JSON invalide, coupures et
  reprise de la file hors ligne, local ↔ distant, certificat HTTPS refusé.
- Anomalie signalée (non corrigée) : **ANO-09**, lectures en double à la connexion (officine ×3, préventes,
  BL du jour, QR des modes ×2) — test sauté avec son identifiant.

## CI
Résultats de `flutter test` au format `--machine` → `tool/rapport_tests.dart` → résumé par catégorie
(`test/categories.json`) et mesures de performance dans le résumé du job, artefact `rapport-tests` à côté de l'APK.
